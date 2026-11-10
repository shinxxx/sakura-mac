/*! @file
	@brief 非 Windows 平台用的 Win32 兼容定义（平台抽象层，阶段 1 第 13 步）

	只提供核心代码（sakura_core 中的纯逻辑部分）编译所需的最小定义。
	- 基本类型、常量、结构体：与 Windows SDK 的定义保持相同的大小和含义。
	- 窗口、绘图等句柄：只声明为不透明指针，让头文件能通过编译。
	  核心代码不应真正使用它们，后续步骤会逐步把这类依赖移出核心库。
	- MSVC 运行库扩展函数：用标准 C/C++ 或 POSIX 函数实现。

	WCHAR 定义为 char16_t（2 字节 UTF-16，与 Windows 相同）。
	宽字符串函数（wcslen、_wcsicmp、_swprintf 等）的 char16_t 版本在 sakura_core/util/wchar16.h。

	Copyright (C) 2026, Sakura Editor Organization
	SPDX-License-Identifier: Zlib
*/
#ifndef SAKURA_PLATFORM_H_
#define SAKURA_PLATFORM_H_
#pragma once

#if defined(_WIN32)
#error "sakura_platform.h is for non-Windows platforms only."
#endif

#include <cctype>
#include <cerrno>
#include <cstdarg>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cwchar>
#include <cwctype>
#include <iterator>
#include <strings.h>

// ---------------------------------------------------------------------------
// SAL 注解：非 Windows 平台上没有意义，全部定义为空。
// ---------------------------------------------------------------------------
#define _In_
#define _In_z_
#define _In_opt_
#define _In_opt_z_
#define _In_reads_(n)
#define _In_reads_opt_(n)
#define _Inout_
#define _Inout_opt_
#define _Inout_z_
#define _Out_
#define _Out_opt_
#define _Out_writes_(n)
#define _Out_writes_z_(n)
#define _Outptr_
#define _Outptr_opt_
#define _Ret_z_
#define _Ret_maybenull_
#define _Check_return_
#define _Success_(expr)
#define _Printf_format_string_
#define _Analysis_assume_(expr)
#define _Use_decl_annotations_

// ---------------------------------------------------------------------------
// 调用约定等 MSVC 关键字
// ---------------------------------------------------------------------------
#define WINAPI
#define CALLBACK
#define APIENTRY
#define STDMETHODCALLTYPE
#define __stdcall
#define __cdecl
#define FAR
#define NEAR
#define CONST const

// ---------------------------------------------------------------------------
// 基本类型（大小与 Windows 相同）
// ---------------------------------------------------------------------------
typedef std::uint8_t   BYTE;
typedef std::uint16_t  WORD;
typedef short          SHORT;
typedef std::uint32_t  DWORD;
typedef std::int32_t   BOOL;
typedef std::int32_t   INT;
typedef std::uint32_t  UINT;
typedef std::int32_t   LONG;
typedef std::uint32_t  ULONG;
typedef long long          LONGLONG;   // Windows 与 __int64 相同，是 long long（不是 int64_t 的 long）
typedef unsigned long long ULONGLONG;
typedef std::int32_t   INT32;
typedef std::uint32_t  UINT32;
typedef long long          INT64;
typedef unsigned long long UINT64;
typedef std::intptr_t  INT_PTR;
typedef std::uintptr_t UINT_PTR;
typedef std::intptr_t  LONG_PTR;
typedef std::uintptr_t ULONG_PTR;
typedef std::uintptr_t DWORD_PTR;
typedef std::size_t    SIZE_T;
typedef char           CHAR;
typedef char16_t       WCHAR;   // UTF-16 码元（第 14 步，见 sakura_core/util/wchar16.h）
typedef WCHAR          OLECHAR;
typedef void*          PVOID;
typedef void*          LPVOID;
typedef const void*    LPCVOID;
typedef BYTE*          LPBYTE;
typedef DWORD*         LPDWORD;
typedef CHAR*          LPSTR;
typedef const CHAR*    LPCSTR;
typedef WCHAR*         LPWSTR;
typedef const WCHAR*   LPCWSTR;
typedef UINT_PTR       WPARAM;
typedef LONG_PTR       LPARAM;
typedef LONG_PTR       LRESULT;
typedef DWORD          COLORREF;
typedef WORD           ATOM;
typedef DWORD          LCID;
typedef LONG           HRESULT;
typedef int            errno_t;

#ifndef TRUE
#define TRUE  1
#endif
#ifndef FALSE
#define FALSE 0
#endif

