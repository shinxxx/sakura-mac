/*! @file
	@brief 查找与替换（计划第 32 步）的测试

	原版 cmd/CViewCommander_Search.cpp、CViewCommander_Bookmark.cpp（Command_JUMP）在核心库里的移植：
	- 次を検索・前を検索：从哪里开始找、长度 0 的匹配前进一个字、先頭（末尾）から再検索
	- 置換：置換対象（選択文字・選択始点挿入・選択終点追加・行削除）、正则表达式、クリップボードから貼り付け
	- すべて置換：整个文件和选择范围、「すべて置換」は置換の繰返し、之后的光标和选择
	- 指定行へジャンプ：改行単位・折り返し単位、PL/SQL
	- 查找文字的标记（検索文字列の色）、查找的设置和历史（sakura.ini）

	期待值是按原版的处理一步一步算出来的（注释里写了算法上的依据）。
*/
/*
	Copyright (C) 2026, Sakura Editor Organization

	SPDX-License-Identifier: Zlib
*/
#include "sakura_core/SakuraCore.h"

#include <gtest/gtest.h>

#include <string>

using namespace sakura::core;

namespace {

std::string Utf8(const Text& t)
{
	std::string s;
	for (char16_t c : t) {
		if (c < 0x80) {
			s += static_cast<char>(c);
		} else if (c < 0x800) {
			s += static_cast<char>(0xC0 | (c >> 6));
			s += static_cast<char>(0x80 | (c & 0x3F));
		} else {
			s += static_cast<char>(0xE0 | (c >> 12));
			s += static_cast<char>(0x80 | ((c >> 6) & 0x3F));
			s += static_cast<char>(0x80 | (c & 0x3F));
		}
	}
	return s;
}

#define EXPECT_TEXT(expected, actual) EXPECT_EQ(Utf8(expected), Utf8(actual))

Range R(int l1, int c1, int l2, int c2) { return Range{ Position{ l1, c1 }, Position{ l2, c2 } }; }
SearchView At(int line, int column) { return SearchView{ Position{ line, column }, std::nullopt }; }
SearchView Sel(const Range& r) { return SearchView{ r.from, r }; }

const SearchOptions kPlain{};
const SearchOptions kRegex{ true, false, false };
const SearchOptions kWord{ false, false, true };

class MacSearchTest : public ::testing::Test {
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
	static ReplaceOptions Rep(const SearchOptions& search = kPlain, ReplaceTarget target = ReplaceTarget::Selection)
	{
		ReplaceOptions o;
		o.search = search;
		o.target = target;
		return o;
	}
	std::unique_ptr<Document> m_doc;
};

} // namespace

// ---------------------------------------------------------------------------
// 次を検索・前を検索
// ---------------------------------------------------------------------------

TEST_F(MacSearchTest, SearchNextStartsAtSelectionEnd)
{
	SetText(u"abc abc\nabc\n");
	auto r = m_doc->SearchNext(u"abc", kPlain, At(0, 0), false);
	EXPECT_EQ(SearchStatus::Found, r.status);
	ASSERT_TRUE(r.view.selection);
	EXPECT_EQ(R(0, 0, 0, 3), *r.view.selection) << "光标上的匹配也找到";
	EXPECT_EQ((Position{ 0, 0 }), r.view.caret) << "光标在匹配的开头";

	r = m_doc->SearchNext(u"abc", kPlain, r.view, false);
	EXPECT_EQ(R(0, 4, 0, 7), *r.view.selection) << "从选择的末尾往后找";
	r = m_doc->SearchNext(u"abc", kPlain, r.view, false);
	EXPECT_EQ(R(1, 0, 1, 3), *r.view.selection);

	// 没有了：选择解除，光标在原来的选择末尾
	auto none = m_doc->SearchNext(u"abc", kPlain, r.view, false);
	EXPECT_EQ(SearchStatus::NotFound, none.status);
	EXPECT_FALSE(none.view.selection);
	EXPECT_EQ((Position{ 1, 3 }), none.view.caret);

	// 先頭から再検索する
	auto wrapped = m_doc->SearchNext(u"abc", kPlain, r.view, true);
	EXPECT_EQ(SearchStatus::Wrapped, wrapped.status);
	EXPECT_EQ(R(0, 0, 0, 3), *wrapped.view.selection);
}

