# Copyright (C) 2026, Sakura Editor Organization
#
# SPDX-License-Identifier: Zlib
#
# Windows 版 sakura.exe の印刷（计划第 47 步，CI 的 print-windows 运行）：
#   「Microsoft Print to PDF」の出力先をファイルにして既定のプリンターにし、
#   macos/core/tests/data/print/cases.tsv の各条件を sakura.ini の [Print] PS[00] に書いて、
#   sample.txt を宏の Print() で印刷する（プリンターのダイアログは OK を押す）。
#   PDF は <OutDir>\<名前>.pdf。文字の位置は print_pdf_chars.py で取り出して Mac 版の expected.txt と比べる
#   （Mac 版は核心库测试 MacPrintTest.WindowsComparison が同じ条件で作る）。
param(
	[Parameter(Mandatory = $true)][string]$SakuraExe,
	[Parameter(Mandatory = $true)][string]$DataDir,
	[Parameter(Mandatory = $true)][string]$OutDir
)
$ErrorActionPreference = 'Stop'

$SakuraExe = (Resolve-Path $SakuraExe).Path
$DataDir = (Resolve-Path $DataDir).Path
$exeDir = Split-Path $SakuraExe
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$OutDir = (Resolve-Path $OutDir).Path
$work = Join-Path $OutDir 'work'
if (Test-Path $work) { Remove-Item -Recurse -Force $work }
New-Item -ItemType Directory -Force -Path $work | Out-Null

Get-Process sakura -ErrorAction SilentlyContinue | Stop-Process -Force
Get-ChildItem $exeDir -Filter 'sakura_lang_*.dll' | ForEach-Object { Remove-Item $_.FullName }
Remove-Item (Join-Path $exeDir 'sakura.exe.ini') -ErrorAction SilentlyContinue
$ini = Join-Path $exeDir 'sakura.ini'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$utf8Bom = New-Object System.Text.UTF8Encoding($true)

