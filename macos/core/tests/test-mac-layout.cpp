/*! @file
	@brief 排版（计划第 27 步）的测试

	排版是原版 doc/layout 的代码原样编译的，换行的位置由同一段代码按同样的规则决定。
	与 Windows 版可能不同的只有字符宽度：Windows 用 GDI 测，Mac 用 Core Text 测。
	等宽字体时两边都按“半角一格、比半角宽的字符两格”（CCharWidthCache::QueryPixelWidth），
	所以只要半角宽度相同，换行位置就相同。

	这里用测试用的字符宽度（半角 8 点、全角 16 点，sakura_platform_hooks 的默认测量函数），
	按原版的规则写出期待的换行位置：
	- 折り返し桁数、全角字符、TAB 的展开
	- 改行文字をぶら下げる、英文ワードラップ、行頭禁則、行末禁則、句読点ぶら下げ
	- 折り返さない、右端で折り返す（窗口宽度 → 桁数）
	- 逻辑位置和排版位置的换算
	- 编辑后逐段更新的排版与从头重新排版的结果相同
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

#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <string>
#include <vector>

using namespace sakura::core;

namespace {

//! 测试用的字体：默认的测量函数按字体大小的一半算半角宽度（16 → 半角 8 点、全角 16 点）
constexpr std::int32_t kFontSize = 16;
constexpr std::int32_t kHan = 8;

class MacLayoutTest : public ::testing::Test {
protected:
	void SetUp() override
	{
		ASSERT_TRUE(Startup());
		SetLayoutFont(u"TestMono", kFontSize);
		// 「基本」的类型别设置：先关掉所有禁则，每个测试按需要打开
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
		ApplyType();
	}
	void TearDown() override
	{
		m_doc.reset();
		SetTextMeasureFunction(nullptr);
		Shutdown(false);
	}

	//! 改过的类型别设置写回共通设置，重新建立文档（与原版改了タイプ別設定后重新打开相同）
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

	//! 排版行的文字（不含换行符）。带换行符的行在后面加 "↵"
	std::vector<Text> Rows() const
	{
		std::vector<Text> rows;
		for (std::int32_t i = 0; i < m_doc->LayoutLineCount(); i++) {
			const LayoutLine l = m_doc->GetLayoutLine(i);
			Text row = m_doc->GetLine(l.start.line).substr(l.start.column, l.length);
			if (l.eol != Eol::None) row += u"↵";
			rows.push_back(row);
		}
		return rows;
	}

	STypeConfig m_type{};
	std::unique_ptr<Document> m_doc;
};

using RowList = std::vector<Text>;

} // namespace

// ---------------------------------------------------------------------------
// 折り返し桁数、字符宽度
// ---------------------------------------------------------------------------

TEST_F(MacLayoutTest, CharWidthFollowsFont)
{
	// 半角宽度与 CTextMetrics::Update 相同：52 个英文字母的宽度 / 26 再四舍五入到一半
	EXPECT_EQ(kHan, m_doc->CharWidth());
	EXPECT_EQ(10 * kHan, m_doc->LayoutWidth());
	const ViewSettings v = m_doc->GetViewSettings();
	EXPECT_EQ(WrapMethod::SettingWidth, v.wrapMethod);
	EXPECT_EQ(10, v.wrapColumns);
	EXPECT_EQ(10, v.typeWrapColumns);
	EXPECT_EQ(4, v.tabColumns);
}

//! 界面层登记的测量函数收到的字体
std::u16string g_measuredFace;
std::int32_t g_measuredSize = 0;

TEST_F(MacLayoutTest, RegisteredMeasureFunctionIsUsed)
{
	// 每个 UTF-16 单位 10 点、宽字符 15 点的“字体”：等宽字体按原版的规则，比半角宽的字符算 2 倍（20 点）
	SetTextMeasureFunction([](const char16_t* face, std::int32_t size, const char16_t* text, std::size_t length) -> std::int32_t {
		g_measuredFace = face;
		g_measuredSize = size;
		std::int32_t width = 0;
		for (std::size_t i = 0; i < length; i++) width += text[i] < 0x1100 ? 10 : 15;
		return width;
	});
	SetLayoutFont(u"Menlo", 13);
	m_doc->Relayout();
	EXPECT_EQ(u"Menlo", g_measuredFace);
	EXPECT_EQ(13, g_measuredSize);
	EXPECT_EQ(10, m_doc->CharWidth());
	SetText(u"aあb");
	EXPECT_EQ((std::vector<std::int32_t>{ 0, 10, 30, 40 }), m_doc->GetLayoutCharPositions(0));
}

TEST_F(MacLayoutTest, EmptyDocumentHasNoLayoutLines)
{
	EXPECT_EQ(0, m_doc->LayoutLineCount());
	EXPECT_EQ((LayoutPosition{ 0, 0 }), m_doc->LogicToLayout(Position{ 0, 0 }));
}

TEST_F(MacLayoutTest, WrapsAtSettingWidth)
{
	SetText(u"0123456789ABCDEFGHIJKLMN\r\nshort\r\n");
	EXPECT_EQ((RowList{ u"0123456789", u"ABCDEFGHIJ", u"KLMN↵", u"short↵" }), Rows());
	// 折り返した行的开始位置
	EXPECT_EQ((Position{ 0, 10 }), m_doc->GetLayoutLine(1).start);
	EXPECT_EQ(Eol::None, m_doc->GetLayoutLine(1).eol);
	EXPECT_EQ(Eol::CRLF, m_doc->GetLayoutLine(2).eol);
}

TEST_F(MacLayoutTest, FullWidthCharactersTakeTwoColumns)
{
	// 全角 5 个正好 10 桁；前面有半角时第 5 个全角放不下，移到下一行
	SetText(u"あいうえおかきく\naあいうえおか");
	EXPECT_EQ((RowList{ u"あいうえお", u"かきく↵", u"aあいうえ", u"おか" }), Rows());
	const auto x = m_doc->GetLayoutCharPositions(2);
	EXPECT_EQ((std::vector<std::int32_t>{ 0, 8, 24, 40, 56, 72 }), x);
}

TEST_F(MacLayoutTest, EolAtFullLineGoesToNextLineUnlessHanging)
{
	// 正好 10 桁的行：换行符也占宽度（1 点），所以只有换行符到了下一行（与原版相同）
	SetText(u"0123456789\nX");
	EXPECT_EQ((RowList{ u"0123456789", u"↵", u"X" }), Rows());

	// 「改行文字をぶら下げる」：换行符留在同一行
	m_type.m_bKinsokuRet = true;
	ApplyType();
	SetText(u"0123456789\nX");
	EXPECT_EQ((RowList{ u"0123456789↵", u"X" }), Rows());
}

TEST_F(MacLayoutTest, TabExpandsToNextTabStop)
{
	// TAB 幅 4：到下一个 4 桁的边界
	SetText(u"\tA\nab\tc\nabcd\te");
	EXPECT_EQ((std::vector<std::int32_t>{ 0, 4 * kHan, 5 * kHan }), m_doc->GetLayoutCharPositions(0));
	EXPECT_EQ((std::vector<std::int32_t>{ 0, kHan, 2 * kHan, 4 * kHan, 5 * kHan }), m_doc->GetLayoutCharPositions(1));
	EXPECT_EQ((std::vector<std::int32_t>{ 0, kHan, 2 * kHan, 3 * kHan, 4 * kHan, 8 * kHan, 9 * kHan }), m_doc->GetLayoutCharPositions(2));
}

TEST_F(MacLayoutTest, TabWrapsWhenItDoesNotFit)
{
	// 第 8 桁的 TAB 要到第 12 桁，10 桁里放不下，到下一行的开头（宽 4 桁）
	SetText(u"01234567\tX");
	EXPECT_EQ((RowList{ u"01234567", u"\tX" }), Rows());
	EXPECT_EQ((std::vector<std::int32_t>{ 0, 4 * kHan, 5 * kHan }), m_doc->GetLayoutCharPositions(1));
}

TEST_F(MacLayoutTest, SurrogatePairIsNotSplit)
{
	// U+20B9F（𠮟）是一个全角字
	SetText(u"012345678\U00020B9F");
	EXPECT_EQ((RowList{ u"012345678", u"\U00020B9F" }), Rows());
	EXPECT_EQ((std::vector<std::int32_t>{ 0, 0, 2 * kHan }), m_doc->GetLayoutCharPositions(1));
}

// ---------------------------------------------------------------------------
// 禁則
// ---------------------------------------------------------------------------

TEST_F(MacLayoutTest, WordWrapKeepsEnglishWords)
{
	m_type.m_bWordWrap = true;
	ApplyType();
	SetText(u"hello world foobar");
	EXPECT_EQ((RowList{ u"hello ", u"world ", u"foobar" }), Rows());

	// 不做英文ワードラップ时在第 10 桁切开
	m_type.m_bWordWrap = false;
	ApplyType();
	SetText(u"hello world foobar");
	EXPECT_EQ((RowList{ u"hello worl", u"d foobar" }), Rows());
}

TEST_F(MacLayoutTest, KinsokuHeadMovesPreviousCharacter)
{
	// 行頭禁則：「。」不能在行首，和前一个字一起到下一行
	m_type.m_bKinsokuHead = true;
	m_type.m_szKinsokuHead = u"。、";
	ApplyType();
	SetText(u"あいうえお。かき");
	EXPECT_EQ((RowList{ u"あいうえ", u"お。かき" }), Rows());
}

TEST_F(MacLayoutTest, KinsokuTailMovesOpeningBracket)
{
	// 行末禁則：「「」不能在行末，到下一行
	m_type.m_bKinsokuTail = true;
	m_type.m_szKinsokuTail = u"「";
	ApplyType();
	SetText(u"あいうえ「お」");
	EXPECT_EQ((RowList{ u"あいうえ", u"「お」" }), Rows());
}

TEST_F(MacLayoutTest, KutoBurasageHangsPunctuation)
{
	// 句読点ぶら下げ：「。」超出折り返し桁，留在同一行
	m_type.m_bKinsokuKuto = true;
	m_type.m_szKinsokuKuto = u"、。";
	ApplyType();
	SetText(u"あいうえお。かき");
	EXPECT_EQ((RowList{ u"あいうえお。", u"かき" }), Rows());
}

// ---------------------------------------------------------------------------
// 折り返し方法
// ---------------------------------------------------------------------------

TEST_F(MacLayoutTest, NoWrapKeepsLogicalLines)
{
	SetText(u"0123456789ABCDEFGHIJ\nあい");
	ASSERT_TRUE(m_doc->SetWrap(WrapMethod::None, 0));
	EXPECT_EQ((RowList{ u"0123456789ABCDEFGHIJ↵", u"あい" }), Rows());
	EXPECT_EQ(WrapMethod::None, m_doc->GetViewSettings().wrapMethod);
	// 宽度是最长的行（包括换行符的部分，CLayoutMgr::CalculateTextWidth）
	EXPECT_LE(20 * kHan, m_doc->LayoutWidth());
	// 设置相同时什么也不做
	EXPECT_FALSE(m_doc->SetWrap(WrapMethod::None, 0));

	// 回到「指定桁で折り返す」
	ASSERT_TRUE(m_doc->SetWrap(WrapMethod::SettingWidth, m_doc->GetViewSettings().typeWrapColumns));
	EXPECT_EQ((RowList{ u"0123456789", u"ABCDEFGHIJ", u"↵", u"あい" }), Rows());
}

TEST_F(MacLayoutTest, WindowWidthWrap)
{
	// 右端で折り返す：宽度减去折り返し記号 1 桁后的桁数（CEditView::ViewColNumToWrapColNum）
	EXPECT_EQ(15, m_doc->WrapColumnsForWidth(16 * kHan));
	EXPECT_EQ(15, m_doc->WrapColumnsForWidth(16 * kHan + kHan - 1));
	EXPECT_EQ(10, m_doc->WrapColumnsForWidth(3 * kHan));	// 最小 10 桁
	SetText(u"0123456789ABCDEFGHIJ");
	ASSERT_TRUE(m_doc->SetWrap(WrapMethod::WindowWidth, m_doc->WrapColumnsForWidth(16 * kHan)));
	EXPECT_EQ((RowList{ u"0123456789ABCDE", u"FGHIJ" }), Rows());
	EXPECT_EQ(15 * kHan, m_doc->LayoutWidth());

	// 有ぶら下げ时也减去它的宽度
	m_type.m_bKinsokuRet = true;
	m_type.m_bKinsokuKuto = true;
	ApplyType();
	EXPECT_EQ(12, m_doc->WrapColumnsForWidth(16 * kHan));
}

// ---------------------------------------------------------------------------
// 位置的换算
// ---------------------------------------------------------------------------

TEST_F(MacLayoutTest, LogicAndLayoutPositions)
{
	SetText(u"0123456789ABCDE\nあいうえおか");
	EXPECT_EQ((LayoutPosition{ 0, 3 * kHan }), m_doc->LogicToLayout(Position{ 0, 3 }));
	EXPECT_EQ((LayoutPosition{ 1, 5 * kHan }), m_doc->LogicToLayout(Position{ 0, 15 }));
	EXPECT_EQ((LayoutPosition{ 3, 2 * kHan }), m_doc->LogicToLayout(Position{ 1, 6 }));
	EXPECT_EQ((Position{ 0, 12 }), m_doc->LayoutToLogic(LayoutPosition{ 1, 2 * kHan }));
	EXPECT_EQ((Position{ 1, 5 }), m_doc->LayoutToLogic(LayoutPosition{ 3, 0 }));
	// 往復
	for (std::int32_t line = 0; line < m_doc->LineCount(); line++) {
		const auto length = static_cast<std::int32_t>(m_doc->GetLine(line).size());
		for (std::int32_t column = 0; column <= length; column++) {
			const Position p{ line, column };
			EXPECT_EQ(p, m_doc->LayoutToLogic(m_doc->LogicToLayout(p))) << line << "," << column;
		}
	}
}

// ---------------------------------------------------------------------------
// 编辑
// ---------------------------------------------------------------------------

TEST_F(MacLayoutTest, IncrementalLayoutMatchesFullLayout)
{
	m_type.m_bWordWrap = true;
	m_type.m_bKinsokuHead = true;
	m_type.m_szKinsokuHead = u"。、";
	ApplyType();
	SetText(u"hello world\nあいうえお。かき\n\tTAB\n");
	struct Edit { Range range; Text text; };
	const std::vector<Edit> edits = {
		{ { { 0, 5 }, { 0, 5 } }, u" big" },					// 在行的中间插入
		{ { { 1, 2 }, { 1, 2 } }, u"XYZ\nabc" },				// 插入带换行的文字
		{ { { 0, 0 }, { 1, 1 } }, u"" },						// 跨行删除
		{ { { 0, 0 }, { 0, 0 } }, u"0123456789012345678901234" },	// 长行
		{ { { 2, 0 }, { 2, 0 } }, u"あああああああああああ" },
	};
	for (const auto& e : edits) {
		ASSERT_EQ(Result::Ok, m_doc->Replace(e.range, e.text));
		const RowList incremental = Rows();
		m_doc->Relayout();
		EXPECT_EQ(Rows(), incremental);
	}
	// 撤销、重做也一样
	while (m_doc->CanUndo()) {
		ASSERT_EQ(Result::Ok, m_doc->Undo());
		const RowList incremental = Rows();
		m_doc->Relayout();
		EXPECT_EQ(Rows(), incremental);
	}
	EXPECT_EQ((RowList{}), Rows());
	while (m_doc->CanRedo()) {
		ASSERT_EQ(Result::Ok, m_doc->Redo());
		const RowList incremental = Rows();
		m_doc->Relayout();
		EXPECT_EQ(Rows(), incremental);
	}
}

TEST_F(MacLayoutTest, OpenRelayoutsWithTypeSetting)
{
	const auto path = std::filesystem::path(std::getenv("HOME")) / "layout.zzz";	// 不属于任何类型的扩展名（「基本」）
	{
		std::ofstream out(path, std::ios::binary);
		out << "0123456789ABC\r\n";
	}
	// 临时改成折り返さない，重新打开后回到类型别设置（CLoadAgent::OnAfterLoad）
	ASSERT_TRUE(m_doc->SetWrap(WrapMethod::None, 0));
	ASSERT_EQ(Result::Ok, m_doc->Open(path.u16string()));
	EXPECT_EQ(WrapMethod::SettingWidth, m_doc->GetViewSettings().wrapMethod);
	EXPECT_EQ((RowList{ u"0123456789", u"ABC↵" }), Rows());
}
