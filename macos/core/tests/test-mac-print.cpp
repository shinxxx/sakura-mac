/*! @file
	@brief 印刷（计划第 47 步：印刷・印刷プレビュー・印刷ページ設定）の测试

	- 印刷ページ設定：既定値（原版 CPrint::SettingInitialize）、読み書き、ヘッダー・フッターのフォント
	- ダイアログの数値の範囲と直し方（原版 CDlgPrintSetting::DataCheckAndCorrect）、mm と 1/10 mm、フォント幅
	- 用紙の表と向き、印字可能桁数・行数、ヘッダー・フッターの高さ（原版 CPrint）
	- フォントの欄の文字（原版 CDlgPrintSetting::SetFontName、CalcPrintableLineAndColumn）
	- 印刷用の排版とページ（原版 CPrintPreview）：折り返し、ページ数、段組、行番号（改行単位・折り返し単位、区切り）、
	  ヘッダー・フッター（$p $P $f、寄せ、フォント指定）、TAB、カラー印刷の色、文書ごとの印刷ページ設定の番号
	- Windows 官方版との対照：data/print/cases.tsv の条件で sample.txt を印刷した文字の位置が data/print/expected.txt と同じ。
	  expected.txt は CI の print-windows（macos/tools/print/windows-print.ps1）が Windows 官方版 sakura.exe で
	  PDF に印刷して比べる。环境变量 SAKURA_PRINT_UPDATE=1 时不比较，写出 expected.txt。
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
#include <map>
#include <sstream>
#include <string>
#include <tuple>
#include <vector>

using namespace sakura::core;

namespace {

namespace fs = std::filesystem;

Text T(const std::string& s)
{
	Text out;
	for (size_t i = 0; i < s.size();) {
		unsigned char c = static_cast<unsigned char>(s[i]);
		char32_t cp;
		int n;
		if (c < 0x80) { cp = c; n = 1; }
		else if ((c >> 5) == 6) { cp = c & 0x1F; n = 2; }
		else if ((c >> 4) == 14) { cp = c & 0x0F; n = 3; }
		else { cp = c & 0x07; n = 4; }
		for (int k = 1; k < n; ++k) cp = (cp << 6) | (static_cast<unsigned char>(s[i + k]) & 0x3F);
		i += n;
		if (cp >= 0x10000) {
			cp -= 0x10000;
			out += char16_t(0xD800 + (cp >> 10));
			out += char16_t(0xDC00 + (cp & 0x3FF));
		} else {
			out += char16_t(cp);
		}
	}
	return out;
}

std::string U8(const Text& s)
{
	std::string out;
	for (size_t i = 0; i < s.size(); ++i) {
		char32_t cp = s[i];
		if (cp >= 0xD800 && cp < 0xDC00 && i + 1 < s.size()) {
			cp = 0x10000 + ((cp - 0xD800) << 10) + (s[i + 1] - 0xDC00);
			++i;
		}
		if (cp < 0x80) out += char(cp);
		else if (cp < 0x800) { out += char(0xC0 | (cp >> 6)); out += char(0x80 | (cp & 0x3F)); }
		else if (cp < 0x10000) { out += char(0xE0 | (cp >> 12)); out += char(0x80 | ((cp >> 6) & 0x3F)); out += char(0x80 | (cp & 0x3F)); }
		else { out += char(0xF0 | (cp >> 18)); out += char(0x80 | ((cp >> 12) & 0x3F)); out += char(0x80 | ((cp >> 6) & 0x3F)); out += char(0x80 | (cp & 0x3F)); }
	}
	return out;
}

std::string ReadAll(const fs::path& path)
{
	std::ifstream in(path, std::ios::binary);
	std::ostringstream ss;
	ss << in.rdbuf();
	return ss.str();
}

fs::path DataDir()
{
	return fs::path(SAKURA_ROOT_DIR) / "macos" / "core" / "tests" / "data" / "print";
}

//! ページの文字（空白以外）：x（文字の左端）、y（ベースライン）、文字。y、x の順
std::vector<std::tuple<int, int, std::string>> PageChars(const PrintPage& page)
{
	std::vector<std::tuple<int, int, std::string>> items;
	for (const auto& run : page.runs) {
		if (run.tab) continue;	// TAB は下線だけ
		int x = run.x;
		for (size_t i = 0; i < run.text.size(); ++i) {
			Text ch(1, run.text[i]);
			const int dx = i < run.dx.size() ? run.dx[i] : 0;
			int advance = dx;
			if (run.text[i] >= 0xD800 && run.text[i] < 0xDC00 && i + 1 < run.text.size()) {
				// サロゲートペアは一文字
				ch += run.text[i + 1];
				advance += i + 1 < run.dx.size() ? run.dx[i + 1] : 0;
				++i;
			}
			if (ch != u" " && ch != u"\t" && ch != u"　") items.emplace_back(run.baseline, x, U8(ch));
			x += advance;
		}
	}
	std::sort(items.begin(), items.end());
	return items;
}

//! 一つのページの本文の行（ベースラインごとに文字をつなげたもの）
std::vector<std::string> PageLines(const PrintPage& page)
{
	std::map<int, std::vector<std::pair<int, std::string>>> rows;
	for (const auto& [y, x, c] : PageChars(page)) rows[y].emplace_back(x, c);
	std::vector<std::string> out;
	for (auto& [y, cs] : rows) {
		std::sort(cs.begin(), cs.end());
		std::string s;
		for (auto& [x, c] : cs) s += c;
		out.push_back(s);
	}
	return out;
}

class MacPrintTest : public ::testing::Test {
protected:
	void SetUp() override
	{
		ASSERT_TRUE(Startup());
	}
	void TearDown() override
	{
		Shutdown(false);
	}
	//! 文書（無題）に text を入れる
	std::unique_ptr<Document> MakeDoc(const std::string& text)
	{
		auto doc = Document::Create();
		EXPECT_NE(nullptr, doc);
		EXPECT_EQ(Result::Ok, doc->Insert(Position{ 0, 0 }, T(text)));
		return doc;
	}
	//! タイプ別設定の nInts の一つを変える（0 から数えて 7 行番号を改行単位、8 行番号区切り、10 印刷ページ設定）
	void SetTypeInt(int typeIndex, int pos, int value)
	{
		const Text section = u"Types(" + T(std::to_string(typeIndex)) + u")";
		const auto ints = GetCommonSetting(section, u"nInts");
		ASSERT_TRUE(ints.has_value());
		std::vector<std::string> v;
		std::stringstream ss(U8(*ints));
		for (std::string s; std::getline(ss, s, ',');) v.push_back(s);
		ASSERT_LT(pos, int(v.size()));
		v[pos] = std::to_string(value);
		std::string joined;
		for (size_t i = 0; i < v.size(); ++i) joined += (i ? "," : "") + v[i];
		ASSERT_TRUE(SetCommonSetting(section, u"nInts", T(joined)));
	}
	//! ヘッダー・フッターなしの設定
	static PrintSetting Plain()
	{
		PrintSetting s = GetPrintSetting(0);
		for (auto& h : s.header) h.clear();
		for (auto& f : s.footer) f.clear();
		return s;
	}
};

} // namespace

// ----- 印刷ページ設定 -----

TEST_F(MacPrintTest, DefaultSetting)
{
	// 原版 CPrint::SettingInitialize（CShareData::InitShareData で 8 つ）
	const PrintSetting s = GetPrintSetting(0);
	EXPECT_EQ(Text(u"印刷設定 1"), s.name);
	EXPECT_EQ(Text(u"ＭＳ 明朝"), s.fontHan);
	EXPECT_EQ(Text(u"ＭＳ 明朝"), s.fontZen);
	EXPECT_EQ(24, s.fontHeight);
	EXPECT_EQ(12, s.fontWidth);
	EXPECT_EQ(1, s.columns);
	EXPECT_EQ(70, s.columnSpace);
	EXPECT_EQ(30, s.lineSpacing);
	EXPECT_EQ(100, s.marginTop);
	EXPECT_EQ(200, s.marginBottom);
	EXPECT_EQ(200, s.marginLeft);
	EXPECT_EQ(100, s.marginRight);
	EXPECT_EQ(PaperOrientation::Portrait, s.orientation);
	EXPECT_EQ(9, s.paperSize);
	EXPECT_FALSE(s.colorPrint);
	EXPECT_TRUE(s.wordWrap);
	EXPECT_FALSE(s.kinsokuHead || s.kinsokuTail || s.kinsokuRet || s.kinsokuKuto);
	EXPECT_FALSE(s.lineNumber);
	EXPECT_EQ(Text(u"$f"), s.header[0]);
	EXPECT_EQ(Text(), s.header[1]);
	EXPECT_EQ(Text(), s.header[2]);
	EXPECT_EQ(Text(), s.footer[0]);
	EXPECT_EQ(Text(u"- $p -"), s.footer[1]);
	EXPECT_EQ(Text(), s.footer[2]);
	EXPECT_TRUE(s.headerFont.faceName.empty());
	EXPECT_TRUE(s.footerFont.faceName.empty());
	for (int i = 1; i < PrintSettingCount; ++i) {
		EXPECT_EQ(u"印刷設定 " + T(std::to_string(i + 1)), GetPrintSetting(i).name);
		EXPECT_EQ(24, GetPrintSetting(i).fontHeight);
	}
	// 範囲の外は 0 番
	EXPECT_EQ(Text(u"印刷設定 1"), GetPrintSetting(-1).name);
	EXPECT_EQ(Text(u"印刷設定 1"), GetPrintSetting(PrintSettingCount).name);
}

TEST_F(MacPrintTest, SetAndGetSetting)
{
	PrintSetting s = GetPrintSetting(2);
	s.name = u"横向き";
	s.fontHan = u"Courier New";
	s.fontZen = u"ＭＳ ゴシック";
	s.fontHeight = 40;
	s.fontWidth = 20;
	s.columns = 2;
	s.columnSpace = 150;
	s.lineSpacing = 0;
	s.marginTop = 0;
	s.marginBottom = 500;
	s.marginLeft = 10;
	s.marginRight = 20;
	s.orientation = PaperOrientation::Landscape;
	s.paperSize = 13;
	s.colorPrint = true;
	s.wordWrap = false;
	s.kinsokuHead = s.kinsokuTail = s.kinsokuRet = s.kinsokuKuto = true;
	s.lineNumber = true;
	s.header[0] = u"";
	s.header[2] = u"$p/$P";
	s.footer[0] = u"$f";
	s.headerFont = PrintFont{ u"Arial", 120, true, false };
	s.footerFont = PrintFont{ u"ＭＳ 明朝", 95, false, true };
	s.printerName = u"Office Printer";
	SetPrintSetting(2, s);

	const PrintSetting r = GetPrintSetting(2);
	EXPECT_EQ(s.name, r.name);
	EXPECT_EQ(s.fontHan, r.fontHan);
	EXPECT_EQ(s.fontZen, r.fontZen);
	EXPECT_EQ(40, r.fontHeight);
	EXPECT_EQ(20, r.fontWidth);
	EXPECT_EQ(2, r.columns);
	EXPECT_EQ(150, r.columnSpace);
	EXPECT_EQ(0, r.lineSpacing);
	EXPECT_EQ(0, r.marginTop);
	EXPECT_EQ(500, r.marginBottom);
	EXPECT_EQ(10, r.marginLeft);
	EXPECT_EQ(20, r.marginRight);
	EXPECT_EQ(PaperOrientation::Landscape, r.orientation);
	EXPECT_EQ(13, r.paperSize);
	EXPECT_TRUE(r.colorPrint);
	EXPECT_FALSE(r.wordWrap);
	EXPECT_TRUE(r.kinsokuHead && r.kinsokuTail && r.kinsokuRet && r.kinsokuKuto);
	EXPECT_TRUE(r.lineNumber);
	EXPECT_EQ(Text(), r.header[0]);
	EXPECT_EQ(Text(u"$p/$P"), r.header[2]);
	EXPECT_EQ(Text(u"$f"), r.footer[0]);
	EXPECT_EQ(Text(u"Arial"), r.headerFont.faceName);
	EXPECT_EQ(120, r.headerFont.pointSize);
	EXPECT_TRUE(r.headerFont.bold);
	EXPECT_FALSE(r.headerFont.italic);
	EXPECT_EQ(Text(u"ＭＳ 明朝"), r.footerFont.faceName);
	EXPECT_EQ(95, r.footerFont.pointSize);
	EXPECT_FALSE(r.footerFont.bold);
	EXPECT_TRUE(r.footerFont.italic);
	EXPECT_EQ(Text(u"Office Printer"), r.printerName);
	// ほかの設定は変わらない
	EXPECT_EQ(Text(u"印刷設定 2"), GetPrintSetting(1).name);
	EXPECT_EQ(Text(u"印刷設定 4"), GetPrintSetting(3).name);

	// 長すぎる名前・書式は切る（原版の配列の大きさ）
	s.name = Text(40, u'あ');
	s.header[1] = Text(120, u'x');
	SetPrintSetting(2, s);
	EXPECT_EQ(Text(32, u'あ'), GetPrintSetting(2).name);
	EXPECT_EQ(Text(99, u'x'), GetPrintSetting(2).header[1]);

	// フォントの指定をやめる
	s.headerFont = PrintFont{};
	SetPrintSetting(2, s);
	EXPECT_TRUE(GetPrintSetting(2).headerFont.faceName.empty());
}

TEST_F(MacPrintTest, SettingIsSavedInIni)
{
	PrintSetting s = GetPrintSetting(1);
	s.fontHeight = 33;
	s.fontWidth = 17;
	s.header[1] = u"中央";
	s.footerFont = PrintFont{ u"Arial", 100, true, false };
	SetPrintSetting(1, s);
	// 終わるときに sakura.ini の [Print] に書く（原版 ShareData_IO_Print と同じ書き方）
	Shutdown(true);
	const std::string ini = ReadAll(fs::path(SettingsFilePath()));
	EXPECT_NE(std::string::npos, ini.find("PS[01].nInts=17,33,1,70,30,100,200,200,100,1,9,1,0,1,0,0,1,0,0")) << ini.substr(0, 200);
	EXPECT_NE(std::string::npos, ini.find(U8(u"PS[01].szHF[1]=中央")));
	EXPECT_NE(std::string::npos, ini.find("PS[01].lfFooterFaceName=Arial"));
	// 次に起動したときに読む
	ASSERT_TRUE(Startup());
	const PrintSetting r = GetPrintSetting(1);
	EXPECT_EQ(33, r.fontHeight);
	EXPECT_EQ(17, r.fontWidth);
	EXPECT_EQ(Text(u"中央"), r.header[1]);
	EXPECT_EQ(Text(u"Arial"), r.footerFont.faceName);
	EXPECT_EQ(100, r.footerFont.pointSize);
	EXPECT_TRUE(r.footerFont.bold);
	EXPECT_EQ(Text(u"印刷設定 1"), GetPrintSetting(0).name);
}

// ----- ダイアログの数値 -----

TEST_F(MacPrintTest, FieldRanges)
{
	using F = PrintSettingField;
	EXPECT_EQ(std::make_pair(7, 200), PrintSettingRange(F::FontHeight));
	EXPECT_EQ(std::make_pair(0, 150), PrintSettingRange(F::LineSpacing));
	EXPECT_EQ(std::make_pair(1, 4), PrintSettingRange(F::Columns));
	EXPECT_EQ(std::make_pair(0, 30), PrintSettingRange(F::ColumnSpace));
	for (F f : { F::MarginTop, F::MarginBottom, F::MarginLeft, F::MarginRight }) {
		EXPECT_EQ(std::make_pair(0, 50), PrintSettingRange(f));
	}
	// 原版 DataCheckAndCorrect：範囲の外は端に
	EXPECT_EQ(7, CorrectPrintSettingValue(F::FontHeight, 3));
	EXPECT_EQ(7, CorrectPrintSettingValue(F::FontHeight, 7));
	EXPECT_EQ(8, CorrectPrintSettingValue(F::FontHeight, 8));
	EXPECT_EQ(200, CorrectPrintSettingValue(F::FontHeight, 201));
	EXPECT_EQ(4, CorrectPrintSettingValue(F::Columns, 9));
	EXPECT_EQ(1, CorrectPrintSettingValue(F::Columns, 0));
	EXPECT_EQ(0, CorrectPrintSettingValue(F::MarginLeft, -5));
	EXPECT_EQ(50, CorrectPrintSettingValue(F::MarginLeft, 51));

	PrintSetting s;
	SetPrintSettingField(s, F::FontHeight, 31);
	EXPECT_EQ(31, s.fontHeight);
	EXPECT_EQ(16, s.fontWidth);	// (高さ + 1) / 2
	SetPrintSettingField(s, F::FontHeight, 500);
	EXPECT_EQ(200, s.fontHeight);
	EXPECT_EQ(100, s.fontWidth);
	SetPrintSettingField(s, F::ColumnSpace, 12);	// mm → 1/10 mm
	EXPECT_EQ(120, s.columnSpace);
	EXPECT_EQ(12, GetPrintSettingField(s, F::ColumnSpace));
	SetPrintSettingField(s, F::MarginTop, 99);
	EXPECT_EQ(500, s.marginTop);
	SetPrintSettingField(s, F::MarginRight, 3);
	EXPECT_EQ(30, s.marginRight);
	SetPrintSettingField(s, F::LineSpacing, 45);
	EXPECT_EQ(45, s.lineSpacing);
	SetPrintSettingField(s, F::Columns, 3);
	EXPECT_EQ(3, s.columns);
	EXPECT_EQ(3, GetPrintSettingField(s, F::Columns));
	EXPECT_EQ(50, GetPrintSettingField(s, F::MarginTop));
	EXPECT_EQ(200, GetPrintSettingField(s, F::FontHeight));
}

TEST_F(MacPrintTest, FontLabels)
{
	// 原版 CalcPrintableLineAndColumn：1/10 mm → pt（小数 1 桁）
	EXPECT_EQ(Text(u"6.8pt"), PrintFontSizeText(24));
	EXPECT_EQ(Text(u"1.9pt"), PrintFontSizeText(7));	// 7 * 720 / 254 = 19（切り捨て）
	EXPECT_EQ(Text(u"56.6pt"), PrintFontSizeText(200));
	// 原版 SetFontName：「名前(ポイント/mm)」。整数のポイントは小数なし。mm の小数の桁が整数の桁と同じなのも原版のまま
	EXPECT_EQ(Text(u"Arial(12pt/4.4mm)"), PrintFontLabel(PrintFont{ u"Arial", 120 }));
	EXPECT_EQ(Text(u"ＭＳ 明朝(9.5pt/3.3mm)"), PrintFontLabel(PrintFont{ u"ＭＳ 明朝", 95 }));
	EXPECT_EQ(Text(), PrintFontLabel(PrintFont{}));
}

TEST_F(MacPrintTest, MacFontFace)
{
	EXPECT_EQ(Text(u"Hiragino Mincho ProN"), MacFontFace(u"ＭＳ 明朝"));
	EXPECT_EQ(Text(u"Hiragino Sans"), MacFontFace(u"ＭＳ ゴシック"));
	EXPECT_EQ(Text(u"Hiragino Sans"), MacFontFace(u"メイリオ"));
	EXPECT_EQ(Text(u"Menlo"), MacFontFace(u"Terminal"));
	EXPECT_EQ(Text(u"Courier New"), MacFontFace(u"Courier New"));
}

// ----- 用紙、桁数・行数 -----

TEST_F(MacPrintTest, Papers)
{
	const auto papers = PaperList();
	ASSERT_GE(papers.size(), 30u);
	EXPECT_EQ(9, papers[0].id);
	EXPECT_EQ(Text(u"A4 (210 x 297 mm)"), papers[0].name);
	EXPECT_EQ(2100, papers[0].width);
	EXPECT_EQ(2970, papers[0].height);
	EXPECT_EQ(Text(u"A3 (297 x 420 mm)"), papers[1].name);

	auto a4 = GetPaperSize(9, PaperOrientation::Portrait);
	ASSERT_TRUE(a4);
	EXPECT_EQ(2100, a4->width);
	EXPECT_EQ(2970, a4->height);
	auto a4l = GetPaperSize(9, PaperOrientation::Landscape);
	ASSERT_TRUE(a4l);
	EXPECT_EQ(2970, a4l->width);
	EXPECT_EQ(2100, a4l->height);
	auto b5 = GetPaperSize(13, PaperOrientation::Portrait);
	ASSERT_TRUE(b5);
	EXPECT_EQ(1820, b5->width);
	EXPECT_EQ(2570, b5->height);
	EXPECT_FALSE(GetPaperSize(9999, PaperOrientation::Portrait));
}

TEST_F(MacPrintTest, PrintableColumnsAndLines)
{
	PrintSetting s = GetPrintSetting(0);
	// A4 縦、既定：(2100 - 200 - 100) / 12 = 150 桁
	EXPECT_EQ(150, PrintableColumns(s, 2100, 0));
	// 行番号 5 桁：(1800 - 60) / 12 = 145
	EXPECT_EQ(145, PrintableColumns(s, 2100, 5));
	// 2 段：(1800 - 70 - 2 * 60) / 12 / 2 = 67
	s.columns = 2;
	EXPECT_EQ(67, PrintableColumns(s, 2100, 5));
	// 用紙より余白が大きい
	EXPECT_EQ(0, PrintableColumns(s, 250, 0));
	s.columns = 1;

	// ヘッダー・フッター：24 * 130 / 100 = 31
	EXPECT_EQ(31, PrintHeaderHeight(s));
	EXPECT_EQ(31, PrintFooterHeight(s));
	// (2970 - 300 - 62 - 62 + 7) / 31 = 82 行
	EXPECT_EQ(82, PrintableLines(s, 2970));
	s.header[0].clear();
	EXPECT_EQ(0, PrintHeaderHeight(s));
	EXPECT_EQ(84, PrintableLines(s, 2970));
	// フォントの指定があるときはそのポイント数で（12pt：120 * 254 / 720 = 42 → 42 * 130 / 100 = 54）
	s.footerFont = PrintFont{ u"Arial", 120 };
	EXPECT_EQ(54, PrintFooterHeight(s));
	s.footer[1].clear();
	EXPECT_EQ(0, PrintFooterHeight(s));
	EXPECT_EQ(86, PrintableLines(s, 2970));
	EXPECT_EQ(0, PrintableLines(s, 200));
}

// ----- 印刷用の排版とページ -----

TEST_F(MacPrintTest, LayoutAndPages)
{
	std::string text;
	for (int i = 1; i <= 100; ++i) text += "line " + std::to_string(i) + "\n";
	auto doc = MakeDoc(text);
	const auto layout = doc->CreatePrintLayout(GetPrintSetting(0));
	ASSERT_NE(nullptr, layout);
	EXPECT_FALSE(layout->IsEmpty());
	EXPECT_EQ(150, layout->Columns());
	EXPECT_EQ(82, layout->Lines());
	EXPECT_EQ(0, layout->LineNumberColumns());
	EXPECT_EQ(2100, layout->Paper().width);
	EXPECT_EQ(2970, layout->Paper().height);
	// 100 行（最後の改行のあとは行にならない）→ 82 行と 18 行の 2 ページ
	EXPECT_EQ(2, layout->PageCount());

	ExpandParameterView view;
	const PrintPage p1 = layout->GetPage(0, view);
	const auto lines = PageLines(p1);
	// ヘッダー（$f）、本文 82 行、フッター
	ASSERT_EQ(1u + 82u + 1u, lines.size());
	EXPECT_EQ("(無題)", lines.front());
	EXPECT_EQ("line1", lines[1]);
	EXPECT_EQ("line82", lines[82]);
	EXPECT_EQ("-1-", lines.back());

	// 位置：ヘッダーのベースラインは 余白上 + 5 + 文字の高さ、本文は 余白上 + ヘッダーの高さ * 2 + 文字の高さ
	const auto chars = PageChars(p1);
	EXPECT_EQ(std::make_tuple(100 + 5 + 24, 200 + 5, std::string("(")), chars.front());
	bool found = false;
	for (const auto& [y, x, c] : chars) {
		if (y == 100 + 62 + 24 && x == 200 && c == "l") found = true;
	}
	EXPECT_TRUE(found);
	// 2 行目は行送り 31 下
	EXPECT_EQ("line2", PageLines(p1)[2]);
	// フッター：中央寄せ。ベースラインは 用紙 - 余白下 - 5
	const auto& last = chars.back();
	EXPECT_EQ(2970 - 200 - 5, std::get<0>(last));

	const PrintPage p2 = layout->GetPage(1, view);
	const auto lines2 = PageLines(p2);
	ASSERT_EQ(1u + 18u + 1u, lines2.size());
	EXPECT_EQ("line83", lines2[1]);
	EXPECT_EQ("line100", lines2[18]);
	EXPECT_EQ("-2-", lines2.back());

	// 範囲の外は空
	EXPECT_TRUE(layout->GetPage(2, view).runs.empty());
	EXPECT_TRUE(layout->GetPage(-1, view).runs.empty());
}

TEST_F(MacPrintTest, WrapAndDx)
{
	// 1 行 150 桁：全角は 2 桁、半角は 1 桁。dx は半角 12、全角 24
	auto doc = MakeDoc(std::string(160, 'a') + "\n" + "あいう\tb\n");
	const auto layout = doc->CreatePrintLayout(Plain());
	ASSERT_NE(nullptr, layout);
	const PrintPage page = layout->GetPage(0, ExpandParameterView{});
	const auto lines = PageLines(page);
	ASSERT_EQ(3u, lines.size());
	EXPECT_EQ(std::string(150, 'a'), lines[0]);
	EXPECT_EQ(std::string(10, 'a'), lines[1]);
	EXPECT_EQ("あいうb", lines[2]);
	// 3 行目：あいう は全角の幅、TAB は描かない（カラー印刷でないとき）、b は TAB 幅 4 の 8 桁目。
	// 半角と全角のフォントが同じときは全部半角のフォントで描く（原版 WCODE::GetFontNo）
	std::vector<const PrintRun*> runs;
	for (const auto& r : page.runs) {
		if (r.baseline == page.runs.back().baseline) runs.push_back(&r);
	}
	ASSERT_EQ(2u, runs.size());
	EXPECT_FALSE(runs[0]->zen);
	EXPECT_EQ(Text(u"あいう"), runs[0]->text);
	EXPECT_EQ(200, runs[0]->x);
	EXPECT_EQ((std::vector<std::int32_t>{ 24, 24, 24 }), runs[0]->dx);
	EXPECT_FALSE(runs[1]->zen);
	EXPECT_EQ(Text(u"b"), runs[1]->text);
	EXPECT_EQ(200 + 8 * 12, runs[1]->x);
	EXPECT_EQ(0u, runs[0]->color);

	// 全角のフォントが違うとき：0x80 以上の文字は全角のフォント（原版 nKind == 1）
	PrintSetting s = Plain();
	s.fontZen = u"ＭＳ ゴシック";
	const auto layout2 = doc->CreatePrintLayout(s);
	const PrintPage page2 = layout2->GetPage(0, ExpandParameterView{});
	bool zen = false;
	for (const auto& r : page2.runs) {
		if (r.text == u"あいう") zen = r.zen;
		if (r.text == u"b") EXPECT_FALSE(r.zen);
	}
	EXPECT_TRUE(zen);
}

TEST_F(MacPrintTest, LineNumbers)
{
	std::string text;
	for (int i = 1; i <= 12; ++i) text += "x" + std::to_string(i) + "\n";
	text += std::string(200, 'w') + "\n";	// 折り返す
	auto doc = MakeDoc(text);
	PrintSetting s = Plain();
	s.lineNumber = true;
	const auto layout = doc->CreatePrintLayout(s);
	ASSERT_NE(nullptr, layout);
	// 14 行 → 行番号の桁数は 2 桁 + 区切り 1（原版 DetectWidthOfLineNumberArea。基本の nLineNumWidth は 2）
	EXPECT_EQ(3, layout->LineNumberColumns());
	EXPECT_EQ((1800 - 3 * 12) / 12, layout->Columns());
	const PrintPage page = layout->GetPage(0, ExpandParameterView{});
	// 行番号は 本文の左に右寄せ（「1 」の 2 桁 → 本文の 2 桁前から）
	const int base = 200 + 3 * 12;
	const PrintRun* first = nullptr;
	for (const auto& r : page.runs) {
		if (r.text == u"1 ") { first = &r; break; }
	}
	ASSERT_NE(nullptr, first);
	EXPECT_EQ(base - 2 * 12, first->x);
	const auto lines = PageLines(page);
	EXPECT_EQ("1x1", lines[0]);
	EXPECT_EQ("12x12", lines[11]);
	EXPECT_EQ("13" + std::string(147, 'w'), lines[12]);
	// 改行単位：折り返した行は空白
	EXPECT_EQ(std::string(53, 'w'), lines[13]);
	// 最後の改行のあとの空の行は排版の行がない（原版 CLayoutMgr）
	EXPECT_EQ(14u, lines.size());
	// 区切りは縦線（基本の nLineTermType = 1）：本文と行番号の隙間の中央
	ASSERT_EQ(1u, page.rules.size());
	EXPECT_EQ(base - 6, page.rules[0].x);
	EXPECT_EQ(100, page.rules[0].top);
	EXPECT_EQ(100 + 31 * 14, page.rules[0].bottom);

	// 折り返し単位の行番号、区切りは文字「:」
	SetTypeInt(0, 7, 0);
	SetTypeInt(0, 8, 2);
	ASSERT_TRUE(SetCommonSetting(u"Types(0)", u"cLineTermChar", u":"));
	auto doc2 = MakeDoc(text);
	const auto layout2 = doc2->CreatePrintLayout(s);
	ASSERT_NE(nullptr, layout2);
	const PrintPage page2 = layout2->GetPage(0, ExpandParameterView{});
	const auto lines2 = PageLines(page2);
	EXPECT_EQ("1:x1", lines2[0]);
	ASSERT_EQ(14u, lines2.size());
	EXPECT_EQ("14:" + std::string(53, 'w'), lines2[13]);
	EXPECT_TRUE(page2.rules.empty());
}

TEST_F(MacPrintTest, LineNumberWidthGrows)
{
	// 1000 行を超えると 4 桁 + 区切り
	std::string text;
	for (int i = 0; i < 1200; ++i) text += "a\n";
	auto doc = MakeDoc(text);
	PrintSetting s = Plain();
	s.lineNumber = true;
	const auto layout = doc->CreatePrintLayout(s);
	ASSERT_NE(nullptr, layout);
	EXPECT_EQ(5, layout->LineNumberColumns());
	EXPECT_EQ(86, layout->Lines());	// ヘッダー・フッターなし：(2670 + 7) / 31
	EXPECT_EQ((1201 + 85) / 86, layout->PageCount());
	// 100 行未満：2 桁 + 区切り
	auto small = MakeDoc("a\nb\n");
	EXPECT_EQ(3, small->CreatePrintLayout(s)->LineNumberColumns());
	// 行番号なし：0
	s.lineNumber = false;
	EXPECT_EQ(0, doc->CreatePrintLayout(s)->LineNumberColumns());
}

TEST_F(MacPrintTest, Columns)
{
	std::string text;
	for (int i = 1; i <= 30; ++i) text += "r" + std::to_string(i) + "\n";
	auto doc = MakeDoc(text);
	PrintSetting s = Plain();
	s.columns = 2;
	s.fontHeight = 100;
	s.fontWidth = 50;
	s.lineSpacing = 0;
	const auto layout = doc->CreatePrintLayout(s);
	ASSERT_NE(nullptr, layout);
	// (2970 - 300 + 0) / 100 = 26 行、(1800 - 70) / 50 / 2 = 17 桁
	EXPECT_EQ(26, layout->Lines());
	EXPECT_EQ(17, layout->Columns());
	// 31 行 / (26 * 2) → 1 ページ
	EXPECT_EQ(1, layout->PageCount());
	const PrintPage page = layout->GetPage(0, ExpandParameterView{});
	// 2 段目の 1 行目は r27：x は 余白左 + (17 桁 * 50 + 70)
	bool found = false;
	for (const auto& r : page.runs) {
		if (r.text == u"r27") {
			found = true;
			EXPECT_EQ(200 + 17 * 50 + 70, r.x);
			EXPECT_EQ(100 + 100, r.baseline);
		}
	}
	EXPECT_TRUE(found);
}

TEST_F(MacPrintTest, HeaderFooterExpand)
{
	std::string text;
	for (int i = 0; i < 200; ++i) text += "t\n";
	auto doc = MakeDoc(text);
	PrintSetting s = GetPrintSetting(0);
	s.header[0] = u"L$p";
	s.header[1] = u"C";
	s.header[2] = u"$p/$P";
	s.footer[0] = u"\t$P";
	s.footer[1] = u"";
	s.footer[2] = u"R";
	const auto layout = doc->CreatePrintLayout(s);
	ASSERT_NE(nullptr, layout);
	ASSERT_EQ(3, layout->PageCount());
	const PrintPage page = layout->GetPage(1, ExpandParameterView{});
	std::map<Text, const PrintRun*> byText;
	for (const auto& r : page.runs) byText[r.text] = &r;
	// 左寄せ：rect.left = 余白左 + 5
	ASSERT_TRUE(byText.count(u"L2"));
	EXPECT_EQ(205, byText[u"L2"]->x);
	EXPECT_EQ(129, byText[u"L2"]->baseline);
	// 中央寄せ：(left + right - 幅) / 2。right = 2100 - (100 + 5)
	ASSERT_TRUE(byText.count(u"C"));
	EXPECT_EQ((205 + 1995 - 12) / 2, byText[u"C"]->x);
	// 右寄せ
	ASSERT_TRUE(byText.count(u"2/3"));
	EXPECT_EQ(1995 - 36, byText[u"2/3"]->x);
	// フッター：TAB は描かず、その幅（TAB 幅 4）だけ進む
	ASSERT_TRUE(byText.count(u"3"));
	EXPECT_EQ(205 + 4 * 12, byText[u"3"]->x);
	EXPECT_EQ(2970 - 205, byText[u"3"]->baseline);
	ASSERT_TRUE(byText.count(u"R"));
	EXPECT_EQ(1995 - 12, byText[u"R"]->x);
	EXPECT_TRUE(page.alignedTexts.empty());

	// フォントの指定があるとき：界面層が測って寄せる
	s.headerFont = PrintFont{ u"Arial", 120, true };
	const auto layout2 = doc->CreatePrintLayout(s);
	const PrintPage page2 = layout2->GetPage(0, ExpandParameterView{});
	ASSERT_EQ(3u, page2.alignedTexts.size());
	EXPECT_EQ(Text(u"L1"), page2.alignedTexts[0].text);
	EXPECT_EQ(0, page2.alignedTexts[0].align);
	EXPECT_EQ(Text(u"1/3"), page2.alignedTexts[2].text);
	EXPECT_EQ(2, page2.alignedTexts[2].align);
	EXPECT_EQ(205, page2.alignedTexts[2].left);
	EXPECT_EQ(1995, page2.alignedTexts[2].right);
	EXPECT_EQ(105, page2.alignedTexts[2].top);
	EXPECT_FALSE(page2.alignedTexts[2].footer);
	EXPECT_EQ(Text(u"Arial"), page2.alignedTexts[2].font.faceName);
	EXPECT_TRUE(page2.alignedTexts[2].font.bold);
	// ヘッダーの高さは 12pt で：42 * 130 / 100 = 54 → 本文は 100 + 108 + 24
	bool found = false;
	for (const auto& r : page2.runs) {
		if (r.text == u"t" && r.baseline == 100 + 108 + 24) found = true;
	}
	EXPECT_TRUE(found);

	// プレビューの外では $p は「(印刷プレビューでのみ使用できます)」（原版 STR_PREVIEW_ONLY）
	const Text outside = doc->ExpandParameter(u"$p", ExpandParameterView{});
	EXPECT_NE(Text(u"1"), outside);
	EXPECT_FALSE(outside.empty());
}

TEST_F(MacPrintTest, ColorPrint)
{
	auto doc = MakeDoc("abc\tdef\n");
	PrintSetting s = Plain();
	s.colorPrint = true;
	s.lineNumber = true;
	const auto layout = doc->CreatePrintLayout(s);
	ASSERT_NE(nullptr, layout);
	const PrintPage page = layout->GetPage(0, ExpandParameterView{});
	// 基本のテキストの色（黒）。行番号もテキストの色
	for (const auto& r : page.runs) EXPECT_EQ(0u, r.color);
	ASSERT_FALSE(page.runs.empty());

	// テキストの色を変えると本文も行番号もその色
	ASSERT_TRUE(SetCommonSetting(u"Types(0)", u"C[TXT]", u"1,1,1,0,0,0,0,0,0,0,0,123456,ffffff"));
	auto doc2 = MakeDoc("abc\n");
	const auto layout2 = doc2->CreatePrintLayout(s);
	const PrintPage page2 = layout2->GetPage(0, ExpandParameterView{});
	ASSERT_FALSE(page2.runs.empty());
	const auto ini = GetCommonSetting(u"Types(0)", u"C[TXT]");
	ASSERT_TRUE(ini.has_value());
	const std::uint32_t expected = page2.runs[0].color;
	EXPECT_NE(0u, expected) << U8(*ini);
	for (const auto& r : page2.runs) EXPECT_EQ(expected, r.color);
}

TEST_F(MacPrintTest, EmptyArea)
{
	auto doc = MakeDoc("a\n");
	PrintSetting s = Plain();
	s.paperSize = 9;
	s.fontHeight = 200;
	s.fontWidth = 100;
	s.marginLeft = 1100;
	s.marginRight = 1000;
	const auto layout = doc->CreatePrintLayout(s);
	ASSERT_NE(nullptr, layout);
	EXPECT_TRUE(layout->IsEmpty());
	EXPECT_EQ(0, layout->PageCount());
	EXPECT_TRUE(layout->GetPage(0, ExpandParameterView{}).runs.empty());

	// 表にない用紙は A4 縦
	s = Plain();
	s.paperSize = 9999;
	s.orientation = PaperOrientation::Landscape;
	const auto layout2 = doc->CreatePrintLayout(s);
	EXPECT_EQ(2100, layout2->Paper().width);
	EXPECT_EQ(9, layout2->Setting().paperSize);
	EXPECT_EQ(PaperOrientation::Portrait, layout2->Setting().orientation);
}

TEST_F(MacPrintTest, DocumentPrintSettingIndex)
{
	auto doc = MakeDoc("a\n");
	auto other = MakeDoc("b\n");
	EXPECT_EQ(0, doc->PrintSettingIndex());
	// 原版 OnPrintPageSetting：タイプ別設定に書く。同じタイプの文書も
	EXPECT_TRUE(doc->SetPrintSettingIndex(3));
	EXPECT_EQ(3, doc->PrintSettingIndex());
	// タイプ別設定に書いてある（ほかの文書は設定の変更の知らせで読み直す）
	other->ApplyTypeSettingChange(0);
	EXPECT_EQ(3, other->PrintSettingIndex());
	EXPECT_EQ(3, MakeDoc("c\n")->PrintSettingIndex());
	EXPECT_FALSE(doc->SetPrintSettingIndex(3));
	EXPECT_FALSE(doc->SetPrintSettingIndex(8));
	EXPECT_FALSE(doc->SetPrintSettingIndex(-1));
	EXPECT_EQ(3, doc->PrintSettingIndex());
}

// ----- Windows 官方版との対照 -----

TEST_F(MacPrintTest, WindowsComparison)
{
	const fs::path data = DataDir();
	const fs::path work = fs::temp_directory_path() / "sakura-mac-print-test";
	fs::remove_all(work);
	fs::create_directories(work);
	// $f がファイル名になるように Windows と同じ名前で開く
	fs::copy_file(data / "sample.txt", work / "sample.txt");
	auto doc = Document::Create();
	ASSERT_NE(nullptr, doc);
	ASSERT_EQ(Result::Ok, doc->Open((work / "sample.txt").u16string()));

	std::ifstream cases(data / "cases.tsv", std::ios::binary);
	ASSERT_TRUE(cases.good());
	std::string out;
	std::string line;
	int count = 0;
	while (std::getline(cases, line)) {
		if (!line.empty() && line.back() == '\r') line.pop_back();
		if (line.empty() || line[0] == '#') continue;
		const auto tab = line.find('\t');
		const std::string name = line.substr(0, tab);
		PrintSetting s = GetPrintSetting(0);
		// CI の Windows には ＭＳ 明朝 がないので ＭＳ ゴシック（半角は高さの半分、全角はその倍。测试の文字幅と同じ）
		s.fontHan = s.fontZen = u"ＭＳ ゴシック";
		if (tab != std::string::npos) {
			std::stringstream ss(line.substr(tab + 1));
			for (std::string kv; std::getline(ss, kv, ';');) {
				if (kv.empty()) continue;
				const auto eq = kv.find('=');
				const std::string k = kv.substr(0, eq);
				const std::string v = kv.substr(eq + 1);
				const int n = std::atoi(v.c_str());
				if (k == "height") { s.fontHeight = n; s.fontWidth = (n + 1) / 2; }
				else if (k == "spacing") s.lineSpacing = n;
				else if (k == "columns") s.columns = n;
				else if (k == "colspace") s.columnSpace = n;
				else if (k == "mt") s.marginTop = n;
				else if (k == "mb") s.marginBottom = n;
				else if (k == "ml") s.marginLeft = n;
				else if (k == "mr") s.marginRight = n;
				else if (k == "paper") s.paperSize = static_cast<std::int16_t>(n);
				else if (k == "orient") s.orientation = static_cast<PaperOrientation>(n);
				else if (k == "wrap") s.wordWrap = n != 0;
				else if (k == "linenum") s.lineNumber = n != 0;
				else if (k == "kh") s.kinsokuHead = n != 0;
				else if (k == "kt") s.kinsokuTail = n != 0;
				else if (k == "kr") s.kinsokuRet = n != 0;
				else if (k == "kk") s.kinsokuKuto = n != 0;
				else if (k.size() == 2 && k[0] == 'h') s.header[k[1] - '0'] = T(v);
				else if (k.size() == 2 && k[0] == 'f') s.footer[k[1] - '0'] = T(v);
				else ADD_FAILURE() << "unknown key " << k;
			}
		}
		const auto layout = doc->CreatePrintLayout(s);
		ASSERT_NE(nullptr, layout);
		out += "== " + name + " ==\n";
		out += "pages " + std::to_string(layout->PageCount()) + "\n";
		for (int p = 0; p < layout->PageCount(); ++p) {
			out += "-- " + std::to_string(p + 1) + " --\n";
			for (const auto& [y, x, c] : PageChars(layout->GetPage(p, ExpandParameterView{}))) {
				out += std::to_string(x) + " " + std::to_string(y) + " " + c + "\n";
			}
		}
		++count;
	}
	EXPECT_EQ(4, count);
	doc.reset();
	fs::remove_all(work);

	const fs::path expected = data / "expected.txt";
	if (const char* u = std::getenv("SAKURA_PRINT_UPDATE"); u && std::string(u) == "1") {
		std::ofstream(expected, std::ios::binary) << out;
		return;
	}
	EXPECT_EQ(ReadAll(expected), out);
}
