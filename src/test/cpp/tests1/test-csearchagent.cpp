/*
	Copyright (C) 2021-2022, Sakura Editor Organization

	SPDX-License-Identifier: Zlib
*/

#include "pch.h"
#include "agent/CSaveAgent.h"

#include "cmd/COpeBlk.h"

#include <array>
#include <initializer_list>
#include <string>
#include <string_view>
#include <utility>
#include <vector>
#include "doc/logic/CDocLineMgr.h"
#include "agent/CSearchAgent.h"
#include "docplus/CBookmarkManager.h"
#include "extmodule/CBregexp.h"

#if defined(_WIN32)
#include "window/EditorTestSuite.hpp"
#else
#include "mac-share-data.hpp"	// Mac 版: 編集ウィンドウはまだないので、共通設定だけを用意する（移植計画のステップ 20）
#endif

using ::testing::ElementsAre;	// pch.h に using が無いのでここで宣言する

namespace {

template <typename T> void SetLines(CDocLineMgr& m, int seq, T begin, T end)
{
	for (auto it = begin; it != end; ++it) {
		CDocLine* line = m.AddNewLine();
		line->SetDocLineString(it->data(), it->length());
		line->m_sMark.m_cModified = seq;
	}
}

void SetLines(CDocLineMgr& m, int seq, std::initializer_list<sakura::wstring_view> args)
{
	SetLines(m, seq, args.begin(), args.end());
}

struct RawLineData {
	const WCHAR* line;
	int seq;
};

COpeLineData MakeOpeLineData(std::initializer_list<RawLineData> lines)
{
	COpeLineData data;
	for (RawLineData rawLine : lines) {
		CLineData line;
		line.cmemLine = rawLine.line;
		line.nSeq = rawLine.seq;
		data.push_back(line);
	}
	return data;
}

}

TEST(CDeleteOpe, Dump001)
{
	CDeleteOpe ope;

	// 呼ぶだけ
	ope.DUMP();
}

TEST(CInsertOpe, Dump001)
{
	CInsertOpe ope;

	// 呼ぶだけ
	ope.DUMP();
}

TEST(COpeBlk, AppendOpe001)
{
	COpeBlk blk;

	auto pOpe = new CReplaceOpe();
	pOpe->m_ptCaretPos_PHY_Before = CLogicPoint(0, 1);
	pOpe->m_ptCaretPos_PHY_After = CLogicPoint(0, 1);
	blk.AppendOpe(pOpe);

	// 呼ぶだけ
	blk.DUMP();
}

TEST(COpeBlk, AppendOpe101)
{
	COpeBlk blk;
	auto pOpe = new CMoveCaretOpe();
	blk.AppendOpe(pOpe);
}

/*!
	CSearchAgent::ReplaceData のテスト

	行の一部を置き換える。
 */
TEST(CSearchAgent, ReplaceData1)
{
	CDocLineMgr m;
	SetLines(m, 1, {LTEXT("AAA\n"), LTEXT("BBB\n"), LTEXT("CCC\n")});

	COpeLineData insData = MakeOpeLineData({{LTEXT("DDD"), 2}});
	COpeLineData delData;

	DocLineReplaceArg arg;
	arg.sDelRange = CLogicRange(CLogicPoint(0, 1), CLogicPoint(3, 1));
	arg.pcmemDeleted = &delData;
	arg.pInsData = &insData;
	arg.nDelSeq = 1;
	arg.nInsSeq = -1;
	CSearchAgent(&m).ReplaceData(&arg, false);

	EXPECT_EQ(m.GetLineCount(), 3);
	EXPECT_STREQ(m.GetLine(CLogicInt(0))->GetPtr(), LTEXT("AAA\n"));
	EXPECT_EQ(m.GetLine(CLogicInt(0))->m_sMark.m_cModified.GetSeq(), 1);
	EXPECT_STREQ(m.GetLine(CLogicInt(1))->GetPtr(), LTEXT("DDD\n"));
	EXPECT_EQ(m.GetLine(CLogicInt(1))->m_sMark.m_cModified.GetSeq(), 2);
	EXPECT_STREQ(m.GetLine(CLogicInt(2))->GetPtr(), LTEXT("CCC\n"));
	EXPECT_EQ(m.GetLine(CLogicInt(2))->m_sMark.m_cModified.GetSeq(), 1);

	EXPECT_EQ(arg.nInsSeq, 1);
	EXPECT_EQ(arg.pcmemDeleted->size(), 1);
	EXPECT_STREQ(arg.pcmemDeleted->at(0).cmemLine.GetStringPtr(), LTEXT("BBB"));
	EXPECT_EQ(arg.pcmemDeleted->at(0).nSeq, 1);
	EXPECT_EQ(arg.nDeletedLineNum, 0);
	EXPECT_EQ(arg.nInsLineNum, 0);
	EXPECT_EQ(arg.ptNewPos, CLogicPoint(3, 1));
}

/*!
	CSearchAgent::ReplaceData のテスト

	行全体を置き換える。
 */
TEST(CSearchAgent, ReplaceData2)
{
	CDocLineMgr m;
	SetLines(m, 1, {LTEXT("AAA\n"), LTEXT("BBB\n"), LTEXT("CCC\n")});

	COpeLineData insData = MakeOpeLineData({{LTEXT("DDD\n"), 2}});
	COpeLineData delData;

	DocLineReplaceArg arg;
	arg.sDelRange = CLogicRange(CLogicPoint(0, 1), CLogicPoint(4, 1));
	arg.pcmemDeleted = &delData;
	arg.pInsData = &insData;
	arg.nDelSeq = 1;
	arg.nInsSeq = -1;
	CSearchAgent(&m).ReplaceData(&arg, false);

	EXPECT_EQ(m.GetLineCount(), 3);
	EXPECT_STREQ(m.GetLine(CLogicInt(0))->GetPtr(), LTEXT("AAA\n"));
	EXPECT_EQ(m.GetLine(CLogicInt(0))->m_sMark.m_cModified.GetSeq(), 1);
	EXPECT_STREQ(m.GetLine(CLogicInt(1))->GetPtr(), LTEXT("DDD\n"));
	EXPECT_EQ(m.GetLine(CLogicInt(1))->m_sMark.m_cModified.GetSeq(), 2);
	EXPECT_STREQ(m.GetLine(CLogicInt(2))->GetPtr(), LTEXT("CCC\n"));
	EXPECT_EQ(m.GetLine(CLogicInt(2))->m_sMark.m_cModified.GetSeq(), 1);

	EXPECT_EQ(arg.nInsSeq, 0);
	EXPECT_EQ(arg.pcmemDeleted->size(), 1);
	EXPECT_STREQ(arg.pcmemDeleted->at(0).cmemLine.GetStringPtr(), LTEXT("BBB\n"));
	EXPECT_EQ(arg.pcmemDeleted->at(0).nSeq, 1);
	EXPECT_EQ(arg.nDeletedLineNum, 1);
	EXPECT_EQ(arg.nInsLineNum, 1);
	EXPECT_EQ(arg.ptNewPos, CLogicPoint(0, 2));
}

/*!
	CSearchAgent::ReplaceData のテスト

	行末の改行を削除する。
 */
TEST(CSearchAgent, ReplaceData3)
{
	CDocLineMgr m;
	SetLines(m, 1, {LTEXT("AAA\n"), LTEXT("BBB\n"), LTEXT("CCC\n")});

	COpeLineData delData;

	DocLineReplaceArg arg;
	arg.sDelRange = CLogicRange(CLogicPoint(3, 1), CLogicPoint(4, 1));
	arg.pcmemDeleted = &delData;
	arg.pInsData = nullptr;
	arg.nDelSeq = 1;
	arg.nInsSeq = -1;
	CSearchAgent(&m).ReplaceData(&arg, false);

	EXPECT_EQ(m.GetLineCount(), 2);
	EXPECT_STREQ(m.GetLine(CLogicInt(0))->GetPtr(), LTEXT("AAA\n"));
	EXPECT_EQ(m.GetLine(CLogicInt(0))->m_sMark.m_cModified.GetSeq(), 1);
	EXPECT_STREQ(m.GetLine(CLogicInt(1))->GetPtr(), LTEXT("BBBCCC\n"));
	EXPECT_EQ(m.GetLine(CLogicInt(1))->m_sMark.m_cModified.GetSeq(), 1);

	EXPECT_EQ(arg.nInsSeq, 0);
	EXPECT_EQ(arg.pcmemDeleted->size(), 2);
	EXPECT_STREQ(arg.pcmemDeleted->at(0).cmemLine.GetStringPtr(), LTEXT("\n"));
	EXPECT_EQ(arg.pcmemDeleted->at(0).nSeq, 1);
	EXPECT_STREQ(arg.pcmemDeleted->at(1).cmemLine.GetStringPtr(), LTEXT(""));
	EXPECT_EQ(arg.pcmemDeleted->at(1).nSeq, 1);
	EXPECT_EQ(arg.nDeletedLineNum, 1);
	EXPECT_EQ(arg.nInsLineNum, 0);
	EXPECT_EQ(arg.ptNewPos, CLogicPoint(3, 1));
}

