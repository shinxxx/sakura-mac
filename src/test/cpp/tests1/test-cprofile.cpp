/*! @file */
/*
	Copyright (C) 2018-2026, Sakura Editor Organization

	SPDX-License-Identifier: Zlib
*/
#include "pch.h"
#include "env/CDataProfile.h"

#include "env/CShareData_IO.h"
#include "env/DLLSHAREDATA.h"
#include "uiparts/CMenuDrawer.h"

#include <Shlwapi.h>

#include <cstdlib>
#include <fstream>

#include "util/file.h"
#include "view/colors/EColorIndexType.h"

#if defined(_WIN32)
#include "window/TrayWndTestSuite.hpp"
#else
#include "mac-editor-test-suite.hpp"	// Mac 版: トレイウィンドウはまだないので、共通設定だけを用意する（移植計画のステップ 21）
#endif

using namespace std::literals::string_literals;
using namespace std::literals::string_view_literals;

extern template
void ShareData_IO_KeyHelpArr<KeyHelpInfo(&)[MAX_KEYHELP_FILE]>(
	CDataProfile&			cProfile,
	sakura::wstring_view		sectionName,	//!< [in] セクション名
	KeyHelpInfo				(&KeyHelpArr)[MAX_KEYHELP_FILE],
	int&					nKeyHelpNum
);

extern template
void ShareData_IO_OutlineDockRect<CommonSetting_OutLine>(
	CDataProfile&			cProfile,
	sakura::wstring_view		sectionName,	//!< [in] セクション名
	sakura::wstring_view		entryKey,		//!< [in] エントリ名
	CommonSetting_OutLine&	tEntryValue		//!< [in,out] エントリ値
);

extern template
void ShareData_IO_VertLineIdx<CKetaXInt(&)[MAX_VERTLINES]>(
	CDataProfile&		cProfile,
	sakura::wstring_view	sectionName,	//!< [in] セクション名
	CKetaXInt			(&nVertLineIdx)[MAX_VERTLINES]
);

/*!
 * @brief 内部バッファが溢れたら拡張する
 */
TEST(CProfile, ReadProfile_ExpandLineBuffer)
{
	std::filesystem::path iniPath{ "test.ini" };

	std::error_code ec;
	std::filesystem::remove(iniPath, ec);

	// ファイル出力ストリームをバイナリモードで開く
	std::ofstream os(iniPath, std::ios::binary);

	std::vector<std::string> lines{
		"; test"s,
		"[test]"s,
		"test=1"s,
	};

	constexpr auto& prefix = "too_long_item=";
	auto tooLongLine = std::format("{}{:x<4083}", prefix, 'x');	// 4096文字を超える行を作る
	lines.emplace_back(tooLongLine);

	// 各行を書き込む
	for (const auto& line : lines) {
		if (!line.empty()) {
			os.write(LPCSTR(std::data(line)), std::size(line));
		}
		os << '\r';
	}

	os.close();

	CDataProfile cProfile;
	cProfile.ReadProfile(iniPath);

	bool value = false;
	EXPECT_TRUE(cProfile.IOProfileData(LTEXT("test"), LTEXT("test"), value));
	EXPECT_THAT(value, IsTrue());

	std::filesystem::remove(iniPath, ec);
}

/*!
 * @brief 設定ファイルの改行コードがCR
 */
TEST(CProfile, ReadProfile_LineTerminatorCr)
{
	std::filesystem::path iniPath{ "test.ini" };

	std::error_code ec;
	std::filesystem::remove(iniPath, ec);

	// ファイル出力ストリームをバイナリモードで開く
	std::ofstream os(iniPath, std::ios::binary);

	const std::array lines{
		u8"; test"sv,
		u8"[test]"sv,
		u8"test=1"sv,
	};

	// 各行を書き込む
	for (const auto& line : lines) {
		if (!line.empty()) {
			os.write(LPCSTR(std::data(line)), std::size(line));
		}
		os << '\r';
	}

	os.close();

	CDataProfile cProfile;
	cProfile.ReadProfile(iniPath);

	bool value = false;
	EXPECT_TRUE(cProfile.IOProfileData(LTEXT("test"), LTEXT("test"), value));
	EXPECT_THAT(value, IsTrue());

	std::filesystem::remove(iniPath, ec);
}

/*!
 * @brief WriteProfileは指定されたパスに含まれるサブディレクトリを作成する
 */
TEST( CProfile, WriteProfileMakesSubDirectories )
{
	// サブディレクトリを含むパスを作成する
	WCHAR szIniName[_MAX_PATH]{ 0 };
#if defined(_WIN32)
	::_wfullpath( szIniName, LTEXT("test1\\test2\\test.ini"), int(std::size(szIniName)) );
#else
	// Mac 版: パスの区切りは '/'（移植計画のステップ 21）
	::wcscpy_s( szIniName, sakura::path_to_wstring(std::filesystem::absolute("test1/test2/test.ini")).c_str() );
#endif

	// プロファイルを書き出す
	CProfile cProfile;
	cProfile.WriteProfile( szIniName, LTEXT("WriteProfileのテスト") );

	ASSERT_TRUE( fexist( szIniName ) );

	WCHAR* p;

	std::error_code ec;

	// ファイルを削除
	std::filesystem::remove( szIniName, ec );

#if defined(_WIN32)
	// フォルダーを削除
	p = ::PathFindFileNameW( szIniName );
	p[0] = LCHAR('\0');
	std::filesystem::remove( szIniName, ec );

	// フォルダーを削除
	p = ::PathFindFileNameW( szIniName );
	p[0] = LCHAR('\0');
	std::filesystem::remove( szIniName, ec );
#else
	// Mac 版: PathFindFileNameW の代わりに std::filesystem で親フォルダーを削除する（移植計画のステップ 21）
	(void)p;
	const auto dir2 = std::filesystem::path( szIniName ).parent_path();
	std::filesystem::remove( dir2, ec );
	std::filesystem::remove( dir2.parent_path(), ec );
#endif
}

/*!
 * @brief GetProfileDataのテスト
 */
TEST(CProfile, GetProfileData_NoSection)
{
	CProfile cProfile;
	cProfile.SetReadingMode();

	// 初期状態は空なのでセクションが見つからない
	sakura::wstring value;
	ASSERT_FALSE(cProfile.GetProfileData(LTEXT("存在しないセクション名"), LTEXT("szTest"), value));
}

/*!
 * @brief GetProfileDataのテスト
 */
TEST(CProfile, GetProfileData_NewSection)
{
	CProfile cProfile;
	cProfile.SetReadingMode();

	sakura::wstring value;
	ASSERT_FALSE(cProfile.GetProfileData(LTEXT("Test"), LTEXT("szTest"), value));

	// セクションを追加
	cProfile.SetProfileData(LTEXT("Test"), LTEXT("szTest"), LTEXT("value"));

	// 追加されたセクションを取得
	ASSERT_TRUE(cProfile.GetProfileData(LTEXT("Test"), LTEXT("szTest"), value));
	ASSERT_STREQ(LTEXT("value"), value.data());
}

/*!
 * @brief GetProfileDataのテスト
 */
TEST(CProfile, GetProfileData_NoEntry)
{
	CProfile cProfile;
	cProfile.SetReadingMode();

	sakura::wstring value;
	ASSERT_FALSE(cProfile.GetProfileData(LTEXT("Test"), LTEXT("szTest"), value));

	cProfile.SetProfileData(LTEXT("Test"), LTEXT("szTest"), LTEXT("value"));

	ASSERT_TRUE(cProfile.GetProfileData(LTEXT("Test"), LTEXT("szTest"), value));
	ASSERT_STREQ(LTEXT("value"), value.data());

	// 該当するキーがないのでエントリを取得できない
	ASSERT_FALSE(cProfile.GetProfileData(LTEXT("Test"), LTEXT("nTest"), value));
}

