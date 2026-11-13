/*! @file
	@brief 基本编辑（计划第 29 步）的测试

	原版 CEditView、CViewCommander 的编辑处理在核心库里的移植：
	- 矩形选择的复制、删除、输入（每行插入）、矩形贴付（Command_PASTEBOX）
	- 行末之后插入时用空白填补（InsertData_CEditView）
	- 多行选择的 TAB 缩进、逆缩进（Command_INDENT、Command_UNINDENT）
	- 「スペースの挿入」的 TAB、オートインデント（Command_WCHAR）
	- 复制用的文字（GetSelectedData、CopyCurLine）、贴付时的换行符转换（ConvertEol）
	- 行删除（Command_DELETE_LINE）
	每个处理都是撤销的一步。
	字符宽度是测试用的（半角 8 点），TAB 幅 4。
*/
/*
	Copyright (C) 2026, Sakura Editor Organization

	SPDX-License-Identifier: Zlib
*/
#include "pch.h"
#include "sakura_core/SakuraCore.h"

#include "env/CDocTypeManager.h"
#include "env/DLLSHAREDATA.h"
#include "types/CType.h"

using namespace sakura::core;

namespace {

constexpr std::int32_t kFontSize = 16;
constexpr std::int32_t kHan = 8;	//!< 半角一字的宽度

class MacEditTest : public ::testing::Test {
protected:
	void SetUp() override
	{
		ASSERT_TRUE(Startup());
		SetLayoutFont(u"TestMono", kFontSize);
		ASSERT_TRUE(CDocTypeManager().GetTypeConfig(CTypeConfig(0), m_type));
		m_type.m_nTextWrapMethod = WRAP_NO_TEXT_WRAP;
		m_type.m_nTabSpace = CKetaXInt(4);
		m_type.m_nColumnSpace = 0;
		m_type.m_nIndentLayout = 0;
		ApplyType();
	}
	void TearDown() override
	{
		m_doc.reset();
		Shutdown(false);
	}
	void ApplyType()
	{
		m_doc.reset();
		ASSERT_TRUE(CDocTypeManager().SetTypeConfig(CTypeConfig(0), m_type));
		m_doc = Document::Create();
		ASSERT_NE(nullptr, m_doc);
	}
	void SetText(const Text& text)
	{
		ASSERT_EQ(Result::Ok, m_doc->Replace(Range{ Position{}, m_doc->EndPosition() }, text));
	}
	//! 撤销到最初（每个测试的 SetText 之后的状态）
	void UndoOnce(const Text& expected)
	{
		ASSERT_TRUE(m_doc->CanUndo());
		ASSERT_EQ(Result::Ok, m_doc->Undo());
		EXPECT_EQ(expected, m_doc->GetText());
	}

	STypeConfig m_type{};
	std::unique_ptr<Document> m_doc;
};

//! 横向位置：第 n 个半角
constexpr std::int32_t X(std::int32_t n) { return n * kHan; }

} // namespace

// ---------------------------------------------------------------------------
// 设置
// ---------------------------------------------------------------------------

TEST_F(MacEditTest, DefaultEditSettings)
{
	// 原版的默认值（CShareData::InitShareData、CType::InitTypeConfig）
	const EditSettings e = m_doc->GetEditSettings();
	EXPECT_TRUE(e.copyWithoutSelection);
	EXPECT_TRUE(e.lineModePaste);
	EXPECT_FALSE(e.clearSelectionAfterCopy);
	EXPECT_TRUE(e.autoColumnPaste);
	EXPECT_FALSE(e.convertEolOnPaste);
	EXPECT_FALSE(e.addEolAtWrapOnCopy);
	EXPECT_FALSE(e.insertSpacesForTab);
	EXPECT_TRUE(e.autoIndent);
}

// ---------------------------------------------------------------------------
// 复制
// ---------------------------------------------------------------------------

TEST_F(MacEditTest, CopyTextKeepsEol)
{
	SetText(u"abc\r\ndef\nghi");
	EXPECT_EQ(u"bc\r\nde", m_doc->GetCopyText(Range{ { 0, 1 }, { 1, 2 } }));
	EXPECT_EQ(u"def\n", m_doc->GetCopyText(Range{ { 1, 0 }, { 2, 0 } }));
	EXPECT_EQ(u"", m_doc->GetCopyText(Range{ { 1, 1 }, { 1, 1 } }));
}

