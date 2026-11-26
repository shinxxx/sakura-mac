# Copyright (C) 2026, Sakura Editor Organization
#
# SPDX-License-Identifier: Zlib
#
# Windows 版 sakura.exe 的编辑辅助功能的结果（计划第 44 步，CI 的 edit-support-windows 运行）：
#   宏 windows-edit-support.js 的 @DATA@、@OUT@ 换成实际的文件夹，sakura.exe -M=宏 运行，等 done.txt 写出来。
#   结果是 <OutDir>\<名字>.txt（UTF-8），与 Mac 版的 expected 比较。
#   DiffExe（GNU diffutils 的 diff.exe，原版 DIFF差分表示 用的）：复制到 sakura.exe 的文件夹（宏的 Diff 用），
#   再直接对 diff\<名字>\old.txt・new.txt 运行，塊の見出し（「99,99c99,99」）写到 diff.txt（与 Mac 版自己实现的差分比较）。
param(
	[Parameter(Mandatory = $true)][string]$SakuraExe,
	[Parameter(Mandatory = $true)][string]$DataDir,
	[Parameter(Mandatory = $true)][string]$OutDir,
	[Parameter(Mandatory = $true)][string]$DiffExe
)
$ErrorActionPreference = 'Stop'

$SakuraExe = (Resolve-Path $SakuraExe).Path
$DataDir = (Resolve-Path $DataDir).Path
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$OutDir = (Resolve-Path $OutDir).Path

Get-Process sakura -ErrorAction SilentlyContinue | Stop-Process -Force
# 日文的界面（与 Mac 版相同的消息）：去掉语言 DLL
Get-ChildItem (Split-Path $SakuraExe) -Filter 'sakura_lang_*.dll' | ForEach-Object { Remove-Item $_.FullName }

# 样本复制到工作文件夹（宏会改写文件的时候不改仓库里的）
$work = Join-Path $OutDir 'work'
if (Test-Path $work) { Remove-Item -Recurse -Force $work }
Copy-Item -Recurse -LiteralPath $DataDir -Destination $work

# GNU diff：sakura.exe の隣に置く（DLL も）。直接実行して塊の見出しを集める
$DiffExe = (Resolve-Path $DiffExe).Path
Get-ChildItem (Split-Path $DiffExe) -Filter '*.dll' | ForEach-Object { Copy-Item $_.FullName (Split-Path $SakuraExe) }
Copy-Item $DiffExe (Join-Path (Split-Path $SakuraExe) 'diff.exe')
& $DiffExe --version | Select-Object -First 1
# 選択肢（原版 F_DIFF の第 2 引数のビット → diff の選択肢）。OrderedDictionary の整数の添字は位置になるので配列で
$flagOptions = @(@(0x00, ''), @(0x01, '-i'), @(0x02, '-w'), @(0x04, '-b'), @(0x08, '-B'), @(0x10, '-t'), @(0x0F, '-iwbB'))
$diffLines = New-Object System.Collections.Generic.List[string]
foreach ($case in (Get-ChildItem (Join-Path $DataDir 'diff') -Directory | Sort-Object Name)) {
	foreach ($pair in $flagOptions) {
		$flag = $pair[0]
		$diffArgs = @()
		if ($pair[1] -ne '') { $diffArgs += $pair[1] }
		$diffArgs += (Join-Path $case.FullName 'old.txt'), (Join-Path $case.FullName 'new.txt')
		$hunks = & $DiffExe @diffArgs | Where-Object { $_ -match '^[0-9]' }
		$diffLines.Add(('{0} {1:x2}: {2}' -f $case.Name, $flag, ($hunks -join ' ')))
	}
}
[IO.File]::WriteAllText((Join-Path $OutDir 'diff.txt'), (($diffLines -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding($false)))

$template = Get-Content (Join-Path $PSScriptRoot 'windows-edit-support.js') -Raw -Encoding utf8
$js = $template.Replace('@DATA@', $work.Replace('\', '\\')).Replace('@OUT@', $OutDir.Replace('\', '\\'))
$macro = Join-Path $OutDir 'edit-support.js'
Set-Content $macro $js -Encoding utf8BOM

$done = Join-Path $OutDir 'done.txt'
$p = Start-Process $SakuraExe -ArgumentList "-M=`"$macro`"" -PassThru
$deadline = (Get-Date).AddMinutes(35)
while ((Get-Date) -lt $deadline -and -not (Test-Path $done)) { Start-Sleep -Seconds 2 }
if (-not (Test-Path $done)) {
	# 終わらなかった：画面を残す（メッセージボックス等で止まっていないか）
	Add-Type -AssemblyName System.Windows.Forms, System.Drawing
	$bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
	$bmp = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
	$g = [System.Drawing.Graphics]::FromImage($bmp)
	$g.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
	$bmp.Save((Join-Path $OutDir 'timeout.png'))
}
Get-Process sakura -ErrorAction SilentlyContinue | Stop-Process -Force
if (-not (Test-Path $done)) { throw 'macro did not finish' }
Get-ChildItem $OutDir -Filter 'error*.txt' | ForEach-Object { Write-Host "::error::$($_.Name): $(Get-Content $_.FullName)"; $script:failed = $true }
if ($failed) { exit 1 }