// ---------------------------------------------------------------------------
// 句柄：不透明指针。核心代码只应传递，不应使用。
// ---------------------------------------------------------------------------
#define SAKURA_DECLARE_HANDLE(name) struct name##__; typedef struct name##__* name
typedef void* HANDLE;
SAKURA_DECLARE_HANDLE(HWND);
SAKURA_DECLARE_HANDLE(HINSTANCE);
SAKURA_DECLARE_HANDLE(HDC);
SAKURA_DECLARE_HANDLE(HFONT);
SAKURA_DECLARE_HANDLE(HBITMAP);
SAKURA_DECLARE_HANDLE(HBRUSH);
SAKURA_DECLARE_HANDLE(HPEN);
SAKURA_DECLARE_HANDLE(HRGN);
SAKURA_DECLARE_HANDLE(HICON);
SAKURA_DECLARE_HANDLE(HMENU);
SAKURA_DECLARE_HANDLE(HACCEL);
SAKURA_DECLARE_HANDLE(HKEY);
SAKURA_DECLARE_HANDLE(HMONITOR);
SAKURA_DECLARE_HANDLE(HIMC);
SAKURA_DECLARE_HANDLE(HDROP);
SAKURA_DECLARE_HANDLE(HIMAGELIST);
SAKURA_DECLARE_HANDLE(HTREEITEM);
typedef HICON   HCURSOR;
typedef HINSTANCE HMODULE;
typedef HANDLE  HGLOBAL;
typedef HANDLE  HGDIOBJ;
//! 只在界面代码里使用、核心代码只出现在声明里的结构体：不定义内容（打印对话框等）
typedef struct tagPDW PRINTDLG, *LPPRINTDLG;
struct IDataObject; typedef IDataObject* LPDATAOBJECT;
#define INVALID_HANDLE_VALUE (reinterpret_cast<HANDLE>(static_cast<LONG_PTR>(-1)))

// ---------------------------------------------------------------------------
// 结构体
// ---------------------------------------------------------------------------
typedef struct tagPOINT { LONG x; LONG y; } POINT, *PPOINT, *LPPOINT;
typedef struct tagSIZE  { LONG cx; LONG cy; } SIZE, *PSIZE, *LPSIZE;
typedef struct tagRECT  { LONG left; LONG top; LONG right; LONG bottom; } RECT, *PRECT, *LPRECT;
typedef const RECT* LPCRECT;
typedef struct tagPOINTS { short x; short y; } POINTS;
typedef struct _POINTL { LONG x; LONG y; } POINTL;
typedef struct _SYSTEMTIME {
	WORD wYear; WORD wMonth; WORD wDayOfWeek; WORD wDay;
	WORD wHour; WORD wMinute; WORD wSecond; WORD wMilliseconds;
} SYSTEMTIME, *PSYSTEMTIME, *LPSYSTEMTIME;
typedef struct _FILETIME { DWORD dwLowDateTime; DWORD dwHighDateTime; } FILETIME, *PFILETIME, *LPFILETIME;
typedef union _ULARGE_INTEGER {
	struct { DWORD LowPart; DWORD HighPart; };
	struct { DWORD LowPart; DWORD HighPart; } u;
	ULONGLONG QuadPart;
} ULARGE_INTEGER;
typedef struct _GUID {
	DWORD Data1; WORD Data2; WORD Data3; BYTE Data4[8];
} GUID, IID, CLSID;

#define LF_FACESIZE 32
#define DEFAULT_PITCH 0
#define FIXED_PITCH   1
#define ANSI_CHARSET     0
#define DEFAULT_CHARSET  1
#define SHIFTJIS_CHARSET 128
#define FW_NORMAL 400
#define FW_BOLD   700
#define VARIABLE_PITCH 2
typedef struct tagLOGFONTW {
	LONG lfHeight; LONG lfWidth; LONG lfEscapement; LONG lfOrientation; LONG lfWeight;
	BYTE lfItalic; BYTE lfUnderline; BYTE lfStrikeOut; BYTE lfCharSet;
	BYTE lfOutPrecision; BYTE lfClipPrecision; BYTE lfQuality; BYTE lfPitchAndFamily;
	WCHAR lfFaceName[LF_FACESIZE];
} LOGFONTW, LOGFONT, *LPLOGFONT;

// ---------------------------------------------------------------------------
// 常量
// ---------------------------------------------------------------------------
#define MAX_PATH  260
#define _MAX_PATH 260
#define _MAX_DRIVE 3
#define _MAX_DIR  256
#define _MAX_FNAME 256
#define _MAX_EXT  256

#define CP_ACP        0
#define CP_OEMCP      1
#define CP_MACCP      2
#define CP_THREAD_ACP 3
#define CP_SYMBOL     42
#define CP_UTF7       65000
#define CP_UTF8       65001

#define MB_PRECOMPOSED       0x00000001
#define MB_COMPOSITE         0x00000002
#define MB_USEGLYPHCHARS     0x00000004
#define MB_ERR_INVALID_CHARS 0x00000008