TEST_F(MacEditTest, CopyTextAddsEolAtWrapWhenEnabled)
{
	m_type.m_nTextWrapMethod = WRAP_SETTING_WIDTH;
	m_type.m_nMaxLineKetas = CKetaXInt(10);
	ApplyType();
	SetText(u"0123456789abcdef\r\n");
	// 折り返し位置では改行しない（默认）
	EXPECT_EQ(u"89ab", m_doc->GetCopyText(Range{ { 0, 8 }, { 0, 12 } }));
	GetDllShareData().m_Common.m_sEdit.m_bAddCRLFWhenCopy = true;
	EXPECT_EQ(u"89\r\nab", m_doc->GetCopyText(Range{ { 0, 8 }, { 0, 12 } }));
	// 行コピー：折り返した行は CRLF を付ける
	EXPECT_EQ(u"0123456789\r\n", m_doc->GetLayoutLineCopyText(0));
	GetDllShareData().m_Common.m_sEdit.m_bAddCRLFWhenCopy = false;
	EXPECT_EQ(u"0123456789", m_doc->GetLayoutLineCopyText(0));
	EXPECT_EQ(u"abcdef\r\n", m_doc->GetLayoutLineCopyText(1));
	EXPECT_EQ(u"", m_doc->GetLayoutLineCopyText(2));
}

TEST_F(MacEditTest, BoxText)
{
	SetText(u"abcdef\r\n12\r\nxyz");
	EXPECT_EQ(u"bc\r\n2\r\nyz\r\n", m_doc->GetBoxText(BoxRange{ 0, 2, X(1), X(3) }));
	// TAB は 4 桁：左端が TAB の途中のときは TAB 全体を含む（LineColumnToIndex）
	SetText(u"\tab\r\nabcdef");
	EXPECT_EQ(u"\t\r\ncd\r\n", m_doc->GetBoxText(BoxRange{ 0, 1, X(2), X(4) }));
	EXPECT_EQ(u"\ta\r\nabcde\r\n", m_doc->GetBoxText(BoxRange{ 0, 1, X(0), X(5) }));
}

// ---------------------------------------------------------------------------
// 矩形の削除・貼り付け・入力
// ---------------------------------------------------------------------------

TEST_F(MacEditTest, DeleteBoxIsOneUndoStep)
{
	SetText(u"abcdef\r\n12\r\nxyz");
	const Position caret = m_doc->DeleteBox(BoxRange{ 0, 2, X(1), X(3) });
	EXPECT_EQ(u"adef\r\n1\r\nx", m_doc->GetText());
	EXPECT_EQ((Position{ 0, 1 }), caret);
	UndoOnce(u"abcdef\r\n12\r\nxyz");
}

TEST_F(MacEditTest, DeleteBoxOutsideTextOnlyMovesCaret)
{
	SetText(u"ab\r\ncd\r\n");
	const bool canUndoBefore = m_doc->CanUndo();
	const Position caret = m_doc->DeleteBox(BoxRange{ 0, 1, X(5), X(8) });
	EXPECT_EQ(u"ab\r\ncd\r\n", m_doc->GetText());
	EXPECT_EQ((Position{ 0, 2 }), caret);	// 行末より右は行末へ
	EXPECT_EQ(canUndoBefore, m_doc->CanUndo());
}

TEST_F(MacEditTest, PasteBoxInsertsEachLineAtSameColumn)
{
	SetText(u"aaaa\r\nb\r\n");
	m_doc->PasteBox(LayoutPosition{ 0, X(2) }, u"XY\r\nZ\r\n");
	// 2 行目は行末より右なので空白で埋める
	EXPECT_EQ(u"aaXYaa\r\nb Z\r\n", m_doc->GetText());
	UndoOnce(u"aaaa\r\nb\r\n");
}

TEST_F(MacEditTest, PasteBoxAddsEolBelowLastLine)
{
	SetText(u"a");
	m_doc->PasteBox(LayoutPosition{ 0, X(1) }, u"X\r\nY\r\nZ");
	// 改行の無い最後の行には改行を追加してから次の行へ（原版と同じく最後の行にも追加）
	EXPECT_EQ(u"aX\r\n Y\r\n Z\r\n", m_doc->GetText());
	UndoOnce(u"a");
}

