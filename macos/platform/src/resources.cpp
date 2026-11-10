/*! @file
	@brief 资源的读取（FindResource、LoadResource 等，计划第 21 步）

	原版用 FindResource / LoadResource 读取 exe 里的用户定义资源，例如主菜单的默认设置
	（IDR_MENU1，类型 ID_RC_TYPE_INI，内容是 src/main/resources/MainMenu.ini）。
	Mac 版在构建时由 macos/tools/rc_strings.py 把这些文件的内容嵌入核心库（g_sakuraResourceData），
	这里按类型和 ID 查找。返回的句柄就是表里那一项的地址，数据只读，不需要释放（与 Windows 相同）。

	Copyright (C) 2026, Sakura Editor Organization
	SPDX-License-Identifier: Zlib
*/
#include "StdAfx.h"

#include <cstddef>

// 构建时由 macos/tools/rc_strings.py 生成
struct SakuraResourceData { unsigned int type; unsigned int id; const unsigned char* data; std::size_t size; };
extern const SakuraResourceData g_sakuraResourceData[];
extern const std::size_t g_sakuraResourceDataCount;

HRSRC FindResourceW(HMODULE /* hModule */, LPCWSTR lpName, LPCWSTR lpType)
{
	// 名字为字符串的资源原版没有使用
	if (!IS_INTRESOURCE(lpName) || !IS_INTRESOURCE(lpType)) {
		SetLastError(ERROR_INVALID_PARAMETER);
		return nullptr;
	}
	const auto id = static_cast<unsigned int>(reinterpret_cast<ULONG_PTR>(lpName));
	const auto type = static_cast<unsigned int>(reinterpret_cast<ULONG_PTR>(lpType));
	for (std::size_t i = 0; i < g_sakuraResourceDataCount; ++i) {
		const auto& entry = g_sakuraResourceData[i];
		if (entry.type == type && entry.id == id) {
			return reinterpret_cast<HRSRC>(const_cast<SakuraResourceData*>(&entry));
		}
	}
	SetLastError(1813L);	// ERROR_RESOURCE_TYPE_NOT_FOUND
	return nullptr;
}

HGLOBAL LoadResource(HMODULE /* hModule */, HRSRC hResInfo)
{
	return reinterpret_cast<HGLOBAL>(hResInfo);
}

LPVOID LockResource(HGLOBAL hResData)
{
	if (!hResData) return nullptr;
	const auto& entry = *reinterpret_cast<const SakuraResourceData*>(hResData);
	return const_cast<unsigned char*>(entry.data);
}

DWORD SizeofResource(HMODULE /* hModule */, HRSRC hResInfo)
{
	if (!hResInfo) return 0;
	const auto& entry = *reinterpret_cast<const SakuraResourceData*>(hResInfo);
	return static_cast<DWORD>(entry.size);
}
