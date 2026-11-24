/*! @file
	@brief アウトライン解析（计划第 42 步）的测试

	data/outline/ 的样本文件用各解析方法解析，结果（窗口标题、ツリー或リスト、「コピー」的文字）
	与 data/outline/expected/ 的文件相同。expected 的文件和 Windows 官方版（CI 的 outline-windows：
	sakura.exe 打开同样的文件执行アウトライン解析，读出对话框的ツリー・リスト和「コピー」的文字）比较，
	两边都相同，就确认了 Mac 版的解析结果与 Windows 版一致。

	样本文件的类型与 CI 的 Windows 版相同：内置的类型（拡張子），加上追加的类型
	（WZ階層付テキスト、XML、Erlang、ルールファイル 2 个、ツリー的「順序」3 个、リスト的排序 1 个）。

	环境变量 SAKURA_OUTLINE_UPDATE=1 时不比较，写出 expected 的文件（更新时用）。
*/
/*
	Copyright (C) 2026, Sakura Editor Organization

	SPDX-License-Identifier: Zlib
*/
#include "pch.h"

#include "sakura_core/SakuraCore.h"

#include "util/file.h"

#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <string>

using namespace sakura::core;

namespace {

namespace fs = std::filesystem;

fs::path DataDir()
{
	return fs::path(SAKURA_ROOT_DIR) / "macos" / "core" / "tests" / "data" / "outline";
}

Text ToText(const std::string& s)
{
	// UTF-8 → UTF-16
	Text r;
	for (size_t i = 0; i < s.size();) {
		const unsigned char c = static_cast<unsigned char>(s[i]);
		char32_t cp;
		int n;
		if (c < 0x80) { cp = c; n = 1; }
		else if ((c >> 5) == 0x6) { cp = c & 0x1F; n = 2; }
		else if ((c >> 4) == 0xE) { cp = c & 0x0F; n = 3; }
		else { cp = c & 0x07; n = 4; }
		for (int k = 1; k < n && i + k < s.size(); ++k) cp = (cp << 6) | (static_cast<unsigned char>(s[i + k]) & 0x3F);
		i += n;
		if (cp >= 0x10000) {
			cp -= 0x10000;
			r += char16_t(0xD800 + (cp >> 10));
			r += char16_t(0xDC00 + (cp & 0x3FF));
		} else {
			r += char16_t(cp);
		}
	}
	return r;
}

std::string ToUtf8(const Text& t)
{
	std::string r;
	for (size_t i = 0; i < t.size(); ++i) {
		char32_t cp = t[i];
		if (0xD800 <= cp && cp < 0xDC00 && i + 1 < t.size()) {
			cp = 0x10000 + ((cp - 0xD800) << 10) + (t[++i] - 0xDC00);
		}
		if (cp < 0x80) {
			r += char(cp);
		} else if (cp < 0x800) {
			r += char(0xC0 | (cp >> 6));
			r += char(0x80 | (cp & 0x3F));
		} else if (cp < 0x10000) {
			r += char(0xE0 | (cp >> 12));
			r += char(0x80 | ((cp >> 6) & 0x3F));
			r += char(0x80 | (cp & 0x3F));
		} else {
			r += char(0xF0 | (cp >> 18));
			r += char(0x80 | ((cp >> 12) & 0x3F));
			r += char(0x80 | ((cp >> 6) & 0x3F));
			r += char(0x80 | (cp & 0x3F));
		}
	}
	return r;
}

Text Num(int value)
{
	const auto s = std::to_string(value);
	return Text(s.begin(), s.end());
}

void ReplaceAll(Text& s, const Text& from, const Text& to)
{
	if (from.empty()) return;
	for (size_t pos = 0; (pos = s.find(from, pos)) != Text::npos; pos += to.size()) {
		s.replace(pos, from.size(), to);
	}
}

/*!
	解析结果的文字（与 CI 的 Windows 版读出的格式相同）：
	  title: 窗口标题
	  [tree]：一个项目一行。缩进是层次×2，「- 」展开着、「+ 」折叠着（有孩子时）、「  」没有孩子；
	          选着的项目（光标在文件开头时的 GetFuncInfoIndex）后面是「 <」
	  [list]：先是列名一行，再是一行一个项目（行、桁、関数名、第 4 列，TAB 分隔），选着的行后面是「 <」
	  [clip]：「コピー」的文字（换行是 LF，文件的路径换成 <FILE>）
	打开窗口时光标在开头：选着的项目的上层展开（原版 SetItemSelection 的 TreeView_SelectItem）
*/
Text Dump(OutlineResult result, const Text& path)
{
	const int selected = OutlineItemAt(result, 1, 1);
	Text out = u"title: " + result.title + u"\n";
	if (result.isTree) {
		// 选着的项目的上层展开
		const auto nodePath = OutlineNodePath(result, selected);
		std::vector<OutlineNode>* level = &result.tree;
		for (size_t i = 0; i + 1 < nodePath.size(); ++i) {
			OutlineNode& node = (*level)[nodePath[i]];
			node.expanded = true;
			level = &node.children;
		}
		out += u"[tree]\n";
		struct Walker {
			Text& out;
			int selected;
			void Walk(const std::vector<OutlineNode>& nodes, int depth)
			{
				for (const auto& node : nodes) {
					out += Text(size_t(depth) * 2, u' ');
					out += node.children.empty() ? u"  " : (node.expanded ? u"- " : u"+ ");
					out += node.label;
					if (0 <= selected && node.item == selected) out += u" <";
					out += u"\n";
					Walk(node.children, depth + 1);
				}
			}
		} walker{ out, selected };
		walker.Walk(result.tree, 0);
	} else {
		out += u"[list]\n";
		out += result.columnTitles[0] + u"\t" + result.columnTitles[1] + u"\t" + result.columnTitles[2] + u"\t" + result.columnTitles[3] + u"\n";
		for (const auto& row : result.rows) {
			out += Num(row.line) + u"\t" + Num(row.column) + u"\t" + row.name + u"\t" + row.remark;
			if (row.item == selected) out += u" <";
			out += u"\n";
		}
	}
	Text clip = result.clipText;
	ReplaceAll(clip, u"\r\n", u"\n");
	ReplaceAll(clip, path, u"<FILE>");
	out += u"[clip]\n" + clip;
	return out;
}

class MacOutlineTest : public ::testing::Test {
protected:
	void SetUp() override
	{
		RemoveIniFolder();
		ASSERT_TRUE(Startup());
		// CI 的 Windows 版与同样的类型（macos/tools/outline/windows-outline.ps1）
		AddType(u"WZ", { { u"szTypeExts", u"wzt" }, { u"nDefaultOutline", u"9" } });
		AddType(u"XML", { { u"szTypeExts", u"xml" }, { u"nDefaultOutline", u"15" } });
		AddType(u"Erlang", { { u"szTypeExts", u"erl" }, { u"nDefaultOutline", u"14" } });
		AddType(u"Rule1", { { u"szTypeExts", u"rtx" }, { u"nDefaultOutline", u"12" },
							{ u"szOutlineRuleFilename", Path("sample.rul") } });
		AddType(u"Rule2", { { u"szTypeExts", u"rgx" }, { u"nDefaultOutline", u"12" },
							{ u"szOutlineRuleFilename", Path("sample.rux") } });
		AddType(u"CppAtoZ", { { u"szTypeExts", u"cps" }, { u"nDefaultOutline", u"16" }, { u"nOutlineSortType", u"2" } });
		AddType(u"JavaDesc", { { u"szTypeExts", u"jvd" }, { u"nDefaultOutline", u"4" }, { u"nOutlineSortType", u"1" } });
		AddType(u"TextZtoA", { { u"szTypeExts", u"txz" }, { u"nDefaultOutline", u"3" }, { u"nOutlineSortType", u"3" } });
		AddType(u"PerlNameDesc", { { u"szTypeExts", u"plx" }, { u"nDefaultOutline", u"7" },
								   { u"nOutlineSortCol", u"2" }, { u"bOutlineSortDesc", u"1" } });
	}
	void TearDown() override
	{
		Shutdown(false);
		RemoveIniFolder();
	}
	static void RemoveIniFolder()
	{
		std::error_code ec;
		fs::remove_all(GetIniFileName().parent_path(), ec);
	}
	static Text Path(const char* name)
	{
		return ToText((DataDir() / name).string());
	}
	static void AddType(const Text& name, std::vector<std::pair<Text, Text>> values)
	{
		const int index = AddTypeSetting();
		ASSERT_LE(0, index);
		values.emplace_back(u"szTypeName", name);
		ASSERT_TRUE(SetCommonSettings(u"Types(" + Num(index) + u")", values));
	}
	static std::unique_ptr<Document> Open(const char* name)
	{
		auto doc = Document::Create();
		EXPECT_EQ(Result::Ok, doc->Open(Path(name)));
		return doc;
	}
	//! 解析结果与 expected 的文件相同
	static void Check(const char* name)
	{
		SCOPED_TRACE(name);
		auto doc = Open(name);
		const Text dump = Dump(doc->AnalyzeOutline(), Path(name));
		const fs::path expected = DataDir() / "expected" / (std::string(name) + ".txt");
		const std::string actual = ToUtf8(dump);
		if (const char* update = std::getenv("SAKURA_OUTLINE_UPDATE"); update && *update == '1') {
			fs::create_directories(expected.parent_path());
			std::ofstream(expected, std::ios::binary) << actual;
			return;
		}
		std::ifstream in(expected, std::ios::binary);
		ASSERT_TRUE(in.good()) << expected;
		const std::string text((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
		EXPECT_EQ(text, actual);
	}
};

// ----- 各解析方法（与 Windows 版相同） -----

TEST_F(MacOutlineTest, Cpp) { Check("sample.cpp"); }
TEST_F(MacOutlineTest, C) { Check("sample.c"); }
TEST_F(MacOutlineTest, CCppHeader) { Check("sample.h"); }
TEST_F(MacOutlineTest, Java) { Check("Sample.java"); }
TEST_F(MacOutlineTest, PlSql) { Check("sample.sql"); }
TEST_F(MacOutlineTest, Cobol) { Check("sample.cbl"); }
TEST_F(MacOutlineTest, Asm) { Check("sample.asm"); }
TEST_F(MacOutlineTest, Perl) { Check("sample.pl"); }
TEST_F(MacOutlineTest, VisualBasic) { Check("sample.bas"); }
TEST_F(MacOutlineTest, Python) { Check("sample.py"); }
TEST_F(MacOutlineTest, Html) { Check("sample.html"); }
TEST_F(MacOutlineTest, Tex) { Check("sample.tex"); }
TEST_F(MacOutlineTest, Text) { Check("sample.txt"); }
TEST_F(MacOutlineTest, WzText) { Check("sample.wzt"); }
TEST_F(MacOutlineTest, Xml) { Check("sample.xml"); }
TEST_F(MacOutlineTest, Erlang) { Check("sample.erl"); }
TEST_F(MacOutlineTest, RuleFile) { Check("rule.rtx"); }
TEST_F(MacOutlineTest, RuleFileRegexReplace) { Check("regex.rgx"); }
TEST_F(MacOutlineTest, TreeSortAtoZ) { Check("sorted.cps"); }
TEST_F(MacOutlineTest, TreeSortDefaultDesc) { Check("desc.jvd"); }
TEST_F(MacOutlineTest, TreeSortZtoA) { Check("ztoa.txz"); }
TEST_F(MacOutlineTest, ListSortNameDesc) { Check("namedesc.plx"); }

// ----- 解析方法的指定、类型、结果的项目 -----

TEST_F(MacOutlineTest, ResultFields)
{
	auto doc = Open("sample.c");
	const auto result = doc->AnalyzeOutline();
	EXPECT_EQ(OutlineType::C, result.type);		// C/C++ の .c は C
	EXPECT_EQ(OutlineType::C, result.listType);
	EXPECT_FALSE(result.isTree);
	EXPECT_EQ(Path("sample.c"), result.filePath);
	ASSERT_FALSE(result.items.empty());
	// 項目：add の宣言（6 行目）
	const auto& first = result.items.front();
	EXPECT_EQ(u"add", first.name);
	EXPECT_EQ(6, first.line);
	EXPECT_EQ(1, first.column);
	EXPECT_EQ(6, first.layoutLine);
	EXPECT_EQ(1, first.layoutColumn);

	// 解析方法を指定（タイプ別設定と違う方法）
	const auto text = doc->AnalyzeOutline(OutlineType::Text);
	EXPECT_EQ(OutlineType::Text, text.type);
	EXPECT_TRUE(text.isTree);
	EXPECT_EQ(u"テキスト トピックツリー", text.title);

	// .cpp は C++
	auto cpp = Open("sample.cpp");
	EXPECT_EQ(OutlineType::Cpp, cpp->AnalyzeOutline().type);
	// 解析方法の決定（Command_FUNCLIST の最初）：タイプ別設定、C/C++ は拡張子、指定したものはそのまま
	EXPECT_EQ(OutlineType::Cpp, cpp->ResolveOutlineType(OutlineType::Default));
	EXPECT_EQ(OutlineType::C, doc->ResolveOutlineType(OutlineType::Default));
	EXPECT_EQ(OutlineType::CCpp, Open("sample.h")->ResolveOutlineType(OutlineType::Default));
	EXPECT_EQ(OutlineType::Python, Open("sample.py")->ResolveOutlineType(OutlineType::Default));
	EXPECT_EQ(OutlineType::Html, cpp->ResolveOutlineType(OutlineType::Html));
	EXPECT_EQ(OutlineType::CCpp, cpp->ResolveOutlineType(OutlineType::CCpp));	// 指定したときは解析で決まる
	EXPECT_EQ(OutlineType::Cpp, cpp->AnalyzeOutline(OutlineType::CCpp).type);
	// 新規文書（ファイル名なし）：C/C++ の自動判定は C/C++ のまま
	auto untitled = Document::Create();
	ASSERT_EQ(Result::Ok, untitled->Insert({ 0, 0 }, u"int f()\r\n{\r\n}\r\n"));
	const auto u = untitled->AnalyzeOutline(OutlineType::CCpp);
	EXPECT_EQ(OutlineType::CCpp, u.type);
	EXPECT_TRUE(u.filePath.empty());
}

TEST_F(MacOutlineTest, RuleFileMissing)
{
	// ルールファイルが読めない：項目なし（原版 MakeFuncList_RuleFile）
	int index = -1;
	for (const auto& t : TypeSettings()) {
		if (t.name == u"Rule1") index = t.index;
	}
	ASSERT_LE(0, index);
	ASSERT_TRUE(SetCommonSetting(u"Types(" + Num(index) + u")", u"szOutlineRuleFilename", u"/nonexistent/rule.txt"));
	auto doc = Document::Create();
	ASSERT_EQ(Result::Ok, doc->Open(Path("rule.rtx")));
	const auto result = doc->AnalyzeOutline(OutlineType::RuleFile);
	EXPECT_TRUE(result.items.empty());
	EXPECT_EQ(u"ルールファイル", result.title);
}

// ----- 並べ替え（窓口里改「順序」、点列名） -----

TEST_F(MacOutlineTest, SortTree)
{
	auto doc = Open("sample.txt");
	auto result = doc->AnalyzeOutline();
	ASSERT_EQ(OutlineSort::Default, result.sort);
	ASSERT_LE(3u, result.tree.size());
	const Text first = result.tree.front().label;
	SortOutlineTree(result, OutlineSort::DefaultDesc);
	EXPECT_EQ(OutlineSort::DefaultDesc, result.sort);
	EXPECT_EQ(first, result.tree.back().label);
	for (size_t i = 1; i < result.tree.size(); ++i) {
		EXPECT_GT(result.tree[i - 1].order, result.tree[i].order);
	}
	SortOutlineTree(result, OutlineSort::Default);
	EXPECT_EQ(first, result.tree.front().label);

	// アルファベット順：大文字小文字を区別しない、同じ名前は登録順
	OutlineResult r;
	r.tree = { { u"beta", 0, 0 }, { u"Alpha", 1, 1 }, { u"alpha", 2, 2 }, { u"_under", 3, 3 }, { u"Gamma", 4, 4 } };
	SortOutlineTree(r, OutlineSort::AtoZ);
	std::vector<Text> labels;
	for (const auto& n : r.tree) labels.push_back(n.label);
	EXPECT_EQ((std::vector<Text>{ u"_under", u"Alpha", u"alpha", u"beta", u"Gamma" }), labels);
	SortOutlineTree(r, OutlineSort::ZtoA);
	labels.clear();
	for (const auto& n : r.tree) labels.push_back(n.label);
	EXPECT_EQ((std::vector<Text>{ u"Gamma", u"beta", u"alpha", u"Alpha", u"_under" }), labels);
}

TEST_F(MacOutlineTest, SortRows)
{
	auto doc = Open("sample.bas");
	auto result = doc->AnalyzeOutline();
	ASSERT_FALSE(result.isTree);
	EXPECT_EQ(0, result.sortColumn);
	EXPECT_EQ(u"行 *", result.columnTitles[0]);
	EXPECT_EQ(u"桁", result.columnTitles[1]);
	EXPECT_EQ(u"関数名", result.columnTitles[2]);
	EXPECT_EQ(u"", result.columnTitles[3]);
	// 関数名
	SortOutlineRows(result, 2, false);
	EXPECT_EQ(u"関数名 *", result.columnTitles[2]);
	EXPECT_EQ(u"行", result.columnTitles[0]);
	for (size_t i = 1; i < result.rows.size(); ++i) {
		EXPECT_LE(wmemicmp(result.rows[i - 1].name.c_str(), result.rows[i].name.c_str()), 0);
	}
	// 第 4 列の降順：備考（m_nInfo）の大きい順、同じなら前の順（安定）
	SortOutlineRows(result, 3, true);
	EXPECT_EQ(u"*", result.columnTitles[3]);
	EXPECT_TRUE(result.sortDescending);
	for (size_t i = 1; i < result.rows.size(); ++i) {
		EXPECT_GE(result.items[result.rows[i - 1].item].info, result.items[result.rows[i].item].info);
	}
	// 行
	SortOutlineRows(result, 0, false);
	for (size_t i = 1; i < result.rows.size(); ++i) {
		EXPECT_LT(result.rows[i - 1].line, result.rows[i].line);
	}
}

// ----- カーソル位置の項目 -----

TEST_F(MacOutlineTest, ItemAtCaret)
{
	auto doc = Open("sample.py");
	const auto result = doc->AnalyzeOutline();
	ASSERT_LE(4u, result.items.size());
	// 先頭：最初の項目
	EXPECT_EQ(0, OutlineItemAt(result, 1, 1));
	// 各項目の位置とその後ろ：その項目
	for (int i = 0; i < int(result.items.size()); ++i) {
		const auto& item = result.items[i];
		EXPECT_EQ(i, OutlineItemAt(result, item.layoutLine, item.layoutColumn)) << i;
		EXPECT_EQ(i, OutlineItemAt(result, item.layoutLine, item.layoutColumn + 100)) << i;
	}
	// 末尾：最後の項目
	EXPECT_EQ(int(result.items.size()) - 1, OutlineItemAt(result, 100000, 1));
	// 項目なし
	EXPECT_EQ(-1, OutlineItemAt(OutlineResult{}, 1, 1));
	// ツリーの位置
	const auto path = OutlineNodePath(result, 1);
	ASSERT_FALSE(path.empty());
	const OutlineNode* node = &result.tree[path[0]];
	for (size_t i = 1; i < path.size(); ++i) node = &node->children[path[i]];
	EXPECT_EQ(1, node->item);
	EXPECT_TRUE(OutlineNodePath(result, -1).empty());
}

// ----- 関数リストマーク（次の関数リストマークへ／前の関数リストマークへ） -----

TEST_F(MacOutlineTest, FuncListMark)
{
	auto doc = Open("sample.py");
	// 解析前はマークなし
	for (int i = 0; i < doc->LineCount(); ++i) {
		EXPECT_FALSE(doc->HasFuncListMark(i));
	}
	EXPECT_EQ(-1, doc->FindFuncListMark(0, true, true));
	const auto result = doc->AnalyzeOutline();
	std::vector<int> marks;
	for (const auto& item : result.items) {
		if (marks.empty() || marks.back() != item.line - 1) marks.push_back(item.line - 1);
	}
	for (int i = 0; i < doc->LineCount(); ++i) {
		EXPECT_EQ(std::find(marks.begin(), marks.end(), i) != marks.end(), doc->HasFuncListMark(i)) << i;
	}
	bool wrapped = true;
	// 次：先頭から
	EXPECT_EQ(marks[0], doc->FindFuncListMark(0, true, true, &wrapped));
	EXPECT_FALSE(wrapped);
	EXPECT_EQ(marks[1], doc->FindFuncListMark(marks[0], true, true, &wrapped));
	// 最後の次：先頭へ戻る（先頭（末尾）から再検索する）
	EXPECT_EQ(marks[0], doc->FindFuncListMark(marks.back(), true, true, &wrapped));
	EXPECT_TRUE(wrapped);
	EXPECT_EQ(-1, doc->FindFuncListMark(marks.back(), true, false, &wrapped));
	EXPECT_FALSE(wrapped);
	// 前
	EXPECT_EQ(marks[0], doc->FindFuncListMark(marks[1], false, true, &wrapped));
	EXPECT_FALSE(wrapped);
	EXPECT_EQ(marks.back(), doc->FindFuncListMark(marks[0], false, true, &wrapped));
	EXPECT_TRUE(wrapped);
	EXPECT_EQ(-1, doc->FindFuncListMark(marks[0], false, false));

	// 行を挿入するとマークも一緒に動く（マークは行に付いている）
	ASSERT_EQ(Result::Ok, doc->Insert({ 0, 0 }, u"# added\r\n"));
	EXPECT_FALSE(doc->HasFuncListMark(marks[0]) && marks[0] + 1 != marks[1]);
	EXPECT_TRUE(doc->HasFuncListMark(marks[0] + 1));

	// 再解析：前のマークは消えてから付け直す。ブックマークの一覧はマークを変えない
	const auto again = doc->AnalyzeOutline(OutlineType::Bookmark);
	EXPECT_EQ(OutlineType::Bookmark, again.type);
	EXPECT_TRUE(doc->HasFuncListMark(marks[0] + 1));
	doc->AnalyzeOutline(OutlineType::Html);	// 何も見つからない
	for (int i = 0; i < doc->LineCount(); ++i) {
		EXPECT_FALSE(doc->HasFuncListMark(i)) << i;
	}
}

} // namespace