/*!
 * @brief GetProfileDataのテスト
 */
TEST(CProfile, GetProfileData_NewEntry)
{
	CProfile cProfile;
	cProfile.SetReadingMode();

	sakura::wstring value;
	ASSERT_FALSE(cProfile.GetProfileData(LTEXT("Test"), LTEXT("szTest"), value));

	cProfile.SetProfileData(LTEXT("Test"), LTEXT("szTest"), LTEXT("value"));

	ASSERT_TRUE(cProfile.GetProfileData(LTEXT("Test"), LTEXT("szTest"), value));
	ASSERT_STREQ(LTEXT("value"), value.data());

	ASSERT_FALSE(cProfile.GetProfileData(LTEXT("Test"), LTEXT("nTest"), value));

	cProfile.SetProfileData(LTEXT("Test"), LTEXT("nTest"), LTEXT("109"));

	ASSERT_TRUE(cProfile.GetProfileData(LTEXT("Test"), LTEXT("nTest"), value));
	ASSERT_STREQ(LTEXT("109"), value.data());
}

/*!
 * @brief TryParseのテスト
 */
TEST(profile_data, TryParse_int)
{
	int value = 0;
	ASSERT_TRUE(profile_data::TryParse(LTEXT("109"), value));
	ASSERT_EQ(109, value);

	ASSERT_FALSE(profile_data::TryParse(LTEXT(""), value));
	ASSERT_EQ(109, value);

	ASSERT_FALSE(profile_data::TryParse(LTEXT("not a number"), value));
	ASSERT_EQ(109, value);

	ASSERT_TRUE(profile_data::TryParse(LTEXT("888"), value));
	ASSERT_EQ(888, value);
}

/*!
 * @brief TryParseのテスト
 */
TEST(profile_data, TryParse_CLayoutInt)
{
	CLayoutInt value{ 0 };
	ASSERT_TRUE(profile_data::TryParse(LTEXT("109"), value));
	ASSERT_EQ(109, value);

	ASSERT_FALSE(profile_data::TryParse(LTEXT(""), value));
	ASSERT_EQ(109, value);

	ASSERT_FALSE(profile_data::TryParse(LTEXT("not a number"), value));
	ASSERT_EQ(109, value);

	ASSERT_TRUE(profile_data::TryParse(LTEXT("888"), value));
	ASSERT_EQ(888, value);
}

/*!
 * @brief TryParseのテスト
 */
TEST(profile_data, TryParse_enum)
{
	enum ETest { NONE, RED, GREEN, BLUE, };
	ETest value = NONE;
	ASSERT_TRUE(profile_data::TryParse(LTEXT("1"), value));
	ASSERT_EQ(RED, value);

	ASSERT_FALSE(profile_data::TryParse(LTEXT(""), value));
	ASSERT_EQ(RED, value);
}

/*!
 * @brief TryParseのテスト
 */
TEST(profile_data, TryParse_bool)
{
	bool value = false;
	ASSERT_TRUE(profile_data::TryParse(LTEXT("1"), value));
	ASSERT_TRUE(value);

	ASSERT_FALSE(profile_data::TryParse(LTEXT(""), value));
	ASSERT_TRUE(value);

	ASSERT_FALSE(profile_data::TryParse(LTEXT("false"), value));
	ASSERT_TRUE(value);

	ASSERT_TRUE(profile_data::TryParse(LTEXT("0"), value));
	ASSERT_FALSE(value);
}

/*!
 * @brief TryParseのテスト
 */
TEST(profile_data, TryParse_WCHAR)
{
	WCHAR value = LCHAR('\0');
	ASSERT_TRUE(profile_data::TryParse(LTEXT("|"), value));
	ASSERT_EQ(LCHAR('|'), value);

	ASSERT_FALSE(profile_data::TryParse(LTEXT("\U0001F51E"), value));
	ASSERT_EQ(LCHAR('|'), value);

	ASSERT_TRUE(profile_data::TryParse(LTEXT(""), value));
	ASSERT_EQ(LCHAR('\0'), value);
}

/*!
 * @brief TryParseのテスト
 */
TEST(profile_data, TryParse_KEYCODE)
{
	KEYCODE value = '\0';
	ASSERT_TRUE(profile_data::TryParse(LTEXT("W"), value));
	ASSERT_EQ('W', value);

	ASSERT_FALSE(profile_data::TryParse(LTEXT("漢"), value));
	ASSERT_EQ('W', value);

	ASSERT_TRUE(profile_data::TryParse(LTEXT(""), value));
	ASSERT_EQ('\0', value);
}

/*!
 * @brief ToString(KEYCODE)のテスト
 */
TEST(profile_data, ToString_KEYCODE)
{
	sakura::wstring str;
	KEYCODE code;

	code = 0x80;
	str = profile_data::ToString(code);
	ASSERT_STREQ(LTEXT(""), str.c_str());

	code = -1;
	str = profile_data::ToString(code);
	ASSERT_STREQ(LTEXT(""), str.c_str());

	code = 0;
	str = profile_data::ToString(code);
	ASSERT_STREQ(LTEXT(""), str.c_str());

	code = 1;
	str = profile_data::ToString(code);
	ASSERT_STREQ(LTEXT("\x01"), str.c_str());

	code = 0x61;
	str = profile_data::ToString(code);
	ASSERT_STREQ(LTEXT("a"), str.c_str());

	code = 0x7f;
	str = profile_data::ToString(code);
	ASSERT_STREQ(LTEXT("\x7f"), str.c_str());
}

/*!
 * @brief IOProfileDataのテスト
 */
TEST(CDataProfile, IOProfileData)
{
	CDataProfile cProfile;
	cProfile.SetReadingMode();

	sakura::wstring value;
	EXPECT_THAT(cProfile.IOProfileData(LTEXT("Test"), LTEXT("szTest"), value), IsFalse());

	cProfile.SetProfileData(LTEXT("Test"), LTEXT("szTest"), LTEXT("value"));

	EXPECT_THAT(cProfile.IOProfileData(LTEXT("Test"), LTEXT("szTest"), value), IsTrue());
	EXPECT_THAT(value, StrEq(LTEXT("value")));

	EXPECT_THAT(cProfile.IOProfileData(LTEXT("Test"), LTEXT("nTest"), value), IsFalse());

	cProfile.SetProfileData(LTEXT("Test"), LTEXT("nTest"), LTEXT("109"));

	EXPECT_THAT(cProfile.IOProfileData(LTEXT("Test"), LTEXT("nTest"), value), IsTrue());
	EXPECT_THAT(value, StrEq(LTEXT("109")));

	int nValue = 0;
	EXPECT_THAT(cProfile.IOProfileData(LTEXT("Test"), LTEXT("nTest"), nValue), IsTrue());
	EXPECT_THAT(nValue, 109);

	EXPECT_THAT(cProfile.IOProfileData(LTEXT("Test"), LTEXT("szTest"), nValue), IsFalse());
	EXPECT_THAT(nValue, 109);
}

/*!
 * @brief IOProfileDataのテスト
 */
