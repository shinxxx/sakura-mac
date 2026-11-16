/*! @file
	@brief 排版（doc/layout）在 Mac 版用到的、属于窗口的部分的替代（计划第 27 步）

	- DpiScaleX / DpiScaleY（util/window.cpp）：把设置里的像素数（文字间隔等）按屏幕的 DPI 放大。
	  Mac 版的坐标单位是“点”，高分辨率屏幕由系统放大，所以照原样返回（相当于 Windows 的 96 DPI）。
	- BlockingHook（util/window.cpp）：大文件排版时处理窗口消息，让进度条和取消按钮能动。
	  Mac 版核心库不显示进度（CLayoutMgr 没有登记 CProgressListener），不会调用到；
	  为了链接提供一个什么也不做、总是“继续”的版本。

	第 27 步到第 32 步这里还有一个没有色分け的 CColorStrategyPool，
	第 33 步移植了原版的色分け（view/colors），已经删除（见 color_support.cpp）。
*/
/*
	Copyright (C) 2026, Sakura Editor Organization

	SPDX-License-Identifier: Zlib
*/
#include "StdAfx.h"
#include "util/window.h"

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
