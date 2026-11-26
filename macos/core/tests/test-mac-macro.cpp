/*! @file
	@brief マクロ（计划第 45 步）の核心库の部分の测试

	- 関数表（原版 CSMacroMgr の表、GetFuncInfoByName・GetFuncInfoByID・CanFuncIsKeyMacro、CIfObj の大文字小文字を区別しない検索）
	- キーマクロ（.mac）の読み込み（原版 CKeyMacroMgr::LoadKeyMacro）とエラー、保存の形式（SaveKeyMacro、CMacro::Save）、往復
	- マクロのファイルの文字コード（BOM 付き UTF-8、Shift_JIS、Mac 版の BOM なし UTF-8）
	- マクロの種類（拡張子）
	- JScript の前処理（括弧なしの参照に「()」を足す）
	- CompareVersion、ExpandParameter、Cookie
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
#include <string>

using namespace sakura::core;

namespace {

constexpr std::int32_t F_WCHAR = 30200;
constexpr std::int32_t F_DOWN = 30312;
constexpr std::int32_t F_GOLINETOP = 30332;
constexpr std::int32_t F_INSTEXT_W = 30606;
constexpr std::int32_t F_SEARCH_NEXT = 30902;
constexpr std::int32_t F_FILEOPEN2 = 32812;
constexpr std::int32_t F_GETFILENAME = 40001;
constexpr std::int32_t F_CHGTABWIDTH = 40006;
constexpr std::int32_t F_GETSELCOLUMNFROM = 40009;

class MacMacroTest : public ::testing::Test {
protected:
	void SetUp() override
	{
		ASSERT_TRUE(Startup());
		m_dir = std::filesystem::temp_directory_path() / "sakura-mac-macro-test";
		std::filesystem::remove_all(m_dir);
		std::filesystem::create_directories(m_dir);
	}
	void TearDown() override
	{
		std::filesystem::remove_all(m_dir);
		Shutdown(false);
	}
	Text WriteFile(const std::string& name, const std::string& bytes)
	{
		const auto path = m_dir / name;
		std::ofstream(path, std::ios::binary) << bytes;
		const auto s = path.u8string();
		return ToText(std::string(s.begin(), s.end()));
	}
	static Text ToText(const std::string& utf8)
	{
		Text r;
		for (size_t i = 0; i < utf8.size();) {
			unsigned char c = utf8[i];
			char32_t cp;
			int n;
			if (c < 0x80) { cp = c; n = 0; }
			else if ((c & 0xE0) == 0xC0) { cp = c & 0x1F; n = 1; }
			else if ((c & 0xF0) == 0xE0) { cp = c & 0x0F; n = 2; }
			else { cp = c & 0x07; n = 3; }
			for (int k = 1; k <= n; ++k) cp = (cp << 6) | (utf8[i + k] & 0x3F);
			i += n + 1;
			if (cp >= 0x10000) { cp -= 0x10000; r.push_back(char16_t(0xD800 + (cp >> 10))); r.push_back(char16_t(0xDC00 + (cp & 0x3FF))); }
			else r.push_back(char16_t(cp));
		}
		return r;
	}
	std::filesystem::path m_dir;
};

// ----- 関数表 -----

TEST_F(MacMacroTest, FunctionTable)
{
	const auto& table = MacroFunctions();
	ASSERT_GT(table.size(), 380u);
	// 命令が先、関数が後
	EXPECT_FALSE(table.front().isFunction);
	EXPECT_TRUE(table.back().isFunction);

	const auto* ins = FindMacroFunction(u"InsText");
	ASSERT_NE(nullptr, ins);
	EXPECT_EQ(F_INSTEXT_W, ins->code);
	EXPECT_FALSE(ins->isFunction);
	ASSERT_EQ(1u, ins->args.size());
	EXPECT_EQ(MacroValueType::String, ins->args[0]);
	// 「S_」付きでも同じ（原版 GetFuncInfoByName）
	EXPECT_EQ(ins, FindMacroFunction(u"S_InsText"));
	// 大文字小文字は区別する（キーマクロ）
	EXPECT_EQ(nullptr, FindMacroFunction(u"instext"));
	// JScript の Editor オブジェクトは区別しない（CIfObj::GetIDsOfNames）
	EXPECT_EQ(ins, FindMacroFunctionIgnoreCase(u"insTEXT"));

	// FileOpen は FileOpen2 の機能番号（引数 4 つ）
	const auto* open = FindMacroFunction(u"FileOpen");
	ASSERT_NE(nullptr, open);
	EXPECT_EQ(F_FILEOPEN2, open->code);
	EXPECT_EQ(4u, open->args.size());

	// 関数：戻り値の型
	const auto* name = FindMacroFunction(u"GetFilename");
	ASSERT_NE(nullptr, name);
	EXPECT_TRUE(name->isFunction);
	EXPECT_EQ(MacroValueType::String, name->result);
	EXPECT_TRUE(name->args.empty());
	const auto* tab = FindMacroFunction(u"ChangeTabWidth");
	ASSERT_NE(nullptr, tab);
	EXPECT_EQ(F_CHGTABWIDTH, tab->code);
	EXPECT_TRUE(tab->isFunction);
	EXPECT_EQ(MacroValueType::Int, tab->result);
	// 別名（GetSelectColmFrom と GetSelectColumnFrom）は同じ機能番号。番号からは表の最初の名前
	EXPECT_EQ(F_GETSELCOLUMNFROM, FindMacroFunction(u"GetSelectColumnFrom")->code);
	EXPECT_EQ(Text(u"GetSelectColmFrom"), MacroFunctionByCode(F_GETSELCOLUMNFROM)->name);
	EXPECT_EQ(Text(u"GetFilename"), MacroFunctionByCode(F_GETFILENAME)->name);

	EXPECT_EQ(nullptr, FindMacroFunction(u"NoSuchFunction"));
	EXPECT_EQ(nullptr, MacroFunctionByCode(0));
	EXPECT_EQ(Text(u"テキストを貼り付け"), MacroFunctionDisplayName(F_INSTEXT_W));
}

TEST_F(MacMacroTest, CanRecordInKeyMacro)
{
	EXPECT_TRUE(CanRecordInKeyMacro(F_WCHAR));
	EXPECT_TRUE(CanRecordInKeyMacro(F_DOWN));
	EXPECT_TRUE(CanRecordInKeyMacro(F_INSTEXT_W));
	EXPECT_TRUE(CanRecordInKeyMacro(F_SEARCH_NEXT));
	EXPECT_FALSE(CanRecordInKeyMacro(30102));	// F_FILEOPEN
	EXPECT_FALSE(CanRecordInKeyMacro(31250));	// F_RECKEYMACRO
	EXPECT_FALSE(CanRecordInKeyMacro(F_GETFILENAME));
}

// ----- キーマクロの読み込み -----

TEST_F(MacMacroTest, ParseKeyMacro)
{
	const auto r = ParseKeyMacro(
		u"//キーボードマクロのファイル\r\n"
		u"  \t\r\n"
		u"S_InsText('a\\'b\\\\c\\r\\n\\t\\u3042\\u0000z');\t// テキストを貼り付け\r\n"
		u"Down();\n"
		u"GoLineTop(-9);\r"
		u"SearchNext(\"x\\\"y\", 16);\r\n"
		u"Char(97)");
	ASSERT_EQ(MacroLoadResult::Success, r.result) << std::string(r.errorMessage.begin(), r.errorMessage.end());
	ASSERT_EQ(5u, r.calls.size());
	EXPECT_EQ(F_INSTEXT_W, r.calls[0].code);
	ASSERT_EQ(1u, r.calls[0].args.size());
	EXPECT_TRUE(r.calls[0].args[0].isString);
	EXPECT_EQ(Text(u"a'b\\c\r\n\tあ") + Text(1, u'\0') + u"z", r.calls[0].args[0].text);
	EXPECT_EQ(F_DOWN, r.calls[1].code);
	EXPECT_TRUE(r.calls[1].args.empty());
	EXPECT_EQ(F_GOLINETOP, r.calls[2].code);
	ASSERT_EQ(1u, r.calls[2].args.size());
	EXPECT_FALSE(r.calls[2].args[0].isString);
	EXPECT_EQ(-9, r.calls[2].args[0].IntValue());
	EXPECT_EQ(F_SEARCH_NEXT, r.calls[3].code);
	ASSERT_EQ(2u, r.calls[3].args.size());
	EXPECT_EQ(Text(u"x\"y"), r.calls[3].args[0].text);
	EXPECT_EQ(16, r.calls[3].args[1].IntValue());
	EXPECT_EQ(F_WCHAR, r.calls[4].code);
	EXPECT_EQ(97, r.calls[4].args[0].IntValue());
}

TEST_F(MacMacroTest, ParseKeyMacroErrors)
{
	auto msg = [](const KeyMacroParseResult& r) { return std::u16string(r.errorMessage); };
	{
		const auto r = ParseKeyMacro(u"Down();\r\nNoSuch(1);\r\nUp();");
		EXPECT_EQ(MacroLoadResult::Failure, r.result);
		EXPECT_EQ(Text(u"Macro読み込みエラー"), r.errorTitle);
		EXPECT_EQ(Text(u"Line 2: NoSuchは存在しない関数です．\n"), msg(r));
		EXPECT_EQ(1u, r.calls.size());	// エラーの前までは読めている
	}
	{
		const auto r = ParseKeyMacro(u"InsText('abc);");
		EXPECT_EQ(MacroLoadResult::Failure, r.result);
		EXPECT_EQ(Text(u"Line 1:\n関数InsTextの1番目の引数の終わりに'がありません．"), msg(r));
	}
	{
		const auto r = ParseKeyMacro(u"InsText(12);");
		EXPECT_EQ(MacroLoadResult::Failure, r.result);
		EXPECT_EQ(Text(u"Line 1: Column 9\n関数InsTextの1番目の引数に数値は置けません．"), msg(r));
	}
	{
		const auto r = ParseKeyMacro(u"GoLineTop('x');");
		EXPECT_EQ(MacroLoadResult::Failure, r.result);
		EXPECT_EQ(Text(u"Line 1: Column 11\n関数GoLineTopの1番目の引数に文字列は置けません．"), msg(r));
	}
	{
		const auto r = ParseKeyMacro(u"Down(x);");
		EXPECT_EQ(MacroLoadResult::Failure, r.result);
		EXPECT_EQ(Text(u"Line 1: Column 6: Syntax Error\n"), msg(r));
	}
}

// ----- キーマクロの保存 -----

TEST_F(MacMacroTest, FormatKeyMacro)
{
	std::vector<MacroCall> calls;
	calls.push_back(MacroCall{ F_INSTEXT_W, { MacroArg::String(Text(u"a'b\\c\r\n\t\u0001\u007f ") + Text(1, u'\0')) } });
	calls.push_back(MacroCall{ F_DOWN, {} });
	calls.push_back(MacroCall{ F_SEARCH_NEXT, { MacroArg::String(u"key"), MacroArg::Int(16) } });
	calls.push_back(MacroCall{ F_GOLINETOP, { MacroArg::Int(-1) } });
	const Text text = FormatKeyMacro(calls);
	EXPECT_EQ(Text(
		u"//キーボードマクロのファイル\r\n"
		u"InsText('a\\'b\\\\c\\r\\n\\t\\u0001\\u007f\\u2028\\u0000');\t// テキストを貼り付け\r\n"
		u"Down();\t// カーソル下移動\r\n"
		u"SearchNext('key', 16);\t// 次を検索\r\n"
		u"GoLineTop(-1);\t// 行頭に移動(折り返し単位)\r\n"), text);

	// 往復
	const auto r = ParseKeyMacro(text);
	ASSERT_EQ(MacroLoadResult::Success, r.result);
	ASSERT_EQ(calls.size(), r.calls.size());
	for (size_t i = 0; i < calls.size(); ++i) {
		EXPECT_EQ(calls[i].code, r.calls[i].code);
		ASSERT_EQ(calls[i].args.size(), r.calls[i].args.size());
		for (size_t k = 0; k < calls[i].args.size(); ++k) {
			EXPECT_EQ(calls[i].args[k].isString, r.calls[i].args[k].isString);
			EXPECT_EQ(calls[i].args[k].text, r.calls[i].args[k].text);
		}
	}
}

TEST_F(MacMacroTest, KeyMacroFiles)
{
	// 原版のサンプル（tools/macro/CopyDirPath/CopyDirPath.mac：BOM 付き UTF-8、コメントと CopyDirPath();）
	const auto sample = LoadKeyMacroFile(ToText(std::string(SAKURA_ROOT_DIR) + "/tools/macro/CopyDirPath/CopyDirPath.mac"));
	ASSERT_EQ(MacroLoadResult::Success, sample.result);
	ASSERT_EQ(1u, sample.calls.size());
	EXPECT_EQ(FindMacroFunction(u"CopyDirPath")->code, sample.calls[0].code);

	// 保存して読む（BOM 付き UTF-8）
	const Text path = WriteFile("saved.mac", "");
	std::vector<MacroCall> calls{ MacroCall{ F_INSTEXT_W, { MacroArg::String(u"あいう") } } };
	ASSERT_TRUE(SaveKeyMacroFile(path, calls));
	{
		std::ifstream in(m_dir / "saved.mac", std::ios::binary);
		std::string bytes((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
		EXPECT_EQ(std::string("\xEF\xBB\xBF//"), bytes.substr(0, 5));
	}
	const auto back = LoadKeyMacroFile(path);
	ASSERT_EQ(MacroLoadResult::Success, back.result);
	ASSERT_EQ(1u, back.calls.size());
	EXPECT_EQ(Text(u"あいう"), back.calls[0].args[0].text);

	// Shift_JIS（BOM なし）
	const auto sjis = LoadKeyMacroFile(WriteFile("sjis.mac", "InsText('\x82\xA0');\r\n"));
	ASSERT_EQ(MacroLoadResult::Success, sjis.result);
	EXPECT_EQ(Text(u"あ"), sjis.calls[0].args[0].text);
	// Mac 版：BOM なしの UTF-8
	const auto utf8 = LoadKeyMacroFile(WriteFile("utf8.mac", "InsText('\xE3\x81\x82');\n"));
	ASSERT_EQ(MacroLoadResult::Success, utf8.result);
	EXPECT_EQ(Text(u"あ"), utf8.calls[0].args[0].text);

	// ない
	EXPECT_EQ(MacroLoadResult::Failure, LoadKeyMacroFile(ToText((m_dir / "none.mac").string())).result);
}

TEST_F(MacMacroTest, MacroSourceFile)
{
	const auto r = LoadMacroSourceFile(WriteFile("a.js", "\xEF\xBB\xBFInsText('\xE3\x81\x82');\nDown();"));
	ASSERT_EQ(MacroLoadResult::Success, r.result);
	EXPECT_EQ(Text(u"InsText('あ');\r\nDown();\r\n"), r.source);
	const auto s = LoadMacroSourceFile(WriteFile("s.js", "// \x82\xA0\r\n"));
	ASSERT_EQ(MacroLoadResult::Success, s.result);
	EXPECT_EQ(Text(u"// あ\r\n\r\n"), s.source);
	EXPECT_EQ(MacroLoadResult::Failure, LoadMacroSourceFile(ToText((m_dir / "none.js").string())).result);
}

TEST_F(MacMacroTest, MacroKind)
{
	EXPECT_EQ(MacroKind::Key, MacroKindOfPath(u"/a/b/RecKey.mac"));
	EXPECT_EQ(MacroKind::Key, MacroKindOfPath(u"/a/b/RecKey.MAC"));
	EXPECT_EQ(MacroKind::JScript, MacroKindOfPath(u"/a/b.c/x.js"));
	EXPECT_EQ(MacroKind::Unsupported, MacroKindOfPath(u"/a/x.vbs"));
	EXPECT_EQ(MacroKind::Unsupported, MacroKindOfPath(u"/a/x.ppa"));
	EXPECT_EQ(MacroKind::Unsupported, MacroKindOfPath(u"/a/x.py"));
	EXPECT_EQ(MacroKind::Unknown, MacroKindOfPath(u"/a/x.txt"));
	EXPECT_EQ(MacroKind::Unknown, MacroKindOfPath(u"/a.d/x"));
	EXPECT_EQ(MacroKind::JScript, MacroKindOfExtension(u"JS"));
}

// ----- JScript の前処理 -----

TEST_F(MacMacroTest, PrepareJScriptMacro)
{
	// 原版のヘルプのサンプル（SampleGetSelectxxx、SampleIsPossibleUndo、SampleGetCharCode）
	EXPECT_EQ(Text(u"SelectWord();\nvar iLen = GetSelectColmTo() - GetSelectColmFrom();"),
		PrepareJScriptMacro(u"SelectWord;\nvar iLen = GetSelectColmTo - GetSelectColmFrom;"));
	EXPECT_EQ(Text(u"while (IsPossibleUndo()) {\n    Undo();\n}"),
		PrepareJScriptMacro(u"while (IsPossibleUndo) {\n    Undo;\n}"));
	EXPECT_EQ(Text(u"switch (GetCharCode()) {"), PrepareJScriptMacro(u"switch (GetCharCode) {"));
	EXPECT_EQ(Text(u"x = '名前は\"' + GetFilename() + '\"です';"), PrepareJScriptMacro(u"x = '名前は\"' + GetFilename + '\"です';"));
	// 呼び出しはそのまま
	EXPECT_EQ(Text(u"GetLineStr(1); GetLineCount (0); Editor.InsText('a');"),
		PrepareJScriptMacro(u"GetLineStr(1); GetLineCount (0); Editor.InsText('a');"));
	// Editor. の後ろは足す、ほかのオブジェクトの後ろは足さない
	EXPECT_EQ(Text(u"Editor.GetFilename(); obj.GetFilename; Editor . Undo();"),
		PrepareJScriptMacro(u"Editor.GetFilename; obj.GetFilename; Editor . Undo;"));
	// 文字列、コメント、正規表現の中は変えない
	EXPECT_EQ(Text(u"'Undo' + \"Redo\" // Undo\n/* Redo */ s.match(/Undo/g); a / Undo() / 2"),
		PrepareJScriptMacro(u"'Undo' + \"Redo\" // Undo\n/* Redo */ s.match(/Undo/g); a / Undo / 2"));
	// スクリプトで宣言した名前（原版でもスクリプトの名前が先）
	EXPECT_EQ(Text(u"var Left = 1, Right = 2; function Up(Down) { return Down + Left; }\ntry {} catch (Copy) { Copy; }\nPaste();"),
		PrepareJScriptMacro(u"var Left = 1, Right = 2; function Up(Down) { return Down + Left; }\ntry {} catch (Copy) { Copy; }\nPaste;"));
	// 代入の左辺は変えない、比較は変える
	EXPECT_EQ(Text(u"if (GetCharCode() == 4) x = 1;"), PrepareJScriptMacro(u"if (GetCharCode == 4) x = 1;"));
	// 大文字小文字が違う名前は変えない（JavaScript の名前は区別する）
	EXPECT_EQ(Text(u"getfilename;"), PrepareJScriptMacro(u"getfilename;"));
	// 正規表現と割り算の区別
	EXPECT_EQ(Text(u"var r = GetLineCount(0) / 2 / GetViewLines();\nif (/x/.test(GetLineStr(1))) Down();"),
		PrepareJScriptMacro(u"var r = GetLineCount(0) / 2 / GetViewLines;\nif (/x/.test(GetLineStr(1))) Down;"));
}

