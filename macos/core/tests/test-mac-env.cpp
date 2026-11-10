/*! @file
	@brief 设置模块 env（计划第 21 步）的 Mac 版测试

	- sakura.ini 的往返：默认设置写出 → 读入 → 再写出，内容逐字节相同；
	  带有 Windows 版特有的值（C:\ 的路径、Windows 的字体名）的 ini 读入后再写出，也逐字节相同
	- 共享数据（CShareData::InitShareData）的默认值、类型别设置的读写（CDocTypeManager）
	- util/file 的路径函数（Mac 版的分隔符是 '/'）、CTextInputStream_AbsIni
	- 平台层：swscanf_s、_wsplitpath_s、PathMatchSpec、资源（MainMenu.ini）、命名互斥锁
	- C/Migemo（原版 test-extmodules.cpp 的 CMigemoTest）、正则库的初始化（InitRegexp）

	原版的 test-file.cpp 大部分测试 Windows 的文件 API 和路径（C:\、MockKernel32），不在 Mac 上编译；
	其中与平台无关的项目在这里按 Mac 的路径重写。
	测试运行时 HOME 是临时文件夹（mac-test-home.cpp），不会碰到真正的设置文件。
*/
/*
	Copyright (C) 2026, Sakura Editor Organization

	SPDX-License-Identifier: Zlib
*/
#include "pch.h"

#include "_main/CMutex.h"
#include "env/CDocTypeManager.h"
#include "env/CShareData.h"
#include "env/CShareData_IO.h"
#include "env/ShareDataTestSuite.hpp"
#include "extmodule/CBregexp.h"
#include "extmodule/CMigemo.h"
#include "io/CTextStream.h"
#include "util/file.h"
#include "sakura_rc.h"

#include <chrono>
#include <fstream>
#include <future>
#include <iterator>
#include <string>
#include <thread>

// env/CShareData_IO.cpp（ヘッダーには宣言がない）
std::filesystem::path GetIniFileNameForIO(bool bWrite);

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

//! 两个文本按行比较，返回不同的行（最多 10 处）。相同时返回空字符串
std::string DiffLines(const std::string& a, const std::string& b)
{
	auto split = [](const std::string& t) {
		std::vector<std::string> v;
		size_t p = 0;
		for (size_t q; (q = t.find('\n', p)) != std::string::npos; p = q + 1) v.push_back(t.substr(p, q - p));
		v.push_back(t.substr(p));
		return v;
	};
	const auto la = split(a), lb = split(b);
	std::string out;
	int n = 0;
	for (size_t i = 0; i < std::max(la.size(), lb.size()) && n < 10; ++i) {
		const std::string x = i < la.size() ? la[i] : "<none>";
		const std::string y = i < lb.size() ? lb[i] : "<none>";
		if (x != y) {
			out += "line " + std::to_string(i + 1) + ":\n  - " + x + "\n  + " + y + "\n";
			++n;
		}
	}
	return out;
}

std::string U8(const char8_t* s) { return reinterpret_cast<const char*>(s); }

//! 每个测试建立新的共通设置，删除设置文件
class MacEnvTest : public ::testing::Test, public env::ShareDataTestSuite {
protected:
	void SetUp() override
	{
		RemoveIniFolder();
		SetUpShareData();
	}
	void TearDown() override
	{
		TearDownShareData();
		RemoveIniFolder();
	}
	static void RemoveIniFolder()
	{
		std::error_code ec;
		fs::remove_all(GetIniFileName().parent_path(), ec);
	}
	//! 共通设置重新建立（与重新启动编辑器相同）
	static void Restart()
	{
		TearDownShareData();
		SetUpShareData();
	}
};

// ---------------------------------------------------------------------------
// sakura.ini 的往返
// ---------------------------------------------------------------------------