/*!
	CSearchAgent::ReplaceData のテスト

	行末の改行を削除する。削除するデータ長が長いケース。
 */
TEST(CSearchAgent, ReplaceData4)
{
	CDocLineMgr m;
	SetLines(m, 1, {LTEXT("AAA\n"), LTEXT("BBB\n"), LTEXT("CCC\n")});

	COpeLineData delData;

	DocLineReplaceArg arg;
	arg.sDelRange = CLogicRange(CLogicPoint(1, 1), CLogicPoint(4, 1));
	arg.pcmemDeleted = &delData;
	arg.pInsData = nullptr;
	arg.nDelSeq = 1;
	arg.nInsSeq = -1;
	CSearchAgent(&m).ReplaceData(&arg, false);

	EXPECT_EQ(m.GetLineCount(), 2);
	EXPECT_STREQ(m.GetLine(CLogicInt(0))->GetPtr(), LTEXT("AAA\n"));
	EXPECT_EQ(m.GetLine(CLogicInt(0))->m_sMark.m_cModified.GetSeq(), 1);
	EXPECT_STREQ(m.GetLine(CLogicInt(1))->GetPtr(), LTEXT("BCCC\n"));
	EXPECT_EQ(m.GetLine(CLogicInt(1))->m_sMark.m_cModified.GetSeq(), 1);

	EXPECT_EQ(arg.nInsSeq, 0);
	EXPECT_EQ(arg.pcmemDeleted->size(), 2);
	EXPECT_STREQ(arg.pcmemDeleted->at(0).cmemLine.GetStringPtr(), LTEXT("BB\n"));
	EXPECT_EQ(arg.pcmemDeleted->at(0).nSeq, 1);
	EXPECT_STREQ(arg.pcmemDeleted->at(1).cmemLine.GetStringPtr(), LTEXT(""));
	EXPECT_EQ(arg.pcmemDeleted->at(1).nSeq, 1);
	EXPECT_EQ(arg.nDeletedLineNum, 1);
	EXPECT_EQ(arg.nInsLineNum, 0);
	EXPECT_EQ(arg.ptNewPos, CLogicPoint(1, 1));
}

/*!
	CSearchAgent::ReplaceData のテスト

	行末の改行を削除する。対象行がデータ末尾であるケース。
 */
TEST(CSearchAgent, ReplaceData5)
{
	CDocLineMgr m;
	SetLines(m, 1, {LTEXT("AAA\n")});

	COpeLineData delData;

	DocLineReplaceArg arg;
	arg.sDelRange = CLogicRange(CLogicPoint(3, 0), CLogicPoint(4, 0));
	arg.pcmemDeleted = &delData;
	arg.pInsData = nullptr;
	arg.nDelSeq = 1;
	arg.nInsSeq = -1;
	CSearchAgent(&m).ReplaceData(&arg, false);

	EXPECT_EQ(m.GetLineCount(), 1);
	EXPECT_STREQ(m.GetLine(CLogicInt(0))->GetPtr(), LTEXT("AAA"));
	EXPECT_EQ(m.GetLine(CLogicInt(0))->m_sMark.m_cModified.GetSeq(), 1);

	EXPECT_EQ(arg.nInsSeq, 0);
	EXPECT_EQ(arg.pcmemDeleted->size(), 1);
	EXPECT_STREQ(arg.pcmemDeleted->at(0).cmemLine.GetStringPtr(), LTEXT("\n"));
	EXPECT_EQ(arg.pcmemDeleted->at(0).nSeq, 1);
	EXPECT_EQ(arg.nDeletedLineNum, 0);
	EXPECT_EQ(arg.nInsLineNum, 0);
	EXPECT_EQ(arg.ptNewPos, CLogicPoint(3, 0));
}

/*!
	CSearchAgent::ReplaceData のテスト

	文字を挿入して複数行を連結する。
 */
TEST(CSearchAgent, ReplaceData6)
{
	CDocLineMgr m;
	SetLines(m, 1, {LTEXT("AAA\n"), LTEXT("BBB\n"), LTEXT("CCC\n")});

	COpeLineData insData = MakeOpeLineData({{LTEXT(" "), 2}});
	COpeLineData delData;

	DocLineReplaceArg arg;
	arg.sDelRange = CLogicRange(CLogicPoint(2, 1), CLogicPoint(1, 2));
	arg.pcmemDeleted = &delData;
	arg.pInsData = &insData;
	arg.nDelSeq = 1;
	arg.nInsSeq = -1;
	CSearchAgent(&m).ReplaceData(&arg, false);

	EXPECT_EQ(m.GetLineCount(), 2);
	EXPECT_STREQ(m.GetLine(CLogicInt(0))->GetPtr(), LTEXT("AAA\n"));
	EXPECT_EQ(m.GetLine(CLogicInt(0))->m_sMark.m_cModified.GetSeq(), 1);
	EXPECT_STREQ(m.GetLine(CLogicInt(1))->GetPtr(), LTEXT("BB CC\n"));
	EXPECT_EQ(m.GetLine(CLogicInt(1))->m_sMark.m_cModified.GetSeq(), 2);

	EXPECT_EQ(arg.nInsSeq, 1);
	EXPECT_EQ(arg.pcmemDeleted->size(), 2);
	EXPECT_STREQ(arg.pcmemDeleted->at(0).cmemLine.GetStringPtr(), LTEXT("B\n"));
	EXPECT_EQ(arg.pcmemDeleted->at(0).nSeq, 1);
	EXPECT_STREQ(arg.pcmemDeleted->at(1).cmemLine.GetStringPtr(), LTEXT("C"));
	EXPECT_EQ(arg.pcmemDeleted->at(1).nSeq, 1);
	EXPECT_EQ(arg.nDeletedLineNum, 1);
	EXPECT_EQ(arg.nInsLineNum, 0);
	EXPECT_EQ(arg.ptNewPos, CLogicPoint(3, 1));
}

/*!
	CSearchAgent::ReplaceData のテスト

	既存行の間に行を挿入し、次の行の先頭に文字を挿入する。
	先頭に文字を挿入した行がデータの末尾であるケース。
 */
TEST(CSearchAgent, ReplaceData7)
{
	CDocLineMgr m;
	SetLines(m, 1, {LTEXT("AAA\n"), LTEXT("BBB\n")});

	COpeLineData insData = MakeOpeLineData({{LTEXT("CCC\n"), 2}, {LTEXT("DDD"), 3}});
	COpeLineData delData;

	DocLineReplaceArg arg;
	arg.sDelRange = CLogicRange(CLogicPoint(0, 1), CLogicPoint(0, 1));
	arg.pcmemDeleted = &delData;
	arg.pInsData = &insData;
	arg.nDelSeq = 0;
	arg.nInsSeq = -1;
	CSearchAgent(&m).ReplaceData(&arg, false);

	EXPECT_EQ(m.GetLineCount(), 3);
	EXPECT_STREQ(m.GetLine(CLogicInt(0))->GetPtr(), LTEXT("AAA\n"));
	EXPECT_EQ(m.GetLine(CLogicInt(0))->m_sMark.m_cModified.GetSeq(), 1);
	EXPECT_STREQ(m.GetLine(CLogicInt(1))->GetPtr(), LTEXT("CCC\n"));
	EXPECT_EQ(m.GetLine(CLogicInt(1))->m_sMark.m_cModified.GetSeq(), 2);
	EXPECT_STREQ(m.GetLine(CLogicInt(2))->GetPtr(), LTEXT("DDDBBB\n"));
	EXPECT_EQ(m.GetLine(CLogicInt(2))->m_sMark.m_cModified.GetSeq(), 3);

	EXPECT_EQ(arg.nInsSeq, 1);
	EXPECT_TRUE(arg.pcmemDeleted->empty());
	EXPECT_EQ(arg.nDeletedLineNum, 0);
	EXPECT_EQ(arg.nInsLineNum, 1);
	EXPECT_EQ(arg.ptNewPos, CLogicPoint(3, 2));
}

/*!
	CSearchAgent::ReplaceData のテスト

	既存行の間に行を挿入し、次の行の先頭に文字を挿入する。
	先頭に文字を挿入した行がデータの末尾ではないケース。
 */
