# Copyright (C) 2026, Sakura Editor Organization
#
# SPDX-License-Identifier: Zlib
#
# Windows 版サクラエディタ（官方发布的 sakura.exe）的アウトライン解析结果（计划第 42 步）。
# CI 的 outline-windows 用 Windows PowerShell 运行：
#   1. sakura.exe 先运行一次（宏 Editor.ExitAll）做出 sakura.ini，追加与 Mac 版测试相同的类型
#      （macos/core/tests/test-mac-outline.cpp 的 SetUp）
#   2. 每个样本文件：sakura.exe 打开文件并执行宏 Editor.Outline(0)，用 UI Automation 读出
#      アウトライン解析 对话框的标题、ツリー（展开状态、选着的项目）或リスト（列名、各行），
#      按「コピー」按钮读出剪贴板
#   3. 写成与 Mac 版测试相同的格式（<输出文件夹>\<样本名>.txt）
param(
    [Parameter(Mandatory = $true)][string]$SakuraExe,
    [Parameter(Mandatory = $true)][string]$DataDir,
    [Parameter(Mandatory = $true)][string]$OutDir
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Windows.Forms

$SakuraExe = (Resolve-Path $SakuraExe).Path
$DataDir = (Resolve-Path $DataDir).Path
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$OutDir = (Resolve-Path $OutDir).Path
$work = Join-Path $OutDir 'work'
New-Item -ItemType Directory -Force -Path $work | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Stop-Sakura {
    Get-Process sakura -ErrorAction SilentlyContinue | Stop-Process -Force
    for ($i = 0; $i -lt 50 -and (Get-Process sakura -ErrorAction SilentlyContinue); $i++) { Start-Sleep -Milliseconds 200 }
}

function Write-Macro([string]$name, [string]$body) {
    $path = Join-Path $work $name
    [IO.File]::WriteAllText($path, $body, $utf8)
    return $path
}

# ---- 1. sakura.ini ----
Stop-Sakura
$exitMacro = Write-Macro 'exit.js' 'Editor.ExitAll();'
Start-Process $SakuraExe -ArgumentList "-M=`"$exitMacro`"" | Out-Null
for ($i = 0; $i -lt 150 -and (Get-Process sakura -ErrorAction SilentlyContinue); $i++) { Start-Sleep -Milliseconds 200 }
Stop-Sakura
$ini = @(
    (Join-Path (Split-Path $SakuraExe) 'sakura.ini'),
    (Join-Path $env:APPDATA 'sakura\sakura.ini')
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $ini) { throw 'sakura.ini was not created' }
Write-Host "sakura.ini: $ini"
$text = [IO.File]::ReadAllText($ini)
$m = [regex]::Match($text, '(?m)^nTypesCount=(\d+)')
if (-not $m.Success) { throw 'nTypesCount not found' }
$count = [int]$m.Groups[1].Value
# 与 test-mac-outline.cpp 的 SetUp 相同的类型
$types = @(
    @{ szTypeName = 'WZ'; szTypeExts = 'wzt'; nDefaultOutline = '9' },
    @{ szTypeName = 'XML'; szTypeExts = 'xml'; nDefaultOutline = '15' },
    @{ szTypeName = 'Erlang'; szTypeExts = 'erl'; nDefaultOutline = '14' },
    @{ szTypeName = 'Rule1'; szTypeExts = 'rtx'; nDefaultOutline = '12'; szOutlineRuleFilename = (Join-Path $DataDir 'sample.rul') },
    @{ szTypeName = 'Rule2'; szTypeExts = 'rgx'; nDefaultOutline = '12'; szOutlineRuleFilename = (Join-Path $DataDir 'sample.rux') },
    @{ szTypeName = 'CppAtoZ'; szTypeExts = 'cps'; nDefaultOutline = '16'; nOutlineSortType = '2' },
    @{ szTypeName = 'JavaDesc'; szTypeExts = 'jvd'; nDefaultOutline = '4'; nOutlineSortType = '1' },
    @{ szTypeName = 'TextZtoA'; szTypeExts = 'txz'; nDefaultOutline = '3'; nOutlineSortType = '3' },
    @{ szTypeName = 'PerlNameDesc'; szTypeExts = 'plx'; nDefaultOutline = '7'; nOutlineSortCol = '2'; bOutlineSortDesc = '1' }
)
$text = $text.Replace($m.Value, "nTypesCount=$($count + $types.Count)")
$sb = New-Object System.Text.StringBuilder
for ($k = 0; $k -lt $types.Count; $k++) {
    [void]$sb.Append("`r`n[Types($($count + $k))]`r`n")
    foreach ($key in $types[$k].Keys) { [void]$sb.Append("$key=$($types[$k][$key])`r`n") }
}
$text = $text.TrimEnd() + "`r`n" + $sb.ToString()
[IO.File]::WriteAllText($ini, $text, (New-Object System.Text.UTF8Encoding($true)))

# ---- 2. UI Automation ----
$AE = [System.Windows.Automation.AutomationElement]
$TS = [System.Windows.Automation.TreeScope]
$Walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker

function Find-ById($root, [string]$id) {
    $cond = New-Object System.Windows.Automation.PropertyCondition($AE::AutomationIdProperty, $id)
    return $root.FindFirst($TS::Descendants, $cond)
}

function Get-Children($el) {
    $list = @()
    $c = $Walker.GetFirstChild($el)
    while ($c -ne $null) { $list += $c; $c = $Walker.GetNextSibling($c) }
    return $list
}

function Is-Selected($el) {
    $p = $null
    if ($el.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern, [ref]$p)) {
        return $p.Current.IsSelected
    }
    return $false
}

function Dump-Tree($el, [int]$depth, $sb) {
    foreach ($item in (Get-Children $el)) {
        if ($item.Current.ControlType -ne [System.Windows.Automation.ControlType]::TreeItem) { continue }
        $p = $null
        $state = 'LeafNode'
        if ($item.TryGetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern, [ref]$p)) {
            $state = [string]$p.Current.ExpandCollapseState
        }
        $marker = '  '
        if ($state -eq 'Expanded') { $marker = '- ' } elseif ($state -eq 'Collapsed' -or $state -eq 'PartiallyExpanded') { $marker = '+ ' }
        $line = (' ' * ($depth * 2)) + $marker + $item.Current.Name
        if (Is-Selected $item) { $line += ' <' }
        [void]$sb.Append($line + "`n")
        if ($state -eq 'Collapsed') {
            $p.Expand()
            Start-Sleep -Milliseconds 50
        }
        if ($state -ne 'LeafNode') { Dump-Tree $item ($depth + 1) $sb }
    }
}