TEST_F(MacMacroTest, CompareVersion)
{
	EXPECT_GT(CompareVersionString(u"2.4.2", u"2.4.1"), 0);
	EXPECT_EQ(0, CompareVersionString(u"2.4.2.0", u"2.4.2"));
	EXPECT_LT(CompareVersionString(u"2.3", u"2.4.0.1"), 0);
}

// ----- ExpandParameter、Cookie -----

TEST_F(MacMacroTest, ExpandParameter)
{
	auto doc = Document::Create();
	ASSERT_NE(nullptr, doc);
	ExpandParameterView v;
	v.selectedText = u"sel";
	v.caret = Position{ 4, 2 };
	v.date = u"2026/11/26";
	v.time = u"10:00:00";
	v.version = u"2.4.2.0";
	v.macroPath = u"/m/a.js";
	v.untitledNumber = 3;
	// 無題
	EXPECT_EQ(Text(u"(無題)|(無題)|(無題)|3|sel|3:5|2026/11/26 10:00:00|(保存されていません)|$|$q|2.4.2.0|/m/a.js"),
		doc->ExpandParameter(u"$F|$f|$g|$n|$C|$x:$y|$d $t|$D|$$|$q|$V|$M", v));
	EXPECT_EQ(Text(u"新規 更新なし 記録なし 編集可"), doc->ExpandParameter(u"${N?新規$:既存$} ${U?更新$:更新なし$} ${M?記録中$:記録なし$} ${R?ビュー$:上書き禁止$:編集可$}", v));
	v.readOnly = true;
	v.recordingKeyMacro = true;
	EXPECT_EQ(Text(u"上書き禁止 記録中"), doc->ExpandParameter(u"${R?ビュー$:上書き禁止$:編集可$} ${M?記録中$:記録なし$}", v));
	// 入れ子
	EXPECT_EQ(Text(u"AxzC"), doc->ExpandParameter(u"A${N?x${U?y$:z$}$:w$}C", v));

	// ファイルを開いたとき
	const auto dir = std::filesystem::temp_directory_path() / "sakura-mac-macro-expand";
	std::filesystem::create_directories(dir);
	const auto file = dir / "sample.test.txt";
	std::ofstream(file) << "abc\n";
	const auto s = file.string();
	const Text path(s.begin(), s.end());
	ASSERT_EQ(Result::Ok, doc->Open(path));
	const auto ds = dir.string();
	const Text folder = Text(ds.begin(), ds.end()) + u"/";
	EXPECT_EQ(path + u"|sample.test.txt|sample.test|txt|" + folder + u"|" + path, doc->ExpandParameter(u"$F|$f|$g|$b|$e|$/", v));
	EXPECT_EQ(Text(u"既存"), doc->ExpandParameter(u"${N?新規$:既存$}", v));
	v.appName = u"サクラエディタ";
	EXPECT_EQ(Text(u"サクラエディタ"), doc->ExpandParameter(u"$A", v));
	std::filesystem::remove_all(dir);
}