TEST_F(MacSearchTest, SearchNextFromCaretInsideWordAndWrapStatus)
{
	SetText(u"x abc");
	// 光标在 abc 的中间：后面没有，从头再找到的是同一个（▼先頭から再検索しました）
	auto r = m_doc->SearchNext(u"abc", kPlain, At(0, 3), true);
	EXPECT_EQ(SearchStatus::Wrapped, r.status);
	EXPECT_EQ(R(0, 2, 0, 5), *r.view.selection);
	// 从文件开头找时不算再検索
	r = m_doc->SearchNext(u"abc", kPlain, At(0, 0), true);
	EXPECT_EQ(SearchStatus::Found, r.status);
	// 哪里都没有
	EXPECT_EQ(SearchStatus::NotFound, m_doc->SearchNext(u"zzz", kPlain, At(0, 3), true).status);
}

TEST_F(MacSearchTest, SearchPrevStartsAtCaret)
{
	SetText(u"abc abc\nabc\n");
	// [EOF] の行から：前の行の行末から探す
	auto r = m_doc->SearchPrev(u"abc", kPlain, At(2, 0), false);
	EXPECT_EQ(SearchStatus::Found, r.status);
	EXPECT_EQ(R(1, 0, 1, 3), *r.view.selection);
	EXPECT_EQ((Position{ 1, 0 }), r.view.caret);
	r = m_doc->SearchPrev(u"abc", kPlain, r.view, false);
	EXPECT_EQ(R(0, 4, 0, 7), *r.view.selection) << "光标（匹配的开头）之前开始的最后一个";
	r = m_doc->SearchPrev(u"abc", kPlain, r.view, false);
	EXPECT_EQ(R(0, 0, 0, 3), *r.view.selection);

	auto none = m_doc->SearchPrev(u"abc", kPlain, r.view, false);
	EXPECT_EQ(SearchStatus::NotFound, none.status);
	EXPECT_FALSE(none.view.selection);
	EXPECT_EQ((Position{ 0, 0 }), none.view.caret);

	// 末尾から再検索する（▲末尾から再検索しました）
	auto wrapped = m_doc->SearchPrev(u"abc", kPlain, r.view, true);
	EXPECT_EQ(SearchStatus::Wrapped, wrapped.status);
	EXPECT_EQ(R(1, 0, 1, 3), *wrapped.view.selection);
}

TEST_F(MacSearchTest, ZeroLengthMatchAdvancesOneCharacter)
{
	SetText(u"ab\ncd");
	auto r = m_doc->SearchNext(u"^", kRegex, At(0, 0), false);
	EXPECT_EQ(SearchStatus::Found, r.status);
	ASSERT_TRUE(r.view.selection);
	EXPECT_EQ(R(0, 0, 0, 0), *r.view.selection) << "长度 0 的匹配也是选择（原版 IsOne）";
	// 下一次从一个字后面开始，不会一直停在同一个地方
	r = m_doc->SearchNext(u"^", kRegex, r.view, false);
	EXPECT_EQ(R(1, 0, 1, 0), *r.view.selection);

	// 补充平面的字前进两个 UTF-16
	SetText(u"\U0001F600x");
	r = m_doc->SearchNext(u"", kRegex, At(0, 0), false);
	EXPECT_EQ(SearchStatus::NotFound, r.status) << "空的条件";
	r = m_doc->SearchNext(u"(?=x)|^", kRegex, At(0, 0), false);
	EXPECT_EQ(R(0, 0, 0, 0), *r.view.selection);
	r = m_doc->SearchNext(u"(?=x)|^", kRegex, r.view, false);
	EXPECT_EQ(R(0, 2, 0, 2), *r.view.selection);
}

