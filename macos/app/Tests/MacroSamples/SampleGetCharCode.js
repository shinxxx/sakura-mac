//sample.js
//どの文字コードでファイルを開いているか
var oWsh = new ActiveXObject("WScript.Shell");
switch (GetCharCode) {
case 0:
    oWsh.Popup("SJISで開いています", 0, "現在の文字コード", 0);
    break;
case 1:
    oWsh.Popup("JISで開いています", 0, "現在の文字コード", 0);
    break;
case 2:
    oWsh.Popup("EUCで開いています", 0, "現在の文字コード", 0);
    break;
case 3:
    oWsh.Popup("Unicodeで開いています", 0, "現在の文字コード", 0);
    break;
case 4:
    oWsh.Popup("UTF-8で開いています", 0, "現在の文字コード", 0);
    break;
case 5:
    oWsh.Popup("UTF-7で開いています", 0, "現在の文字コード", 0);
    break;
case 6:
    oWsh.Popup("UnicodeBEで開いています", 0, "現在の文字コード", 0);
    break;
default:
    oWsh.Popup("不明", 0, "現在の文字コード", 0);
    break;
}