TEST_F(MacEnvTest, IniLocationIsApplicationSupport)
{
	const char* home = std::getenv("HOME");
	ASSERT_NE(nullptr, home);
	EXPECT_EQ(fs::path(home) / "Library" / "Application Support" / "sakura" / "sakura.ini", GetIniFileName());
	// Mac 版没有“exe 旁边的 ini”，读写都用这个位置
	EXPECT_EQ(GetIniFileName(), GetIniFileNameForIO(false));
	EXPECT_EQ(GetIniFileName(), GetIniFileNameForIO(true));
	auto& share = GetDllShareData();
	EXPECT_STREQ(sakura::path_to_wstring(GetIniFileName()).c_str(), share.m_szIniFile.c_str());
}

/*!
	与原版 CControlProcess::InitializeProcess 相同的启动顺序：
	建立共通设置 → 读入设置文件 → 读不到时写出默认设置 → 刷新字符串资源（键名等）
*/
void StartUpLikeControlProcess()
{
	if (!CShareData_IO::LoadShareData()) {
		CShareData_IO::SaveShareData();
	}
	CShareData::getInstance()->RefreshString();
}

TEST_F(MacEnvTest, IniRoundTripIsByteIdentical)
{
	// 第一次启动：没有设置文件，写出默认设置
	StartUpLikeControlProcess();
	const auto firstRun = ReadAll(GetIniFileName());
	ASSERT_FALSE(firstRun.empty());

	// 与 Windows 版相同的格式：UTF-8 带 BOM，换行是 CRLF
	EXPECT_EQ(0u, firstRun.find("\xEF\xBB\xBF"));
	EXPECT_NE(std::string::npos, firstRun.find(U8(u8"; sakura.ini テキストエディタ設定ファイル\r\n")));
	{
		std::string withoutCrLf = firstRun;
		ReplaceAll(withoutCrLf, "\r\n", "");
		EXPECT_EQ(std::string::npos, withoutCrLf.find('\n')) << "all line breaks are CRLF";
	}
	for (const char* section : { "[Common]\r\n", "[Toolbar]\r\n", "[CustMenu]\r\n", "[Font]\r\n", "[KeyBind]\r\n", "[Print]\r\n", "[Other]\r\n", "[Types(0)]\r\n", "[MainMenu]\r\n" }) {
		EXPECT_NE(std::string::npos, firstRun.find(section)) << section;
	}
	EXPECT_NE(std::string::npos, firstRun.find(U8(u8"KeyBind[000]=0100,30400,30400,30400,30400,30400,30400,30400,30400,ダブルクリック\r\n")));
	EXPECT_NE(std::string::npos, firstRun.find(U8(u8"lfFaceName=ＭＳ ゴシック\r\n")));

	// 编辑器结束时写出
	CShareData_IO::SaveShareData();
	const auto exitSave = ReadAll(GetIniFileName());
	// 与原版相同：第一次启动时写出的文件里，字符串资源的键名还没刷新（RefreshString 在写出之后），
	// 结束时写出的文件才有这几个键名。除此以外完全相同
	{
		std::string expected = firstRun;
		EXPECT_EQ(1, ReplaceAll(expected, "KeyBind[087]=00de,0,0,30621,0,0,0,0,0,\r\n", U8(u8"KeyBind[087]=00de,0,0,30621,0,0,0,0,0,^(英語')\r\n")));
		EXPECT_EQ(1, ReplaceAll(expected, "KeyBind[089]=00c0,0,0,30610,0,0,0,0,0,\r\n", U8(u8"KeyBind[089]=00c0,0,0,30610,0,0,0,0,0,@(英語`)\r\n")));
		EXPECT_EQ(1, ReplaceAll(expected, "KeyBind[099]=005d,31580,31580,31580,31580,31580,31580,31580,31580,\r\n", U8(u8"KeyBind[099]=005d,31580,31580,31580,31580,31580,31580,31580,31580,アプリキー\r\n")));
		EXPECT_EQ("", DiffLines(expected, exitSave));
	}

	// 第二次启动：读入时 [Font] 的磅数（nPointSize=0）由像素数算出（原版 ShareData_IO_LogFont 的“初回”处理），
	// 结束时写出 98（ＭＳ ゴシック 13 像素 = 9.8 磅，96 DPI）。除此以外完全相同
	Restart();
	StartUpLikeControlProcess();
	CShareData_IO::SaveShareData();
	const auto steady = ReadAll(GetIniFileName());
	{
		std::string expected = exitSave;
		const auto font = expected.find("\r\n[Font]\r\n");
		ASSERT_NE(std::string::npos, font);
		const auto point = expected.find("\r\nnPointSize=0\r\n", font);
		ASSERT_NE(std::string::npos, point);
		expected.replace(point, std::strlen("\r\nnPointSize=0"), "\r\nnPointSize=98");
		EXPECT_EQ("", DiffLines(expected, steady));
	}

	// 之后读入再写出，内容逐字节相同（启动、结束重复几次都一样）
	for (int i = 0; i < 2; ++i) {
		Restart();
		StartUpLikeControlProcess();
		CShareData_IO::SaveShareData();
		EXPECT_EQ("", DiffLines(steady, ReadAll(GetIniFileName()))) << "restart " << i;
	}
	// 版本相同，不做备份
	auto bak = GetIniFileName();
	bak += ".bak";
	EXPECT_FALSE(fexist(bak));
}