TEST(CDataProfile, IOProfileData_ColorInfo)
{
	CDataProfile cProfile;
	cProfile.SetReadingMode();

	ColorInfo value{};

	// 設定項目がないと読めない
	EXPECT_FALSE(cProfile.IOProfileData(LTEXT("Test"), LTEXT("clrTest"), value));

	// 値は変更されない
	EXPECT_THAT(value.m_bDisp, IsFalse());

	// 不適切な値を設定（足りない）
	cProfile.SetProfileData(LTEXT("Test"), LTEXT("clrTest"), LTEXT("1,1,ffffff,000000"));

	// 不完全な設定項目は読めない
	EXPECT_FALSE(cProfile.IOProfileData(LTEXT("Test"), LTEXT("clrTest"), value));

	// 値を設定
	cProfile.SetProfileData(LTEXT("Test"), LTEXT("clrTest"), LTEXT("1,1,ffffff,000000,1"));

	// 読める
	EXPECT_THAT(cProfile.IOProfileData(LTEXT("Test"), LTEXT("clrTest"), value), IsTrue());

	// 値は変更される
	EXPECT_THAT(value.m_bDisp, IsTrue());
	EXPECT_THAT(value.m_sFontAttr.m_bBoldFont, IsTrue());
	EXPECT_THAT(value.m_sColorAttr.m_cTEXT, Eq(0xFFFFFF));
	EXPECT_THAT(value.m_sColorAttr.m_cBACK, Eq(0));
	EXPECT_THAT(value.m_sFontAttr.m_bUnderLine, IsTrue());
}

/*!
 * @brief IOProfileDataのテスト
 */
TEST(CDataProfile, IOProfileData_EditInfo)
{
	CDataProfile cProfile;
	cProfile.SetReadingMode();

	EditInfo value{};

	// 設定項目がなくても読める
	EXPECT_TRUE(cProfile.IOProfileData(LTEXT("Test"), LTEXT("eiTest"), value));
}

/*!
 * @brief IOProfileDataのテスト
 */
TEST(CDataProfile, IOProfileData_KeyHelpInfo)
{
	CDataProfile cProfile;
	cProfile.SetReadingMode();

	KeyHelpInfo value{};
	value.m_bUse	= false;
	value.m_szAbout	= LTEXT("about");
	value.m_szPath	= LTEXT("path");

	// 設定項目がないと読めない
	EXPECT_FALSE(cProfile.IOProfileData(LTEXT("Test"), LTEXT("keyHelp"), value));

	// 値は変更されない
	EXPECT_THAT(value.m_bUse, IsFalse());
	EXPECT_THAT(value.m_szAbout, StrEq(LTEXT("about")));
	EXPECT_THAT(value.m_szPath, StrEq(LTEXT("path")));

	// 不適切な値を設定
	cProfile.SetProfileData(LTEXT("Test"), LTEXT("keyHelp"), sakura::format(LTEXT("{},{},{}"), LTEXT("true"), LTEXT("ABOUT"), LTEXT("PATH")));

	// 値が不適切なので読めない
	EXPECT_FALSE(cProfile.IOProfileData(LTEXT("Test"), LTEXT("keyHelp"), value));

	// 値は変更されない
	EXPECT_THAT(value.m_bUse, IsFalse());
	EXPECT_THAT(value.m_szAbout, StrEq(LTEXT("about")));
	EXPECT_THAT(value.m_szPath, StrEq(LTEXT("path")));

	// 不適切な値を設定
	cProfile.SetProfileData(LTEXT("Test"), LTEXT("keyHelp"), sakura::format(LTEXT("{},{},{}"), 1, sakura::wstring(50, LCHAR('a')), LTEXT("PATH")));

	// 値が不適切なので読めない
	EXPECT_FALSE(cProfile.IOProfileData(LTEXT("Test"), LTEXT("keyHelp"), value));

	// 値は変更されない
	EXPECT_THAT(value.m_bUse, IsFalse());
	EXPECT_THAT(value.m_szAbout, StrEq(LTEXT("about")));
	EXPECT_THAT(value.m_szPath, StrEq(LTEXT("path")));

	// 不適切な値を設定
	cProfile.SetProfileData(LTEXT("Test"), LTEXT("keyHelp"), sakura::format(LTEXT("{},{},{}"), 1, sakura::wstring(50 - 1, LCHAR('a')), sakura::wstring(_MAX_PATH, LCHAR('b'))));

	// 値が不適切なので読めない
	EXPECT_FALSE(cProfile.IOProfileData(LTEXT("Test"), LTEXT("keyHelp"), value));

	// 値は変更されない
	EXPECT_THAT(value.m_bUse, IsFalse());
	EXPECT_THAT(value.m_szAbout, StrEq(LTEXT("about")));
	EXPECT_THAT(value.m_szPath, StrEq(LTEXT("path")));

	// 適切（？）な値を設定
	cProfile.SetProfileData(LTEXT("Test"), LTEXT("keyHelp"), sakura::format(LTEXT("{},{},{}"), 1, sakura::wstring(50 - 1, LCHAR('a')), sakura::wstring(_MAX_PATH - 1, LCHAR('b'))));

	// 読める
	EXPECT_TRUE(cProfile.IOProfileData(LTEXT("Test"), LTEXT("keyHelp"), value));

	// 値は変更される
	EXPECT_THAT(value.m_bUse, IsTrue());
	EXPECT_THAT(value.m_szAbout, StrEq(sakura::wstring(50 - 1, LCHAR('a'))));
	EXPECT_THAT(value.m_szPath, StrEq(sakura::wstring(_MAX_PATH - 1, LCHAR('b'))));

	// szAboutが空のパターンを追加で確認する
	value.m_bUse	= false;
	value.m_szAbout	= LTEXT("about");
	value.m_szPath	= LTEXT("path");

	// 適切（？）な値を設定
	cProfile.SetProfileData(LTEXT("Test"), LTEXT("keyHelp"), LTEXT("1,,PATH"));

	// 読める
	EXPECT_TRUE(cProfile.IOProfileData(LTEXT("Test"), LTEXT("keyHelp"), value));

	EXPECT_THAT(value.m_bUse, IsTrue());
	EXPECT_THAT(value.m_szAbout, StrEq(LTEXT("")));
	EXPECT_THAT(value.m_szPath, StrEq(LTEXT("PATH")));

	// 書き込みモード
	cProfile.SetWritingMode();

	// パス未設定なら書き込み失敗とする仕様の確認
	value.m_szPath = LTEXT("");
	EXPECT_FALSE(cProfile.IOProfileData(LTEXT("Test"), LTEXT("keyHelp"), value));

	// 出力フォーマットの確認
	value.m_bUse	= true;
	value.m_szAbout	= LTEXT("ABOUT");
	value.m_szPath	= LTEXT("PATH");

	EXPECT_TRUE(cProfile.IOProfileData(LTEXT("Test"), LTEXT("keyHelp"), value));

	sakura::wstring written;
	cProfile.GetProfileData(LTEXT("Test"), LTEXT("keyHelp"), written);
	EXPECT_THAT(written, StrEq(LTEXT("1,ABOUT,PATH")));
}

/*!
 * @brief IOProfileDataのテスト
 */
