/*! @file */
/*
	Copyright (C) 2026, Sakura Editor Organization

	SPDX-License-Identifier: Zlib
*/
#include "pch.h"
#include <tchar.h>
#include <Windows.h>

#include <string>
#include <string_view>

#include "grep/GrepMessageFormat.h"

#if defined(_WIN32)
#include "window/EditorTestSuite.hpp"
#else
#include "mac-editor-test-suite.hpp"	// Mac 版: 編集ウィンドウはまだないので、共通設定だけを用意する（移植計画のステップ 21）
#endif

/*!
 * @brief lineColumnToString のテスト
 *  最小値を与えて書式を確認する
 */
TEST(GrepMessageFormat, lineColumnToStringMinimum)
{
	WCHAR strWork[64];
	ASSERT_THAT(lineColumnToString(strWork, 1, 1), StrEq(LTEXT("(1,1)")));
}

/*!
 * @brief lineColumnToString のテスト
 *  複数桁の行番号・桁番号を与えて書式を確認する
 */
TEST(GrepMessageFormat, lineColumnToStringMultipleDigits)
{
	WCHAR strWork[64];
	ASSERT_THAT(lineColumnToString(strWork, 1234, 56), StrEq(LTEXT("(1234,56)")));
}

/*!
 * @brief lineColumnToString のテスト
 *  int を超える行番号を与えても桁落ちしないことを確認する
 */
TEST(GrepMessageFormat, lineColumnToStringLargeLineNumber)
{
	WCHAR strWork[64];
	ASSERT_THAT(lineColumnToString(strWork, 4294967296LL, 1), StrEq(LTEXT("(4294967296,1)")));
}

/*!
 * @brief OutputPathInfo のテスト
 *  出力形式3（結果のみ）では何も出力せず、フラグも変化しないこと
 */
TEST(GrepMessageFormat, OutputPathInfoResultOnlyOutputsNothing)
{
	CNativeW cmemMessage(LTEXT(""));
	GrepInfo gi;
	gi.nGrepOutputStyle = 3;
	gi.bGrepOutputBaseFolder = true;
	gi.bGrepSeparateFolder = true;
	bool bOutputBaseFolder = false;
	bool bOutputFolderName = false;
	BOOL bOutFileName = FALSE;

	OutputPathInfo( cmemMessage, gi, LTEXT("C:\\work\\a.txt"), LTEXT("C:\\work"),
		LTEXT("sub"), LTEXT("sub\\a.txt"), LTEXT(" [SJIS]"),
		bOutputBaseFolder, bOutputFolderName, bOutFileName );

	EXPECT_THAT(cmemMessage.GetStringLength(), 0);
	EXPECT_THAT(bOutputBaseFolder, IsFalse());
	EXPECT_THAT(bOutputFolderName, IsFalse());
	EXPECT_THAT(bOutFileName, IsFalse());
}

/*!
 * @brief OutputPathInfo のテスト
 *  出力形式1でベースフォルダーを出力し、フラグが立つこと
 */
TEST(GrepMessageFormat, OutputPathInfoBaseFolderNormalStyle)
{
	CNativeW cmemMessage(LTEXT(""));
	GrepInfo gi;
	gi.nGrepOutputStyle = 1;
	gi.bGrepOutputBaseFolder = true;
	bool bOutputBaseFolder = false;
	bool bOutputFolderName = false;
	BOOL bOutFileName = FALSE;

	OutputPathInfo( cmemMessage, gi, LTEXT("C:\\work\\a.txt"), LTEXT("C:\\work"),
		LTEXT(""), LTEXT("a.txt"), LTEXT(" [SJIS]"),
		bOutputBaseFolder, bOutputFolderName, bOutFileName );

	ASSERT_THAT(cmemMessage.GetStringPtr(), StrEq(LTEXT("■\"C:\\work\"\r\n")));
	EXPECT_THAT(bOutputBaseFolder, IsTrue());
}

/*!
 * @brief OutputPathInfo のテスト
 *  フォルダー毎表示が有効な場合はベースフォルダーの記号が変わること
 */
