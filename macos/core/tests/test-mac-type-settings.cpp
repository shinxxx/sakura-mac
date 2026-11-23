/*! @file
	@brief タイプ別設定的读写（计划第 40 步：タイプ別設定窗口）的测试

	タイプ別設定窗口与共通設定窗口相同，按 sakura.ini 的「节/项目」读写（节是 Types(N)）。这里确认：
	- 读出的值与 sakura.ini 的写法相同（nInts 是逗号分隔的 12 个数）
	- 改了以后这个类型的设置（STypeConfig）和一览（STypeConfigMini：名字、拡張子、文字コード）都变了，别的类型不变
	- 范围限制与原版读入 sakura.ini 时相同（折り返し桁数 10～10240、TAB幅 2～桁数-2、行番号の最小桁数 2～11 等）
	- 没有的类型、写法不对的节不改
	- 打开着的文档：类型是改了的类型时按新的设置重新排版（原版 PM_CHANGESETTING_TYPE），别的类型的文档不变；
	  拡張子改了时按文件名重新决定类型；折り返し方法的临时设置按原版的规则保留或解除
	- SaveSettings 以后 sakura.ini 里是新的值，重新启动后也是
*/
/*
	Copyright (C) 2026, Sakura Editor Organization

	SPDX-License-Identifier: Zlib
*/
#include "pch.h"

#include "sakura_core/SakuraCore.h"

#include "config/app_constants.h"
#include "env/CDocTypeManager.h"
#include "env/DLLSHAREDATA.h"
#include "util/file.h"

#include <algorithm>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <string>

using namespace sakura::core;