TEST_F(MacMacroTest, Cookie)
{
	auto doc = Document::Create();
	ASSERT_NE(nullptr, doc);
	EXPECT_EQ(0, doc->SetCookie(u"document", u"a", u"1"));
	EXPECT_EQ(0, doc->SetCookie(u"document", u"b_2", u"2"));
	EXPECT_EQ(0, doc->SetCookie(u"window", u"w", u"x"));
	EXPECT_EQ(1, doc->SetCookie(u"global", u"a", u"1"));
	EXPECT_EQ(2, doc->SetCookie(u"document", u"a-b", u"1"));
	EXPECT_EQ(Text(u"1"), doc->GetCookie(u"document", u"a"));
	EXPECT_EQ(Text(u""), doc->GetCookie(u"document", u"none"));
	EXPECT_EQ(Text(u"def"), doc->GetCookieDefault(u"document", u"none", u"def"));
	EXPECT_EQ(Text(u"a,b_2"), doc->GetCookieNames(u"document"));
	EXPECT_EQ(0, doc->DeleteCookie(u"document", u"a"));
	EXPECT_EQ(5, doc->DeleteCookie(u"document", u"a"));
	// 閉じて(無題)で document の Cookie は消える、window は残る（原版 CEditDoc::InitDoc）
	doc->CloseToUntitled();
	EXPECT_EQ(Text(u""), doc->GetCookieNames(u"document"));
	EXPECT_EQ(Text(u"x"), doc->GetCookie(u"window", u"w"));
}

} // namespace
