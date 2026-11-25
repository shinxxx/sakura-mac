/*! @file */
/*
	Copyright (C) 2026, Sakura Editor Organization

	SPDX-License-Identifier: Zlib
*/
#include "pch.h"
#include "grep/CGrepEnumKeys.h"
#include "grep/CGrepEnumFiles.h"
#include "grep/CGrepEnumFilterFiles.h"
#if defined(_WIN32)
#include "grep/GrepTestSuite.hpp"	// grep_test::TempFolder
#else
#include "mac-grep-temp-folder.hpp"	// Mac 版: grep_test::TempFolder(GrepTestSuite.hpp は編集ウィンドウを使う。移植計画のステップ 43)
#endif

#include <algorithm>
#include <string>
#include <string_view>
#include <vector>

/*
	除外ファイルの正規表現のテスト

	CGrepEnumKeys: 除外ファイル(正規表現)のキーの振り分けと照合関数
	CGrepEnumFilterFiles: 照合関数による列挙の除外
	CGrepExceptFileRegexps: 正規表現の照合器

	コマンドライン・ダイアログからの実行のテストは、Grep の実行基盤(GrepTestSuite)を使うので
	test-grep-cmdline.cpp・test-grep-dialog.cpp に置く。

	注意: 引用符を含む生文字列はマクロの引数に書かない(MSVC の従来のプリプロセッサーで C2017 やマクロ引数の分割が起きる)。
	変数に入れてからマクロに渡す。区切りの「,」を含む文字列も同様に変数に入れる。
*/

using ::testing::ElementsAre;	// pch.h に using が無いのでここで宣言する

namespace {

using grep_test::TempFolder;

//! 列挙結果の名前を昇順(符号単位)で返す
std::vector<sakura::wstring> Names(const CGrepEnumFileBase& items)
{
	std::vector<sakura::wstring> names;
	for (int i = 0; i < items.GetCount(); ++i) {
		names.emplace_back(items.GetFileName(i));
	}
	std::ranges::sort(names);
	return names;
}

} // namespace

// ---------------------------------------------------------------------------
// キーの振り分け(CGrepEnumKeys)
// ---------------------------------------------------------------------------

/*!
	@brief 正規表現モードでは除外ファイル(!)が正規表現の配列に振り分けられること
*/
TEST(CGrepEnumKeysExceptRegex, Classify)
{
	CGrepEnumKeys keys;
	ASSERT_THAT(keys.SetFileKeys(LTEXT(R"(*.cpp;!^[^.]+$;!\.bak$;#obj)"), true), Eq(0));

	EXPECT_THAT(keys.m_vecSearchFileKeys, ElementsAre(LTEXT("*.cpp")));
	EXPECT_THAT(keys.m_vecExceptFileRegexKeys, ElementsAre(LTEXT("^[^.]+$"), LTEXT(R"(\.bak$)")));
	EXPECT_THAT(keys.m_vecExceptFileKeys, IsEmpty());
	EXPECT_THAT(keys.m_vecExceptAbsFileKeys, IsEmpty());
	EXPECT_THAT(keys.m_vecExceptFolderKeys, ElementsAre(LTEXT("obj")));
}

/*!
	@brief 正規表現モードではパスとしての検査をしないこと
*/
TEST(CGrepEnumKeysExceptRegex, SkipsPathValidation)
{
	CGrepEnumKeys keys;
	// ワイルドカードとして扱うと、フォルダー部分に * があるのでエラー
	EXPECT_THAT(keys.SetFileKeys(LTEXT(R"(!.*\.txt$)")), Eq(1));
	// 正規表現として扱うときはエラーにならない。絶対パスに見えるものも正規表現として扱う
	EXPECT_THAT(keys.SetFileKeys(LTEXT(R"(!.*\.txt$;!C:\a$)"), true), Eq(0));
	EXPECT_THAT(keys.m_vecExceptFileRegexKeys, ElementsAre(LTEXT(R"(.*\.txt$)"), LTEXT(R"(C:\a$)")));
	EXPECT_THAT(keys.m_vecExceptAbsFileKeys, IsEmpty());
}

/*!
	@brief 空の正規表現は入れないこと(すべてのファイルが除外されるのを防ぐ)
*/
TEST(CGrepEnumKeysExceptRegex, IgnoresEmpty)
{
	CGrepEnumKeys keys;
	ASSERT_THAT(keys.SetFileKeys(LTEXT("*.cpp;!"), true), Eq(0));
	EXPECT_THAT(keys.m_vecExceptFileRegexKeys, IsEmpty());
}

/*!
	@brief SetFileKeys() を呼び直すと、正規表現と照合関数がクリアされること
*/
TEST(CGrepEnumKeysExceptRegex, ClearsOnReentry)
{
	CGrepEnumKeys keys;
	ASSERT_THAT(keys.SetFileKeys(LTEXT("!^a$"), true), Eq(0));
	keys.m_fnIsExceptFilePath = [](sakura::wstring_view) { return true; };

	ASSERT_THAT(keys.SetFileKeys(LTEXT("*.cpp")), Eq(0));
	EXPECT_THAT(keys.m_vecExceptFileRegexKeys, IsEmpty());
	EXPECT_THAT(keys.IsExceptFilePath(LTEXT("a")), IsFalse());
}