TEST_F(MacSearchTest, SearchOptionsAndInvalidPattern)
{
	SetText(u"Apple apple pineapple");
	auto r = m_doc->SearchNext(u"apple", SearchOptions{ false, true, false }, At(0, 0), false);
	EXPECT_EQ(R(0, 6, 0, 11), *r.view.selection) << "英大文字と小文字を区別する";
	r = m_doc->SearchNext(u"apple", kWord, At(0, 7), false);
	EXPECT_EQ(R(0, 6, 0, 11), *r.view.selection) << "単語単位：光标所在的单词也算（CLineMatchFinder::FindIncludingWordAt）";
	r = m_doc->SearchNext(u"apple", kWord, At(0, 12), false);
	EXPECT_EQ(SearchStatus::NotFound, r.status) << "単語単位：pineapple には一致しない";

	r = m_doc->SearchNext(u"(abc", kRegex, At(0, 0), false);
	EXPECT_EQ(SearchStatus::InvalidPattern, r.status);
	EXPECT_FALSE(r.error.empty());
	EXPECT_TRUE(RegexpSyntaxError(u"(abc", false).has_value());
	EXPECT_FALSE(RegexpSyntaxError(u"a+b", true).has_value());
	EXPECT_FALSE(RegexpVersion().empty()) << "検索ダイアログに表示する bregonig のバージョン";
}

TEST_F(MacSearchTest, WordAtCaret)
{
	SetText(u"hello world\n");
	EXPECT_EQ(R(0, 6, 0, 11), m_doc->WordRangeAt(Position{ 0, 8 }));
	EXPECT_EQ(R(0, 0, 0, 5), m_doc->WordRangeAt(Position{ 0, 0 }));
	EXPECT_FALSE(m_doc->WordRangeAt(Position{ 1, 0 })) << "[EOF] の行";
	EXPECT_FALSE(m_doc->WordRangeAt(Position{ 5, 0 }));
}

// ---------------------------------------------------------------------------
// 置換
// ---------------------------------------------------------------------------

TEST_F(MacSearchTest, ReplaceReplacesCurrentMatchAndFindsNext)
{
	SetText(u"cat dog cat\n");
	auto r = m_doc->ReplaceNext(u"cat", u"lion", Rep(), At(0, 0));
	EXPECT_EQ(SearchStatus::Found, r.status);
	EXPECT_EQ(1, r.count);
	EXPECT_TEXT(u"lion dog cat\n", m_doc->GetText());
	EXPECT_EQ(SearchStatus::Found, r.next);
	EXPECT_EQ(R(0, 9, 0, 12), *r.view.selection) << "换了之后选中下一个";

	r = m_doc->ReplaceNext(u"cat", u"lion", Rep(), r.view);
	EXPECT_TEXT(u"lion dog lion\n", m_doc->GetText());
	EXPECT_EQ(SearchStatus::NotFound, r.next) << "原版显示「最後まで置換しました。」";
	EXPECT_FALSE(r.view.selection);
	EXPECT_EQ((Position{ 0, 13 }), r.view.caret) << "光标在换了的文字后面";

	// 一次置換是撤销的一步
	ASSERT_EQ(Result::Ok, m_doc->Undo());
	EXPECT_TEXT(u"lion dog cat\n", m_doc->GetText());

	// 没有要换的
	r = m_doc->ReplaceNext(u"zzz", u"x", Rep(), At(0, 0));
	EXPECT_EQ(SearchStatus::NotFound, r.status);
	EXPECT_EQ(0, r.count);
	EXPECT_TEXT(u"lion dog cat\n", m_doc->GetText());
}

