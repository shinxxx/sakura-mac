/*! @file */
/*
	Copyright (C) 2018-2022, Sakura Editor Organization

	SPDX-License-Identifier: Zlib
*/
#include "StdAfx.h"
#if defined(_WIN32)
#include "view/CEditView.h" // SColorStrategyInfo
#else
#include "view/colors/CColorStrategy.h"	// Mac 版：編集画面（CEditView）は使わない（移植計画のステップ 33）
#include "env/DLLSHAREDATA.h"
#endif
#include "CColor_Url.h"
#include "parse/CWordParse.h"
#include "doc/CEditDoc.h"
#include "doc/layout/CLayout.h"
#if defined(_WIN32)
#include "types/CTypeSupport.h"
#endif

// -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- //
//                           URL                               //
// -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- //

bool CColor_Url::BeginColor(const CStringRef& cStr, int nPos)
{
	if(!cStr.IsValid())return false;

	int	nUrlLen;

	if( _IsPosKeywordHead(cStr,nPos) /* URLを表示する */
	 && IsURL( cStr.GetPtr(), nPos, cStr.GetLength(), &nUrlLen )	/* 指定アドレスがURLの先頭ならばTRUEとその長さを返す */
	){
		this->m_nCOMMENTEND = nPos + nUrlLen;
		return true;
	}
	return false;
}

bool CColor_Url::EndColor([[maybe_unused]] const CStringRef& cStr, int nPos)
{
	if( nPos == this->m_nCOMMENTEND ){
		return true;
	}
	return false;
}