TEST_F(MacEnvTest, WindowsSpecificValuesSurviveRoundTrip)
{
	// 启动两次之后的设置文件（见上面的测试）
	StartUpLikeControlProcess();
	CShareData_IO::SaveShareData();
	Restart();
	StartUpLikeControlProcess();
	CShareData_IO::SaveShareData();
	std::string ini = ReadAll(GetIniFileName());

	// 改成 Windows 版写出的值：C:\ 的路径、Windows 的界面字体、转义的分隔符
	const std::string macFolder = GetIniFileName().parent_path().string() + "/";
	ASSERT_EQ(2, ReplaceAll(ini, "=" + macFolder + "\r\n", U8(u8"=C:\\Users\\さくら\\AppData\\Roaming\\sakura\\\r\n")));
	ASSERT_LT(0, ReplaceAll(ini, "FaceName=Hiragino Sans\r\n", "FaceName=Yu Gothic UI\r\n"));
	ASSERT_EQ(1, ReplaceAll(ini, "szRegexpLib=\r\n", "szRegexpLib=bregonig.dll\r\n"));
	ASSERT_EQ(1, ReplaceAll(ini, "szMigemoDll=\r\n", U8(u8"szMigemoDll=C:\\Program Files\\sakura\\migemo.dll\r\n")));
	WriteAll(GetIniFileName(), ini);

	Restart();
	StartUpLikeControlProcess();
	const auto& common = GetDllShareData().m_Common;
	EXPECT_STREQ(LTEXT("bregonig.dll"), common.m_sSearch.m_szRegexpLib);
	EXPECT_STREQ(LTEXT("C:\\Program Files\\sakura\\migemo.dll"), common.m_sHelper.m_szMigemoDll.c_str());
	EXPECT_STREQ(LTEXT("C:\\Users\\さくら\\AppData\\Roaming\\sakura\\"), common.m_sMacro.m_szMACROFOLDER);

	CShareData_IO::SaveShareData();
	EXPECT_EQ("", DiffLines(ini, ReadAll(GetIniFileName())));
}

TEST_F(MacEnvTest, OlderIniVersionMakesBackup)
{
	// 原版 test-cprofile.cpp 的 ShareData_IO_2：版本较旧时先做备份
	WriteAll(GetIniFileName(), "\xEF\xBB\xBF[Other]\r\nszVersion=2.0.0.0\r\n");
	EXPECT_TRUE(CShareData_IO::LoadShareData());
	auto bak = GetIniFileName();
	bak += ".bak";
	EXPECT_EQ("\xEF\xBB\xBF[Other]\r\nszVersion=2.0.0.0\r\n", ReadAll(bak));
}

// ---------------------------------------------------------------------------
// 共享数据的默认值、类型别设置
// ---------------------------------------------------------------------------