TEST_F(MacSearchTest, ReplaceStartsAtSelectionStart)
{
	SetText(u"cat cat");
	// 选择不是匹配时：从选择的开头往后找
	auto r = m_doc->ReplaceNext(u"cat", u"X", Rep(), Sel(R(0, 1, 0, 2)));
	EXPECT_TEXT(u"cat X", m_doc->GetText());
	EXPECT_EQ(SearchStatus::NotFound, r.next);
	// 先頭から再検索する：下一次查找从头再找
	ReplaceOptions o = Rep();
	o.searchAll = true;
	SetText(u"cat cat");
	r = m_doc->ReplaceNext(u"cat", u"X", o, At(0, 4));
	EXPECT_TEXT(u"cat X", m_doc->GetText());
	EXPECT_EQ(SearchStatus::Wrapped, r.next);
	EXPECT_EQ(R(0, 0, 0, 3), *r.view.selection);
}

TEST_F(MacSearchTest, ReplaceTargets)
{
	// 選択始点挿入：插在匹配前面，下一次从匹配的后面找
	SetText(u"a cat");
	auto r = m_doc->ReplaceNext(u"cat", u"big ", Rep(kPlain, ReplaceTarget::InsertBefore), At(0, 0));
	EXPECT_TEXT(u"a big cat", m_doc->GetText());
	EXPECT_EQ((Position{ 0, 9 }), r.view.caret);

	// 選択終点追加
	SetText(u"a cat b cat");
	r = m_doc->ReplaceNext(u"cat", u"s", Rep(kPlain, ReplaceTarget::InsertAfter), At(0, 0));
	EXPECT_TEXT(u"a cats b cat", m_doc->GetText());
	EXPECT_EQ(R(0, 9, 0, 12), *r.view.selection);

	// 行削除
	SetText(u"keep\ncat line\nkeep2\n");
	r = m_doc->ReplaceNext(u"cat", u"ignored", Rep(kPlain, ReplaceTarget::DeleteLine), At(0, 0));
	EXPECT_TEXT(u"keep\nkeep2\n", m_doc->GetText());
	EXPECT_EQ((Position{ 1, 0 }), r.view.caret);
	// 改行のない最終行
	SetText(u"a\ncat");
	m_doc->ReplaceNext(u"cat", u"", Rep(kPlain, ReplaceTarget::DeleteLine), At(0, 0));
	EXPECT_TEXT(u"a\n", m_doc->GetText());
}

TEST_F(MacSearchTest, ReplaceWithRegularExpression)
{
	SetText(u"id=12 id=34");
	auto r = m_doc->ReplaceNext(u"id=([0-9]+)", u"[$1]", Rep(kRegex), At(0, 0));
	EXPECT_TEXT(u"[12] id=34", m_doc->GetText());
	EXPECT_EQ(R(0, 5, 0, 10), *r.view.selection);

	// 正则表达式的選択始点挿入は「置換後$&」
	SetText(u"id=12 id=34");
	r = m_doc->ReplaceNext(u"id=[0-9]+", u"x", Rep(kRegex, ReplaceTarget::InsertBefore), At(0, 0));
	EXPECT_TEXT(u"xid=12 id=34", m_doc->GetText());
	EXPECT_EQ(R(0, 7, 0, 12), *r.view.selection);
	SetText(u"id=12");
	m_doc->ReplaceNext(u"id=[0-9]+", u";", Rep(kRegex, ReplaceTarget::InsertAfter), At(0, 0));
	EXPECT_TEXT(u"id=12;", m_doc->GetText());

	// 长度 0 的匹配：连后面一个字一起换（不会无限地换）
	SetText(u"ab\ncd");
	r = m_doc->ReplaceNext(u"^", u"> ", Rep(kRegex), At(0, 0));
	EXPECT_TEXT(u"> ab\ncd", m_doc->GetText());
	EXPECT_EQ(R(1, 0, 1, 0), *r.view.selection);

	// 换行符：\r\n 的 \r 也一起换（原版：改行にかかっていたら行全体を置換）
	SetText(u"a\r\nb");
	m_doc->ReplaceNext(u"\\r\\n", u",", Rep(kRegex), At(0, 0));
	EXPECT_TEXT(u"a,b", m_doc->GetText());
}

