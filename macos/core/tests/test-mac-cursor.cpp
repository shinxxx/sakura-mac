/*! @file
	@brief 光标移动的目标（计划第 34 步）的测试

	原版 cmd/CViewCommander_Cursor.cpp 里决定移动目标的部分在核心库里的移植：
	- 単語の左端／右端に移動（CSearchAgent::PrevOrNextWord）：英数字、空白、日文的字种的边界，行头行末跨行
	- 前／次の段落へ（Command_GOPREVPARAGRAPH / GONEXTPARAGRAPH）：空行和非空行的边界
	- 前／次の変更行へ（Command_MODIFYLINE_PREV / NEXT）：变更行的块的开头和末尾、先頭（末尾）から再検索
	- 行頭に移動 的「行頭の空白を飛ばす」（Command_GOLINETOP）

	期待值按原版的算法一步一步算出（注释里写了依据）。
*/
/*
	Copyright (C) 2026, Sakura Editor Organization

	SPDX-License-Identifier: Zlib
*/
#include "sakura_core/SakuraCore.h"

#include <gtest/gtest.h>

#include <cstdlib>
#include <filesystem>
#include <fstream>

using namespace sakura::core;

namespace {

Position P(int line, int column) { return Position{ line, column }; }

class MacCursorTest : public ::testing::Test {
protected:
	void SetUp() override
	{
		ASSERT_TRUE(Startup());
		m_saved = GetSearchSettings();
		m_doc = Document::Create();
		ASSERT_NE(nullptr, m_doc);
	}
	void TearDown() override
	{
		m_doc.reset();
		SetSearchSettings(m_saved);
		Shutdown(false);
	}
	void SetText(const Text& text)
	{
		ASSERT_EQ(Result::Ok, m_doc->Replace(Range{ Position{}, m_doc->EndPosition() }, text));
	}
	//! 打开内容是 text 的文件（打开时没有变更行）
	void OpenText(const char* name, const std::string& text)
	{
		const auto path = std::filesystem::path(std::getenv("HOME")) / name;
		{
			std::ofstream out(path, std::ios::binary);
			out << text;
		}
		ASSERT_EQ(Result::Ok, m_doc->Open(path.u16string()));
	}
	void SetSearchAll(bool on)
	{
		auto s = GetSearchSettings();
		s.searchAll = on;
		SetSearchSettings(s);
	}
	std::unique_ptr<Document> m_doc;
	SearchSettings m_saved;
};

} // namespace

// ---------------------------------------------------------------------------
// 単語の左端／右端に移動
// ---------------------------------------------------------------------------

//! 英数字的单词：右是下一个单词的开头（空白跳过），左是这个（前一个）单词的开头
TEST_F(MacCursorTest, WordMoveAlnum)
{
	SetText(u"abc def  ghi");
	EXPECT_EQ(m_doc->WordMoveTarget(P(0, 0), false), P(0, 4));
	EXPECT_EQ(m_doc->WordMoveTarget(P(0, 4), false), P(0, 9));
	EXPECT_EQ(m_doc->WordMoveTarget(P(0, 1), false), P(0, 4));
	EXPECT_EQ(m_doc->WordMoveTarget(P(0, 9), true), P(0, 4));
	EXPECT_EQ(m_doc->WordMoveTarget(P(0, 6), true), P(0, 4));
	EXPECT_EQ(m_doc->WordMoveTarget(P(0, 4), true), P(0, 0));
}

//! 记号、日文：字种（漢字、カタカナ、ひらがな）变的地方是边界
TEST_F(MacCursorTest, WordMoveCharTypes)
{
	SetText(u"a+=b 日本語テキストです");
	EXPECT_EQ(m_doc->WordMoveTarget(P(0, 0), false), P(0, 1));		// a | +=
	EXPECT_EQ(m_doc->WordMoveTarget(P(0, 1), false), P(0, 3));		// += | b
	EXPECT_EQ(m_doc->WordMoveTarget(P(0, 5), false), P(0, 8));		// 日本語 | テキスト
	EXPECT_EQ(m_doc->WordMoveTarget(P(0, 8), false), P(0, 12));		// テキスト | です
	EXPECT_EQ(m_doc->WordMoveTarget(P(0, 12), true), P(0, 8));
}

//! 行头、行末：原版在行内找不到时返回失败（App 这时按一个字移动，跨到前后的行）
TEST_F(MacCursorTest, WordMoveAtLineEnds)
{
	SetText(u"abc\ndef");
	EXPECT_EQ(m_doc->WordMoveTarget(P(0, 3), false), std::nullopt);
	EXPECT_EQ(m_doc->WordMoveTarget(P(1, 0), true), std::nullopt);
	EXPECT_EQ(m_doc->WordMoveTarget(P(0, 0), false), P(0, 3));		// 行末也是停止的位置
	EXPECT_EQ(m_doc->WordMoveTarget(P(5, 0), false), std::nullopt);		// 范围外
}

