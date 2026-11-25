/*! @file */
/*
	Copyright (C) 2026, Sakura Editor Organization

	SPDX-License-Identifier: Zlib
*/
#include "pch.h"
#include "grep/CGrepEnumKeys.h"

//! 絶対パスの例(Mac 版は '/' から始まるパス。移植計画のステップ 43)
#if defined(_WIN32)
#define WORK_DIR "C:\\work\\"
#else
#define WORK_DIR "/work/"
#endif

/*!
	@brief 解析結果を std::wstring の配列に変換する

	VGrepEnumKeys の要素型に依存せず比較できるようにするためのヘルパー。
*/
static std::vector<sakura::wstring> ToStrings(const VGrepEnumKeys& keys)
{
	return std::vector<sakura::wstring>(keys.cbegin(), keys.cend());
}

/*!
	@brief 区切り文字(空白・セミコロン・カンマ)でパターンが分割されること
*/
TEST(CGrepEnumKeys, SplitPattern_Delimiters)
{
	const auto patterns = CGrepEnumKeys::SplitPattern(LTEXT("*.cpp *.h;*.txt,*.md"));
	EXPECT_THAT(patterns, Eq(std::vector<sakura::wstring>({ LTEXT("*.cpp"), LTEXT("*.h"), LTEXT("*.txt"), LTEXT("*.md") })));
}

/*!
	@brief 引用符が取り除かれ、引用符内の区切り文字が無視されること
*/
TEST(CGrepEnumKeys, SplitPattern_DoubleQuotes)
{
	const auto patterns = CGrepEnumKeys::SplitPattern(LTEXT("\"a b;c.txt\";*.h"));
	EXPECT_THAT(patterns, Eq(std::vector<sakura::wstring>({ LTEXT("a b;c.txt"), LTEXT("*.h") })));
}

/*!
	@brief 空文字列を渡すと空の配列が返ること
*/
TEST(CGrepEnumKeys, SplitPattern_Empty)
{
	const auto patterns = CGrepEnumKeys::SplitPattern(LTEXT(""));
	EXPECT_THAT(patterns.empty(), IsTrue());
}

/*!
	@brief 区切り文字だけを渡すと空の配列が返ること
*/
TEST(CGrepEnumKeys, SplitPattern_DelimitersOnly)
{
	const auto patterns = CGrepEnumKeys::SplitPattern(LTEXT(" ;,"));
	EXPECT_THAT(patterns.empty(), IsTrue());
}

/*!
	@brief 引用符が閉じられていない場合、以降が1つのトークンとして扱われること

	引用符の中では区切り文字を無視するため、閉じ忘れると末尾まで
	1トークンになる。現在の挙動を追認するテスト。
*/
TEST(CGrepEnumKeys, SplitPattern_UnclosedDoubleQuote)
{
	const auto patterns = CGrepEnumKeys::SplitPattern(LTEXT("\"*.cpp;*.h"));
	EXPECT_THAT(patterns, Eq(std::vector<sakura::wstring>({ LTEXT("*.cpp;*.h") })));
}

/*!
	@brief トークンの途中の引用符でも内外が切り替わること

	a"b c"d は1つの要素になり、引用符を取り除くと ab cd になる。
*/
TEST(CGrepEnumKeys, SplitPattern_QuoteInsideToken)
{
	const auto patterns = CGrepEnumKeys::SplitPattern(LTEXT("a\"b c\"d;*.h"));
	EXPECT_THAT(patterns, Eq(std::vector<sakura::wstring>({ LTEXT("ab cd"), LTEXT("*.h") })));
}

/*!
	@brief 引用符を残したまま区切り文字で分割されること
*/
TEST(CGrepEnumKeys, SplitPatternKeepQuotes_KeepsQuotes)
{
	const auto patterns = CGrepEnumKeys::SplitPatternKeepQuotes(LTEXT("\"a,b.txt\" *.h;a\"b c\"d,\"x y\""));
	EXPECT_THAT(patterns, Eq(std::vector<sakura::wstring_view>({ LTEXT("\"a,b.txt\""), LTEXT("*.h"), LTEXT("a\"b c\"d"), LTEXT("\"x y\"") })));
}

/*!
	@brief 空文字列・区切り文字だけの場合に空の配列が返ること
*/
TEST(CGrepEnumKeys, SplitPatternKeepQuotes_Empty)
{
	EXPECT_THAT(CGrepEnumKeys::SplitPatternKeepQuotes(LTEXT("")).empty(), IsTrue());
	EXPECT_THAT(CGrepEnumKeys::SplitPatternKeepQuotes(LTEXT(" ;, ;")).empty(), IsTrue());
}

