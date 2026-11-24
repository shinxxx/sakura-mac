# Copyright (C) 2026, Sakura Editor Organization
#
# SPDX-License-Identifier: Zlib
#
# Windows 版サクラエディタ（官方发布的 sakura.exe）的アウトライン解析结果（计划第 42 步）。
# CI 的 outline-windows 用 Windows PowerShell 运行：
#   1. sakura.exe 先运行一次（宏 Editor.ExitAll）做出 sakura.ini，追加与 Mac 版测试相同的类型
#      （macos/core/tests/test-mac-outline.cpp 的 SetUp）
#   2. 每个样本文件：sakura.exe 用宏打开文件并执行 Editor.Outline(0)，从对话框读出标题、
#      ツリー（展开状态、选着的项目）或リスト（列名、各行）（TreeView・ListView 的消息，读 sakura.exe 进程里的内存），
#      按「コピー」按钮读出剪贴板
# sakura.exe 是 32 位的，结构体的大小要相同，所以用 32 位的 Windows PowerShell 运行（SysWOW64）。
# 界面的语言是日文（与 Mac 版相同）：删掉语言 DLL（sakura_lang_*.dll），用内置的日文资源。
#   3. 写成与 Mac 版测试相同的格式（<输出文件夹>\<样本名>.txt）
param(
    [Parameter(Mandatory = $true)][string]$SakuraExe,
    [Parameter(Mandatory = $true)][string]$DataDir,
    [Parameter(Mandatory = $true)][string]$OutDir
)
$ErrorActionPreference = 'Stop'
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
    [DllImport("user32.dll")] public static extern IntPtr GetDlgItem(IntPtr dlg, int id);
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr hwnd, uint msg, IntPtr wParam, IntPtr lParam);
    // WM_COMMAND（BN_CLICKED）でボタンを押す
    public static void Click(IntPtr dlg, int id) { SendMessage(dlg, 0x0111, (IntPtr)id, GetDlgItem(dlg, id)); }

    // ---- sakura.exe の TreeView・ListView を読む（相手の進程のメモリに構造体を置いて SendMessage） ----
    [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint access, bool inherit, uint pid);
    [DllImport("kernel32.dll")] static extern IntPtr VirtualAllocEx(IntPtr proc, IntPtr addr, int size, uint type, uint protect);
    [DllImport("kernel32.dll")] static extern bool VirtualFreeEx(IntPtr proc, IntPtr addr, int size, uint type);
    [DllImport("kernel32.dll")] static extern bool WriteProcessMemory(IntPtr proc, IntPtr addr, byte[] buf, int size, out int written);
    [DllImport("kernel32.dll")] static extern bool ReadProcessMemory(IntPtr proc, IntPtr addr, byte[] buf, int size, out int read);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    const int TextOffset = 256, TextChars = 2000, MemSize = 8192;
    static IntPtr proc, mem;
    public static void Open(IntPtr hwnd) {
        uint pid; GetWindowThreadProcessId(hwnd, out pid);
        proc = OpenProcess(0x0008 | 0x0010 | 0x0020 | 0x0400, false, pid);
        mem = VirtualAllocEx(proc, IntPtr.Zero, MemSize, 0x1000, 0x04);
        if (mem == IntPtr.Zero) throw new Exception("VirtualAllocEx failed");
    }
    public static void Close() { VirtualFreeEx(proc, mem, 0, 0x8000); CloseHandle(proc); }
    static void WriteInts(int[] values) {
        var buf = new byte[values.Length * 4];
        Buffer.BlockCopy(values, 0, buf, 0, buf.Length);
        int n; WriteProcessMemory(proc, mem, buf, buf.Length, out n);
        int m; WriteProcessMemory(proc, mem + TextOffset, new byte[2], 2, out m);
    }
    static string ReadText() {
        var buf = new byte[TextChars * 2]; int n;
        ReadProcessMemory(proc, mem + TextOffset, buf, buf.Length, out n);
        var s = Encoding.Unicode.GetString(buf);
        int z = s.IndexOf('\0'); return z >= 0 ? s.Substring(0, z) : s;
    }
    // TreeView：TVM_GETNEXTITEM、TVM_GETITEMW（TVITEMW：mask, hItem, state, stateMask, pszText, cchTextMax, ...）
    public static IntPtr TreeNext(IntPtr tree, IntPtr item, int code) { return SendMessage(tree, 0x110A, (IntPtr)code, item); }
    public static int TreeState(IntPtr tree, IntPtr item) { return (int)SendMessage(tree, 0x1127, item, (IntPtr)0xFF); }
    public static string TreeText(IntPtr tree, IntPtr item) {
        WriteInts(new int[] { 0x0001 | 0x0010, (int)item, 0, 0, (int)mem + TextOffset, TextChars, 0, 0, 0, 0 });
        SendMessage(tree, 0x113E, IntPtr.Zero, mem);
        return ReadText();
    }
    // ListView：LVM_GETITEMCOUNT、LVM_GETITEMTEXTW（LVITEMW：mask, iItem, iSubItem, state, stateMask, pszText, cchTextMax, ...）
    public static int ListCount(IntPtr list) { return (int)SendMessage(list, 0x1004, IntPtr.Zero, IntPtr.Zero); }
    public static int ListState(IntPtr list, int index) { return (int)SendMessage(list, 0x102C, (IntPtr)index, (IntPtr)0xFF); }
    public static string ListText(IntPtr list, int index, int sub) {
        WriteInts(new int[] { 0x0001, index, sub, 0, 0, (int)mem + TextOffset, TextChars, 0, 0, 0, 0, 0, 0, 0, 0 });
        SendMessage(list, 0x1073, (IntPtr)index, mem);
        return ReadText();
    }
    // ヘッダー：LVM_GETHEADER、HDM_GETITEMCOUNT、HDM_GETITEMW（HDITEMW：mask, cxy, pszText, hbm, cchTextMax, ...）
    public static string HeaderText(IntPtr list, int index) {
        IntPtr header = SendMessage(list, 0x101F, IntPtr.Zero, IntPtr.Zero);
        WriteInts(new int[] { 0x0002, 0, (int)mem + TextOffset, 0, TextChars, 0, 0, 0, 0, 0, 0, 0 });
        SendMessage(header, 0x120B, (IntPtr)index, mem);
        return ReadText();
    }
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

