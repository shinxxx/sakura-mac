/*! @file
	@brief 语法颜色（计划第 33 步）的测试

	原版的色分け类（view/colors 的 CColor_Comment、CColor_Quote、CColor_KeywordSet 等）原样编进了核心库，
	Document::SyntaxColors 按原版 CEditView::DrawLogicLine 的顺序调用它们。这里确认：
	- 各内置类型（types/CType_*.cpp 的默认设置）的注释、字符串、关键字、数字、URL
	- 跨行的块注释（排版时记下的行首状态）在编辑、撤销、折り返し之后也正确
	- 一个进程里开多个不同类型的文档时各用各的设置
	- sakura.ini 的类型别设置：正規表現キーワード、ヒアドキュメント、全部不显示时
*/
/*
	Copyright (C) 2026, Sakura Editor Organization

	SPDX-License-Identifier: Zlib
*/
#include "sakura_core/SakuraCore.h"
#include <gtest/gtest.h>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <utility>
#include <string>
#include <vector>
namespace fs = std::filesystem;
using namespace sakura::core;
namespace {

void WriteBytes(const fs::path& path, const std::string& bytes)
{
	std::ofstream out(path, std::ios::binary);
	out.write(bytes.data(), static_cast<std::streamsize>(bytes.size()));
}

/*!
	一行的颜色画成文字串，与行的文字一一对应，方便对照：
	「.」普通文字（テキスト）、「C」注释、「S」单引号字符串、「W」双引号字符串、
	「H」ヒアドキュメント、「U」URL、「N」半角数字、「1」～「9」「0」強調キーワード1～10、
	「a」～「j」正規表現キーワード1～10
*/
std::string Paint(Document& doc, int line)
{
	std::string s(doc.GetLine(line).size(), '.');
	for (const auto& run : doc.SyntaxColors(line)) {
		EXPECT_LT(run.from, run.to);
		const auto c = static_cast<ColorIndex>(run.color);
		char ch = '?';
		switch (c) {
		case ColorIndex::Comment: ch = 'C'; break;
		case ColorIndex::SingleQuote: ch = 'S'; break;
		case ColorIndex::DoubleQuote: ch = 'W'; break;
		case ColorIndex::Heredoc: ch = 'H'; break;
		case ColorIndex::Url: ch = 'U'; break;
		case ColorIndex::Digit: ch = 'N'; break;
		default:
			if (ColorIndex::Keyword1 <= c && c <= ColorIndex::Keyword10) {
				ch = "1234567890"[run.color - static_cast<int>(ColorIndex::Keyword1)];
			} else if (ColorIndex::Regex1 <= c && c <= ColorIndex::Regex10) {
				ch = static_cast<char>('a' + (run.color - static_cast<int>(ColorIndex::Regex1)));
			}
			break;
		}
		for (int i = run.from; i < run.to && i < static_cast<int>(s.size()); ++i) s[i] = ch;
	}
	return s;
}

//! 全部的行
std::vector<std::string> PaintAll(Document& doc)
{
	std::vector<std::string> v;
	for (int i = 0; i < doc.LineCount(); ++i) v.push_back(Paint(doc, i));
	return v;
}

class MacSyntaxColorTest : public ::testing::Test {
protected:
	void SetUp() override
	{
		ASSERT_TRUE(Startup());
		m_dir = fs::path(std::getenv("HOME")) / "syntax-color-work";
		fs::remove_all(m_dir);
		fs::create_directories(m_dir);
	}
	void TearDown() override
	{
		Shutdown(false);
		std::error_code ec;
		fs::remove_all(m_dir, ec);
	}
	//! 文件名决定类型别设置（CDocTypeManager::GetDocumentTypeOfPath）
	std::unique_ptr<Document> Open(const char* name, const std::string& text)
	{
		const auto path = m_dir / name;
		WriteBytes(path, text);
		auto doc = Document::Create();
		EXPECT_NE(nullptr, doc);
		OpenOptions options;
		options.encoding = encoding::UTF8;
		EXPECT_EQ(Result::Ok, doc->Open(path.u16string(), options));
		return doc;
	}

	fs::path m_dir;
};

} // namespace

// ---------------------------------------------------------------------------
// 各内置类型（types/CType_*.cpp 的默认设置）
// 期待值：原版的色分け类（CColor_Comment 等）本身就编进了核心库，下面是按原版的规则逐字核对过的结果
// ---------------------------------------------------------------------------

