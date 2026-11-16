/*! @file
	@brief 导入 Windows 版的设置（计划第 35 步）的测试

	Mac 版可以导入 Windows 版的 sakura.ini（sakura::core::ImportSettings）。这里确认：
	- 导入后重新启动，共通設定、キー割り当て、タイプ別設定、メインメニュー 都与 Windows 版相同，
	  再写出的 sakura.ini 除历史的几节以外与导入的文件逐行相同（什么也没有丢）
	- 历史（[MRU]、[Keys]、[Grep]、[Folders]、[Cmd]）保留这台 Mac 的
	- Windows 的路径、DLL 名原样保留
	- 导入前的设置有备份；重新启动之前结束时不写出设置（不会盖掉导入的文件）
	- 旧版本的 Shift_JIS 的 sakura.ini 也能导入；不是设置文件、没有的文件不导入，设置不变
*/
/*
	Copyright (C) 2026, Sakura Editor Organization

	SPDX-License-Identifier: Zlib
*/
#include "pch.h"

#include "sakura_core/SakuraCore.h"

#include "env/CDocTypeManager.h"
#include "env/DLLSHAREDATA.h"
#include "util/file.h"

#include <algorithm>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <map>
#include <string>

#include <unistd.h>

using namespace sakura::core;

namespace {

namespace fs = std::filesystem;

std::string ReadAll(const fs::path& path)
{
	std::ifstream in(path, std::ios::binary);
	return std::string(std::istreambuf_iterator<char>(in), std::istreambuf_iterator<char>());
}

void WriteAll(const fs::path& path, std::string_view data)
{
	fs::create_directories(path.parent_path());
	std::ofstream out(path, std::ios::binary);
	out.write(data.data(), std::streamsize(data.size()));
}

//! text 里的 from 全部换成 to。返回替换的次数
int ReplaceAll(std::string& text, std::string_view from, std::string_view to)
{
	int n = 0;
	for (size_t pos = 0; (pos = text.find(from, pos)) != std::string::npos; pos += to.size(), ++n) {
		text.replace(pos, from.size(), to);
	}
	return n;
}

//! section 这一节里的第一个 from 换成 to。换了返回 true
bool ReplaceInSection(std::string& text, std::string_view section, std::string_view from, std::string_view to)
{
	const auto start = text.find("\r\n[" + std::string(section) + "]\r\n");
	if (start == std::string::npos) return false;
	const auto end = text.find("\r\n[", start + 3);
	const auto pos = text.find(from, start);
	if (pos == std::string::npos || (end != std::string::npos && pos > end)) return false;
	text.replace(pos, from.size(), to);
	return true;
}

//! ini 按节分开（节名 → 那一节的内容）
std::map<std::string, std::string> Sections(const std::string& ini)
{
	std::map<std::string, std::string> r;
	std::string name;
	for (size_t p = 0, q; p < ini.size(); p = q + 2) {
		q = ini.find("\r\n", p);
		if (q == std::string::npos) q = ini.size();
		const auto line = ini.substr(p, q - p);
		if (line.size() > 2 && line.front() == '[' && line.back() == ']') {
			name = line.substr(1, line.size() - 2);
			r[name];
		} else if (!name.empty() && !line.empty()) {
			r[name] += line + "\n";
		}
	}
	return r;
}

std::string U8(const char8_t* s) { return reinterpret_cast<const char*>(s); }

fs::path IniPath() { return fs::path(SettingsFilePath()); }
fs::path BackupPath() { return fs::path(SettingsBackupPath()); }

//! 保留 Mac 的历史的几节
bool IsHistorySection(const std::string& name)
{
	return name == "MRU" || name == "Keys" || name == "Grep" || name == "Folders" || name == "Cmd";
}

const STypeConfigMini* TypeMini(int index)
{
	const STypeConfigMini* mini = nullptr;
	CDocTypeManager().GetTypeConfigMini(CTypeConfig(index), &mini);
	return mini;
}

class MacImportTest : public ::testing::Test {
protected:
	void SetUp() override
	{
		RemoveIniFolder();
		m_dir = fs::temp_directory_path() / ("sakura-import-test-" + std::to_string(::getpid()));
		fs::create_directories(m_dir);
	}
	void TearDown() override
	{
		Shutdown(false);
		RemoveIniFolder();
		std::error_code ec;
		fs::remove_all(m_dir, ec);
	}
	static void RemoveIniFolder()
	{
		std::error_code ec;
		fs::remove_all(GetIniFileName().parent_path(), ec);
	}

