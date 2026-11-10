/*! @file
	@brief BSTR 和 VARIANT 的替代实现（非 Windows 平台，阶段 1 第 20 步）

	原版宏接口（_os/OleTypes.h、macro/）使用的 COM 字符串和可变类型。
	BSTR 的内存布局与 Windows 相同：前面 4 字节是字节数（不含结尾的 0），后面是 UTF-16 字符串和结尾的 0。
	VariantChangeType 等宏执行时才用到的函数，在宏的步骤里加入。

	Copyright (C) 2026, Sakura Editor Organization
	SPDX-License-Identifier: Zlib
*/
#include "StdAfx.h"

#include <cstdlib>
#include <cstring>

namespace {

constexpr size_t kPrefix = sizeof(std::uint32_t);

std::uint32_t* Header(BSTR bstr)
{
	return reinterpret_cast<std::uint32_t*>(reinterpret_cast<char*>(bstr) - kPrefix);
}

} // namespace

BSTR SysAllocStringLen(const OLECHAR* strIn, UINT ui)
{
	const size_t bytes = static_cast<size_t>(ui) * sizeof(OLECHAR);
	auto* p = static_cast<char*>(std::malloc(kPrefix + bytes + sizeof(OLECHAR)));
	if (!p) return nullptr;
	*reinterpret_cast<std::uint32_t*>(p) = static_cast<std::uint32_t>(bytes);
	auto* str = reinterpret_cast<BSTR>(p + kPrefix);
	if (strIn) {
		std::memcpy(str, strIn, bytes);
	} else {
		std::memset(str, 0, bytes);
	}
	str[ui] = 0;
	return str;
}

BSTR SysAllocString(const OLECHAR* psz)
{
	if (!psz) return nullptr;
	return SysAllocStringLen(psz, static_cast<UINT>(std::char_traits<OLECHAR>::length(psz)));
}

INT SysReAllocString(BSTR* pbstr, const OLECHAR* psz)
{
	if (!pbstr) return FALSE;
	BSTR newStr = SysAllocString(psz);
	if (psz && !newStr) return FALSE;
	SysFreeString(*pbstr);
	*pbstr = newStr;
	return TRUE;
}

UINT SysStringLen(BSTR pbstr)
{
	return pbstr ? static_cast<UINT>(*Header(pbstr) / sizeof(OLECHAR)) : 0;
}

void SysFreeString(BSTR bstrString)
{
	if (bstrString) std::free(Header(bstrString));
}

void VariantInit(VARIANTARG* pvarg)
{
	if (!pvarg) return;
	std::memset(pvarg, 0, sizeof(*pvarg));
	pvarg->vt = VT_EMPTY;
}

HRESULT VariantClear(VARIANTARG* pvarg)
{
	if (!pvarg) return E_INVALIDARG;
	if (pvarg->vt == VT_BSTR) SysFreeString(pvarg->bstrVal);
	VariantInit(pvarg);
	return S_OK;
}

HRESULT VariantCopy(VARIANTARG* pvargDest, const VARIANTARG* pvargSrc)
{
	if (!pvargDest || !pvargSrc) return E_INVALIDARG;
	if (pvargDest == pvargSrc) return S_OK;
	VariantClear(pvargDest);
	*pvargDest = *pvargSrc;
	if (pvargSrc->vt == VT_BSTR && pvargSrc->bstrVal) {
		pvargDest->bstrVal = SysAllocStringLen(pvargSrc->bstrVal, SysStringLen(pvargSrc->bstrVal));
		if (!pvargDest->bstrVal) { VariantInit(pvargDest); return E_OUTOFMEMORY; }
	}
	return S_OK;
}

HRESULT VariantCopyInd(VARIANT* pvarDest, const VARIANTARG* pvargSrc)
{
	if (!pvargSrc) return E_INVALIDARG;
	if ((pvargSrc->vt & VT_BYREF) == 0) {
		// 原版的 Variant 构造函数对未初始化的目标调用 VariantCopyInd，所以这里不先清除目标
		VariantInit(pvarDest);
		return VariantCopy(pvarDest, pvargSrc);
	}
	if (pvargSrc->vt == (VT_BYREF | VT_VARIANT)) {
		return VariantCopyInd(pvarDest, pvargSrc->pvarVal);
	}
	return DISP_E_BADVARTYPE;
}