TEST(CDataProfile, IOProfileData_MacroRec)
{
	CDataProfile cProfile;
	cProfile.SetReadingMode();

	MacroRec value{};
	value.m_szName[0]			= LCHAR('\0');
	value.m_szFile[0]			= LCHAR('\0');
	value.m_bReloadWhenExecute	= false;

	// 設定項目がないと読めない
	EXPECT_FALSE(cProfile.IOProfileData(LTEXT("Test"), LTEXT("[000]"), value));

	// 値は変更されない
	EXPECT_THAT(value.m_szName, StrEq(LTEXT("")));
	EXPECT_THAT(value.m_szFile, StrEq(LTEXT("")));
	EXPECT_THAT(value.m_bReloadWhenExecute, IsFalse());

	// 不適切な値を設定
	cProfile.SetProfileData(LTEXT("Test"), LTEXT("Name[000]"), sakura::wstring(MACRONAME_MAX, LCHAR('a')));

	// 値が不適切なので読めない
	EXPECT_FALSE(cProfile.IOProfileData(LTEXT("Test"), LTEXT("[000]"), value));

	// 値は変更されない
	EXPECT_THAT(value.m_szName, StrEq(LTEXT("")));
	EXPECT_THAT(value.m_szFile, StrEq(LTEXT("")));
	EXPECT_THAT(value.m_bReloadWhenExecute, IsFalse());

	// 不適切な値を設定
	cProfile.SetProfileData(LTEXT("Test"), LTEXT("Name[000]"), sakura::wstring(MACRONAME_MAX - 1, LCHAR('a')));
	cProfile.SetProfileData(LTEXT("Test"), LTEXT("File[000]"), sakura::wstring(_MAX_PATH + 1, LCHAR('b')));

	// 値が不適切なので読めない
	EXPECT_FALSE(cProfile.IOProfileData(LTEXT("Test"), LTEXT("[000]"), value));

	// 値は変更されない
	EXPECT_THAT(value.m_szName, StrEq(LTEXT("")));
	EXPECT_THAT(value.m_szFile, StrEq(LTEXT("")));
	EXPECT_THAT(value.m_bReloadWhenExecute, IsFalse());

	// 適切（？）な値を設定
	cProfile.SetProfileData(LTEXT("Test"), LTEXT("Name[000]"), sakura::wstring(MACRONAME_MAX - 1, LCHAR('a')));
	cProfile.SetProfileData(LTEXT("Test"), LTEXT("File[000]"), sakura::wstring(_MAX_PATH, LCHAR('b')));
	cProfile.SetProfileData(LTEXT("Test"), LTEXT("ReloadWhenExecute[000]"), LTEXT("1"));

	// 読める
	EXPECT_TRUE(cProfile.IOProfileData(LTEXT("Test"), LTEXT("[000]"), value));

	// 値は変更される
	EXPECT_THAT(value.m_szName, StrEq(sakura::wstring(MACRONAME_MAX - 1, LCHAR('a'))));
	EXPECT_THAT(value.m_szFile, StrEq(sakura::wstring(_MAX_PATH, LCHAR('b'))));
	EXPECT_THAT(value.m_bReloadWhenExecute, IsTrue());
}

/*!
 * @brief IOProfileDataのテスト
 */
TEST(CDataProfile, IOProfileData_PluginRec)
{
	CDataProfile cProfile;
	cProfile.SetReadingMode();

	PluginRec value{};
	value.m_szId = LTEXT("");
	value.m_szName = LTEXT("");
	value.m_state = EPluginState::PLS_NONE;
	value.m_nCmdNum = 0;

	// 設定項目がないと読めない
	EXPECT_FALSE(cProfile.IOProfileData(LTEXT("Test"), LTEXT("pluginTest"), value));

	// 値は変更されない
	EXPECT_THAT(value.m_nCmdNum, 0);

	// 不適切な値を設定（サイズオーバー1）
	cProfile.SetProfileData(LTEXT("Test"), LTEXT("pluginTest.Name"), sakura::wstring(size_t(MAX_PLUGIN_ID), LCHAR('a')));

	// 不完全な設定項目は読めない
	EXPECT_FALSE(cProfile.IOProfileData(LTEXT("Test"), LTEXT("pluginTest"), value));

	cProfile.SetProfileData(LTEXT("Test"), LTEXT("pluginTest.Name"), sakura::wstring(size_t(MAX_PLUGIN_ID) - 1, LCHAR('a')));

	// 不適切な値を設定（サイズオーバー2）
	cProfile.SetProfileData(LTEXT("Test"), LTEXT("pluginTest.Id"), sakura::wstring(size_t(MAX_PLUGIN_NAME), LCHAR('b')));

	// 不完全な設定項目は読めない
	EXPECT_FALSE(cProfile.IOProfileData(LTEXT("Test"), LTEXT("pluginTest"), value));

	cProfile.SetProfileData(LTEXT("Test"), LTEXT("pluginTest.Id"), sakura::wstring(size_t(MAX_PLUGIN_NAME) - 1, LCHAR('b')));

	// 不適切な値を設定（型誤り）
	cProfile.SetProfileData(LTEXT("Test"), LTEXT("pluginTest.CmdNum"), LTEXT("なし"));

	// 不完全な設定項目は読めない
	EXPECT_FALSE(cProfile.IOProfileData(LTEXT("Test"), LTEXT("pluginTest"), value));

	// 値を設定
	cProfile.SetProfileData(LTEXT("Test"), LTEXT("pluginTest.CmdNum"), LTEXT("1"));

	// 読める
	EXPECT_THAT(cProfile.IOProfileData(LTEXT("Test"), LTEXT("pluginTest"), value), IsTrue());

	// 値は変更される
	EXPECT_THAT(value.m_szName.c_str(), StartsWith(LTEXT("aaa")));
	EXPECT_THAT(value.m_szId.c_str(), StartsWith(LTEXT("bbb")));
	EXPECT_THAT(value.m_nCmdNum, 1);
}

/*!
 * @brief IOProfileDataのテスト
 */
TEST(CDataProfile, IOProfileData_RECT)
{
	CDataProfile cProfile;
	cProfile.SetReadingMode();

	RECT value = { 1, 2, 3, 4 };

	// 設定項目がないと読めない
	EXPECT_THAT(cProfile.IOProfileData(LTEXT("Test"), LTEXT("rcTest"), value), IsFalse());

	// 値は変更されない
	EXPECT_THAT(value.left, 1);
	EXPECT_THAT(value.top, 2);
	EXPECT_THAT(value.right, 3);
	EXPECT_THAT(value.bottom, 4);

	// 値を設定
	cProfile.SetProfileData(LTEXT("Test"), LTEXT("rcTest"), LTEXT("4,3,2,1"));

	// 読める
	EXPECT_THAT(cProfile.IOProfileData(LTEXT("Test"), LTEXT("rcTest"), value), IsTrue());

	// 値は変更される
	EXPECT_THAT(value.left, 4);
	EXPECT_THAT(value.top, 3);
	EXPECT_THAT(value.right, 2);
	EXPECT_THAT(value.bottom, 1);

	// 値を設定（足りない）
	cProfile.SetProfileData(LTEXT("Test"), LTEXT("rcTest"), LTEXT("109,108,107"));

	// 不完全な設定項目は読めない
	EXPECT_THAT(cProfile.IOProfileData(LTEXT("Test"), LTEXT("rcTest"), value), IsFalse());

	// 値は変更されない
	EXPECT_THAT(value.left, 4);
	EXPECT_THAT(value.top, 3);
	EXPECT_THAT(value.right, 2);
	EXPECT_THAT(value.bottom, 1);
}

/*!
 * @brief IOProfileDataSetのテスト
 */