#define WC_DISCARDNS         0x00000010
#define WC_SEPCHARS          0x00000020
#define WC_DEFAULTCHAR       0x00000040
#define WC_ERR_INVALID_CHARS 0x00000080
#define WC_COMPOSITECHECK    0x00000200
#define WC_NO_BEST_FIT_CHARS 0x00000400

#define MAX_LEADBYTES     12
#define MAX_DEFAULTCHAR   2

#define CP_INSTALLED  0x00000001
#define CP_SUPPORTED  0x00000002

typedef struct _cpinfo {
	UINT MaxCharSize;
	BYTE DefaultChar[MAX_DEFAULTCHAR];
	BYTE LeadByte[MAX_LEADBYTES];
} CPINFO, *LPCPINFO;

typedef struct _cpinfoexW {
	UINT  MaxCharSize;
	BYTE  DefaultChar[MAX_DEFAULTCHAR];
	BYTE  LeadByte[MAX_LEADBYTES];
	WCHAR UnicodeDefaultChar;
	UINT  CodePage;
	WCHAR CodePageName[MAX_PATH];
} CPINFOEXW, *LPCPINFOEXW;
typedef CPINFOEXW CPINFOEX;
typedef LPCPINFOEXW LPCPINFOEX;

typedef BOOL (CALLBACK* CODEPAGE_ENUMPROCW)(WCHAR*);
typedef CODEPAGE_ENUMPROCW CODEPAGE_ENUMPROC;

#define MB_OK                0x00000000L
#define MB_OKCANCEL          0x00000001L
#define MB_YESNOCANCEL       0x00000003L
#define MB_YESNO             0x00000004L
#define MB_ICONSTOP          0x00000010L
#define MB_ICONQUESTION      0x00000020L
#define MB_ICONEXCLAMATION   0x00000030L
#define MB_ICONINFORMATION   0x00000040L
#define MB_TOPMOST           0x00040000L
#define IDOK     1
#define IDCANCEL 2
#define IDYES    6
#define IDNO     7

// 输入法模式（类型别设置里保存的值，与 Windows 相同）
#define IME_CMODE_ALPHANUMERIC 0x0000
#define IME_CMODE_NATIVE       0x0001
#define IME_CMODE_KATAKANA     0x0002
#define IME_CMODE_FULLSHAPE    0x0008
#define IME_CMODE_ROMAN        0x0010
#define IME_CMODE_NOCONVERSION 0x0100

// 共通设置的默认值里使用的常量（值与 Windows 相同，保存在 sakura.ini 里。第 21 步）
#define HOTKEYF_SHIFT   0x01
#define HOTKEYF_CONTROL 0x02
#define HOTKEYF_ALT     0x04
#define HOTKEYF_EXT     0x08
#define DEFAULT_QUALITY        0
#define DRAFT_QUALITY          1
#define PROOF_QUALITY          2
#define NONANTIALIASED_QUALITY 3
#define ANTIALIASED_QUALITY    4
#define CLEARTYPE_QUALITY      5
#define SIZE_RESTORED  0
#define SIZE_MINIMIZED 1
#define SIZE_MAXIMIZED 2
#define WM_APP 0x8000
inline BOOL SetRect(LPRECT lprc, int xLeft, int yTop, int xRight, int yBottom)
{
	if (!lprc) return FALSE;
	lprc->left = xLeft; lprc->top = yTop; lprc->right = xRight; lprc->bottom = yBottom;
	return TRUE;
}
#define R2_XORPEN 7   // 选择范围的绘制方式（_main/global.cpp 的常量）
#define CW_USEDEFAULT (static_cast<int>(0x80000000))
#define NO_ERROR 0L
#define S_OK     static_cast<HRESULT>(0L)
#define S_FALSE  static_cast<HRESULT>(1L)

#define RGB(r, g, b) (static_cast<COLORREF>( \
	static_cast<BYTE>(r) | (static_cast<WORD>(static_cast<BYTE>(g)) << 8) | (static_cast<DWORD>(static_cast<BYTE>(b)) << 16)))

#define MAKEWORD(a, b) (static_cast<WORD>((static_cast<BYTE>(a)) | (static_cast<WORD>(static_cast<BYTE>(b)) << 8)))
#define MAKELONG(a, b) (static_cast<LONG>((static_cast<WORD>(a)) | (static_cast<DWORD>(static_cast<WORD>(b)) << 16)))
#define LOWORD(l) (static_cast<WORD>(static_cast<DWORD_PTR>(l) & 0xffff))
#define HIWORD(l) (static_cast<WORD>((static_cast<DWORD_PTR>(l) >> 16) & 0xffff))
#define LOBYTE(w) (static_cast<BYTE>(static_cast<DWORD_PTR>(w) & 0xff))
#define HIBYTE(w) (static_cast<BYTE>((static_cast<DWORD_PTR>(w) >> 8) & 0xff))
#define UNREFERENCED_PARAMETER(P) ((void)(P))

