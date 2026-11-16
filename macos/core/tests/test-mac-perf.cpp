/*! @file
	@brief 大文件、超长行的性能测试（计划第 36 步）

	核心库对大文件（20 万行、约 17 MB）和超长行（一行 200 万字）的打开、查找、置换、编辑、
	画面用的数据（排版行、文字位置、颜色）、输入法用的下标换算各量一次时间，打印出来（[PERF] 的行），
	超过上限时失败。上限按 Debug 构建定得很宽：目的是发现「随文件大小成平方地变慢」那样的问题。
	Release 构建的数值由 CI 的 core-perf-macos 打印，记录在 macos/docs/phase2-performance.md。

	另外确认全文的下标和位置的换算（Document::TextLength、OffsetOf、PositionAtOffset）的结果。
*/
/*
	Copyright (C) 2026, Sakura Editor Organization

	SPDX-License-Identifier: Zlib
*/
#include "sakura_core/SakuraCore.h"

#include <gtest/gtest.h>

#include <chrono>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <string>

#include <unistd.h>

using namespace sakura::core;

namespace {

namespace fs = std::filesystem;

//! 经过的时间（毫秒）
class Stopwatch {
public:
	double Ms() const
	{
		return std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - m_start).count();
	}

private:
	std::chrono::steady_clock::time_point m_start = std::chrono::steady_clock::now();
};

//! 量 f 的时间，打印，超过 limitMs 时失败
template <typename F>
void Measure(const char* name, double limitMs, F&& f)
{
	Stopwatch watch;
	f();
	const double ms = watch.Ms();
	std::cout << "[PERF] " << name << ": " << static_cast<long long>(ms + 0.5) << " ms (limit " << limitMs << " ms)" << std::endl;
	EXPECT_LT(ms, limitMs) << name;
}

constexpr int kLargeLines = 200000;		//!< 大文件的行数
constexpr int kLongChars = 2000000;		//!< 超长行的字数

class MacPerfTest : public ::testing::Test {
protected:
	static void SetUpTestSuite()
	{
		s_dir = fs::temp_directory_path() / ("sakura-perf-" + std::to_string(::getpid()));
		fs::create_directories(s_dir);
		// 大文件：日文和英文、TAB、C 风格的注释，每行不同的数字。最后一行有查找用的文字
		{
			std::ofstream out(s_dir / "large.txt", std::ios::binary);
			char buf[256];
			for (int i = 0; i < kLargeLines; ++i) {
				const int n = std::snprintf(buf, sizeof buf,
					"%07d: The quick brown fox \xE3\x82\xB8\xE3\x83\xA3\xE3\x83\xB3\xE3\x83\x97 over the lazy dog\tint x = %d; // comment\r\n", i, i);
				out.write(buf, n);
			}
			out << "needle at the end\r\n";
		}
		// 超长行：200 万字一行（没有换行），最后有查找用的文字
		{
			std::ofstream out(s_dir / "long.txt", std::ios::binary);
			const std::string chunk = "abcdefghi ";
			for (int i = 0; i < kLongChars / static_cast<int>(chunk.size()); ++i) out << chunk;
			out << "needle";
		}
	}
	static void TearDownTestSuite()
	{
		std::error_code ec;
		fs::remove_all(s_dir, ec);
	}
	void SetUp() override { ASSERT_TRUE(Startup()); }
	void TearDown() override { Shutdown(false); }

	static inline fs::path s_dir;
};

} // namespace