	/*!
		Windows 版的 sakura.ini：启动两次之后的设置文件（第 21 步：这以后读入再写出逐字节相同），
		改成在 Windows 上改过设置的样子。做完以后 Mac 的设置文件删掉（没有启动）
	*/
	static std::string MakeWindowsIni()
	{
		EXPECT_TRUE(Startup());
		Shutdown(true);
		EXPECT_TRUE(Startup());
		Shutdown(true);
		std::string ini = ReadAll(IniPath());
		RemoveIniFolder();

		// キー割り当て：F8 换成「挿入／上書きモード切り替え」（默认是コピー）
		EXPECT_EQ(1, ReplaceAll(ini, "KeyBind[018]=0077,30602,", "KeyBind[018]=0077,31001,"));
		// タイプ別設定：テキスト 加上扩展名 memo，改文字的颜色
		EXPECT_TRUE(ReplaceInSection(ini, "Types(1)", "szTypeExts=txt,log,1st,err,ps\r\n", "szTypeExts=txt,log,1st,err,ps,memo\r\n"));
		EXPECT_TRUE(ReplaceInSection(ini, "Types(1)", "C[TXT]=1,0,000000,", "C[TXT]=1,0,123456,"));
		// メインメニュー：新規作成 的快捷字母换成 X，「開く」和它换位置
		EXPECT_TRUE(ReplaceInSection(ini, "MainMenu", "MM[001]=1,1,30101,N,\r\n", "MM[001]=1,1,30102,O,\r\n"));
		EXPECT_TRUE(ReplaceInSection(ini, "MainMenu", "MM[003]=1,1,30102,O,\r\n", "MM[003]=1,1,30101,X,\r\n"));
		// 共通設定：Windows 的路径、DLL
		EXPECT_EQ(1, ReplaceAll(ini, "szBackUpFolder=\\\r\n", U8(u8"szBackUpFolder=C:\\Users\\さくら\\Backup\\\r\n")));
		EXPECT_EQ(1, ReplaceAll(ini, "szRegexpLib=\r\n", "szRegexpLib=bregonig.dll\r\n"));
		EXPECT_EQ(1, ReplaceAll(ini, "szMigemoDll=\r\n", U8(u8"szMigemoDll=C:\\Program Files\\sakura\\migemo.dll\r\n")));
		// 历史：Windows 的查找历史、マクロ的文件夹
		EXPECT_TRUE(ReplaceInSection(ini, "Keys", "_SEARCHKEY_Counts=0\r\n", "SEARCHKEY[00]=windows-key\r\n_SEARCHKEY_Counts=1\r\n"));
		const std::string macFolder = GetIniFileName().parent_path().string() + "/";
		EXPECT_EQ(1, ReplaceAll(ini, "szMACROFOLDER=" + macFolder + "\r\n", U8(u8"szMACROFOLDER=C:\\Users\\さくら\\AppData\\Roaming\\sakura\\\r\n")));
		return ini;
	}

	fs::path m_dir;
};

} // namespace