TEST_F(MacSearchTest, ReplaceWithClipboardTextIsLiteral)
{
	SetText(u"cat");
	ReplaceOptions o = Rep(kRegex);
	o.paste = true;
	m_doc->ReplaceNext(u"c.t", u"$1&", o, At(0, 0));
	EXPECT_TEXT(u"$1&", m_doc->GetText()) << "クリップボードから貼り付けるときは正規表現の置換をしない";
}

// ---------------------------------------------------------------------------
// すべて置換
// ---------------------------------------------------------------------------

TEST_F(MacSearchTest, ReplaceAllWholeFile)
{
	SetText(u"cat cat\ndog cat\n");
	auto r = m_doc->ReplaceAll(u"cat", u"lion", Rep(), At(1, 2));
	EXPECT_EQ(3, r.count);
	EXPECT_TEXT(u"lion lion\ndog lion\n", m_doc->GetText());
	EXPECT_FALSE(r.view.selection);
	EXPECT_EQ((Position{ 1, 8 }), r.view.caret) << "最后换的文字后面";
	ASSERT_EQ(Result::Ok, m_doc->Undo());
	EXPECT_TEXT(u"cat cat\ndog cat\n", m_doc->GetText()) << "撤销的一步";

	// 没有可换的：光标到文件开头（原版 Command_GOFILETOP）
	r = m_doc->ReplaceAll(u"zzz", u"x", Rep(), At(1, 2));
	EXPECT_EQ(0, r.count);
	EXPECT_EQ((Position{ 0, 0 }), r.view.caret);

	// 「選択範囲」でも、選択がなければファイル全体
	ReplaceOptions o = Rep();
	o.selectedArea = true;
	r = m_doc->ReplaceAll(u"cat", u"x", o, At(0, 0));
	EXPECT_EQ(3, r.count);
}

TEST_F(MacSearchTest, ReplaceAllInSelection)
{
	ReplaceOptions o = Rep();
	o.selectedArea = true;

	// 选择 2、3 个 cat：选择的末尾跟着替换后的长度变化
	SetText(u"cat cat cat\ncat\n");
	auto r = m_doc->ReplaceAll(u"cat", u"lion", o, Sel(R(0, 4, 0, 11)));
	EXPECT_EQ(2, r.count);
	EXPECT_TEXT(u"cat lion lion\ncat\n", m_doc->GetText());
	ASSERT_TRUE(r.view.selection);
	EXPECT_EQ(R(0, 4, 0, 13), *r.view.selection);
	EXPECT_EQ((Position{ 0, 13 }), r.view.caret);

	// 选择的末尾在行首：那一行不算（原版 2007.01.19 ryoji）
	SetText(u"cat\ncat\ncat\n");
	r = m_doc->ReplaceAll(u"cat", u"x", o, Sel(R(0, 0, 2, 0)));
	EXPECT_EQ(2, r.count);
	EXPECT_TEXT(u"x\nx\ncat\n", m_doc->GetText());
	EXPECT_EQ(R(0, 0, 2, 0), *r.view.selection);

	// 选择的末尾在匹配的中间：这个不换
	SetText(u"cat cat");
	r = m_doc->ReplaceAll(u"cat", u"x", o, Sel(R(0, 0, 0, 5)));
	EXPECT_EQ(1, r.count);
	EXPECT_TEXT(u"x cat", m_doc->GetText());
	EXPECT_EQ(R(0, 0, 0, 3), *r.view.selection);

	// 正则表达式的一括置换：最后一行只换到选择的末尾
	SetText(u"aaaa");
	r = m_doc->ReplaceAll(u"a", u"b", Rep(kRegex), Sel(R(0, 1, 0, 3)));
	EXPECT_TEXT(u"bbbb", m_doc->GetText()) << "selectedArea 没打开：整个文件";
	SetText(u"aaaa");
	ReplaceOptions ro = Rep(kRegex);
	ro.selectedArea = true;
	r = m_doc->ReplaceAll(u"a", u"b", ro, Sel(R(0, 1, 0, 3)));
	EXPECT_EQ(2, r.count);
	EXPECT_TEXT(u"abba", m_doc->GetText());
	EXPECT_EQ(R(0, 1, 0, 3), *r.view.selection);
}

