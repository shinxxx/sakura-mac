/*! @file
	@brief 测试用的共通设置（计划第 20 步，第 21 步移植 env 后删除）

	说明见 mac-share-data.hpp。另外，util/file.cpp 也要到第 21 步才移植，
	第 20 步编进核心库的 parse/DetectIndentationStyle 用到的 fexist 先在这里按原版的写法实现。
*/
/*
	Copyright (C) 2026, Sakura Editor Organization

	SPDX-License-Identifier: Zlib
*/
#include "pch.h"
#include "mac-share-data.hpp"
#include "util/file.h"
#include "env/CShareData.h"

#include <memory>
#include <stdexcept>

namespace {

std::unique_ptr<DLLSHAREDATA> g_pShareData;

} // namespace

namespace mac_test {

DLLSHAREDATA& SetUpShareData()
{
	if (!g_pShareData) {
		// 与原版一样：共享内存一开始是清零的，再调用默认构造（CShareData::InitShareData 的 placement new）
		g_pShareData = std::make_unique<DLLSHAREDATA>();
		auto& common = g_pShareData->m_Common;
		// 第 20 步的代码用到的项目里，原版默认值不是 0 的（env/CShareData.cpp 的 InitShareData）
		wcscpy(common.m_sFormat.m_szMidashiKigou, LTEXT("１２３４５６７８９０（(［[「『【■□▲△▼▽◆◇○◎●§・※☆★第①②③④⑤⑥⑦⑧⑨⑩⑪⑫⑬⑭⑮⑯⑰⑱⑲⑳ⅠⅡⅢⅣⅤⅥⅦⅧⅨⅩ一二三四五六七八九十壱弐参伍"));
	}
	return *g_pShareData;
}

void TearDownShareData()
{
	g_pShareData.reset();
}

} // namespace mac_test

// 原版 env/CShareData.cpp
DLLSHAREDATA* GetDllShareDataPtr() noexcept
{
	return g_pShareData.get();
}

// 原版 env/DLLSHAREDATA.cpp
DLLSHAREDATA& GetDllShareData()
{
	auto pShareData = GetDllShareDataPtr();
	if (!pShareData) {
		throw std::domain_error("DLLSHAREDATA is not initialized");
	}
	return *pShareData;
}

// 原版 util/file.cpp
bool fexist(LPCWSTR pszPath)
{
	return _waccess(pszPath, 0) != -1;
}

bool fexist(const std::filesystem::path& path) noexcept
{
	std::error_code ec;
	return std::filesystem::exists(path, ec);
}

// 原版 env/CShareData.cpp（类型别设置的默认值里用到）
void CShareData::InitFileTree(SFileTree* setting)
{
	setting->m_bProject = true;
	for (int i = 0; i < int(std::size(setting->m_aItems)); i++) {
		SFileTreeItem& item = setting->m_aItems[i];
		item.m_eFileTreeItemType = EFileTreeItemType_Grep;
		item.m_szTargetPath = LTEXT("");
		item.m_szLabelName = LTEXT("");
		item.m_szTargetPath = LTEXT("");
		item.m_nDepth = 0;
		item.m_szTargetFile = LTEXT("");
		item.m_bIgnoreHidden = true;
		item.m_bIgnoreReadOnly = false;
		item.m_bIgnoreSystem = false;
	}
	setting->m_nItemCount = 1;
	setting->m_aItems[0].m_szTargetPath = LTEXT(".");
	setting->m_aItems[0].m_szTargetFile = LTEXT("*.*");
}

// ---------------------------------------------------------------------------
// 大纲解析（types/CType_*.cpp 里的 CDocOutline::MakeFuncList_* 等）用到、但第 20 步还没有的函数。
// 大纲解析要把行号换算成排版位置（doc/layout，第 27 步），判断扩展名用 util/file（第 21 步）。
// 这些函数和类型的默认设置在同一个目标文件里，为了能链接，这里先放一个调用就报告失败的版本。
// 第 20 步的测试不调用大纲解析。
// ---------------------------------------------------------------------------
#include "doc/layout/CLayoutMgr.h"

void CLayoutMgr::LogicToLayout(const CLogicPoint& ptLogic, CLayoutPoint* pptLayout, CLayoutInt nLineHint)
{
	(void)ptLogic; (void)nLineHint;
	ADD_FAILURE() << "CLayoutMgr::LogicToLayout is ported in plan step 27";
	*pptLayout = CLayoutPoint(CLayoutInt(0), CLayoutInt(0));
}

BOOL CheckEXT(const WCHAR* pszPath, const WCHAR* pszExt)
{
	(void)pszPath; (void)pszExt;
	ADD_FAILURE() << "CheckEXT (util/file.cpp) is ported in plan step 21";
	return FALSE;
}