TEST(GrepMessageFormat, OutputPathInfoBaseFolderSeparateFolder)
{
	CNativeW cmemMessage(LTEXT(""));
	GrepInfo gi;
	gi.nGrepOutputStyle = 1;
	gi.bGrepOutputBaseFolder = true;
	gi.bGrepSeparateFolder = true;
	bool bOutputBaseFolder = false;
	bool bOutputFolderName = false;
	BOOL bOutFileName = FALSE;

	OutputPathInfo( cmemMessage, gi, LTEXT("C:\\work\\sub\\a.txt"), LTEXT("C:\\work"),
		LTEXT("sub"), LTEXT("sub\\a.txt"), LTEXT(" [SJIS]"),
		bOutputBaseFolder, bOutputFolderName, bOutFileName );

	ASSERT_THAT(cmemMessage.GetStringPtr(), StrEq(LTEXT("◎\"C:\\work\"\r\n■\"sub\"\r\n")));
	EXPECT_THAT(bOutputBaseFolder, IsTrue());
	EXPECT_THAT(bOutputFolderName, IsTrue());
}

/*!
 * @brief OutputPathInfo のテスト
 *  フォルダー名が空の場合は記号のみを出力すること
 */
TEST(GrepMessageFormat, OutputPathInfoEmptyFolderName)
{
	CNativeW cmemMessage(LTEXT(""));
	GrepInfo gi;
	gi.nGrepOutputStyle = 1;
	gi.bGrepSeparateFolder = true;
	bool bOutputBaseFolder = false;
	bool bOutputFolderName = false;
	BOOL bOutFileName = FALSE;

	OutputPathInfo( cmemMessage, gi, LTEXT("C:\\work\\a.txt"), LTEXT("C:\\work"),
		LTEXT(""), LTEXT("a.txt"), LTEXT(" [SJIS]"),
		bOutputBaseFolder, bOutputFolderName, bOutFileName );

	ASSERT_THAT(cmemMessage.GetStringPtr(), StrEq(LTEXT("■\r\n")));
	EXPECT_THAT(bOutputFolderName, IsTrue());
}

/*!
 * @brief OutputPathInfo のテスト
 *  出力形式2（WZ風）ではファイル名を出力し、bOutFileName が立つこと
 */
TEST(GrepMessageFormat, OutputPathInfoWzStyleFileName)
{
	CNativeW cmemMessage(LTEXT(""));
	GrepInfo gi;
	gi.nGrepOutputStyle = 2;
	bool bOutputBaseFolder = false;
	bool bOutputFolderName = false;
	BOOL bOutFileName = FALSE;

	OutputPathInfo( cmemMessage, gi, LTEXT("C:\\work\\a.txt"), LTEXT("C:\\work"),
		LTEXT(""), LTEXT("a.txt"), LTEXT(" [SJIS]"),
		bOutputBaseFolder, bOutputFolderName, bOutFileName );

	ASSERT_THAT(cmemMessage.GetStringPtr(), StrEq(LTEXT("■\"C:\\work\\a.txt\" [SJIS]\r\n")));
	EXPECT_THAT(bOutFileName, IsTrue());
}

/*!
 * @brief OutputPathInfo のテスト
 *  すでに出力済みの場合は二重に出力しないこと
 */
TEST(GrepMessageFormat, OutputPathInfoDoesNotOutputTwice)
{
	CNativeW cmemMessage(LTEXT(""));
	GrepInfo gi;
	gi.nGrepOutputStyle = 2;
	gi.bGrepOutputBaseFolder = true;
	gi.bGrepSeparateFolder = true;
	bool bOutputBaseFolder = true;
	bool bOutputFolderName = true;
	BOOL bOutFileName = TRUE;

	OutputPathInfo( cmemMessage, gi, LTEXT("C:\\work\\sub\\a.txt"), LTEXT("C:\\work"),
		LTEXT("sub"), LTEXT("sub\\a.txt"), LTEXT(" [SJIS]"),
		bOutputBaseFolder, bOutputFolderName, bOutFileName );

	EXPECT_THAT(cmemMessage.GetStringLength(), 0);
}

/*!
 * @brief OutputPathInfo のテスト
 *  出力形式2でフォルダー毎表示が有効な場合は相対パスと別記号を使うこと
 */