TEST(CDataProfile, IOProfileDataSet001)
{
	CDataProfile cProfile;
	cProfile.SetReadingMode();

	StaticVector<SFilePath, 3, LPCWSTR> values{};

	// INIの有効要素数が指定されている場合、その要素数だけ読み込む
	cProfile.SetProfileData(LTEXT("Test"), LTEXT("_Entry_Counts"), LTEXT("2"));
	cProfile.SetProfileData(LTEXT("Test"), LTEXT("Entry[00]"), LTEXT("first"));
	cProfile.SetProfileData(LTEXT("Test"), LTEXT("Entry[01]"), LTEXT(""));
	cProfile.SetProfileData(LTEXT("Test"), LTEXT("Entry[02]"), LTEXT("ignored"));

	cProfile.IOProfileDataSet(LTEXT("Test"), LTEXT("Entry"), values);

	EXPECT_THAT(values.size(), Eq(2));
	EXPECT_THAT(values[0], StrEq(LTEXT("first")));
	EXPECT_THAT(values[1], StrEq(LTEXT("")));
}

/*!
 * @brief IOProfileDataSetのテスト
 */
TEST(CDataProfile, IOProfileDataSet002)
{
	CDataProfile cProfile;
	cProfile.SetReadingMode();

	StaticVector<SFilePath, 4, LPCWSTR> values{};

	// INIの有効要素数が配列サイズを超えている場合、配列サイズに補正する
	cProfile.SetProfileData(LTEXT("Test"), LTEXT("nEntryCount"), LTEXT("5"));
	cProfile.SetProfileData(LTEXT("Test"), LTEXT("Entry[00]"), LTEXT("first"));
	cProfile.SetProfileData(LTEXT("Test"), LTEXT("Entry[01]"), LTEXT("second"));
	cProfile.SetProfileData(LTEXT("Test"), LTEXT("Entry[02]"), LTEXT("third"));
	cProfile.SetProfileData(LTEXT("Test"), LTEXT("Entry[03]"), LTEXT("force"));

	cProfile.IOProfileDataSet(LTEXT("Test"), LTEXT("Entry"), values, LTEXT("nEntryCount"));

	EXPECT_THAT(values.size(), Eq(4));
	EXPECT_THAT(values[0], StrEq(LTEXT("first")));
	EXPECT_THAT(values[1], StrEq(LTEXT("second")));
	EXPECT_THAT(values[2], StrEq(LTEXT("third")));
	EXPECT_THAT(values[3], StrEq(LTEXT("force")));
}

/*!
 * @brief IOProfileDataSetのテスト
 */
TEST(CDataProfile, IOProfileDataSet003)
{
	CDataProfile cProfile;
	cProfile.SetReadingMode();

	StaticVector<SFilePath, 4, LPCWSTR> values{};

	// INIに有効要素数がない場合、末尾から見て最初に見付かった空ではない要素を最終要素とする
	cProfile.SetProfileData(LTEXT("Test"), LTEXT("Entry[00]"), LTEXT("first"));
	cProfile.SetProfileData(LTEXT("Test"), LTEXT("Entry[01]"), LTEXT("second"));

	cProfile.IOProfileDataSet(LTEXT("Test"), LTEXT("Entry"), values);

	EXPECT_THAT(values.size(), Eq(2));
	EXPECT_THAT(values[0], StrEq(LTEXT("first")));
	EXPECT_THAT(values[1], StrEq(LTEXT("second")));
}

/*!
 * @brief ShareData_IO_2のテスト
 *
 * INIファイルのバージョンが読めなかった場合、バックアップファイルを作成する仕様の確認
 */
TEST(ShareData_IO, ShareData_IO_2)
{
	constexpr std::array UTF8_BOM = { '\xEF', '\xBB', '\xBF' };

	const auto iniPath = GetIniFileName();
#if defined(_WIN32)
	const auto bakPath = std::filesystem::path{ iniPath.native() + LTEXT(".bak") };
#else
	auto bakPath = iniPath;	// Mac 版: path::native() は UTF-8 なので += で連結する（移植計画のステップ 21）
	bakPath += LTEXT(".bak");
	std::filesystem::create_directories(iniPath.parent_path());	// Mac 版: 設定フォルダーはまだ無いことがある
#endif

	// ファイル出力ストリームをバイナリモードで開く
	std::ofstream fos{ iniPath };

	// UTF-8 BOMを出力
	fos.write(UTF8_BOM.data(), UTF8_BOM.size());

	// 各行を書き込む
	fos << "[Other]" << std::endl;
	fos << "szVersion=1,2,3" << std::endl;

	fos.close();

	// 共有データを生成して初期化する
	window::TrayWndTestSuite::SetUpTrayWnd();

	// テスト対象を呼び出す
	CShareData_IO::LoadShareData();

	EXPECT_THAT(fexist(bakPath), IsTrue());

	// 共有データを破棄する
	window::TrayWndTestSuite::TearDownTrayWnd();

	std::error_code ec;
	std::filesystem::remove(bakPath, ec);
	std::filesystem::remove(iniPath, ec);
}

/*!
 * @brief ShareData_IO_ColorSetのテスト
 */
TEST(ShareData_IO, ShareData_IO_ColorSet)
{
	CDataProfile cProfile;
	cProfile.SetReadingMode();

	std::vector<ColorInfo> colorInfoArr{ size_t(COLORIDX_LAST) };

	// キャレット前景色がテキスト背景色と同じ
	cProfile.SetProfileData(LTEXT("Test"), LTEXT("C[TXT]"), LTEXT("1,1,000000,ffffff,1"));	// 黒文字、白背景
	cProfile.SetProfileData(LTEXT("Test"), LTEXT("C[CAR]"), LTEXT("1,1,ffffff,ff0000,1"));	// 白文字、赤背景

	ShareData_IO_ColorSet(cProfile, LTEXT("Test"), colorInfoArr);

	// キャレット前景色がテキスト文字色に変更される
	EXPECT_THAT(colorInfoArr[COLORIDX_CARET].m_sColorAttr.m_cTEXT, colorInfoArr[COLORIDX_TEXT].m_sColorAttr.m_cTEXT);
}

/*!
 * @brief ShareData_IO_KeyHelpArrのテスト
 */
TEST(ShareData_IO, ShareData_IO_KeyHelpArr)
{
	CDataProfile cProfile;
	cProfile.SetReadingMode();

	KeyHelpInfo KeyHelpArr[MAX_KEYHELP_FILE]{};
	int nKeyHelpNum = 0;

	cProfile.SetProfileData(LTEXT("Test"), LTEXT("KDct[00]"), LTEXT("0,about,path"));
	cProfile.SetProfileData(LTEXT("Test"), LTEXT("KDct[01]"), LTEXT("1,ABOUT,PATH"));

	ShareData_IO_KeyHelpArr(cProfile, LTEXT("Test"), KeyHelpArr, nKeyHelpNum);

	EXPECT_THAT(KeyHelpArr[0].m_bUse, IsFalse());
	EXPECT_THAT(KeyHelpArr[0].m_szAbout, StrEq(LTEXT("about")));
	EXPECT_THAT(KeyHelpArr[0].m_szPath, StrEq(LTEXT("path")));
	EXPECT_THAT(KeyHelpArr[1].m_bUse, IsTrue());
	EXPECT_THAT(KeyHelpArr[1].m_szAbout, StrEq(LTEXT("ABOUT")));
	EXPECT_THAT(KeyHelpArr[1].m_szPath, StrEq(LTEXT("PATH")));
	EXPECT_THAT(nKeyHelpNum, 2);

	// 旧バージョンサポート
	cProfile.SetProfileData(LTEXT("Test"), LTEXT("szKeyWordHelpFile"), LTEXT("szKeyWordHelpFile"));
	ShareData_IO_KeyHelpArr(cProfile, LTEXT("Test"), KeyHelpArr, nKeyHelpNum);
	EXPECT_THAT(KeyHelpArr[0].m_szPath, StrEq(LTEXT("szKeyWordHelpFile")));
	EXPECT_THAT(nKeyHelpNum, 1);
}