// ---------------------------------------------------------------------------
// MSVC 运行库扩展
// ---------------------------------------------------------------------------
#define _TRUNCATE  (static_cast<size_t>(-1))
#define STRUNCATE  80
//! 与 MSVC 相同的写法：不求值，所以对指针所指结构体的数组成员也能用在常量表达式里
template <typename T, size_t N> char (*__countof_helper(T (&)[N]))[N];
#define _countof(a) (sizeof(*__countof_helper(a)))
#define _HEAP_MAXREQ (static_cast<size_t>(-1) & ~static_cast<size_t>(0x1F))

inline int _stricmp(const char* a, const char* b) { return ::strcasecmp(a, b); }
inline int _strnicmp(const char* a, const char* b, size_t n) { return ::strncasecmp(a, b, n); }
inline int _memicmp(const void* a, const void* b, size_t n) {
	auto p = static_cast<const unsigned char*>(a);
	auto q = static_cast<const unsigned char*>(b);
	for (size_t i = 0; i < n; ++i) {
		const int d = std::tolower(p[i]) - std::tolower(q[i]);
		if (d != 0) return d;
	}
	return 0;
}
inline unsigned short _byteswap_ushort(unsigned short v) { return __builtin_bswap16(v); }
inline unsigned long _byteswap_ulong(unsigned long v) { return __builtin_bswap32(static_cast<std::uint32_t>(v)); }
inline int __iscsym(int c) { return std::isalnum(c) || c == '_'; }

// char 版の _snprintf_s / _scprintf は sakura_core/util/wchar16.h（%S で WCHAR 文字列を扱うため）

// ---------------------------------------------------------------------------
// Win32 API 的替代实现（macos/platform/src/win32_api.cpp）
// 只提供核心代码需要的少数函数，行为与 Windows 相同。
// ---------------------------------------------------------------------------
/* ---- 代码页转换（macos/platform/src/codepage.cpp） ----
 * 单字节/双字节代码页按在 Windows 上导出的转换表（macos/platform/data/codepages.bin）实现，结果与 Windows 一致。
 * UTF-8 由代码实现。UTF-7、GB18030、ISO-2022 系等少数代码页用 iconv 实现。
 * CP_ACP、CP_OEMCP 与 Windows 的“使用 Unicode UTF-8 提供全球语言支持”设置相同，都是 65001。 */
