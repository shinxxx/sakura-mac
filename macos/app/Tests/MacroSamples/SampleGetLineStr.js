//sample.js
//指定論理行の取得
var oWsh = new ActiveXObject("WScript.Shell");
var sBuf;

sBuf = "先頭行の内容は\n" + GetLineStr(1) + "\n\n";
sBuf += "現在キャレット行の内容は\n" + GetLineStr(0) + "\n\n";
sBuf += "最終行の内容は\n" + GetLineStr(GetLineCount(0));

oWsh.Popup(sBuf, 0, "行を取得", 0);