Add-Type @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public static class PrintWin {
	delegate bool EnumProc(IntPtr hwnd, IntPtr lParam);
	[DllImport("user32.dll")] static extern bool EnumWindows(EnumProc proc, IntPtr lParam);
	[DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
	[DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr hwnd, StringBuilder s, int n);
	[DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr hwnd, StringBuilder s, int n);
	[DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hwnd);
	[DllImport("user32.dll")] static extern IntPtr GetDlgItem(IntPtr hwnd, int id);
	[DllImport("user32.dll")] static extern bool PostMessage(IntPtr hwnd, uint msg, IntPtr w, IntPtr l);
	// プロセス pid の見えているダイアログ（#32770）のタイトル。OK ボタン（IDOK）があり、タイトルが except でないもの
	public static List<string> Dialogs(uint pid) {
		var list = new List<string>();
		EnumWindows((h, l) => {
			uint p; GetWindowThreadProcessId(h, out p);
			if (p != pid || !IsWindowVisible(h)) return true;
			var c = new StringBuilder(256); GetClassName(h, c, 256);
			var t = new StringBuilder(256); GetWindowText(h, t, 256);
			if (c.ToString() == "#32770") list.Add(h.ToInt64() + "\t" + t.ToString() + "\t" + (GetDlgItem(h, 1) != IntPtr.Zero));
			return true;
		}, IntPtr.Zero);
		return list;
	}
	public static void PressOk(long hwnd) {
		PostMessage(new IntPtr(hwnd), 0x0111 /* WM_COMMAND */, new IntPtr(1) /* IDOK */, IntPtr.Zero);
	}
}
'@

function Save-Screen([string]$name) {
	Add-Type -AssemblyName System.Windows.Forms, System.Drawing
	$bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
	$bmp = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
	$g = [System.Drawing.Graphics]::FromImage($bmp)
	$g.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
	$bmp.Save((Join-Path $OutDir $name))
}

# 印刷先：Microsoft Print to PDF の出力をファイルに（ダイアログで名前を聞かない）
$pdf = Join-Path $work 'out.pdf'
$printer = 'Microsoft Print to PDF'
Add-PrinterPort -Name $pdf
Set-Printer -Name $printer -PortName $pdf
# 既定のプリンター（Windows が自動で選ぶ設定を切る）
Set-ItemProperty 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Windows' -Name LegacyDefaultPrinterMode -Value 1 -Type DWord
Get-CimInstance Win32_Printer -Filter "Name='$printer'" | Invoke-CimMethod -MethodName SetDefaultPrinter | Out-Null
Get-Printer | Format-Table Name, DriverName, PortName -AutoSize | Out-String -Width 200 | Write-Host

$sample = Join-Path $work 'sample.txt'
Copy-Item (Join-Path $DataDir 'sample.txt') $sample

foreach ($line in [IO.File]::ReadAllLines((Join-Path $DataDir 'cases.tsv'), $utf8)) {
	if ($line -eq '' -or $line.StartsWith('#')) { continue }
	$cols = $line.Split("`t")
	$name = $cols[0]
	# 既定値（原版 CPrint::SettingInitialize。Mac 版の测试と同じ）に条件を重ねる。
	# フォントは ＭＳ ゴシック（CI の Windows には ＭＳ 明朝 がない。ほかのフォントに代わると文字の幅が変わる）
	$v = [ordered]@{
		height = 24; spacing = 30; columns = 1; colspace = 70; mt = 100; mb = 200; ml = 200; mr = 100
		orient = 1; paper = 9; wrap = 1; linenum = 0; kh = 0; kt = 0; kr = 0; kk = 0
		h0 = '$f'; h1 = ''; h2 = ''; f0 = ''; f1 = '- $p -'; f2 = ''
	}
	if ($cols.Count -gt 1) {
		foreach ($kv in $cols[1].Split(';')) {
			if ($kv -eq '') { continue }
			$eq = $kv.IndexOf('=')
			$v[$kv.Substring(0, $eq)] = $kv.Substring($eq + 1)
		}
	}
	$width = [Math]::Floor(([int]$v.height + 1) / 2)
	$ints = @($width, $v.height, $v.columns, $v.colspace, $v.spacing, $v.mt, $v.mb, $v.ml, $v.mr, $v.orient, $v.paper, $v.wrap, $v.linenum, 1, 0, 0, 1, 0, 0) -join ','
	$iniText = "[Print]`r`nPS[00].nInts=$ints`r`nPS[00].szSName=印刷設定 1`r`nPS[00].szFF=ＭＳ ゴシック`r`nPS[00].szFFZ=ＭＳ ゴシック`r`n"
	for ($j = 0; $j -lt 3; $j++) {
		$iniText += "PS[00].szHF[$j]=$($v["h$j"])`r`nPS[00].szFTF[$j]=$($v["f$j"])`r`n"
	}
	$iniText += "PS[00].bKinsokuHead=$($v.kh)`r`nPS[00].bKinsokuTail=$($v.kt)`r`nPS[00].bKinsokuRet=$($v.kr)`r`nPS[00].bKinsokuKuto=$($v.kk)`r`nPS[00].bColorPrint=0`r`n"
	[IO.File]::WriteAllText($ini, $iniText, $utf8Bom)

	Remove-Item $pdf -ErrorAction SilentlyContinue
	$done = Join-Path $OutDir 'done.txt'
	Remove-Item $done -ErrorAction SilentlyContinue
	$js = @"
Editor.Print();
new ActiveXObject("Scripting.FileSystemObject").CreateTextFile("$($done.Replace('\', '\\'))", true).Close();
"@
	$macro = Join-Path $OutDir 'print.js'
	[IO.File]::WriteAllText($macro, $js, $utf8Bom)
	$p = Start-Process $SakuraExe -ArgumentList "`"$sample`"", "-M=`"$macro`"" -PassThru
	$deadline = (Get-Date).AddMinutes(2)
	$pressed = @{}
	while ((Get-Date) -lt $deadline -and -not (Test-Path $done)) {
		foreach ($proc in @(Get-Process sakura -ErrorAction SilentlyContinue)) {
			foreach ($d in [PrintWin]::Dialogs([uint32]$proc.Id)) {
				$f = $d.Split("`t")
				# プリンターのダイアログ（「印刷」）だけ OK。印刷中のダイアログ（IDD_PRINTING）は押さない
				if ($f[2] -eq 'True' -and -not $pressed.ContainsKey($f[0]) -and $f[1] -ne '印刷中') {
					Write-Host "$name : OK on dialog '$($f[1])'"
					$pressed[$f[0]] = $true
					[PrintWin]::PressOk([long]$f[0])
				}
			}
		}
		Start-Sleep -Milliseconds 300
	}
	if (-not (Test-Path $done)) { Save-Screen "timeout-$name.png" }
	# スプーラーが PDF を書き終わるまで待つ
	$deadline = (Get-Date).AddMinutes(1)
	$last = -1
	while ((Get-Date) -lt $deadline) {
		$jobs = @(Get-PrintJob -PrinterName $printer -ErrorAction SilentlyContinue)
		$size = if (Test-Path $pdf) { (Get-Item $pdf).Length } else { -1 }
		if ($jobs.Count -eq 0 -and $size -gt 0 -and $size -eq $last) { break }
		$last = $size
		Start-Sleep -Milliseconds 500
	}
	Start-Sleep -Milliseconds 500
	Get-Process sakura -ErrorAction SilentlyContinue | Stop-Process -Force
	Start-Sleep -Milliseconds 500
	if (-not (Test-Path $done)) { throw "macro did not finish: $name" }
	if (-not (Test-Path $pdf)) { Save-Screen "nopdf-$name.png"; throw "no PDF: $name" }
	Move-Item $pdf (Join-Path $OutDir "$name.pdf") -Force
	Write-Host "$name : $((Get-Item (Join-Path $OutDir "$name.pdf")).Length) bytes"
}
