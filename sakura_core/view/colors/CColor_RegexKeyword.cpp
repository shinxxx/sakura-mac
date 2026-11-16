/*! @file */
/*
	Copyright (C) 2008, kobake
	Copyright (C) 2018-2022, Sakura Editor Organization

	SPDX-License-Identifier: Zlib
*/

#include "StdAfx.h"
#if defined(_WIN32)
#include "view/CEditView.h" // SColorStrategyInfo
#else
#include "view/colors/CColorStrategy.h"	// Mac 版：編集画面（CEditView）は使わない（移植計画のステップ 33）
#include "env/DLLSHAREDATA.h"
#include "env/CRegexKeyword.h"
#endif
#include "CColor_RegexKeyword.h"

bool CColor_RegexKeyword::BeginColor(const CStringRef& cStr, int nPos)
{
	if(!cStr.IsValid())return false;

	int		nMatchLen;
	int		nMatchColor;

#if defined(_WIN32)
	const CEditView* pcView = CColorStrategyPool::getInstance()->GetCurrentView();
	CRegexKeyword* pcRegexKeyword = pcView->m_cRegexKeyword;
#else
	CRegexKeyword* pcRegexKeyword = GetColorRegexKeywordMac();	// Mac 版：文書ごとの正規表現キーワード（移植計画のステップ 33）
#endif

	//正規表現キーワード
	if( pcRegexKeyword->RegexIsKeyword( cStr, nPos, &nMatchLen, &nMatchColor )
	){
		this->m_nCOMMENTEND = nPos + nMatchLen;  /* キーワード文字列の終端をセットする */
		this->m_nCOMMENTMODE = ToColorIndexType_RegularExpression(nMatchColor);
		return true;
	}
	return false;
}

bool CColor_RegexKeyword::EndColor([[maybe_unused]] const CStringRef& cStr, int nPos)
{
	if( nPos == this->m_nCOMMENTEND ){
		return true;
	}
	return false;
}

void CColor_RegexKeyword::OnStartScanLogic()
{
#if defined(_WIN32)
	CEditView* pcView = CColorStrategyPool::getInstance()->GetCurrentView();
	CRegexKeyword* pcRegexKeyword = pcView->m_cRegexKeyword;
#else
	CRegexKeyword* pcRegexKeyword = GetColorRegexKeywordMac();	// Mac 版（移植計画のステップ 33）
#endif
	if( m_pTypeData->m_bUseRegexKeyword ){
		pcRegexKeyword->RegexKeyLineStart();
	}
}