/*!
 * @brief ShareData_IO_LogFontのテスト
 */
TEST(ShareData_IO, ShareData_IO_LogFont)
{
	CDataProfile cProfile;
	cProfile.SetReadingMode();

	LOGFONT lf{};
	INT nPointSize = 0;

	// 設定項目がないと読めない
	ShareData_IO_LogFont(cProfile, LTEXT("Test"), LTEXT("lf"), lf, nPointSize);

	EXPECT_THAT(nPointSize, 0);
	EXPECT_THAT(lf.lfHeight, 0);

	// 値を設定
	cProfile.SetProfileData(LTEXT("Test"), LTEXT("nPointSize"), LTEXT("12"));

	// 複合項目なので、やっぱり読めない
	EXPECT_FALSE(ShareData_IO_LogFont(cProfile, LTEXT("Test"), LTEXT("lf"), lf, nPointSize));

	EXPECT_THAT(nPointSize, 12);
	EXPECT_THAT(lf.lfHeight, 0);

	// 不適切な値を設定（足りない）
	cProfile.SetProfileData(LTEXT("Test"), LTEXT("lf"), LTEXT("1,2,3,4,5,6,7,8,9,10,11,12"));

	// 項目が足りないので読めない
	EXPECT_FALSE(ShareData_IO_LogFont(cProfile, LTEXT("Test"), LTEXT("lf"), lf, nPointSize));

	// 値を設定
	cProfile.SetProfileData(LTEXT("Test"), LTEXT("lf"), LTEXT("1,2,3,4,5,6,7,8,9,10,11,12,13"));

	// 複合項目なので、やっぱり読めない
	EXPECT_FALSE(ShareData_IO_LogFont(cProfile, LTEXT("Test"), LTEXT("lf"), lf, nPointSize));

	EXPECT_THAT(nPointSize, 12);
	EXPECT_THAT(lf.lfHeight, 0);
	EXPECT_THAT(lf.lfFaceName[0], LCHAR('\0'));

	// 値を設定
	cProfile.SetProfileData(LTEXT("Test"), LTEXT("lfFaceName"), LTEXT("font name"));

	// 読める
	EXPECT_TRUE(ShareData_IO_LogFont(cProfile, LTEXT("Test"), LTEXT("lf"), lf, nPointSize));

	EXPECT_THAT(nPointSize,				12);
	EXPECT_THAT(lf.lfHeight,			-2);	// 補正が入るので入力値と異なる
	EXPECT_THAT(lf.lfWidth,				0x2);
	EXPECT_THAT(lf.lfEscapement,		0x3);
	EXPECT_THAT(lf.lfOrientation,		0x4);
	EXPECT_THAT(lf.lfWeight,			0x5);
	EXPECT_THAT(lf.lfItalic,			0x6);
	EXPECT_THAT(lf.lfUnderline,			0x7);
	EXPECT_THAT(lf.lfStrikeOut,			0x8);
	EXPECT_THAT(lf.lfCharSet,			0x9);
	EXPECT_THAT(lf.lfOutPrecision,		0xA);
	EXPECT_THAT(lf.lfClipPrecision,		0xB);
	EXPECT_THAT(lf.lfQuality,			0xC);
	EXPECT_THAT(lf.lfPitchAndFamily,	0xD);
	EXPECT_THAT(lf.lfFaceName,			StrEq(LTEXT("font name")));
}

/*!
 * @brief ShareData_IO_OutlineDockRectのテスト
 */
TEST(ShareData_IO, ShareData_IO_OutlineDockRect)
{
	CDataProfile cProfile;
	cProfile.SetReadingMode();

	CommonSetting_OutLine value = {};
	value.m_cxOutlineDockLeft	= 1;
	value.m_cyOutlineDockTop	= 2;
	value.m_cxOutlineDockRight	= 3;
	value.m_cyOutlineDockBottom	= 4;

	// 設定項目がないと読めない
	ShareData_IO_OutlineDockRect(cProfile, LTEXT("Test"), LTEXT("xyOutlineDock"), value);

	// 値は変更されない
	EXPECT_THAT(value.m_cxOutlineDockLeft, 1);
	EXPECT_THAT(value.m_cyOutlineDockTop, 2);
	EXPECT_THAT(value.m_cxOutlineDockRight, 3);
	EXPECT_THAT(value.m_cyOutlineDockBottom, 4);

	// 値を設定
	cProfile.SetProfileData(LTEXT("Test"), LTEXT("xyOutlineDock"), LTEXT("4,3,2,1"));

	// 読める
	ShareData_IO_OutlineDockRect(cProfile, LTEXT("Test"), LTEXT("xyOutlineDock"), value);

	// 値は変更される
	EXPECT_THAT(value.m_cxOutlineDockLeft, 4);
	EXPECT_THAT(value.m_cyOutlineDockTop, 3);
	EXPECT_THAT(value.m_cxOutlineDockRight, 2);
	EXPECT_THAT(value.m_cyOutlineDockBottom, 1);

	// 値を設定（足りない）
	cProfile.SetProfileData(LTEXT("Test"), LTEXT("xyOutlineDock"), LTEXT("109,108,107"));

	// 不完全な設定項目は読めない
	ShareData_IO_OutlineDockRect(cProfile, LTEXT("Test"), LTEXT("xyOutlineDock"), value);

	// 値は変更されない
	EXPECT_THAT(value.m_cxOutlineDockLeft, 4);
	EXPECT_THAT(value.m_cyOutlineDockTop, 3);
	EXPECT_THAT(value.m_cxOutlineDockRight, 2);
	EXPECT_THAT(value.m_cyOutlineDockBottom, 1);
}

/*!
 * @brief ShareData_IO_Printのテスト
 */
TEST(ShareData_IO, ShareData_IO_Print)
{
	CDataProfile cProfile;
	cProfile.SetReadingMode();

	cProfile.SetProfileData(LTEXT("Print"), LTEXT("PS[00].szHF[0]"), LTEXT("&f"));
	cProfile.SetProfileData(LTEXT("Print"), LTEXT("PS[00].szFTF[0]"), LTEXT("&C- &P -"));

	std::vector<PRINTSETTING> printSettings{ static_cast<size_t>(MAX_PRINTSETTINGARR) };

	ShareData_IO_Print(cProfile, printSettings);

	EXPECT_THAT(printSettings[0].m_szHeaderForm[0], StrEq(LTEXT("$f")));
	EXPECT_THAT(printSettings[0].m_szFooterForm[0], StrEq(LTEXT("")));
	EXPECT_THAT(printSettings[0].m_szFooterForm[1], StrEq(LTEXT("- $p -")));
}

/*!
 * @brief ShareData_IO_PrintIntsのテスト
 */
