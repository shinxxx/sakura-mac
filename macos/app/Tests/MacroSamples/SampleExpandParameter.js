//sample.js
//特殊文字の展開
var oWsh = new ActiveXObject("WScript.Shell");
var sBuf;

sBuf = "現在開いているファイルのタイムスタンプは\n";
sBuf += ExpandParameter("$D") + " " + ExpandParameter("$T") + "です。\n\n";

sBuf += ExpandParameter("${R?読み取り専用の$:上書き禁止の$:編集可能な$}") + "ファイルです。";

oWsh.Popup(sBuf, 0, "ファイル情報", 0);
//EOF
