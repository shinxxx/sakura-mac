# Copyright (C) 2026, Sakura Editor Organization
#
# SPDX-License-Identifier: Zlib
#
# Windows 版 sakura.exe のバックアップファイル名（计划第 46 步，CI 的 backup-windows 运行）：
#   macos/core/tests/data/backup/cases.tsv 的每个条件写进 sakura.exe 旁边的 sakura.ini（[Common]），
#   第 k 次保存前把 test.txt 的更新日时设成 2026-01-0k 10:20:3k（当地时间），用宏把内容换成「k」上書き保存，退出。
#   结果（文件夹里的文件名和内容）写到 <OutDir>\backup.txt（UTF-8、LF），与 Mac 版的 expected.txt 比较
#   （Mac 版由核心库测试 MacBackupTest.BackupWindowsComparison 做同样的手顺）。
param(
	[Parameter(Mandatory = $true)][string]$SakuraExe,
	[Parameter(Mandatory = $true)][string]$Cases,
	[Parameter(Mandatory = $true)][string]$OutDir
)
$ErrorActionPreference = 'Stop'

$SakuraExe = (Resolve-Path $SakuraExe).Path
$exeDir = Split-Path $SakuraExe
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$OutDir = (Resolve-Path $OutDir).Path
$work = Join-Path $OutDir 'work'
if (Test-Path $work) { Remove-Item -Recurse -Force $work }
New-Item -ItemType Directory -Force -Path $work | Out-Null

Get-Process sakura -ErrorAction SilentlyContinue | Stop-Process -Force
# 日文的界面：去掉语言 DLL。设置文件用 sakura.exe 旁边的 sakura.ini（多用户设置 sakura.exe.ini 去掉）
Get-ChildItem $exeDir -Filter 'sakura_lang_*.dll' | ForEach-Object { Remove-Item $_.FullName }
Remove-Item (Join-Path $exeDir 'sakura.exe.ini') -ErrorAction SilentlyContinue
$ini = Join-Path $exeDir 'sakura.ini'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$utf8Bom = New-Object System.Text.UTF8Encoding($true)

function Save-Screen([string]$name) {
	Add-Type -AssemblyName System.Windows.Forms, System.Drawing
	$bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
	$bmp = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
	$g = [System.Drawing.Graphics]::FromImage($bmp)
	$g.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
	$bmp.Save((Join-Path $OutDir $name))
}

$out = New-Object System.Text.StringBuilder
foreach ($line in [IO.File]::ReadAllLines((Resolve-Path $Cases).Path, $utf8)) {
	if ($line -eq '' -or $line.StartsWith('#')) { continue }
	$cols = $line.Split("`t")
	$name = $cols[0]
	$saves = [int]$cols[1]
	$dir = Join-Path $work $name
	New-Item -ItemType Directory -Force -Path $dir | Out-Null

	# 既定値（Mac 版の测试と同じ）に条件を重ねる
	$values = [ordered]@{
		bBackUp = '1'; bBackUpDialog = '0'; bBackUpDustBox = '0'; bBackUpFolder = '0'; bBackUpFolderRM = '0'
		bBackUpPathAdvanced = '0'; nBackUpType = '1'; bBackUpType2_Opt1 = '0'; bBackUpType2_Opt2 = [string]((98 -shl 16) -bor 10)
		bBackUpType2_Opt4 = '0'; szBackUpFolder = ''; szBackUpPathAdvanced = ''
		bCheckFileTimeStamp = '0'
	}
	foreach ($kv in $cols[2].Split(';')) {
		if ($kv -eq '') { continue }
		$eq = $kv.IndexOf('=')
		$value = $kv.Substring($eq + 1)
		# @DIR@/x → このケースのフォルダー\x（Windows の区切り）
		$value = $value.Replace('@DIR@/', $dir + '\').Replace('@DIR@', $dir)
		$values[$kv.Substring(0, $eq)] = $value
	}
	$iniText = "[Common]`r`n"
	foreach ($k in $values.Keys) { $iniText += "$k=$($values[$k])`r`n" }
	[IO.File]::WriteAllText($ini, $iniText, $utf8Bom)

	$file = Join-Path $dir 'test.txt'
	[IO.File]::WriteAllText($file, '0', $utf8)
	for ($k = 1; $k -le $saves; $k++) {
		(Get-Item $file).LastWriteTime = New-Object DateTime 2026, 1, $k, 10, 20, (30 + $k), ([DateTimeKind]::Local)
		$done = Join-Path $OutDir 'done.txt'
		Remove-Item $done -ErrorAction SilentlyContinue
		$js = @"
Editor.SelectAll();
Editor.InsText("$k");
Editor.FileSave();
new ActiveXObject("Scripting.FileSystemObject").CreateTextFile("$($done.Replace('\', '\\'))", true).Close();
Editor.ExitAll();
"@
		$macro = Join-Path $OutDir 'save.js'
		[IO.File]::WriteAllText($macro, $js, $utf8Bom)
		$p = Start-Process $SakuraExe -ArgumentList "`"$file`"", "-M=`"$macro`"" -PassThru
		$deadline = (Get-Date).AddMinutes(2)
		while ((Get-Date) -lt $deadline -and -not (Test-Path $done)) { Start-Sleep -Milliseconds 300 }
		if (-not (Test-Path $done)) { Save-Screen "timeout-$name-$k.png" }
		# 設定は常駐プロセスの共有メモリにあるので、ケースごとに必ず全部終わらせる
		Start-Sleep -Milliseconds 500
		Get-Process sakura -ErrorAction SilentlyContinue | Stop-Process -Force
		Start-Sleep -Milliseconds 500
		if (-not (Test-Path $done)) { throw "macro did not finish: $name $k" }
	}

	# フォルダーの中のファイル（相対パス、/ 区切り、序数の順）と内容
	$files = @(Get-ChildItem -Recurse -File $dir | ForEach-Object { $_.FullName.Substring($dir.Length + 1).Replace('\', '/') })
	[Array]::Sort($files, [StringComparer]::Ordinal)
	[void]$out.Append("== $name ==`n")
	foreach ($f in $files) {
		$content = [IO.File]::ReadAllText((Join-Path $dir $f.Replace('/', '\')), $utf8)
		[void]$out.Append("${f}: $content`n")
	}
}
[IO.File]::WriteAllText((Join-Path $OutDir 'backup.txt'), $out.ToString(), $utf8)
Get-Content (Join-Path $OutDir 'backup.txt')