BOOL IsValidCodePage(UINT codePage);
UINT GetACP();
UINT GetOEMCP();
BOOL GetCPInfo(UINT codePage, LPCPINFO lpCPInfo);
BOOL GetCPInfoExW(UINT codePage, DWORD dwFlags, LPCPINFOEXW lpCPInfoEx);
#define GetCPInfoEx GetCPInfoExW
BOOL IsDBCSLeadByteEx(UINT codePage, BYTE testChar);
BOOL IsDBCSLeadByte(BYTE testChar);
BOOL EnumSystemCodePagesW(CODEPAGE_ENUMPROCW lpCodePageEnumProc, DWORD dwFlags);
#define EnumSystemCodePages EnumSystemCodePagesW
int MultiByteToWideChar(UINT codePage, DWORD dwFlags, LPCSTR lpMultiByteStr, int cbMultiByte, WCHAR* lpWideCharStr, int cchWideChar);
int WideCharToMultiByte(UINT codePage, DWORD dwFlags, const WCHAR* lpWideCharStr, int cchWideChar, LPSTR lpMultiByteStr, int cbMultiByte, LPCSTR lpDefaultChar, BOOL* lpUsedDefaultChar);
//! FILETIME（1601-01-01 起的 100 纳秒数，UTC）→ SYSTEMTIME（UTC）
BOOL FileTimeToSystemTime(const FILETIME* lpFileTime, LPSYSTEMTIME lpSystemTime);
//! SYSTEMTIME → FILETIME
BOOL SystemTimeToFileTime(const SYSTEMTIME* lpSystemTime, LPFILETIME lpFileTime);
//! UTC 的 SYSTEMTIME → 本地时间。lpTimeZone 必须是 nullptr（使用当前时区）
BOOL SystemTimeToTzSpecificLocalTime(const void* lpTimeZone, const SYSTEMTIME* lpUniversalTime, LPSYSTEMTIME lpLocalTime);
//! 当前本地时间
void GetLocalTime(LPSYSTEMTIME lpSystemTime);
//! 当前 UTC 时间
void GetSystemTime(LPSYSTEMTIME lpSystemTime);
//! 系统启动后的毫秒数
DWORD GetTickCount();
ULONGLONG GetTickCount64();
//! 暂停指定毫秒
void Sleep(DWORD dwMilliseconds);
//! (a * b) / c，四舍五入。c 为 0 时返回 -1
int MulDiv(int nNumber, int nNumerator, int nDenominator);
//! 向调试输出写字符串（macOS 上写到 stderr 和系统日志）
void OutputDebugStringW(const WCHAR* lpOutputString);
void OutputDebugStringA(const char* lpOutputString);
//! 中断到调试器
void DebugBreak();
//! 原版运行时加载的 DLL（bregonig.dll 等）在 Mac 版是静态链接的。下面三个函数按 DLL 名
//! 找到对应的函数表，未登记的名字返回 nullptr（见 macos/platform/src/static_modules.cpp）
typedef INT_PTR (*FARPROC)();
HMODULE LoadLibraryW(const WCHAR* lpLibFileName);
FARPROC GetProcAddress(HMODULE hModule, const char* lpProcName);
BOOL FreeLibrary(HMODULE hLibModule);
//! 虚拟内存（mem/CPoolResource 用）。只支持 MEM_COMMIT | MEM_RESERVE 分配、MEM_RELEASE 释放整块，
//! 与 Windows 一样返回清零的内存，失败时返回 nullptr（macos/platform/src/win32_api.cpp）
#define MEM_COMMIT     0x00001000
#define MEM_RESERVE    0x00002000
#define MEM_RELEASE    0x00008000
#define PAGE_READWRITE 0x04
LPVOID VirtualAlloc(LPVOID lpAddress, SIZE_T dwSize, DWORD flAllocationType, DWORD flProtect);
BOOL VirtualFree(LPVOID lpAddress, SIZE_T dwSize, DWORD dwFreeType);
//! 等待的超时时间：无限（_main/CMutex 用。Mac 版的 CMutex 是进程内的互斥锁，见 CMutex.h）
#define INFINITE 0xFFFFFFFF
//! 全局内存（剪贴板、拖放等传递数据用。util/os.h 的 cxx::GlobalMemory 使用，第 21 步）
//! 在进程内分配，句柄指向内部的管理信息；GlobalLock 返回数据的地址（不移动，锁计数不管理）
typedef WORD CLIPFORMAT;
#define GMEM_FIXED    0x0000
#define GMEM_MOVEABLE 0x0002
#define GMEM_ZEROINIT 0x0040
#define GHND (GMEM_MOVEABLE | GMEM_ZEROINIT)
#define GPTR (GMEM_FIXED | GMEM_ZEROINIT)
HGLOBAL GlobalAlloc(UINT uFlags, SIZE_T dwBytes);
HGLOBAL GlobalFree(HGLOBAL hMem);
LPVOID GlobalLock(HGLOBAL hMem);
BOOL GlobalUnlock(HGLOBAL hMem);
SIZE_T GlobalSize(HGLOBAL hMem);
//! 最近一次错误码
DWORD GetLastError();
void SetLastError(DWORD dwErrCode);

/* ---- 文件 ---- */
#define ERROR_FILE_NOT_FOUND      2L
#define ERROR_PATH_NOT_FOUND      3L
#define ERROR_GEN_FAILURE         31L
#define ERROR_SHARING_VIOLATION   32L
#define ERROR_FILE_EXISTS         80L
#define ERROR_ALREADY_EXISTS      183L
#define ERROR_FILE_INVALID        1006L
#define ERROR_ACCESS_DENIED       5L
#define ERROR_INVALID_HANDLE      6L
#define ERROR_NOT_ENOUGH_MEMORY   8L
#define ERROR_INVALID_PARAMETER   87L
#define ERROR_INVALID_ADDRESS     487L
#define ERROR_MOD_NOT_FOUND       126L
#define ERROR_PROC_NOT_FOUND      127L
#define ERROR_INSUFFICIENT_BUFFER 122L
#define ERROR_INVALID_FLAGS       1004L
#define ERROR_NO_UNICODE_TRANSLATION 1113L
#define FILE_ATTRIBUTE_READONLY   0x00000001
#define FILE_ATTRIBUTE_HIDDEN     0x00000002
#define FILE_ATTRIBUTE_SYSTEM     0x00000004
#define FILE_ATTRIBUTE_DIRECTORY  0x00000010
#define FILE_ATTRIBUTE_ARCHIVE    0x00000020
#define FILE_ATTRIBUTE_NORMAL     0x00000080
#define INVALID_FILE_ATTRIBUTES   ((DWORD)-1)
//! 文件属性。macOS 上只返回只读、目录、隐藏（文件名以 . 开头）；文件不存在时返回 INVALID_FILE_ATTRIBUTES
DWORD GetFileAttributesW(const WCHAR* lpFileName);
//! 设置文件属性。macOS 上只处理只读属性（写权限），其余属性忽略
BOOL SetFileAttributesW(const WCHAR* lpFileName, DWORD dwFileAttributes);
#define GetFileAttributes GetFileAttributesW
#define SetFileAttributes SetFileAttributesW
/* ---- 文件句柄和文件映射（macos/platform/src/file_api.cpp） ----
 * 共享模式不起作用（见 file_api.cpp 的说明）。CreateFileMappingW 只能映射文件。 */