// 大文件：打开、查找、置换、编辑、画面的数据、输入法的换算
TEST_F(MacPerfTest, LargeFile)
{
	auto doc = Document::Create();
	Measure("large: open (17 MB, 200000 lines)", 15000, [&] {
		ASSERT_EQ(Result::Ok, doc->Open((s_dir / "large.txt").u16string()));
	});
	ASSERT_EQ(kLargeLines + 1, doc->LineCount());
	EXPECT_GE(doc->LayoutLineCount(), kLargeLines + 1);

	Measure("large: find at the end", 3000, [&] {
		auto r = doc->Find(u"needle", Position{});
		ASSERT_TRUE(r.has_value());
		EXPECT_EQ(kLargeLines, r->from.line);
	});
	Measure("large: find backward from the end", 3000, [&] {
		auto r = doc->Find(u"0000000", Position{ kLargeLines, 0 }, SearchDirection::Backward);
		ASSERT_TRUE(r.has_value());
		EXPECT_EQ(0, r->from.line);
	});
	SearchOptions regex;
	regex.regularExpression = true;
	Measure("large: regex find at the end", 5000, [&] {
		EXPECT_TRUE(doc->Find(u"needle\\s+at", Position{}, SearchDirection::Forward, regex).has_value());
	});
	Measure("large: find all", 5000, [&] {
		EXPECT_EQ(static_cast<size_t>(kLargeLines), doc->FindAll(u"fox").size());
	});

	// 画面：中间的 100 行（排版行、文字的位置、语法颜色）
	Measure("large: 100 rows for drawing (middle)", 1000, [&] {
		const int mid = doc->LayoutLineCount() / 2;
		size_t total = 0;
		for (int i = 0; i < 100; ++i) {
			const auto layout = doc->GetLayoutLine(mid + i);
			total += doc->GetLine(layout.start.line).size();
			total += doc->GetLayoutCharPositions(mid + i).size();
			total += doc->SyntaxColors(layout.start.line).size();
		}
		EXPECT_GT(total, 0u);
	});
	Measure("large: last row (jump to end)", 500, [&] {
		const auto layout = doc->GetLayoutLine(doc->LayoutLineCount() - 1);
		EXPECT_EQ(kLargeLines, layout.start.line);
		EXPECT_EQ((Position{ kLargeLines + 1, 0 }), doc->LayoutToLogic(doc->LogicToLayout(Position{ kLargeLines + 1, 0 })));
	});

	// 输入法：文末的位置和全文的下标（每次按键都问）
	std::int64_t length = 0;
	Measure("large: text length + offset at end + position at offset", 500, [&] {
		length = doc->TextLength();
		EXPECT_EQ(length, doc->OffsetOf(doc->EndPosition()));
		EXPECT_EQ(doc->EndPosition(), doc->PositionAtOffset(length));
	});

	// 编辑：文末输入、撤销（不重新排版全文）
	Measure("large: insert at the end and undo", 500, [&] {
		ASSERT_EQ(Result::Ok, doc->Insert(doc->EndPosition(), u"x"));
		ASSERT_EQ(Result::Ok, doc->Undo());
	});
	Measure("large: insert at the top and undo", 500, [&] {
		ASSERT_EQ(Result::Ok, doc->Insert(Position{}, u"x\r\n"));
		ASSERT_EQ(Result::Ok, doc->Undo());
	});
	EXPECT_EQ(length, doc->TextLength());

	// 折り返し的变更（全文重新排版）
	Measure("large: rewrap at 40 columns", 10000, [&] {
		doc->SetWrap(WrapMethod::SettingWidth, 40);
	});
	EXPECT_GT(doc->LayoutLineCount(), kLargeLines * 2);

	Measure("large: replace all (200000)", 20000, [&] {
		EXPECT_EQ(kLargeLines, doc->ReplaceAll(u"fox", u"cat"));
	});
}

// 超长行：打开、查找、画面的数据（行中间的排版行）、行末的编辑
TEST_F(MacPerfTest, LongLine)
{
	auto doc = Document::Create();
	Measure("long: open (one line, 2000000 chars)", 10000, [&] {
		ASSERT_EQ(Result::Ok, doc->Open((s_dir / "long.txt").u16string()));
	});
	ASSERT_EQ(1, doc->LineCount());
	const int rows = doc->LayoutLineCount();
	EXPECT_GT(rows, 1);
	std::cout << "[PERF] long: layout rows = " << rows << std::endl;

	Measure("long: find at the end", 3000, [&] {
		auto r = doc->Find(u"needle", Position{});
		ASSERT_TRUE(r.has_value());
		EXPECT_EQ(kLongChars, r->from.column);
	});
	Measure("long: syntax colors of the line (once per line)", 10000, [&] {
		(void)doc->SyntaxColors(0);
	});
	Measure("long: 50 rows for drawing (middle of the line)", 2000, [&] {
		size_t total = 0;
		for (int i = 0; i < 50 && rows / 2 + i < rows; ++i) {
			total += doc->GetLayoutLine(rows / 2 + i).length;
			total += doc->GetLayoutCharPositions(rows / 2 + i).size();
		}
		EXPECT_GT(total, 0u);
	});
	// 画面的每一行都换算光标的位置（光标在超长行的末尾时）
	Measure("long: caret position to layout x50 (end of the line)", 500, [&] {
		const auto end = doc->EndPosition();
		for (int i = 0; i < 50; ++i) {
			EXPECT_EQ(rows - 1, doc->LogicToLayout(end).line);
		}
	});
	Measure("long: offset and position at the end", 500, [&] {
		const auto end = doc->EndPosition();
		EXPECT_EQ(kLongChars + 6, doc->OffsetOf(end));
		EXPECT_EQ(end, doc->PositionAtOffset(doc->TextLength()));
	});
	Measure("long: insert at the end and undo", 3000, [&] {
		ASSERT_EQ(Result::Ok, doc->Insert(doc->EndPosition(), u"x"));
		ASSERT_EQ(Result::Ok, doc->Undo());
	});
	// 折り返さない：与原版相同，最大桁数（10240 桁）的地方折り返す
	Measure("long: no wrap", 5000, [&] {
		doc->SetWrap(WrapMethod::None, 80);
	});
	EXPECT_GT(doc->LayoutLineCount(), 1);
}

