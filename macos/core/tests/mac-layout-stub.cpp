/*! @file
	@brief 排版（doc/layout）移植之前，测试用的临时函数（计划第 20 步加入，第 27 步删除）

	大纲解析（types/CType_*.cpp 里的 CDocOutline::MakeFuncList_* 等）要把行号换算成排版位置，
	用到 CLayoutMgr::LogicToLayout。排版是第 27 步，这里先放一个调用就报告失败的版本，
	使类型的默认设置（与大纲解析在同一个目标文件里）能够链接。测试不调用大纲解析的这一部分。

	第 20 步时这个函数在 mac-share-data.cpp 里；第 21 步移植 env 后，那个文件删除，只留下这一部分。
*/
/*
	Copyright (C) 2026, Sakura Editor Organization

	SPDX-License-Identifier: Zlib
*/
#include "pch.h"
#include "doc/layout/CLayoutMgr.h"

void CLayoutMgr::LogicToLayout(const CLogicPoint& ptLogic, CLayoutPoint* pptLayout, CLayoutInt nLineHint)
{
	(void)ptLogic; (void)nLineHint;
	ADD_FAILURE() << "CLayoutMgr::LogicToLayout is ported in plan step 27";
	*pptLayout = CLayoutPoint(CLayoutInt(0), CLayoutInt(0));
}
