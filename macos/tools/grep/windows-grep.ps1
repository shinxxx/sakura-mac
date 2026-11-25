# Copyright (C) 2026, Sakura Editor Organization
#
# SPDX-License-Identifier: Zlib
#
# Windows 官方版 sakura.exe 的 Grep 的结果（计划第 43 步）
# CI 的 grep-windows 运行：
#   1. 按 macos/core/tests/data/grep/cases.txt 的每一行，复制 tree/ 到工作文件夹，
#      用 sakura.exe -GREPMODE -GKEY -GFILE -GFOLDER -GOPT=…XU（结果写到标准输出）-CODE=4（结果的文档是 UTF-8）执行 Grep。
#   2. 与 Mac 版的测试（test-mac-grep.cpp 的 GrepWindowsComparison）相同地整理：文件夹的绝对路径 → {DIR}，
#      路径的 \ → /，正規表現ライブラリ的版本（到行末）→ {VERSION}；Grep置換 时在后面加上置換后的全部文件的内容（16 进）。
#   （界面的语言用日文：删掉语言 DLL）
#   3. 写出 <OutDir>\<名字>.txt（UTF-8），与 Mac 版的 expected 比较。
param(
	[Parameter(Mandatory = $true)][string]$SakuraExe,
	[Parameter(Mandatory = $true)][string]$DataDir,
	[Parameter(Mandatory = $true)][string]$OutDir
)
$ErrorActionPreference = 'Stop'

$SakuraExe = (Resolve-Path $SakuraExe).Path
$DataDir = (Resolve-Path $DataDir).Path
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$OutDir = (Resolve-Path $OutDir).Path
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Quote([string]$s) { return '"' + $s.Replace('"', '""') + '"' }

function Stop-Sakura {
	Get-Process sakura -ErrorAction SilentlyContinue | Stop-Process -Force
	Start-Sleep -Milliseconds 500
}

# 置換后的全部文件：相对路径（/ 分隔）按 UTF-16 的顺序，内容是 16 进
function Dump-Tree([string]$root) {
	$files = @(Get-ChildItem -LiteralPath $root -Recurse -File | ForEach-Object {
		[PSCustomObject]@{ Name = $_.FullName.Substring($root.Length + 1).Replace('\', '/'); Path = $_.FullName }
	})
	[Array]::Sort($files, [Comparison[object]]{ param($a, $b) [string]::CompareOrdinal($a.Name, $b.Name) })
	$sb = New-Object System.Text.StringBuilder
	[void]$sb.Append("----- files -----`n")
	foreach ($f in $files) {
		[void]$sb.Append($f.Name + ':')
		foreach ($b in [IO.File]::ReadAllBytes($f.Path)) { [void]$sb.Append((' {0:X2}' -f $b)) }
		[void]$sb.Append("`n")
	}
	return $sb.ToString()
}

Stop-Sakura
# 界面的语言是日文（与 Mac 版相同，结果的标题是日文）：删掉语言 DLL（sakura_lang_*.dll），用内置的日文资源
Get-ChildItem (Split-Path $SakuraExe) -Filter 'sakura_lang_*.dll' | ForEach-Object { Write-Host "remove $($_.Name)"; Remove-Item $_.FullName }
$ng = 0
foreach ($line in [IO.File]::ReadAllLines((Join-Path $DataDir 'cases.txt'), $utf8)) {
	if ($line -eq '' -or $line.StartsWith('#')) { continue }
	$c = $line.Split("`t")
	$name = $c[0]
	$work = Join-Path $OutDir "work\$name"
	if (Test-Path $work) { Remove-Item -Recurse -Force $work }
	New-Item -ItemType Directory -Force -Path $work | Out-Null
	$tree = Join-Path $work 'tree'
	Copy-Item -Recurse -LiteralPath (Join-Path $DataDir 'tree') -Destination $tree

	$arguments = "-GREPMODE -GKEY=$(Quote $c[1]) -GFILE=$(Quote $c[2]) -GFOLDER=$(Quote $tree) -GOPT=$($c[3])XU -CODE=4"
	if ($c[4] -ne '') { $arguments += " -GCODE=$($c[4])" }
	if ($c.Count -ge 6) { $arguments += " -GREPR=$(Quote $c[5])" }
	Write-Host "[$name] $arguments"
	$stdout = Join-Path $work 'stdout.bin'
	# 偶尔标准输出是空的（编辑进程刚启动时的时机）：空的时候再试（最多 3 次。Grep置換 只在没有改文件时再试）
	for ($try = 1; $try -le 3; $try++) {
		$p = Start-Process -FilePath $SakuraExe -ArgumentList $arguments -RedirectStandardOutput $stdout -PassThru -NoNewWindow
		if (-not $p.WaitForExit(120000)) { Write-Host "::error::timeout: $name"; $ng = 1; Stop-Sakura; break }
		if ((Get-Item $stdout).Length -gt 0) { break }
		Write-Host "[$name] empty output (try $try)"
		Start-Sleep -Seconds 2
	}

	$text = $utf8.GetString([IO.File]::ReadAllBytes($stdout))
	$text = [regex]::Replace($text, [regex]::Escape($tree), '{DIR}', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
	$text = $text.Replace('\', '/')
	$text = [regex]::Replace($text, '\(正規表現:[^\r\n]*', '(正規表現:{VERSION})')
	if ($c.Count -ge 6) { $text += Dump-Tree $tree }
	[IO.File]::WriteAllText((Join-Path $OutDir "$name.txt"), $text, $utf8)
}
Stop-Sakura
exit $ng
