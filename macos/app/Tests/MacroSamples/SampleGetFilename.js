//sample.js
//現在開いているファイル名
var oWsh = new ActiveXObject("WScript.Shell");
oWsh.Popup('ファイル名は"' + GetFilename + '"です', 0, "ファイル名", 0);
