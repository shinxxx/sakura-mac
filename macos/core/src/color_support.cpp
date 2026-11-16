/*! @file
	@brief Mac 版的色分け对象（计划第 33 步）。说明见 color_support.h
*/
/*
	Copyright (C) 2026, Sakura Editor Organization

	SPDX-License-Identifier: Zlib
*/
#include "StdAfx.h"
#include "color_support.h"
#include "view/colors/CColorStrategy.h"
#include "env/CRegexKeyword.h"

namespace {
	//! 没有指定对象时用的空设置（所有颜色都不显示，与原版关掉所有色分け时相同）
	const STypeConfig& EmptyTypeConfig()
	{
		static const STypeConfig empty{};
		return empty;
	}
	const STypeConfig* s_pType = nullptr;
	CRegexKeyword* s_pRegex = nullptr;
}

const STypeConfig* GetColorTypeConfigMac()
{
	return s_pType ? s_pType : &EmptyTypeConfig();
}

CRegexKeyword* GetColorRegexKeywordMac()
{
	return s_pRegex;
}

void SetColorTargetMac(const STypeConfig* type, CRegexKeyword* regex, bool force)
{
	if (!force && type == s_pType && regex == s_pRegex) {
		return;
	}
	s_pType = type;
	s_pRegex = regex;
	CColorStrategyPool::getInstance()->OnChangeSetting();
}
