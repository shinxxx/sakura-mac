// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib
//
// 第 45 步：Windows 版サクラエディタ（官方发布的 sakura.exe）と Mac 版で同じ JScript マクロを実行して結果を比べる。
// 無題の空の文書で実行する。各節の結果を R に集め、最後に文書を R の行（改行は Enter）に置き換える。
// Mac：App 単元テスト JSMacroTests.testWindowsCompare が実行して、文書を WindowsCompare.txt と比べる。
// Windows：CI の macro-windows が macos/tools/macro/windows-macro.ps1 で sakura.exe -M= で実行し、文書を同じファイルと比べる。
// JScript（ES3）で書く：let・const・アロー関数・テンプレート文字列は使わない。
// メッセージボックスが出る機能（見つからないときの通知 0x08 など）は使わない（CI が止まる）。
var R = [];

function lineText(n) {
	return Editor.GetLineStr(n).replace(/[\r\n]+$/, "");
}
function caret() {
	return Editor.ExpandParameter("$y") + ":" + Editor.ExpandParameter("$x");
}
function clear() {
	Editor.SelectAll();
	Editor.Delete();
}
//! 文書の全体（行を | でつなぐ）
function docText() {
	var n = Editor.GetLineCount(0);
	var a = [];
	for (var i = 1; i <= n; i++) a.push(lineText(i));
	return a.join("|");
}
function put(name, value) {
	R.push(name + "=" + value);
}

// ----- InsText・Char(13)・GetLineCount・GetLineStr -----
clear();
Editor.InsText("abc def\tghi");
Editor.Char(13);
Editor.InsText("2行目 あいう");
Editor.Char(13);
Editor.InsText("three");
put("linecount", Editor.GetLineCount(0));
put("line1", lineText(1));
put("line2", lineText(2));
put("line3", lineText(3));
put("line4", "[" + Editor.GetLineStr(4) + "]");
put("caret.end", caret());

// ----- カーソル移動 -----
Editor.GoFileTop();
put("caret.top", caret());
Editor.Right();
Editor.Right();
put("caret.right2", caret());
Editor.GoLineEnd();
put("caret.lineend", caret());
Editor.Down();
put("caret.down", caret());
Editor.GoLineTop();
put("caret.linetop", caret());
Editor.GoFileEnd();
put("caret.fileend", caret());
Editor.MoveCursor(2, 3, 0);
put("movecursor", caret());
Editor.Jump(3, 1);
put("jump", caret());

// ----- 選択 -----
Editor.MoveCursor(1, 6, 0);
Editor.SelectWord();
put("selectword", Editor.GetSelectedString(0));
put("selected", Editor.IsTextSelected());
put("select.range", Editor.GetSelectLineFrom() + "," + Editor.GetSelectColmFrom() + "-" + Editor.GetSelectLineTo() + "," + Editor.GetSelectColmTo());
Editor.MoveCursor(2, 1, 0);
put("selected.after", Editor.IsTextSelected());
Editor.SelectLine();
put("selectline", "[" + Editor.GetSelectedString(0).replace(/\r\n|\r|\n/g, "<EOL>") + "]");
Editor.Left();
put("left.after.selectline", caret());

// ----- 削除 -----
clear();
Editor.InsText("abcdef");
Editor.GoLineTop();
Editor.Delete();
Editor.GoLineEnd();
Editor.DeleteBack();
put("delete", docText());

// ----- 検索 -----
clear();
Editor.InsText("foo Foo FOO bar foobar");
Editor.GoFileTop();
Editor.SearchNext("bar", 0);
put("search.bar", caret() + " [" + Editor.GetSelectedString(0) + "]");
Editor.SearchNext("bar", 0);
put("search.bar2", caret() + " [" + Editor.GetSelectedString(0) + "]");
Editor.GoFileTop();
Editor.SearchNext("bar", 1);
put("search.word", caret() + " [" + Editor.GetSelectedString(0) + "]");
Editor.GoFileTop();
Editor.SearchNext("FOO", 2);
put("search.case", caret() + " [" + Editor.GetSelectedString(0) + "]");
Editor.GoFileEnd();
Editor.SearchPrev("f.o", 4);
put("search.prev.regex", caret() + " [" + Editor.GetSelectedString(0) + "]");

// ----- 置換 -----
var replaceCases = [
	["foo", "X", 0],
	["foo", "X", 2],
	["foo", "X", 1],
	["f(o+)", "[$1]", 4],
	["^", ">", 4],
	["o", "0", 0]
];
for (var i = 0; i < replaceCases.length; i++) {
	var c = replaceCases[i];
	clear();
	Editor.InsText("foo Foo FOO bar foobar");
	Editor.Char(13);
	Editor.InsText("foo2");
	Editor.GoFileTop();
	Editor.ReplaceAll(c[0], c[1], c[2]);
	put("replaceall." + i, docText());
}
clear();
Editor.InsText("foo foo foo");
Editor.GoFileTop();
Editor.Replace("foo", "bar", 0);
put("replace.one", docText());

// ----- 大文字小文字を区別しない名前・括弧の省略・Editor なし -----
clear();
Editor.InsText("hello world");
//! 原版で例外になるかもしれないもの（例外のときは名前を書く）
function tryPut(name, f) {
	try {
		put(name, f());
	} catch (e) {
		put(name, "error");
	}
}
tryPut("lowercase.method", function () { return Editor.getlinecount(0); });
tryPut("lowercase.object", function () { return typeof editor; });
tryPut("global", function () { return GetLineCount(0); });
tryPut("global.lowercase", function () { return getlinecount(0); });
Editor.GoFileTop();
SelectWord;
put("parenless", IsTextSelected + " " + GetSelectedString(0));

// ----- ExpandParameter -----
put("expand.dollar", Editor.ExpandParameter("$$"));
put("expand.cond", Editor.ExpandParameter("${w?Grep$:通常$}"));
put("expand.filename", "[" + Editor.ExpandParameter("$f") + "]");
put("getfilename", "[" + Editor.GetFilename() + "]");

// ----- Cookie -----
put("cookie.set", Editor.SetCookie("window", "k1", "v1"));
put("cookie.get", Editor.GetCookie("window", "k1"));
put("cookie.default", Editor.GetCookieDefault("window", "none", "dflt"));
put("cookie.set2", Editor.SetCookie("document", "k2", "v2"));
put("cookie.names", Editor.GetCookieNames("document"));
put("cookie.delete", Editor.DeleteCookie("window", "k1"));
put("cookie.delete2", Editor.DeleteCookie("window", "k1"));
put("cookie.badscope", Editor.SetCookie("app", "k", "v"));
put("cookie.badname", Editor.SetCookie("window", "1x", "v"));

// ----- 行・桁の換算、バージョン -----
clear();
Editor.InsText("a\tbあc");
put("index2column", Editor.LineIndexToColumn(1, 3) + "," + Editor.LineIndexToColumn(1, 5));
put("column2index", Editor.LineColumnToIndex(1, 5) + "," + Editor.LineColumnToIndex(1, 9));
put("linenum", Editor.LayoutToLogicLineNum(1) + "," + Editor.LogicToLayoutLineNum(1, 1));
put("compareversion", Editor.CompareVersion("2.4.1", "2.4.10") + "," + Editor.CompareVersion("2.4.1.0", "2.4.1") + "," + Editor.CompareVersion("2.3", "2.4"));

// ----- 結果を文書に書く -----
clear();
for (var j = 0; j < R.length; j++) {
	Editor.InsText(R[j]);
	Editor.Char(13);
}