TEST_F(MacEnvTest, InitShareDataDefaults)
{
	const auto& share = GetDllShareData();
	EXPECT_NE(0u, share.m_sVersion.m_dwProductVersionMS);
	// 内嵌的 MainMenu.ini（资源 IDR_MENU1）读入了主菜单
	EXPECT_LT(0, share.m_Common.m_sMainMenu.m_nMainMenuNum);
	// 按键分配（func/CKeyBind.cpp 的 InitKeyAssign）
	EXPECT_LT(0, share.m_Common.m_sKeyBind.m_nKeyNameArrNum);
	// 打印设置（print/CPrint.cpp 的 SettingInitialize）
	EXPECT_STREQ(LTEXT("ＭＳ 明朝"), share.m_PrintSettingArr[0].m_szPrintFontFaceHan);
	EXPECT_EQ(DMPAPER_A4, share.m_PrintSettingArr[0].m_nPrintPaperSize);
	// 类型别设置
	EXPECT_LT(1, share.m_nTypesCount);
	EXPECT_STREQ(LTEXT("テキスト"), share.m_TypeMini[1].m_szTypeName);
}

TEST_F(MacEnvTest, DocTypeManagerGetSetTypeConfig)
{
	CDocTypeManager mgr;
	const auto cpp = mgr.GetDocumentTypeOfPath(LTEXT("/Users/sakura/src/main.cpp"));
	ASSERT_LT(0, cpp.GetIndex());
	STypeConfig type{};
	ASSERT_TRUE(mgr.GetTypeConfig(cpp, type));
	EXPECT_STREQ(LTEXT("C/C++"), type.m_szTypeName);

	::wcscpy_s(type.m_szTypeExts, LTEXT("cpp,mm"));
	EXPECT_TRUE(mgr.SetTypeConfig(cpp, type));
	EXPECT_EQ(cpp.GetIndex(), mgr.GetDocumentTypeOfPath(LTEXT("/tmp/x.mm")).GetIndex());
	const STypeConfigMini* mini = nullptr;
	ASSERT_TRUE(mgr.GetTypeConfigMini(cpp, &mini));
	EXPECT_STREQ(LTEXT("cpp,mm"), mini->m_szTypeExts);

	// ワイルドカード（PathMatchSpec）
	EXPECT_TRUE(CDocTypeManager::IsFileNameMatch(LTEXT("*.txt;Makefile*"), LTEXT("Makefile.am")));
	EXPECT_FALSE(CDocTypeManager::IsFileNameMatch(LTEXT("*.txt"), LTEXT("a.md")));
}

// ---------------------------------------------------------------------------
// util/file 的路径函数（Mac 的路径）
// ---------------------------------------------------------------------------

TEST(MacFileUtil, PathPieces)
{
	EXPECT_STREQ(LTEXT("main.cpp"), GetFileTitlePointer(LTEXT("/Users/sakura/main.cpp")));
	EXPECT_STREQ(LTEXT("main.cpp"), GetFileTitlePointer(LTEXT("main.cpp")));
	EXPECT_EQ(3, CalcDirectoryDepth(LTEXT("/Users/sakura/src/main.cpp")));

	WCHAR folder[_MAX_PATH]{}, file[_MAX_PATH]{};
	SplitPath_FolderAndFile(LTEXT("/Users/sakura/main.cpp"), folder, file);
	EXPECT_STREQ(LTEXT("/Users/sakura"), folder);
	EXPECT_STREQ(LTEXT("main.cpp"), file);
	SplitPath_FolderAndFile(LTEXT("/main.cpp"), folder, file);
	EXPECT_STREQ(LTEXT("/"), folder);

	WCHAR path[_MAX_PATH] = LTEXT("/Users/sakura/");
	CutLastYenFromDirectoryPath(path);
	EXPECT_STREQ(LTEXT("/Users/sakura"), path);
	AddLastYenFromDirectoryPath(path);
	EXPECT_STREQ(LTEXT("/Users/sakura/"), path);
	WCHAR root[_MAX_PATH] = LTEXT("/");
	CutLastYenFromDirectoryPath(root);
	EXPECT_STREQ(LTEXT("/"), root);
	EXPECT_EQ(sakura::wstring(LTEXT("a/b/")), AddLastYenPath(LTEXT("a/b")));

	EXPECT_TRUE(CheckEXT(LTEXT("/Users/sakura/readme.TXT"), LTEXT("txt")));
	EXPECT_FALSE(CheckEXT(LTEXT("/Users/sakura.txt/readme"), LTEXT("txt")));

	EXPECT_TRUE(_IS_REL_PATH(LTEXT("dict")));
	EXPECT_FALSE(_IS_REL_PATH(LTEXT("/Users/sakura/dict")));
}