/*!
	@brief 除外ファイルの一覧(結果の先頭に表示するもの)に正規表現も含まれること
*/
TEST(CGrepEnumKeysExceptRegex, GetExcludeFilesIncludesRegex)
{
	CGrepEnumKeys keys;
	ASSERT_THAT(keys.SetFileKeys(LTEXT("!^a$;!^b$"), true), Eq(0));
	EXPECT_THAT(keys.GetExcludeFiles(), ElementsAre(LTEXT("^a$"), LTEXT("^b$")));
}

/*!
	@brief 照合関数が未設定なら一致しない扱い、設定されていればその結果になること
*/
TEST(CGrepEnumKeysExceptRegex, IsExceptFilePath)
{
	const sakura::wstring readme = LTEXT(R"(C:\work\README)");
	const sakura::wstring text = LTEXT(R"(C:\work\a.txt)");

	CGrepEnumKeys keys;
	EXPECT_THAT(keys.IsExceptFilePath(readme), IsFalse());

	keys.m_fnIsExceptFilePath = [&readme](sakura::wstring_view filePath) { return filePath == readme; };
	EXPECT_THAT(keys.IsExceptFilePath(readme), IsTrue());
	EXPECT_THAT(keys.IsExceptFilePath(text), IsFalse());
}

/*!
	@brief 正規表現モードでなければ、除外ファイルは従来どおりワイルドカードとして振り分けられること
*/
TEST(CGrepEnumKeysExceptRegex, OffKeepsWildcard)
{
	CGrepEnumKeys keys;
	ASSERT_THAT(keys.SetFileKeys(LTEXT("!*.bak")), Eq(0));
	EXPECT_THAT(keys.m_vecExceptFileKeys, ElementsAre(LTEXT("*.bak")));
	EXPECT_THAT(keys.m_vecExceptFileRegexKeys, IsEmpty());
}

/*!
	@brief 同じ正規表現は 1 つにまとめられること
*/
TEST(CGrepEnumKeysExceptRegex, Unique)
{
	CGrepEnumKeys keys;
	ASSERT_THAT(keys.SetFileKeys(LTEXT("!^a$;!^a$"), true), Eq(0));
	EXPECT_THAT(keys.m_vecExceptFileRegexKeys, ElementsAre(LTEXT("^a$")));
}

/*!
	@brief 区切り文字(空白・;・,)を含む正規表現は引用符で囲めば分割されないこと
*/
TEST(CGrepEnumKeysExceptRegex, QuotedDelimiters)
{
	const sakura::wstring pattern = LTEXT(R"(!"^a b$";!"\d{2,4}";!"a;b")");	// 引用符を含むのでマクロの外で作る
	const sakura::wstring digits = LTEXT(R"(\d{2,4})");

	CGrepEnumKeys keys;
	ASSERT_THAT(keys.SetFileKeys(pattern.c_str(), true), Eq(0));
	EXPECT_THAT(keys.m_vecExceptFileRegexKeys, ElementsAre(LTEXT("^a b$"), digits, LTEXT("a;b")));
}

/*!
	@brief 引用符で囲まない「,」では分割されること(引用符が必要なことの確認)
*/
TEST(CGrepEnumKeysExceptRegex, UnquotedCommaSplits)
{
	const sakura::wstring pattern = LTEXT(R"(!\d{2,4})");	// 「,」を含むのでマクロの外で作る

	CGrepEnumKeys keys;
	ASSERT_THAT(keys.SetFileKeys(pattern.c_str(), true), Eq(0));
	EXPECT_THAT(keys.m_vecExceptFileRegexKeys, ElementsAre(LTEXT(R"(\d{2)")));
	EXPECT_THAT(keys.m_vecSearchFileKeys, ElementsAre(LTEXT("4}")));
}

/*!
	@brief 正規表現モードでも、除外フォルダーと検索対象の検査は従来どおりであること
*/
TEST(CGrepEnumKeysExceptRegex, OtherRulesUnchanged)
{
	CGrepEnumKeys keys;
	EXPECT_THAT(keys.SetFileKeys(LTEXT(R"(#a*\b)"), true), Eq(1));
	EXPECT_THAT(keys.SetFileKeys(LTEXT(R"(sub*\a.txt)"), true), Eq(1));
#if defined(_WIN32)
	EXPECT_THAT(keys.SetFileKeys(LTEXT(R"(C:\x\*.txt)"), true), Eq(2));
#else
	EXPECT_THAT(keys.SetFileKeys(LTEXT("/x/*.txt"), true), Eq(2));	// Mac 版: 絶対パスは '/' から
#endif
}