typedef struct _SECURITY_ATTRIBUTES { DWORD nLength; LPVOID lpSecurityDescriptor; BOOL bInheritHandle; } SECURITY_ATTRIBUTES, *LPSECURITY_ATTRIBUTES;
#define GENERIC_READ    0x80000000u
#define GENERIC_WRITE   0x40000000u
#define GENERIC_ALL     0x10000000u
#define FILE_SHARE_READ   0x00000001
#define FILE_SHARE_WRITE  0x00000002
#define FILE_SHARE_DELETE 0x00000004
#define CREATE_NEW        1
#define CREATE_ALWAYS     2
#define OPEN_EXISTING     3
#define OPEN_ALWAYS       4
#define TRUNCATE_EXISTING 5
#define FILE_FLAG_SEQUENTIAL_SCAN 0x08000000
#define INVALID_FILE_SIZE ((DWORD)0xFFFFFFFF)
#define PAGE_READONLY   0x02
#define FILE_MAP_WRITE  0x0002
#define FILE_MAP_READ   0x0004
#define FILE_MAP_ALL_ACCESS 0x000F001F
HANDLE CreateFileW(const WCHAR* lpFileName, DWORD dwDesiredAccess, DWORD dwShareMode, LPSECURITY_ATTRIBUTES lpSecurityAttributes,
	DWORD dwCreationDisposition, DWORD dwFlagsAndAttributes, HANDLE hTemplateFile);
#define CreateFile CreateFileW
BOOL CloseHandle(HANDLE hObject);
DWORD GetFileSize(HANDLE hFile, LPDWORD lpFileSizeHigh);
BOOL GetFileTime(HANDLE hFile, LPFILETIME lpCreationTime, LPFILETIME lpLastAccessTime, LPFILETIME lpLastWriteTime);
HANDLE CreateFileMappingW(HANDLE hFile, LPSECURITY_ATTRIBUTES lpFileMappingAttributes, DWORD flProtect,
	DWORD dwMaximumSizeHigh, DWORD dwMaximumSizeLow, const WCHAR* lpName);
#define CreateFileMapping CreateFileMappingW
LPVOID MapViewOfFile(HANDLE hFileMappingObject, DWORD dwDesiredAccess, DWORD dwFileOffsetHigh, DWORD dwFileOffsetLow, SIZE_T dwNumberOfBytesToMap);
BOOL UnmapViewOfFile(LPCVOID lpBaseAddress);
//! 检查文件是否存在（mode 0）、能否写（2）、能否读（4）、能否读写（6）。与 MSVC 相同，成功返回 0，失败返回 -1
int _waccess(const WCHAR* path, int mode);
//! 用 UTF-16 的路径和模式打开文件（路径转换为 UTF-8 后调用 fopen）
FILE* _wfopen(const WCHAR* filename, const WCHAR* mode);
/*!
	Shlwapi 的 PathMatchSpecW（第 21 步，类型别扩展名的通配符匹配）。
	pszSpec 可以用 ';' 分隔多个模式；'*' 匹配任意个字符，'?' 匹配一个字符，不区分大小写（ASCII）；
	与 Windows 相同，"*.*" 匹配所有文件名，"xxx.*" 也匹配没有扩展名的 "xxx"。
*/
BOOL PathMatchSpecW(const WCHAR* pszFile, const WCHAR* pszSpec);
#define PathMatchSpec PathMatchSpecW

