/*! @file
	@brief 原版 src/test/cpp/tests1/window/EditorTestSuite.hpp、TrayWndTestSuite.hpp 的 Mac 版（计划第 21 步）

	原版的 EditorTestSuite 建立共通设置之后，还建立编辑窗口（CEditWnd）、文档和各个代理。
	Mac 版还没有编辑窗口（第 26 步窗口框架之后），这里只建立共通设置（env::ShareDataTestSuite，与原版相同）。
	原版的 TrayWndTestSuite 建立共通设置之后还建立任务栏托盘窗口（CControlTray），Mac 版同样只建立共通设置。
	原版测试里 #include "window/EditorTestSuite.hpp"、"window/TrayWndTestSuite.hpp" 的地方，Mac 版改为包含这个文件。
	（第 20 步时用的是 mac-share-data.hpp 里同名的类，只设置了一部分默认值；第 21 步换成真正的 InitShareData）
*/
/*
	Copyright (C) 2026, Sakura Editor Organization

	SPDX-License-Identifier: Zlib
*/
#pragma once

#include "env/ShareDataTestSuite.hpp"

namespace window {

struct EditorTestSuite : public env::ShareDataTestSuite
{
	static void SetUpEditor() { SetUpShareData(); }
	static void TearDownEditor() { TearDownShareData(); }
};

struct TrayWndTestSuite : public env::ShareDataTestSuite
{
	static void SetUpTrayWnd() { SetUpShareData(); }
	static void TearDownTrayWnd() { TearDownShareData(); }
};

} // namespace window