TEST(GrepMessageFormat, OutputPathInfoWzStyleSeparateFolder)
{
	CNativeW cmemMessage(LTEXT(""));
	GrepInfo gi;
	gi.nGrepOutputStyle = 2;
	gi.bGrepSeparateFolder = true;
	// ベースフォルダーとフォルダー名は出力済みにして、ファイル名の分岐だけを見る
	bool bOutputBaseFolder = true;
	bool bOutputFolderName = true;
	BOOL bOutFileName = FALSE;

	OutputPathInfo( cmemMessage, gi, LTEXT("C:\\work\\sub\\a.txt"), LTEXT("C:\\work"),
		LTEXT("sub"), LTEXT("sub\\a.txt"), LTEXT(" [SJIS]"),
		bOutputBaseFolder, bOutputFolderName, bOutFileName );

	ASSERT_THAT(cmemMessage.GetStringPtr(), StrEq(LTEXT("◆\"sub\\a.txt\" [SJIS]\r\n")));
	EXPECT_THAT(bOutFileName, IsTrue());
}

/*!
 * @brief OutputPathInfo のテスト
 *  既存の内容が長い場合でもバッファを広げて追記できること
 */
TEST(GrepMessageFormat, OutputPathInfoExpandsBuffer)
{
	// 初期バッファ1024を超えるよう、あらかじめ長い内容を入れておく
	const sakura::wstring prefix(800, LCHAR('x'));
	CNativeW cmemMessage(prefix.c_str());
	GrepInfo gi;
	gi.nGrepOutputStyle = 1;
	gi.bGrepOutputBaseFolder = true;
	bool bOutputBaseFolder = false;
	bool bOutputFolderName = false;
	BOOL bOutFileName = FALSE;

	OutputPathInfo( cmemMessage, gi, LTEXT("C:\\work\\a.txt"), LTEXT("C:\\work"),
		LTEXT(""), LTEXT("a.txt"), LTEXT(" [SJIS]"),
		bOutputBaseFolder, bOutputFolderName, bOutFileName );

	const sakura::wstring expected = prefix + LTEXT("■\"C:\\work\"\r\n");
	ASSERT_THAT(cmemMessage.GetStringPtr(), StrEq(expected.c_str()));
	EXPECT_THAT(bOutputBaseFolder, IsTrue());
}

/*!
 * SetGrepResult のテストのためのフィクスチャクラス
 *
 * SetGrepResult は GetDllShareData() を参照するため、共有データの用意が必要。
 */
class SetGrepResultTest : public ::testing::Test, public window::EditorTestSuite {
protected:
	static void SetUpTestSuite() { SetUpEditor(); }
	static void TearDownTestSuite() { TearDownEditor(); }
};

/*!
 * @brief SetGrepResult のテスト
 *  出力形式1・該当行出力の書式を確認する
 */
TEST_F(SetGrepResultTest, NormalStyleHitLine)
{
	CNativeW cmemMessage(LTEXT(""));
	GrepInfo gi;
	gi.nGrepOutputStyle = 1;
	gi.nGrepOutputLineType = 1;

	constexpr sakura::wstring_view line = LTEXT("hello\r\n");
	SetGrepResult( cmemMessage, LTEXT("a.txt"), LTEXT(" [SJIS]"), 12, 3,
		line.data(), static_cast<int>(line.length()), 2,
		nullptr, 0, gi );

	ASSERT_THAT(cmemMessage.GetStringPtr(), StrEq(LTEXT("a.txt(12,3) [SJIS]: hello\r\n")));
}

/*!
 * @brief SetGrepResult のテスト
 *  ベースフォルダー表示が有効な場合は先頭に記号が付くこと
 */
TEST_F(SetGrepResultTest, NormalStyleWithBaseFolderMark)
{
	CNativeW cmemMessage(LTEXT(""));
	GrepInfo gi;
	gi.nGrepOutputStyle = 1;
	gi.nGrepOutputLineType = 1;
	gi.bGrepOutputBaseFolder = true;

	constexpr sakura::wstring_view line = LTEXT("hello\r\n");
	SetGrepResult( cmemMessage, LTEXT("a.txt"), LTEXT(" [SJIS]"), 1, 1,
		line.data(), static_cast<int>(line.length()), 2,
		nullptr, 0, gi );

	ASSERT_THAT(cmemMessage.GetStringPtr(), StrEq(LTEXT("・a.txt(1,1) [SJIS]: hello\r\n")));
}