TEST_F(MacEditTest, InsertAtLayoutPadsAfterLineEnd)
{
	SetText(u"ab\r\ncd");
	EXPECT_EQ((LayoutPosition{ 0, X(5) }), m_doc->InsertAtLayout(LayoutPosition{ 0, X(4) }, u"X"));
	EXPECT_EQ(u"ab  X\r\ncd", m_doc->GetText());
	EXPECT_EQ((LayoutPosition{ 1, X(4) }), m_doc->InsertAtLayout(LayoutPosition{ 1, X(3) }, u"Y"));
	EXPECT_EQ(u"ab  X\r\ncd Y", m_doc->GetText());
	EXPECT_EQ((LayoutPosition{ 0, X(2) }), m_doc->InsertAtLayout(LayoutPosition{ 0, X(1) }, u"Z"));
	EXPECT_EQ(u"aZb  X\r\ncd Y", m_doc->GetText());
}

TEST_F(MacEditTest, TypingIntoZeroWidthBoxInsertsOnEveryLine)
{
	SetText(u"abc\r\nd\r\nefg");
	Position caret;
	const BoxRange box = m_doc->IndentBox(BoxRange{ 0, 2, X(1), X(1) }, u"X", IndentKind::None, &caret);
	EXPECT_EQ(u"aXbc\r\ndX\r\neXfg", m_doc->GetText());
	EXPECT_EQ((BoxRange{ 0, 2, X(2), X(2) }), box);
	EXPECT_EQ((Position{ 0, 2 }), caret);
	UndoOnce(u"abc\r\nd\r\nefg");
}

TEST_F(MacEditTest, TypingIntoBoxInsertsBeforeSelectionAndPadsShortLines)
{
	SetText(u"abcd\r\nd\r\nefgh");
	const BoxRange box = m_doc->IndentBox(BoxRange{ 0, 2, X(2), X(3) }, u"-", IndentKind::None);
	// 選択範囲は削除しない。短い行は空白で埋めてから入力
	EXPECT_EQ(u"ab-cd\r\nd -\r\nef-gh", m_doc->GetText());
	EXPECT_EQ((BoxRange{ 0, 2, X(3), X(4) }), box);
}

TEST_F(MacEditTest, TabIndentBox)
{
	SetText(u"abcd\r\n\r\nefgh");
	// 幅 0 のときは右端を最大にするだけ（Command_INDENT ver1）
	const BoxRange wide = m_doc->IndentBox(BoxRange{ 0, 2, X(1), X(1) }, u"\t", IndentKind::Tab);
	EXPECT_EQ(u"abcd\r\n\r\nefgh", m_doc->GetText());
	EXPECT_EQ(X(1), wide.left);
	EXPECT_LT(X(1), wide.right);
	// 空行には挿入しない
	const BoxRange box = m_doc->IndentBox(BoxRange{ 0, 2, X(1), X(2) }, u"\t", IndentKind::Tab);
	EXPECT_EQ(u"a\tbcd\r\n\r\ne\tfgh", m_doc->GetText());
	EXPECT_EQ((BoxRange{ 0, 2, X(4), X(5) }), box);
}

// ---------------------------------------------------------------------------
// 複数行のインデント・逆インデント
// ---------------------------------------------------------------------------

TEST_F(MacEditTest, IndentLinesSkipsEmptyLines)
{
	SetText(u"a\r\n\r\nb\r\nc");
	EXPECT_EQ(3, m_doc->IndentLines(0, 3, u"\t"));
	EXPECT_EQ(u"\ta\r\n\r\n\tb\r\nc", m_doc->GetText());
	UndoOnce(u"a\r\n\r\nb\r\nc");
}

TEST_F(MacEditTest, IndentLinesSkipsWrappedRows)
{
	m_type.m_nTextWrapMethod = WRAP_SETTING_WIDTH;
	m_type.m_nMaxLineKetas = CKetaXInt(10);
	ApplyType();
	SetText(u"0123456789abc\r\nx");
	ASSERT_EQ(3, m_doc->LayoutLineCount());
	// 行頭にだけ挿入。折り返しが変わると下端も変わる
	EXPECT_EQ(3, m_doc->IndentLines(0, 3, u"\t"));
	EXPECT_EQ(u"\t0123456789abc\r\n\tx", m_doc->GetText());
}

