# Copyright (C) 2026, Sakura Editor Organization
#
# SPDX-License-Identifier: Zlib
#
# Windows 版サクラエディタ（官方发布的 sakura.exe）的ステータスバー（计划第 38 步）。
# CI 的 statusbar-windows 用 32 位的 Windows PowerShell 运行：
#   1. sakura.exe 先运行一次做出 sakura.ini（ツールバー・タブバー・ステータスバーを表示する）
#   2. cases.txt 的每一行：宏でファイルを開き、先頭から Down を N 回、Right を M 回押して、
#      ステータスバーの各欄（SB_GETTEXTW。sakura.exe 进程里的内存で読む）を書き出す
#   3. 与 Mac 版的测试（StatusBarTests.testSameAsWindows）相同的格式：<输出文件夹>\statusbar.txt
#   ウィンドウの画面（ツールバー・タブバー・ステータスバー）も保存する（Mac 版の画面と見比べる）
# 界面的语言是日文（与 Mac 版相同）：删掉语言 DLL（sakura_lang_*.dll），用内置的日文资源。
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
public static class StatusWin32 {
    delegate bool EnumProc(IntPtr hwnd, IntPtr lParam);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc proc, IntPtr lParam);
    [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr parent, EnumProc proc, IntPtr lParam);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr hwnd, StringBuilder s, int n);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr hwnd, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr hwnd, uint msg, IntPtr wParam, IntPtr lParam);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hwnd, out RECT rect);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hwnd);

    [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint access, bool inherit, uint pid);
    [DllImport("kernel32.dll")] static extern IntPtr VirtualAllocEx(IntPtr proc, IntPtr addr, int size, uint type, uint protect);
    [DllImport("kernel32.dll")] static extern bool VirtualFreeEx(IntPtr proc, IntPtr addr, int size, uint type);
    [DllImport("kernel32.dll")] static extern bool WriteProcessMemory(IntPtr proc, IntPtr addr, byte[] buf, int size, out int written);
    [DllImport("kernel32.dll")] static extern bool ReadProcessMemory(IntPtr proc, IntPtr addr, byte[] buf, int size, out int read);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    const int MemSize = 4096;
    // ステータスバーの欄の文字（SB_GETTEXTW：相手の進程のメモリに受け取る）
    public static string[] Parts(IntPtr bar) {
        int count = (int)SendMessage(bar, 0x0406, IntPtr.Zero, IntPtr.Zero);	// SB_GETPARTS
        uint pid; GetWindowThreadProcessId(bar, out pid);
        IntPtr proc = OpenProcess(0x0008 | 0x0010 | 0x0020 | 0x0400, false, pid);
        IntPtr mem = VirtualAllocEx(proc, IntPtr.Zero, MemSize, 0x1000, 0x04);
        if (mem == IntPtr.Zero) throw new Exception("VirtualAllocEx failed");
        var result = new string[count];
        try {
            for (int i = 0; i < count; i++) {
                int w; WriteProcessMemory(proc, mem, new byte[MemSize], MemSize, out w);
                SendMessage(bar, 0x040D, (IntPtr)i, mem);	// SB_GETTEXTW
                var buf = new byte[MemSize]; int n;
                ReadProcessMemory(proc, mem, buf, buf.Length, out n);
                var s = Encoding.Unicode.GetString(buf);
                int z = s.IndexOf('\0'); result[i] = z >= 0 ? s.Substring(0, z) : s;
            }
        } finally { VirtualFreeEx(proc, mem, 0, 0x8000); CloseHandle(proc); }
        return result;
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

# 編集窓口（ステータスバー msctls_statusbar32 を子に持つ、見えている窓口）
function Find-Editor([int]$timeoutSec) {
    $deadline = (Get-Date).AddSeconds($timeoutSec)
    while ((Get-Date) -lt $deadline) {
        $pids = [uint32[]]@(Get-Process sakura -ErrorAction SilentlyContinue | ForEach-Object { $_.Id })
        foreach ($h in [StatusWin32]::TopWindows($pids)) {
            if (-not [StatusWin32]::IsWindowVisible($h)) { continue }
            foreach ($c in [StatusWin32]::Children($h)) {
                if ([StatusWin32]::ClassOf($c) -eq 'msctls_statusbar32') { return @($h, $c) }
            }
        }
        Start-Sleep -Milliseconds 300
    }
    return $null
}

function Save-Window([IntPtr]$hwnd, [string]$name) {
    try {
        [StatusWin32]::SetForegroundWindow($hwnd) | Out-Null
        Start-Sleep -Milliseconds 500
        $r = New-Object StatusWin32+RECT
        [StatusWin32]::GetWindowRect($hwnd, [ref]$r) | Out-Null
        $w = $r.Right - $r.Left; $h = $r.Bottom - $r.Top
        $bmp = New-Object System.Drawing.Bitmap $w, $h
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.CopyFromScreen($r.Left, $r.Top, 0, 0, (New-Object System.Drawing.Size $w, $h))
        $bmp.Save((Join-Path $OutDir "$name.png"), [System.Drawing.Imaging.ImageFormat]::Png)
        $g.Dispose(); $bmp.Dispose()
    } catch { Write-Host "screenshot failed: $_" }
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
$iniText = [IO.File]::ReadAllText($ini)
foreach ($key in @('bDispTOOLBAR', 'bDispSTATUSBAR', 'bDispTabWnd')) {
    $m = [regex]::Match($iniText, "(?m)^$key=.*$")
    Write-Host "$($m.Value)"
}

function Set-Ini([string]$key, [string]$value) {
    $text = [IO.File]::ReadAllText($ini)
    $text = [regex]::Replace($text, "(?m)^$key=.*$", "$key=$value")
    [IO.File]::WriteAllText($ini, $text, (New-Object System.Text.UTF8Encoding($true)))
}

# ---- 2. ステータスバーを読む ----
$lines = New-Object System.Collections.Generic.List[string]
$failed = 0
$cases = Get-Content (Join-Path $DataDir 'cases.txt') -Encoding UTF8 | Where-Object { $_ -and -not $_.StartsWith('#') }
foreach ($case in $cases) {
    $f = $case.Split(' ')
    $file = Join-Path $DataDir $f[0]
    Stop-Sakura
    $ran = Join-Path $work 'ran.txt'
    Remove-Item $ran -ErrorAction SilentlyContinue
    $js = 'Editor.FileOpen("' + $file.Replace('\', '\\') + '"); Editor.GoFileTop(0);' +
        ' for (var i = 0; i < ' + $f[1] + '; i++) Editor.Down();' +
        ' for (var i = 0; i < ' + $f[2] + '; i++) Editor.Right();' +
        ' var fso = new ActiveXObject("Scripting.FileSystemObject"); var t = fso.CreateTextFile("' + $ran.Replace('\', '\\') + '", true); t.WriteLine(Editor.GetFilename()); t.Close();'
    $macro = Write-Macro 'move.js' $js
    Start-Process $SakuraExe -ArgumentList "-M=`"$macro`"" | Out-Null
    for ($i = 0; $i -lt 150 -and -not (Test-Path $ran); $i++) { Start-Sleep -Milliseconds 200 }
    $found = Find-Editor 20
    if (-not (Test-Path $ran) -or -not $found) {
        Write-Host "::error::macro did not finish: $case"
        $failed++
        if ($failed -ge 3) { break }
        continue
    }
    Start-Sleep -Milliseconds 800
    $parts = [StatusWin32]::Parts($found[1])
    Write-Host "$case -> $($parts -join ' | ')"
    # 1 行・桁、2 改行、3 文字コード、4 文字コードセット、6 挿入、7 ズーム（5 の REC はオーナードロー）
    $lines.Add("$case|$($parts[1])|$($parts[2])|$($parts[3])|$($parts[4])|$($parts[6])|$($parts[7])")
    if ($case -eq 'sjis-crlf.txt 1 2') { Save-Window $found[0] 'window-statusbar' }
}
[IO.File]::WriteAllText((Join-Path $OutDir 'statusbar.txt'), (($lines -join "`n") + "`n"), $utf8)

# ---- 3. タブバーも表示した画面（2 つのファイル） ----
Stop-Sakura
Set-Ini 'bDispTabWnd' '1'
$tabMacro = Write-Macro 'tab.js' ('Editor.FileOpen("' + (Join-Path $DataDir 'sjis-crlf.txt').Replace('\', '\\') + '");')
Start-Process $SakuraExe -ArgumentList "-M=`"$tabMacro`"" | Out-Null
Start-Sleep -Seconds 3
Start-Process $SakuraExe -ArgumentList "`"$(Join-Path $DataDir 'utf8-lf.txt')`"" | Out-Null
Start-Sleep -Seconds 3
$found = Find-Editor 20
if ($found) { Save-Window $found[0] 'window-tabbar' }
Stop-Sakura

Write-Host '---- statusbar.txt ----'
Get-Content (Join-Path $OutDir 'statusbar.txt') -Encoding UTF8 | ForEach-Object { Write-Host $_ }
if ($failed -gt 0) { exit 1 }
