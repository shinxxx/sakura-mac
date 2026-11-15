/*! @file
	@brief 打开与保存（计划第 30 步）的测试

	- 文件对话框的编码列表（原版 CCodeTypesForCombobox、AddComboCodePages）
	- 编码能否加 BOM、BOM 的默认值（CCodeTypeName::UseBom、IsBomDefOn）
	- 保存前的检查（CCodeChecker::OnCheckSave）：换行符混在、不能用这个编码表示的字符和它的位置
	- 完成标志：第 18 步的样本文件用 Document 打开再保存，字节不变（App 里经过 SakuraDocument 的同样测试在 macos/app/Tests/OpenSaveTests.swift）
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

#include <algorithm>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <sstream>

using namespace sakura::core;

namespace {

class MacSaveTest : public ::testing::Test {
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
	//! 类型别设置「保存時に改行コードの混在を警告する」
	void SetCheckEol(bool check)
	{
		STypeConfig type;
		ASSERT_TRUE(CDocTypeManager().GetTypeConfig(CTypeConfig(0), type));
		type.m_bChkEnterAtEnd = check;
		ASSERT_TRUE(CDocTypeManager().SetTypeConfig(CTypeConfig(0), type));
		m_doc = Document::Create();
		ASSERT_NE(nullptr, m_doc);
	}

	std::unique_ptr<Document> m_doc;
};

bool Contains(const std::vector<EncodingChoice>& list, Encoding code)
{
	return std::any_of(list.begin(), list.end(), [code](const EncodingChoice& c) { return c.code == code; });
}

} // namespace

// ---------------------------------------------------------------------------
// 编码列表
// ---------------------------------------------------------------------------

TEST_F(MacSaveTest, EncodingChoicesAreSameAsOriginalCombobox)
{
	const auto list = EncodingChoices();
	ASSERT_EQ(10u, list.size());
	const Encoding codes[] = { encoding::AutoDetect, encoding::SJIS, encoding::JIS, encoding::EUC, encoding::Latin1,
		encoding::UTF16LE, encoding::UTF16BE, encoding::UTF8, encoding::CESU8, encoding::UTF7 };
	const char16_t* names[] = { u"自動選択", u"SJIS", u"JIS", u"EUC-JP", u"Latin1",
		u"UTF-16", u"UTF-16BE", u"UTF-8", u"CESU-8", u"UTF-7" };
	for (size_t i = 0; i < list.size(); ++i) {
		EXPECT_EQ(codes[i], list[i].code) << i;
		EXPECT_EQ(Text(names[i]), list[i].name) << i;
	}
}

TEST_F(MacSaveTest, CodePageChoices)
{
	const auto list = CodePageChoices();
	ASSERT_LE(4u, list.size());
	EXPECT_EQ(90, list[0].code);
	EXPECT_EQ(Text(u"CP_ACP"), list[0].name);
	EXPECT_EQ(91, list[1].code);
	EXPECT_EQ(Text(u"CP_OEM"), list[1].name);
	EXPECT_TRUE(Contains(list, 932));
	EXPECT_TRUE(Contains(list, 1252));
	// 原版自己实现的 UTF-32 也在里面。CP_ACP、CP_OEM 之后按代码页的编号排列
	const auto utf32 = std::find_if(list.begin(), list.end(), [](const EncodingChoice& c) { return c.code == 12000; });
	ASSERT_NE(list.end(), utf32);
	EXPECT_EQ(Text(u"12000 (UTF-32LE)"), utf32->name);
	EXPECT_TRUE(Contains(list, 12001));
	EXPECT_TRUE(std::is_sorted(list.begin() + 2, list.end(),
		[](const EncodingChoice& a, const EncodingChoice& b) { return a.code < b.code; }));
	for (const auto& c : list) {
		EXPECT_TRUE(IsValidEncoding(c.code)) << c.code;
		EXPECT_FALSE(c.name.empty()) << c.code;
	}
}

TEST_F(MacSaveTest, BomAvailability)
{
	EXPECT_TRUE(EncodingCanHaveBom(encoding::UTF8));
	EXPECT_TRUE(EncodingCanHaveBom(encoding::UTF16LE));
	EXPECT_TRUE(EncodingCanHaveBom(encoding::UTF16BE));
	EXPECT_TRUE(EncodingCanHaveBom(encoding::CESU8));
	EXPECT_TRUE(EncodingCanHaveBom(encoding::UTF7));
	EXPECT_TRUE(EncodingCanHaveBom(encoding::UTF32LE));
	EXPECT_FALSE(EncodingCanHaveBom(encoding::SJIS));
	EXPECT_FALSE(EncodingCanHaveBom(encoding::JIS));
	EXPECT_FALSE(EncodingCanHaveBom(encoding::EUC));
	EXPECT_FALSE(EncodingCanHaveBom(encoding::Latin1));
	// 代码页按 U+FEFF 能否转换决定（原版相同），这里不检查
	EXPECT_FALSE(EncodingCanHaveBom(encoding::AutoDetect));

	// UTF-16 默认有 BOM，UTF-8 默认没有（与原版相同）
	EXPECT_TRUE(EncodingBomDefault(encoding::UTF16LE));
	EXPECT_TRUE(EncodingBomDefault(encoding::UTF16BE));
	EXPECT_FALSE(EncodingBomDefault(encoding::UTF8));
	EXPECT_FALSE(EncodingBomDefault(encoding::SJIS));
}

// ---------------------------------------------------------------------------
// 保存前的检查
// ---------------------------------------------------------------------------

TEST_F(MacSaveTest, CheckSaveNothingToWarn)
{
	SetText(u"abc\r\nあいう\r\n");
	const SaveCheck check = m_doc->CheckSave(SaveOptions{ encoding::SJIS });
	EXPECT_FALSE(check.eolMixed);
	EXPECT_FALSE(check.lostSome);
}

TEST_F(MacSaveTest, CheckSaveMixedEol)
{
	SetCheckEol(true);
	SetText(u"a\r\nb\nc");
	EXPECT_TRUE(m_doc->CheckSave().eolMixed);
	// 保存时统一换行符的话不用问
	EXPECT_FALSE(m_doc->CheckSave(SaveOptions{ std::nullopt, std::nullopt, Eol::LF }).eolMixed);
	// 最后一行没有换行符不算混在
	SetText(u"a\nb\nc");
	EXPECT_FALSE(m_doc->CheckSave().eolMixed);
	// 检查没有改文档
	SetText(u"a\r\nb\nc");
	EXPECT_EQ(Eol::CRLF, m_doc->GetLineEol(0));
	EXPECT_EQ(Eol::LF, m_doc->GetLineEol(1));
}

TEST_F(MacSaveTest, CheckSaveMixedEolDisabledByTypeSetting)
{
	SetCheckEol(false);
	SetText(u"a\r\nb\nc");
	EXPECT_FALSE(m_doc->CheckSave().eolMixed);
}

TEST_F(MacSaveTest, CheckSaveLostCharacterPosition)
{
	SetText(u"abc\nxyé\n");
	const SaveCheck check = m_doc->CheckSave(SaveOptions{ encoding::SJIS });
	EXPECT_TRUE(check.lostSome);
	EXPECT_EQ(1, check.lostAt.line);
	EXPECT_EQ(2, check.lostAt.column);
	EXPECT_EQ(Text(u"é"), check.lostChar);
	EXPECT_EQ(Text(u"U+00E9"), check.lostCharCode);
	// UTF-8 可以表示
	EXPECT_FALSE(m_doc->CheckSave(SaveOptions{ encoding::UTF8 }).lostSome);
}

TEST_F(MacSaveTest, CheckSaveLostSurrogatePair)
{
	SetText(u"a\U0001F600");
	const SaveCheck check = m_doc->CheckSave(SaveOptions{ encoding::EUC });
	EXPECT_TRUE(check.lostSome);
	EXPECT_EQ(0, check.lostAt.line);
	EXPECT_EQ(1, check.lostAt.column);
	EXPECT_EQ(Text(u"\U0001F600"), check.lostChar);
	EXPECT_FALSE(check.lostCharCode.empty());
}

TEST_F(MacSaveTest, CheckSaveCodePageComparesRoundTrip)
{
	// 代码页不返回 LOSESOME，原版自己比较转换前后的文字
	SetText(u"abc\ndeあf");
	const SaveCheck check = m_doc->CheckSave(SaveOptions{ 1252 });
	EXPECT_TRUE(check.lostSome);
	EXPECT_EQ(1, check.lostAt.line);
	EXPECT_EQ(2, check.lostAt.column);
	EXPECT_EQ(Text(u"あ"), check.lostChar);
	EXPECT_EQ(Text(u"U+3042"), check.lostCharCode);
	EXPECT_FALSE(m_doc->CheckSave(SaveOptions{ 932 }).lostSome);
}

TEST_F(MacSaveTest, CheckSaveUsesCurrentEncodingByDefault)
{
	// 新文档的编码是类型别设置的默认值
	SetText(u"あ");
	const Encoding current = m_doc->GetFileInfo().encoding;
	EXPECT_EQ(m_doc->CheckSave(SaveOptions{ current }).lostSome, m_doc->CheckSave().lostSome);
	EXPECT_TRUE(m_doc->CheckSave(SaveOptions{ encoding::Latin1 }).lostSome);
}

// ---------------------------------------------------------------------------
// 完成标志：样本文件打开再保存，字节不变
// ---------------------------------------------------------------------------

namespace {

struct Sample {
	std::string name;
	Encoding code = encoding::None;
	bool bom = false;
	Encoding detect = -1;	//!< 自动识别的期望。-1 是不能自动识别（指定编码打开）
};

std::string ReadFileBytes(const std::filesystem::path& path)
{
	std::ifstream in(path, std::ios::binary);
	return std::string(std::istreambuf_iterator<char>(in), std::istreambuf_iterator<char>());
}

std::vector<Sample> LoadSamples()
{
	std::vector<Sample> samples;
	std::istringstream in(ReadFileBytes(std::filesystem::path(SAKURA_ROUNDTRIP_DATA_DIR) / "manifest.tsv"));
	std::string line;
	while (std::getline(in, line)) {
		if (line.empty() || line[0] == '#') continue;
		std::istringstream fields(line);
		Sample s;
		std::string code, codec, bom, detect;
		std::getline(fields, s.name, '\t');
		std::getline(fields, code, '\t');
		std::getline(fields, codec, '\t');
		std::getline(fields, bom, '\t');
		std::getline(fields, detect, '\t');
		s.code = std::stoi(code);
		s.bom = bom == "1";
		s.detect = std::stoi(detect);
		samples.push_back(s);
	}
	return samples;
}

} // namespace

TEST_F(MacSaveTest, SamplesOpenThenSaveAreByteIdentical)
{
	const auto samples = LoadSamples();
	ASSERT_LE(80u, samples.size());
	const auto dir = std::filesystem::path(std::getenv("HOME")) / "mac-save-roundtrip";
	std::filesystem::create_directories(dir);
	for (const auto& s : samples) {
		const auto src = std::filesystem::path(SAKURA_ROUNDTRIP_DATA_DIR) / (s.name + ".bin");
		const auto dst = dir / (s.name + ".bin");
		// 能自动识别的样本用「自動選択」打开，其他的指定编码打开（与打开对话框相同）
		const Encoding open = (s.detect != -1) ? encoding::AutoDetect : s.code;
		auto doc = Document::Create();
		ASSERT_NE(nullptr, doc);
		ASSERT_EQ(Result::Ok, doc->Open(Text(src.u16string()), OpenOptions{ open })) << s.name;
		EXPECT_EQ(s.code, doc->GetFileInfo().encoding) << s.name;
		EXPECT_EQ(s.bom, doc->GetFileInfo().bom) << s.name;
		EXPECT_FALSE(doc->CheckSave().lostSome) << s.name;
		// 与上書き保存相同的设置（现在的编码、BOM，不转换换行符）
		ASSERT_EQ(Result::Ok, doc->SaveAs(Text(dst.u16string()))) << s.name;
		EXPECT_TRUE(ReadFileBytes(src) == ReadFileBytes(dst)) << s.name;
	}
	std::error_code ec;
	std::filesystem::remove_all(dir, ec);
}
