/*! @file
	@brief 编辑辅助功能（计划第 44 步）的测试

	- 対括弧の検索（原版 CEditView::SearchBracket、SearchBracketForward、SearchBracketBackward）
	  期待值按原版的算法算出（注释里写了依据）。
	- ブックマーク（原版 CViewCommander_Bookmark.cpp、CBookmarkManager）：設定・解除、次・前、全解除、
	  パターンに一致する行をマーク、「最近使ったファイル」に保存する形式（GetBookMarks・SetBookMarks）と復元
	- インクリメンタルサーチの検索（開始位置をそのまま使う、後方の再検索の開始位置、MIGEMO）
	- DIFF差分表示：Mac 版自己实现的差分（Diff.cpp）的塊が GNU diff と同じ、行の印（原版 AnalyzeDiffInfo）、次・前の差分
	- ファイル内容比較（原版 Commander_COMPARE_core）
	- 入力補完（GetLeftWord、補完ファイル・編集中データ・強調キーワードの候補）、キーワードヘルプ（KeySearchCore）

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

#include <algorithm>
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
	// 宏の MoveCursor(y, 2) のあとのカーソル（Windows 版では空の行でも $x は 2）
	auto col = [&](int) { return 1; };
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

// ----- インクリメンタルサーチ -----

namespace {

std::string R(const std::optional<Range>& r)
{
	if (!r) return "none";
	return std::to_string(r->from.line) + ":" + std::to_string(r->from.column) + "-" + std::to_string(r->to.line) + ":" + std::to_string(r->to.column);
}

} // namespace

TEST_F(MacEditSupportTest, ISearchFind)
{
	SetText(u"abc abc\r\nxabc\r\nlast abc");
	const SearchOptions o;
	EXPECT_EQ("0:0-0:3", R(m_doc->ISearchFind(u"abc", P(0, 0), SearchDirection::Forward, o, false)));
	EXPECT_EQ("0:4-0:7", R(m_doc->ISearchFind(u"abc", P(0, 1), SearchDirection::Forward, o, false)));
	EXPECT_EQ("1:1-1:4", R(m_doc->ISearchFind(u"abc", P(1, 0), SearchDirection::Forward, o, false)));
	EXPECT_EQ("0:4-0:7", R(m_doc->ISearchFind(u"abc", P(1, 1), SearchDirection::Backward, o, false)));
	EXPECT_EQ("none", R(m_doc->ISearchFind(u"zzz", P(0, 0), SearchDirection::Forward, o, false)));
	EXPECT_EQ("none", R(m_doc->ISearchFind(u"abc", P(9, 0), SearchDirection::Forward, o, false)));
	// 後方の再検索の開始位置：最後の行の「改行を含む長さ - 1」（改行のない最後の行は最後の文字の前、原版と同じ）
	const Position wrap = m_doc->ISearchWrapBackwardStart();
	EXPECT_EQ(2, wrap.line);
	EXPECT_EQ(7, wrap.column);
	EXPECT_EQ("2:0-2:4", R(m_doc->ISearchFind(u"last", wrap, SearchDirection::Backward, o, false)));
	EXPECT_EQ("2:5-2:8", R(m_doc->ISearchFind(u"abc", wrap, SearchDirection::Backward, o, false)));	// 開始位置より前から始まる一致
	// 改行の途中からも検索できる（後方の再検索：CRLF の行は「改行を含む長さ - 1」が CR と LF の間）
	SetText(u"abc\r\n");
	EXPECT_EQ(0, m_doc->ISearchWrapBackwardStart().line);
	EXPECT_EQ(4, m_doc->ISearchWrapBackwardStart().column);
	EXPECT_EQ("0:0-0:3", R(m_doc->ISearchFind(u"abc", m_doc->ISearchWrapBackwardStart(), SearchDirection::Backward, o, false)));
	// 正規表現の错误は見つからない
	SearchOptions re;
	re.regularExpression = true;
	EXPECT_EQ("none", R(m_doc->ISearchFind(u"(", P(0, 0), SearchDirection::Forward, re, false)));
	EXPECT_FALSE(m_doc->GetLastSearchError().empty());
}

// MIGEMO：辞書がないときは使えない。辞書（共通設定『支援』の「辞書」）があればローマ字で日本語を探す
TEST_F(MacEditSupportTest, ISearchMigemo)
{
	ResetMigemo();
	const Text saved = GetCommonSetting(u"Common", u"szMigemoDict").value_or(u"");
	const auto dict = fs::path(std::getenv("HOME")) / "isearch-migemo-dict";
	fs::remove_all(dict);
	ASSERT_TRUE(SetCommonSetting(u"Common", u"szMigemoDict", dict.u16string()));
	EXPECT_EQ(MigemoStatus::NoDictionary, PrepareMigemo());
	EXPECT_EQ(u"sakura", MigemoQuery(u"sakura"));
	fs::create_directories(dict);
	fs::copy(fs::path(SAKURA_MIGEMO_DICT_DIR) / "utf-8", dict / "utf-8", fs::copy_options::recursive);
	EXPECT_EQ(MigemoStatus::Ready, PrepareMigemo());
	SetText(u"これはサクラエディタです");
	SearchOptions re;
	re.regularExpression = true;
	EXPECT_EQ("0:3-0:10", R(m_doc->ISearchFind(u"sakuraedhit", P(0, 0), SearchDirection::Forward, re, true)));	// サクラエディ[トテツチタ]
	EXPECT_EQ("none", R(m_doc->ISearchFind(u"sakuraedhit", P(0, 0), SearchDirection::Forward, re, false)));
	ResetMigemo();
	ASSERT_TRUE(SetCommonSetting(u"Common", u"szMigemoDict", saved));
	fs::remove_all(dict);
}

// ----- DIFF差分表示 -----

namespace {

std::string Hunks(const std::vector<DiffHunk>& hunks)
{
	std::string s;
	for (const auto& h : hunks) {
		const Text t = FormatDiffHunk(h);
		s += (s.empty() ? "" : " ") + std::string(t.begin(), t.end());
	}
	return s;
}

std::vector<Text> L(std::initializer_list<const char16_t*> xs)
{
	std::vector<Text> v;
	for (auto x : xs) v.emplace_back(x);
	return v;
}

Text ReadUtf8(const fs::path& path)
{
	std::ifstream in(path, std::ios::binary);
	std::string bytes((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
	Text r;
	for (size_t i = 0; i < bytes.size();) {
		const unsigned char c = static_cast<unsigned char>(bytes[i]);
		char32_t cp;
		int n;
		if (c < 0x80) { cp = c; n = 1; }
		else if ((c >> 5) == 0x6) { cp = c & 0x1F; n = 2; }
		else if ((c >> 4) == 0xE) { cp = c & 0x0F; n = 3; }
		else { cp = c & 0x07; n = 4; }
		for (int k = 1; k < n && i + k < bytes.size(); ++k) cp = (cp << 6) | (static_cast<unsigned char>(bytes[i + k]) & 0x3F);
		i += n;
		if (cp >= 0x10000) {
			cp -= 0x10000;
			r += char16_t(0xD800 + (cp >> 10));
			r += char16_t(0xDC00 + (cp & 0x3FF));
		} else {
			r += char16_t(cp);
		}
	}
	return r;
}

//! 原版 F_DIFF の選択肢（0x01 -i、0x02 -w、0x04 -b、0x08 -B、0x10 -t）
DiffOptions FlagsToOptions(int flags)
{
	DiffOptions o;
	o.ignoreCase = (flags & 0x01) != 0;
	o.ignoreAllSpace = (flags & 0x02) != 0;
	o.ignoreSpaceChange = (flags & 0x04) != 0;
	o.ignoreBlankLines = (flags & 0x08) != 0;
	o.expandTabs = (flags & 0x10) != 0;
	return o;
}

constexpr int kDiffFlags[] = { 0x00, 0x01, 0x02, 0x04, 0x08, 0x10, 0x0F };

std::vector<std::string> DiffCases()
{
	std::vector<std::string> names;
	for (const auto& e : fs::directory_iterator(DataDir() / "diff")) {
		if (e.is_directory()) names.push_back(e.path().filename().string());
	}
	std::sort(names.begin(), names.end());
	return names;
}

std::string Hex2(int n)
{
	static const char* digits = "0123456789abcdef";
	return std::string{ digits[(n >> 4) & 0xF], digits[n & 0xF] };
}

} // namespace

TEST_F(MacEditSupportTest, DiffHunks)
{
	const DiffOptions o;
	EXPECT_EQ("1a2", Hunks(ComputeDiff(L({ u"a", u"b" }), L({ u"a", u"X", u"b" }), o)));
	EXPECT_EQ("2,3d1", Hunks(ComputeDiff(L({ u"a", u"b", u"c", u"d" }), L({ u"a", u"d" }), o)));
	EXPECT_EQ("2c2", Hunks(ComputeDiff(L({ u"a", u"b", u"c" }), L({ u"a", u"B", u"c" }), o)));
	EXPECT_EQ("0a1,2", Hunks(ComputeDiff(L({}), L({ u"a", u"b" }), o)));
	EXPECT_EQ("1,2d0", Hunks(ComputeDiff(L({ u"a", u"b" }), L({}), o)));
	EXPECT_EQ("", Hunks(ComputeDiff(L({ u"a" }), L({ u"a" }), o)));
	// 同じ行が続くときは一番下の行を変更として出す（diff と同じ）
	EXPECT_EQ("4d3", Hunks(ComputeDiff(L({ u"x", u"a", u"a", u"a", u"y" }), L({ u"x", u"a", u"a", u"y" }), o)));
	// 選択肢
	DiffOptions ic; ic.ignoreCase = true;
	EXPECT_EQ("", Hunks(ComputeDiff(L({ u"Hello" }), L({ u"hello" }), ic)));
	DiffOptions w; w.ignoreAllSpace = true;
	EXPECT_EQ("", Hunks(ComputeDiff(L({ u"a b", u"c " }), L({ u"ab", u"\tc" }), w)));
	DiffOptions b; b.ignoreSpaceChange = true;
	EXPECT_EQ("2c2", Hunks(ComputeDiff(L({ u"a  b", u"ab", u"c " }), L({ u"a b", u"a b", u"c" }), b)));
	DiffOptions bl; bl.ignoreBlankLines = true;
	EXPECT_EQ("", Hunks(ComputeDiff(L({ u"a", u"", u"b" }), L({ u"a", u"b", u"" }), bl)));
	EXPECT_EQ("2d1 3a3", Hunks(ComputeDiff(L({ u"a", u"", u"b" }), L({ u"a", u"b", u"" }), o)));
	EXPECT_EQ("2a3", Hunks(ComputeDiff(L({ u"a", u"" }), L({ u"a", u"", u"c" }), bl)));
	// -B に -b・-w を付けると空白だけの行も空（GNU diff 2.8.7 と同じ）
	EXPECT_EQ("2d1", Hunks(ComputeDiff(L({ u"a", u"  ", u"b" }), L({ u"a", u"b" }), bl)));
	DiffOptions blw = bl; blw.ignoreAllSpace = true;
	EXPECT_EQ("", Hunks(ComputeDiff(L({ u"a", u"  ", u"b" }), L({ u"a", u"b" }), blw)));
	DiffOptions blb = bl; blb.ignoreSpaceChange = true;
	EXPECT_EQ("", Hunks(ComputeDiff(L({ u"a", u" \t", u"b" }), L({ u"a", u"b" }), blb)));
	// 行の分け方：LF、CR LF の CR は除く、改行のない最後の行は区別する
	const auto lines = SplitDiffLines(u"a\r\nb\rc\nd");
	ASSERT_EQ(3u, lines.size());
	EXPECT_EQ(u"a", lines[0]);
	EXPECT_EQ(u"b\rc", lines[1]);
	EXPECT_EQ(Text(u"d") + u'\0', lines[2]);
	EXPECT_EQ("2c2", Hunks(ComputeDiff(SplitDiffLines(u"a\nb"), SplitDiffLines(u"a\nb\n"), o)));
	// -b・-w では最後の改行の有無を区別しない（GNU diff 2.8.7 と同じ）
	EXPECT_EQ("", Hunks(ComputeDiff(SplitDiffLines(u"a\nb"), SplitDiffLines(u"a\nb\n"), w)));
	EXPECT_EQ("", Hunks(ComputeDiff(SplitDiffLines(u"a\nb"), SplitDiffLines(u"a\nb\n"), b)));
}

// 行の印（原版 AnalyzeDiffInfo）：編集中のファイルが新ファイル（既定）・旧ファイル、最後の行より後の削除、次・前の差分
TEST_F(MacEditSupportTest, DiffMarks)
{
	SetText(u"a\nX\nb\nc\n");
	EXPECT_FALSE(m_doc->IsDiffUsed());
	EXPECT_EQ(Document::DiffResult::Marked, m_doc->ApplyDiff(u"a\nb\nd\n", DiffOptions{}, false));
	EXPECT_TRUE(m_doc->IsDiffUsed());
	EXPECT_EQ(DiffMark::None, m_doc->GetDiffMark(0));
	EXPECT_EQ(DiffMark::Append, m_doc->GetDiffMark(1));
	EXPECT_EQ(DiffMark::Change, m_doc->GetDiffMark(3));
	bool wrapped = true;
	EXPECT_EQ(1, m_doc->FindDiffMark(0, true, false, &wrapped));
	EXPECT_FALSE(wrapped);
	EXPECT_EQ(3, m_doc->FindDiffMark(1, true, false));
	EXPECT_EQ(-1, m_doc->FindDiffMark(3, true, false));
	EXPECT_EQ(1, m_doc->FindDiffMark(3, true, true, &wrapped));
	EXPECT_TRUE(wrapped);
	EXPECT_EQ(1, m_doc->FindDiffMark(3, false, false));
	// 旧ファイル：相手で追加された所は「削除」（次の行に）、自分にしかない行は「追加」
	EXPECT_EQ(Document::DiffResult::Marked, m_doc->ApplyDiff(u"a\nX\nb\nc\nnew\n", DiffOptions{}, true));
	EXPECT_EQ(DiffMark::None, m_doc->GetDiffMark(1)) << "前の印は消える";
	EXPECT_EQ(DiffMark::DeleteAtEnd, m_doc->GetDiffMark(3));
	m_doc->ResetDiffMarks();
	EXPECT_FALSE(m_doc->IsDiffUsed());
	EXPECT_EQ(DiffMark::None, m_doc->GetDiffMark(3));
	EXPECT_EQ(Document::DiffResult::NoDiff, m_doc->ApplyDiff(u"a\nX\nb\nc\n", DiffOptions{}, false));
	EXPECT_FALSE(m_doc->IsDiffUsed());
	EXPECT_EQ(Document::DiffResult::Binary, m_doc->ApplyDiff(Text(u"a") + u'\0', DiffOptions{}, false));
}

// GNU diff（Windows 上的 diff.exe）との比較：diff/<名字>/old.txt と new.txt の塊の見出し
TEST_F(MacEditSupportTest, DiffWindowsComparison)
{
	std::string out;
	for (const auto& name : DiffCases()) {
		const auto oldLines = SplitDiffLines(ReadUtf8(DataDir() / "diff" / name / "old.txt"));
		const auto newLines = SplitDiffLines(ReadUtf8(DataDir() / "diff" / name / "new.txt"));
		for (int flags : kDiffFlags) {
			out += name + " " + Hex2(flags) + ": " + Hunks(ComputeDiff(oldLines, newLines, FlagsToOptions(flags))) + "\n";
		}
	}
	CompareExpected("diff", out);
}

// Windows 官方版との比較：開いたファイルと相手のファイルで DIFF差分表示 したときの各行の印（宏の Diff と GetLineAttribute）
TEST_F(MacEditSupportTest, DiffMarkWindowsComparison)
{
	std::string out;
	for (const auto& name : DiffCases()) {
		const fs::path dir = DataDir() / "diff" / name;
		for (int flags : kDiffFlags) {
			for (int side = 0; side < 2; ++side) {
				auto doc = Document::Create();
				auto other = Document::Create();
				ASSERT_EQ(Result::Ok, doc->Open((dir / (side ? "old.txt" : "new.txt")).u16string(), OpenOptions{}));
				ASSERT_EQ(Result::Ok, other->Open((dir / (side ? "new.txt" : "old.txt")).u16string(), OpenOptions{}));
				doc->ApplyDiff(other->GetText(), FlagsToOptions(flags), side == 1);
				std::string marks;
				for (int y = 0; y < doc->LineCount(); ++y) {
					marks += (y ? "," : "") + std::to_string(static_cast<int>(doc->GetDiffMark(y)));
				}
				out += name + " " + Hex2(flags | (side ? 0x20 : 0)) + ": " + marks + "\n";
			}
		}
	}
	CompareExpected("diffmark", out);
}

// ----- ファイル内容比較 -----

TEST_F(MacEditSupportTest, CompareWith)
{
	SetText(u"abc\r\ndef\r\n");
	auto other = Document::Create();
	ASSERT_EQ(Result::Ok, other->Replace(Range{ Position{}, other->EndPosition() }, u"abc\r\ndXf\r\n"));
	auto r = m_doc->CompareWith(*other, P(0, 0), P(0, 0));
	EXPECT_TRUE(r.different);
	EXPECT_EQ(1, r.mine.line);
	EXPECT_EQ(1, r.mine.column);
	EXPECT_EQ(1, r.theirs.line);
	EXPECT_EQ(1, r.theirs.column);
	// 異なる位置から：ずれていれば違う
	r = m_doc->CompareWith(*other, P(1, 2), P(1, 2));
	EXPECT_FALSE(r.different);
	// 改行の違い（CR LF と LF）も違い
	ASSERT_EQ(Result::Ok, other->Replace(Range{ Position{}, other->EndPosition() }, u"abc\ndef\n"));
	r = m_doc->CompareWith(*other, P(0, 0), P(0, 0));
	EXPECT_TRUE(r.different);
	EXPECT_EQ(0, r.mine.line);
	EXPECT_EQ(3, r.mine.column);
	// 長さの違い
	ASSERT_EQ(Result::Ok, other->Replace(Range{ Position{}, other->EndPosition() }, u"abc\r\ndef\r\nmore"));
	r = m_doc->CompareWith(*other, P(0, 0), P(0, 0));
	EXPECT_TRUE(r.different);
	EXPECT_EQ(2, r.mine.line);
	EXPECT_EQ(2, r.theirs.line);
}

// ----- 入力補完・キーワードヘルプ -----

namespace {

class TypeSetting {
public:
	TypeSetting(Document& doc, std::vector<std::pair<Text, Text>> values) : m_doc(doc)
	{
		m_section = u"Types(" + ToText16(std::to_string(doc.GetFileInfo().typeIndex)) + u")";
		for (const auto& [key, value] : values) {
			m_saved.emplace_back(key, GetCommonSetting(m_section, key).value_or(u""));
			EXPECT_TRUE(SetCommonSetting(m_section, key, value));
		}
		m_doc.ApplyTypeSettingChange(m_doc.GetFileInfo().typeIndex);
	}
	~TypeSetting()
	{
		for (const auto& [key, value] : m_saved) SetCommonSetting(m_section, key, value);
		m_doc.ApplyTypeSettingChange(m_doc.GetFileInfo().typeIndex);
	}
	static Text ToText16(const std::string& s) { return Text(s.begin(), s.end()); }

private:
	Document& m_doc;
	Text m_section;
	std::vector<std::pair<Text, Text>> m_saved;
};

std::string Join(const std::vector<Text>& v)
{
	std::string s;
	for (const auto& t : v) {
		if (!s.empty()) s += ",";
		for (char16_t c : t) s += c < 0x80 ? char(c) : '#';
	}
	return s;
}

} // namespace

// カーソル直前の単語（原版 GetLeftWord）
TEST_F(MacEditSupportTest, LeftWord)
{
	SetText(u"int value = val;\r\n\r\n日本語の単語\r\n");
	EXPECT_EQ(u"val", m_doc->LeftWord(P(0, 15)));
	EXPECT_EQ(u"va", m_doc->LeftWord(P(0, 6)));
	EXPECT_EQ(u";", m_doc->LeftWord(P(0, 16))) << "記号も単語（原版 WhereCurrentWord）";
	EXPECT_EQ(u"", m_doc->LeftWord(P(0, 4))) << "直前が空白";
	EXPECT_EQ(u"", m_doc->LeftWord(P(0, 0))) << "行頭";
	EXPECT_EQ(u"", m_doc->LeftWord(P(1, 0)));
	EXPECT_EQ(u"日本語", m_doc->LeftWord(P(2, 3)));
}

// 候補：補完ファイル、編集中データ（カーソルの単語は除く、重複は除く）、強調キーワード
TEST_F(MacEditSupportTest, HokanCandidates)
{
	const auto file = fs::path(std::getenv("HOME")) / "hokan-test.kwd";
	{
		std::ofstream out(file, std::ios::binary);
		out << "; comment\r\nprintf\r\nprint_r\r\nPrintln\r\nprintf\r\n";
	}
	SetText(u"print_value printer pri\r\nprinter Print\r\n");
	const Position caret = P(0, 23);
	{
		TypeSetting t(*m_doc, { { u"szHokanFile", file.u16string() }, { u"bUseHokanByFile", u"0" }, { u"bHokanLoHiCase", u"0" },
								 { u"bUseHokanByKeyword", u"0" } });
		EXPECT_EQ("printf,print_r,printf", Join(m_doc->HokanCandidates(u"pri", caret)));
	}
	{
		TypeSetting t(*m_doc, { { u"szHokanFile", file.u16string() }, { u"bUseHokanByFile", u"1" }, { u"bHokanLoHiCase", u"1" },
								 { u"bUseHokanByKeyword", u"0" } });
		EXPECT_EQ("printf,print_r,Println,printf,print_value,printer,Print", Join(m_doc->HokanCandidates(u"pri", caret)));
	}
	{
		TypeSetting t(*m_doc, { { u"szHokanFile", u"" }, { u"bUseHokanByFile", u"1" }, { u"bHokanLoHiCase", u"0" },
								 { u"bUseHokanByKeyword", u"0" } });
		EXPECT_EQ("print_value,printer", Join(m_doc->HokanCandidates(u"pri", caret)));
		EXPECT_TRUE(m_doc->SupportFilePaths().empty());
	}
	fs::remove(file);
}

// 強調キーワードを候補に（C/C++ の強調キーワード）
TEST_F(MacEditSupportTest, HokanByKeyword)
{
	const auto path = fs::path(std::getenv("HOME")) / "hokan-keyword.cpp";
	{
		std::ofstream out(path, std::ios::binary);
		out << "ret";
	}
	ASSERT_EQ(Result::Ok, m_doc->Open(path.u16string()));
	TypeSetting t(*m_doc, { { u"szHokanFile", u"" }, { u"bUseHokanByFile", u"0" }, { u"bHokanLoHiCase", u"0" },
							 { u"bUseHokanByKeyword", u"1" } });
	const auto words = m_doc->HokanCandidates(u"retu", P(0, 3));
	EXPECT_EQ("return", Join(words));
	fs::remove(path);
}

// キーワードヘルプ：辞書の書式（キー,キー /// 説明。\n と \x5C）、前方一致、キーワードも表示、ヒットした次の辞書も検索
TEST_F(MacEditSupportTest, KeywordHelp)
{
	const auto dict1 = fs::path(std::getenv("HOME")) / "help1.khp";
	const auto dict2 = fs::path(std::getenv("HOME")) / "help2.khp";
	{
		std::ofstream out(dict1, std::ios::binary);
		out << "; comment /// no\r\nprintf,fprintf /// print formatted\\nline2\r\nstrlen /// length \\x5C n\r\n";
	}
	{
		std::ofstream out(dict2, std::ios::binary);
		out << "printf /// second dictionary\r\n";
	}
	SetText(u"x");
	{
		TypeSetting t(*m_doc, { { u"bUseKeyWordHelp", u"1" }, { u"KDct[00]", u"1,one," + dict1.u16string() },
								 { u"KDct[01]", u"1,two," + dict2.u16string() }, { u"bUseKeyHelpAllSearch", u"0" },
								 { u"bUseKeyHelpKeyDisp", u"0" }, { u"bUseKeyHelpPrefix", u"0" } });
		EXPECT_TRUE(m_doc->UsesKeywordHelp());
		EXPECT_EQ(2u, m_doc->SupportFilePaths().size());
		auto r = m_doc->LookupKeywordHelp(u"fprintf");
		EXPECT_TRUE(r.hit);
		EXPECT_EQ(u"print formatted\nline2", r.info);
		EXPECT_EQ(0, r.dictionary);
		EXPECT_EQ(2, r.line);
		EXPECT_EQ(u"length \\ n", m_doc->LookupKeywordHelp(u"STRLEN").info) << "大文字小文字は区別しない";
		EXPECT_FALSE(m_doc->LookupKeywordHelp(u"comment").hit) << "; の行は見ない";
		EXPECT_FALSE(m_doc->LookupKeywordHelp(u"strl").hit) << "前方一致でなければ完全一致";
	}
	{
		TypeSetting t(*m_doc, { { u"bUseKeyWordHelp", u"1" }, { u"KDct[00]", u"1,one," + dict1.u16string() },
								 { u"KDct[01]", u"1,two," + dict2.u16string() }, { u"bUseKeyHelpAllSearch", u"1" },
								 { u"bUseKeyHelpKeyDisp", u"1" }, { u"bUseKeyHelpPrefix", u"1" } });
		auto r = m_doc->LookupKeywordHelp(u"pri");
		EXPECT_TRUE(r.hit);
		EXPECT_EQ(u"[ pri ]\n--------------------\n■help1\nprintf >>\nprint formatted\nline2\n--------------------\n■help2\nprintf >>\nsecond dictionary", r.info);
		EXPECT_EQ(0, r.dictionary);
	}
	fs::remove(dict1);
	fs::remove(dict2);
}