// 全文的下标和位置的换算（输入法用）：换行符的中间、超出范围
TEST(MacOffsetTest, OffsetAndPosition)
{
	ASSERT_TRUE(Startup());
	{
		auto doc = Document::Create();
		ASSERT_EQ(Result::Ok, doc->Insert(Position{}, u"ab\r\ncde\nf"));
		EXPECT_EQ(9, doc->TextLength());
		EXPECT_EQ(0, doc->OffsetOf(Position{ 0, 0 }));
		EXPECT_EQ(2, doc->OffsetOf(Position{ 0, 2 }));
		EXPECT_EQ(2, doc->OffsetOf(Position{ 0, 99 }));		// 列超出：行末（换行符之前）
		EXPECT_EQ(4, doc->OffsetOf(Position{ 1, 0 }));
		EXPECT_EQ(7, doc->OffsetOf(Position{ 1, 3 }));
		EXPECT_EQ(9, doc->OffsetOf(Position{ 2, 1 }));
		EXPECT_EQ(9, doc->OffsetOf(Position{ 5, 0 }));		// 行超出：文档末尾
		EXPECT_EQ(0, doc->OffsetOf(Position{ 0, -1 }));

		EXPECT_EQ((Position{ 0, 0 }), doc->PositionAtOffset(0));
		EXPECT_EQ((Position{ 0, 2 }), doc->PositionAtOffset(2));
		EXPECT_EQ((Position{ 0, 2 }), doc->PositionAtOffset(3));	// CR 和 LF 的中间：换行符之前
		EXPECT_EQ((Position{ 1, 0 }), doc->PositionAtOffset(4));
		EXPECT_EQ((Position{ 1, 3 }), doc->PositionAtOffset(7));
		EXPECT_EQ((Position{ 2, 0 }), doc->PositionAtOffset(8));
		EXPECT_EQ((Position{ 2, 1 }), doc->PositionAtOffset(9));
		EXPECT_EQ(doc->EndPosition(), doc->PositionAtOffset(100));
		EXPECT_EQ((Position{ 0, 0 }), doc->PositionAtOffset(-5));
		// 与全文的下标一致
		const auto text = doc->GetText();
		EXPECT_EQ(static_cast<std::int64_t>(text.size()), doc->TextLength());
		for (std::int64_t i = 0; i <= doc->TextLength(); ++i) {
			const auto p = doc->PositionAtOffset(i);
			const bool insideCrLf = (i == 3);
			EXPECT_EQ(insideCrLf ? 2 : i, doc->OffsetOf(p)) << i;
		}
	}
	{
		// 空的文档、最后以换行结束
		auto doc = Document::Create();
		EXPECT_EQ(0, doc->TextLength());
		EXPECT_EQ(0, doc->OffsetOf(Position{}));
		EXPECT_EQ((Position{ 0, 0 }), doc->PositionAtOffset(0));
		ASSERT_EQ(Result::Ok, doc->Insert(Position{}, u"a\n"));
		EXPECT_EQ(2, doc->OffsetOf(doc->EndPosition()));
		EXPECT_EQ(doc->EndPosition(), doc->PositionAtOffset(2));
	}
	Shutdown(false);
}

// 行的长度（不取出文字）和变更次数（界面层的缓存是否还有效）
TEST(MacOffsetTest, LineLengthAndChangeCount)
{
	ASSERT_TRUE(Startup());
	{
		auto doc = Document::Create();
		ASSERT_EQ(Result::Ok, doc->Insert(Position{}, u"ab\r\ncde\nf"));
		EXPECT_EQ(2, doc->LineLength(0));
		EXPECT_EQ(3, doc->LineLength(1));
		EXPECT_EQ(1, doc->LineLength(2));
		EXPECT_EQ(0, doc->LineLength(3));
		EXPECT_EQ(0, doc->LineLength(-1));

		// 编辑、撤销、重新排版时增加，只是读的时候不变
		auto count = doc->ChangeCount();
		(void)doc->GetText();
		(void)doc->Find(u"cd", Position{});
		EXPECT_EQ(count, doc->ChangeCount());
		ASSERT_EQ(Result::Ok, doc->Insert(Position{ 0, 0 }, u"x"));
		EXPECT_LT(count, doc->ChangeCount());
		count = doc->ChangeCount();
		ASSERT_EQ(Result::Ok, doc->Undo());
		EXPECT_LT(count, doc->ChangeCount());
		count = doc->ChangeCount();
		EXPECT_TRUE(doc->SetWrap(WrapMethod::SettingWidth, 20));
		EXPECT_LT(count, doc->ChangeCount());
	}
	Shutdown(false);
}