// 导入 → 重新启动：设置与 Windows 版相同，历史是 Mac 的
TEST_F(MacImportTest, ImportedSettingsAreUsedAfterRestart)
{
	const std::string windowsIni = MakeWindowsIni();
	const auto source = m_dir / "sakura.ini";
	WriteAll(source, windowsIni);

	// Mac 这边：默认设置，查找历史里有 mac-key
	ASSERT_TRUE(Startup());
	AddSearchKey(u"mac-key");
	const FunctionCode f8Before = FunctionForKey(0x77, 0);
	EXPECT_NE(31001, f8Before);

	ASSERT_EQ(ImportResult::Imported, CheckSettingsFile(source.u16string()));
	ASSERT_EQ(ImportResult::Imported, ImportSettings(source.u16string()));
	EXPECT_TRUE(IsSettingsImportPending());
	// 重新启动之前还是原来的设置（与 Windows 版换掉 sakura.ini 相同）
	EXPECT_EQ(f8Before, FunctionForKey(0x77, 0));

	// 结束（写出设置）→ 启动
	Shutdown(true);
	ASSERT_TRUE(Startup());
	EXPECT_FALSE(IsSettingsImportPending());

	// キー割り当て、タイプ別設定、メインメニュー、共通設定
	EXPECT_EQ(31001, FunctionForKey(0x77, 0));
	EXPECT_EQ(1, CDocTypeManager().GetDocumentTypeOfPath(LTEXT("/tmp/note.memo")).GetIndex());
	const auto menu = MainMenu();
	ASSERT_GT(menu.size(), 3u);
	EXPECT_EQ(30102, menu[1].code);
	EXPECT_EQ(30101, menu[3].code);
	EXPECT_EQ(Text(u"X"), menu[3].accessKey);
	const auto& common = GetDllShareData().m_Common;
	EXPECT_STREQ(LTEXT("C:\\Users\\さくら\\Backup\\"), common.m_sBackup.m_szBackUpFolder.c_str());
	EXPECT_STREQ(LTEXT("bregonig.dll"), common.m_sSearch.m_szRegexpLib);
	EXPECT_STREQ(LTEXT("C:\\Program Files\\sakura\\migemo.dll"), common.m_sHelper.m_szMigemoDll.c_str());

	// 历史是 Mac 的
	EXPECT_EQ(std::vector<Text>{ u"mac-key" }, SearchKeyHistory());
	EXPECT_STREQ(sakura::path_to_wstring(GetIniFileName().parent_path()).append(LTEXT("/")).c_str(), common.m_sMacro.m_szMACROFOLDER);

	// 再写出：历史以外的节与导入的文件逐行相同
	Shutdown(true);
	const auto imported = Sections(windowsIni);
	const auto saved = Sections(ReadAll(IniPath()));
	for (const auto& [name, body] : imported) {
		if (IsHistorySection(name)) continue;
		auto it = saved.find(name);
		ASSERT_NE(saved.end(), it) << name;
		EXPECT_EQ(body, it->second) << "[" << name << "]";
	}
	for (const auto& [name, body] : saved) {
		EXPECT_TRUE(imported.contains(name)) << name;
	}
	EXPECT_NE(std::string::npos, saved.at("Keys").find("SEARCHKEY[00]=mac-key\n"));
	EXPECT_EQ(std::string::npos, saved.at("Keys").find("windows-key"));
}

// 导入前的设置有备份；重新启动之前结束时不写出（导入的文件留着）
TEST_F(MacImportTest, BackupAndNoSaveBeforeRestart)
{
	const std::string windowsIni = MakeWindowsIni();
	const auto source = m_dir / "sakura.ini";
	WriteAll(source, windowsIni);

	ASSERT_TRUE(Startup());
	AddSearchKey(u"before-import");
	ASSERT_EQ(ImportResult::Imported, ImportSettings(source.u16string()));

	// 备份：导入前的 Mac 的设置（现在的设置写出以后复制的，有刚登记的历史）
	const auto backup = ReadAll(BackupPath());
	EXPECT_NE(std::string::npos, backup.find("SEARCHKEY[00]=before-import\r\n"));
	EXPECT_NE(std::string::npos, backup.find("KeyBind[018]=0077,30602,"));

	// 导入以后、重新启动之前登记的历史不保存：结束时不写出设置，导入的文件不变（与 Windows 版换掉 ini 后相同）
	AddSearchKey(u"after-import");
	const auto afterImport = ReadAll(IniPath());
	Shutdown(true);
	EXPECT_EQ(afterImport, ReadAll(IniPath()));
	EXPECT_NE(std::string::npos, afterImport.find("KeyBind[018]=0077,31001,"));
	EXPECT_NE(std::string::npos, afterImport.find("SEARCHKEY[00]=before-import\r\n"));

	// 格式与 Windows 版相同：UTF-8 带 BOM，换行是 CRLF
	EXPECT_EQ(0u, afterImport.find("\xEF\xBB\xBF"));
	EXPECT_NE(std::string::npos, afterImport.find(U8(u8"; sakura.ini テキストエディタ設定ファイル\r\n")));
}