/*!
	@brief 引用符の閉じ忘れを判定できること
*/
TEST(CGrepEnumKeys, HasUnclosedQuote)
{
	EXPECT_THAT(CGrepEnumKeys::HasUnclosedQuote(LTEXT("")), IsFalse());
	EXPECT_THAT(CGrepEnumKeys::HasUnclosedQuote(LTEXT("*.cpp;*.h")), IsFalse());
	EXPECT_THAT(CGrepEnumKeys::HasUnclosedQuote(LTEXT("\"a,b.txt\";\"x y\"")), IsFalse());
	EXPECT_THAT(CGrepEnumKeys::HasUnclosedQuote(LTEXT("\"a,b.txt")), IsTrue());
	EXPECT_THAT(CGrepEnumKeys::HasUnclosedQuote(LTEXT("\"a\" \"b")), IsTrue());
}

/*!
	@brief 検索パターン省略時に既定のワイルドカードが補われること
*/
TEST(CGrepEnumKeys, SetFileKeys_DefaultWildcard)
{
	CGrepEnumKeys keys;
	EXPECT_THAT(keys.SetFileKeys(LTEXT("")), Eq(0));
	EXPECT_THAT(ToStrings(keys.m_vecSearchFileKeys), Eq(std::vector<sakura::wstring>({ LTEXT("*.*") })));
	EXPECT_THAT(ToStrings(keys.m_vecSearchFolderKeys), Eq(std::vector<sakura::wstring>({ LTEXT("*.*") })));
}

/*!
	@brief 接頭辞(なし・!・#)でパターンが振り分けられること
*/
TEST(CGrepEnumKeys, SetFileKeys_Classify)
{
	CGrepEnumKeys keys;
	EXPECT_THAT(keys.SetFileKeys(LTEXT("*.cpp !*.bak #obj")), Eq(0));
	EXPECT_THAT(ToStrings(keys.m_vecSearchFileKeys), Eq(std::vector<sakura::wstring>({ LTEXT("*.cpp") })));
	EXPECT_THAT(ToStrings(keys.m_vecExceptFileKeys), Eq(std::vector<sakura::wstring>({ LTEXT("*.bak") })));
	EXPECT_THAT(ToStrings(keys.m_vecExceptFolderKeys), Eq(std::vector<sakura::wstring>({ LTEXT("obj") })));
	EXPECT_THAT(ToStrings(keys.m_vecSearchFolderKeys), Eq(std::vector<sakura::wstring>({ LTEXT("*.*") })));
}

/*!
	@brief 除外指定の絶対パスが専用の配列に振り分けられること
*/
TEST(CGrepEnumKeys, SetFileKeys_AbsoluteExcept)
{
	CGrepEnumKeys keys;
	EXPECT_THAT(keys.SetFileKeys(LTEXT("*.cpp !" WORK_DIR "*.bak #" WORK_DIR "obj")), Eq(0));
	EXPECT_THAT(ToStrings(keys.m_vecExceptAbsFileKeys), Eq(std::vector<sakura::wstring>({ LTEXT("" WORK_DIR "*.bak") })));
	EXPECT_THAT(ToStrings(keys.m_vecExceptAbsFolderKeys), Eq(std::vector<sakura::wstring>({ LTEXT("" WORK_DIR "obj") })));
	EXPECT_THAT(keys.m_vecExceptFileKeys.empty(), IsTrue());
	EXPECT_THAT(keys.m_vecExceptFolderKeys.empty(), IsTrue());
}

/*!
	@brief UNCパスの除外指定が絶対パスとして振り分けられること
*/
#if defined(_WIN32)	// Mac 版: UNC パスは無い
TEST(CGrepEnumKeys, SetFileKeys_UncPathExcept)
{
	CGrepEnumKeys keys;
	EXPECT_THAT(keys.SetFileKeys(LTEXT("*.cpp !\\\\server\\share\\*.bak")), Eq(0));
	EXPECT_THAT(ToStrings(keys.m_vecExceptAbsFileKeys), Eq(std::vector<sakura::wstring>({ LTEXT("\\\\server\\share\\*.bak") })));
	EXPECT_THAT(keys.m_vecExceptFileKeys.empty(), IsTrue());
}
#endif

