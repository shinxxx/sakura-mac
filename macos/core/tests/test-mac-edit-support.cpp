/*! @file
	@brief 编辑辅助功能（计划第 44 步）的测试

	- 対括弧の検索（原版 CEditView::SearchBracket、SearchBracketForward、SearchBracketBackward）
	  期待值按原版的算法算出（注释里写了依据）。
	- ブックマーク（原版 CViewCommander_Bookmark.cpp、CBookmarkManager）：設定・解除、次・前、全解除、
	  パターンに一致する行をマーク、「最近使ったファイル」に保存する形式（GetBookMarks・SetBookMarks）と復元

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

// ----- ブックマーク -----

namespace {

std::string MarkedLines(const Document& doc)
{
	std::string s;
	for (int y = 0; y < doc.LineCount(); ++y) {
		if (doc.IsBookmarked(y)) s += (s.empty() ? "" : ",") + std::to_string(y + 1);
	}
	return s;
}

} // namespace

TEST_F(MacEditSupportTest, BookmarkSetResetAndFind)
{
	SetText(u"a\nb\nc\nd\ne\n");
	EXPECT_FALSE(m_doc->IsBookmarked(1));
	m_doc->ToggleBookmarks(1, 1);
	m_doc->ToggleBookmarks(3, 4);
	EXPECT_EQ("2,4,5", MarkedLines(*m_doc));
	m_doc->ToggleBookmarks(1, 3);	// 反転
	EXPECT_EQ("3,5", MarkedLines(*m_doc));
	bool wrapped = true;
	EXPECT_EQ(2, m_doc->FindBookmark(0, true, false, &wrapped));
	EXPECT_FALSE(wrapped);
	EXPECT_EQ(4, m_doc->FindBookmark(2, true, false));
	EXPECT_EQ(-1, m_doc->FindBookmark(4, true, false));
	EXPECT_EQ(2, m_doc->FindBookmark(4, true, true, &wrapped));	// 先頭から再検索
	EXPECT_TRUE(wrapped);
	EXPECT_EQ(2, m_doc->FindBookmark(4, false, false));
	EXPECT_EQ(-1, m_doc->FindBookmark(2, false, false));
	EXPECT_EQ(4, m_doc->FindBookmark(2, false, true, &wrapped));	// 末尾から再検索
	EXPECT_TRUE(wrapped);
	m_doc->ResetBookmarks();
	EXPECT_EQ("", MarkedLines(*m_doc));
	EXPECT_EQ(-1, m_doc->FindBookmark(0, true, true));
	// 編集で行が動いてもブックマークは行に付いていく（CDocLine のフラグ）
	m_doc->SetBookmark(2, true);
	ASSERT_EQ(Result::Ok, m_doc->Insert(P(0, 0), u"new\n"));
	EXPECT_EQ("4", MarkedLines(*m_doc));
}

// パターンに一致する行をマーク：既にマークのある行はそのまま、正規表現の错误
TEST_F(MacEditSupportTest, BookmarkPattern)
{
	SetText(u"ab\nAB\nxab\n\nab c\n");
	SearchOptions o;
	EXPECT_TRUE(m_doc->MarkPattern(u"ab", o));
	EXPECT_EQ("1,2,3,5", MarkedLines(*m_doc));
	m_doc->ResetBookmarks();
	o.matchCase = true;
	o.wholeWord = true;
	EXPECT_TRUE(m_doc->MarkPattern(u"ab", o));
	EXPECT_EQ("1,5", MarkedLines(*m_doc));
	SearchOptions re;
	re.regularExpression = true;
	EXPECT_TRUE(m_doc->MarkPattern(u"^$", re));
	EXPECT_EQ("1,4,5", MarkedLines(*m_doc));
	EXPECT_FALSE(m_doc->MarkPattern(u"(", re));
	EXPECT_FALSE(m_doc->GetLastSearchError().empty());
}

// 「最近使ったファイル」の形式（原版 ver2：差分の 32 進数）。旧形式（行番号,区切り）も読める
TEST_F(MacEditSupportTest, BookmarkListFormat)
{
	SetText(Text(60, u'\n'));
	EXPECT_EQ(u":0", m_doc->GetBookmarkList());
	// 0,2,5,9,42 行 → :00123x0（原版のコメントの例）
	for (int y : { 0, 2, 5, 9, 42 }) m_doc->SetBookmark(y, true);
	EXPECT_EQ(u":00123x0", m_doc->GetBookmarkList());
	m_doc->ResetBookmarks();
	m_doc->SetBookmarkList(u":00123x0");
	EXPECT_EQ("1,3,6,10,43", MarkedLines(*m_doc));
	m_doc->ResetBookmarks();
	m_doc->SetBookmarkList(u"1, 3,7");
	EXPECT_EQ("2,4,8", MarkedLines(*m_doc));
	m_doc->ResetBookmarks();
	m_doc->SetBookmarkList(u":0a");
	EXPECT_EQ("11", MarkedLines(*m_doc));
	m_doc->ResetBookmarks();
	m_doc->SetBookmarkList(u":1abc");	// 不明なバージョン
	EXPECT_EQ("", MarkedLines(*m_doc));
}

// 閉じるとき（AddToRecent）に「最近使ったファイル」に登録し、次に開いたときに復元する（共通設定「ブックマークを復元する」）
TEST_F(MacEditSupportTest, BookmarkRestoredFromRecent)
{
	const auto path = fs::path(std::getenv("HOME")) / "bookmark-restore.txt";
	{
		std::ofstream out(path, std::ios::binary);
		out << "1\n2\n3\n4\n";
	}
	ASSERT_EQ(Result::Ok, m_doc->Open(path.u16string()));
	m_doc->SetBookmark(1, true);
	m_doc->SetBookmark(3, true);
	m_doc->AddToRecent(P(0, 0), 0);
	auto other = Document::Create();
	ASSERT_EQ(Result::Ok, other->Open(path.u16string()));
	EXPECT_EQ("2,4", MarkedLines(*other));
	// 「ブックマークを復元する」を外すと復元しない
	const Text saved = GetCommonSetting(u"Common", u"m_bRestoreBookmarks").value_or(u"1");
	ASSERT_TRUE(SetCommonSetting(u"Common", u"m_bRestoreBookmarks", u"0"));
	auto third = Document::Create();
	ASSERT_EQ(Result::Ok, third->Open(path.u16string()));
	EXPECT_EQ("", MarkedLines(*third));
	ASSERT_TRUE(SetCommonSetting(u"Common", u"m_bRestoreBookmarks", saved));
}

// Windows 官方版との比較：bookmarks.txt で宏と同じ操作（windows-edit-support.js の「ブックマーク」）
TEST_F(MacEditSupportTest, BookmarkWindowsComparison)
{
	ASSERT_EQ(Result::Ok, m_doc->Open((DataDir() / "bookmarks.txt").u16string()));
	const int n = m_doc->LineCount();
	std::string out;
	auto marks = [&](const char* title) { out += std::string(title) + ": " + MarkedLines(*m_doc) + "\n"; };
	// 宏の MoveCursor(y, 2)：行の長さで止まる
	auto col = [&](int y) { return std::min(1, static_cast<int>(m_doc->GetLine(y).size())); };
	auto walk = [&](const char* title, bool searchAll) {
		std::string s;
		for (int y = 0; y < n; ++y) {
			const int nx = m_doc->FindBookmark(y, true, searchAll);
			const int px = m_doc->FindBookmark(y, false, searchAll);
			auto pos = [&](int found) {
				return found >= 0 ? std::to_string(found + 1) + ":1" : std::to_string(y + 1) + ":" + std::to_string(col(y) + 1);
			};
			s += (s.empty() ? "" : " ") + std::to_string(y + 1) + ">" + pos(nx) + "<" + pos(px);
		}
		out += std::string(title) + ": " + s + "\n";
	};
	m_doc->ToggleBookmarks(1, 1);
	m_doc->ToggleBookmarks(4, 4);
	marks("set 2,5");
	m_doc->ToggleBookmarks(2, 4);
	marks("toggle 3-5");
	m_doc->ToggleBookmarks(7, 8);
	marks("toggle 8-9");
	m_doc->ToggleBookmarks(0, 0);
	m_doc->ToggleBookmarks(0, 0);
	marks("toggle 1 twice");
	walk("next/prev searchAll", true);
	walk("next/prev", false);
	m_doc->ResetBookmarks();
	marks("reset");
	walk("no marks", false);
	SearchOptions o;
	m_doc->MarkPattern(u"ab", o);
	marks("pattern ab");
	o.matchCase = true;
	m_doc->MarkPattern(u"ab", o);
	marks("pattern ab case");
	m_doc->ResetBookmarks();
	SearchOptions w;
	w.wholeWord = true;
	m_doc->MarkPattern(u"ab", w);
	marks("pattern ab word");
	m_doc->ResetBookmarks();
	SearchOptions re;
	re.regularExpression = true;
	m_doc->MarkPattern(u"^\\s*$", re);
	marks("pattern regex blank");
	m_doc->MarkPattern(u"AB", o);
	marks("pattern AB case added");
	CompareExpected("bookmark", out);
}