// 旧版本的 sakura.ini（Shift_JIS、没有 BOM、只有一部分设置）：有的设置读入，没有的是默认值
TEST_F(MacImportTest, OldShiftJisIni)
{
	const auto source = m_dir / "old.ini";
	// テキスト(旧) 的 Shift_JIS
	WriteAll(source,
		"[Common]\r\nnCaretType=1\r\n"
		"[Other]\r\nnTypesCount=17\r\nszVersion=1.6.6.0\r\n"
		"[Types(1)]\r\nszTypeName=\x83\x65\x83\x4C\x83\x58\x83\x67(\x8B\x8C)\r\nszTypeExts=txt,old\r\n");
	ASSERT_TRUE(Startup());
	ASSERT_EQ(ImportResult::Imported, CheckSettingsFile(source.u16string()));
	ASSERT_EQ(ImportResult::Imported, ImportSettings(source.u16string()));
	Shutdown(true);

	ASSERT_TRUE(Startup());
	const auto& common = GetDllShareData().m_Common;
	EXPECT_EQ(1, common.m_sGeneral.m_nCaretType);
	ASSERT_NE(nullptr, TypeMini(1));
	EXPECT_STREQ(LTEXT("テキスト(旧)"), TypeMini(1)->m_szTypeName);
	EXPECT_EQ(1, CDocTypeManager().GetDocumentTypeOfPath(LTEXT("/tmp/a.old")).GetIndex());
	// ini 里没有的：默认值（C/C++ 的类型、默认的按键分配）
	ASSERT_NE(nullptr, TypeMini(2));
	EXPECT_STREQ(LTEXT("C/C++"), TypeMini(2)->m_szTypeName);
	EXPECT_NE(0, FunctionForKey(0x77, 0));
	// 版本较旧：与原版相同，读入时做 .bak 备份
	auto bak = GetIniFileName();
	bak += ".bak";
	EXPECT_TRUE(fexist(bak));
}

// 不是设置文件、没有的文件：不导入，设置文件不变
TEST_F(MacImportTest, RejectsNonSettingsFiles)
{
	ASSERT_TRUE(Startup());
	Shutdown(true);
	ASSERT_TRUE(Startup());
	const auto before = ReadAll(IniPath());

	const auto text = m_dir / "readme.txt";
	WriteAll(text, "hello\r\n[Common]\r\n");
	const auto typeExport = m_dir / "type.ini";	// タイプ別設定のエクスポート（[Common] がない）
	WriteAll(typeExport, "\xEF\xBB\xBF[SakuraType]\r\nszTypeName=Text\r\n");
	const auto missing = m_dir / "missing.ini";

	EXPECT_EQ(ImportResult::NotSettingsFile, CheckSettingsFile(text.u16string()));
	EXPECT_EQ(ImportResult::NotSettingsFile, ImportSettings(text.u16string()));
	EXPECT_EQ(ImportResult::NotSettingsFile, ImportSettings(typeExport.u16string()));
	EXPECT_EQ(ImportResult::ReadFailed, CheckSettingsFile(missing.u16string()));
	EXPECT_EQ(ImportResult::ReadFailed, ImportSettings(missing.u16string()));
	EXPECT_EQ(ImportResult::ReadFailed, ImportSettings(m_dir.u16string()));	// 文件夹
	EXPECT_EQ(ImportResult::ReadFailed, ImportSettings(Text()));

	EXPECT_FALSE(IsSettingsImportPending());
	EXPECT_EQ(before, ReadAll(IniPath()));
	EXPECT_FALSE(fexist(BackupPath()));
}

// 自己的 sakura.ini 也可以导入（读入和写出是同一个文件）
TEST_F(MacImportTest, ImportOwnSettingsFile)
{
	ASSERT_TRUE(Startup());
	Shutdown(true);
	ASSERT_TRUE(Startup());
	Shutdown(true);
	ASSERT_TRUE(Startup());
	const auto before = ReadAll(IniPath());
	ASSERT_EQ(ImportResult::Imported, ImportSettings(IniPath().u16string()));
	EXPECT_EQ(before, ReadAll(IniPath()));
	EXPECT_EQ(before, ReadAll(BackupPath()));
}
