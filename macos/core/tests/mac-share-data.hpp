/*! @file
	@brief 测试用的共通设置（计划第 20 步，第 21 步移植 env 后删除）

	原版的共通设置（DLLSHAREDATA）放在进程间共享内存里，由 env/CShareData 建立并设置默认值。
	env 要到第 21 步才移植，在那之前，第 20 步编进核心库的代码（查找、读文件、大纲解析等）
	需要的 GetDllShareData() 由这里提供：一个进程内的 DLLSHAREDATA，与原版共享内存一样先清零，
	再把用到的项目设成原版 CShareData::InitShareData 的默认值。

	原版测试用的 window::EditorTestSuite 要建立编辑窗口，Mac 版还没有窗口，
	这里提供同名的类，只建立共通设置。
*/
/*
	Copyright (C) 2026, Sakura Editor Organization

	SPDX-License-Identifier: Zlib
*/
#pragma once

#include "env/DLLSHAREDATA.h"

namespace mac_test {

//! 建立测试用的共通设置（已经建立时什么都不做）。返回它的引用
DLLSHAREDATA& SetUpShareData();
//! 删除测试用的共通设置。之后 GetDllShareData() 与原版未初始化时一样抛出异常
void TearDownShareData();

} // namespace mac_test

namespace window {

//! 原版 src/test/cpp/tests1/window/EditorTestSuite.hpp 的 Mac 版（只建立共通设置）
struct EditorTestSuite
{
	static void SetUpEditor() { mac_test::SetUpShareData(); }
	static void TearDownEditor() { mac_test::TearDownShareData(); }
};

} // namespace window