TEST(MacFileUtil, InvalidFilenameChars)
{
	// Windows 版と同じ判定（Mac でも Windows と共有するファイル名を作らない）
	EXPECT_FALSE(IsInvalidFilenameChars(LTEXT("test.txt")));
	EXPECT_TRUE(IsInvalidFilenameChars(LTEXT("test?.txt")));
	EXPECT_TRUE(IsInvalidFilenameChars(LTEXT("a|b")));
}

TEST(MacFileUtil, FileMatchScoreSepExt)
{
	EXPECT_EQ(8, FileMatchScoreSepExt(LTEXT("/tmp/TEST.TXT"), LTEXT("/tmp/test.txt")));
	EXPECT_EQ(6, FileMatchScoreSepExt(LTEXT("/tmp/TEST.TXT"), LTEXT("/tmp/test.tst")));	// "test" + ".t"
	EXPECT_EQ(8, FileMatchScoreSepExt(LTEXT("/a/TEST.TXT"), LTEXT("/b/test.txt")));
}

TEST(MacFileUtil, ExistsTimestampAndTempFile)
{
	const auto temp = GetTempFilePath(LTEXT("skr"));
	ASSERT_TRUE(fexist(temp));
	EXPECT_EQ(".tmp", temp.extension().string());
	EXPECT_TRUE(IsFileExists(sakura::path_to_wstring(temp).c_str(), true));
	EXPECT_FALSE(IsDirectory(sakura::path_to_wstring(temp).c_str()));
	EXPECT_TRUE(IsDirectory(sakura::path_to_wstring(temp.parent_path()).c_str()));

	// 更新日時（FILETIME、1601 年基準）
	fs::last_write_time(temp, fs::file_time_type::clock::now());
	CFileTime ft;
	ASSERT_TRUE(GetLastWriteTimestamp(sakura::path_to_wstring(temp), &ft));
	const auto& st = ft.GetSYSTEMTIME();
	EXPECT_LE(2026, st.wYear);
	fs::remove(temp);
	EXPECT_FALSE(GetLastWriteTimestamp(sakura::path_to_wstring(temp), &ft));
}

TEST_F(MacEnvTest, InidirAndAbsIniStream)
{
	const auto iniDir = GetIniFileName().parent_path();
	WCHAR dir[_MAX_PATH]{};
	GetInidir(dir);
	EXPECT_EQ(sakura::path_to_wstring(iniDir) + LTEXT("/"), sakura::wstring(dir));
	GetInidir(dir, LTEXT("keyword/cpp.kwd"));
	EXPECT_EQ(sakura::path_to_wstring(iniDir / "keyword" / "cpp.kwd"), sakura::wstring(dir));

	// 相对路径按设置文件的文件夹解释（强调关键字、辞书文件等）
	WriteAll(iniDir / "keyword" / "cpp.kwd", U8(u8"\xEF\xBB\xBF" "class\r\n名前空間\r\n"));
	CTextInputStream_AbsIni in(LTEXT("keyword/cpp.kwd"));
	ASSERT_TRUE(in);
	EXPECT_EQ(sakura::wstring(LTEXT("class")), in.ReadLineW());
	EXPECT_EQ(sakura::wstring(LTEXT("名前空間")), in.ReadLineW());
}