TEST(CSearchAgent, ReplaceData8)
{
	CDocLineMgr m;
	SetLines(m, 1, {LTEXT("AAA\n"), LTEXT("BBB\n"), LTEXT("CCC\n")});

	COpeLineData insData = MakeOpeLineData({{LTEXT("DDD\n"), 2}, {LTEXT("EEE"), 3}});
	COpeLineData delData;

	DocLineReplaceArg arg;
	arg.sDelRange = CLogicRange(CLogicPoint(0, 1), CLogicPoint(0, 1));
	arg.pcmemDeleted = &delData;
	arg.pInsData = &insData;
	arg.nDelSeq = 0;
	arg.nInsSeq = -1;
	CSearchAgent(&m).ReplaceData(&arg, false);

	EXPECT_EQ(m.GetLineCount(), 4);
	EXPECT_STREQ(m.GetLine(CLogicInt(0))->GetPtr(), LTEXT("AAA\n"));
	EXPECT_EQ(m.GetLine(CLogicInt(0))->m_sMark.m_cModified.GetSeq(), 1);
	EXPECT_STREQ(m.GetLine(CLogicInt(1))->GetPtr(), LTEXT("DDD\n"));
	EXPECT_EQ(m.GetLine(CLogicInt(1))->m_sMark.m_cModified.GetSeq(), 2);
	EXPECT_STREQ(m.GetLine(CLogicInt(2))->GetPtr(), LTEXT("EEEBBB\n"));
	EXPECT_EQ(m.GetLine(CLogicInt(2))->m_sMark.m_cModified.GetSeq(), 3);
	EXPECT_STREQ(m.GetLine(CLogicInt(3))->GetPtr(), LTEXT("CCC\n"));
	EXPECT_EQ(m.GetLine(CLogicInt(3))->m_sMark.m_cModified.GetSeq(), 1);

	EXPECT_EQ(arg.nInsSeq, 1);
	EXPECT_TRUE(arg.pcmemDeleted->empty());
	EXPECT_EQ(arg.nDeletedLineNum, 0);
	EXPECT_EQ(arg.nInsLineNum, 1);
	EXPECT_EQ(arg.ptNewPos, CLogicPoint(3, 2));
}

/*!
	CSearchAgent::ReplaceData のテスト

	既存行の末尾に新しい行を追加する。
 */
TEST(CSearchAgent, ReplaceData9)
{
	CDocLineMgr m;
	SetLines(m, 1, {LTEXT("AAA\n"), LTEXT("BBB\n")});

	COpeLineData insData = MakeOpeLineData({{LTEXT("CCC\n"), 2}});
	COpeLineData delData;

	DocLineReplaceArg arg;
	arg.sDelRange = CLogicRange(CLogicPoint(0, 2), CLogicPoint(0, 2));
	arg.pcmemDeleted = &delData;
	arg.pInsData = &insData;
	arg.nDelSeq = 0;
	arg.nInsSeq = -1;
	CSearchAgent(&m).ReplaceData(&arg, false);

	EXPECT_EQ(m.GetLineCount(), 3);
	EXPECT_STREQ(m.GetLine(CLogicInt(0))->GetPtr(), LTEXT("AAA\n"));
	EXPECT_EQ(m.GetLine(CLogicInt(0))->m_sMark.m_cModified.GetSeq(), 1);
	EXPECT_STREQ(m.GetLine(CLogicInt(1))->GetPtr(), LTEXT("BBB\n"));
	EXPECT_EQ(m.GetLine(CLogicInt(1))->m_sMark.m_cModified.GetSeq(), 1);
	EXPECT_STREQ(m.GetLine(CLogicInt(2))->GetPtr(), LTEXT("CCC\n"));
	EXPECT_EQ(m.GetLine(CLogicInt(2))->m_sMark.m_cModified.GetSeq(), 2);

	EXPECT_EQ(arg.nInsSeq, 0);
	EXPECT_TRUE(arg.pcmemDeleted->empty());
	EXPECT_EQ(arg.nDeletedLineNum, 0);
	EXPECT_EQ(arg.nInsLineNum, 1);
	EXPECT_EQ(arg.ptNewPos, CLogicPoint(0, 3));
}

/*!
	CSearchAgent::ReplaceData のテスト

	置換後の文字列が既存の行バッファの有効長に収まる場合の最適化済みコードパスの検査。
 */
TEST(CSearchAgent, ReplaceData10)
{
	CDocLineMgr m;
	SetLines(m, 1, {LTEXT("0123456789\n")});
	m.GetLine(CLogicInt(0))->_GetDocLineData().AllocStringBuffer(15);

	COpeLineData insData = MakeOpeLineData({{LTEXT("0123"), 2}});
	COpeLineData delData;

	DocLineReplaceArg arg;
	arg.sDelRange = CLogicRange(CLogicPoint(9, 0), CLogicPoint(10, 0));
	arg.pcmemDeleted = &delData;
	arg.pInsData = &insData;
	arg.nDelSeq = 0;
	arg.nInsSeq = -1;
	CSearchAgent(&m).ReplaceData(&arg, false);

	EXPECT_EQ(m.GetLineCount(), 1);
	EXPECT_STREQ(m.GetLine(CLogicInt(0))->GetPtr(), LTEXT("0123456780123\n"));
	EXPECT_EQ(m.GetLine(CLogicInt(0))->m_sMark.m_cModified.GetSeq(), 2);

	EXPECT_EQ(arg.nInsSeq, 1);
	EXPECT_EQ(arg.pcmemDeleted->size(), 1);
	EXPECT_STREQ(arg.pcmemDeleted->at(0).cmemLine.GetStringPtr(), LTEXT("9"));
	EXPECT_EQ(arg.pcmemDeleted->at(0).nSeq, 1);
	EXPECT_EQ(arg.nDeletedLineNum, 0);
	EXPECT_EQ(arg.nInsLineNum, 0);
	EXPECT_EQ(arg.ptNewPos, CLogicPoint(13, 0));
}

/*!
	@brief 文書の中の検索とブックマークの一括設定のテスト

	CSearchAgent::SearchWord() と CBookmarkManager::MarkSearchWord() の今の動きを固定する。
	単語単位は共有データの設定を読み、正規表現は bregonig.dll を読み込むので、共有データを用意する。
 */
struct CSearchAgentSearchTest : public ::testing::Test, public window::EditorTestSuite {
	static void SetUpTestSuite() { SetUpEditor(); }
	static void TearDownTestSuite() { TearDownEditor(); }

	CDocLineMgr m_cDocLineMgr;
	CBregexp m_cRegexp;
	SSearchOption m_sSearchOption;
	sakura::wstring m_strKey;
	CSearchStringPattern m_cPattern;

	//! 文書を作る。行の文字列には行末を含める
	void SetDocument(std::initializer_list<sakura::wstring_view> lines)
	{
		for (const auto& line : lines) {
			m_cDocLineMgr.AddNewLine()->SetDocLineString(line.data(), int(line.length()), false);
		}
	}

	//! 文字列の検索に使う文書
	void SetStringDocument()
	{
		SetDocument({ LTEXT("abc abcd abc\n"), LTEXT("xyz\n"), LTEXT("ABC\n"), LTEXT("abc") });
	}

	//! 単語単位の検索に使う文書
	void SetWordDocument()
	{
		SetDocument({ LTEXT("foo foobar foo_bar foo\n"), LTEXT("bar foo\n") });
	}

	//! ブックマークの一括設定に使う文書
	void SetBookmarkDocument()
	{
		SetDocument({ LTEXT("foo\n"), LTEXT("foobar\n"), LTEXT("bar foo\n"), LTEXT("FOO") });
	}

	//! 検索の条件を設定する
	bool SetKey(sakura::wstring_view key, bool bRegularExp, bool bLoHiCase, bool bWordOnly)
	{
		m_strKey = key;
		m_sSearchOption = SSearchOption(bRegularExp, bLoHiCase, bWordOnly);
		return m_cPattern.SetPattern(nullptr, m_strKey.c_str(), m_strKey.length(), m_sSearchOption, &m_cRegexp);
	}

	//! (x, y) から検索する。見つかれば { FromX, FromY, ToX, ToY }、見つからなければ空
	std::vector<int> Search(int x, int y, ESearchDirection eDirection)
	{
		CLogicRange range;
		if (const int nRet = CSearchAgent(&m_cDocLineMgr).SearchWord(CLogicPoint(x, y), eDirection, &range, m_cPattern); nRet == 0) {
			return {};
		}
		return { range.GetFrom().x, range.GetFrom().y, range.GetTo().x, range.GetTo().y };
	}

	//! ブックマークの付いている行の番号
	std::vector<int> BookmarkedLines()
	{
		std::vector<int> lines;
		for (int i = 0; i < m_cDocLineMgr.GetLineCount(); ++i) {
			if (CBookmarkGetter(m_cDocLineMgr.GetLine(CLogicInt(i))).IsBookmarked()) {
				lines.push_back(i);
			}
		}
		return lines;
	}
};

// ---------------------------------------------------------------------------
// SearchWord: 文字列
// ---------------------------------------------------------------------------

//! 前方: カーソルの位置の一致を返す
TEST_F(CSearchAgentSearchTest, StringForward)
{
	SetStringDocument();
	ASSERT_THAT(SetKey(LTEXT("abc"), false, true, false), IsTrue());
	EXPECT_THAT(Search(0, 0, SEARCH_FORWARD), ElementsAre(0, 0, 3, 0));
}

