//sample.js
//挿入・上書きモードを調べる
var oWsh = new ActiveXObject("WScript.Shell");
if (IsInsMode) {
    oWsh.Popup("挿入モードです", 0, "Message", 0);
} else {
    oWsh.Popup("上書モードです", 0, "Message", 0);
}
