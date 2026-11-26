//sample.js
//空行をカウントする
var iLine = 0;
var iCount = 0;
var iMax = GetLineCount(0);	//論理行数を取得
while (++iLine <= iMax){	//全行をループ
    if (GetLineStr(iLine).match(/[^\t ]+/) == 0){
        iCount++;
    }
}

var oWsh = new ActiveXObject("WScript.Shell");
oWsh.Popup(iCount, 0, "", 0);