//! 前方: 行の途中から探す。単語の一部にも一致する
TEST_F(CSearchAgentSearchTest, StringForwardFromMiddleOfLine)
{
	SetStringDocument();
	ASSERT_THAT(SetKey(LTEXT("abc"), false, true, false), IsTrue());
	EXPECT_THAT(Search(1, 0, SEARCH_FORWARD), ElementsAre(4, 0, 7, 0));
}

//! 前方: 大文字小文字を区別すると、次の行の大文字は飛ばす
TEST_F(CSearchAgentSearchTest, StringForwardMatchCase)
{
	SetStringDocument();
	ASSERT_THAT(SetKey(LTEXT("abc"), false, true, false), IsTrue());
	EXPECT_THAT(Search(10, 0, SEARCH_FORWARD), ElementsAre(0, 3, 3, 3));
}

//! 前方: 大文字小文字を区別しない
TEST_F(CSearchAgentSearchTest, StringForwardIgnoreCase)
{
	SetStringDocument();
	ASSERT_THAT(SetKey(LTEXT("abc"), false, false, false), IsTrue());
	EXPECT_THAT(Search(10, 0, SEARCH_FORWARD), ElementsAre(0, 2, 3, 2));
}

//! 前方: 見つからない
TEST_F(CSearchAgentSearchTest, StringForwardNotFound)
{
	SetStringDocument();
	ASSERT_THAT(SetKey(LTEXT("zzz"), false, true, false), IsTrue());
	EXPECT_THAT(Search(0, 0, SEARCH_FORWARD), IsEmpty());
}

//! 前方: 重なる一致も見つける
TEST_F(CSearchAgentSearchTest, StringForwardOverlap)
{
	SetDocument({ LTEXT("aaa") });
	ASSERT_THAT(SetKey(LTEXT("aa"), false, true, false), IsTrue());
	EXPECT_THAT(Search(1, 0, SEARCH_FORWARD), ElementsAre(1, 0, 3, 0));
}

//! 後方: カーソルより前で最後の一致を返す
TEST_F(CSearchAgentSearchTest, StringBackward)
{
	SetStringDocument();
	ASSERT_THAT(SetKey(LTEXT("abc"), false, true, false), IsTrue());
	EXPECT_THAT(Search(9, 0, SEARCH_BACKWARD), ElementsAre(4, 0, 7, 0));
}

//! 後方: カーソルの位置から始まる一致は含めない
TEST_F(CSearchAgentSearchTest, StringBackwardExcludesCursorPosition)
{
	SetStringDocument();
	ASSERT_THAT(SetKey(LTEXT("abc"), false, true, false), IsTrue());
	EXPECT_THAT(Search(4, 0, SEARCH_BACKWARD), ElementsAre(0, 0, 3, 0));
}

//! 後方: 前の行へさかのぼる。大文字小文字を区別すると大文字の行は飛ばす
TEST_F(CSearchAgentSearchTest, StringBackwardPrevLinesMatchCase)
{
	SetStringDocument();
	ASSERT_THAT(SetKey(LTEXT("abc"), false, true, false), IsTrue());
	EXPECT_THAT(Search(0, 3, SEARCH_BACKWARD), ElementsAre(9, 0, 12, 0));
}

//! 後方: 前の行へさかのぼる。大文字小文字を区別しない
TEST_F(CSearchAgentSearchTest, StringBackwardPrevLinesIgnoreCase)
{
	SetStringDocument();
	ASSERT_THAT(SetKey(LTEXT("abc"), false, false, false), IsTrue());
	EXPECT_THAT(Search(0, 3, SEARCH_BACKWARD), ElementsAre(0, 2, 3, 2));
}

//! 後方: 文書の先頭より前には無い
TEST_F(CSearchAgentSearchTest, StringBackwardNotFoundAtTop)
{
	SetStringDocument();
	ASSERT_THAT(SetKey(LTEXT("abc"), false, true, false), IsTrue());
	EXPECT_THAT(Search(0, 0, SEARCH_BACKWARD), IsEmpty());
}

/*!
	後方: 行の先頭から一致の長さずつ進めて探すので、重なる一致は飛ばす

	"aaa" でカーソルが 3 のとき、1 から始まる一致は見つけず、0 から始まる一致を返す。
 */
TEST_F(CSearchAgentSearchTest, StringBackwardSkipsOverlap)
{
	SetDocument({ LTEXT("aaa") });
	ASSERT_THAT(SetKey(LTEXT("aa"), false, true, false), IsTrue());
	EXPECT_THAT(Search(3, 0, SEARCH_BACKWARD), ElementsAre(0, 0, 2, 0));
}

// ---------------------------------------------------------------------------
// SearchWord: 単語単位
// ---------------------------------------------------------------------------

//! 前方: 単語に一致する
TEST_F(CSearchAgentSearchTest, WordForward)
{
	SetWordDocument();
	ASSERT_THAT(SetKey(LTEXT("foo"), false, true, true), IsTrue());
	EXPECT_THAT(Search(0, 0, SEARCH_FORWARD), ElementsAre(0, 0, 3, 0));
}

//! 前方: 単語の一部(foobar・foo_bar)には一致しない
TEST_F(CSearchAgentSearchTest, WordForwardSkipsPartOfWord)
{
	SetWordDocument();
	ASSERT_THAT(SetKey(LTEXT("foo"), false, true, true), IsTrue());
	EXPECT_THAT(Search(3, 0, SEARCH_FORWARD), ElementsAre(19, 0, 22, 0));
}

//! 前方: 単語の途中から探すと、その単語の先頭から一致する(カーソルより前から始まる範囲を返す)
TEST_F(CSearchAgentSearchTest, WordForwardFromMiddleOfWord)
{
	SetWordDocument();
	ASSERT_THAT(SetKey(LTEXT("foo"), false, true, true), IsTrue());
	EXPECT_THAT(Search(20, 0, SEARCH_FORWARD), ElementsAre(19, 0, 22, 0));
}

//! 前方: 大文字小文字を区別しない
TEST_F(CSearchAgentSearchTest, WordForwardIgnoreCase)
{
	SetWordDocument();
	ASSERT_THAT(SetKey(LTEXT("FOO"), false, false, true), IsTrue());
	EXPECT_THAT(Search(0, 0, SEARCH_FORWARD), ElementsAre(0, 0, 3, 0));
}

//! 前方: 大文字小文字を区別する
TEST_F(CSearchAgentSearchTest, WordForwardMatchCase)
{
	SetWordDocument();
	ASSERT_THAT(SetKey(LTEXT("FOO"), false, true, true), IsTrue());
	EXPECT_THAT(Search(0, 0, SEARCH_FORWARD), IsEmpty());
}

//! 前方: 検索語が 2 つの単語なら、どちらかの単語に一致する
TEST_F(CSearchAgentSearchTest, WordForwardAnyWordOfKey)
{
	SetWordDocument();
	ASSERT_THAT(SetKey(LTEXT("foo bar"), false, true, true), IsTrue());
	EXPECT_THAT(Search(0, 1, SEARCH_FORWARD), ElementsAre(0, 1, 3, 1));
}

//! 前方: 単語の一部にしか無ければ見つからない
TEST_F(CSearchAgentSearchTest, WordForwardNotFound)
{
	SetDocument({ LTEXT("foobar foo_bar\n") });
	ASSERT_THAT(SetKey(LTEXT("foo"), false, true, true), IsTrue());
	EXPECT_THAT(Search(0, 0, SEARCH_FORWARD), IsEmpty());
}

//! 後方: 単語を 1 つずつさかのぼり、単語の一部は飛ばす
TEST_F(CSearchAgentSearchTest, WordBackward)
{
	SetWordDocument();
	ASSERT_THAT(SetKey(LTEXT("foo"), false, true, true), IsTrue());
	EXPECT_THAT(Search(19, 0, SEARCH_BACKWARD), ElementsAre(0, 0, 3, 0));
}

//! 後方: 単語の途中から探すと、その単語に一致する(カーソルより後ろまでの範囲を返す)
TEST_F(CSearchAgentSearchTest, WordBackwardFromMiddleOfWord)
{
	SetWordDocument();
	ASSERT_THAT(SetKey(LTEXT("foo"), false, true, true), IsTrue());
	EXPECT_THAT(Search(2, 0, SEARCH_BACKWARD), ElementsAre(0, 0, 3, 0));
}

//! 後方: 前の行の行末からさかのぼる
TEST_F(CSearchAgentSearchTest, WordBackwardPrevLine)
{
	SetWordDocument();
	ASSERT_THAT(SetKey(LTEXT("foo"), false, true, true), IsTrue());
	EXPECT_THAT(Search(0, 1, SEARCH_BACKWARD), ElementsAre(19, 0, 22, 0));
}

//! 後方: 文書の先頭より前には無い
TEST_F(CSearchAgentSearchTest, WordBackwardNotFoundAtTop)
{
	SetWordDocument();
	ASSERT_THAT(SetKey(LTEXT("foo"), false, true, true), IsTrue());
	EXPECT_THAT(Search(0, 0, SEARCH_BACKWARD), IsEmpty());
}

