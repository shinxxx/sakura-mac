/*! @file
	@brief 核心库对外接口（计划第 22 步）的测试

	只通过 sakura_core/SakuraCore.h 使用核心库，与之后界面层（桥接层、Swift）的用法相同：
	- 启动和结束（共通设置、sakura.ini）
	- 打开、保存（编码、BOM、换行符；保存后的字节与原版的写法一致）
	- 编辑、撤销、重做、修改标记
	- 查找、全部替换（文字列、单词单位、区分大小写、正则表达式）
	- 命令（功能编号、名字、能否执行）
	- 接口头文件只引用 C++ 标准库的头文件
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
#include <iterator>
#include <regex>
#include <set>
#include <string>

namespace fs = std::filesystem;
using namespace sakura::core;

namespace {

std::string ReadBytes(const fs::path& path)
{
	std::ifstream in(path, std::ios::binary);
	return std::string(std::istreambuf_iterator<char>(in), std::istreambuf_iterator<char>());
}

void WriteBytes(const fs::path& path, const std::string& bytes)
{
	std::ofstream out(path, std::ios::binary);
	out.write(bytes.data(), static_cast<std::streamsize>(bytes.size()));
}

Text ToText(const fs::path& path)
{
	return path.u16string();
}

std::string Utf8(const Text& t)
{
	std::string s;
	for (std::size_t i = 0; i < t.size(); ++i) {
		char32_t c = t[i];
		if (0xD800 <= c && c < 0xDC00 && i + 1 < t.size()) {
			c = 0x10000 + ((c - 0xD800) << 10) + (t[++i] - 0xDC00);
		}
		if (c < 0x80) {
			s += static_cast<char>(c);
		} else if (c < 0x800) {
			s += static_cast<char>(0xC0 | (c >> 6));
			s += static_cast<char>(0x80 | (c & 0x3F));
		} else if (c < 0x10000) {
			s += static_cast<char>(0xE0 | (c >> 12));
			s += static_cast<char>(0x80 | ((c >> 6) & 0x3F));
			s += static_cast<char>(0x80 | (c & 0x3F));
		} else {
			s += static_cast<char>(0xF0 | (c >> 18));
			s += static_cast<char>(0x80 | ((c >> 12) & 0x3F));
			s += static_cast<char>(0x80 | ((c >> 6) & 0x3F));
			s += static_cast<char>(0x80 | (c & 0x3F));
		}
	}
	return s;
}

//! 测试失败时显示 UTF-8
#define EXPECT_TEXT(expected, actual) EXPECT_EQ(Utf8(expected), Utf8(actual))

class CoreApiTest : public ::testing::Test {
protected:
	void SetUp() override
	{
		ASSERT_TRUE(Startup());
		// HOME 是每个测试进程自己的临时文件夹（mac-test-home.cpp）
		m_dir = fs::path(std::getenv("HOME")) / "core-api-work";
		fs::remove_all(m_dir);
		fs::create_directories(m_dir);
		m_doc = Document::Create();
		ASSERT_NE(nullptr, m_doc);
	}
	void TearDown() override
	{
		m_doc.reset();
		Shutdown(false);
		std::error_code ec;
		fs::remove_all(m_dir, ec);
	}

	//! 设置全文（作为一次编辑）
	void SetText(const Text& text)
	{
		ASSERT_EQ(Result::Ok, m_doc->Replace(Range{ Position{}, m_doc->EndPosition() }, text));
	}

	fs::path m_dir;
	std::unique_ptr<Document> m_doc;
};

} // namespace

// ---------------------------------------------------------------------------
// 启动和结束
// ---------------------------------------------------------------------------

TEST(CoreApiStartup, StartupLoadsSettingsAndShutdownSavesThem)
{
	ASSERT_FALSE(IsStarted());
	EXPECT_EQ(nullptr, Document::Create());	// 启动前不能建立文档

	ASSERT_TRUE(Startup());
	EXPECT_TRUE(IsStarted());
	EXPECT_TRUE(Startup());	// 第二次什么也不做
	const fs::path ini(SettingsFilePath());
	EXPECT_EQ(fs::path(std::getenv("HOME")) / "Library" / "Application Support" / "sakura" / "sakura.ini", ini);
	EXPECT_TRUE(fs::exists(ini)) << "没有 sakura.ini 时写出默认设置（与原版控制进程相同）";

	fs::remove(ini);
	Shutdown(false);
	EXPECT_FALSE(IsStarted());
	EXPECT_FALSE(fs::exists(ini)) << "saveSettings=false 时不写出";

	ASSERT_TRUE(Startup());
	fs::remove(ini);
	Shutdown(true);
	EXPECT_TRUE(fs::exists(ini)) << "结束时写出 sakura.ini";
	Shutdown(true);	// 已经结束时什么也不做
}

// ---------------------------------------------------------------------------
// 新文档、编辑
// ---------------------------------------------------------------------------

TEST_F(CoreApiTest, NewDocumentIsEmpty)
{
	EXPECT_EQ(0, m_doc->LineCount());
	EXPECT_TEXT(u"", m_doc->GetText());
	EXPECT_EQ((Position{ 0, 0 }), m_doc->EndPosition());
	EXPECT_FALSE(m_doc->IsModified());
	EXPECT_FALSE(m_doc->CanUndo());
	EXPECT_FALSE(m_doc->CanRedo());
	const FileInfo& info = m_doc->GetFileInfo();
	EXPECT_TRUE(info.path.empty());
	EXPECT_EQ(0, info.typeIndex);
	EXPECT_FALSE(info.typeName.empty());
	EXPECT_TRUE(IsValidEncoding(info.encoding));
	EXPECT_EQ(Eol::CRLF, m_doc->GetNewLineEol());	// 原版的默认设置
}

TEST_F(CoreApiTest, InsertReplaceDelete)
{
	Position end;
	ASSERT_EQ(Result::Ok, m_doc->Insert(Position{ 0, 0 }, u"abc\r\ndef", &end));
	EXPECT_EQ((Position{ 1, 3 }), end);
	EXPECT_EQ(2, m_doc->LineCount());
	EXPECT_TEXT(u"abc", m_doc->GetLine(0));
	EXPECT_TEXT(u"abc\r\n", m_doc->GetLine(0, true));
	EXPECT_EQ(Eol::CRLF, m_doc->GetLineEol(0));
	EXPECT_EQ(Eol::None, m_doc->GetLineEol(1));
	EXPECT_EQ((Position{ 1, 3 }), m_doc->EndPosition());
	EXPECT_TRUE(m_doc->IsModified());

	// 在行中间插入多行
	ASSERT_EQ(Result::Ok, m_doc->Insert(Position{ 0, 1 }, u"X\nY", &end));
	EXPECT_EQ((Position{ 1, 1 }), end);
	EXPECT_TEXT(u"aX\nYbc\r\ndef", m_doc->GetText());
	EXPECT_EQ(Eol::LF, m_doc->GetLineEol(0));

	// 跨行替换
	ASSERT_EQ(Result::Ok, m_doc->Replace(Range{ Position{ 0, 1 }, Position{ 1, 2 } }, u"--", &end));
	EXPECT_EQ((Position{ 0, 3 }), end);
	EXPECT_TEXT(u"a--c\r\ndef", m_doc->GetText());
	EXPECT_TEXT(u"--c\r\nd", m_doc->GetText(Range{ Position{ 0, 1 }, Position{ 1, 1 } }));

	// 删除换行符
	ASSERT_EQ(Result::Ok, m_doc->Delete(Range{ Position{ 0, 4 }, Position{ 1, 0 } }));
	EXPECT_TEXT(u"a--cdef", m_doc->GetText());
	EXPECT_EQ(1, m_doc->LineCount());

	// 末尾加上换行后，EOF 在下一行开头
	ASSERT_EQ(Result::Ok, m_doc->Insert(m_doc->EndPosition(), u"\n"));
	EXPECT_EQ((Position{ 1, 0 }), m_doc->EndPosition());
	ASSERT_EQ(Result::Ok, m_doc->Insert(Position{ 1, 0 }, u"z"));
	EXPECT_TEXT(u"a--cdef\nz", m_doc->GetText());
}

TEST_F(CoreApiTest, InvalidPositionsAreRejected)
{
	SetText(u"ab\r\ncd");
	const Text before = m_doc->GetText();
	EXPECT_EQ(Result::InvalidArgument, m_doc->Insert(Position{ 0, 3 }, u"x"));	// 改行の中
	EXPECT_EQ(Result::InvalidArgument, m_doc->Insert(Position{ 2, 0 }, u"x"));	// 最後の行に改行がないので EOF は (1,2)
	EXPECT_EQ(Result::InvalidArgument, m_doc->Insert(Position{ -1, 0 }, u"x"));
	EXPECT_EQ(Result::InvalidArgument, m_doc->Replace(Range{ Position{ 1, 0 }, Position{ 0, 0 } }, u"x"));	// 逆向き
	EXPECT_TEXT(before, m_doc->GetText());
	EXPECT_TEXT(u"", m_doc->GetLine(5));
	EXPECT_TEXT(u"", m_doc->GetText(Range{ Position{ 0, 0 }, Position{ 9, 0 } }));
}

TEST_F(CoreApiTest, UndoRedoRestoresTextAndModifiedFlag)
{
	ASSERT_EQ(Result::Ok, m_doc->Insert(Position{}, u"one\ntwo\n"));
	ASSERT_EQ(Result::Ok, m_doc->Replace(Range{ Position{ 0, 0 }, Position{ 1, 3 } }, u"1\n2\n3"));
	EXPECT_TEXT(u"1\n2\n3\n", m_doc->GetText());

	Position caret;
	ASSERT_EQ(Result::Ok, m_doc->Undo(&caret));
	EXPECT_TEXT(u"one\ntwo\n", m_doc->GetText());
	EXPECT_EQ((Position{ 0, 0 }), caret);
	EXPECT_TRUE(m_doc->CanRedo());
	ASSERT_EQ(Result::Ok, m_doc->Undo());
	EXPECT_TEXT(u"", m_doc->GetText());
	EXPECT_EQ(0, m_doc->LineCount());
	EXPECT_FALSE(m_doc->IsModified()) << "回到了最初的状态";
	EXPECT_FALSE(m_doc->CanUndo());
	EXPECT_EQ(Result::InvalidArgument, m_doc->Undo());

	ASSERT_EQ(Result::Ok, m_doc->Redo());
	ASSERT_EQ(Result::Ok, m_doc->Redo(&caret));
	EXPECT_TEXT(u"1\n2\n3\n", m_doc->GetText());
	EXPECT_EQ((Position{ 2, 1 }), caret);
	EXPECT_TRUE(m_doc->IsModified());
	EXPECT_FALSE(m_doc->CanRedo());

	// 撤销后再编辑，可以重做的部分丢弃
	ASSERT_EQ(Result::Ok, m_doc->Undo());
	ASSERT_EQ(Result::Ok, m_doc->Insert(Position{}, u">"));
	EXPECT_FALSE(m_doc->CanRedo());
	EXPECT_TEXT(u">one\ntwo\n", m_doc->GetText());
}

TEST_F(CoreApiTest, UndoManyEditsBackToOriginal)
{
	SetText(u"0123456789\nabcdefghij\n");
	const Text original = m_doc->GetText();
	// 用简单的随机数反复插入、删除、替换
	unsigned seed = 12345;
	auto rnd = [&](int n) { seed = seed * 1103515245u + 12345u; return static_cast<int>((seed >> 16) % static_cast<unsigned>(n)); };
	std::vector<Text> history{ original };
	for (int i = 0; i < 200; i++) {
		const int nLines = m_doc->LineCount();
		const int line = rnd(nLines);
		const int len = static_cast<int>(m_doc->GetLine(line).size());
		Position a{ line, rnd(len + 1) };
		Position b = a;
		if (rnd(2)) {
			const int line2 = std::min(nLines - 1, line + rnd(2));
			b = Position{ line2, line2 == line ? a.column + rnd(len - a.column + 1) : rnd(static_cast<int>(m_doc->GetLine(line2).size()) + 1) };
		}
		static const Text inserts[] = { u"", u"x", u"\n", u"\r\n", u"あい\nう", u"\r", u"\U0001F600" };
		const Text ins = inserts[rnd(7)];
		if (a == b && ins.empty()) continue;	// 什么也不改的编辑不记入撤销缓冲
		ASSERT_EQ(Result::Ok, m_doc->Replace(Range{ a, b }, ins)) << i;
		history.push_back(m_doc->GetText());
	}
	for (int i = static_cast<int>(history.size()) - 1; i > 0; i--) {
		ASSERT_EQ(history[i], m_doc->GetText()) << i;
		ASSERT_EQ(Result::Ok, m_doc->Undo()) << i;
	}
	EXPECT_TEXT(original, m_doc->GetText());
	for (std::size_t i = 1; i < history.size(); i++) {
		ASSERT_EQ(Result::Ok, m_doc->Redo()) << i;
		ASSERT_EQ(history[i], m_doc->GetText()) << i;
	}
}

TEST_F(CoreApiTest, BeginEndEditMakesOneUndoStep)
{
	SetText(u"abc");
	m_doc->BeginEdit();
	ASSERT_EQ(Result::Ok, m_doc->Insert(Position{ 0, 0 }, u"1"));
	m_doc->BeginEdit();	// 嵌套
	ASSERT_EQ(Result::Ok, m_doc->Insert(Position{ 0, 4 }, u"2"));
	m_doc->EndEdit();
	EXPECT_EQ(Result::InvalidArgument, m_doc->Undo()) << "编辑途中不能撤销";
	ASSERT_EQ(Result::Ok, m_doc->Delete(Range{ Position{ 0, 2 }, Position{ 0, 3 } }));
	m_doc->EndEdit();
	EXPECT_TEXT(u"1ac2", m_doc->GetText());
	ASSERT_EQ(Result::Ok, m_doc->Undo());
	EXPECT_TEXT(u"abc", m_doc->GetText());
	m_doc->EndEdit();	// 多余的 EndEdit 不出错
	// 空的编辑块不进入撤销缓冲
	m_doc->BeginEdit();
	m_doc->EndEdit();
	ASSERT_EQ(Result::Ok, m_doc->Undo());
	EXPECT_TEXT(u"", m_doc->GetText());
}

// ---------------------------------------------------------------------------
// 打开、保存
// ---------------------------------------------------------------------------

TEST_F(CoreApiTest, OpenDetectsEncodingAndSaveKeepsBytes)
{
	struct Sample {
		const char* name;
		std::string bytes;
		Encoding encoding;
		bool bom;
		Text text;
	};
	const Sample samples[] = {
		// SJIS：「あいう」和「ｱ漢字」
		{ "sjis.txt", "\x82\xA0\x82\xA2\x82\xA4\r\n\xB1\x8A\xBF\x8E\x9A\r\n", encoding::SJIS, false, u"あいう\r\nｱ漢字\r\n" },
		{ "utf8bom.txt", "\xEF\xBB\xBF" "abc\n\xE3\x81\x82\n", encoding::UTF8, true, u"abc\nあ\n" },
		{ "utf8.txt", "\xE6\x97\xA5\xE6\x9C\xAC\xE8\xAA\x9E\xE3\x81\xAE\xE3\x83\x86\xE3\x82\xAD\xE3\x82\xB9\xE3\x83\x88\r", encoding::UTF8, false, u"日本語のテキスト\r" },
		{ "utf16le.txt", std::string("\xFF\xFE" "a\0\r\0\n\0B\x30", 10), encoding::UTF16LE, true, u"a\r\nあ" },
		{ "eucjp.txt", "\xA4\xA2\xA4\xA4\xA4\xA6\xA4\xA8\xA4\xAA\n", encoding::EUC, false, u"あいうえお\n" },
	};
	for (const auto& s : samples) {
		const fs::path path = m_dir / s.name;
		WriteBytes(path, s.bytes);
		ASSERT_EQ(Result::Ok, m_doc->Open(ToText(path))) << s.name;
		const FileInfo& info = m_doc->GetFileInfo();
		EXPECT_EQ(s.encoding, info.encoding) << s.name << " " << Utf8(EncodingName(info.encoding));
		EXPECT_EQ(s.bom, info.bom) << s.name;
		EXPECT_TEXT(s.text, m_doc->GetText()) << s.name;
		EXPECT_FALSE(m_doc->IsModified());
		EXPECT_FALSE(m_doc->CanUndo());

		// 覆盖保存（command::FileSave）后字节相同
		ASSERT_EQ(Result::Ok, m_doc->ExecuteCommand(command::FileSave)) << s.name;
		EXPECT_EQ(s.bytes, ReadBytes(path)) << s.name;
	}
}

TEST_F(CoreApiTest, OpenWithSpecifiedEncoding)
{
	const fs::path path = m_dir / "a.txt";
	WriteBytes(path, "\x82\xA0");	// SJIS 的「あ」，按 Latin1 是 2 个字符
	ASSERT_EQ(Result::Ok, m_doc->Open(ToText(path), OpenOptions{ encoding::Latin1 }));
	EXPECT_EQ(encoding::Latin1, m_doc->GetFileInfo().encoding);
	EXPECT_TEXT(u"‚ ", m_doc->GetText());
	ASSERT_EQ(Result::Ok, m_doc->Open(ToText(path), OpenOptions{ encoding::SJIS }));
	EXPECT_TEXT(u"あ", m_doc->GetText());
	EXPECT_EQ(Result::InvalidArgument, m_doc->Open(ToText(path), OpenOptions{ 12345678 }));
	EXPECT_EQ(Result::Failed, m_doc->Open(ToText(m_dir / "no-such-file.txt")));
	EXPECT_EQ(0, m_doc->LineCount());
}

TEST_F(CoreApiTest, OpenChoosesTypeByFileName)
{
	const fs::path cpp = m_dir / "main.cpp";
	WriteBytes(cpp, "int main() {}\n");
	ASSERT_EQ(Result::Ok, m_doc->Open(ToText(cpp)));
	EXPECT_NE(0, m_doc->GetFileInfo().typeIndex);
	EXPECT_TEXT(u"C/C++", m_doc->GetFileInfo().typeName);

	// 另存为时扩展名变了，类型也跟着变
	ASSERT_EQ(Result::Ok, m_doc->SaveAs(ToText(m_dir / "notes.txt")));
	EXPECT_TEXT(ToText(m_dir / "notes.txt"), m_doc->GetFileInfo().path);
	EXPECT_TEXT(u"テキスト", m_doc->GetFileInfo().typeName);
}

TEST_F(CoreApiTest, SaveAsConvertsEncodingBomAndEol)
{
	SetText(u"あ\r\nb\nc\rd");
	EXPECT_TRUE(m_doc->IsModified());
	EXPECT_EQ(Result::InvalidArgument, m_doc->Save()) << "无题文档不能覆盖保存";
	EXPECT_FALSE(m_doc->IsCommandEnabled(command::FileSave));

	const fs::path path = m_dir / "out.txt";
	ASSERT_EQ(Result::Ok, m_doc->SaveAs(ToText(path), SaveOptions{ encoding::UTF16BE, true, Eol::LF }));
	EXPECT_EQ(std::string("\xFE\xFF" "\x30\x42\0\n\0b\0\n\0c\0\n\0d", 16), ReadBytes(path));
	EXPECT_FALSE(m_doc->IsModified());
	EXPECT_EQ(encoding::UTF16BE, m_doc->GetFileInfo().encoding);
	EXPECT_TRUE(m_doc->GetFileInfo().bom);
	EXPECT_EQ(Eol::LF, m_doc->GetNewLineEol());

	// 统一换行符可以撤销（与原版相同）
	ASSERT_EQ(Result::Ok, m_doc->Undo());
	EXPECT_TEXT(u"あ\r\nb\nc\rd", m_doc->GetText());
	EXPECT_TRUE(m_doc->IsModified());

	// SJIS 表示不了的字符返回 LostSome（原版的 RESULT_LOSESOME）
	ASSERT_EQ(Result::Ok, m_doc->Insert(Position{ 0, 0 }, u"\U0001F600"));
	EXPECT_EQ(Result::LostSome, m_doc->SaveAs(ToText(path), SaveOptions{ encoding::SJIS, false }));
	EXPECT_EQ(Result::InvalidArgument, m_doc->SaveAs(ToText(path), SaveOptions{ 12345678 }));
	EXPECT_EQ(Result::Failed, m_doc->SaveAs(ToText(m_dir / "no-such-dir" / "x.txt")));
}

TEST_F(CoreApiTest, SaveEmptyDocumentWithBom)
{
	const fs::path path = m_dir / "empty.txt";
	ASSERT_EQ(Result::Ok, m_doc->SaveAs(ToText(path), SaveOptions{ encoding::UTF8, true }));
	EXPECT_EQ("\xEF\xBB\xBF", ReadBytes(path));
	ASSERT_EQ(Result::Ok, m_doc->SaveAs(ToText(path), SaveOptions{ encoding::UTF8, false }));
	EXPECT_EQ("", ReadBytes(path));
}

// ---------------------------------------------------------------------------
// 查找、替换
// ---------------------------------------------------------------------------

TEST_F(CoreApiTest, FindForwardBackwardAndOptions)
{
	SetText(u"Apple apple\npineapple APPLE\n");
	auto r = m_doc->Find(u"apple", Position{ 0, 0 });
	ASSERT_TRUE(r);
	EXPECT_EQ((Range{ Position{ 0, 0 }, Position{ 0, 5 } }), *r);	// 不区分大小写
	r = m_doc->Find(u"apple", Position{ 0, 0 }, SearchDirection::Forward, SearchOptions{ false, true, false });
	ASSERT_TRUE(r);
	EXPECT_EQ((Range{ Position{ 0, 6 }, Position{ 0, 11 } }), *r);
	r = m_doc->Find(u"apple", Position{ 1, 0 }, SearchDirection::Forward, SearchOptions{ false, false, true });
	ASSERT_TRUE(r);
	EXPECT_EQ((Range{ Position{ 1, 10 }, Position{ 1, 15 } }), *r) << "单词单位时不匹配 pineapple";
	r = m_doc->Find(u"apple", Position{ 1, 10 }, SearchDirection::Backward);
	ASSERT_TRUE(r);
	EXPECT_EQ((Range{ Position{ 1, 4 }, Position{ 1, 9 } }), *r);
	EXPECT_FALSE(m_doc->Find(u"banana", Position{}));
	EXPECT_TRUE(m_doc->GetLastSearchError().empty());

	EXPECT_EQ(4u, m_doc->FindAll(u"apple").size());
	EXPECT_EQ(2u, m_doc->FindAll(u"apple", SearchOptions{ false, true, false }).size());
	EXPECT_EQ(3u, m_doc->FindAll(u"apple", SearchOptions{ false, false, true }).size());
}

TEST_F(CoreApiTest, FindWithRegularExpression)
{
	SetText(u"id=12\r\nname=さくら\r\nid=345");
	const SearchOptions re{ true, false, false };
	auto r = m_doc->Find(u"id=([0-9]+)", Position{ 0, 1 }, SearchDirection::Forward, re);
	ASSERT_TRUE(r);
	EXPECT_EQ((Range{ Position{ 2, 0 }, Position{ 2, 6 } }), *r);
	r = m_doc->Find(u"^name=.+$", Position{}, SearchDirection::Forward, re);
	ASSERT_TRUE(r);
	EXPECT_EQ((Range{ Position{ 1, 0 }, Position{ 1, 8 } }), *r);
	// 包括换行符的匹配，末尾是下一行的开头
	r = m_doc->Find(u"12\\r\\n", Position{}, SearchDirection::Forward, re);
	ASSERT_TRUE(r);
	EXPECT_EQ((Range{ Position{ 0, 3 }, Position{ 1, 0 } }), *r);

	const auto all = m_doc->FindAll(u"[0-9]", re);
	EXPECT_EQ(5u, all.size());

	// 正则表达式有错误
	EXPECT_FALSE(m_doc->Find(u"(abc", Position{}, SearchDirection::Forward, re));
	EXPECT_FALSE(m_doc->GetLastSearchError().empty());
	EXPECT_TRUE(m_doc->FindAll(u"(abc", re).empty());
	EXPECT_EQ(-1, m_doc->ReplaceAll(u"(abc", u"x", re));
	EXPECT_FALSE(m_doc->GetLastSearchError().empty());
	EXPECT_FALSE(m_doc->Find(u"", Position{}));
}

TEST_F(CoreApiTest, ReplaceAllIsOneUndoStep)
{
	SetText(u"cat cat\ndog cat\n");
	EXPECT_EQ(3, m_doc->ReplaceAll(u"cat", u"lion"));
	EXPECT_TEXT(u"lion lion\ndog lion\n", m_doc->GetText());
	ASSERT_EQ(Result::Ok, m_doc->Undo());
	EXPECT_TEXT(u"cat cat\ndog cat\n", m_doc->GetText());

	// 替换后的文字里含有查找的词，也不会无限替换
	EXPECT_EQ(3, m_doc->ReplaceAll(u"cat", u"catcat"));
	EXPECT_TEXT(u"catcat catcat\ndog catcat\n", m_doc->GetText());
	ASSERT_EQ(Result::Ok, m_doc->Undo());

	// 替换成含有换行的文字
	EXPECT_EQ(3, m_doc->ReplaceAll(u"cat", u"c\na\nt"));
	EXPECT_TEXT(u"c\na\nt c\na\nt\ndog c\na\nt\n", m_doc->GetText());
	ASSERT_EQ(Result::Ok, m_doc->Undo());
	EXPECT_EQ(0, m_doc->ReplaceAll(u"bird", u"x"));
	EXPECT_TEXT(u"cat cat\ndog cat\n", m_doc->GetText());
}

TEST_F(CoreApiTest, ReplaceAllWithRegularExpression)
{
	SetText(u"2026-11-11\r\nx 1999-01-02 y 2000-12-31\r\nnone\r\n");
	const SearchOptions re{ true, false, false };
	EXPECT_EQ(3, m_doc->ReplaceAll(u"([0-9]{4})-([0-9]{2})-([0-9]{2})", u"$3/$2/$1", re));
	EXPECT_TEXT(u"11/11/2026\r\nx 02/01/1999 y 31/12/2000\r\nnone\r\n", m_doc->GetText());
	ASSERT_EQ(Result::Ok, m_doc->Undo());
	EXPECT_TEXT(u"2026-11-11\r\nx 1999-01-02 y 2000-12-31\r\nnone\r\n", m_doc->GetText());

	// 替换行末（$ 和换行）
	EXPECT_EQ(3, m_doc->ReplaceAll(u"$", u";", re));
	EXPECT_TEXT(u"2026-11-11;\r\nx 1999-01-02 y 2000-12-31;\r\nnone;\r\n", m_doc->GetText());
	ASSERT_EQ(Result::Ok, m_doc->Undo());
	// 大小写
	EXPECT_EQ(1, m_doc->ReplaceAll(u"NONE", u"some", re));
	EXPECT_EQ(0, m_doc->ReplaceAll(u"SOME", u"x", SearchOptions{ true, true, false }));
}

// ---------------------------------------------------------------------------
// 命令
// ---------------------------------------------------------------------------

TEST_F(CoreApiTest, CommandsByFunctionCode)
{
	// 名字与原版的菜单相同（sakura_rc.rc 的 STRINGTABLE）
	EXPECT_TEXT(u"元に戻す", CommandName(command::Undo));
	EXPECT_TEXT(u"やり直し", CommandName(command::Redo));
	EXPECT_TEXT(u"上書き保存", CommandName(command::FileSave));
	EXPECT_TEXT(u"", CommandName(0));
	EXPECT_TEXT(u"SJIS", EncodingName(encoding::SJIS));
	EXPECT_TEXT(u"UTF-8", EncodingName(encoding::UTF8));
	EXPECT_TEXT(u"CP1252", EncodingName(1252));
	EXPECT_TEXT(u"", EncodingName(12345678));
	EXPECT_TEXT(u"\r\n", EolText(Eol::CRLF));
	EXPECT_TEXT(u" ", EolText(Eol::LineSeparator));
	EXPECT_TEXT(u"", EolText(Eol::None));

	EXPECT_FALSE(m_doc->IsCommandEnabled(command::Undo));
	ASSERT_EQ(Result::Ok, m_doc->Insert(Position{}, u"a"));
	EXPECT_TRUE(m_doc->IsCommandEnabled(command::Undo));
	EXPECT_FALSE(m_doc->IsCommandEnabled(command::Redo));
	ASSERT_EQ(Result::Ok, m_doc->ExecuteCommand(command::Undo));
	EXPECT_TEXT(u"", m_doc->GetText());
	EXPECT_TRUE(m_doc->IsCommandEnabled(command::Redo));
	ASSERT_EQ(Result::Ok, m_doc->ExecuteCommand(command::Redo));
	EXPECT_TEXT(u"a", m_doc->GetText());
	EXPECT_EQ(Result::InvalidArgument, m_doc->ExecuteCommand(command::Redo));

	ASSERT_EQ(Result::Ok, m_doc->ExecuteCommand(command::NewLineLF));
	EXPECT_EQ(Eol::LF, m_doc->GetNewLineEol());
	ASSERT_EQ(Result::Ok, m_doc->ExecuteCommand(command::NewLineCR));
	EXPECT_EQ(Eol::CR, m_doc->GetNewLineEol());
	m_doc->SetNewLineEol(Eol::None);	// 无效的值忽略（与原版 Command_CHGMOD_EOL 相同）
	EXPECT_EQ(Eol::CR, m_doc->GetNewLineEol());

	// 编辑画面的命令还没有移植
	constexpr FunctionCode F_SELECTALL = 30401;
	EXPECT_FALSE(Document::IsCommandSupported(F_SELECTALL));
	EXPECT_EQ(Result::NotSupported, m_doc->ExecuteCommand(F_SELECTALL));
	EXPECT_FALSE(m_doc->IsCommandEnabled(F_SELECTALL));
	EXPECT_TRUE(Document::IsCommandSupported(command::FileSave));
}

TEST_F(CoreApiTest, NewLineEolFollowsFirstLineOfOpenedFile)
{
	const fs::path path = m_dir / "lf.txt";
	WriteBytes(path, "a\nb\r\n");
	ASSERT_EQ(Result::Ok, m_doc->Open(ToText(path)));
	EXPECT_EQ(Eol::LF, m_doc->GetNewLineEol());	// 与 CDocEditor::OnAfterLoad 相同
	WriteBytes(path, "a");
	ASSERT_EQ(Result::Ok, m_doc->Open(ToText(path)));
	EXPECT_EQ(Eol::CRLF, m_doc->GetNewLineEol());
}

// ---------------------------------------------------------------------------
// 接口头文件只引用 C++ 标准库（完成标志）。
// 编译上的确认是 CMake 的 sakura_core_api_header_check 目标（macos/core/api/header_check.cpp）
// ---------------------------------------------------------------------------

TEST(CoreApiHeader, IncludesOnlyStandardHeaders)
{
	const fs::path header = fs::path(SAKURA_ROOT_DIR) / "macos" / "core" / "include" / "sakura_core" / "SakuraCore.h";
	std::ifstream in(header);
	ASSERT_TRUE(in) << header;
	const std::set<std::string> allowed = { "cstdint", "memory", "optional", "string", "vector" };
	const std::regex include(R"(^\s*#\s*include\s*([<"])([^>"]+)[>"])");
	std::string line;
	int count = 0;
	while (std::getline(in, line)) {
		std::smatch m;
		if (std::regex_search(line, m, include)) {
			++count;
			EXPECT_EQ("<", m[1].str()) << line;
			EXPECT_TRUE(allowed.count(m[2].str())) << line;
		}
		EXPECT_EQ(std::string::npos, line.find("WCHAR")) << line;
		EXPECT_EQ(std::string::npos, line.find("_WIN32")) << line;
	}
	EXPECT_EQ(static_cast<int>(allowed.size()), count);
}