TEST_F(MacSearchTest, ReplaceAllConsecutive)
{
	// 一括置換：一行の中は一回の置換（^ は行頭だけ）
	SetText(u"aaa");
	auto r = m_doc->ReplaceAll(u"^a", u"", Rep(kRegex), At(0, 0));
	EXPECT_EQ(1, r.count);
	EXPECT_TEXT(u"aa", m_doc->GetText());

	// 「すべて置換」は置換の繰返し：置換したあとをまた探す
	SetText(u"aaa");
	ReplaceOptions o = Rep(kRegex);
	o.consecutiveAll = true;
	r = m_doc->ReplaceAll(u"^a", u"", o, At(0, 0));
	EXPECT_EQ(3, r.count);
	EXPECT_TEXT(u"", m_doc->GetText());

	// 每行的开头
	SetText(u"x\ny\n");
	r = m_doc->ReplaceAll(u"^", u"> ", Rep(kRegex), At(0, 0));
	EXPECT_EQ(2, r.count);
	EXPECT_TEXT(u"> x\n> y\n", m_doc->GetText());

	// 行末
	SetText(u"ab\n");
	r = m_doc->ReplaceAll(u"$", u";", o, At(0, 0));
	EXPECT_EQ(1, r.count);
	EXPECT_TEXT(u"ab;\n", m_doc->GetText());
	SetText(u"ab\n");
	r = m_doc->ReplaceAll(u"$", u";", Rep(kRegex), At(0, 0));
	EXPECT_EQ(1, r.count);
	EXPECT_TEXT(u"ab;\n", m_doc->GetText());
	// 改行のない最終行の行末：bregonig の BSubst は探し始める位置が行の長さと同じだと置換しない
	// （CBregexp::Replace のコメント「nLen = nStart のとき置換に失敗する」）。Windows 版も同じライブラリで同じ結果。
	// 置換できなかった一致の後ろから探し続けるので、止まる
	SetText(u"ab");
	r = m_doc->ReplaceAll(u"$", u";", o, At(0, 0));
	EXPECT_EQ(0, r.count);
	EXPECT_TEXT(u"ab", m_doc->GetText());
	r = m_doc->ReplaceAll(u"$", u";", Rep(kRegex), At(0, 0));
	EXPECT_EQ(0, r.count);
}

TEST_F(MacSearchTest, ReplaceAllTargets)
{
	SetText(u"cat cat");
	auto r = m_doc->ReplaceAll(u"cat", u"a ", Rep(kPlain, ReplaceTarget::InsertBefore), At(0, 0));
	EXPECT_EQ(2, r.count);
	EXPECT_TEXT(u"a cat a cat", m_doc->GetText());

	SetText(u"cat cat");
	r = m_doc->ReplaceAll(u"cat", u"s", Rep(kPlain, ReplaceTarget::InsertAfter), At(0, 0));
	EXPECT_TEXT(u"cats cats", m_doc->GetText());

	SetText(u"x cat\ny\ncat z\n");
	r = m_doc->ReplaceAll(u"cat", u"", Rep(kPlain, ReplaceTarget::DeleteLine), At(0, 0));
	EXPECT_EQ(2, r.count);
	EXPECT_TEXT(u"y\n", m_doc->GetText());

	SetText(u"cat1 cat2");
	r = m_doc->ReplaceAll(u"cat([0-9])", u"<$1>", Rep(kRegex, ReplaceTarget::InsertAfter), At(0, 0));
	EXPECT_TEXT(u"cat1<1> cat2<2>", m_doc->GetText());

	// 替换后的文字里含有查找的词，也不会无限替换
	SetText(u"cat");
	r = m_doc->ReplaceAll(u"cat", u"catcat", Rep(), At(0, 0));
	EXPECT_EQ(1, r.count);
	EXPECT_TEXT(u"catcat", m_doc->GetText());

	// 旧的接口（第 22 步）结果相同
	SetText(u"cat cat\ndog cat\n");
	EXPECT_EQ(3, m_doc->ReplaceAll(u"cat", u"lion"));
	EXPECT_TEXT(u"lion lion\ndog lion\n", m_doc->GetText());
}

