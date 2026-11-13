/*! @file
	@brief 排版（doc/layout）在 Mac 版用到的、还没有移植的部分的替代（计划第 27 步）

	原版的排版（CLayoutMgr）除了文字宽度，还用到两样属于编辑画面的东西：

	- 色分け（view/colors 的 CColorStrategyPool）：排版时顺便记下每一排版行开头的
	  注释、引号的状态（CLayout::GetColorTypePrev），绘制时用。换行的位置不受影响。
	  色分け依赖编辑画面（CEditView），在第 33 步（语法颜色）与绘制一起移植。
	  在那之前这里的 CColorStrategyPool 没有任何色分け（与原版关掉所有色分け时相同），
	  排版行的颜色状态都是 COLORIDX_DEFAULT。
	- DpiScaleX / DpiScaleY（util/window.cpp）：把设置里的像素数（文字间隔等）按屏幕的 DPI 放大。
	  Mac 版的坐标单位是“点”，高分辨率屏幕由系统放大，所以照原样返回（相当于 Windows 的 96 DPI）。
	- BlockingHook（util/window.cpp）：大文件排版时处理窗口消息，让进度条和取消按钮能动。
	  Mac 版核心库不显示进度（CLayoutMgr 没有登记 CProgressListener），不会调用到；
	  为了链接提供一个什么也不做、总是“继续”的版本。

	第 33 步移植 view/colors 时删除这个文件里的 CColorStrategyPool。
*/
/*
	Copyright (C) 2026, Sakura Editor Organization

	SPDX-License-Identifier: Zlib
*/
#include "StdAfx.h"
#include "view/colors/CColorStrategy.h"
#include "util/window.h"

CColorStrategyPool::CColorStrategyPool() = default;
CColorStrategyPool::~CColorStrategyPool() = default;

CColorStrategy* CColorStrategyPool::GetStrategyByColor(EColorIndexType /* eColor */) const
{
	return nullptr;
}

void CColorStrategyPool::CheckColorMODE(CColorStrategy** ppcColorStrategy, int /* nPos */, const CStringRef& /* cLineStr */)
{
	*ppcColorStrategy = nullptr;
}

bool CColorStrategyPool::HasRangeBasedColorStrategies() const noexcept
{
	return false;
}

LONG DpiScaleX(LONG x)
{
	return x;
}

LONG DpiScaleY(LONG y)
{
	return y;
}

BOOL BlockingHook(HWND /* hwndDlgCancel */)
{
	return TRUE;
}