/*!
 * @brief SetGrepResult のテスト
 *  出力形式2（WZ風）の書式を確認する
 */
TEST_F(SetGrepResultTest, WzStyleHitLine)
{
	CNativeW cmemMessage(LTEXT(""));
	GrepInfo gi;
	gi.nGrepOutputStyle = 2;
	gi.nGrepOutputLineType = 1;

	constexpr sakura::wstring_view line = LTEXT("hello\r\n");
	SetGrepResult( cmemMessage, LTEXT("a.txt"), LTEXT(" [SJIS]"), 12, 3,
		line.data(), static_cast<int>(line.length()), 2,
		nullptr, 0, gi );

	ASSERT_THAT(cmemMessage.GetStringPtr(), StrEq(LTEXT("・(    12,3    ): hello\r\n")));
}

/*!
 * @brief SetGrepResult のテスト
 *  出力形式3（結果のみ）では見出しが付かないこと
 */
TEST_F(SetGrepResultTest, ResultOnlyStyleHitLine)
{
	CNativeW cmemMessage(LTEXT(""));
	GrepInfo gi;
	gi.nGrepOutputStyle = 3;
	gi.nGrepOutputLineType = 1;

	constexpr sakura::wstring_view line = LTEXT("hello\r\n");
	SetGrepResult( cmemMessage, LTEXT("a.txt"), LTEXT(" [SJIS]"), 12, 3,
		line.data(), static_cast<int>(line.length()), 2,
		nullptr, 0, gi );

	ASSERT_THAT(cmemMessage.GetStringPtr(), StrEq(LTEXT("hello\r\n")));
}

/*!
 * @brief SetGrepResult のテスト
 *  該当部分出力では一致した文字列だけが出力されること
 */
TEST_F(SetGrepResultTest, MatchedPartOnly)
{
	CNativeW cmemMessage(LTEXT(""));
	GrepInfo gi;
	gi.nGrepOutputStyle = 3;
	gi.nGrepOutputLineType = 0;

	constexpr sakura::wstring_view line = LTEXT("hello world\r\n");
	constexpr sakura::wstring_view match = LTEXT("world");
	SetGrepResult( cmemMessage, LTEXT("a.txt"), LTEXT(" [SJIS]"), 1, 7,
		line.data(), static_cast<int>(line.length()), 2,
		match.data(), static_cast<int>(match.length()), gi );

	ASSERT_THAT(cmemMessage.GetStringPtr(), StrEq(LTEXT("world\r\n")));
}

/*!
 * @brief SetGrepResult のテスト
 *  該当部分が改行で終わる場合は改行を重ねて出力しないこと
 */
TEST_F(SetGrepResultTest, MatchedPartEndingWithEol)
{
	CNativeW cmemMessage(LTEXT(""));
	GrepInfo gi;
	gi.nGrepOutputStyle = 3;
	gi.nGrepOutputLineType = 0;

	constexpr sakura::wstring_view line = LTEXT("hello\r\n");
	constexpr sakura::wstring_view match = LTEXT("hello\r\n");
	SetGrepResult( cmemMessage, LTEXT("a.txt"), LTEXT(" [SJIS]"), 1, 1,
		line.data(), static_cast<int>(line.length()), 2,
		match.data(), static_cast<int>(match.length()), gi );

	ASSERT_THAT(cmemMessage.GetStringPtr(), StrEq(LTEXT("hello\r\n")));
}

/*!
 * @brief SetGrepResult のテスト
 *  該当行が長すぎる場合は上限で切り捨てられること
 */
