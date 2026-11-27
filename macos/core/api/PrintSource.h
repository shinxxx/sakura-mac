/*! @file
	@brief 印刷用の排版に渡す文書の中身（计划第 47 步。核心库の内部だけで使う）
*/
/*
	Copyright (C) 2026, Sakura Editor Organization

	SPDX-License-Identifier: Zlib
*/
#pragma once

#include <functional>
#include <memory>

#include "sakura_core/SakuraCore.h"
#include "basis/SakuraBasis.h"

class CDocLineMgr;
struct STypeConfig;

namespace sakura::core {

//! 原版 CPrintPreview が CEditDoc から取るもの
struct PrintSourceMac {
	const Document* doc = nullptr;			//!< ヘッダー・フッターの ExpandParameter
	const CDocLineMgr* lines = nullptr;		//!< 文書の行（原版 m_cDocLineMgr）
	const STypeConfig* type = nullptr;		//!< タイプ別設定（原版 m_cDocType.GetDocumentAttribute()）
	CKetaXInt tabSpace{ 4 };				//!< 原版 m_cLayoutMgr.GetTabSpaceKetas()
	int tsvMode = 0;						//!< 原版 m_cLayoutMgr.m_tsvInfo.m_nTsvMode
	std::function<void()> activateColors;	//!< 色分けの対象をこの文書に（Mac 版は文書がいくつもある）
};

std::unique_ptr<PrintLayout> CreatePrintLayoutMac(const PrintSourceMac& source, const PrintSetting& setting);

} // namespace sakura::core
