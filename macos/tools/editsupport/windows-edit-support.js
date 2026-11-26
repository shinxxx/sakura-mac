// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib
//
// Windows 版サクラエディタ（官方发布的 sakura.exe）的编辑辅助功能的结果（计划第 44 步）。
// CI 的 edit-support-windows 用 sakura.exe -M=这个宏 运行，结果写到 @OUT@\<名字>.txt（UTF-8），
// 与 Mac 版核心库测试（test-mac-edit-support.cpp）比较的 macos/core/tests/data/editsupport/expected 相同。
// @DATA@（样本的文件夹）、@OUT@（结果的文件夹）由 CI 换成实际的值。最后写 @OUT@\done.txt。
var fso = new ActiveXObject("Scripting.FileSystemObject");

function writeResult(name, lines) {
	var s = new ActiveXObject("ADODB.Stream");
	s.Type = 2;
	s.Charset = "utf-8";
	s.Open();
	s.WriteText(lines.join("\n") + "\n");
	// BOM を除いて保存
	s.Position = 0;
	s.Type = 1;
	s.Position = 3;
	var bin = new ActiveXObject("ADODB.Stream");
	bin.Type = 1;
	bin.Open();
	s.CopyTo(bin);
	bin.SaveToFile("@OUT@\\" + name + ".txt", 2);
	bin.Close();
	s.Close();
}

function caret() {
	return Editor.ExpandParameter("$y") + ":" + Editor.ExpandParameter("$x");
}

function lineText(n) {
	// 改行を除く
	return Editor.GetLineStr(n).replace(/[\r\n]+$/, "");
}

var sections = [];

// ----- 対括弧の検索（F_BRACKETPAIR）：各行の各位置から BracketPair したあとのカーソル -----
sections.push(function () {
	var out = [];
	Editor.FileOpen("@DATA@\\brackets.txt");
	var n = Editor.GetLineCount(0);
	for (var y = 1; y <= n; y++) {
		var text = lineText(y);
		for (var x = 1; x <= text.length + 1; x++) {
			var c = text.charCodeAt(x - 1);
			if (c >= 0xDC00 && c <= 0xDFFF) continue;	// サロゲートの後半には置かない
			Editor.MoveCursor(y, x, 0);
			Editor.BracketPair();
			out.push(y + ":" + x + " -> " + caret());
		}
	}
	writeResult("bracket", out);
	Editor.FileClose();
});

// ----- ブックマーク：設定・解除（選択範囲）、次・前（先頭から再検索する・しない）、全解除、パターンに一致する行をマーク -----
sections.push(function () {
	var out = [];
	Editor.FileOpen("@DATA@\\bookmarks.txt");
	var n = Editor.GetLineCount(0);
	function marks(title) {
		var s = [];
		for (var y = 1; y <= n; y++) {
			if (Editor.GetLineAttribute(y, 2)) s.push(y);
		}
		out.push(title + ": " + s.join(","));
	}
	// 見つからないときのメッセージを出さない（0x08 を付けない）、先頭（末尾）から再検索する（0x20）
	function setSearchAll(on) {
		Editor.SearchNext("\u0001\u0002notfound", (on ? 0x20 : 0) | 0x800);
	}
	function walk(title) {
		var s = [];
		for (var y = 1; y <= n; y++) {
			Editor.MoveCursor(y, 2, 0);
			Editor.BookmarkNext();
			var next = caret();
			Editor.MoveCursor(y, 2, 0);
			Editor.BookmarkPrev();
			s.push(y + ">" + next + "<" + caret());
		}
		out.push(title + ": " + s.join(" "));
	}
	Editor.MoveCursor(2, 1, 0); Editor.BookmarkSet();
	Editor.MoveCursor(5, 1, 0); Editor.BookmarkSet();
	marks("set 2,5");
	Editor.MoveCursor(3, 1, 0); Editor.MoveCursor(5, 1, 1); Editor.BookmarkSet();
	marks("toggle 3-5");
	Editor.MoveCursor(8, 3, 0); Editor.MoveCursor(9, 1, 1); Editor.BookmarkSet();
	marks("toggle 8-9");
	Editor.MoveCursor(1, 1, 0); Editor.BookmarkSet(); Editor.BookmarkSet();
	marks("toggle 1 twice");
	setSearchAll(true);
	walk("next/prev searchAll");
	setSearchAll(false);
	walk("next/prev");
	Editor.BookmarkReset();
	marks("reset");
	Editor.MoveCursor(1, 1, 0);
	setSearchAll(false);
	walk("no marks");
	Editor.BookmarkPattern("ab", 0x800);
	marks("pattern ab");
	Editor.BookmarkPattern("ab", 0x02 | 0x800);
	marks("pattern ab case");
	Editor.BookmarkReset();
	Editor.BookmarkPattern("ab", 0x01 | 0x800);
	marks("pattern ab word");
	Editor.BookmarkReset();
	Editor.BookmarkPattern("^\\s*$", 0x04 | 0x800);
	marks("pattern regex blank");
	Editor.BookmarkPattern("AB", 0x02 | 0x800);
	marks("pattern AB case added");
	writeResult("bookmark", out);
	Editor.FileClose();
});

for (var i = 0; i < sections.length; i++) {
	try {
		sections[i]();
	} catch (e) {
		writeResult("error" + i, ["error: " + e.message]);
	}
}
writeResult("done", ["done"]);