/* ---- 键盘、绘图的常量（apiwrap/StdApi.h 等头文件用，第 21 步） ---- */
//! 属性表（util/shell.h 的 MyPropertySheet 的参数）。只声明类型，设置对话框的步骤再定义
typedef struct _PROPSHEETHEADERW* LPPROPSHEETHEADERW;
typedef LPPROPSHEETHEADERW LPPROPSHEETHEADER;
//! 用纸大小和方向（wingdi.h 的值。打印设置保存在 sakura.ini 里，要与 Windows 版相同；第 21 步）
#define DMORIENT_PORTRAIT  1
#define DMORIENT_LANDSCAPE 2
#define DMPAPER_LETTER 1
#define DMPAPER_LETTERSMALL 2
#define DMPAPER_TABLOID 3
#define DMPAPER_LEDGER 4
#define DMPAPER_LEGAL 5
#define DMPAPER_STATEMENT 6
#define DMPAPER_EXECUTIVE 7
#define DMPAPER_A3 8
#define DMPAPER_A4 9
#define DMPAPER_A4SMALL 10
#define DMPAPER_A5 11
#define DMPAPER_B4 12
#define DMPAPER_B5 13
#define DMPAPER_FOLIO 14
#define DMPAPER_QUARTO 15
#define DMPAPER_10X14 16
#define DMPAPER_11X17 17
#define DMPAPER_NOTE 18
#define DMPAPER_ENV_9 19
#define DMPAPER_ENV_10 20
#define DMPAPER_ENV_11 21
#define DMPAPER_ENV_12 22
#define DMPAPER_ENV_14 23
#define DMPAPER_CSHEET 24
#define DMPAPER_DSHEET 25
#define DMPAPER_ESHEET 26
#define DMPAPER_ENV_DL 27
#define DMPAPER_ENV_C5 28
#define DMPAPER_ENV_C3 29
#define DMPAPER_ENV_C4 30
#define DMPAPER_ENV_C6 31
#define DMPAPER_ENV_C65 32
#define DMPAPER_ENV_B4 33
#define DMPAPER_ENV_B5 34
#define DMPAPER_ENV_B6 35
#define DMPAPER_ENV_ITALY 36
#define DMPAPER_ENV_MONARCH 37
#define DMPAPER_ENV_PERSONAL 38
#define DMPAPER_FANFOLD_US 39
#define DMPAPER_FANFOLD_STD_GERMAN 40
#define DMPAPER_FANFOLD_LGL_GERMAN 41
#define ETO_OPAQUE  0x0002
#define ETO_CLIPPED 0x0004
/*
	GDI 函数的声明（uiparts/CGraphics.h 的内联函数引用它们）。
	第 21 步只需要头文件能编译（设置模块通过 view/colors/CColorStrategy.h 间接包含 CGraphics.h），
	这些函数不会被调用，也还没有实现；第 28 步（Core Text 绘制）实现。
*/
#define HGDI_ERROR  (reinterpret_cast<HGDIOBJ>(static_cast<intptr_t>(-1)))
#define PATCOPY     0x00F00021
#define TRANSPARENT 1
#define OPAQUE      2
#define PS_SOLID    0
HGDIOBJ SelectObject(HDC hdc, HGDIOBJ h);
BOOL DeleteObject(HGDIOBJ ho);
BOOL PatBlt(HDC hdc, int x, int y, int w, int h, DWORD rop);
HBRUSH GetSysColorBrush(int nIndex);
HBRUSH CreateSolidBrush(COLORREF color);
int SetBkMode(HDC hdc, int mode);
BOOL MoveToEx(HDC hdc, int x, int y, LPPOINT lppt);
BOOL LineTo(HDC hdc, int x, int y);
COLORREF SetPixel(HDC hdc, int x, int y, COLORREF color);
BOOL ExtTextOutW(HDC hdc, int x, int y, UINT options, const RECT* lprect, const WCHAR* lpString, UINT c, const INT* lpDx);
#define ExtTextOut ExtTextOutW
//! 虚拟键码（与 Windows 相同的值。按键分配的设置里保存这些值，sakura.ini 要与 Windows 版相同）
#define VK_LBUTTON  0x01
#define VK_RBUTTON  0x02
#define VK_MBUTTON  0x04
#define VK_XBUTTON1 0x05
#define VK_XBUTTON2 0x06
#define VK_BACK     0x08
#define VK_TAB      0x09
#define VK_RETURN   0x0D
#define VK_SHIFT    0x10
#define VK_CONTROL  0x11
#define VK_MENU     0x12
#define VK_ESCAPE   0x1B
#define VK_SPACE    0x20
#define VK_PRIOR    0x21
#define VK_NEXT     0x22
#define VK_END      0x23
#define VK_HOME     0x24
#define VK_LEFT     0x25
#define VK_UP       0x26
#define VK_RIGHT    0x27
#define VK_DOWN     0x28
#define VK_INSERT   0x2D
#define VK_DELETE   0x2E
#define VK_APPS     0x5D
#define VK_F1  0x70
#define VK_F2  0x71
#define VK_F3  0x72
#define VK_F4  0x73
#define VK_F5  0x74
#define VK_F6  0x75
#define VK_F7  0x76
#define VK_F8  0x77
#define VK_F9  0x78
#define VK_F10 0x79
#define VK_F11 0x7A
#define VK_F12 0x7B
#define VK_F13 0x7C
#define VK_F14 0x7D
#define VK_F15 0x7E
#define VK_F16 0x7F
#define VK_F17 0x80
#define VK_F18 0x81
#define VK_F19 0x82
#define VK_F20 0x83
#define VK_F21 0x84
#define VK_F22 0x85
#define VK_F23 0x86
#define VK_F24 0x87
//! 按键状态。核心库里没有键盘，总是返回 0（没有按下）；界面层以后用 NSEvent 的修饰键实现（macos/platform/src/ui_bridge.cpp）
SHORT GetKeyState(int nVirtKey);