# 界面的语言：日文（内置的资源）
Get-ChildItem (Split-Path $SakuraExe) -Filter 'sakura_lang_*.dll' | ForEach-Object { Write-Host "remove $($_.Name)"; Remove-Item $_.FullName }

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

# ---- 2. 対話框を読む ----
function Dump-Tree([IntPtr]$tree, [IntPtr]$item, [int]$depth, $sb) {
    while ($item -ne [IntPtr]::Zero) {
        $child = [OutlineWin32]::TreeNext($tree, $item, 4)	# TVGN_CHILD
        $state = [OutlineWin32]::TreeState($tree, $item)
        $marker = '  '
        if ($child -ne [IntPtr]::Zero) { if ($state -band 0x20) { $marker = '- ' } else { $marker = '+ ' } }	# TVIS_EXPANDED
        $line = (' ' * ($depth * 2)) + $marker + [OutlineWin32]::TreeText($tree, $item)
        if ($state -band 0x02) { $line += ' <' }	# TVIS_SELECTED
        [void]$sb.Append($line + "`n")
        if ($child -ne [IntPtr]::Zero) { Dump-Tree $tree $child ($depth + 1) $sb }
        $item = [OutlineWin32]::TreeNext($tree, $item, 1)	# TVGN_NEXT
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
                    if ([OutlineWin32]::GetDlgCtrlID($k) -eq 1149) { return $c }
                }
            }
        }
        Start-Sleep -Milliseconds 300
    }
    return [IntPtr]::Zero
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
    if ($dlg -eq [IntPtr]::Zero) {
        Write-Host "::error::outline dialog not found: $($sample.Name)"
        if (Test-Path $ran) { Write-Host "macro ran: $(Get-Content $ran)" } else { Write-Host 'macro did not finish' }
        Show-Windows
        Save-Screen ('notfound-' + $sample.Name)
        $failed += $sample.Name
        if ($failed.Count -ge 3) { break }
        continue
    }
    Start-Sleep -Milliseconds 500
    [OutlineWin32]::Open($dlg)
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('title: ' + [OutlineWin32]::TextOf($dlg) + "`n")
    $tree = [OutlineWin32]::GetDlgItem($dlg, 1137)
    $list = [OutlineWin32]::GetDlgItem($dlg, 1084)
    if ([OutlineWin32]::IsWindowVisible($tree)) {
        [void]$sb.Append("[tree]`n")
        Dump-Tree $tree ([OutlineWin32]::TreeNext($tree, [IntPtr]::Zero, 0)) 0 $sb	# TVGN_ROOT
    } elseif ([OutlineWin32]::IsWindowVisible($list)) {
        [void]$sb.Append("[list]`n")
        [void]$sb.Append(((0..3 | ForEach-Object { [OutlineWin32]::HeaderText($list, $_) }) -join "`t") + "`n")
        for ($i = 0; $i -lt [OutlineWin32]::ListCount($list); $i++) {
            $line = ((0..3 | ForEach-Object { [OutlineWin32]::ListText($list, $i, $_) }) -join "`t")
            if ([OutlineWin32]::ListState($list, $i) -band 0x02) { $line += ' <' }	# LVIS_SELECTED
            [void]$sb.Append($line + "`n")
        }
    } else {
        Write-Host "::error::tree/list not found: $($sample.Name)"; $failed += $sample.Name
    }
    [OutlineWin32]::Close()
    # 「コピー」
    [OutlineWin32]::Click($dlg, 1149)
    Start-Sleep -Milliseconds 500
    $clip = [System.Windows.Forms.Clipboard]::GetText()
    $clip = $clip.Replace("`r`n", "`n").Replace($file, '<FILE>')
    [void]$sb.Append("[clip]`n" + $clip)
    [IO.File]::WriteAllText((Join-Path $OutDir ($sample.Name + '.txt')), $sb.ToString(), $utf8)
    Write-Host "done: $($sample.Name)"
}
Stop-Sakura
if ($failed.Count -gt 0) { throw "failed: $($failed -join ', ')" }
