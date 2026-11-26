//sample.js
//選択状態を取得
var sBuf;
switch ( IsTextSelected ){
case 0:
    sBuf = "選択されたテキストはありません。";
    break;
case 1:
    sBuf = "選択中の文字列は\n\n";
    break;
case 2:
    sBuf = "矩形選択されています\n\n";
    break;
}

sBuf += GetSelectedString(0);   

var oWsh = new ActiveXObject("WScript.Shell");
oWsh.Popup(sBuf, 0, "", 0);