/* ---- 工具栏按钮（uiparts/CMenuDrawer 的按钮表。工具栏的设置按这个表的序号保存在 sakura.ini 里，第 21 步） ---- */
typedef struct _TBBUTTON {
	int iBitmap;
	int idCommand;
	BYTE fsState;
	BYTE fsStyle;
	BYTE bReserved[6];
	DWORD_PTR dwData;
	INT_PTR iString;
} TBBUTTON, *PTBBUTTON, *LPTBBUTTON;
#define TBSTATE_CHECKED  0x01
#define TBSTATE_ENABLED  0x04
#define TBSTATE_WRAP     0x20
#define TBSTYLE_BUTTON   0x0000
#define TBSTYLE_SEP      0x0001
#define TBSTYLE_DROPDOWN 0x0008

/* ---- 资源（macos/platform/src/resources.cpp，第 21 步） ----
 * 用户定义类型的资源（MainMenu.ini 等）在构建时由 macos/tools/rc_strings.py 嵌入核心库。
 * 模块句柄忽略（只有 sakura 本身的资源）。名字和类型只支持数字（MAKEINTRESOURCE）。 */
SAKURA_DECLARE_HANDLE(HRSRC);
#define MAKEINTRESOURCEW(i) (reinterpret_cast<LPWSTR>(static_cast<ULONG_PTR>(static_cast<WORD>(i))))
#define MAKEINTRESOURCE MAKEINTRESOURCEW
#define IS_INTRESOURCE(r) ((reinterpret_cast<ULONG_PTR>(r) >> 16) == 0)
HRSRC FindResourceW(HMODULE hModule, LPCWSTR lpName, LPCWSTR lpType);
#define FindResource FindResourceW
HGLOBAL LoadResource(HMODULE hModule, HRSRC hResInfo);
LPVOID LockResource(HGLOBAL hResData);
DWORD SizeofResource(HMODULE hModule, HRSRC hResInfo);

/* ---- BSTR 和 VARIANT（macos/platform/src/ole_types.cpp） ----
 * 原版宏接口（_os/OleTypes.h、macro/）传值用的 COM 类型。数据结构与 Windows 相同：
 * BSTR 前面 4 字节是字节数，后面以 0 结尾。VARIANT 只包含原版用到的类型。 */
typedef WCHAR*        BSTR;
typedef unsigned short VARTYPE;
typedef short         VARIANT_BOOL;
enum VARENUM : VARTYPE {
	VT_EMPTY = 0, VT_NULL = 1, VT_I2 = 2, VT_I4 = 3, VT_R8 = 5, VT_BSTR = 8, VT_BOOL = 11,
	VT_VARIANT = 12, VT_UI4 = 19, VT_INT = 22, VT_UINT = 23, VT_BYREF = 0x4000,
};
typedef struct tagVARIANT {
	VARTYPE vt;
	WORD wReserved1, wReserved2, wReserved3;
	union {
		LONG          lVal;
		short         iVal;
		INT           intVal;
		UINT          uintVal;
		ULONG         ulVal;
		VARIANT_BOOL  boolVal;
		double        dblVal;
		BSTR          bstrVal;
		struct tagVARIANT* pvarVal;
		void*         byref;
	};
} VARIANT, VARIANTARG, *LPVARIANT;
#define E_INVALIDARG    static_cast<HRESULT>(0x80070057L)
#define E_OUTOFMEMORY   static_cast<HRESULT>(0x8007000EL)
#define DISP_E_BADVARTYPE static_cast<HRESULT>(0x80020008L)
BSTR SysAllocString(const OLECHAR* psz);
BSTR SysAllocStringLen(const OLECHAR* strIn, UINT ui);
INT  SysReAllocString(BSTR* pbstr, const OLECHAR* psz);
UINT SysStringLen(BSTR pbstr);
void SysFreeString(BSTR bstrString);
void VariantInit(VARIANTARG* pvarg);
HRESULT VariantClear(VARIANTARG* pvarg);
HRESULT VariantCopy(VARIANTARG* pvargDest, const VARIANTARG* pvargSrc);
HRESULT VariantCopyInd(VARIANT* pvarDest, const VARIANTARG* pvargSrc);

#endif /* SAKURA_PLATFORM_H_ */