TEST(ShareData_IO, ShareData_IO_PrintInts)
{
	CDataProfile cProfile;
	cProfile.SetReadingMode();

	PRINTSETTING printSetting{};

	// テスト用に初期値を入れる
	printSetting.m_nPrintFontWidth			= 0;
	printSetting.m_nPrintFontHeight			= 0;
	printSetting.m_nPrintDansuu				= 0;
	printSetting.m_nPrintDanSpace			= 0;
	printSetting.m_nPrintLineSpacing		= 0;
	printSetting.m_nPrintMarginTY			= 0;
	printSetting.m_nPrintMarginBY			= 0;
	printSetting.m_nPrintMarginLX			= 0;
	printSetting.m_nPrintMarginRX			= 0;
	printSetting.m_nPrintPaperOrientation	= 0;
	printSetting.m_nPrintPaperSize			= 0;
	printSetting.m_bPrintWordWrap			= false;
	printSetting.m_bPrintLineNumber			= true;
	printSetting.m_bHeaderUse[0]			= FALSE;
	printSetting.m_bHeaderUse[1]			= TRUE;
	printSetting.m_bHeaderUse[2]			= FALSE;
	printSetting.m_bFooterUse[0]			= TRUE;
	printSetting.m_bFooterUse[1]			= FALSE;
	printSetting.m_bFooterUse[2]			= TRUE;

	// 設定項目がないと読めない
	EXPECT_FALSE(ShareData_IO_PrintInts(cProfile, LTEXT("Test"), LTEXT("PS[00].nInts"), printSetting));

	EXPECT_THAT(printSetting.m_nPrintFontWidth,			0);
	EXPECT_THAT(printSetting.m_nPrintFontHeight,		0);
	EXPECT_THAT(printSetting.m_nPrintDansuu,			0);
	EXPECT_THAT(printSetting.m_nPrintDanSpace,			0);
	EXPECT_THAT(printSetting.m_nPrintLineSpacing,		0);
	EXPECT_THAT(printSetting.m_nPrintMarginTY,			0);
	EXPECT_THAT(printSetting.m_nPrintMarginBY,			0);
	EXPECT_THAT(printSetting.m_nPrintMarginLX,			0);
	EXPECT_THAT(printSetting.m_nPrintMarginRX,			0);
	EXPECT_THAT(printSetting.m_nPrintPaperOrientation,	0);
	EXPECT_THAT(printSetting.m_nPrintPaperSize,			0);
	EXPECT_THAT(printSetting.m_bPrintWordWrap,			IsFalse());
	EXPECT_THAT(printSetting.m_bPrintLineNumber,		IsTrue());
	EXPECT_THAT(printSetting.m_bHeaderUse[0],			IsFalse());
	EXPECT_THAT(printSetting.m_bHeaderUse[1],			IsTrue());
	EXPECT_THAT(printSetting.m_bHeaderUse[2],			IsFalse());
	EXPECT_THAT(printSetting.m_bFooterUse[0],			IsTrue());
	EXPECT_THAT(printSetting.m_bFooterUse[1],			IsFalse());
	EXPECT_THAT(printSetting.m_bFooterUse[2],			IsTrue());

	// 値を設定(18個指定で失敗させる)
	cProfile.SetProfileData(LTEXT("Test"), LTEXT("PS[00].nInts"), LTEXT("1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18"));

	// 項目足りないので、読めない
	EXPECT_FALSE(ShareData_IO_PrintInts(cProfile, LTEXT("Test"), LTEXT("PS[00].nInts"), printSetting));

	EXPECT_THAT(printSetting.m_nPrintFontWidth,			0);
	EXPECT_THAT(printSetting.m_nPrintFontHeight,		0);
	EXPECT_THAT(printSetting.m_nPrintDansuu,			0);
	EXPECT_THAT(printSetting.m_nPrintDanSpace,			0);
	EXPECT_THAT(printSetting.m_nPrintLineSpacing,		0);
	EXPECT_THAT(printSetting.m_nPrintMarginTY,			0);
	EXPECT_THAT(printSetting.m_nPrintMarginBY,			0);
	EXPECT_THAT(printSetting.m_nPrintMarginLX,			0);
	EXPECT_THAT(printSetting.m_nPrintMarginRX,			0);
	EXPECT_THAT(printSetting.m_nPrintPaperOrientation,	0);
	EXPECT_THAT(printSetting.m_nPrintPaperSize,			0);
	EXPECT_THAT(printSetting.m_bPrintWordWrap,			IsFalse());
	EXPECT_THAT(printSetting.m_bPrintLineNumber,		IsTrue());
	EXPECT_THAT(printSetting.m_bHeaderUse[0],			IsFalse());
	EXPECT_THAT(printSetting.m_bHeaderUse[1],			IsTrue());
	EXPECT_THAT(printSetting.m_bHeaderUse[2],			IsFalse());
	EXPECT_THAT(printSetting.m_bFooterUse[0],			IsTrue());
	EXPECT_THAT(printSetting.m_bFooterUse[1],			IsFalse());
	EXPECT_THAT(printSetting.m_bFooterUse[2],			IsTrue());

	// 値を設定
	cProfile.SetProfileData(LTEXT("Test"), LTEXT("PS[00].nInts"), LTEXT("1,2,3,4,5,6,7,8,9,10,11,1,0,1,0,1,0,1,0"));

	// 値が揃ったので読める
	EXPECT_TRUE(ShareData_IO_PrintInts(cProfile, LTEXT("Test"), LTEXT("PS[00].nInts"), printSetting));

	EXPECT_THAT(printSetting.m_nPrintFontWidth,			0x1);
	EXPECT_THAT(printSetting.m_nPrintFontHeight,		0x2);
	EXPECT_THAT(printSetting.m_nPrintDansuu,			0x3);
	EXPECT_THAT(printSetting.m_nPrintDanSpace,			0x4);
	EXPECT_THAT(printSetting.m_nPrintLineSpacing,		0x5);
	EXPECT_THAT(printSetting.m_nPrintMarginTY,			0x6);
	EXPECT_THAT(printSetting.m_nPrintMarginBY,			0x7);
	EXPECT_THAT(printSetting.m_nPrintMarginLX,			0x8);
	EXPECT_THAT(printSetting.m_nPrintMarginRX,			0x9);
	EXPECT_THAT(printSetting.m_nPrintPaperOrientation,	0xA);
	EXPECT_THAT(printSetting.m_nPrintPaperSize,			0xB);
	EXPECT_THAT(printSetting.m_bPrintWordWrap,			IsTrue());
	EXPECT_THAT(printSetting.m_bPrintLineNumber,		IsFalse());
	EXPECT_THAT(printSetting.m_bHeaderUse[0],			IsTrue());
	EXPECT_THAT(printSetting.m_bHeaderUse[1],			IsFalse());
	EXPECT_THAT(printSetting.m_bHeaderUse[2],			IsTrue());
	EXPECT_THAT(printSetting.m_bFooterUse[0],			IsFalse());
	EXPECT_THAT(printSetting.m_bFooterUse[1],			IsTrue());
	EXPECT_THAT(printSetting.m_bFooterUse[2],			IsFalse());
}

/*!
 * @brief ShareData_IO_Pluginのテスト
 */
TEST(ShareData_IO, ShareData_IO_Plugin)
{
	CDataProfile cProfile;
	cProfile.SetWritingMode();

	CommonSetting_Plugin sPlugin{};
	::wcscpy_s(sPlugin.m_PluginTable[0].m_szName, LTEXT("test name"));
	::wcscpy_s(sPlugin.m_PluginTable[0].m_szId, LTEXT("test id"));
	sPlugin.m_PluginTable[0].m_state = EPluginState::PLS_DELETED;
	sPlugin.m_PluginTable[0].m_nCmdNum = 2;

	// 共有データを生成して初期化する
	window::TrayWndTestSuite::SetUpTrayWnd();

	auto pcMenuDrawer = std::make_unique<CMenuDrawer>();

	// 削除機能の確認
	ShareData_IO_Plugin(cProfile, pcMenuDrawer.get(), sPlugin);

	EXPECT_THAT(sPlugin.m_PluginTable[0].m_szName, StrEq(LTEXT("")));
	EXPECT_THAT(sPlugin.m_PluginTable[0].m_szId, StrEq(LTEXT("")));

	pcMenuDrawer = nullptr;

	// 共有データを破棄する
	window::TrayWndTestSuite::TearDownTrayWnd();
}

