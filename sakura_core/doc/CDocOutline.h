/*! @file */
/*
	Copyright (C) 2008, kobake
	Copyright (C) 2018-2022, Sakura Editor Organization

	SPDX-License-Identifier: Zlib
*/
#ifndef SAKURA_CDOCOUTLINE_BDF55702_D938_432D_99F2_BF0F98A7C5FE_H_
#define SAKURA_CDOCOUTLINE_BDF55702_D938_432D_99F2_BF0F98A7C5FE_H_
#pragma once

#include "types/CType.h"	//EOutlineType

class CEditDoc;
class CFuncInfoArr;
struct SOneRule;

#if defined(_WIN32)
using COutlineDocRef = CEditDoc;
#else
class CDocLineMgr;
class CLayoutMgr;
class CEol;
struct STypeConfig;

/*!
	Mac 版：CEditDoc はまだ移植していないので、アウトライン解析が使う部分だけを持つ（移植計画のステップ 42）。
	メンバー名は CEditDoc と同じなので、解析のコード（types/CType_*.cpp）は変更しない。
*/
struct COutlineDocRef {
	struct SDocType {
		const STypeConfig& m_type;
		const STypeConfig& GetDocumentAttribute() const { return m_type; }
	};
	struct SDocFile {
		const WCHAR* m_pszFilePath;
		const WCHAR* GetFilePath() const { return m_pszFilePath; }
	};
	struct SDocEditor {
		const CEol& m_cNewLineCode;
	};
	CDocLineMgr&	m_cDocLineMgr;
	CLayoutMgr&		m_cLayoutMgr;
	SDocType		m_cDocType;
	SDocFile		m_cDocFile;
	SDocEditor		m_cDocEditor;
};
#endif

class CDocOutline{
public:
	CDocOutline(COutlineDocRef* pcDoc) : m_pcDocRef(pcDoc) { }
	void	MakeFuncList_C( CFuncInfoArr* pcFuncInfoArr,
							EOutlineType& nOutlineType,
						    const WCHAR* pszFileName,
							bool bVisibleMemberFunc = true );					//!< C/C++関数リスト作成
	void	MakeFuncList_PLSQL( CFuncInfoArr* pcFuncInfoArr );					//!< PL/SQL関数リスト作成
	void	MakeTopicList_txt( CFuncInfoArr* pcFuncInfoArr );					//!< テキスト・トピックリスト作成
	void	MakeFuncList_Java( CFuncInfoArr* pcFuncInfoArr );					//!< Java関数リスト作成
	void	MakeTopicList_cobol( CFuncInfoArr* pcFuncInfoArr );					//!< COBOL アウトライン解析
	void	MakeTopicList_asm( CFuncInfoArr* pcFuncInfoArr );					//!< アセンブラ アウトライン解析
	void	MakeFuncList_Perl( CFuncInfoArr* pcFuncInfoArr );					//!< Perl関数リスト作成	//	Sep. 8, 2000 genta
	void	MakeFuncList_VisualBasic( CFuncInfoArr* pcFuncInfoArr );			//!< Visual Basic関数リスト作成 //June 23, 2001 N.Nakatani
	void	MakeFuncList_python( CFuncInfoArr* pcFuncInfoArr );					//!< Python アウトライン解析 // 2007.02.08 genta
	void	MakeFuncList_Erlang( CFuncInfoArr* pcFuncInfoArr );					//!< Erlang アウトライン解析 // 2009.08.10 genta
	void	MakeTopicList_wztxt( CFuncInfoArr* pcFuncInfoArr );					//!< 階層付きテキスト アウトライン解析 // 2003.05.20 zenryaku
	void	MakeTopicList_html(CFuncInfoArr* pcFuncInfoArr, bool bXml);			//!< HTML アウトライン解析 // 2003.05.20 zenryaku
	void	MakeTopicList_tex(CFuncInfoArr* pcFuncInfoArr);						//!< TeX アウトライン解析 // 2003.07.20 naoh
	void	MakeFuncList_RuleFile( CFuncInfoArr* pcFuncInfoArr,
								   sakura::wstring& sTitleOverride );				//!< ルールファイルを使ってリスト作成 2002.04.01 YAZAKI
	int		ReadRuleFile( const WCHAR* pszFilename, SOneRule* pcOneRule,
						  int nMaxCount, bool& bRegex, sakura::wstring& title );	//!< ルールファイル読込 2002.04.01 YAZAKI
	void	MakeFuncList_BookMark( CFuncInfoArr* );								//!< ブックマークリスト作成 //2001.12.03 hor
private:
	COutlineDocRef* m_pcDocRef;
};

#endif /* SAKURA_CDOCOUTLINE_BDF55702_D938_432D_99F2_BF0F98A7C5FE_H_ */