/*!
	@brief 同じパターンを重複して登録しないこと
*/
TEST(CGrepEnumKeys, SetFileKeys_Unique)
{
	CGrepEnumKeys keys;
	EXPECT_THAT(keys.SetFileKeys(LTEXT("*.cpp *.cpp")), Eq(0));
	EXPECT_THAT(ToStrings(keys.m_vecSearchFileKeys), Eq(std::vector<sakura::wstring>({ LTEXT("*.cpp") })));
}

/*!
	@brief フォルダー部分のワイルドカードがエラーになること
*/
TEST(CGrepEnumKeys, SetFileKeys_WildcardInFolderIsError)
{
	CGrepEnumKeys keys;
	EXPECT_THAT(keys.SetFileKeys(LTEXT("*\\file.exe")), Eq(1));
}

/*!
	@brief フォルダー部分の '?' ワイルドカードがエラーになること
*/
TEST(CGrepEnumKeys, SetFileKeys_QuestionMarkInFolderIsError)
{
	CGrepEnumKeys keys;
	EXPECT_THAT(keys.SetFileKeys(LTEXT("?\\file.exe")), Eq(1));
}

/*!
	@brief 検索対象への絶対パス指定がエラーになること
*/
TEST(CGrepEnumKeys, SetFileKeys_AbsoluteSearchIsError)
{
	CGrepEnumKeys keys;
	EXPECT_THAT(keys.SetFileKeys(LTEXT("" WORK_DIR "*.cpp")), Eq(2));
}

/*!
	@brief 再呼び出し時に絶対パスの除外指定が持ち越されないこと

	ClearItems() が絶対パス用の2配列をクリアしていなかった不具合の回帰テスト。
*/
TEST(CGrepEnumKeys, SetFileKeys_ClearsAbsoluteExceptOnReentry)
{
	CGrepEnumKeys keys;
	EXPECT_THAT(keys.SetFileKeys(LTEXT("*.cpp !" WORK_DIR "*.bak #" WORK_DIR "obj")), Eq(0));
	ASSERT_THAT(keys.m_vecExceptAbsFileKeys.size(), Eq(1u));
	ASSERT_THAT(keys.m_vecExceptAbsFolderKeys.size(), Eq(1u));

	EXPECT_THAT(keys.SetFileKeys(LTEXT("*.cpp")), Eq(0));
	EXPECT_THAT(keys.m_vecExceptAbsFileKeys.empty(), IsTrue());
	EXPECT_THAT(keys.m_vecExceptAbsFolderKeys.empty(), IsTrue());
}

/*!
	@brief 除外リストが相対パス・絶対パスの順に連結されること
*/
TEST(CGrepEnumKeys, GetExcludeFilesAndFolders)
{
	CGrepEnumKeys keys;
	EXPECT_THAT(keys.SetFileKeys(LTEXT("*.cpp !*.bak !" WORK_DIR "*.tmp #obj #" WORK_DIR "bin")), Eq(0));
	EXPECT_THAT(ToStrings(keys.GetExcludeFiles()), Eq(std::vector<sakura::wstring>({ LTEXT("*.bak"), LTEXT("" WORK_DIR "*.tmp") })));
	EXPECT_THAT(ToStrings(keys.GetExcludeFolders()), Eq(std::vector<sakura::wstring>({ LTEXT("obj"), LTEXT("" WORK_DIR "bin") })));
}

/*!
	@brief 除外パターンの追加が既存の解析結果に積まれること
*/
TEST(CGrepEnumKeys, AddExceptFileAndFolder)
{
	CGrepEnumKeys keys;
	EXPECT_THAT(keys.SetFileKeys(LTEXT("*.cpp !*.bak")), Eq(0));
	EXPECT_THAT(keys.AddExceptFile(LTEXT("*.tmp;" WORK_DIR "*.log")), Eq(0));
	EXPECT_THAT(keys.AddExceptFolder(LTEXT("obj")), Eq(0));
	EXPECT_THAT(ToStrings(keys.m_vecExceptFileKeys), Eq(std::vector<sakura::wstring>({ LTEXT("*.bak"), LTEXT("*.tmp") })));
	EXPECT_THAT(ToStrings(keys.m_vecExceptAbsFileKeys), Eq(std::vector<sakura::wstring>({ LTEXT("" WORK_DIR "*.log") })));
	EXPECT_THAT(ToStrings(keys.m_vecExceptFolderKeys), Eq(std::vector<sakura::wstring>({ LTEXT("obj") })));
}
