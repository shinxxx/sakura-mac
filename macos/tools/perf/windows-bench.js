// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib
//
// Windows 版サクラエディタの性能测试用的宏（计划第 36 步）。
// 与 Mac 版的 macos/core/tests/test-mac-perf.cpp 相同的文件（make_perf_files.py）、相同的操作量时间，
// 每一步写一行到结果文件（名字<TAB>毫秒）。CI 的 perf-windows 用 sakura.exe -M=这个宏 运行。
// @FILE@（打开的文件）、@OUT@（结果文件）、@KIND@（large / long）由 CI 换成实际的值。
var fso = new ActiveXObject("Scripting.FileSystemObject");
var kind = "@KIND@";

function write(line) {
	var f = fso.OpenTextFile("@OUT@", 8, true);	// 8 = 追加
	f.WriteLine(line);
	f.Close();
}

function measure(name, func) {
	var start = new Date().getTime();
	var note = "";
	try {
		var r = func();
		if (r !== undefined) note = "\t" + r;
	} catch (e) {
		note = "\terror: " + e.message;
	}
	write(kind + ": " + name + "\t" + (new Date().getTime() - start) + note);
}

measure("open", function () {
	Editor.FileOpen("@FILE@");
	return "lines=" + Editor.GetLineCount(0);
});

if (kind == "large") {
	measure("find at the end", function () {
		Editor.GoFileTop();
		Editor.SearchNext("needle", 0);
		return "selected=" + Editor.GetSelectedString(0);
	});
	measure("find backward from the end", function () {
		Editor.GoFileEnd();
		Editor.SearchPrev("0000000", 0);
		return "selected=" + Editor.GetSelectedString(0);
	});
	measure("jump to end", function () {
		Editor.GoFileTop();
		Editor.GoFileEnd();
	});
	measure("insert at the end and undo", function () {
		Editor.GoFileEnd();
		Editor.InsText("x");
		Editor.Undo();
	});
	measure("insert at the top and undo", function () {
		Editor.GoFileTop();
		Editor.InsText("x\r\n");
		Editor.Undo();
	});
	measure("rewrap at 40 columns", function () {
		Editor.ChangeWrapColumn(40);
	});
	measure("replace all", function () {
		Editor.GoFileTop();
		Editor.ReplaceAll("fox", "cat", 0);
	});
} else {
	measure("find at the end", function () {
		Editor.GoFileTop();
		Editor.SearchNext("needle", 0);
		return "selected=" + Editor.GetSelectedString(0);
	});
	measure("jump to end", function () {
		Editor.GoFileTop();
		Editor.GoFileEnd();
	});
	measure("insert at the end and undo", function () {
		Editor.GoFileEnd();
		Editor.InsText("x");
		Editor.Undo();
	});
}
write(kind + ": done");
