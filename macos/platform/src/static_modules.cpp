/*! @file
	@brief 静态链接的“DLL”：LoadLibraryW / GetProcAddress / FreeLibrary 的 Mac 版

	原版在运行时加载 bregonig.dll（正则）等 DLL，用 CDllImp（sakura_core/extmodule/CDllHandler）
	按函数名取得入口地址。Mac 版不加载动态库，而是把这些库作为源码编进来，
	在这里按 DLL 的文件名找到静态链接的函数表。这样 sakura_core/extmodule 的代码不用改。

	只认识下面 g_modules 里登记的 DLL 名（不区分大小写，忽略目录部分）：
	  bregonig.dll（正则，Onigmo + bregonig）、migemo.dll（C/Migemo）。
	其他名字返回 nullptr，和 Windows 上找不到 DLL 时一样。uchardet.dll 也不登记：
	Windows 官方版不附带 uchardet，编码自动识别不用它，Mac 版保持相同（2026-11-09 项目负责人决定）。
*/
/*
	Copyright (C) 2026, Sakura Editor Organization

	SPDX-License-Identifier: Zlib
*/
#include "sakura_platform.h"

#include "migemo.h"

#include <cstring>
#include <mutex>
#include <string_view>

// ---- bregonig（macos/core/CMakeLists.txt 的 bregonig 目标）----
struct bregexp;
extern "C" {
int BMatchW(char16_t* str, char16_t* target, char16_t* targetendp, bregexp** rxp, char16_t* msg);
int BSubstW(char16_t* str, char16_t* target, char16_t* targetendp, bregexp** rxp, char16_t* msg);
int BTransW(char16_t* str, char16_t* target, char16_t* targetendp, bregexp** rxp, char16_t* msg);
int BSplitW(char16_t* str, char16_t* target, char16_t* targetendp, int limit, bregexp** rxp, char16_t* msg);
void BRegfreeW(bregexp* rx);
char16_t* BRegexpVersionW();
int BMatchExW(char16_t* str, char16_t* targetbegp, char16_t* target, char16_t* targetendp, bregexp** rxp, char16_t* msg);
int BSubstExW(char16_t* str, char16_t* targetbegp, char16_t* target, char16_t* targetendp, bregexp** rxp, char16_t* msg);
//! bregonig.cpp 的 DllMain。DLL_PROCESS_ATTACH 时初始化 Perl 兼容语法（OnigSyntaxPerl_NG_EX）
int DllMain(void* hinstDLL, std::uint32_t fdwReason, void* lpvReserved);
}

namespace {

struct ExportEntry {
	const char* name;
	FARPROC     proc;
};

struct StaticModule {
	std::u16string_view  dllName;     //!< 小写
	const ExportEntry*   exports;     //!< {nullptr, nullptr} 结尾
	void               (*attach)();   //!< 第一次加载时调用一次（相当于 DLL_PROCESS_ATTACH）
	std::once_flag*      attachOnce;
};

template<typename F>
FARPROC ToProc(F* f)
{
	return reinterpret_cast<FARPROC>(f);
}

const ExportEntry g_bregonigExports[] = {
	{ "BMatchW",         ToProc(&BMatchW) },
	{ "BSubstW",         ToProc(&BSubstW) },
	{ "BTransW",         ToProc(&BTransW) },
	{ "BSplitW",         ToProc(&BSplitW) },
	{ "BRegfreeW",       ToProc(&BRegfreeW) },
	{ "BRegexpVersionW", ToProc(&BRegexpVersionW) },
	{ "BMatchExW",       ToProc(&BMatchExW) },
	{ "BSubstExW",       ToProc(&BSubstExW) },
	{ nullptr, nullptr }
};

void AttachBregonig()
{
	constexpr std::uint32_t DLL_PROCESS_ATTACH_ = 1;
	DllMain(nullptr, DLL_PROCESS_ATTACH_, nullptr);
}

std::once_flag g_bregonigOnce;

// C/Migemo（macos/core/CMakeLists.txt 的 cmigemo 目标）。与 migemo.def 导出的函数相同
const ExportEntry g_migemoExports[] = {
	{ "migemo_open",             ToProc(&migemo_open) },
	{ "migemo_close",            ToProc(&migemo_close) },
	{ "migemo_query",            ToProc(&migemo_query) },
	{ "migemo_release",          ToProc(&migemo_release) },
	{ "migemo_set_operator",     ToProc(&migemo_set_operator) },
	{ "migemo_get_operator",     ToProc(&migemo_get_operator) },
	{ "migemo_setproc_char2int", ToProc(&migemo_setproc_char2int) },
	{ "migemo_setproc_int2char", ToProc(&migemo_setproc_int2char) },
	{ "migemo_load",             ToProc(&migemo_load) },
	{ "migemo_is_enable",        ToProc(&migemo_is_enable) },
	{ nullptr, nullptr }
};

const StaticModule g_modules[] = {
	{ u"bregonig.dll", g_bregonigExports, &AttachBregonig, &g_bregonigOnce },
	{ u"migemo.dll",   g_migemoExports,   nullptr,         nullptr },
};

//! 取出文件名部分并转成小写（ASCII）
std::u16string BaseNameLower(const WCHAR* path)
{
	std::u16string_view s(path);
	if (const auto pos = s.find_last_of(u"/\\"); pos != std::u16string_view::npos) {
		s.remove_prefix(pos + 1);
	}
	std::u16string r(s);
	for (auto& c : r) {
		if (c >= u'A' && c <= u'Z') c = static_cast<char16_t>(c - u'A' + u'a');
	}
	return r;
}

const StaticModule* FromHandle(HMODULE h)
{
	for (const auto& m : g_modules) {
		if (reinterpret_cast<const void*>(&m) == reinterpret_cast<const void*>(h)) return &m;
	}
	return nullptr;
}

} // namespace

HMODULE LoadLibraryW(const WCHAR* lpLibFileName)
{
	if (!lpLibFileName) {
		SetLastError(ERROR_INVALID_PARAMETER);
		return nullptr;
	}
	const auto name = BaseNameLower(lpLibFileName);
	for (const auto& m : g_modules) {
		if (m.dllName == name) {
			if (m.attach) std::call_once(*m.attachOnce, m.attach);
			return reinterpret_cast<HMODULE>(const_cast<StaticModule*>(&m));
		}
	}
	SetLastError(ERROR_MOD_NOT_FOUND);
	return nullptr;
}

FARPROC GetProcAddress(HMODULE hModule, const char* lpProcName)
{
	const StaticModule* m = FromHandle(hModule);
	if (!m || !lpProcName) {
		SetLastError(ERROR_INVALID_HANDLE);
		return nullptr;
	}
	for (const ExportEntry* e = m->exports; e->name; ++e) {
		if (std::strcmp(e->name, lpProcName) == 0) return e->proc;
	}
	SetLastError(ERROR_PROC_NOT_FOUND);
	return nullptr;
}

BOOL FreeLibrary(HMODULE hLibModule)
{
	// 静态链接，没有要释放的东西。和 Windows 一样，未知的句柄返回 FALSE
	if (!FromHandle(hLibModule)) {
		SetLastError(ERROR_INVALID_HANDLE);
		return FALSE;
	}
	return TRUE;
}
