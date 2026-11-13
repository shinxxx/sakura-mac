/*! @file
	@brief 排版（doc/layout）移植之前的临时函数（计划第 20 步加入，第 27 步删除）

	大纲解析（types/CType_*.cpp 里的 CDocOutline::MakeFuncList_* 等）要把行号换算成排版位置，
	用到 CLayoutMgr::LogicToLayout。排版是第 27 步，这里先放一个不折行的版本：
	排版位置与逻辑位置相同（行号、列都不变）。

	第 20、21 步时这个函数放在测试里（macos/core/tests/mac-layout-stub.cpp）；
	第 24 步 App 也要链接核心库，所以移到核心库里，否则 App 链接时找不到这个函数。
*/
/*
	Copyright (C) 2026, Sakura Editor Organization

	SPDX-License-Identifier: Zlib
*/
#include "StdAfx.h"
#include "doc/layout/CLayoutMgr.h"

void CLayoutMgr::LogicToLayout(const CLogicPoint& ptLogic, CLayoutPoint* pptLayout, CLayoutInt nLineHint)
{
	(void)nLineHint;
	*pptLayout = CLayoutPoint(CLayoutInt(ptLogic.GetX2()), CLayoutInt(ptLogic.GetY2()));
}