TEST_F(MacSyntaxColorTest, Cpp)
{
	auto doc = Open("a.cpp",
		"int x = 10; // c\n"
		"/* a\n"
		"b */ x\n"
		"#if 0\n"
		"foo\n"
		"#endif\n"
		"char* s = \"a\\\"b\"; char c = 'x';\n"
		"\"abc\n"
		"d\"\n"
		"0x1F 3.14 1e5 a1 12L\n"
		"return http://example.com/a;\n");
	EXPECT_EQ(2, doc->GetFileInfo().typeIndex);
	const std::vector<std::string> expected = {
		"111.....NN..CCCC",		// 強調キーワード1（C/C++ 的关键字集）、半角数字、行注释
		"CCCC",					// 块注释 /* */ 跨行
		"CCCC..",
		"CCCCC",				// 块注释2（#if 0 ～ #endif）
		"CCC",
		"CCCCCC",
		"1111......WWWWWW..1111.....SSS.",	// 转义（\"）在字符串里面
		"....",					// 「文字列は行内のみ」：行内没有闭合的引号不着色
		"..",
		"NNNN.NNNN.NNN....NNN",	// 16 进制、小数、指数、末尾的 L。字母后面的数字（a1）不是数字
		"111111.UUUUUUUUUUUUUUUUUUUUU",
	};
	EXPECT_EQ(expected, PaintAll(*doc));
}

TEST_F(MacSyntaxColorTest, TextUrlAndMail)
{
	// テキスト类型：引号和数字不着色（CType_Text.cpp），URL 和邮件地址着色
	auto doc = Open("a.txt", "see https://example.com/x now 123 \"q\" 'r'\nmail me@example.com\n");
	EXPECT_EQ(1, doc->GetFileInfo().typeIndex);
	const std::vector<std::string> expected = {
		"....UUUUUUUUUUUUUUUUUUUUU................",
		".....UUUUUUUUUUUUUU",
	};
	EXPECT_EQ(expected, PaintAll(*doc));
}

TEST_F(MacSyntaxColorTest, OtherBuiltInTypes)
{
	struct Case {
		const char* name;
		int type;
		const char* text;
		std::vector<std::string> expected;
	};
	const Case cases[] = {
		{ "a.html", 3, "<!-- c\n-->x <a href=\"u\">\n", { "CCCCCC", "CCC...1.1111.WWW." } },
		{ "a.sql", 4, "SELECT * FROM t -- c\n/* b */ WHERE a = 'x';\n", { "111111...1111...CCCC", "CCCCCCC.11111.....SSS." } },
		{ "a.cbl", 5, "      * c\n       MOVE 'A' TO B.\n", { "......CCC", ".......1111.SSS.11..." } },
		{ "a.java", 6, "public class A { /* c */ String s = \"x\"; } // e\n", { "111111.11111.....CCCCCCC............WWW....CCCC" } },
		{ "a.asm", 7, "mov ax, 10 ; c\n", { "........NN.CCC" } },
		{ "a.awk", 8, "{ print $1 } # c\n", { "..11111.11...CCC" } },
		{ "a.bat", 9, "REM c\n@echo off ::x\n", { "CCCCC", "11111.111...." } },
		{ "a.pas", 10, "begin { c } (* d *) x := 'a'; // e\nend.\n", { "11111.CCCCC.CCCCCCC......SSS..CCCC", "111." } },
		{ "a.tex", 11, "\\section{a} % c\n", { "11111111....CCC" } },
		{ "a.pl", 12, "my $x = 'a'; # c\nprint \"$x\";\n", { "11......SSS..CCC", "11111.WWWW." } },
		{ "a.py", 13, "def f(): # c\n  return 'a' + \"b\" + 1\n", { "111......CCC", "..111111.SSS...WWW...N" } },
		{ "a.vb", 14, "Dim a As String ' c\na = \"x\"\n", { "111...11.111111.CCC", "....WWW" } },
		{ "a.rtf", 15, "{\\rtf1 a}\n", { "........." } },
		{ "a.ini", 16, "; c\n[sec]\nkey=\"v\"\n", { "CCC", ".....", "......." } },
	};
	for (const auto& c : cases) {
		SCOPED_TRACE(c.name);
		auto doc = Open(c.name, c.text);
		EXPECT_EQ(c.type, doc->GetFileInfo().typeIndex);
		EXPECT_EQ(c.expected, PaintAll(*doc));
	}
}

// ---------------------------------------------------------------------------
// 跨行的色分け（排版时记下的行首状态 CLayout::GetColorTypePrev）
// ---------------------------------------------------------------------------

TEST_F(MacSyntaxColorTest, EditingUpdatesFollowingLines)
{
	auto doc = Open("a.cpp", "x\ny\nz */ w\n");
	EXPECT_EQ((std::vector<std::string>{ ".", ".", "......" }), PaintAll(*doc));	// 只有「*/」不是注释

	// 开头插入 /* 后，后面的行到 */ 为止都是注释（CLayoutMgr::DoLayout_Range 更新后面各行的状态）
	ASSERT_EQ(Result::Ok, doc->Insert(Position{ 0, 0 }, u"/* "));
	EXPECT_EQ((std::vector<std::string>{ "CCCC", "C", "CCCC.." }), PaintAll(*doc));

	// 撤销后注释也没有了
	ASSERT_EQ(Result::Ok, doc->Undo());
	EXPECT_EQ((std::vector<std::string>{ ".", ".", "......" }), PaintAll(*doc));
}