// ---------------------------------------------------------------------------
// 平台层
// ---------------------------------------------------------------------------

TEST(MacPlatformEnv, SwscanfS)
{
	WORD a = 0, b = 0, c = 0, d = 0;
	EXPECT_EQ(4, ::swscanf_s(LTEXT("2.4.4.456"), LTEXT("%hu.%hu.%hu.%hu"), &a, &b, &c, &d));
	EXPECT_EQ(2, a); EXPECT_EQ(4, b); EXPECT_EQ(4, c); EXPECT_EQ(456, d);
	EXPECT_EQ(2, ::swscanf_s(LTEXT("1,2,3"), LTEXT("%hu.%hu"), &a, &b) + 1);	// "1" だけ読める

	int x = 0; unsigned y = 0; WCHAR name[8]{};
	EXPECT_EQ(3, ::swscanf_s(LTEXT("-12,ff,abc"), LTEXT("%d,%x,%[a-z]"), &x, &y, name, unsigned(std::size(name))));
	EXPECT_EQ(-12, x); EXPECT_EQ(0xffu, y); EXPECT_STREQ(LTEXT("abc"), name);
}

TEST(MacPlatformEnv, WsplitpathS)
{
	WCHAR drive[_MAX_DRIVE], dir[_MAX_DIR], fname[_MAX_FNAME], ext[_MAX_EXT];
	EXPECT_EQ(0, _wsplitpath_s(LTEXT("/Users/sakura/main.cpp"), drive, dir, fname, ext));
	EXPECT_STREQ(LTEXT(""), drive);
	EXPECT_STREQ(LTEXT("/Users/sakura/"), dir);
	EXPECT_STREQ(LTEXT("main"), fname);
	EXPECT_STREQ(LTEXT(".cpp"), ext);
}

TEST(MacPlatformEnv, PathMatchSpec)
{
	EXPECT_TRUE(::PathMatchSpec(LTEXT("README"), LTEXT("*.*")));
	EXPECT_TRUE(::PathMatchSpec(LTEXT("main.CPP"), LTEXT("*.c; *.cpp")));
	EXPECT_TRUE(::PathMatchSpec(LTEXT("a1.txt"), LTEXT("a?.txt")));
	EXPECT_FALSE(::PathMatchSpec(LTEXT("a12.txt"), LTEXT("a?.txt")));
	EXPECT_TRUE(::PathMatchSpec(LTEXT("Makefile"), LTEXT("Makefile.*")));
	EXPECT_FALSE(::PathMatchSpec(LTEXT("main.cpp"), LTEXT("*.h")));
}

TEST(MacPlatformEnv, EmbeddedMainMenuResource)
{
	const HRSRC h = ::FindResourceW(nullptr, MAKEINTRESOURCEW(IDR_MENU1), MAKEINTRESOURCEW(ID_RC_TYPE_INI));
	ASSERT_NE(nullptr, h);
	const DWORD size = ::SizeofResource(nullptr, h);
	const auto* p = static_cast<const char*>(::LockResource(::LoadResource(nullptr, h)));
	ASSERT_NE(nullptr, p);
	// src/main/resources/MainMenu.ini と同じ内容
	EXPECT_EQ(ReadAll(fs::path(SAKURA_ROOT_DIR) / "src" / "main" / "resources" / "MainMenu.ini"), std::string(p, size));
	EXPECT_EQ(nullptr, ::FindResourceW(nullptr, MAKEINTRESOURCEW(9999), MAKEINTRESOURCEW(ID_RC_TYPE_INI)));
}

TEST(MacPlatformEnv, NamedMutexIsSharedAcrossObjects)
{
	CMutex m1(FALSE, LTEXT("SakuraMacTestMutex"));
	CMutex m2(FALSE, LTEXT("SakuraMacTestMutex"));
	ASSERT_TRUE(m1.Lock());
	ASSERT_TRUE(m1.Lock(0));	// ロック中にもう一度 Lock しても true（Windows 版の CMutex と同じく、Unlock 1 回で解放される）
	// 別スレッドからは、同じ名前の別オブジェクトでも取れない
	auto other = std::async(std::launch::async, [&] { return m2.Lock(50); });
	EXPECT_FALSE(other.get());
	m1.Unlock();
	auto other2 = std::async(std::launch::async, [&] { const bool r = m2.Lock(1000); if (r) m2.Unlock(); return r; });
	EXPECT_TRUE(other2.get());
}