TEST_F(MacEditTest, UnindentLines)
{
	SetText(u"\ta\r\n    b\r\n  c\r\n      e\r\nd");
	EXPECT_EQ(5, m_doc->UnindentLines(0, 5, u'\t'));
	EXPECT_EQ(u"a\r\nb\r\nc\r\n  e\r\nd", m_doc->GetText());
	UndoOnce(u"\ta\r\n    b\r\n  c\r\n      e\r\nd");
	// SPACE の逆インデントは 1 個ずつ
	m_doc->UnindentLines(0, 5, u' ');
	EXPECT_EQ(u"\ta\r\n   b\r\n c\r\n     e\r\nd", m_doc->GetText());
}

// ---------------------------------------------------------------------------
// TAB、オートインデント、改行コード
// ---------------------------------------------------------------------------

TEST_F(MacEditTest, SoftTab)
{
	EXPECT_EQ(u"\t", m_doc->TabText(X(1)));
	m_type.m_bInsSpace = true;
	ApplyType();
	EXPECT_TRUE(m_doc->GetEditSettings().insertSpacesForTab);
	EXPECT_EQ(u"    ", m_doc->TabText(X(0)));
	EXPECT_EQ(u"   ", m_doc->TabText(X(1)));
	EXPECT_EQ(u" ", m_doc->TabText(X(3)));
	EXPECT_EQ(u"    ", m_doc->TabText(X(4)));
}

TEST_F(MacEditTest, AutoIndent)
{
	SetText(u"\t 　abc\r\nxyz");
	EXPECT_EQ(u"\t 　", m_doc->AutoIndentText(Position{ 0, 6 }));
	EXPECT_EQ(u"\t", m_doc->AutoIndentText(Position{ 0, 1 }));
	EXPECT_EQ(u"", m_doc->AutoIndentText(Position{ 1, 2 }));
	// 日本語空白をインデントに含めない
	m_type.m_bAutoIndent_ZENSPACE = false;
	ApplyType();
	SetText(u"\t 　abc");
	EXPECT_EQ(u"\t ", m_doc->AutoIndentText(Position{ 0, 6 }));
	// その他のインデント対象文字
	m_type.m_szIndentChars[0] = L'>';
	m_type.m_szIndentChars[1] = L'\0';
	ApplyType();
	SetText(u"> > quote");
	EXPECT_EQ(u"> > ", m_doc->AutoIndentText(Position{ 0, 9 }));
	// オートインデントしない
	m_type.m_bAutoIndent = false;
	ApplyType();
	SetText(u"\tabc");
	EXPECT_EQ(u"", m_doc->AutoIndentText(Position{ 0, 4 }));
}

TEST_F(MacEditTest, ConvertEolToNewLine)
{
	m_doc->SetNewLineEol(Eol::LF);
	EXPECT_EQ(u"a\nb\nc\nd", m_doc->ConvertEolToNewLine(u"a\r\nb\nc\rd"));
	m_doc->SetNewLineEol(Eol::CRLF);
	EXPECT_EQ(u"a\r\n\r\nb", m_doc->ConvertEolToNewLine(u"a\n\rb"));
}

// ---------------------------------------------------------------------------
// 行削除
// ---------------------------------------------------------------------------

TEST_F(MacEditTest, DeleteLayoutLine)
{
	SetText(u"abc\r\nde\r\nfghij");
	// 2 行目を削除。カーソルは同じ桁（次の行の桁 1）
	EXPECT_EQ((Position{ 1, 1 }), m_doc->DeleteLayoutLine(1, X(1)));
	EXPECT_EQ(u"abc\r\nfghij", m_doc->GetText());
	UndoOnce(u"abc\r\nde\r\nfghij");
	// 最後の行（改行なし）
	const Position caret = m_doc->DeleteLayoutLine(2, X(4));
	EXPECT_EQ(u"abc\r\nde\r\n", m_doc->GetText());
	EXPECT_EQ((Position{ 2, 0 }), caret);
	// 行末より右の桁は行末へ
	SetText(u"abcdef\r\nxy\r\n");
	EXPECT_EQ((Position{ 0, 2 }), m_doc->DeleteLayoutLine(0, X(5)));
	EXPECT_EQ(u"xy\r\n", m_doc->GetText());
}
