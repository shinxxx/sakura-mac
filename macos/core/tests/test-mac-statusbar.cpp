/*! @file
	@brief ステータスバー（计划第 38 步）的测试

	原版 CCaret::ShowCaretPosInfo 的行・桁、カーソル位置の文字コード、入力改行コードの名前，
	和 ShowCodeBox（文字コード欄のダブルクリック）的各文字コード。
	与 Windows 官方版的状态栏文字的比较在 App 单元测试（StatusBarTests.testWindowsCompare）。
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

//! 测试用的字体：半角 8 点、全角 16 点
constexpr std::int32_t kFontSize = 16;
constexpr std::int32_t kHan = 8;

class MacStatusBarTest : public ::testing::Test {
protected:
	void SetUp() override
	{
		ASSERT_TRUE(Startup());
		SetLayoutFont(u"TestMono", kFontSize);
		ASSERT_TRUE(CDocTypeManager().GetTypeConfig(CTypeConfig(0), m_type));
		m_type.m_nTextWrapMethod = WRAP_SETTING_WIDTH;
		m_type.m_nMaxLineKetas = CKetaXInt(10);
		m_type.m_nTabSpace = CKetaXInt(4);
		m_type.m_nColumnSpace = 0;
		m_type.m_nIndentLayout = 0;
		m_type.m_bWordWrap = false;
		m_type.m_bKinsokuHead = false;
		m_type.m_bKinsokuTail = false;
		m_type.m_bKinsokuRet = false;
		m_type.m_bKinsokuKuto = false;
		m_type.m_bKinsokuHide = false;
		m_type.m_bLineNumIsCRLF = false;
		ASSERT_TRUE(CDocTypeManager().SetTypeConfig(CTypeConfig(0), m_type));
		m_statusbar = GetDllShareData().m_Common.m_sStatusbar;
		m_doc = Document::Create();
		ASSERT_NE(nullptr, m_doc);
	}
	void TearDown() override
	{
		GetDllShareData().m_Common.m_sStatusbar = m_statusbar;
		m_doc.reset();
		Shutdown(false);
	}
	void SetText(const Text& text)
	{
		ASSERT_EQ(Result::Ok, m_doc->Replace(Range{ Position{}, m_doc->EndPosition() }, text));
	}
	//! タイプ別設定「行番号の表示：改行単位」（文书要重新做）
	void SetLineNumIsCRLF(bool on, const Text& text)
	{
		m_type.m_bLineNumIsCRLF = on;
		ASSERT_TRUE(CDocTypeManager().SetTypeConfig(CTypeConfig(0), m_type));
		m_doc = Document::Create();
		ASSERT_NE(nullptr, m_doc);
		SetText(text);
	}
	CaretStatus At(std::int32_t row, std::int32_t column) const
	{
		return m_doc->GetCaretStatus(LayoutPosition{ row, column * kHan });
	}

	STypeConfig m_type;
	CommonSetting_Statusbar m_statusbar{};
	std::unique_ptr<Document> m_doc;
};

} // namespace

TEST_F(MacStatusBarTest, RowColumnAndCharCodeByLayout)
{
	m_doc->SetEncoding(encoding::UTF8, false);
	SetText(u"abcdefghijklmn\r\nxyz");
	// 1 行目の d
	CaretStatus s = At(0, 3);
	EXPECT_EQ(1, s.line);
	EXPECT_EQ(4, s.column);
	EXPECT_EQ(Text(u"U+0064"), s.charCode);	// UTF-8 はコードポイントで表示（DispUtf8Codepoint の初期値）
	// 折り返した 2 行目（レイアウト単位の行番号）の m
	s = At(1, 2);
	EXPECT_EQ(2, s.line);
	EXPECT_EQ(3, s.column);
	EXPECT_EQ(Text(u"U+006D"), s.charCode);
	// 改行の上：改行の名前
	s = At(1, 4);
	EXPECT_EQ(5, s.column);
	EXPECT_EQ(Text(u"CRLF"), s.charCode);
	// 折り返し位置（1 行目の末尾）：文字情報なし
	s = At(0, 10);
	EXPECT_EQ(11, s.column);
	EXPECT_TRUE(s.charCode.empty());
	// EOF の行
	s = At(2, 3);
	EXPECT_EQ(3, s.line);
	EXPECT_EQ(4, s.column);
	EXPECT_TRUE(s.charCode.empty());
}

TEST_F(MacStatusBarTest, EolName)
{
	EXPECT_EQ(Text(u"CRLF"), At(0, 0).eolName);
	m_doc->SetNewLineEol(Eol::LF);
	EXPECT_EQ(Text(u"LF"), At(0, 0).eolName);
	m_doc->SetNewLineEol(Eol::CR);
	EXPECT_EQ(Text(u"CR"), At(0, 0).eolName);
}

TEST_F(MacStatusBarTest, LineNumIsCRLFCountsLogicLine)
{
	SetLineNumIsCRLF(true, u"abcdefghijklmn\r\nあいう");
	// 折り返した 2 行目の m：行は論理行、桁は論理行の先頭からのルーラー単位
	CaretStatus s = At(1, 2);
	EXPECT_EQ(1, s.line);
	EXPECT_EQ(13, s.column);
	// 「あ」の次：ルーラー単位なら全角は 2 桁
	s = At(2, 2);
	EXPECT_EQ(2, s.line);
	EXPECT_EQ(3, s.column);
	// 文字単位（共通設定『ステータスバー』「列数を文字単位で表示」）
	GetDllShareData().m_Common.m_sStatusbar.m_bDispColByChar = TRUE;
	s = At(2, 2);
	EXPECT_EQ(2, s.line);
	EXPECT_EQ(2, s.column);
	s = At(1, 2);
	EXPECT_EQ(13, s.column);
}

TEST_F(MacStatusBarTest, ColumnByCharInLayoutMode)
{
	SetText(u"あいうえおかきく");
	GetDllShareData().m_Common.m_sStatusbar.m_bDispColByChar = TRUE;
	// 折り返した 2 行目の先頭（「か」）：レイアウト行の中の文字位置
	CaretStatus s = At(1, 0);
	EXPECT_EQ(2, s.line);
	EXPECT_EQ(1, s.column);
	s = At(1, 2);
	EXPECT_EQ(2, s.column);
	GetDllShareData().m_Common.m_sStatusbar.m_bDispColByChar = FALSE;
	s = At(1, 2);
	EXPECT_EQ(3, s.column);
}

TEST_F(MacStatusBarTest, CharCodeFollowsDocumentEncoding)
{
	SetText(u"あ\U0001F600");
	m_doc->SetEncoding(encoding::SJIS, false);
	EXPECT_EQ(Text(u"82A0"), At(0, 0).charCode);
	// SJIS で表せない：Unicode で表示（サロゲートペアはコードポイント）
	EXPECT_EQ(Text(u"U+1F600"), At(0, 2).charCode);
	// 「SJISで文字コード値をUnicodeで出力する」
	GetDllShareData().m_Common.m_sStatusbar.m_bDispUniInSjis = TRUE;
	EXPECT_EQ(Text(u"U+3042"), At(0, 0).charCode);
	m_doc->SetEncoding(encoding::EUC, false);
	EXPECT_EQ(Text(u"A4A2"), At(0, 0).charCode);
	m_doc->SetEncoding(encoding::UTF8, false);
	GetDllShareData().m_Common.m_sStatusbar.m_bDispUtf8Codepoint = FALSE;
	EXPECT_EQ(Text(u"E38182"), At(0, 0).charCode);
}

TEST_F(MacStatusBarTest, CharCodesForCodeBox)
{
	SetText(u"あ\r\n");
	const auto codes = m_doc->GetCharCodes(LayoutPosition{ 0, 0 });
	ASSERT_TRUE(codes.has_value());
	EXPECT_EQ(Text(u"あ"), codes->character);
	EXPECT_EQ(Text(u"U+3042"), codes->codePoint);
	EXPECT_EQ(Text(u"82A0"), codes->sjis);
	EXPECT_EQ(Text(u"A4A2"), codes->euc);
	EXPECT_EQ(Text(u"E38182"), codes->utf8);	// 一時的にコードポイント表示をやめる（原版 ShowCodeBox）
	EXPECT_FALSE(codes->jis.empty());
	EXPECT_FALSE(codes->latin1.empty());
	// 改行・EOF の上は文字がない
	EXPECT_FALSE(m_doc->GetCharCodes(LayoutPosition{ 0, 2 * kHan }).has_value());
	EXPECT_FALSE(m_doc->GetCharCodes(LayoutPosition{ 1, 0 }).has_value());
}