TEST_F(MacSyntaxColorTest, WrappedLine)
{
	// 折り返し的逻辑行：第 2 个以后的排版行也接着是注释。颜色按逻辑行返回
	auto doc = Open("a.cpp", "int a; /* 0123456789 0123456789 */ int b;\nint c;\n");
	ASSERT_TRUE(doc->SetWrap(WrapMethod::SettingWidth, 10));
	ASSERT_LT(2, doc->LayoutLineCount());
	EXPECT_EQ((std::vector<std::string>{ "111....CCCCCCCCCCCCCCCCCCCCCCCCCCC.111...", "111..." }), PaintAll(*doc));
}

TEST_F(MacSyntaxColorTest, DocumentsOfDifferentTypes)
{
	// 一个进程里交替处理不同类型的文档，也各按自己的设置着色
	auto cpp = Open("a.cpp", "/* a\nb */ // c\n");	// 「*/」后面的空格是普通文字
	auto sql = Open("a.sql", "-- c\n/* a\n");
	auto txt = Open("a.txt", "/* a\n");
	EXPECT_EQ((std::vector<std::string>{ "CCCC", "CCCC.CCCC" }), PaintAll(*cpp));
	EXPECT_EQ((std::vector<std::string>{ "CCCC", "CCCC" }), PaintAll(*sql));
	EXPECT_EQ((std::vector<std::string>{ "...." }), PaintAll(*txt));
	// 编辑别的文档（按那个文档的设置排版）以后也正确
	ASSERT_EQ(Result::Ok, sql->Insert(Position{ 0, 0 }, u"/* "));
	EXPECT_EQ((std::vector<std::string>{ "CCCC", "CCCC.CCCC" }), PaintAll(*cpp));
	EXPECT_EQ((std::vector<std::string>{ "CCCCCCC", "CCCC" }), PaintAll(*sql));
	ASSERT_EQ(Result::Ok, cpp->Insert(Position{ 2, 0 }, u"x"));
	txt.reset();	// 不再使用关掉的文档的设置
	EXPECT_EQ((std::vector<std::string>{ "CCCC", "CCCC.CCCC", "." }), PaintAll(*cpp));
}

TEST_F(MacSyntaxColorTest, SaveAsChangesType)
{
	// 「名前を付けて保存」换了扩展名，类型别设置和着色一起变
	auto doc = Open("a.txt", "// c\n");
	EXPECT_EQ((std::vector<std::string>{ "...." }), PaintAll(*doc));
	ASSERT_EQ(Result::Ok, doc->SaveAs((m_dir / "b.cpp").u16string()));
	EXPECT_EQ((std::vector<std::string>{ "CCCC" }), PaintAll(*doc));
}

TEST_F(MacSyntaxColorTest, ColorSettings)
{
	// 着色的颜色是类型别设置（GetColor）。原版的默认值
	auto doc = Open("a.cpp", "");
	const ColorSetting comment = doc->GetColor(ColorIndex::Comment);
	EXPECT_TRUE(comment.display);
	EXPECT_EQ(0x008000u, comment.text);
	const ColorSetting url = doc->GetColor(ColorIndex::Url);
	EXPECT_TRUE(url.underline);		// URL 有下划线
	EXPECT_EQ(0x0000FFu, url.text);
	EXPECT_EQ(0x0000FFu, doc->GetColor(ColorIndex::Keyword1).text);
	EXPECT_EQ(0xFF8000u, doc->GetColor(ColorIndex::Keyword2).text);
	EXPECT_FALSE(doc->GetColor(ColorIndex::Regex1).display);
	EXPECT_FALSE(doc->GetColor(ColorIndex::Heredoc).display);
	EXPECT_TRUE(doc->GetColor(ColorIndex::PageView).display);
	EXPECT_FALSE(doc->GetColor(static_cast<ColorIndex>(57)).display);	// 超出范围
}

TEST_F(MacSyntaxColorTest, RichTextAndOutOfRange)
{
	// リッチテキスト类型：只有半角数字着色（URL、引号都不着色。字母后面的「1」不是数字）
	auto doc = Open("a.rtf", "{\\rtf1 http://example.com 'a' 123}\n");
	EXPECT_EQ((std::vector<std::string>{ "..............................NNN." }), PaintAll(*doc));
	EXPECT_TRUE(doc->SyntaxColors(5).empty());	// 超出范围的行
	EXPECT_TRUE(doc->SyntaxColors(-1).empty());
}

