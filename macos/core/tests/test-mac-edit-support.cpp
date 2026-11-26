/*! @file
	@brief 编辑辅助功能（计划第 44 步）的测试

	- 対括弧の検索（原版 CEditView::SearchBracket、SearchBracketForward、SearchBracketBackward）
	  期待值按原版的算法算出（注释里写了依据）。

	与 Windows 官方版的对照：data/editsupport/ 的样本用同样的操作得到的结果与 data/editsupport/expected/ 的文件相同。
	expected 的文件和 Windows 官方版（CI 的 edit-support-windows：macos/tools/editsupport/windows-edit-support.js
	在 sakura.exe 里运行同样的操作）的结果比较。
	环境变量 SAKURA_EDITSUPPORT_UPDATE=1 时不比较，写出 expected 的文件（更新时用）。
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
#include <sstream>
#include <string>

using namespace sakura::core;

namespace {

Position P(int line, int column) { return Position{ line, column }; }

class MacEditSupportTest : public ::testing::Test {
protected:
	void SetUp() override
	{
		ASSERT_TRUE(Startup());
		m_doc = Document::Create();
		ASSERT_NE(nullptr, m_doc);
	}
	void TearDown() override
	{
		m_doc.reset();
		Shutdown(false);
	}
	void SetText(const Text& text)
	{
		ASSERT_EQ(Result::Ok, m_doc->Replace(Range{ Position{}, m_doc->EndPosition() }, text));
	}
	//! F_BRACKETPAIR（mode 3）の移動先
	std::optional<Position> Pair(const Position& caret, bool checkPrev = true)
	{
		const auto r = m_doc->FindBracketPair(caret, checkPrev);
		if (!r) return std::nullopt;
		return r->pair;
	}
	std::unique_ptr<Document> m_doc;
};

namespace fs = std::filesystem;

fs::path DataDir()
{
	return fs::path(SAKURA_ROOT_DIR) / "macos" / "core" / "tests" / "data" / "editsupport";
}

//! 结果与 expected/<name>.txt 相同（SAKURA_EDITSUPPORT_UPDATE=1 时写出）
void CompareExpected(const char* name, const std::string& actual)
{
	const fs::path expected = DataDir() / "expected" / (std::string(name) + ".txt");
	if (const char* u = std::getenv("SAKURA_EDITSUPPORT_UPDATE"); u && std::string(u) == "1") {
		fs::create_directories(expected.parent_path());
		std::ofstream(expected, std::ios::binary) << actual;
		return;
	}
	std::ifstream in(expected, std::ios::binary);
	ASSERT_TRUE(in.good()) << expected;
	std::stringstream ss;
	ss << in.rdbuf();
	EXPECT_EQ(ss.str(), actual) << name;
}

bool Same(const std::optional<Position>& a, const Position& b)
{
	return a && a->line == b.line && a->column == b.column;
}

} // namespace

// カーソルの後ろの文字が開き括弧：対応する閉じ括弧（入れ子は数える）
TEST_F(MacEditSupportTest, BracketForwardNested)
{
	SetText(u"f(a(b)c)d");
	EXPECT_TRUE(Same(Pair(P(0, 1)), P(0, 7)));
	EXPECT_TRUE(Same(Pair(P(0, 3)), P(0, 5)));
}

// 閉じ括弧：対応する開き括弧へ（もう一度で元の位置）
TEST_F(MacEditSupportTest, BracketBackward)
{
	SetText(u"f(a(b)c)d");
	EXPECT_TRUE(Same(Pair(P(0, 7)), P(0, 1)));
	EXPECT_TRUE(Same(Pair(P(0, 5)), P(0, 3)));
}

// カーソルの後ろが括弧でないときは直前の文字（mode bit1）。結果の bracket は直前の文字の位置（原版 mode bit2）
TEST_F(MacEditSupportTest, BracketPreviousChar)
{
	SetText(u"(ab)c");
	EXPECT_TRUE(Same(Pair(P(0, 4)), P(0, 0)));		// ')' の後ろ
	const auto r = m_doc->FindBracketPair(P(0, 4), true);
	ASSERT_TRUE(r);
	EXPECT_EQ(0, r->bracket.line);
	EXPECT_EQ(3, r->bracket.column);
	EXPECT_FALSE(Pair(P(0, 4), false));				// 前方文字を調べない（mode bit1 = 0）
	EXPECT_FALSE(Pair(P(0, 2)));						// 前後とも括弧でない
	EXPECT_TRUE(Same(Pair(P(0, 1)), P(0, 3)));		// 後ろの 'a' は括弧ではない → 直前の '(' の対括弧
}

// 複数行、全角括弧、対応表の全部の組
TEST_F(MacEditSupportTest, BracketKinds)
{
	SetText(u"{\r\n  x;\r\n}\r\n");
	EXPECT_TRUE(Same(Pair(P(0, 0)), P(2, 0)));
	EXPECT_TRUE(Same(Pair(P(2, 0)), P(0, 0)));
	const char16_t* pairs[] = { u"()", u"[]", u"{}", u"<>", u"｢｣", u"【】", u"『』", u"「」", u"＜＞", u"≪≫", u"《》",
								u"（）", u"〈〉", u"｛｝", u"〔〕", u"［］", u"“”", u"〝〟" };
	for (const auto* pair : pairs) {
		Text t = Text(1, pair[0]) + u"あ" + Text(1, pair[1]);
		SetText(t);
		EXPECT_TRUE(Same(Pair(P(0, 0)), P(0, 2))) << static_cast<int>(pair[0]);
		EXPECT_TRUE(Same(Pair(P(0, 2)), P(0, 0))) << static_cast<int>(pair[0]);
		EXPECT_TRUE(IsBracketChar(pair[0]));
		EXPECT_TRUE(IsBracketChar(pair[1]));
	}
	EXPECT_FALSE(IsBracketChar(u'a'));
	EXPECT_FALSE(IsBracketChar(u'"'));
}

// 注釈や文字列の中でも区別しない（原版と同じ）、対応が無いときは失敗
TEST_F(MacEditSupportTest, BracketUnmatched)
{
	SetText(u"(a\")\"");
	EXPECT_TRUE(Same(Pair(P(0, 0)), P(0, 3)));
	SetText(u"((a)");
	EXPECT_FALSE(Pair(P(0, 0)));
	SetText(u"a))");
	EXPECT_FALSE(Pair(P(0, 2)));
	// 空の文書、最後の行の後ろ
	SetText(u"");
	EXPECT_FALSE(Pair(P(0, 0)));
	SetText(u"(\r\n");
	EXPECT_FALSE(Pair(P(1, 0)));
}

// サロゲートペアは飛ばす（原版 GetCharNext の nPos - cPos > 1）
TEST_F(MacEditSupportTest, BracketSkipsSurrogatePair)
{
	SetText(u"(\U00020BB7)");
	EXPECT_TRUE(Same(Pair(P(0, 0)), P(0, 3)));
	// 直前の文字がサロゲートペアのときは調べない（nCharSize == 1 のときだけ）
	SetText(u"a\U00020BB7");
	EXPECT_FALSE(Pair(P(0, 3)));
}

// 表示領域の中だけ探す（強調表示、mode bit0 = 0）：表示領域の終わりの行まで
TEST_F(MacEditSupportTest, BracketSearchArea)
{
	SetText(u"(\r\n\r\n\r\n)\r\n");
	// 0 行目から 3 行目まで表示：見つかる
	EXPECT_TRUE(m_doc->FindBracketPair(P(0, 0), false, Document::BracketSearchArea{ 0, 3 }));
	// 2 行目まで：見つからない（原版 nSearchNum = bottom - y、行ごとに減らして負になったら中断）
	EXPECT_FALSE(m_doc->FindBracketPair(P(0, 0), false, Document::BracketSearchArea{ 0, 2 }));
	// 逆方向：表示領域の先頭まで
	EXPECT_TRUE(m_doc->FindBracketPair(P(3, 0), false, Document::BracketSearchArea{ 0, 3 }));
	EXPECT_FALSE(m_doc->FindBracketPair(P(3, 0), false, Document::BracketSearchArea{ 1, 3 }));
}

// Windows 官方版との比較：各行の各位置から対括弧の検索をしたあとのカーソル（1 開始の論理位置、宏の $y:$x）
TEST_F(MacEditSupportTest, BracketWindowsComparison)
{
	ASSERT_EQ(Result::Ok, m_doc->Open((DataDir() / "brackets.txt").u16string()));
	std::string out;
	for (int y = 0; y < m_doc->LineCount(); ++y) {
		const Text text = m_doc->GetLine(y);
		for (int x = 0; x <= static_cast<int>(text.size()); ++x) {
			if (x < static_cast<int>(text.size()) && text[x] >= 0xDC00 && text[x] <= 0xDFFF) continue;
			Position to = P(y, x);
			if (const auto r = m_doc->FindBracketPair(P(y, x), true)) to = r->pair;
			out += std::to_string(y + 1) + ":" + std::to_string(x + 1) + " -> " + std::to_string(to.line + 1) + ":" + std::to_string(to.column + 1) + "\n";
		}
	}
	CompareExpected("bracket", out);
}
