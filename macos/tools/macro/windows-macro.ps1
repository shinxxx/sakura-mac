# Copyright (C) 2026, Sakura Editor Organization
#
# SPDX-License-Identifier: Zlib
#
# 第 45 步：Windows 版 sakura.exe で Tests/MacroSamples/WindowsCompare.js を実行して、最後の文書を <OutDir>\WindowsCompare.txt（UTF-8、LF）に書く。
# Mac 版は App 単元テスト JSMacroTests.testWindowsCompare が同じマクロを実行して、同じ期待値（Tests/MacroSamples/WindowsCompare.txt）と比べる。
param(
	[Parameter(Mandatory = $true)][string]$SakuraExe,
	[Parameter(Mandatory = $true)][string]$Macro,
	[Parameter(Mandatory = $true)][string]$OutDir
)
$ErrorActionPreference = 'Stop'

$SakuraExe = (Resolve-Path $SakuraExe).Path
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$OutDir = (Resolve-Path $OutDir).Path
Get-Process sakura -ErrorAction SilentlyContinue | Stop-Process -Force
# 日本語のメッセージ・設定（Mac 版と同じ）
Get-ChildItem (Split-Path $SakuraExe) -Filter 'sakura_lang_*.dll' | ForEach-Object { Remove-Item $_.FullName }

$shared = Get-Content $Macro -Raw -Encoding utf8
$out = $OutDir.Replace('\', '\\')
$tail = @"

function writeUtf8(path, text) {
	var s = new ActiveXObject("ADODB.Stream");
	s.Type = 2;
	s.Charset = "utf-8";
	s.Open();
	s.WriteText(text);
	s.Position = 0;
	s.Type = 1;
	s.Position = 3;	// BOM を除く
	var bin = new ActiveXObject("ADODB.Stream");
	bin.Type = 1;
	bin.Open();
	s.CopyTo(bin);
	bin.SaveToFile(path, 2);
	bin.Close();
	s.Close();
}
var __lines = [];
var __n = Editor.GetLineCount(0);
for (var __i = 1; __i <= __n; __i++) __lines.push(Editor.GetLineStr(__i).replace(/[\r\n]+`$/, ""));
writeUtf8("$out\\WindowsCompare.txt", __lines.join("\n"));
writeUtf8("$out\\done.txt", "done\n");
"@
$js = "try {`r`n" + $shared + "`r`n} catch (e) {`r`n`tnew ActiveXObject(`"Scripting.FileSystemObject`").CreateTextFile(`"$out\\error.txt`", true).Write(String(e.message));`r`n}`r`n" + $tail
$path = Join-Path $OutDir 'macro.js'
Set-Content $path $js -Encoding utf8BOM

$done = Join-Path $OutDir 'done.txt'
$p = Start-Process $SakuraExe -ArgumentList "-M=`"$path`"" -PassThru
$deadline = (Get-Date).AddMinutes(5)
while ((Get-Date) -lt $deadline -and -not (Test-Path $done)) { Start-Sleep -Seconds 2 }
if (-not (Test-Path $done)) {
	# 止まったときの画面（メッセージボックス等）
	Add-Type -AssemblyName System.Windows.Forms, System.Drawing
	$bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
	$bmp = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
	$g = [System.Drawing.Graphics]::FromImage($bmp)
	$g.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
	$bmp.Save((Join-Path $OutDir 'timeout.png'))
}
Get-Process sakura -ErrorAction SilentlyContinue | Stop-Process -Force
if (Test-Path (Join-Path $OutDir 'error.txt')) { Write-Host "::error::macro error: $(Get-Content (Join-Path $OutDir 'error.txt'))" }
if (-not (Test-Path $done)) { throw 'macro did not finish' }
