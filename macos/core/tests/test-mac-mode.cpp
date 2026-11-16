/*! @file
	@brief 文件、模式、设定的命令（计划第 34 步）的核心部分的测试

	- 文字コードセット指定（Command_CHG_CHARSET → CDocFile::SetCodeSetChg / IsChgCodeSet）
	- 挿入／上書きモード切り替え（Command_CHGMOD_INS）和上書き的输入（DelCharForOverwrite）
	- 入力改行コード指定、開き直す 的打勾（IsFuncChecked）
	- 現在のウィンドウ幅で折り返し（Command_WRAPWINDOWWIDTH → CEditView::GetWrapMode）
	- フォントサイズ拡大／縮小（Command_SETFONTSIZE 的倍率表）

	期待值按原版的算法算出（注释里写了依据）。
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

#include <gtest/gtest.h>

#include <cstdlib>
#include <filesystem>
#include <fstream>

using namespace sakura::core;

namespace {

constexpr std::int32_t kFontSize = 16;
constexpr std::int32_t kHan = 8;	//!< 半角一字的宽度（TestMono 16）

Position P(int line, int column) { return Position{ line, column }; }

class MacModeTest : public ::testing::Test {
protected:
	void SetUp() override
	{
		ASSERT_TRUE(Startup());
		SetLayoutFont(u"TestMono", kFontSize);
		m_saved = GetDllShareData().m_Common;
		ASSERT_TRUE(CDocTypeManager().GetTypeConfig(CTypeConfig(0), m_type));
		m_type.m_nTextWrapMethod = WRAP_SETTING_WIDTH;
		m_type.m_nMaxLineKetas = CKetaXInt(80);
		m_type.m_nColumnSpace = 0;
		m_type.m_bKinsokuHide = false;
		m_type.m_bKinsokuRet = false;	// ぶら下げ余白は折り返し記号の 1 桁だけ
		m_type.m_bKinsokuKuto = false;
		ApplyType();
	}
	void TearDown() override
	{
		m_doc.reset();
		GetDllShareData().m_Common = m_saved;
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
	//! 打开内容是 bytes 的文件
	void OpenBytes(const char* name, const std::string& bytes, Encoding encoding = encoding::AutoDetect)
	{
		const auto path = std::filesystem::path(std::getenv("HOME")) / name;
		{
			std::ofstream out(path, std::ios::binary);
			out << bytes;
		}
		OpenOptions options;
		options.encoding = encoding;
		ASSERT_EQ(Result::Ok, m_doc->Open(path.u16string(), options));
	}
	//! 上書き输入，返回之后的光标
	Position Overwrite(const Position& at, const Text& text)
	{
		Position caret{};
		EXPECT_EQ(Result::Ok, m_doc->OverwriteText(at, text, &caret));
		return caret;
	}

	CommonSetting m_saved{};
	STypeConfig m_type{};
	std::unique_ptr<Document> m_doc;
};

// ----- 閉じて(無題) -----

//! 内容、撤销、文件名、编码都回到新文档的状态
TEST_F(MacModeTest, CloseToUntitled)
{
	OpenBytes("mode-close.txt", "abc\ndef\n", encoding::SJIS);
	ASSERT_EQ(Result::Ok, m_doc->Insert(P(0, 0), u"x"));
	ASSERT_TRUE(m_doc->IsModified());
	const auto fresh = Document::Create();
	m_doc->CloseToUntitled();
	EXPECT_EQ(u"", m_doc->GetText());
	EXPECT_EQ(0, m_doc->LineCount());
	EXPECT_TRUE(m_doc->GetFileInfo().path.empty());
	EXPECT_EQ(fresh->GetFileInfo().encoding, m_doc->GetFileInfo().encoding);
	EXPECT_FALSE(m_doc->IsModified());
	EXPECT_FALSE(m_doc->CanUndo());
	EXPECT_FALSE(m_doc->IsEncodingChanged());
	// 之后可以照常编辑
	ASSERT_EQ(Result::Ok, m_doc->Insert(P(0, 0), u"new"));
	EXPECT_EQ(u"new", m_doc->GetText());
}

// ----- 文字コードセット指定 -----

//! 打开的文件改了编码或 BOM 才算「文字コードセットが変更されています」。改回去就不算
TEST_F(MacModeTest, SetEncodingMarksChange)
{
	OpenBytes("mode-utf8.txt", "abc\r\n", encoding::UTF8);
	EXPECT_FALSE(m_doc->IsEncodingChanged());
	m_doc->SetEncoding(encoding::SJIS, true);			// SJIS 不能加 BOM（UseBom() 是 false）
	EXPECT_EQ(encoding::SJIS, m_doc->GetFileInfo().encoding);
	EXPECT_FALSE(m_doc->GetFileInfo().bom);
	EXPECT_TRUE(m_doc->IsEncodingChanged());
	EXPECT_FALSE(m_doc->IsModified()) << "内容不变";
	m_doc->SetEncoding(encoding::UTF8, true);			// BOM 不同也算改过
	EXPECT_TRUE(m_doc->GetFileInfo().bom);
	EXPECT_TRUE(m_doc->IsEncodingChanged());
	m_doc->SetEncoding(encoding::UTF8, false);
	EXPECT_FALSE(m_doc->IsEncodingChanged());
}

//! 新文件（IsFileTimeZero）不算改过；保存以后保存时的编码成为基准
TEST_F(MacModeTest, SetEncodingOnNewFileAndAfterSave)
{
	m_doc->SetEncoding(encoding::EUC, false);
	EXPECT_EQ(encoding::EUC, m_doc->GetFileInfo().encoding);
	EXPECT_FALSE(m_doc->IsEncodingChanged());
	const auto path = std::filesystem::path(std::getenv("HOME")) / "mode-new.txt";
	ASSERT_EQ(Result::Ok, m_doc->SaveAs(path.u16string()));
	EXPECT_EQ(encoding::EUC, m_doc->GetFileInfo().encoding);
	EXPECT_FALSE(m_doc->IsEncodingChanged());
	m_doc->SetEncoding(encoding::UTF8, false);
	EXPECT_TRUE(m_doc->IsEncodingChanged());
	ASSERT_EQ(Result::Ok, m_doc->Save());
	EXPECT_FALSE(m_doc->IsEncodingChanged());
}

// ----- 挿入／上書きモード -----

//! 新文档按共通設定「挿入モード」；Command_CHGMOD_INS 切换，菜单打勾
TEST_F(MacModeTest, InsertModeToggle)
{
	EXPECT_TRUE(m_doc->IsInsertMode());
	EXPECT_TRUE(m_doc->IsCommandChecked(command::ChangeInsMode));
	EXPECT_TRUE(Document::IsCommandSupported(command::ChangeInsMode));
	EXPECT_TRUE(m_doc->IsCommandEnabled(command::ChangeInsMode));
	EXPECT_EQ(Result::Ok, m_doc->ExecuteCommand(command::ChangeInsMode));
	EXPECT_FALSE(m_doc->IsInsertMode());
	EXPECT_FALSE(m_doc->IsCommandChecked(command::ChangeInsMode));

	GetDllShareData().m_Common.m_sGeneral.m_bIsINSMode = false;
	ApplyType();
	EXPECT_FALSE(m_doc->IsInsertMode()) << "共通設定で上書きモード";
}

//! 上書き：光标处的字换成输入的字；行末默认不删换行（「改行は上書きしない」默认 ON）
TEST_F(MacModeTest, OverwriteReplacesCharacters)
{
	SetText(u"abc\ndef");
	EXPECT_EQ(P(0, 2), Overwrite(P(0, 0), u"XY"));
	EXPECT_EQ(u"XYc\ndef", m_doc->GetText());
	// 行末：改行は上書きしない → 插入
	ASSERT_TRUE(GetDllShareData().m_Common.m_sEdit.m_bNotOverWriteCRLF);
	EXPECT_EQ(P(0, 5), Overwrite(P(0, 3), u"!!"));
	EXPECT_EQ(u"XYc!!\ndef", m_doc->GetText());
	// 文件的最后（没有换行）：插入
	EXPECT_EQ(P(1, 4), Overwrite(P(1, 3), u"g"));
	EXPECT_EQ(u"XYc!!\ndefg", m_doc->GetText());
	// 撤销：一次输入是一步
	ASSERT_EQ(Result::Ok, m_doc->Undo());
	EXPECT_EQ(u"XYc!!\ndef", m_doc->GetText());
}

//! 「改行は上書きしない」关掉时，行末的输入删掉换行（Command_DELETE），下一行接上来
TEST_F(MacModeTest, OverwriteJoinsLinesWhenAllowed)
{
	GetDllShareData().m_Common.m_sEdit.m_bNotOverWriteCRLF = FALSE;
	SetText(u"ab\r\ncd");
	EXPECT_EQ(P(0, 3), Overwrite(P(0, 2), u"X"));
	EXPECT_EQ(u"abXcd", m_doc->GetText());
}

//! 换行的输入、补充平面的字、TAB 的上書き
TEST_F(MacModeTest, OverwriteSpecialCharacters)
{
	SetText(u"a\U0001F600b\tc");
	EXPECT_EQ(P(0, 2), Overwrite(P(0, 1), u"x"));		// 补充平面的字（2 个 UTF-16）整个换掉
	EXPECT_EQ(u"axb\tc", m_doc->GetText());
	EXPECT_EQ(P(0, 4), Overwrite(P(0, 3), u"y"));		// TAB 也是一个字
	EXPECT_EQ(u"axbyc", m_doc->GetText());
	EXPECT_EQ(P(1, 0), Overwrite(P(0, 1), u"\n"));		// 换行不删字（原版 Command_WCHAR 的改行处理）
	EXPECT_EQ(u"a\nxbyc", m_doc->GetText());
}

//! 「文字幅に合わせてスペースを詰める」：全角换半角补一个空白，半角换全角吃掉两个半角
TEST_F(MacModeTest, OverwriteFixMode)
{
	GetDllShareData().m_Common.m_sEdit.m_bOverWriteFixMode = true;
	SetText(u"あいう");
	// 全角（2 桁）→ 半角（1 桁）：nKetaDiff = 1，后面补一个空白
	EXPECT_EQ(P(0, 1), Overwrite(P(0, 0), u"a"));
	EXPECT_EQ(u"a いう", m_doc->GetText());
	SetText(u"abcd");
	// 半角 → 全角：nKetaDiff = -1，下一个半角也删掉（nDelLen = 2），nKetaAfterIns = 1+1-2 = 0
	EXPECT_EQ(P(0, 1), Overwrite(P(0, 0), u"あ"));
	EXPECT_EQ(u"あcd", m_doc->GetText());
	// 半角 → 全角，下一个是全角：nKetaAfterIns = 1+2-2 = 1，补一个空白
	SetText(u"aいb");
	EXPECT_EQ(P(0, 1), Overwrite(P(0, 0), u"う"));
	EXPECT_EQ(u"う b", m_doc->GetText());
}

// ----- 菜单的打勾 -----

//! 入力改行コード指定：现在的换行符打勾（NEL、PS、LS 原版也不打勾）
TEST_F(MacModeTest, NewLineEolChecked)
{
	ASSERT_EQ(Result::Ok, m_doc->ExecuteCommand(command::NewLineLF));
	EXPECT_TRUE(m_doc->IsCommandChecked(command::NewLineLF));
	EXPECT_FALSE(m_doc->IsCommandChecked(command::NewLineCRLF));
	EXPECT_FALSE(m_doc->IsCommandChecked(command::NewLineCR));
	ASSERT_EQ(Result::Ok, m_doc->ExecuteCommand(command::NewLineCRLF));
	EXPECT_TRUE(m_doc->IsCommandChecked(command::NewLineCRLF));
	EXPECT_FALSE(m_doc->IsCommandChecked(command::NewLineNEL));
}

//! ○○で開き直す：现在的编码打勾
TEST_F(MacModeTest, ReopenEncodingChecked)
{
	OpenBytes("mode-sjis.txt", "abc\r\n", encoding::SJIS);
	EXPECT_TRUE(m_doc->IsCommandChecked(30111));	// F_FILE_REOPEN_SJIS
	EXPECT_FALSE(m_doc->IsCommandChecked(30115));	// F_FILE_REOPEN_UTF8
	m_doc->SetEncoding(encoding::UTF8, false);
	EXPECT_TRUE(m_doc->IsCommandChecked(30115));
	EXPECT_FALSE(m_doc->IsCommandChecked(30119)) << "現在と同じ文字コードで開き直す 不打勾";
}

// ----- 現在のウィンドウ幅で折り返し -----

//! 设定值 → 窗口宽度 → 最大值 → 设定值 → …（GetWrapMode 的 c)、1)、a)）
TEST_F(MacModeTest, WrapWindowWidthCycle)
{
	const std::int32_t width = kHan * 41;	// 减去折り返し記号 1 桁：40 桁
	ASSERT_EQ(40, m_doc->WrapColumnsForWidth(width));
	ASSERT_EQ(80, m_doc->GetViewSettings().wrapColumns);
	auto step = [&](std::int32_t expected) {
		const auto columns = m_doc->WrapWindowWidthColumns(width);
		ASSERT_TRUE(columns.has_value());
		EXPECT_EQ(expected, *columns);
		m_doc->SetWrap(WrapMethod::SettingWidth, *columns);
		EXPECT_EQ(expected, m_doc->GetViewSettings().wrapColumns);
	};
	step(40);		// c) ウィンドウ幅
	step(10240);	// 1) ウィンドウ幅と合っている → 最大値
	step(80);		// a) 最大値 → 設定値
	step(40);
}

//! 窗口极窄（放不下 MINLINEKETAS 桁）：最大值和设定值之间切换；设定值也是最大值时不能改变
TEST_F(MacModeTest, WrapWindowWidthNarrow)
{
	const std::int32_t width = kHan * 6;	// 5 桁
	ASSERT_EQ(10, m_doc->WrapColumnsForWidth(width));
	auto columns = m_doc->WrapWindowWidthColumns(width);
	ASSERT_TRUE(columns.has_value());
	EXPECT_EQ(10240, *columns);				// 4) 折り返し幅!=最大値 : 最大値
	m_doc->SetWrap(WrapMethod::SettingWidth, *columns);
	columns = m_doc->WrapWindowWidthColumns(width);
	ASSERT_TRUE(columns.has_value());
	EXPECT_EQ(80, *columns);				// 7) 最大値!=設定値 : 設定値

	m_type.m_nMaxLineKetas = CKetaXInt(10240);
	ApplyType();
	EXPECT_FALSE(m_doc->WrapWindowWidthColumns(width).has_value());	// 6) 変更不能
	// 刚好 10 桁的宽度不算极窄
	EXPECT_EQ(10, m_doc->WrapWindowWidthColumns(kHan * 11).value_or(-1));
}

// ----- フォントサイズ拡大／縮小 -----

//! 原版的倍率表：12pt → 13.2→13pt（1 点单位）→ 15 → …；缩小时到下一个不同的大小
TEST_F(MacModeTest, ZoomFontSize)
{
	auto up = ZoomFontSize(12, 1.0, 1, 1.0);
	ASSERT_TRUE(up.has_value());
	EXPECT_DOUBLE_EQ(13.0, up->pointSize);		// 12 × 1.1 = 13.2 → 13
	EXPECT_DOUBLE_EQ(1.1, up->zoom);
	up = ZoomFontSize(12, up->zoom, 1, 1.0);
	ASSERT_TRUE(up.has_value());
	EXPECT_DOUBLE_EQ(15.0, up->pointSize);		// 12 × 1.25 = 15
	auto down = ZoomFontSize(12, 1.0, -1, 1.0);
	ASSERT_TRUE(down.has_value());
	EXPECT_DOUBLE_EQ(10.0, down->pointSize);	// 12 × 0.9 = 10.8 → 10
	EXPECT_DOUBLE_EQ(0.9, down->zoom);
	// 原版的 0.5 点单位
	up = ZoomFontSize(12, 1.0, 1);
	ASSERT_TRUE(up.has_value());
	EXPECT_DOUBLE_EQ(13.0, up->pointSize);		// 13.2 → 13.0
	// 上限 72 点：不能再大
	EXPECT_FALSE(ZoomFontSize(72, 1.0, 1, 1.0).has_value());
	EXPECT_FALSE(ZoomFontSize(12, 1.0, 0, 1.0).has_value());
}

} // namespace
