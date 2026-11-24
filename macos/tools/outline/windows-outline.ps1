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

Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public static class OutlineWin32 {
    delegate bool EnumProc(IntPtr hwnd, IntPtr lParam);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc proc, IntPtr lParam);
    [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr parent, EnumProc proc, IntPtr lParam);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr hwnd, StringBuilder s, int n);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr hwnd, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern int GetDlgCtrlID(IntPtr hwnd);
    public static string ClassOf(IntPtr h) { var s = new StringBuilder(256); GetClassName(h, s, 256); return s.ToString(); }
    public static string TextOf(IntPtr h) { var s = new StringBuilder(1024); GetWindowText(h, s, 1024); return s.ToString(); }
    public static List<IntPtr> TopWindows(uint[] pids) {
        var list = new List<IntPtr>();
        EnumWindows((h, l) => { uint pid; GetWindowThreadProcessId(h, out pid); if (Array.IndexOf(pids, pid) >= 0) list.Add(h); return true; }, IntPtr.Zero);
        return list;
    }
    public static List<IntPtr> Children(IntPtr parent) {
        var list = new List<IntPtr>();
        EnumChildWindows(parent, (h, l) => { list.Add(h); return true; }, IntPtr.Zero);
        return list;
    }
}
"@

function Save-Screen([string]$name) {
    try {
        $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
        $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size)
        $bmp.Save((Join-Path $OutDir "$name.png"), [System.Drawing.Imaging.ImageFormat]::Png)
        $g.Dispose(); $bmp.Dispose()
    } catch { Write-Host "screenshot failed: $_" }
}

function Show-Windows {
    $pids = [uint32[]]@(Get-Process sakura -ErrorAction SilentlyContinue | ForEach-Object { $_.Id })
    Write-Host "sakura processes: $($pids -join ', ')"
    foreach ($h in [OutlineWin32]::TopWindows($pids)) {
        Write-Host ("  window {0} class={1} visible={2} text={3}" -f $h, [OutlineWin32]::ClassOf($h), [OutlineWin32]::IsWindowVisible($h), [OutlineWin32]::TextOf($h))
        foreach ($c in [OutlineWin32]::Children($h)) {
            Write-Host ("    child id={0} class={1} visible={2} text={3}" -f [OutlineWin32]::GetDlgCtrlID($c), [OutlineWin32]::ClassOf($c), [OutlineWin32]::IsWindowVisible($c), [OutlineWin32]::TextOf($c))
        }
    }
}

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

# アウトライン解析 対話框（#32770 で、子に「コピー」ボタン 1149 があるもの。フローティングでもドッキングでも）
function Find-Dialog([int]$timeoutSec) {
    $deadline = (Get-Date).AddSeconds($timeoutSec)
    while ((Get-Date) -lt $deadline) {
        $pids = [uint32[]]@(Get-Process sakura -ErrorAction SilentlyContinue | ForEach-Object { $_.Id })
        foreach ($h in [OutlineWin32]::TopWindows($pids)) {
            $candidates = @($h) + @([OutlineWin32]::Children($h))
            foreach ($c in $candidates) {
                if ([OutlineWin32]::ClassOf($c) -ne '#32770' -or -not [OutlineWin32]::IsWindowVisible($c)) { continue }
                foreach ($k in [OutlineWin32]::Children($c)) {
                    if ([OutlineWin32]::GetDlgCtrlID($k) -eq 1149) { return $AE::FromHandle($c) }
                }
            }
        }
        Start-Sleep -Milliseconds 300
    }
    return $null
}

$samples = Get-ChildItem $DataDir -File | Where-Object { $_.Extension -notin @('.rul', '.rux') -and $_.Name -ne '.gitattributes' }
$failed = @()
foreach ($sample in $samples) {
    Stop-Sakura
    [System.Windows.Forms.Clipboard]::Clear()
    $file = $sample.FullName
    # 性能测试（perf-windows）と同じく、マクロでファイルを開いてからアウトライン解析を実行する
    $ran = Join-Path $work 'ran.txt'
    Remove-Item $ran -ErrorAction SilentlyContinue
    $js = 'Editor.FileOpen("' + $file.Replace('\', '\\') + '"); Editor.Outline(0);' +
        ' var fso = new ActiveXObject("Scripting.FileSystemObject"); var f = fso.CreateTextFile("' + $ran.Replace('\', '\\') + '", true); f.WriteLine(Editor.GetFilename()); f.Close();'
    $outlineMacro = Write-Macro 'outline.js' $js
    Start-Process $SakuraExe -ArgumentList "-M=`"$outlineMacro`"" | Out-Null
    Write-Host "$(Get-Date -Format HH:mm:ss) open: $($sample.Name)"
    $dlg = Find-Dialog 30
    if ($dlg -eq $null) {
        Write-Host "::error::outline dialog not found: $($sample.Name)"
        if (Test-Path $ran) { Write-Host "macro ran: $(Get-Content $ran)" } else { Write-Host 'macro did not finish' }
        Show-Windows
        Save-Screen ('notfound-' + $sample.Name)
        $failed += $sample.Name
        if ($failed.Count -ge 3) { break }
        continue
    }
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