function Find-Dialog([int]$timeoutSec) {
    $deadline = (Get-Date).AddSeconds($timeoutSec)
    while ((Get-Date) -lt $deadline) {
        foreach ($proc in (Get-Process sakura -ErrorAction SilentlyContinue)) {
            $cond = New-Object System.Windows.Automation.PropertyCondition($AE::ProcessIdProperty, $proc.Id)
            foreach ($win in $AE::RootElement.FindAll($TS::Children, $cond)) {
                if ($win.Current.ClassName -eq '#32770') {
                    $copy = Find-ById $win '1149'
                    if ($copy -ne $null -and $copy.Current.IsEnabled) { return $win }
                }
            }
        }
        Start-Sleep -Milliseconds 300
    }
    return $null
}

$outlineMacro = Write-Macro 'outline.js' 'Editor.Outline(0);'
$samples = Get-ChildItem $DataDir -File | Where-Object { $_.Extension -notin @('.rul', '.rux') -and $_.Name -ne '.gitattributes' }
$failed = @()
foreach ($sample in $samples) {
    Stop-Sakura
    [System.Windows.Forms.Clipboard]::Clear()
    $file = $sample.FullName
    Start-Process $SakuraExe -ArgumentList "-M=`"$outlineMacro`" `"$file`"" | Out-Null
    $dlg = Find-Dialog 60
    if ($dlg -eq $null) { Write-Host "::error::outline dialog not found: $($sample.Name)"; $failed += $sample.Name; continue }
    Start-Sleep -Milliseconds 500
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('title: ' + $dlg.Current.Name + "`n")
    $tree = Find-ById $dlg '1137'
    $list = Find-ById $dlg '1084'
    if ($tree -ne $null -and -not $tree.Current.IsOffscreen) {
        [void]$sb.Append("[tree]`n")
        Dump-Tree $tree 0 $sb
    } elseif ($list -ne $null) {
        [void]$sb.Append("[list]`n")
        $header = $list.FindFirst($TS::Descendants, (New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::Header)))
        $titles = @()
        if ($header -ne $null) { foreach ($h in (Get-Children $header)) { $titles += $h.Current.Name } }
        while ($titles.Count -lt 4) { $titles += '' }
        [void]$sb.Append(($titles[0..3] -join "`t") + "`n")
        foreach ($row in (Get-Children $list)) {
            if ($row.Current.ControlType -ne [System.Windows.Automation.ControlType]::ListItem) { continue }
            $cells = @(Get-Children $row | ForEach-Object { $_.Current.Name })
            if ($cells.Count -lt 4) { $cells = @($row.Current.Name) + $cells; while ($cells.Count -lt 4) { $cells += '' } }
            $line = ($cells[0..3] -join "`t")
            if (Is-Selected $row) { $line += ' <' }
            [void]$sb.Append($line + "`n")
        }
    } else {
        Write-Host "::error::tree/list not found: $($sample.Name)"; $failed += $sample.Name
    }
    # 「コピー」
    $copy = Find-ById $dlg '1149'
    $copy.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
    Start-Sleep -Milliseconds 500
    $clip = [System.Windows.Forms.Clipboard]::GetText()
    $clip = $clip.Replace("`r`n", "`n").Replace($file, '<FILE>')
    [void]$sb.Append("[clip]`n" + $clip)
    [IO.File]::WriteAllText((Join-Path $OutDir ($sample.Name + '.txt')), $sb.ToString(), $utf8)
    Write-Host "done: $($sample.Name)"
}
Stop-Sakura
if ($failed.Count -gt 0) { throw "failed: $($failed -join ', ')" }
