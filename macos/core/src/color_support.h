/*! @file
	@brief Mac 版的色分け对象（计划第 33 步）

	原版的色分け（view/colors 的 CColorStrategyPool）是一个进程一个，从 CEditDoc::GetInstance(0)
	和编辑画面（CEditView）取类型别设置和正则关键字。原版一个进程只有一个文档，
	Mac 版一个进程开多个文档，所以排版、取颜色之前先用 SetColorTargetMac 指定当前的文档。
*/
/*
	Copyright (C) 2026, Sakura Editor Organization

	SPDX-License-Identifier: Zlib
*/
#pragma once

struct STypeConfig;
class CRegexKeyword;

/*!
	指定色分け的对象（文档的类型别设置和正则关键字），并更新色分け的设置
	（CColorStrategyPool::OnChangeSetting，与原版切换类型别设置时相同）。
	对象没有变化时什么也不做。
	@param type  类型别设置。nullptr 时清除（不再色分け）
	@param regex 正则关键字（type->m_bUseRegexKeyword 为 false 时可以是 nullptr）
	@param force true 时即使对象相同也重新读设置（类型别设置的内容改了以后）
*/
void SetColorTargetMac(const STypeConfig* type, CRegexKeyword* regex, bool force = false);