// ---------------------------------------------------------------------------
// 前／次の段落へ
// ---------------------------------------------------------------------------

//! 0:a 1:b 2:(空) 3:c 4:d 5:(空) 6:(空白だけ) 7:e
TEST_F(MacCursorTest, NextParagraph)
{
	SetText(u"a\nb\n\nc\nd\n\n  \ne");
	EXPECT_EQ(m_doc->ParagraphTarget(0, true), 3);		// 非空行を飛ばし、空行も飛ばして次の段落の先頭
	EXPECT_EQ(m_doc->ParagraphTarget(3, true), 7);		// 空白だけの行も空行
	EXPECT_EQ(m_doc->ParagraphTarget(2, true), 3);		// 空行から：次の非空行
	EXPECT_EQ(m_doc->ParagraphTarget(7, true), 8);		// 最後の段落：[EOF] の行
	EXPECT_EQ(m_doc->ParagraphTarget(8, true), std::nullopt);
}

TEST_F(MacCursorTest, PrevParagraph)
{
	SetText(u"a\nb\n\nc\nd\n\n  \ne");
	EXPECT_EQ(m_doc->ParagraphTarget(7, false), 3);	// 前の段落の先頭
	EXPECT_EQ(m_doc->ParagraphTarget(3, false), 0);
	EXPECT_EQ(m_doc->ParagraphTarget(4, false), 3);		// 段落の途中からはその段落の先頭
	EXPECT_EQ(m_doc->ParagraphTarget(0, false), std::nullopt);
}

// ---------------------------------------------------------------------------
// 前／次の変更行へ
// ---------------------------------------------------------------------------

//! 0:one 1:two 2:THREE* 3:FOUR* 4:five 5:[EOF]
TEST_F(MacCursorTest, NextModifiedLine)
{
	OpenText("cursor-modified.txt", "one\ntwo\nthree\nfour\nfive\n");
	ASSERT_EQ(Result::Ok, m_doc->Replace(Range{ P(2, 0), P(3, 4) }, u"THREE\nFOUR"));
	SetSearchAll(true);
	auto j = m_doc->ModifiedLineTarget(P(0, 0), true);
	ASSERT_TRUE(j);
	EXPECT_EQ(j->position, P(2, 0));		// 変更行のブロックの先頭
	EXPECT_FALSE(j->wrapped);
	j = m_doc->ModifiedLineTarget(P(2, 0), true);
	ASSERT_TRUE(j);
	EXPECT_EQ(j->position, P(4, 0));		// ブロックの末尾（次の行頭）
	j = m_doc->ModifiedLineTarget(P(4, 0), true);
	ASSERT_TRUE(j);
	EXPECT_EQ(j->position, P(2, 0));		// 先頭から再検索
	EXPECT_TRUE(j->wrapped);

	SetSearchAll(false);
	EXPECT_EQ(m_doc->ModifiedLineTarget(P(4, 0), true), std::nullopt);
}

TEST_F(MacCursorTest, PrevModifiedLine)
{
	OpenText("cursor-modified2.txt", "one\ntwo\nthree\nfour\nfive\n");
	ASSERT_EQ(Result::Ok, m_doc->Replace(Range{ P(2, 0), P(3, 4) }, u"THREE\nFOUR"));
	SetSearchAll(true);
	auto j = m_doc->ModifiedLineTarget(P(5, 0), false);	// [EOF] から
	ASSERT_TRUE(j);
	EXPECT_EQ(j->position, P(4, 0));		// NEXT と同じ位置（ブロックの末尾の次の行）
	j = m_doc->ModifiedLineTarget(P(4, 0), false);
	ASSERT_TRUE(j);
	EXPECT_EQ(j->position, P(2, 0));
	EXPECT_FALSE(j->wrapped);

	// 変更がない文書：見つからない
	OpenText("cursor-modified3.txt", "one\ntwo\n");
	EXPECT_EQ(m_doc->ModifiedLineTarget(P(1, 0), false), std::nullopt);
	EXPECT_EQ(m_doc->ModifiedLineTarget(P(0, 0), true), std::nullopt);
}

// ---------------------------------------------------------------------------
// 行頭に移動：行頭の空白を飛ばす
// ---------------------------------------------------------------------------

TEST_F(MacCursorTest, IndentEnd)
{
	SetText(u"  \tabc\n    \nxyz\n");
	EXPECT_EQ(m_doc->IndentEnd(0, 0, 6), 3);	// 空白と TAB の後
	EXPECT_EQ(m_doc->IndentEnd(1, 0, 4), 0);	// 空白だけの行は行頭
	EXPECT_EQ(m_doc->IndentEnd(2, 0, 3), 0);	// インデントなし
	EXPECT_EQ(m_doc->IndentEnd(0, 0, 2), 0);	// 折り返しの範囲内が空白だけ
	EXPECT_EQ(m_doc->IndentEnd(9, 0, 3), 0);	// 範囲外
}