//! 後方: 大文字小文字を区別しないときだけ、前の行の単語に一致する
TEST_F(CSearchAgentSearchTest, WordBackwardIgnoreCase)
{
	SetWordDocument();
	ASSERT_THAT(SetKey(LTEXT("FOO"), false, false, true), IsTrue());
	EXPECT_THAT(Search(0, 1, SEARCH_BACKWARD), ElementsAre(19, 0, 22, 0));
	ASSERT_THAT(SetKey(LTEXT("FOO"), false, true, true), IsTrue());
	EXPECT_THAT(Search(0, 1, SEARCH_BACKWARD), IsEmpty());
}

// ---------------------------------------------------------------------------
// SearchWord: 正規表現
// ---------------------------------------------------------------------------

//! 前方: 一致の範囲を返す
TEST_F(CSearchAgentSearchTest, RegexForward)
{
	SetDocument({ LTEXT("abbbc abc\n") });
	ASSERT_THAT(SetKey(LTEXT("b+"), true, true, false), IsTrue());
	EXPECT_THAT(Search(0, 0, SEARCH_FORWARD), ElementsAre(1, 0, 4, 0));
}

//! 前方: 行の途中から探す
TEST_F(CSearchAgentSearchTest, RegexForwardFromMiddleOfLine)
{
	SetDocument({ LTEXT("abbbc abc\n") });
	ASSERT_THAT(SetKey(LTEXT("b+"), true, true, false), IsTrue());
	EXPECT_THAT(Search(2, 0, SEARCH_FORWARD), ElementsAre(2, 0, 4, 0));
}

//! 前方: 一致は行をまたがない。次の行へ進む
TEST_F(CSearchAgentSearchTest, RegexForwardNextLine)
{
	SetDocument({ LTEXT("abc\n"), LTEXT("xbz") });
	ASSERT_THAT(SetKey(LTEXT("b"), true, true, false), IsTrue());
	EXPECT_THAT(Search(2, 0, SEARCH_FORWARD), ElementsAre(1, 1, 2, 1));
}

//! 前方: 大文字小文字を区別しない
TEST_F(CSearchAgentSearchTest, RegexForwardIgnoreCase)
{
	SetDocument({ LTEXT("abc") });
	ASSERT_THAT(SetKey(LTEXT("B"), true, false, false), IsTrue());
	EXPECT_THAT(Search(0, 0, SEARCH_FORWARD), ElementsAre(1, 0, 2, 0));
}

//! 前方: 大文字小文字を区別する
TEST_F(CSearchAgentSearchTest, RegexForwardMatchCase)
{
	SetDocument({ LTEXT("abc") });
	ASSERT_THAT(SetKey(LTEXT("B"), true, true, false), IsTrue());
	EXPECT_THAT(Search(0, 0, SEARCH_FORWARD), IsEmpty());
}

//! 前方: 行頭(長さ 0)。行の途中から探すと、その行の行頭には一致せず、次の行の行頭に一致する
TEST_F(CSearchAgentSearchTest, RegexForwardLineHead)
{
	SetDocument({ LTEXT("abc\n"), LTEXT("def") });
	ASSERT_THAT(SetKey(LTEXT("^"), true, true, false), IsTrue());
	EXPECT_THAT(Search(0, 0, SEARCH_FORWARD), ElementsAre(0, 0, 0, 0));
	EXPECT_THAT(Search(1, 0, SEARCH_FORWARD), ElementsAre(0, 1, 0, 1));
}

//! 前方: 行末(長さ 0)は、CRLF の CR の前に一致する
TEST_F(CSearchAgentSearchTest, RegexForwardLineEnd)
{
	SetDocument({ LTEXT("abc\r\n"), LTEXT("def") });
	ASSERT_THAT(SetKey(LTEXT("$"), true, true, false), IsTrue());
	EXPECT_THAT(Search(0, 0, SEARCH_FORWARD), ElementsAre(3, 0, 3, 0));
}

//! 前方: 改行文字の中で一致したときは、一致の始まりを改行文字の始まりに直す(CRLF の LF に一致しても CR から)
TEST_F(CSearchAgentSearchTest, RegexForwardMatchInsideEol)
{
	SetDocument({ LTEXT("abc\r\n"), LTEXT("x\n") });
	ASSERT_THAT(SetKey(LTEXT("\\n"), true, true, false), IsTrue());
	EXPECT_THAT(Search(0, 0, SEARCH_FORWARD), ElementsAre(3, 0, 5, 0));
}

//! 前方: 改行文字の中から探し始めると、その行は探さずに次の行へ進む
TEST_F(CSearchAgentSearchTest, RegexForwardStartInsideEol)
{
	SetDocument({ LTEXT("abc\r\n"), LTEXT("x\n") });
	ASSERT_THAT(SetKey(LTEXT("\\n"), true, true, false), IsTrue());
	EXPECT_THAT(Search(4, 0, SEARCH_FORWARD), ElementsAre(1, 1, 2, 1));
}

//! 後方: カーソルより前で最後の一致を返す。カーソルの位置から始まる一致は含めない
TEST_F(CSearchAgentSearchTest, RegexBackward)
{
	SetDocument({ LTEXT("abcabc") });
	ASSERT_THAT(SetKey(LTEXT("b"), true, true, false), IsTrue());
	EXPECT_THAT(Search(5, 0, SEARCH_BACKWARD), ElementsAre(4, 0, 5, 0));
	EXPECT_THAT(Search(4, 0, SEARCH_BACKWARD), ElementsAre(1, 0, 2, 0));
}

//! 後方: 前の行へさかのぼる
TEST_F(CSearchAgentSearchTest, RegexBackwardPrevLine)
{
	SetDocument({ LTEXT("abc\n"), LTEXT("xyz") });
	ASSERT_THAT(SetKey(LTEXT("b"), true, true, false), IsTrue());
	EXPECT_THAT(Search(1, 1, SEARCH_BACKWARD), ElementsAre(1, 0, 2, 0));
}

//! 後方: 長さ 0 の一致の後は 1 文字進めて探すので、止まらずに行頭の一致を返す
TEST_F(CSearchAgentSearchTest, RegexBackwardZeroLength)
{
	SetDocument({ LTEXT("abc") });
	ASSERT_THAT(SetKey(LTEXT("^"), true, true, false), IsTrue());
	EXPECT_THAT(Search(2, 0, SEARCH_BACKWARD), ElementsAre(0, 0, 0, 0));
}

//! 正規表現・後方: 長さ 0 の一致の後は 1 文字(サロゲートペアは 2)進めるので、正字と異体字セレクタの間の一致も見つける
TEST_F(CSearchAgentSearchTest, RegexBackwardZeroLengthBeforeVariationSelector)
{
	SetDocument({ LTEXT("\u845B\U000E0100x") });	// 葛 + 異体字セレクタ(VS17) + x
	ASSERT_THAT(SetKey(LTEXT("^|\U000E0100"), true, true, false), IsTrue());
	EXPECT_THAT(Search(4, 0, SEARCH_BACKWARD), ElementsAre(1, 0, 3, 0));
}

//! 見つからない
TEST_F(CSearchAgentSearchTest, RegexNotFound)
{
	SetDocument({ LTEXT("abc\n"), LTEXT("xyz") });
	ASSERT_THAT(SetKey(LTEXT("q"), true, true, false), IsTrue());
	EXPECT_THAT(Search(0, 0, SEARCH_FORWARD), IsEmpty());
	EXPECT_THAT(Search(3, 1, SEARCH_BACKWARD), IsEmpty());
}

// ---------------------------------------------------------------------------
// MarkSearchWord
// ---------------------------------------------------------------------------

//! 文字列: 一致を含む行にブックマークを付ける
TEST_F(CSearchAgentSearchTest, MarkSearchWordString)
{
	SetBookmarkDocument();
	ASSERT_THAT(SetKey(LTEXT("foo"), false, true, false), IsTrue());
	CBookmarkManager(&m_cDocLineMgr).MarkSearchWord(m_cPattern);
	EXPECT_THAT(BookmarkedLines(), ElementsAre(0, 1, 2));
}

//! 単語単位: 単語の一部(foobar)の行には付けない
TEST_F(CSearchAgentSearchTest, MarkSearchWordWord)
{
	SetBookmarkDocument();
	ASSERT_THAT(SetKey(LTEXT("foo"), false, true, true), IsTrue());
	CBookmarkManager(&m_cDocLineMgr).MarkSearchWord(m_cPattern);
	EXPECT_THAT(BookmarkedLines(), ElementsAre(0, 2));
}

//! 単語単位: 大文字小文字を区別しない
TEST_F(CSearchAgentSearchTest, MarkSearchWordWordIgnoreCase)
{
	SetBookmarkDocument();
	ASSERT_THAT(SetKey(LTEXT("foo"), false, false, true), IsTrue());
	CBookmarkManager(&m_cDocLineMgr).MarkSearchWord(m_cPattern);
	EXPECT_THAT(BookmarkedLines(), ElementsAre(0, 2, 3));
}