namespace {

namespace fs = std::filesystem;

class MacTypeSettingTest : public ::testing::Test {
protected:
	void SetUp() override
	{
		RemoveIniFolder();
		ASSERT_TRUE(Startup());
		m_dir = fs::path(std::getenv("HOME")) / "type-settings-work";
		fs::remove_all(m_dir);
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
	//! 名字是 name 的类型的编号
	static int IndexOf(const Text& name)
	{
		for (const auto& t : TypeSettings()) {
			if (t.name == name) return t.index;
		}
		return -1;
	}
	static STypeConfig Config(int index)
	{
		STypeConfig type;
		EXPECT_TRUE(CDocTypeManager().GetTypeConfig(CTypeConfig(index), type));
		return type;
	}
	static Text Section(int index)
	{
		const auto s = std::to_string(index);
		return u"Types(" + Text(s.begin(), s.end()) + u")";
	}
	std::unique_ptr<Document> Open(const char* name, const std::string& text)
	{
		const auto path = m_dir / name;
		std::ofstream(path, std::ios::binary) << text;
		auto doc = Document::Create();
		EXPECT_NE(nullptr, doc);
		OpenOptions options;
		options.encoding = encoding::UTF8;
		EXPECT_EQ(Result::Ok, doc->Open(path.u16string(), options));
		return doc;
	}

	fs::path m_dir;
};

std::string ReadAll(const fs::path& path)
{
	std::ifstream in(path, std::ios::binary);
	return std::string(std::istreambuf_iterator<char>(in), std::istreambuf_iterator<char>());
}

std::string Narrow(const std::optional<Text>& t)
{
	return t ? std::string(t->begin(), t->end()) : std::string("(none)");
}

} // namespace

//! 一览：顺序与 Types(0)、Types(1)… 相同，0 是「基本」
TEST_F(MacTypeSettingTest, ListsTypesInOrder)
{
	const auto types = TypeSettings();
	ASSERT_EQ(GetDllShareData().m_nTypesCount, static_cast<int>(types.size()));
	for (size_t i = 0; i < types.size(); ++i) {
		EXPECT_EQ(static_cast<int>(i), types[i].index);
		EXPECT_EQ(Text(GetDllShareData().m_TypeMini[i].m_szTypeName.c_str()), types[i].name);
	}
	EXPECT_EQ(u"基本", types[0].name);
	const int cpp = IndexOf(u"C/C++");
	ASSERT_LT(0, cpp);
	EXPECT_NE(Text::npos, types[cpp].extensions.find(u"cpp"));
}

//! 读：与 sakura.ini 的写法相同
TEST_F(MacTypeSettingTest, GetReturnsIniValue)
{
	const int cpp = IndexOf(u"C/C++");
	const STypeConfig type = Config(cpp);
	EXPECT_EQ(u"C/C++", GetCommonSetting(Section(cpp), u"szTypeName"));
	EXPECT_EQ(Text(type.m_szTypeExts.c_str()), GetCommonSetting(Section(cpp), u"szTypeExts"));
	EXPECT_EQ(type.m_bInsSpace ? u"1" : u"0", GetCommonSetting(Section(cpp), u"bInsSpace"));
	// nInts：m_nIdx, 折り返し桁数, 文字の間隔, TAB幅, 強調キーワード1, 2, 文字列エスケープ, 行番号を改行単位, 行番号区切り, 英文ワードラップ, 印刷, TSV
	const auto ints = Narrow(GetCommonSetting(Section(cpp), u"nInts"));
	EXPECT_EQ(0u, ints.find(std::to_string(cpp) + "," + std::to_string(Int(type.m_nMaxLineKetas)) + ","));
	EXPECT_EQ(11, std::count(ints.begin(), ints.end(), ','));
	// タイプ別フォント（ShareData_IO_LogFont の既定の名前）
	EXPECT_TRUE(GetCommonSetting(Section(cpp), u"lf").has_value());
	EXPECT_TRUE(GetCommonSetting(Section(cpp), u"nPointSize").has_value());
	EXPECT_TRUE(GetCommonSetting(Section(cpp), u"lfFaceName").has_value());

	EXPECT_FALSE(GetCommonSetting(Section(cpp), u"NoSuchKey").has_value());
	EXPECT_FALSE(GetCommonSetting(Section(GetDllShareData().m_nTypesCount), u"szTypeName").has_value());
	EXPECT_FALSE(GetCommonSetting(u"Types(01)", u"szTypeName").has_value());
	EXPECT_FALSE(GetCommonSetting(u"Types()", u"szTypeName").has_value());
	EXPECT_FALSE(GetCommonSetting(u"Types(-1)", u"szTypeName").has_value());
}

//! 写：这个类型变了（一览的名字、拡張子、文字コード也是），别的类型不变
TEST_F(MacTypeSettingTest, SetChangesOnlyThatType)
{
	const int cpp = IndexOf(u"C/C++");
	const int text = IndexOf(u"テキスト");
	ASSERT_LT(0, text);
	const STypeConfig textBefore = Config(text);
	ASSERT_TRUE(SetCommonSettings(Section(cpp), {
		{ u"szTypeName", u"C++ (Mac)" }, { u"szTypeExts", u"cpp,mm" }, { u"bInsSpace", u"1" },
		{ u"eDefaultCodetype", std::u16string(u"0") }, { u"szKinsokuHead", u"!%)" },
	}));
	const STypeConfig type = Config(cpp);
	EXPECT_STREQ(LTEXT("C++ (Mac)"), type.m_szTypeName.c_str());
	EXPECT_TRUE(type.m_bInsSpace);
	EXPECT_STREQ(LTEXT("!%)"), type.m_szKinsokuHead.c_str());
	EXPECT_EQ(cpp, type.m_nIdx);
	const auto& mini = GetDllShareData().m_TypeMini[cpp];
	EXPECT_STREQ(LTEXT("C++ (Mac)"), mini.m_szTypeName.c_str());
	EXPECT_STREQ(LTEXT("cpp,mm"), mini.m_szTypeExts.c_str());
	EXPECT_EQ(CODE_SJIS, mini.m_encoding.m_eDefaultCodetype);
	EXPECT_EQ(u"C++ (Mac)", TypeSettings()[cpp].name);
	// 拡張子でタイプが決まる
	EXPECT_EQ(cpp, CDocTypeManager().GetDocumentTypeOfPath(LTEXT("a.mm")).GetIndex());

	const STypeConfig textAfter = Config(text);
	EXPECT_STREQ(textBefore.m_szTypeName.c_str(), textAfter.m_szTypeName.c_str());
	EXPECT_EQ(textBefore.m_bInsSpace, textAfter.m_bInsSpace);
}

//! 「基本」（Types(0)）：m_TypeBasis も変わる（新しい文書はこれを使う）
TEST_F(MacTypeSettingTest, SetBasisChangesTypeBasis)
{
	ASSERT_TRUE(SetCommonSetting(u"Types(0)", u"nLineSpace", u"5"));
	EXPECT_EQ(5, GetDllShareData().m_TypeBasis.m_nLineSpace);
	auto doc = Document::Create();
	EXPECT_EQ(5, doc->GetViewSettings().lineSpacing);
}

//! 范围限制与原版读入 sakura.ini 时相同
TEST_F(MacTypeSettingTest, SetAppliesOriginalLimits)
{
	const int cpp = IndexOf(u"C/C++");
	const auto ints = [&](const char* body) {
		return Text(u"0,") + Text(body, body + std::strlen(body));
	};
	// 折り返し桁数 MINLINEKETAS～MAXLINEKETAS、TAB幅 2～桁数-2
	ASSERT_TRUE(SetCommonSetting(Section(cpp), u"nInts", ints("99999,0,99,0,0,0,1,1,0,0,0")));
	EXPECT_EQ(MAXLINEKETAS, Int(Config(cpp).m_nMaxLineKetas));
	EXPECT_EQ(99, Int(Config(cpp).m_nTabSpace));
	ASSERT_TRUE(SetCommonSetting(Section(cpp), u"nInts", ints("3,0,99,0,0,0,1,1,0,0,0")));
	EXPECT_EQ(MINLINEKETAS, Int(Config(cpp).m_nMaxLineKetas));
	EXPECT_EQ(MINLINEKETAS - 2, Int(Config(cpp).m_nTabSpace));
	// m_nIdx は書いた値でなく、その類型の番号（原版 ShareData_IO_Types の読み込み後）
	EXPECT_EQ(cpp, Config(cpp).m_nIdx);
	// 12 個そろわないときは読まない（原版と同じ）
	const auto before = GetCommonSetting(Section(cpp), u"nInts");
	ASSERT_TRUE(SetCommonSetting(Section(cpp), u"nInts", u"1,2,3"));
	EXPECT_EQ(before, GetCommonSetting(Section(cpp), u"nInts"));

	// 行番号の最小桁数 2～11、行の間隔 -128～128
	ASSERT_TRUE(SetCommonSetting(Section(cpp), u"nLineNumWidth", u"20"));
	EXPECT_EQ(LINENUMWIDTH_MAX, Config(cpp).m_nLineNumWidth);
	ASSERT_TRUE(SetCommonSetting(Section(cpp), u"nLineSpace", u"-500"));
	EXPECT_EQ(-LINESPACE_MAX, Config(cpp).m_nLineSpace);
}

//! 没有的项目、没有的类型：false，什么也不改
TEST_F(MacTypeSettingTest, SetRejectsUnknownItems)
{
	const int cpp = IndexOf(u"C/C++");
	EXPECT_FALSE(SetCommonSettings(Section(cpp), { { u"bInsSpace", u"1" }, { u"NoSuchKey", u"1" } }));
	EXPECT_FALSE(Config(cpp).m_bInsSpace);
	EXPECT_FALSE(SetCommonSetting(Section(GetDllShareData().m_nTypesCount), u"bInsSpace", u"1"));
	EXPECT_FALSE(SetCommonSetting(u"Types(x)", u"bInsSpace", u"1"));
}

//! 打开着的文档：这个类型的文档按新的设置重新排版，别的类型的文档不变（原版 PM_CHANGESETTING_TYPE）
TEST_F(MacTypeSettingTest, OpenDocumentsFollowChangedType)
{
	const int text = IndexOf(u"テキスト");
	const int cpp = IndexOf(u"C/C++");
	auto txt = Open("a.txt", "0123456789 0123456789 0123456789\n");
	auto src = Open("a.cpp", "0123456789 0123456789 0123456789\n");
	ASSERT_EQ(text, txt->GetFileInfo().typeIndex);
	ASSERT_EQ(cpp, src->GetFileInfo().typeIndex);
	const auto srcSpacing = src->GetViewSettings().lineSpacing;

	// テキスト：指定桁で折り返す 12 桁、行の間隔 7
	auto ints = Narrow(GetCommonSetting(Section(text), u"nInts"));
	ints = ints.substr(0, ints.find(',') + 1) + "12" + ints.substr(ints.find(',', ints.find(',') + 1));
	ASSERT_TRUE(SetCommonSettings(Section(text), {
		{ u"nInts", Text(ints.begin(), ints.end()) }, { u"nTextWrapMethod", u"1" }, { u"nLineSpace", u"7" },
	}));
	EXPECT_TRUE(txt->ApplyTypeSettingChange(text));
	EXPECT_EQ(12, txt->GetViewSettings().wrapColumns);
	EXPECT_EQ(WrapMethod::SettingWidth, txt->GetViewSettings().wrapMethod);
	EXPECT_EQ(7, txt->GetViewSettings().lineSpacing);
	EXPECT_LT(1, txt->LayoutLineCount());

	EXPECT_FALSE(src->ApplyTypeSettingChange(text)) << "別のタイプの文書はそのまま";
	EXPECT_EQ(srcSpacing, src->GetViewSettings().lineSpacing);
}

//! 拡張子が変わった：ファイル名でタイプを決め直す（原版 CEditDoc::OnChangeSetting の SetDocumentType）
TEST_F(MacTypeSettingTest, ChangedExtensionsMoveDocumentToOtherType)
{
	const int text = IndexOf(u"テキスト");
	const int cpp = IndexOf(u"C/C++");
	auto doc = Open("a.zzz", "x\n");
	ASSERT_EQ(0, doc->GetFileInfo().typeIndex);
	// C/C++ に zzz を足す → a.zzz は C/C++ になる
	const auto exts = GetCommonSetting(Section(cpp), u"szTypeExts").value_or(u"");
	ASSERT_TRUE(SetCommonSetting(Section(cpp), u"szTypeExts", exts + u",zzz"));
	EXPECT_TRUE(doc->ApplyTypeSettingChange(cpp));
	EXPECT_EQ(cpp, doc->GetFileInfo().typeIndex);
	EXPECT_EQ(u"C/C++", doc->GetFileInfo().typeName);
	EXPECT_FALSE(doc->ApplyTypeSettingChange(text));
	// 元に戻す → 基本 に戻る
	ASSERT_TRUE(SetCommonSetting(Section(cpp), u"szTypeExts", exts));
	EXPECT_TRUE(doc->ApplyTypeSettingChange(cpp));
	EXPECT_EQ(0, doc->GetFileInfo().typeIndex);
}

//! 折り返し方法の一時設定（F_TMPWRAP* 等）：タイプ別設定の折り返し方法が変わらなければ残る。同じになれば解除
TEST_F(MacTypeSettingTest, TemporaryWrapIsKeptUnlessSettingMatches)
{
	const int text = IndexOf(u"テキスト");
	auto doc = Open("b.txt", "0123456789 0123456789 0123456789\n");
	ASSERT_TRUE(SetCommonSetting(Section(text), u"nTextWrapMethod", u"1"));
	ASSERT_TRUE(doc->ApplyTypeSettingChange(text));
	ASSERT_EQ(WrapMethod::SettingWidth, doc->GetViewSettings().wrapMethod);
	// 一時的に「折り返さない」
	ASSERT_TRUE(doc->SetWrap(WrapMethod::None, 0));
	// 行の間隔だけ変える → 一時設定は残る
	ASSERT_TRUE(SetCommonSetting(Section(text), u"nLineSpace", u"3"));
	ASSERT_TRUE(doc->ApplyTypeSettingChange(text));
	EXPECT_EQ(WrapMethod::None, doc->GetViewSettings().wrapMethod);
	// タイプ別設定も「折り返さない」にする → 一時設定は解除（以後はタイプ別設定に従う）
	ASSERT_TRUE(SetCommonSetting(Section(text), u"nTextWrapMethod", u"0"));
	ASSERT_TRUE(doc->ApplyTypeSettingChange(text));
	EXPECT_EQ(WrapMethod::None, doc->GetViewSettings().wrapMethod);
	ASSERT_TRUE(SetCommonSetting(Section(text), u"nTextWrapMethod", u"1"));
	ASSERT_TRUE(doc->ApplyTypeSettingChange(text));
	EXPECT_EQ(WrapMethod::SettingWidth, doc->GetViewSettings().wrapMethod);
}

//! 保存：sakura.ini の [Types(N)] に新しい値、再起動後も
TEST_F(MacTypeSettingTest, SaveSettingsWritesIni)
{
	const int cpp = IndexOf(u"C/C++");
	ASSERT_TRUE(SetCommonSettings(Section(cpp), { { u"szTypeName", u"CPP" }, { u"szIndentChars", u"{}" } }));
	ASSERT_TRUE(SaveSettings());
	const auto ini = ReadAll(GetIniFileName());
	const auto section = ini.find("[Types(" + std::to_string(cpp) + ")]");
	ASSERT_NE(std::string::npos, section);
	const auto next = ini.find("\r\n[", section + 1);
	const auto body = ini.substr(section, next - section);
	EXPECT_NE(std::string::npos, body.find("szTypeName=CPP\r\n"));
	EXPECT_NE(std::string::npos, body.find("szIndentChars={}\r\n"));

	Shutdown(false);
	ASSERT_TRUE(Startup());
	EXPECT_STREQ(LTEXT("CPP"), Config(cpp).m_szTypeName.c_str());
	EXPECT_STREQ(LTEXT("{}"), Config(cpp).m_szIndentChars.c_str());
}