// ---------------------------------------------------------------------------
// 指定行へジャンプ
// ---------------------------------------------------------------------------

TEST_F(MacSearchTest, JumpToLine)
{
	JumpOptions o;
	EXPECT_FALSE(m_doc->JumpPosition(o)) << "空的文档（原版 ErrorBeep）";

	SetText(u"0123456789abcdef\nx");
	ASSERT_TRUE(m_doc->SetWrap(WrapMethod::SettingWidth, 10));
	ASSERT_EQ(3, m_doc->LayoutLineCount());

	o.lineNumIsCRLF = true;
	o.lineNumber = 2;
	EXPECT_EQ((Position{ 1, 0 }), m_doc->JumpPosition(o)) << "改行単位";
	o.lineNumber = 0;
	EXPECT_EQ((Position{ 0, 0 }), m_doc->JumpPosition(o)) << "0 以下は 1 行目";
	o.lineNumber = 99;
	EXPECT_EQ(m_doc->EndPosition(), m_doc->JumpPosition(o));

	o.lineNumIsCRLF = false;
	o.lineNumber = 2;
	EXPECT_EQ((Position{ 0, 10 }), m_doc->JumpPosition(o)) << "折り返し単位：2 行目は折り返した後ろ";
	o.lineNumber = 99;
	EXPECT_EQ((Position{ 1, 0 }), m_doc->JumpPosition(o)) << "最後のレイアウト行";
}

TEST_F(MacSearchTest, JumpToPlsqlLine)
{
	SetText(u"-- c\n\nselect 1;\n/* x\n*/\nfoo;\n");
	JumpOptions o;
	o.plsql = true;
	o.plsqlBlockFirstLine = 1;
	o.lineNumber = 2;
	// 1 行目（-- コメント）が 1、空行は数えない、3 行目が 2
	EXPECT_EQ((Position{ 2, 0 }), m_doc->JumpPosition(o));
	o.lineNumber = 3;
	// /* と */ の行（コメントブロック）も数える
	EXPECT_EQ((Position{ 3, 0 }), m_doc->JumpPosition(o));
	o.plsqlBlockFirstLine = 3;
	o.lineNumber = 1;
	EXPECT_EQ((Position{ 2, 0 }), m_doc->JumpPosition(o)) << "テキストの 3 行目をブロックの 1 行目とする";
}

// ---------------------------------------------------------------------------
// 検索文字列の色
// ---------------------------------------------------------------------------