//! 正規表現: 行頭から照合する
TEST_F(CSearchAgentSearchTest, MarkSearchWordRegex)
{
	SetBookmarkDocument();
	ASSERT_THAT(SetKey(LTEXT("^foo"), true, true, false), IsTrue());
	CBookmarkManager(&m_cDocLineMgr).MarkSearchWord(m_cPattern);
	EXPECT_THAT(BookmarkedLines(), ElementsAre(0, 1));
}

//! すでに付いているブックマークは、一致しなくても外さない
TEST_F(CSearchAgentSearchTest, MarkSearchWordKeepsBookmarks)
{
	SetBookmarkDocument();
	CBookmarkSetter(m_cDocLineMgr.GetLine(CLogicInt(3))).SetBookmark(true);
	ASSERT_THAT(SetKey(LTEXT("foo"), false, true, false), IsTrue());
	CBookmarkManager(&m_cDocLineMgr).MarkSearchWord(m_cPattern);
	EXPECT_THAT(BookmarkedLines(), ElementsAre(0, 1, 2, 3));
}

// ---------------------------------------------------------------------------
// イレギュラーケース
// ---------------------------------------------------------------------------

//! 空の検索語は、文字列でも単語単位でも見つからず、ブックマークも付けない
TEST_F(CSearchAgentSearchTest, EmptyKey)
{
	SetDocument({ LTEXT("abc\n") });
	ASSERT_THAT(SetKey(LTEXT(""), false, true, false), IsTrue());
	EXPECT_THAT(Search(0, 0, SEARCH_FORWARD), IsEmpty());
	EXPECT_THAT(Search(3, 0, SEARCH_BACKWARD), IsEmpty());
	ASSERT_THAT(SetKey(LTEXT(""), false, true, true), IsTrue());
	EXPECT_THAT(Search(0, 0, SEARCH_FORWARD), IsEmpty());
	CBookmarkManager(&m_cDocLineMgr).MarkSearchWord(m_cPattern);
	EXPECT_THAT(BookmarkedLines(), IsEmpty());
}

//! 単語単位: 区切り(空白・タブ・全角空白)だけの検索語は単語を含まないので見つからない。前後の区切りは無視する
TEST_F(CSearchAgentSearchTest, WordDelimiterOnlyKey)
{
	SetDocument({ LTEXT("foo bar\n"), LTEXT("foo") });
	ASSERT_THAT(SetKey(LTEXT(" \t　"), false, true, true), IsTrue());
	EXPECT_THAT(Search(0, 0, SEARCH_FORWARD), IsEmpty());
	EXPECT_THAT(Search(3, 1, SEARCH_BACKWARD), IsEmpty());
	ASSERT_THAT(SetKey(LTEXT("  foo  "), false, true, true), IsTrue());
	EXPECT_THAT(Search(0, 0, SEARCH_FORWARD), ElementsAre(0, 0, 3, 0));
	EXPECT_THAT(Search(3, 1, SEARCH_BACKWARD), ElementsAre(0, 1, 3, 1));
}

//! 空の文書・範囲外の行から探すと、見つからない
TEST_F(CSearchAgentSearchTest, EmptyDocumentAndOutOfRangeLine)
{
	ASSERT_THAT(SetKey(LTEXT("a"), false, true, false), IsTrue());
	EXPECT_THAT(Search(0, 0, SEARCH_FORWARD), IsEmpty());
	EXPECT_THAT(Search(0, 0, SEARCH_BACKWARD), IsEmpty());

	SetDocument({ LTEXT("abc\n") });
	EXPECT_THAT(Search(0, -1, SEARCH_FORWARD), IsEmpty());
	EXPECT_THAT(Search(0, 1, SEARCH_FORWARD), IsEmpty());
	EXPECT_THAT(Search(0, 5, SEARCH_BACKWARD), IsEmpty());
	ASSERT_THAT(SetKey(LTEXT("a"), false, true, true), IsTrue());
	EXPECT_THAT(Search(0, 1, SEARCH_FORWARD), IsEmpty());
	EXPECT_THAT(Search(0, 5, SEARCH_BACKWARD), IsEmpty());
}

//! 文字列: 検索語に改行文字を含めると、同じ行の行末までなら一致する。行はまたがない
TEST_F(CSearchAgentSearchTest, StringKeyContainsEol)
{
	SetDocument({ LTEXT("abc\r\n"), LTEXT("def") });
	ASSERT_THAT(SetKey(LTEXT("c\r\n"), false, true, false), IsTrue());
	EXPECT_THAT(Search(0, 0, SEARCH_FORWARD), ElementsAre(2, 0, 5, 0));
	ASSERT_THAT(SetKey(LTEXT("c\n"), false, true, false), IsTrue());
	EXPECT_THAT(Search(0, 0, SEARCH_FORWARD), IsEmpty());
	ASSERT_THAT(SetKey(LTEXT("c\r\ndef"), false, true, false), IsTrue());
	EXPECT_THAT(Search(0, 0, SEARCH_FORWARD), IsEmpty());
}

//! 行末が CR だけの行: 文字列は CR まで一致し、単語単位は前後の行へ進む
TEST_F(CSearchAgentSearchTest, CrOnlyLineEndings)
{
	SetDocument({ LTEXT("abc\r"), LTEXT("def\r"), LTEXT("ghi") });
	ASSERT_THAT(SetKey(LTEXT("c\r"), false, true, false), IsTrue());
	EXPECT_THAT(Search(0, 0, SEARCH_FORWARD), ElementsAre(2, 0, 4, 0));
	ASSERT_THAT(SetKey(LTEXT("def"), false, true, true), IsTrue());
	EXPECT_THAT(Search(0, 0, SEARCH_FORWARD), ElementsAre(0, 1, 3, 1));
	EXPECT_THAT(Search(3, 2, SEARCH_BACKWARD), ElementsAre(0, 1, 3, 1));
}

//! 文字列・後方: カーソルより前から始まり、カーソルをまたぐ一致を返す
TEST_F(CSearchAgentSearchTest, StringBackwardMatchStraddlesCursor)
{
	SetDocument({ LTEXT("abcabc") });
	ASSERT_THAT(SetKey(LTEXT("abc"), false, true, false), IsTrue());
	EXPECT_THAT(Search(5, 0, SEARCH_BACKWARD), ElementsAre(3, 0, 6, 0));
}

//! 単語単位・後方: 最後の行に行末が無くても、行末から単語をさかのぼる
TEST_F(CSearchAgentSearchTest, WordBackwardLastLineWithoutEol)
{
	SetDocument({ LTEXT("foo bar") });
	ASSERT_THAT(SetKey(LTEXT("bar"), false, true, true), IsTrue());
	EXPECT_THAT(Search(7, 0, SEARCH_BACKWARD), ElementsAre(4, 0, 7, 0));
	EXPECT_THAT(Search(6, 0, SEARCH_BACKWARD), ElementsAre(4, 0, 7, 0));
	EXPECT_THAT(Search(4, 0, SEARCH_BACKWARD), IsEmpty());
}

/*!
	単語単位・後方: カーソルが行末より右でも、行末とみなしてその行を探す

	今はその行を飛ばすので DISABLED_ にしている(#2743 の 1)。文字列の後方検索は同じ位置からその行を探す。
 */
TEST_F(CSearchAgentSearchTest, DISABLED_WordBackwardCursorPastTextSearchesLine)
{
	SetDocument({ LTEXT("abc\n"), LTEXT("abc") });
	ASSERT_THAT(SetKey(LTEXT("abc"), false, true, true), IsTrue());
	EXPECT_THAT(Search(4, 0, SEARCH_BACKWARD), ElementsAre(0, 0, 3, 0));
	EXPECT_THAT(Search(100, 1, SEARCH_BACKWARD), ElementsAre(0, 1, 3, 1));
}

//! 単語単位: 検索語の記号も 1 つの単語として扱う(a.b は a・.・b のどれかに一致する)
TEST_F(CSearchAgentSearchTest, WordKeyPunctuationIsAlsoAWord)
{
	SetDocument({ LTEXT("x.y\n") });
	ASSERT_THAT(SetKey(LTEXT("a.b"), false, true, true), IsTrue());
	EXPECT_THAT(Search(0, 0, SEARCH_FORWARD), ElementsAre(1, 0, 2, 0));
}

//! 単語単位: 全角空白は単語の区切り
TEST_F(CSearchAgentSearchTest, WordFullWidthSpaceIsDelimiter)
{
	SetDocument({ LTEXT("foobar foo　baz\n") });
	ASSERT_THAT(SetKey(LTEXT("foo　bar"), false, true, true), IsTrue());
	EXPECT_THAT(Search(0, 0, SEARCH_FORWARD), ElementsAre(7, 0, 10, 0));
}

