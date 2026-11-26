//sample.js
//選択中の文字列
var oWsh = new ActiveXObject("WScript.Shell");
oWsh.Popup(GetSelectedString, 0, "選択中の文字列", 0);