TEST_F(MacSearchTest, SearchMarks)
{
	SetText(u"apple Apple pineapple\nbanana apple\n");
	ASSERT_TRUE(m_doc->GetColor(ColorIndex::Search).display) << "原版の初期値：検索文字列は表示";
	auto marks = m_doc->SearchMarks(0, u"apple", kPlain);
	ASSERT_EQ(3u, marks.size());
	EXPECT_EQ(0, marks[0].from);
	EXPECT_EQ(5, marks[0].to);
	EXPECT_EQ(16, marks[2].from);
	EXPECT_EQ(static_cast<std::uint8_t>(ColorIndex::Search), marks[0].color);

	EXPECT_EQ(2u, m_doc->SearchMarks(0, u"apple", SearchOptions{ false, true, false }).size()) << "apple と pineapple";
	EXPECT_EQ(2u, m_doc->SearchMarks(0, u"apple", kWord).size());

	// 単語単位：検索語の 2 番目の単語は 2 番目に表示する色
	marks = m_doc->SearchMarks(1, u"apple banana", kWord);
	ASSERT_EQ(2u, marks.size());
	EXPECT_EQ(0, marks[0].from);
	const bool search2 = m_doc->GetColor(ColorIndex::Search2).display;
	EXPECT_EQ(static_cast<std::uint8_t>(search2 ? ColorIndex::Search2 : ColorIndex::Search), marks[0].color);
	EXPECT_EQ(static_cast<std::uint8_t>(ColorIndex::Search), marks[1].color);

	// 長さ 0 の一致は表示しない。条件に誤りがあれば何もない
	EXPECT_TRUE(m_doc->SearchMarks(0, u"^", kRegex).empty());
	EXPECT_TRUE(m_doc->SearchMarks(0, u"(a", kRegex).empty());
	EXPECT_EQ(3u, m_doc->SearchMarks(0, u"p+le", kRegex).size());
	EXPECT_TRUE(m_doc->SearchMarks(9, u"apple", kPlain).empty());
}

// ---------------------------------------------------------------------------
// 設定と履歴
// ---------------------------------------------------------------------------

TEST_F(MacSearchTest, SettingsAndHistorySurviveRestart)
{
	SearchSettings s = GetSearchSettings();
	s.options = SearchOptions{ true, true, false };
	s.notifyNotFound = true;
	s.autoCloseFind = true;
	s.autoCloseReplace = true;
	s.searchAll = true;
	s.consecutiveAll = true;
	s.selectedArea = true;
	s.jumpLineNumIsCRLF = false;
	SetSearchSettings(s);

	const auto seq = SearchKeySequence();
	AddSearchKey(u"first");
	AddSearchKey(u"second");
	AddReplaceKey(u"repl");
	EXPECT_EQ(seq + 2, SearchKeySequence());
	ASSERT_LE(2u, SearchKeyHistory().size());
	EXPECT_TEXT(u"second", SearchKeyHistory()[0]);
	EXPECT_TEXT(u"first", SearchKeyHistory()[1]);
	AddSearchKey(u"first");
	EXPECT_TEXT(u"first", SearchKeyHistory()[0]) << "同じ文字列は先頭に移る";
	AddSearchKey(Text(300, u'x'));
	EXPECT_TEXT(u"first", SearchKeyHistory()[0]) << "_MAX_PATH 以上は履歴に入れない";

	m_doc.reset();
	Shutdown(true);
	ASSERT_TRUE(Startup());
	m_doc = Document::Create();

	const SearchSettings t = GetSearchSettings();
	EXPECT_TRUE(t.options.regularExpression);
	EXPECT_TRUE(t.options.matchCase);
	EXPECT_FALSE(t.options.wholeWord);
	EXPECT_TRUE(t.notifyNotFound);
	EXPECT_TRUE(t.autoCloseFind);
	EXPECT_TRUE(t.autoCloseReplace);
	EXPECT_TRUE(t.searchAll);
	EXPECT_TRUE(t.consecutiveAll);
	EXPECT_TRUE(t.selectedArea);
	EXPECT_FALSE(t.jumpLineNumIsCRLF);
	ASSERT_LE(2u, SearchKeyHistory().size());
	EXPECT_TEXT(u"first", SearchKeyHistory()[0]);
	ASSERT_LE(1u, ReplaceKeyHistory().size());
	EXPECT_TEXT(u"repl", ReplaceKeyHistory()[0]);

	// 元に戻す（他のテストに影響しないように）
	SetSearchSettings(SearchSettings{});
	Shutdown(true);
	ASSERT_TRUE(Startup());
}