//! 単語単位: ひらがなとカタカナの境目で単語が分かれる
TEST_F(CSearchAgentSearchTest, WordKanaBoundaries)
{
	SetDocument({ LTEXT("ひらがなカタカナ\n") });
	ASSERT_THAT(SetKey(LTEXT("カタカナ"), false, true, true), IsTrue());
	EXPECT_THAT(Search(0, 0, SEARCH_FORWARD), ElementsAre(4, 0, 8, 0));
	EXPECT_THAT(Search(8, 0, SEARCH_BACKWARD), ElementsAre(4, 0, 8, 0));
	ASSERT_THAT(SetKey(LTEXT("がな"), false, true, true), IsTrue());
	EXPECT_THAT(Search(0, 0, SEARCH_FORWARD), IsEmpty());
}

/*!
	単語単位: 長音「ー」は前後どちらの単語にも付く

	「あーカ」は「あ」から見ると「あー」「カ」、「カ」から見ると「あ」「ーカ」に分かれる。今の動きを固定する。
 */
TEST_F(CSearchAgentSearchTest, WordProlongedSoundMarkJoinsBothSides)
{
	SetDocument({ LTEXT("あーカ\n") });
	ASSERT_THAT(SetKey(LTEXT("あー"), false, true, true), IsTrue());
	EXPECT_THAT(Search(0, 0, SEARCH_FORWARD), ElementsAre(0, 0, 2, 0));
	ASSERT_THAT(SetKey(LTEXT("ーカ"), false, true, true), IsTrue());
	EXPECT_THAT(Search(0, 0, SEARCH_FORWARD), ElementsAre(1, 0, 3, 0));
	ASSERT_THAT(SetKey(LTEXT("カ"), false, true, true), IsTrue());
	EXPECT_THAT(Search(0, 0, SEARCH_FORWARD), IsEmpty());
	EXPECT_THAT(Search(3, 0, SEARCH_BACKWARD), IsEmpty());
}

/*!
	文字列: 検索語がサロゲートペアの片方だけ(UTF-16 のコード片)なら、文字の途中では一致しない

	今はペアの途中に一致するので DISABLED_ にしている(#2743 の 2)。
 */
TEST_F(CSearchAgentSearchTest, DISABLED_StringKeyDoesNotCutCharacter)
{
	SetDocument({ LTEXT("\U00020BB7\n") });	// 𠮷
	ASSERT_THAT(SetKey(LTEXT("\xDFB7"), false, true, false), IsTrue());
	EXPECT_THAT(Search(0, 0, SEARCH_FORWARD), IsEmpty());
	ASSERT_THAT(SetKey(LTEXT("\xD842"), false, true, false), IsTrue());
	EXPECT_THAT(Search(0, 0, SEARCH_FORWARD), IsEmpty());
}

//! 正規表現: 行末(長さ 0)は、LF・CR・行末なしのどの行でも改行文字の前に一致する
TEST_F(CSearchAgentSearchTest, RegexLineEndEachEol)
{
	ASSERT_THAT(SetKey(LTEXT("$"), true, true, false), IsTrue());
	SetDocument({ LTEXT("abc\n"), LTEXT("abc\r"), LTEXT("abc") });
	EXPECT_THAT(Search(0, 0, SEARCH_FORWARD), ElementsAre(3, 0, 3, 0));
	EXPECT_THAT(Search(0, 1, SEARCH_FORWARD), ElementsAre(3, 1, 3, 1));
	EXPECT_THAT(Search(0, 2, SEARCH_FORWARD), ElementsAre(3, 2, 3, 2));
}

//! 正規表現・後方: 行末(長さ 0)はカーソルの位置から始まるので含めず、カーソルより後ろからなら一致する
TEST_F(CSearchAgentSearchTest, RegexBackwardLineEnd)
{
	SetDocument({ LTEXT("abc") });
	ASSERT_THAT(SetKey(LTEXT("$"), true, true, false), IsTrue());
	EXPECT_THAT(Search(3, 0, SEARCH_BACKWARD), IsEmpty());
	EXPECT_THAT(Search(4, 0, SEARCH_BACKWARD), ElementsAre(3, 0, 3, 0));
}

//! 正規表現・後方: 前の行へさかのぼると、その行の行末(長さ 0)に一致する
TEST_F(CSearchAgentSearchTest, RegexBackwardPrevLineEnd)
{
	SetDocument({ LTEXT("ab\n"), LTEXT("cd") });
	ASSERT_THAT(SetKey(LTEXT("$"), true, true, false), IsTrue());
	EXPECT_THAT(Search(0, 1, SEARCH_BACKWARD), ElementsAre(2, 0, 2, 0));
}

//! 正規表現: 「.」は改行文字に一致しないので、改行だけの行を飛ばす
TEST_F(CSearchAgentSearchTest, RegexDotSkipsEol)
{
	SetDocument({ LTEXT("\r\n"), LTEXT("ab") });
	ASSERT_THAT(SetKey(LTEXT("."), true, true, false), IsTrue());
	EXPECT_THAT(Search(0, 0, SEARCH_FORWARD), ElementsAre(0, 1, 1, 1));
}

//! 正規表現: 「\r」は CRLF の CR だけに一致する(改行文字の途中までの範囲を返す)
TEST_F(CSearchAgentSearchTest, RegexCrInsideCrlf)
{
	SetDocument({ LTEXT("abc\r\n") });
	ASSERT_THAT(SetKey(LTEXT("\\r"), true, true, false), IsTrue());
	EXPECT_THAT(Search(0, 0, SEARCH_FORWARD), ElementsAre(3, 0, 4, 0));
}

/*!
	@brief 1 行の中で一致を探す部品(CLineMatchFinder)のテスト

	Grep・Grep 置換が、1 行の中の一致を前から順に探すのに使う。
	検索の条件の準備(共有データ・SetKey())は CSearchAgentSearchTest のものを使う。
 */
struct CLineMatchFinderTest : public CSearchAgentSearchTest {
	//! 行の先頭から順に探し、見つかった一致を { 始まり, 長さ, 始まり, 長さ, ... } で返す
	std::vector<int> FindAll(sakura::wstring_view line)
	{
		const CLineMatchFinder finder(m_cPattern, &m_cRegexp);
		const auto nLineLen = static_cast<int>(line.length());
		std::vector<int> result;
		int nStart = 0;
		while (const auto match = finder.Find(line.data(), nLineLen, nStart)) {
			result.push_back(match->nIndex);
			result.push_back(match->nLength);
			nStart = CLineMatchFinder::GetNextStart(line.data(), nLineLen, *match);
		}
		return result;
	}

	//! nStart から 1 つ探す。見つかれば { 始まり, 長さ }、見つからなければ空
	std::vector<int> Find(sakura::wstring_view line, int nStart)
	{
		const CLineMatchFinder finder(m_cPattern, &m_cRegexp);
		const auto match = finder.Find(line.data(), static_cast<int>(line.length()), nStart);
		if (!match) {
			return {};
		}
		return { match->nIndex, match->nLength };
	}
};

//! 文字列: 一致の後ろから次を探すので、重なる一致は数えない
TEST_F(CLineMatchFinderTest, StringDoesNotOverlap)
{
	ASSERT_THAT(SetKey(LTEXT("aa"), false, true, false), IsTrue());
	EXPECT_THAT(FindAll(LTEXT("aaaaa\n")), ElementsAre(0, 2, 2, 2));
}

//! 文字列: 大文字と小文字を区別しない
TEST_F(CLineMatchFinderTest, StringIgnoreCase)
{
	ASSERT_THAT(SetKey(LTEXT("ab"), false, false, false), IsTrue());
	EXPECT_THAT(FindAll(LTEXT("Ab xaB")), ElementsAre(0, 2, 4, 2));
}

//! 文字列: 見つからない・検索語が行より長い
TEST_F(CLineMatchFinderTest, StringNotFound)
{
	ASSERT_THAT(SetKey(LTEXT("ab"), false, true, false), IsTrue());
	EXPECT_THAT(FindAll(LTEXT("xyz")), IsEmpty());
	EXPECT_THAT(FindAll(LTEXT("a")), IsEmpty());
}

//! 単語単位: 単語の一部(foobar・foo_bar の foo)は飛ばす
TEST_F(CLineMatchFinderTest, WordSkipsPartOfWord)
{
	ASSERT_THAT(SetKey(LTEXT("foo"), false, true, true), IsTrue());
	EXPECT_THAT(FindAll(LTEXT("foo foobar foo_bar foo\n")), ElementsAre(0, 3, 19, 3));
	EXPECT_THAT(FindAll(LTEXT("foobar")), IsEmpty());
}

//! 単語単位: 検索語が 2 単語なら、どちらにも一致する
TEST_F(CLineMatchFinderTest, WordMultipleWordsKey)
{
	ASSERT_THAT(SetKey(LTEXT("foo bar"), false, true, true), IsTrue());
	EXPECT_THAT(FindAll(LTEXT("bar x foo")), ElementsAre(0, 3, 6, 3));
}

