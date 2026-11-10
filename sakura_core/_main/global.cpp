/*!	@file
	@brief 文字列共通定義

	@author Norio Nakatani
*/
/*
	Copyright (C) 1998-2001, Norio Nakatani
	Copyright (C) 2001, MIK, Stonee, jepro
	Copyright (C) 2002, KK
	Copyright (C) 2003, MIK
	Copyright (C) 2005, Moca
	Copyright (C) 2018-2022, Sakura Editor Organization

	This source code is designed for sakura editor.
	Please contact the copyright holder to use this code for other purpose.
*/

#include "StdAfx.h"
#include "_main/global.h"

#if defined(_WIN32)	// Mac 版: プロセスとコマンドライン（G_AppInstance、GetProfileName）は移植計画のステップ 26 で移植する
#include "_main/CCommandLine.h"
#include "_main/CNormalProcess.h"
#include "basis/CErrorInfo.h"
#endif
#include "config/app_constants.h"
#if defined(_WIN32)
#include "window/CEditWnd.h"
#include "version.h"	// ビルド時に生成する。Mac 版のバージョン情報はアプリのビルドで用意する
#endif
#include "CSelectLang.h"
#include "sakura_rc.h"

#ifdef DEV_VERSION
#pragma message("-------------------------------------------------------------------------------------")
#pragma message("---  This is a Dev version and under development. Be careful to use this version. ---")
#pragma message("-------------------------------------------------------------------------------------")
#endif

/*!
	アプリ名を取得します。

	@date 2007/09/21 kobake 整理
 */
LPCWSTR GetAppName( void )
{
	// アプリ名をリソースから読み込む
	return LS(STR_GSTR_APPNAME);
}

/*! 選択領域描画用パラメータ */
const COLORREF	SELECTEDAREA_RGB = RGB( 255, 255, 255 );
const int		SELECTEDAREA_ROP2 = R2_XORPEN;

#if defined(_WIN32)
HINSTANCE G_AppInstance()
{
	const auto process = CProcess::getInstance();
	return process ? process->GetProcessInstance() : ::GetModuleHandleW(nullptr);
}

/*!
 * 起動時に指定されたプロファイル名を取得する
 */
LPCWSTR GetProfileName() noexcept
{
	const auto cmdline = CCommandLine::getInstance();
	return cmdline ? cmdline->GetProfileName() : LTEXT("");
}
#else
/*!
 * Mac 版：アプリのモジュールハンドル。Mac 版にはモジュールハンドルがなく、
 * リソースはアプリに 1 つだけ（FindResourceW などはハンドルを見ない）なので nullptr を返す（移植計画のステップ 21）
 */
HINSTANCE G_AppInstance()
{
	return nullptr;
}
#endif // defined(_WIN32)

/*!
 * コンストラクタ
 */
SSearchOption::SSearchOption() noexcept
	: SSearchOption(false, false, false)
{
}

/*!
 * コンストラクタ(値指定)
 */
SSearchOption::SSearchOption(
	bool _bRegularExp,
	bool _bLoHiCase,
	bool _bWordOnly
) noexcept
	: bRegularExp(_bRegularExp)
	, bLoHiCase(_bLoHiCase)
	, bWordOnly(_bWordOnly)
{
}

//! リセットする(全部falseにする)
void SSearchOption::Reset()
{
	bRegularExp = false;
	bLoHiCase = false;
	bWordOnly = false;
}

/*!
 * 同型との等価比較
 *
 * @param rhs 比較対象
 * @retval true 等しい
 * @retval false 等しくない
 */
bool SSearchOption::operator == (const SSearchOption& rhs) const noexcept
{
	if (this == &rhs) return true;
	return bRegularExp == rhs.bRegularExp
		&& bLoHiCase == rhs.bLoHiCase
		&& bWordOnly == rhs.bWordOnly;
}

/*!
 * 同型との否定の等価比較
 *
 * @param rhs 比較対象
 * @retval true 等しくない
 * @retval false 等しい
 */
bool SSearchOption::operator != (const SSearchOption& rhs) const noexcept
{
	return !(*this == rhs);
}
