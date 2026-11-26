//sample.js
var oWsh = new ActiveXObject("WScript.Shell");
switch (GetLineCode) {
case 0:
    oWsh.Popup("CRLF", 0, "改行コード", 0);
    break;
case 1:
    oWsh.Popup("CR", 0, "改行コード", 0);
    break;
case 2:
    oWsh.Popup("LF", 0, "改行コード", 0);
    break;
default:
    oWsh.Popup("不明", 0, "改行コード", 0);
    break;
}
