/*! @file
	@brief アウトライン解析的结果的整理（计划第 42 步）。说明见 OutlineView.cpp
*/
/*
	Copyright (C) 2026, Sakura Editor Organization

	SPDX-License-Identifier: Zlib
*/
#pragma once

#include "sakura_core/SakuraCore.h"

class CFuncInfoArr;

namespace sakura::core {

/*!
	解析结果做成 OutlineResult（原版 CDlgFuncList::SetData）。
	@param nOutlineType  解析方法（EOutlineType）
	@param nListType     一覧的形式（原版 m_nListType）
	@param titleOverride ルールファイル 的「Title=」（空时用原版的标题）
	@param sortType, sortCol, sortDesc タイプ別設定 的 nOutlineSortType、nOutlineSortCol、bOutlineSortDesc
*/
OutlineResult BuildOutlineView(CFuncInfoArr& arr, int nOutlineType, int nListType, const Text& titleOverride,
							   bool lineNumIsCRLF, int sortType, int sortCol, bool sortDesc);

} // namespace sakura::core