/*!
 * @brief ShareData_IO_RegexKeywordのテスト
 */
TEST(ShareData_IO, ShareData_IO_RegexKeyword)
{
	CDataProfile cProfile;
	cProfile.SetReadingMode();

	const auto pType = std::make_unique<STypeConfig>();
	auto& type = *pType;

	// テスト用に初期値を入れる
	type.m_bUseRegexKeyword		= true;

	// 設定項目がないと読めない
	ShareData_IO_RegexKeyword(cProfile, LTEXT("Test"), type);

	// 値は変更されない
	EXPECT_THAT(type.m_bUseRegexKeyword, IsTrue());

	// 値を設定
	cProfile.SetProfileData(LTEXT("Test"), LTEXT("bUseRegexKeyword"), LTEXT("0"));
	cProfile.SetProfileData(LTEXT("Test"), LTEXT("RxKey[000]"), sakura::format(LTEXT("{},{}"), int(COLORIDX_LAST), LTEXT("patten")));
	cProfile.SetProfileData(LTEXT("Test"), LTEXT("RxKey[001]"), sakura::format(LTEXT("{},{}"), sakura::wstring(20, LCHAR('c')), LTEXT("patten")));
	cProfile.SetProfileData(LTEXT("Test"), LTEXT("RxKey[002]"), sakura::format(LTEXT("{},{}"), LTEXT("TXT"), LTEXT("patten")));

	// 設定項目があれば読める
	ShareData_IO_RegexKeyword(cProfile, LTEXT("Test"), type);

	// 値は反映される
	EXPECT_THAT(type.m_bUseRegexKeyword, IsFalse());
	EXPECT_THAT(type.m_RegexKeywordArr[0].m_nColorIndex, Eq<int>(COLORIDX_REGEX1));
	EXPECT_THAT(type.m_RegexKeywordArr[1].m_nColorIndex, Eq<int>(COLORIDX_REGEX1));
	EXPECT_THAT(type.m_RegexKeywordArr[2].m_nColorIndex, Eq<int>(COLORIDX_TEXT));
}

/*!
 * @brief ShareData_IO_TypeIntsのテスト
 */
TEST(ShareData_IO, ShareData_IO_TypeInts)
{
	CDataProfile cProfile;
	cProfile.SetReadingMode();

	const auto pType = std::make_unique<STypeConfig>();
	auto& type = *pType;

	// テスト用に初期値を入れる
	type.m_nIdx					= 0;
	type.m_nMaxLineKetas		= 0;
	type.m_nColumnSpace			= 0;
	type.m_nTabSpace			= 0;
	type.m_nKeyWordSetIdx[0]	= 0;
	type.m_nKeyWordSetIdx[1]	= 0;
	type.m_nStringType			= 0;
	type.m_bLineNumIsCRLF		= false;
	type.m_nLineTermType		= 0;
	type.m_bWordWrap			= false;
	type.m_nCurrentPrintSetting	= 0;
	type.m_nTsvMode				= 0;

	// 設定項目がないと読めない
	ShareData_IO_TypeInts(cProfile, LTEXT("Test"), type);

	EXPECT_THAT(type.m_nIdx,					0);
	EXPECT_THAT(type.m_nMaxLineKetas,			0);
	EXPECT_THAT(type.m_nColumnSpace,			0);
	EXPECT_THAT(type.m_nTabSpace,				0);
	EXPECT_THAT(type.m_nKeyWordSetIdx[0],		0);
	EXPECT_THAT(type.m_nKeyWordSetIdx[1],		0);
	EXPECT_THAT(type.m_nStringType,				0);
	EXPECT_THAT(type.m_bLineNumIsCRLF,			IsFalse());
	EXPECT_THAT(type.m_nLineTermType,			0);
	EXPECT_THAT(type.m_bWordWrap,				IsFalse());
	EXPECT_THAT(type.m_nCurrentPrintSetting,	0);
	EXPECT_THAT(type.m_nTsvMode,				0);

	// 値を設定(11個指定で失敗させる)
	cProfile.SetProfileData(LTEXT("Test"), LTEXT("nInts"), LTEXT("1,2,3,4,5,6,7,1,9,1,11"));

	// 項目足りないので、読めない
	ShareData_IO_TypeInts(cProfile, LTEXT("Test"), type);

	EXPECT_THAT(type.m_nIdx,					0);
	EXPECT_THAT(type.m_nMaxLineKetas,			0);
	EXPECT_THAT(type.m_nColumnSpace,			0);
	EXPECT_THAT(type.m_nTabSpace,				0);
	EXPECT_THAT(type.m_nKeyWordSetIdx[0],		0);
	EXPECT_THAT(type.m_nKeyWordSetIdx[1],		0);
	EXPECT_THAT(type.m_nStringType,				0);
	EXPECT_THAT(type.m_bLineNumIsCRLF,			IsFalse());
	EXPECT_THAT(type.m_nLineTermType,			0);
	EXPECT_THAT(type.m_bWordWrap,				IsFalse());
	EXPECT_THAT(type.m_nCurrentPrintSetting,	0);
	EXPECT_THAT(type.m_nTsvMode,				0);

	// 値を設定
	cProfile.SetProfileData(LTEXT("Test"), LTEXT("nInts"), LTEXT("1,2,3,4,5,6,7,1,9,1,11,12"));

	// 値が揃ったので読める
	ShareData_IO_TypeInts(cProfile, LTEXT("Test"), type);

	EXPECT_THAT(type.m_nIdx,					1);
	EXPECT_THAT(type.m_nMaxLineKetas,			10);
	EXPECT_THAT(type.m_nColumnSpace,			3);
	EXPECT_THAT(type.m_nTabSpace,				4);
	EXPECT_THAT(type.m_nKeyWordSetIdx[0],		5);
	EXPECT_THAT(type.m_nKeyWordSetIdx[1],		6);
	EXPECT_THAT(type.m_nStringType,				7);
	EXPECT_THAT(type.m_bLineNumIsCRLF,			IsTrue());
	EXPECT_THAT(type.m_nLineTermType,			9);
	EXPECT_THAT(type.m_bWordWrap,				IsTrue());
	EXPECT_THAT(type.m_nCurrentPrintSetting,	11);
	EXPECT_THAT(type.m_nTsvMode,				12);
}

/*!
 * @brief ShareData_IO_VertLineIdxのテスト
 */
TEST(ShareData_IO, ShareData_IO_VertLineIdx)
{
	CDataProfile cProfile;
	cProfile.SetReadingMode();

	CKetaXInt nVertLineIdx[MAX_VERTLINES]{};

	// 設定項目がないと読めない
	ShareData_IO_VertLineIdx(cProfile, LTEXT("Test"), nVertLineIdx);

	// 値を設定
	cProfile.SetProfileData(LTEXT("Test"), LTEXT("nVertLineIdx1"), LTEXT("20"));

	ShareData_IO_VertLineIdx(cProfile, LTEXT("Test"), nVertLineIdx);

	EXPECT_THAT(nVertLineIdx[0], 20);
}