// ---------------------------------------------------------------------------
// sakura.ini 的类型别设置：正規表現キーワード、ヒアドキュメント
// ---------------------------------------------------------------------------

namespace {

//! 在 sakura.ini 的 [Types(n)] 后面加行（同名的键替换掉）
void EditTypeSection(const fs::path& ini, int type, const std::vector<std::pair<std::string, std::string>>& entries)
{
	std::ifstream in{ ini };
	std::vector<std::string> lines;
	for (std::string l; std::getline(in, l);) {
		if (!l.empty() && l.back() == '\r') l.pop_back();
		lines.push_back(l);
	}
	in.close();
	const std::string header = "[Types(" + std::to_string(type) + ")]";
	std::vector<std::string> out;
	bool inSection = false;
	for (const auto& l : lines) {
		if (!l.empty() && l[0] == '[') {
			inSection = (l == header);
			out.push_back(l);
			if (inSection) {
				for (const auto& [k, v] : entries) out.push_back(k + "=" + v);
			}
			continue;
		}
		if (inSection) {
			const auto eq = l.find('=');
			bool replaced = false;
			for (const auto& [k, v] : entries) replaced |= (eq != std::string::npos && l.substr(0, eq) == k);
			if (replaced) continue;
		}
		out.push_back(l);
	}
	std::ofstream o{ ini, std::ios::binary | std::ios::trunc };
	for (const auto& l : out) o << l << "\r\n";
}

} // namespace

class MacSyntaxColorIniTest : public MacSyntaxColorTest {
protected:
	void SetUp() override
	{
		// 先写出默认的 sakura.ini，改了类型别设置后重新读入
		ASSERT_TRUE(Startup());
		m_ini = fs::path(SettingsFilePath());
		fs::remove(m_ini);
		Shutdown(true);
		ASSERT_TRUE(fs::exists(m_ini));
	}
	void TearDown() override
	{
		MacSyntaxColorTest::TearDown();
		fs::remove(m_ini);	// 其他测试用默认设置
	}
	void Start()
	{
		MacSyntaxColorTest::SetUp();
	}
	fs::path m_ini;
};

TEST_F(MacSyntaxColorIniTest, RegexKeyword)
{
	// 在「基本」（Types(0)）设置正規表現キーワード（原版的 ini 格式「颜色名,/正则/k」）
	EditTypeSection(m_ini, 0, {
		{ "bUseRegexKeyword", "1" },
		{ "RxKey[000]", "RK1,/TODO/k" },
		{ "RxKey[001]", "RK2,/^#.*$/k" },
		{ "C[RK1]", "1,0,ff0000,f0fbff,0" },
		{ "C[RK2]", "1,1,00ff00,f0fbff,0" },
	});
	Start();
	auto doc = Open("noext", "a TODO b TODO\n# head TODO\nc\n");
	EXPECT_EQ(0, doc->GetFileInfo().typeIndex);
	// 正規表現キーワード比其他着色先判断（CColorStrategyPool 的顺序）。行首（^）只匹配行首
	const std::vector<std::string> expected = {
		"..aaaa...aaaa",
		"bbbbbbbbbbb",
		".",
	};
	EXPECT_EQ(expected, PaintAll(*doc));
	const ColorSetting rk2 = doc->GetColor(ColorIndex::Regex2);
	EXPECT_TRUE(rk2.display);
	EXPECT_TRUE(rk2.bold);
	EXPECT_EQ(0x00FF00u, rk2.text);	// ini 里是 BGR（COLORREF）
}

TEST_F(MacSyntaxColorIniTest, Heredoc)
{
	// 在 C/C++ 打开ヒアドキュメント（PHP 格式，默认不显示）
	EditTypeSection(m_ini, 2, { { "C[HDC]", "1,0,400080,f0fbff,0" } });
	Start();
	auto doc = Open("a.cpp", "x = <<<EOT\nabc /* d\nEOT;\ny\n");
	const std::vector<std::string> expected = {
		"....HHHHHH",
		"HHHHHHHH",
		"HHH.",		// 到结束的标识符为止是ヒアドキュメント（不包括「;」）
		".",
	};
	EXPECT_EQ(expected, PaintAll(*doc));
}

TEST_F(MacSyntaxColorIniTest, NoColorWhenAllOff)
{
	// 所有着色都不显示的设置（原版 IsSkipBeforeLayout）全部是普通文字
	EditTypeSection(m_ini, 0, { { "C[CMT]", "0,0,008000,f0fbff,0" }, { "C[URL]", "0,0,ff0000,f0fbff,1" } });
	Start();
	auto doc = Open("noext", "http://example.com 123 \"a\"\n");
	EXPECT_TRUE(doc->SyntaxColors(0).empty());
}