//! 単語単位: 単語の途中から探すと、その単語は飛ばす
TEST_F(CLineMatchFinderTest, WordStartInsideWord)
{
	ASSERT_THAT(SetKey(LTEXT("foo"), false, true, true), IsTrue());
	EXPECT_THAT(Find(LTEXT("foofoo foo"), 1), ElementsAre(7, 3));
}

//! 単語単位: 探し始める位置を含む単語が検索語と同じでも、探し始める位置より前から始まるなら飛ばす
TEST_F(CLineMatchFinderTest, WordContainingStart)
{
	ASSERT_THAT(SetKey(LTEXT("foo"), false, true, true), IsTrue());
	EXPECT_THAT(Find(LTEXT("foo foo"), 1), ElementsAre(4, 3));
	EXPECT_THAT(Find(LTEXT("foo foo"), 3), ElementsAre(4, 3));
}

//! 単語単位(FindIncludingWordAt): 探し始める位置を含む単語が検索語と同じなら、その単語の先頭を返す(探し始める位置より前でも)
TEST_F(CLineMatchFinderTest, WordIncludingWordAt)
{
	ASSERT_THAT(SetKey(LTEXT("foo"), false, true, true), IsTrue());
	const CLineMatchFinder finder(m_cPattern, &m_cRegexp);
	constexpr sakura::wstring_view line = LTEXT("foo foo");
	const auto match = finder.FindIncludingWordAt(line.data(), static_cast<int>(line.length()), 1);
	ASSERT_THAT(match.has_value(), IsTrue());
	EXPECT_THAT(match->nIndex, Eq(0));
	EXPECT_THAT(match->nLength, Eq(3));
}

//! 単語単位: 長音「ー」は前後どちらの単語にも付くので、一致の終わりから探すと前の一致に重なる単語が見つかる。重なる一致は返さない
TEST_F(CLineMatchFinderTest, WordOverlapByProlongedSoundMark)
{
	ASSERT_THAT(SetKey(LTEXT("あー ーカ"), false, true, true), IsTrue());
	EXPECT_THAT(FindAll(LTEXT("あーカ")), ElementsAre(0, 2));
}

//! 正規表現: 1 行の中の一致をすべて探す
TEST_F(CLineMatchFinderTest, RegexFindsEachMatch)
{
	ASSERT_THAT(SetKey(LTEXT("[0-9]+"), true, true, false), IsTrue());
	EXPECT_THAT(FindAll(LTEXT("a1b22\r\n")), ElementsAre(1, 1, 3, 2));
	EXPECT_THAT(FindAll(LTEXT("abc\r\n")), IsEmpty());
}

//! 正規表現: 長さ 0 の一致(行頭・行末)は、同じ位置で 2 回数えない
TEST_F(CLineMatchFinderTest, RegexZeroLength)
{
	ASSERT_THAT(SetKey(LTEXT("^"), true, true, false), IsTrue());
	EXPECT_THAT(FindAll(LTEXT("ab\r\n")), ElementsAre(0, 0));
	ASSERT_THAT(SetKey(LTEXT("$"), true, true, false), IsTrue());
	EXPECT_THAT(FindAll(LTEXT("ab")), ElementsAre(2, 0));
}

//! 正規表現と単語単位の両方を指定したときは、正規表現で探す
TEST_F(CLineMatchFinderTest, RegexTakesPrecedenceOverWord)
{
	ASSERT_THAT(SetKey(LTEXT("fo+"), true, true, true), IsTrue());
	EXPECT_THAT(FindAll(LTEXT("foo foobar")), ElementsAre(0, 3, 4, 3));
}

//! 探し始める位置が行の長さ以上なら、見つからない
//! (行の長さちょうどは CBregexp::Match() が一致にしない。行の長さより後ろは部品が探さない)
TEST_F(CLineMatchFinderTest, StartBeyondLine)
{
	ASSERT_THAT(SetKey(LTEXT("$"), true, true, false), IsTrue());
	EXPECT_THAT(Find(LTEXT("ab"), 1), ElementsAre(2, 0));
	EXPECT_THAT(Find(LTEXT("ab"), 2), IsEmpty());
	EXPECT_THAT(Find(LTEXT("ab"), 3), IsEmpty());
}

/*!
	@brief CSearchStringPattern::CompileRegexp() のテスト

	SetPattern() で設定したパターンを別の CBregexp にコンパイルし、その CBregexp で探した結果を確かめる。
 */
struct CompileRegexpTest : public CLineMatchFinderTest {
	CBregexp m_cOtherRegexp;

	//! 別の CBregexp を使って、行の先頭から順に探す
	std::vector<int> FindAllWithOther(sakura::wstring_view line)
	{
		const CLineMatchFinder finder(m_cPattern, &m_cOtherRegexp);
		const auto nLineLen = static_cast<int>(line.length());
		std::vector<int> result;
		int nStart = 0;
		while (const auto match = finder.Find(line.data(), nLineLen, nStart)) {
			result.push_back(match->nIndex);
			result.push_back(match->nLength);
			nStart = CLineMatchFinder::GetNextStart(line.data(), nLineLen, *match);
		}
		return result;
	}
};

//! 正規表現: 別の CBregexp でも、同じ一致になる
TEST_F(CompileRegexpTest, SameMatches)
{
	ASSERT_THAT(SetKey(LTEXT("H.T"), true, true, false), IsTrue());
	ASSERT_THAT(m_cPattern.CompileRegexp(m_cOtherRegexp), IsTrue());
	EXPECT_THAT(FindAllWithOther(LTEXT("xHIT HAT hit\n")), ElementsAre(1, 3, 5, 3));
	EXPECT_THAT(FindAllWithOther(LTEXT("xHIT HAT hit\n")), ::testing::ContainerEq(FindAll(LTEXT("xHIT HAT hit\n"))));
}

//! 正規表現: 大文字と小文字を区別しない指定も引き継ぐ
TEST_F(CompileRegexpTest, IgnoreCase)
{
	ASSERT_THAT(SetKey(LTEXT("hit"), true, false, false), IsTrue());
	ASSERT_THAT(m_cPattern.CompileRegexp(m_cOtherRegexp), IsTrue());
	EXPECT_THAT(FindAllWithOther(LTEXT("HIT Hit\n")), ElementsAre(0, 3, 4, 3));
}

//! 正規表現の置換: 置換後文字列と全域オプションも引き継ぐ
TEST_F(CompileRegexpTest, ReplacePattern)
{
	m_strKey = LTEXT("HIT");
	m_sSearchOption = SSearchOption(true, true, false);
	ASSERT_THAT(m_cPattern.SetPattern(nullptr, m_strKey.c_str(), m_strKey.length(), LTEXT("R"), m_sSearchOption, &m_cRegexp, true), IsTrue());
	ASSERT_THAT(m_cPattern.CompileRegexp(m_cOtherRegexp), IsTrue());

	constexpr sakura::wstring_view target = LTEXT("HIT x HIT");
	EXPECT_THAT(m_cOtherRegexp.Replace(target.data(), static_cast<int>(target.length())), Eq(2));
	EXPECT_THAT(sakura::wstring_view(m_cOtherRegexp.GetString(), m_cOtherRegexp.GetStringLen()), Eq(LTEXT("R x R")));
}

//! 正規表現でなければ、何もせず true を返す(別の CBregexp は初期化しない)
TEST_F(CompileRegexpTest, NotRegexp)
{
	ASSERT_THAT(SetKey(LTEXT("abc"), false, true, false), IsTrue());
	EXPECT_THAT(m_cPattern.CompileRegexp(m_cOtherRegexp), IsTrue());
	EXPECT_THAT(m_cOtherRegexp.IsAvailable(), IsFalse());
}

//! パターンを設定する前は、何もせず true を返す
TEST_F(CompileRegexpTest, BeforeSetPattern)
{
	EXPECT_THAT(m_cPattern.CompileRegexp(m_cOtherRegexp), IsTrue());
	EXPECT_THAT(m_cOtherRegexp.IsAvailable(), IsFalse());
}

//! 次に探し始める位置: 一致の後ろ。長さ 0 の一致なら 1 文字(サロゲートペアは 2)進め、行の末尾でも 1 進める
TEST(CLineMatchFinder, GetNextStart)
{
	constexpr sakura::wstring_view line = LTEXT("a\U0001F600b");
	const auto nLineLen = static_cast<int>(line.length());
	EXPECT_THAT(CLineMatchFinder::GetNextStart(line.data(), nLineLen, { 1, 2 }), Eq(3));
	EXPECT_THAT(CLineMatchFinder::GetNextStart(line.data(), nLineLen, { 0, 0 }), Eq(1));
	EXPECT_THAT(CLineMatchFinder::GetNextStart(line.data(), nLineLen, { 1, 0 }), Eq(3));
	EXPECT_THAT(CLineMatchFinder::GetNextStart(line.data(), nLineLen, { 4, 0 }), Eq(5));
}