TEST_F(SetGrepResultTest, HitLineIsTruncated)
{
	CNativeW cmemMessage(LTEXT(""));
	GrepInfo gi;
	gi.nGrepOutputStyle = 1;	// ノーマルの上限は2000文字
	gi.nGrepOutputLineType = 1;

	sakura::wstring line(2100, LCHAR('a'));
	line += LTEXT("\r\n");
	SetGrepResult( cmemMessage, LTEXT("a.txt"), LTEXT(" [SJIS]"), 1, 1,
		line.data(), static_cast<int>(line.length()), 2,
		nullptr, 0, gi );

	const sakura::wstring expected =
		sakura::wstring(LTEXT("a.txt(1,1) [SJIS]: ")) + sakura::wstring(2000, LCHAR('a')) + LTEXT("\r\n");
	ASSERT_THAT(cmemMessage.GetStringPtr(), StrEq(expected.c_str()));
}

/*!
 * @brief SetGrepResult のテスト
 *  該当部分が長すぎる場合は上限で切り捨てられること
 */
TEST_F(SetGrepResultTest, MatchedPartIsTruncated)
{
	CNativeW cmemMessage(LTEXT(""));
	GrepInfo gi;
	gi.nGrepOutputStyle = 3;	// 結果のみの上限は2500文字
	gi.nGrepOutputLineType = 0;

	sakura::wstring line(2600, LCHAR('b'));
	line += LTEXT("\r\n");
	SetGrepResult( cmemMessage, LTEXT("a.txt"), LTEXT(" [SJIS]"), 1, 1,
		line.data(), static_cast<int>(line.length()), 2,
		line.data(), 2600, gi );

	const sakura::wstring expected = sakura::wstring(2500, LCHAR('b')) + LTEXT("\r\n");
	ASSERT_THAT(cmemMessage.GetStringPtr(), StrEq(expected.c_str()));
}

/*!
 * CGrepResultWriter のテストのためのフィクスチャクラス
 *
 * CGrepResultWriter は SetGrepResult を使い、該当部分の出力では共有データを参照するため、共有データを用意する。
 */
class CGrepResultWriterTest : public SetGrepResultTest {
protected:
	CNativeW cmemMessage{ LTEXT("") };
	GrepInfo gi;
	bool bOutputBaseFolder = false;
	bool bOutputFolderName = false;

	//! 行 line(行末は CRLF)の pos から len 文字に一致したものとして、1 件足す
	static void AddMatch(CGrepResultWriter& writer, LONGLONG nLine, sakura::wstring_view line, sakura::wstring_view::size_type pos, sakura::wstring_view::size_type len)
	{
		writer.AddMatch({
			.nLine = nLine, .nColumn = static_cast<int>(pos) + 1,
			.pLine = line.data(), .nLineLen = static_cast<int>(line.length()), .nEolLen = 2,
			.pMatch = line.data() + pos, .nMatchLen = static_cast<int>(len)
		});
	}

	//! C:\work の下のファイル(文字コード名は [SJIS])
	static SGrepResultFile File(const WCHAR* pszFullPath, const WCHAR* pszFolder, const WCHAR* pszRelPath)
	{
		return { .pszFullPath = pszFullPath, .pszBaseFolder = LTEXT("C:\\work"), .pszFolder = pszFolder, .pszRelPath = pszRelPath, .pszCodeName = LTEXT(" [SJIS]") };
	}
};

/*!
 * @brief CGrepResultWriter のテスト
 *  ノーマル・該当部分: 一致ごとにフルパス・行桁・文字コード名と一致した部分を出す
 */
TEST_F(CGrepResultWriterTest, NormalStyleMatchedPart)
{
	gi.nGrepOutputStyle = 1;
	gi.nGrepOutputLineType = 0;
	CGrepResultWriter writer(cmemMessage, gi, File(LTEXT("C:\\work\\a.txt"), LTEXT(""), LTEXT("a.txt")), bOutputBaseFolder, bOutputFolderName);

	constexpr sakura::wstring_view line = LTEXT("x HIT HIT\r\n");
	AddMatch(writer, 1, line, 2, 3);
	AddMatch(writer, 1, line, 6, 3);

	EXPECT_THAT(cmemMessage.GetStringPtr(), ::testing::StrEq(LTEXT("C:\\work\\a.txt(1,3) [SJIS]: HIT\r\nC:\\work\\a.txt(1,7) [SJIS]: HIT\r\n")));
}