// ---------------------------------------------------------------------------
// 外部模块（原版 test-extmodules.cpp 的 CMigemoTest、InitRegexp）
// ---------------------------------------------------------------------------

class MacMigemoTest : public MacEnvTest {
protected:
	fs::path m_dictPath;
	void SetUp() override
	{
		MacEnvTest::SetUp();
		m_dictPath = GetIniFileName().replace_filename("dict");
	}
	void CopyDict(const char* charset)
	{
		fs::create_directories(m_dictPath);
		fs::copy(fs::path(SAKURA_MIGEMO_DICT_DIR) / charset, m_dictPath / charset, fs::copy_options::recursive);
	}
};

TEST_F(MacMigemoTest, NoDictionary)
{
	auto& sHelper = GetDllShareData().m_Common.m_sHelper;
	sHelper.m_szMigemoDll = LTEXT("");
	sHelper.m_szMigemoDict = LTEXT("");
	CMigemo migemo;
	migemo.InitDll();
	EXPECT_FALSE(migemo.migemo_load_all());
	EXPECT_FALSE(migemo.migemo_is_enable());
}

TEST_F(MacMigemoTest, Utf8DictionaryRelativeToIni)
{
	auto& sHelper = GetDllShareData().m_Common.m_sHelper;
	sHelper.m_szMigemoDll = LTEXT("migemo.dll");	// 相对路径
	sHelper.m_szMigemoDict = LTEXT("dict");
	CopyDict("utf-8");
	CMigemo migemo;
	migemo.InitDll();
	EXPECT_TRUE(migemo.migemo_load_all());
	EXPECT_TRUE(migemo.migemo_is_enable());
	EXPECT_EQ(sakura::wstring(LTEXT("(ｻｸﾗｴﾃﾞｨ[ﾄﾃﾂﾁﾀ]|サクラエディ[トテツチタ]|さくらえでぃ[とてつちたｔt])")), migemo.migemo_query_w(LTEXT("さくらえでぃt")));
}

TEST_F(MacMigemoTest, Cp932DictionaryAbsolutePath)
{
	auto& sHelper = GetDllShareData().m_Common.m_sHelper;
	sHelper.m_szMigemoDll = sakura::path_to_wstring(GetIniFileName().replace_filename("migemo.dll")).c_str();	// 绝对路径（不存在时用默认的名字）
	sHelper.m_szMigemoDict = sakura::path_to_wstring(m_dictPath).c_str();
	CopyDict("cp932");
	CMigemo migemo;
	migemo.InitDll();
	EXPECT_TRUE(migemo.migemo_load_all());
	EXPECT_TRUE(migemo.migemo_is_enable());
	// Shift_JIS に変換できない文字はそのまま返る
	EXPECT_EQ(sakura::wstring(LTEXT("\U0001F6B9")), migemo.migemo_query_w(LTEXT("\U0001F6B9")));
}

TEST_F(MacEnvTest, InitRegexpUsesCommonSetting)
{
	CBregexp regexp;
	EXPECT_TRUE(InitRegexp(nullptr, regexp, false));
	EXPECT_TRUE(regexp.IsAvailable());
	// 指定した DLL が無いときは既定の名前（bregonig.dll）で読み込む（Windows 版と同じ）
	::wcscpy_s(GetDllShareData().m_Common.m_sSearch.m_szRegexpLib, LTEXT("no-such-regexp.dll"));
	CBregexp regexp2;
	EXPECT_TRUE(InitRegexp(nullptr, regexp2, false));
	EXPECT_STREQ(LTEXT("bregonig.dll"), regexp2.GetLoadedDllName());
}

} // namespace
