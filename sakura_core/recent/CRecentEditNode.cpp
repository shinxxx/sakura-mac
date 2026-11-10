/*! @file */
/*
	Copyright (C) 2008, kobake
	Copyright (C) 2018-2026, Sakura Editor Organization

	SPDX-License-Identifier: Zlib
*/

#include "StdAfx.h"
#include "CRecentEditNode.h"

// -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- //
//                           生成                              //
// -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- //

CRecentEditNode::CRecentEditNode()
{
	Create(
		GetShareData()->m_sNodes.m_pEditArr,
		0,
		&GetShareData()->m_sNodes.m_nEditArrNum,
		nullptr,
		MAX_EDITWINDOWS,
		nullptr
	);
}

// -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- //
//                      オーバーライド                         //
// -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- //

/*
	アイテムの比較要素を取得する。

	@note	取得後のポインタはユーザー管理の構造体にキャストして参照してください。
*/
const WCHAR* CRecentEditNode::GetItemText( [[maybe_unused]] int nIndex ) const
{
	return LTEXT("WIN"); //※テキスト情報は無い (GetWindowTextしてあげても良いけど、この関数は実行されないので、意味は無い)
}

bool CRecentEditNode::DataToReceiveType( const EditNode** dst, const EditNode* src ) const
{
	*dst = src;
	return true;
}

int CRecentEditNode::CompareItem( const EditNode* p1, const EditNode* p2 ) const
{
#if defined(_WIN32)
	return int(p1->m_hWnd - p2->m_hWnd);
#else
	// Mac 版：HWND は不完全型なので、アドレスの大小で比べる（移植計画のステップ 21）
	const auto a = reinterpret_cast<std::uintptr_t>(p1->m_hWnd);
	const auto b = reinterpret_cast<std::uintptr_t>(p2->m_hWnd);
	return a < b ? -1 : (a == b ? 0 : 1);
#endif
}

// -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- //
//                   固有インターフェース                      //
// -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- //

int CRecentEditNode::FindItemByHwnd(HWND hwnd) const
{
	int n = GetItemCount();
	for(int i=0;i<n;i++){
		if(GetItem(i)->m_hWnd == hwnd)return i;
	}
	return -1;
}

void CRecentEditNode::DeleteItemByHwnd(HWND hwnd)
{
	int n = FindItemByHwnd(hwnd);
	if(n!=-1){
		DeleteItem(n);
	}
	else{
		DEBUG_TRACE( LTEXT("DeleteItemByHwnd失敗\n") );
	}
}