/*!
 * @brief CGrepResultWriter のテスト
 *  WZ風・該当行: ファイル名の見出しは最初の一致の前に 1 回だけ出す
 */
TEST_F(CGrepResultWriterTest, WzStyleFileNameOnce)
{
	gi.nGrepOutputStyle = 2;
	gi.nGrepOutputLineType = 1;
	CGrepResultWriter writer(cmemMessage, gi, File(LTEXT("C:\\work\\a.txt"), LTEXT(""), LTEXT("a.txt")), bOutputBaseFolder, bOutputFolderName);

	AddMatch(writer, 1, LTEXT("hello\r\n"), 2, 3);
	AddMatch(writer, 2, LTEXT("world\r\n"), 0, 1);

	EXPECT_THAT(cmemMessage.GetStringPtr(), ::testing::StrEq(LTEXT("■\"C:\\work\\a.txt\" [SJIS]\r\n・(     1,3    ): hello\r\n・(     2,1    ): world\r\n")));
}

/*!
 * @brief CGrepResultWriter のテスト
 *  ベースフォルダー: 見出しはファイルをまたいで 1 回だけ出し、ファイル名は相対パスで出す
 */
TEST_F(CGrepResultWriterTest, BaseFolderOnceAcrossFiles)
{
	gi.nGrepOutputStyle = 1;
	gi.nGrepOutputLineType = 1;
	gi.bGrepOutputBaseFolder = true;

	CGrepResultWriter writerA(cmemMessage, gi, File(LTEXT("C:\\work\\a.txt"), LTEXT(""), LTEXT("a.txt")), bOutputBaseFolder, bOutputFolderName);
	AddMatch(writerA, 1, LTEXT("x\r\n"), 0, 1);
	CGrepResultWriter writerB(cmemMessage, gi, File(LTEXT("C:\\work\\b.txt"), LTEXT(""), LTEXT("b.txt")), bOutputBaseFolder, bOutputFolderName);
	AddMatch(writerB, 1, LTEXT("y\r\n"), 0, 1);

	EXPECT_THAT(cmemMessage.GetStringPtr(), ::testing::StrEq(LTEXT("■\"C:\\work\"\r\n・a.txt(1,1) [SJIS]: x\r\n・b.txt(1,1) [SJIS]: y\r\n")));
	EXPECT_THAT(bOutputBaseFolder, ::testing::IsTrue());
}

/*!
 * @brief CGrepResultWriter のテスト
 *  フォルダー毎に表示: フォルダーの見出しは、同じフォルダーのファイルをまたいで 1 回だけ出し、ファイル名は相対パスで出す
 */
TEST_F(CGrepResultWriterTest, SeparateFolderOncePerFolder)
{
	gi.nGrepOutputStyle = 1;
	gi.nGrepOutputLineType = 1;
	gi.bGrepSeparateFolder = true;

	CGrepResultWriter writerA(cmemMessage, gi, File(LTEXT("C:\\work\\sub\\a.txt"), LTEXT("sub"), LTEXT("a.txt")), bOutputBaseFolder, bOutputFolderName);
	AddMatch(writerA, 1, LTEXT("x\r\n"), 0, 1);
	CGrepResultWriter writerB(cmemMessage, gi, File(LTEXT("C:\\work\\sub\\b.txt"), LTEXT("sub"), LTEXT("b.txt")), bOutputBaseFolder, bOutputFolderName);
	AddMatch(writerB, 1, LTEXT("y\r\n"), 0, 1);

	EXPECT_THAT(cmemMessage.GetStringPtr(), ::testing::StrEq(LTEXT("■\"sub\"\r\n・a.txt(1,1) [SJIS]: x\r\n・b.txt(1,1) [SJIS]: y\r\n")));
	EXPECT_THAT(bOutputFolderName, ::testing::IsTrue());
}

/*!
 * @brief CGrepResultWriter のテスト
 *  結果のみ: 見出しは出さず、ベースフォルダーを出したかのフラグも変えない
 */