/*!
	@brief 先頭の「!」を 1 つだけ取り除き、残りはそのまま正規表現になること
*/
TEST(CGrepEnumKeysExceptRegex, PrefixCharsInPattern)
{
	CGrepEnumKeys keys;
	ASSERT_THAT(keys.SetFileKeys(LTEXT("!!x;!#y"), true), Eq(0));
	EXPECT_THAT(keys.m_vecExceptFileRegexKeys, ElementsAre(LTEXT("!x"), LTEXT("#y")));
	EXPECT_THAT(keys.m_vecExceptFolderKeys, IsEmpty());
}

/*!
	@brief 除外ファイルしか指定しないとき、検索対象は既定の「*.*」になること
*/
TEST(CGrepEnumKeysExceptRegex, OnlyExcludes)
{
	CGrepEnumKeys keys;
	ASSERT_THAT(keys.SetFileKeys(LTEXT("!^a$"), true), Eq(0));
	EXPECT_THAT(keys.m_vecSearchFileKeys, ElementsAre(LTEXT("*.*")));
}

// ---------------------------------------------------------------------------
// 照合関数のフック(CGrepEnumFilterFiles)
// ---------------------------------------------------------------------------

/*!
	@brief 照合関数に一致したファイルが列挙から除かれること。照合関数が無ければすべて列挙されること
*/
TEST(CGrepEnumFilterFilesExceptRegex, ExceptByFilePathMatcher)
{
	TempFolder folder;
	for (const auto name : { LTEXT("a.txt"), LTEXT("b.log"), LTEXT("README") }) {
		folder.AddFile(name, "x");
	}

	CGrepEnumKeys keys;
	ASSERT_THAT(keys.SetFileKeys(LTEXT("*"), true), Eq(0));
	{
		CGrepEnumFilterFiles files;
		CGrepEnumFiles absExcept;
		files.Enumerates(folder.Path().c_str(), keys, CGrepEnumOptions(), absExcept);
		EXPECT_THAT(Names(files), ElementsAre(LTEXT("README"), LTEXT("a.txt"), LTEXT("b.log")));
	}

	const sakura::wstring readme = (folder.Path() / LTEXT("README")).wstring();
	keys.m_fnIsExceptFilePath = [&readme](sakura::wstring_view filePath) { return filePath == readme; };
	{
		CGrepEnumFilterFiles files;
		CGrepEnumFiles absExcept;
		files.Enumerates(folder.Path().c_str(), keys, CGrepEnumOptions(), absExcept);
		EXPECT_THAT(Names(files), ElementsAre(LTEXT("a.txt"), LTEXT("b.log")));
	}
}

/*!
	@brief 照合関数にはフルパス(キーのフォルダー部分を含む)が渡されること
*/
TEST(CGrepEnumFilterFilesExceptRegex, MatcherGetsFullPath)
{
	TempFolder folder;
#if defined(_WIN32)
	folder.AddFile(LTEXT(R"(sub\x.txt)"), "x");

	CGrepEnumKeys keys;
	ASSERT_THAT(keys.SetFileKeys(LTEXT(R"(sub\*.txt)"), true), Eq(0));
#else
	// Mac 版: パスの区切りは '/'
	folder.AddFile(LTEXT("sub/x.txt"), "x");

	CGrepEnumKeys keys;
	ASSERT_THAT(keys.SetFileKeys(LTEXT("sub/*.txt"), true), Eq(0));
#endif
	std::vector<sakura::wstring> calledPaths;
	keys.m_fnIsExceptFilePath = [&calledPaths](sakura::wstring_view filePath) {
		calledPaths.emplace_back(filePath);
		return true;
	};

	CGrepEnumFilterFiles files;
	CGrepEnumFiles absExcept;
	files.Enumerates(folder.Path().c_str(), keys, CGrepEnumOptions(), absExcept);
#if defined(_WIN32)
	const sakura::wstring expected = (folder.Path() / LTEXT(R"(sub\x.txt)")).wstring();
#else
	const sakura::wstring expected = (folder.Path() / LTEXT("sub/x.txt")).wstring();
#endif
	EXPECT_THAT(calledPaths, ElementsAre(expected));
	EXPECT_THAT(files.GetCount(), Eq(0));
}

/*!
	@brief フォルダーには照合関数が呼ばれないこと
*/
TEST(CGrepEnumFilterFilesExceptRegex, MatcherNotCalledForFolders)
{
	TempFolder folder;
	folder.AddFolder(LTEXT("d"));
	folder.AddFile(LTEXT("f"), "x");

	CGrepEnumKeys keys;
	ASSERT_THAT(keys.SetFileKeys(LTEXT("*"), true), Eq(0));
	std::vector<sakura::wstring> calledPaths;
	keys.m_fnIsExceptFilePath = [&calledPaths](sakura::wstring_view filePath) {
		calledPaths.emplace_back(filePath);
		return false;
	};

	CGrepEnumFilterFiles files;
	CGrepEnumFiles absExcept;
	files.Enumerates(folder.Path().c_str(), keys, CGrepEnumOptions(), absExcept);
	const sakura::wstring expected = (folder.Path() / LTEXT("f")).wstring();
	EXPECT_THAT(calledPaths, ElementsAre(expected));
}
