/*! @file
	@brief 编辑画面的颜色（计划第 28 步）的测试

	- 类型别设置的颜色与原版的默认值相同（CDocTypeSetting.cpp 的 ColorInfo_DEFAULT）
	- 「変更行」：编辑过的行算修改，撤销回到保存时的内容、保存之后不算
*/
/*
	Copyright (C) 2026, Sakura Editor Organization

	SPDX-License-Identifier: Zlib
*/
#include "pch.h"
#include "sakura_core/SakuraCore.h"

#include <cstdlib>
#include <filesystem>
#include <fstream>

using namespace sakura::core;

namespace {

class MacViewTest : public ::testing::Test {
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

	std::unique_ptr<Document> m_doc;
};

} // namespace

//! 默认的颜色：与原版相同（背景是米色 RGB(255,251,240)）
TEST_F(MacViewTest, DefaultColors)
{
	const ColorSetting text = m_doc->GetColor(ColorIndex::Text);
	EXPECT_TRUE(text.display);
	EXPECT_EQ(0x000000u, text.text);
	EXPECT_EQ(0xFFFBF0u, text.back);

	const ColorSetting number = m_doc->GetColor(ColorIndex::LineNumber);
	EXPECT_TRUE(number.display);
	EXPECT_EQ(0x0000FFu, number.text);
	EXPECT_EQ(0xEFEFEFu, number.back);

	const ColorSetting modified = m_doc->GetColor(ColorIndex::LineNumberModified);
	EXPECT_TRUE(modified.display);
	EXPECT_TRUE(modified.bold);

	// 选择范围：文字色和背景色相同（原版按 30% 混合显示）
	const ColorSetting select = m_doc->GetColor(ColorIndex::Select);
	EXPECT_TRUE(select.display);
	EXPECT_EQ(0x316AC5u, select.text);
	EXPECT_EQ(0x316AC5u, select.back);

	EXPECT_EQ(0x000000u, m_doc->GetColor(ColorIndex::Caret).text);
	EXPECT_EQ(0xFF0000u, m_doc->GetColor(ColorIndex::CaretIme).text);
	EXPECT_TRUE(m_doc->GetColor(ColorIndex::CaretLineUnderline).display);
	EXPECT_EQ(0x0000FFu, m_doc->GetColor(ColorIndex::CaretLineUnderline).text);
	EXPECT_FALSE(m_doc->GetColor(ColorIndex::CaretLineBackground).display);
	EXPECT_FALSE(m_doc->GetColor(ColorIndex::EvenLineBackground).display);
	EXPECT_EQ(0x808080u, m_doc->GetColor(ColorIndex::Tab).text);
	EXPECT_EQ(0xC0C0C0u, m_doc->GetColor(ColorIndex::FullWidthSpace).text);
	EXPECT_EQ(0x0080FFu, m_doc->GetColor(ColorIndex::Eol).text);
	EXPECT_EQ(0xFF00FFu, m_doc->GetColor(ColorIndex::WrapMark).text);
	EXPECT_EQ(0x00FFFFu, m_doc->GetColor(ColorIndex::Eof).text);
	EXPECT_EQ(0x000000u, m_doc->GetColor(ColorIndex::Eof).back);

	// 范围外
	EXPECT_FALSE(m_doc->GetColor(static_cast<ColorIndex>(255)).display);
}

//! 「変更行」：编辑过的行。撤销回到原来的内容后不算
TEST_F(MacViewTest, ModifiedLines)
{
	EXPECT_FALSE(m_doc->IsLineModified(0));
	ASSERT_EQ(Result::Ok, m_doc->Replace(Range{}, u"abc\ndef\nghi"));
	EXPECT_TRUE(m_doc->IsLineModified(0));
	EXPECT_TRUE(m_doc->IsLineModified(2));
	EXPECT_FALSE(m_doc->IsLineModified(3));		// 范围外
	EXPECT_FALSE(m_doc->IsLineModified(-1));
	ASSERT_EQ(Result::Ok, m_doc->Undo());
	EXPECT_FALSE(m_doc->IsLineModified(0));
}

//! 打开的文件：没有修改的行不算，改了的那一行算；保存后都不算
TEST_F(MacViewTest, ModifiedLinesAfterOpenAndSave)
{
	const auto path = std::filesystem::path(std::getenv("HOME")) / "view-modified.txt";
	{
		std::ofstream out(path, std::ios::binary);
		out << "one\ntwo\nthree\n";
	}
	ASSERT_EQ(Result::Ok, m_doc->Open(path.u16string()));
	EXPECT_FALSE(m_doc->IsLineModified(0));
	EXPECT_FALSE(m_doc->IsLineModified(1));

	ASSERT_EQ(Result::Ok, m_doc->Replace(Range{ Position{ 1, 0 }, Position{ 1, 0 } }, u"2:"));
	EXPECT_FALSE(m_doc->IsLineModified(0));
	EXPECT_TRUE(m_doc->IsLineModified(1));
	EXPECT_FALSE(m_doc->IsLineModified(2));

	ASSERT_EQ(Result::Ok, m_doc->Save());
	EXPECT_FALSE(m_doc->IsLineModified(1));
	std::filesystem::remove(path);
}