TEST_F(CGrepResultWriterTest, ResultOnlyStyleNoHeading)
{
	gi.nGrepOutputStyle = 3;
	gi.nGrepOutputLineType = 1;
	gi.bGrepOutputBaseFolder = true;

	CGrepResultWriter writer(cmemMessage, gi, File(LTEXT("C:\\work\\a.txt"), LTEXT(""), LTEXT("a.txt")), bOutputBaseFolder, bOutputFolderName);
	AddMatch(writer, 1, LTEXT("x\r\n"), 0, 1);

	EXPECT_THAT(cmemMessage.GetStringPtr(), ::testing::StrEq(LTEXT("x\r\n")));
	EXPECT_THAT(bOutputBaseFolder, ::testing::IsFalse());
}

/*!
 * @brief AppendFolderHeadings のテスト
 *  フォルダー毎に表示しないとき、ベースフォルダー名の印は出力形式2(WZ風)だけ「◎」、ほかは「■」。出力形式3でも出す
 */
TEST(GrepMessageFormat, AppendFolderHeadingsBaseFolderMark)
{
	for (const auto& [style, expected] : { std::pair{ 1, LTEXT("■\"C:\\work\"\r\n") }, std::pair{ 2, LTEXT("◎\"C:\\work\"\r\n") }, std::pair{ 3, LTEXT("■\"C:\\work\"\r\n") } }) {
		GrepInfo gi;
		gi.nGrepOutputStyle = style;
		gi.bGrepOutputBaseFolder = true;
		CNativeW cmemMessage(LTEXT(""));
		bool bOutputBaseFolder = false;
		bool bOutputFolderName = false;
		AppendFolderHeadings(cmemMessage, gi, LTEXT("C:\\work"), LTEXT(""), bOutputBaseFolder, bOutputFolderName);
		EXPECT_THAT(cmemMessage.GetStringPtr(), ::testing::StrEq(expected)) << style;
		EXPECT_THAT(bOutputBaseFolder, ::testing::IsTrue()) << style;
		EXPECT_THAT(bOutputFolderName, ::testing::IsFalse()) << style;
	}
}

/*!
 * @brief AppendFolderHeadings のテスト
 *  フォルダー毎に表示するときは、出力形式3でもベースフォルダー名(「◎」)とフォルダー名(「■」)を出す
 */
TEST(GrepMessageFormat, AppendFolderHeadingsSeparateFolderResultOnly)
{
	GrepInfo gi;
	gi.nGrepOutputStyle = 3;
	gi.bGrepOutputBaseFolder = true;
	gi.bGrepSeparateFolder = true;
	CNativeW cmemMessage(LTEXT(""));
	bool bOutputBaseFolder = false;
	bool bOutputFolderName = false;
	AppendFolderHeadings(cmemMessage, gi, LTEXT("C:\\work"), LTEXT("sub"), bOutputBaseFolder, bOutputFolderName);
	EXPECT_THAT(cmemMessage.GetStringPtr(), ::testing::StrEq(LTEXT("◎\"C:\\work\"\r\n■\"sub\"\r\n")));
	EXPECT_THAT(bOutputBaseFolder, ::testing::IsTrue());
	EXPECT_THAT(bOutputFolderName, ::testing::IsTrue());
}

/*!
 * @brief AppendFolderHeadings のテスト
 *  出したものは出さない。ベースフォルダーそのもの(フォルダー名が空)は「■」だけの行
 */
TEST(GrepMessageFormat, AppendFolderHeadingsOnlyNotYetOutput)
{
	GrepInfo gi;
	gi.bGrepOutputBaseFolder = true;
	gi.bGrepSeparateFolder = true;
	CNativeW cmemMessage(LTEXT(""));
	bool bOutputBaseFolder = true;
	bool bOutputFolderName = false;
	AppendFolderHeadings(cmemMessage, gi, LTEXT("C:\\work"), LTEXT(""), bOutputBaseFolder, bOutputFolderName);
	AppendFolderHeadings(cmemMessage, gi, LTEXT("C:\\work"), LTEXT(""), bOutputBaseFolder, bOutputFolderName);
	EXPECT_THAT(cmemMessage.GetStringPtr(), ::testing::StrEq(LTEXT("■\r\n")));
}
