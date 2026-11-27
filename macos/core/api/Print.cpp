/*! @file
	@brief 印刷（计划第 47 步：印刷・印刷プレビュー・印刷ページ設定）

	原版 CPrint（sakura_core/print/CPrint.cpp）の用紙・印字可能桁と行、
	CPrintPreview（sakura_core/print/CPrintPreview.cpp）の印刷用の排版（OnChangePrintSetting）とページの描画
	（DrawHeaderFooter・DrawPageTextFirst・DrawPageText・Print_DrawLine・Print_DrawBlock・GetColorStrategy）、
	CDlgPrintSetting の入力値の範囲（DataCheckAndCorrect）の移植。
	原版は GDI で描く。Mac 版は描く文字と位置（PrintPage）を返し、界面層が Core Text で描く。
	位置の計算は原版と同じ（1/10 mm の整数）。

	原版と違うところ：
	- 座標は用紙の左上が原点で下向きが正（原版は MM_LOMETRIC で上向きが正。符号を変えただけ）。
	- 文字は上端ではなくベースラインで返す。原版は「行の上端 + (フォント高 - アセント)」に上端を合わせて描くので、
	  ベースラインは「行の上端 + フォント高」になる（フォントによらない）。
	- 用紙の印刷できない余白（原版 GETPRINTINGOFFSET）は 0。Mac は用紙の端からの位置で描く（NSPrintInfo の余白 0）。
	- フォントは MacFontFace で Mac のフォントに置き換えて測る（「ＭＳ 明朝」など Mac にないフォント）。
*/
/*
	Copyright (C) 1998-2001, Norio Nakatani
	Copyright (C) 2002, YAZAKI
	Copyright (C) 2003, かろと
	Copyright (C) 2018-2022, Sakura Editor Organization
	Copyright (C) 2026, Sakura Editor Organization

	SPDX-License-Identifier: Zlib
*/
#include "StdAfx.h"
#include "sakura_core/SakuraCore.h"
#include "PrintSource.h"

#include <algorithm>
#include <cstring>
#include <cwchar>

#include "env/DLLSHAREDATA.h"
#include "print/CPrint.h"
#include "doc/layout/CLayoutMgr.h"
#include "doc/layout/CLayout.h"
#include "doc/logic/CDocLineMgr.h"
#include "doc/logic/CDocLine.h"
#include "view/colors/CColorStrategy.h"
#include "charset/charcode.h"
#include "charset/codechecker.h"
#include "mem/CNativeW.h"
#include "types/CType.h"
#include "util/format.h"
#include "config/app_constants.h"

namespace sakura::core {

namespace {

// ----- PRINTSETTING ↔ PrintSetting -----

template <size_t N>
void CopyTo(WCHAR (&dst)[N], const Text& src)
{
	const size_t n = std::min(src.size(), N - 1);
	std::copy_n(src.data(), n, dst);
	dst[n] = LCHAR('\0');
}

template <size_t N>
Text FromArray(const WCHAR (&src)[N])
{
	size_t n = 0;
	while (n < N && src[n] != LCHAR('\0')) ++n;
	return Text(src, n);
}

PrintFont ToPrintFont(const LOGFONT& lf, int pointSize)
{
	PrintFont f;
	f.faceName = FromArray(lf.lfFaceName);
	if (!f.faceName.empty()) {
		f.pointSize = pointSize;
		f.bold = lf.lfWeight >= 600;
		f.italic = lf.lfItalic != 0;
	}
	return f;
}

//! フォント → LOGFONT。名前がないとき 0 で埋める（原版の「使用」を外したとき）。ほかの値は残す
void FromPrintFont(const PrintFont& f, LOGFONT& lf, int& pointSize)
{
	if (f.faceName.empty()) {
		lf = LOGFONT{};
		pointSize = 0;
		return;
	}
	if (lf.lfFaceName[0] == LCHAR('\0')) {
		lf = LOGFONT{};
		lf.lfCharSet = 1;	// DEFAULT_CHARSET
	}
	CopyTo(lf.lfFaceName, f.faceName);
	lf.lfHeight = -static_cast<LONG>((f.pointSize * 96 + 360) / 720);	// 原版 MySelectFont：画面（96 DPI）のピクセル
	lf.lfWeight = f.bold ? 700 : 400;	// FW_BOLD・FW_NORMAL
	lf.lfItalic = f.italic ? 1 : 0;
	pointSize = f.pointSize;
}

PrintSetting ToPrintSetting(const PRINTSETTING& ps)
{
	PrintSetting s;
	s.name = FromArray(ps.m_szPrintSettingName);
	s.fontHan = FromArray(ps.m_szPrintFontFaceHan);
	s.fontZen = FromArray(ps.m_szPrintFontFaceZen);
	s.fontHeight = ps.m_nPrintFontHeight;
	s.fontWidth = ps.m_nPrintFontWidth;
	s.columns = ps.m_nPrintDansuu;
	s.columnSpace = ps.m_nPrintDanSpace;
	s.lineSpacing = ps.m_nPrintLineSpacing;
	s.marginTop = ps.m_nPrintMarginTY;
	s.marginBottom = ps.m_nPrintMarginBY;
	s.marginLeft = ps.m_nPrintMarginLX;
	s.marginRight = ps.m_nPrintMarginRX;
	s.orientation = ps.m_nPrintPaperOrientation == DMORIENT_LANDSCAPE ? PaperOrientation::Landscape : PaperOrientation::Portrait;
	s.paperSize = ps.m_nPrintPaperSize;
	s.colorPrint = ps.m_bColorPrint;
	s.wordWrap = ps.m_bPrintWordWrap;
	s.kinsokuHead = ps.m_bPrintKinsokuHead;
	s.kinsokuTail = ps.m_bPrintKinsokuTail;
	s.kinsokuRet = ps.m_bPrintKinsokuRet;
	s.kinsokuKuto = ps.m_bPrintKinsokuKuto;
	s.lineNumber = ps.m_bPrintLineNumber;
	for (int i = 0; i < 3; ++i) {
		s.header[i] = FromArray(ps.m_szHeaderForm[i]);
		s.footer[i] = FromArray(ps.m_szFooterForm[i]);
	}
	s.headerFont = ToPrintFont(ps.m_lfHeader, ps.m_nHeaderPointSize);
	s.footerFont = ToPrintFont(ps.m_lfFooter, ps.m_nFooterPointSize);
	s.printerName = FromArray(ps.m_mdmDevMode.m_szPrinterDeviceName);
	return s;
}

void FromPrintSetting(const PrintSetting& s, PRINTSETTING& ps)
{
	CopyTo(ps.m_szPrintSettingName, s.name);
	CopyTo(ps.m_szPrintFontFaceHan, s.fontHan);
	CopyTo(ps.m_szPrintFontFaceZen, s.fontZen);
	ps.m_nPrintFontHeight = s.fontHeight;
	ps.m_nPrintFontWidth = s.fontWidth;
	ps.m_nPrintDansuu = s.columns;
	ps.m_nPrintDanSpace = s.columnSpace;
	ps.m_nPrintLineSpacing = s.lineSpacing;
	ps.m_nPrintMarginTY = s.marginTop;
	ps.m_nPrintMarginBY = s.marginBottom;
	ps.m_nPrintMarginLX = s.marginLeft;
	ps.m_nPrintMarginRX = s.marginRight;
	ps.m_nPrintPaperOrientation = static_cast<short>(s.orientation);
	ps.m_nPrintPaperSize = s.paperSize;
	ps.m_bColorPrint = s.colorPrint;
	ps.m_bPrintWordWrap = s.wordWrap;
	ps.m_bPrintKinsokuHead = s.kinsokuHead;
	ps.m_bPrintKinsokuTail = s.kinsokuTail;
	ps.m_bPrintKinsokuRet = s.kinsokuRet;
	ps.m_bPrintKinsokuKuto = s.kinsokuKuto;
	ps.m_bPrintLineNumber = s.lineNumber;
	for (int i = 0; i < 3; ++i) {
		CopyTo(ps.m_szHeaderForm[i], s.header[i]);
		CopyTo(ps.m_szFooterForm[i], s.footer[i]);
	}
	FromPrintFont(s.headerFont, ps.m_lfHeader, ps.m_nHeaderPointSize);
	FromPrintFont(s.footerFont, ps.m_lfFooter, ps.m_nFooterPointSize);
	CopyTo(ps.m_mdmDevMode.m_szPrinterDeviceName, s.printerName);
}

PRINTSETTING ToNative(const PrintSetting& s)
{
	PRINTSETTING ps{};
	FromPrintSetting(s, ps);
	return ps;
}

// ----- 原版 CTextMetrics::GenerateDxArray・CalcTextWidth・CalcTextWidth2（view/CTextMetrics.cpp。画面の部分は Mac 版にないのでここに） -----

const int* GenerateDxArray(
	std::vector<int>* pvResultArray,
	const WCHAR* pText,
	int nLength,
	int nHankakuDx,
	int nTabSpace = 8,
	int nIndent = 0,
	int nCharSpacing = 0,
	CCharWidthCache& cache = GetCharWidthCache()
)
{
	if (!pText || nLength <= 0) return nullptr;
	std::vector<int>& vResultArray = *pvResultArray;
	vResultArray.clear();

	for (int i = 0; i < nLength; ++i) {
		if (pText[i] == WCODE::TAB) {
			// TAB対応	2013/5/7 Uchi
			if (i > 0 && pText[i - 1] == WCODE::TAB) {
				vResultArray.push_back(nTabSpace);
				nIndent += nTabSpace;
				continue;
			}
			vResultArray.push_back((nTabSpace + nHankakuDx - 1) - ((nIndent + nHankakuDx - 1) % nTabSpace));
			nIndent += vResultArray.back();
			continue;
		}

		const int spacing = (Int)CNativeW::GetKetaOfChar(pText, nLength, i, cache) * nCharSpacing;
		if (IsUTF16High(pText[i]) && i + 1 < nLength && IsUTF16Low(pText[i + 1])) {
			vResultArray.push_back(cache.CalcPxWidthByFont2(pText + i) + spacing);
			vResultArray.push_back(0);
			i++;
			continue;
		}
		vResultArray.push_back(cache.CalcPxWidthByFont(pText[i]) + spacing);
		nIndent += vResultArray.back();

		if (IsVariationSelector(sakura::wstring_view(pText + i + 1, nLength - (i + 1)))) {
			vResultArray.push_back(0);
			vResultArray.push_back(0);
			i += 2;
		}
	}
	return vResultArray.data();
}

int CalcTextWidth(const WCHAR* pText, int nLength, const int* pnDx)
{
	int w = 0;
	for (int i = 0; pnDx && i < nLength; ++i) w += pnDx[i];
	(void)pText;
	return w;
}

int CalcTextWidth2(const WCHAR* pText, int nLength, int nHankakuDx, int nCharSpacing, std::vector<int>& vDxArray)
{
	const int* pDxArray = GenerateDxArray(&vDxArray, pText, nLength, nHankakuDx, 8, 0, nCharSpacing);
	return CalcTextWidth(pText, nLength, pDxArray);
}

//! 印刷のフォントの文字幅キャッシュ（原版 OnChangePrintSetting の SelectCharWidthCache・InitCharWidthCacheFromDC）。
//! 同じフォントのときは初期化しない。終わったら編集画面のキャッシュに戻す（Mac 版は一つのプロセスに編集画面がいくつもある）
class PrintCharWidthScope {
public:
	PrintCharWidthScope(const PRINTSETTING& ps)
	{
		static Text s_han, s_zen;
		static int s_height = -1;
		SelectCharWidthCache(CWM_FONT_PRINT, CWM_CACHE_LOCAL);
		const Text han = MacFontFace(FromArray(ps.m_szPrintFontFaceHan));
		const Text zen = MacFontFace(FromArray(ps.m_szPrintFontFaceZen));
		if (han != s_han || zen != s_zen || ps.m_nPrintFontHeight != s_height) {
			// 原版 SetPreviewFontHan・SetPreviewFontZen：高さは印刷設定のフォント高、幅 0
			LOGFONT lfs[2]{};
			lfs[0].lfHeight = ps.m_nPrintFontHeight;
			CopyTo(lfs[0].lfFaceName, han);
			lfs[1].lfHeight = ps.m_nPrintFontHeight;
			CopyTo(lfs[1].lfFaceName, zen);
			InitCharWidthCacheFromDC(lfs, CWM_FONT_PRINT, nullptr);
			SelectCharWidthCache(CWM_FONT_PRINT, CWM_CACHE_LOCAL);
			s_han = han;
			s_zen = zen;
			s_height = ps.m_nPrintFontHeight;
		}
	}
	~PrintCharWidthScope()
	{
		SelectCharWidthCache(CWM_FONT_EDIT, CWM_CACHE_LOCAL);
	}
	PrintCharWidthScope(const PrintCharWidthScope&) = delete;
	PrintCharWidthScope& operator=(const PrintCharWidthScope&) = delete;
};

//! 原版 DataCheckAndCorrect の sDataRange
struct FieldRange { int minval; int maxval; };
constexpr FieldRange kRanges[] = {
	{ 7, 200 },	//!< フォント高 1/10mm
	{ 0, 150 },	//!< 行送り %
	{ 1, 4 },	//!< 段数
	{ 0, 30 },	//!< 段の隙間 mm
	{ 0, 50 },	//!< 余白 上 mm
	{ 0, 50 },	//!< 下
	{ 0, 50 },	//!< 左
	{ 0, 50 },	//!< 右
};

//! Tab文字をSpace文字に置換え（原版 Tab2Space）
void Tab2Space(Text& s)
{
	std::replace(s.begin(), s.end(), LCHAR('\t'), LCHAR(' '));
}

} // namespace

// ---------------------------------------------------------------------------
// 印刷ページ設定
// ---------------------------------------------------------------------------

PrintSetting GetPrintSetting(std::int32_t index)
{
	if (index < 0 || PrintSettingCount <= index) index = 0;
	return ToPrintSetting(GetDllShareData().m_PrintSettingArr[index]);
}

void SetPrintSetting(std::int32_t index, const PrintSetting& setting)
{
	if (index < 0 || PrintSettingCount <= index) return;
	FromPrintSetting(setting, GetDllShareData().m_PrintSettingArr[index]);
}

std::vector<PaperInfo> PaperList()
{
	std::vector<PaperInfo> result;
	for (int i = 0; i < CPrint::m_nPaperInfoArrNum; ++i) {
		const PAPER_INFO& p = CPrint::m_paperInfoArr[i];
		result.push_back(PaperInfo{ static_cast<std::int16_t>(p.m_nId), p.m_nAllWidth, p.m_nAllHeight, Text(p.m_pszName) });
	}
	return result;
}

std::optional<PaperSize> GetPaperSize(std::int16_t paperId, PaperOrientation orientation)
{
	// 原版 CPrint::GetPaperSize（DM_PAPERSIZE だけ。用紙の長さ・幅はプリンターから来ないので表の値）
	for (int i = 0; i < CPrint::m_nPaperInfoArrNum; ++i) {
		const PAPER_INFO& p = CPrint::m_paperInfoArr[i];
		if (p.m_nId == paperId) {
			PaperSize size{ p.m_nAllWidth, p.m_nAllHeight };
			if (orientation == PaperOrientation::Landscape) std::swap(size.width, size.height);
			return size;
		}
	}
	return std::nullopt;
}

std::int32_t PrintableColumns(const PrintSetting& setting, std::int32_t paperWidth, std::int32_t lineNumberColumns)
{
	PRINTSETTING ps = ToNative(setting);
	return CPrint::CalculatePrintableColumns(&ps, paperWidth, lineNumberColumns);
}

std::int32_t PrintableLines(const PrintSetting& setting, std::int32_t paperHeight)
{
	PRINTSETTING ps = ToNative(setting);
	return CPrint::CalculatePrintableLines(&ps, paperHeight);
}

std::int32_t PrintHeaderHeight(const PrintSetting& setting)
{
	PRINTSETTING ps = ToNative(setting);
	return CPrint::CalcHeaderHeight(&ps);
}

std::int32_t PrintFooterHeight(const PrintSetting& setting)
{
	PRINTSETTING ps = ToNative(setting);
	return CPrint::CalcFooterHeight(&ps);
}

std::pair<std::int32_t, std::int32_t> PrintSettingRange(PrintSettingField field)
{
	const auto i = static_cast<size_t>(field);
	if (std::size(kRanges) <= i) return { 0, 0 };
	return { kRanges[i].minval, kRanges[i].maxval };
}

std::int32_t CorrectPrintSettingValue(PrintSettingField field, std::int32_t nData)
{
	const auto i = static_cast<size_t>(field);
	if (std::size(kRanges) <= i) return nData;
	if (nData <= kRanges[i].minval) nData = kRanges[i].minval;
	if (nData > kRanges[i].maxval) nData = kRanges[i].maxval;
	return nData;
}

void SetPrintSettingField(PrintSetting& s, PrintSettingField field, std::int32_t value)
{
	// 原版 CDlgPrintSetting::GetData
	const int v = CorrectPrintSettingValue(field, value);
	switch (field) {
	case PrintSettingField::FontHeight:
		s.fontHeight = v;
		s.fontWidth = (s.fontHeight + 1) / 2;
		break;
	case PrintSettingField::LineSpacing:	s.lineSpacing = v; break;
	case PrintSettingField::Columns:		s.columns = v; break;
	case PrintSettingField::ColumnSpace:	s.columnSpace = v * 10; break;
	case PrintSettingField::MarginTop:		s.marginTop = v * 10; break;
	case PrintSettingField::MarginBottom:	s.marginBottom = v * 10; break;
	case PrintSettingField::MarginLeft:		s.marginLeft = v * 10; break;
	case PrintSettingField::MarginRight:	s.marginRight = v * 10; break;
	}
}

std::int32_t GetPrintSettingField(const PrintSetting& s, PrintSettingField field)
{
	switch (field) {
	case PrintSettingField::FontHeight:		return s.fontHeight;
	case PrintSettingField::LineSpacing:	return s.lineSpacing;
	case PrintSettingField::Columns:		return s.columns;
	case PrintSettingField::ColumnSpace:	return s.columnSpace / 10;
	case PrintSettingField::MarginTop:		return s.marginTop / 10;
	case PrintSettingField::MarginBottom:	return s.marginBottom / 10;
	case PrintSettingField::MarginLeft:		return s.marginLeft / 10;
	case PrintSettingField::MarginRight:	return s.marginRight / 10;
	}
	return 0;
}

Text PrintFontSizeText(std::int32_t fontHeight)
{
	// 原版：nFontPoints = m_nPrintFontHeight * 720 / 254; "%d.%dpt"
	const int nFontPoints = fontHeight * 720 / 254;
	WCHAR sz[32] = {};
	auto_snprintf_s(sz, std::size(sz), LTEXT("%d.%dpt"), nFontPoints / 10, nFontPoints % 10);
	return Text(sz);
}

Text PrintFontLabel(const PrintFont& font)
{
	// 原版 SetFontName（mm の小数の桁も nMM/10 になっているのは原版のまま）
	if (font.faceName.empty()) return Text();
	const int nPointSize = font.pointSize;
	const int nMM = static_cast<int>((static_cast<long long>(nPointSize) * 254 + 360) / 720);	// MulDiv( nPointSize, 254, 720 )
	WCHAR face[33] = {};
	CopyTo(face, font.faceName);
	WCHAR szName[100] = {};
	auto_sprintf(szName, nPointSize % 10 ? LTEXT("%.32s(%.1fpt/%d.%dmm)") : LTEXT("%.32s(%.0fpt/%d.%dmm)"),
		face, double(nPointSize) / 10, nMM / 10, nMM / 10);
	return Text(szName);
}

Text MacFontFace(const Text& face)
{
	// Windows の日本語フォント → macOS に必ずあるフォント（明朝は明朝、ゴシックはゴシック）
	static const struct { const char16_t* windows; const char16_t* mac; } table[] = {
		{ u"ＭＳ 明朝", u"Hiragino Mincho ProN" },
		{ u"ＭＳ Ｐ明朝", u"Hiragino Mincho ProN" },
		{ u"MS Mincho", u"Hiragino Mincho ProN" },
		{ u"MS PMincho", u"Hiragino Mincho ProN" },
		{ u"游明朝", u"Hiragino Mincho ProN" },
		{ u"Yu Mincho", u"Hiragino Mincho ProN" },
		{ u"ＭＳ ゴシック", u"Hiragino Sans" },
		{ u"ＭＳ Ｐゴシック", u"Hiragino Sans" },
		{ u"MS Gothic", u"Hiragino Sans" },
		{ u"MS PGothic", u"Hiragino Sans" },
		{ u"MS UI Gothic", u"Hiragino Sans" },
		{ u"メイリオ", u"Hiragino Sans" },
		{ u"Meiryo", u"Hiragino Sans" },
		{ u"Meiryo UI", u"Hiragino Sans" },
		{ u"游ゴシック", u"Hiragino Sans" },
		{ u"Yu Gothic", u"Hiragino Sans" },
		{ u"BIZ UDゴシック", u"Hiragino Sans" },
		{ u"BIZ UD明朝", u"Hiragino Mincho ProN" },
		{ u"Consolas", u"Menlo" },
		{ u"Terminal", u"Menlo" },
		{ u"Fixedsys", u"Menlo" },
	};
	for (const auto& e : table) {
		if (face == e.windows) return e.mac;
	}
	return face;
}

// ---------------------------------------------------------------------------
// 印刷用の排版（原版 CPrintPreview）
// ---------------------------------------------------------------------------

struct PrintLayout::Impl {
	PrintSourceMac source;
	PrintSetting setting;
	PRINTSETTING ps{};
	STypeConfig typePrint{};	//!< 原版 m_typePrint。layout が指している
	CLayoutMgr layout;			//!< 原版 m_pLayoutMgr_Print
	PaperSize paper{};
	int paperOffsetLeft = 0;	//!< 原版 m_nPreview_PaperOffsetLeft（Mac 版は 0）
	int paperOffsetTop = 0;
	int enableColumns = 0;		//!< 原版 m_bPreview_EnableColumns
	int enableLines = 0;		//!< 原版 m_bPreview_EnableLines
	int lineNumberColumns = 0;	//!< 原版 m_nPreview_LineNumberColumns
	int allPageNum = 0;			//!< 原版 m_nAllPageNum

	//! 原版 CTextArea::DetectWidthOfLineNumberArea_calculate（印刷用の排版で。bLayout = false）
	int DetectWidthOfLineNumberArea() const
	{
		const STypeConfig& type = *source.type;
		int nAllLines;
		if (type.m_bLineNumIsCRLF) {
			nAllLines = (Int)source.lines->GetLineCount();
		} else {
			nAllLines = (Int)layout.GetLineCount();
		}
		if (0 < nAllLines) {
			int nWork = 1;
			int i;
			for (i = 0; i < LINENUMWIDTH_MIN; ++i) nWork *= 10;	// power<10, LINENUMWIDTH_MIN>
			for (i = LINENUMWIDTH_MIN; i < type.m_nLineNumWidth; ++i) {
				nWork *= 10;
			}
			for (; i < LINENUMWIDTH_MAX; ++i) {
				if (nWork > nAllLines) {
					break;
				}
				nWork *= 10;
			}
			return (i + 1);
		} else {
			//	2003.09.11 wmlhq 行番号が1桁のときと幅を合わせる
			return type.m_nLineNumWidth + 1;
		}
	}

	//! 原版 OnChangePrintSetting（用紙が決まったあと）
	void Build()
	{
		// 行番号を表示するとき、行番号表示に必要な桁数（原版は前の印刷用の排版で数える。最初の排版は空）
		lineNumberColumns = ps.m_bPrintLineNumber ? DetectWidthOfLineNumberArea() : 0;
		// 2014.07.23 レイアウト行番号で行番号幅が合わない時は再計算（原版は OnChangeSetting をやり直す）
		for (int pass = 0; pass < 8; ++pass) {
			BuildOnce();
			if (!ps.m_bPrintLineNumber || IsEmpty()) break;
			const int tempLineNum = DetectWidthOfLineNumberArea();
			if (lineNumberColumns == tempLineNum) break;
			lineNumberColumns = tempLineNum;
		}
	}

	void BuildOnce()
	{
		// 行あたりの文字数(行番号込み)
		enableColumns = CPrint::CalculatePrintableColumns(&ps, paper.width, lineNumberColumns);
		// 縦方向の行数
		enableLines = CPrint::CalculatePrintableLines(&ps, paper.height);
		if (enableColumns == 0 || enableLines == 0) {
			allPageNum = 0;
			return;
		}

		// 印刷用のレイアウト管理情報の初期化
		layout.Create(nullptr, const_cast<CDocLineMgr*>(source.lines));

		// 印刷用のレイアウト情報の変更（タイプ別設定をコピー）
		typePrint = *source.type;
		STypeConfig& ref = typePrint;
		ref.m_nMaxLineKetas = CKetaXInt(enableColumns);
		ref.m_bWordWrap = ps.m_bPrintWordWrap;	// 英文ワードラップをする
		ref.m_nTabSpace = source.tabSpace;
		ref.m_nTsvMode = source.tsvMode;
		ref.m_cLineComment.CopyTo(0, LTEXT(""), -1);
		ref.m_cLineComment.CopyTo(1, LTEXT(""), -1);
		ref.m_cLineComment.CopyTo(2, LTEXT(""), -1);
		ref.m_cBlockComments[0].SetBlockCommentRule(LTEXT(""), LTEXT(""));
		ref.m_cBlockComments[1].SetBlockCommentRule(LTEXT(""), LTEXT(""));
		ref.m_nStringType = 0;
		ref.m_ColorInfoArr[COLORIDX_COMMENT].m_bDisp = false;
		ref.m_ColorInfoArr[COLORIDX_SSTRING].m_bDisp = false;
		ref.m_ColorInfoArr[COLORIDX_WSTRING].m_bDisp = false;
		ref.m_bKinsokuHead = ps.m_bPrintKinsokuHead;
		ref.m_bKinsokuTail = ps.m_bPrintKinsokuTail;
		ref.m_bKinsokuRet = ps.m_bPrintKinsokuRet;
		ref.m_bKinsokuKuto = ps.m_bPrintKinsokuKuto;
		layout.m_nTextWrapMethodCurMac = WRAP_SETTING_WIDTH;
		layout.SetLayoutInfo(true, false, ref, ref.m_nTabSpace, ref.m_nTsvMode, ref.m_nMaxLineKetas,
			CLayoutXInt(ps.m_nPrintFontWidth), nullptr);
		const int perPage = enableLines * ps.m_nPrintDansuu;
		allPageNum = (Int)layout.GetLineCount() / perPage;	// 全ページ数
		if (0 < (Int)layout.GetLineCount() % perPage) {
			allPageNum++;
		}
	}

	bool IsEmpty() const { return enableColumns == 0 || enableLines == 0; }

	// ----- 描画（原版 DrawHeaderFooter・DrawPageText・Print_DrawLine・Print_DrawBlock） -----

	struct Painter {
		const Impl& impl;
		PrintPage& page;
		CColorStrategyPool* pool = nullptr;

		const PRINTSETTING& ps() const { return impl.ps; }

		//! 原版 GetColorStrategy
		CColorStrategy* GetColorStrategy(const CStringRef& cStringLine, int iLogic, CColorStrategy* pStrategy, bool& bChange)
		{
			if (pStrategy) {
				if (pStrategy->EndColor(cStringLine, iLogic)) {
					pStrategy = nullptr;
					bChange = true;
				}
			}
			if (!pStrategy) {
				for (int i = 0; i < pool->GetStrategyCount(); i++) {
					if (pool->GetStrategy(i)->BeginColor(cStringLine, iLogic)) {
						pStrategy = pool->GetStrategy(i);
						bChange = true;
						break;
					}
				}
			}
			return pStrategy;
		}

		//! 原版 Print_DrawBlock。baseline は描画座標（行の上端）から
		void DrawBlock(int x, int lineTop, const WCHAR* pPhysicalLine, int nBlockLen, int nKind,
			const CLayout* pcLayout, int nColorIdx, int nBgnPhysical, int nLayoutX, const int* pDxArray)
		{
			if (nKind == 2 && pcLayout == nullptr) {
				// TABはカラーで無ければ印字不要
				return;
			}
			PrintRun run;
			run.zen = (nKind == 1);
			run.tab = (nKind == 2);
			if (pcLayout) {
				if (-1 != nColorIdx) {
					const ColorInfo& info = impl.source.type->m_ColorInfoArr[nColorIdx];
					if (nKind == 2 && !info.m_sFontAttr.m_bUnderLine) {
						// TABは下線が無ければ印字不要
						return;
					}
					run.bold = info.m_sFontAttr.m_bBoldFont;
					run.underline = info.m_sFontAttr.m_bUnderLine;
					run.color = ColorRgb(info.m_sColorAttr.m_cTEXT);
				}
			}
			run.x = x + nLayoutX;
			run.baseline = lineTop + ps().m_nPrintFontHeight;
			run.text.assign(&pPhysicalLine[nBgnPhysical], nBlockLen);
			run.dx.assign(&pDxArray[nBgnPhysical], &pDxArray[nBgnPhysical] + nBlockLen);
			page.runs.push_back(std::move(run));
		}

		static std::uint32_t ColorRgb(COLORREF c)
		{
			return (static_cast<std::uint32_t>(c & 0xFF) << 16) | (c & 0xFF00) | ((c >> 16) & 0xFF);
		}

		//! 原版 Print_DrawLine
		CColorStrategy* DrawLine(int x, int lineTop, const WCHAR* pLine, int nDocLineLen, int nLineStart, int nLineLen,
			int nIndent, const CLayout* pcLayout = nullptr, CColorStrategy* pStrategyStart = nullptr)
		{
			if (nLineLen == 0) {
				return pStrategyStart;
			}
			// 文字間隔
			const int nDx = ps().m_nPrintFontWidth;
			const int space = (Int)impl.layout.GetCharSpacing();
			// タブ幅取得
			const int nTabSpace = (Int)impl.layout.GetTabSpace();
			const int tabPadding = (Int)impl.layout.GetWidthPerKeta() - 1;

			std::vector<int> vDxArray;
			const int* pDxArray = GenerateDxArray(&vDxArray, pLine + nLineStart, nLineLen, nDx, nTabSpace, nIndent, space);

			int nBgnLogic = nLineStart;
			int iLogic;
			int nLayoutX = nIndent;

			int nKind = 0;		// 0:半角 1:全角 2:タブ
			int nKindLast = 2;	// 直前のnKind状態

			CStringRef cStringLine(pLine, nDocLineLen);
			CColorStrategy* pStrategy = pStrategyStart;
			int nColorIdx = ToColorInfoArrIndex(pStrategy ? pStrategy->GetStrategyColor() : COLORIDX_TEXT);

			for (iLogic = nLineStart; iLogic < nLineStart + nLineLen; ++iLogic, nKindLast = nKind) {
				if (pLine[iLogic] == WCODE::TAB) {
					nKind = 2;
				} else if (0 == WCODE::GetFontNo(pLine[iLogic])) {
					nKind = 0;
				} else {
					nKind = 1;
				}

				bool bChange = false;
				pStrategy = pcLayout ? GetColorStrategy(cStringLine, iLogic, pStrategy, bChange) : nullptr;

				// タブ文字出現 or 文字種(全角／半角)の境界 or 色指定の境界
				if (nKind != nKindLast || bChange) {
					if (0 < iLogic - nBgnLogic) {
						DrawBlock(x, lineTop, pLine + nLineStart, iLogic - nBgnLogic, nKindLast, pcLayout, nColorIdx,
							nBgnLogic - nLineStart, nLayoutX, pDxArray);
						// 桁進め
						if (nKindLast == 2) {
							nLayoutX += (nTabSpace + tabPadding - (nLayoutX + tabPadding) % nTabSpace)
								+ nTabSpace * (iLogic - nBgnLogic - 1);
						} else {
							int nIncrement = 0;
							for (int i = nBgnLogic - nLineStart; i < iLogic - nLineStart; i++) {
								nIncrement += pDxArray[i];
							}
							nLayoutX += nIncrement;
						}
						nBgnLogic = iLogic;
					}
					if (bChange) {
						nColorIdx = ToColorInfoArrIndex(pStrategy ? pStrategy->GetStrategyColor() : COLORIDX_TEXT);
					}
				}
			}

			// 残りを描画
			if (0 < nLineStart + nLineLen - nBgnLogic) {
				DrawBlock(x, lineTop, pLine + nLineStart, nLineStart + nLineLen - nBgnLogic, nKindLast, pcLayout, nColorIdx,
					nBgnLogic - nLineStart, nLayoutX, pDxArray);
			}
			return pStrategy;
		}

		//! 原版 DrawHeaderFooter。rect は原版の cRect（下向きに直したもの）
		void DrawHeaderFooter(int left, int top, int right, int bottom, bool bHeader, const ExpandParameterView& view)
		{
			const PRINTSETTING& s = ps();
			const LOGFONT& lf = bHeader ? s.m_lfHeader : s.m_lfFooter;
			const bool bFontSetting = lf.lfFaceName[0] != LCHAR('\0');
			const auto& forms = bHeader ? s.m_szHeaderForm : s.m_szFooterForm;
			auto expand = [&](int pos) {
				Text out = impl.source.doc->ExpandParameter(FromArray(forms[pos]), view);
				if (out.size() > 1024) out.resize(1024);	// 原版 szWork[1024 + 1]
				return out;
			};

			if (bFontSetting) {
				// フォント指定有り：文字の幅は界面層がそのフォントで測る
				const PrintFont font = ToPrintFont(lf, bHeader ? s.m_nHeaderPointSize : s.m_nFooterPointSize);
				for (int pos = POS_LEFT; pos <= POS_RIGHT; ++pos) {
					PrintAlignedText t;
					t.text = expand(pos);
					Tab2Space(t.text);
					t.align = pos;
					t.left = left;
					t.right = right;
					t.top = bHeader ? top : bottom;
					t.footer = !bHeader;
					t.font = font;
					page.alignedTexts.push_back(std::move(t));
				}
				return;
			}

			// 文字間隔
			const int nDx = s.m_nPrintFontWidth;
			const int spaceing = 0;
			// 行の上端（原版 nY。フッターは rect.bottom + フォント高 の上向き）
			const int nY = bHeader ? top : bottom - s.m_nPrintFontHeight;
			std::vector<int> vDxArray;

			// 左寄せ
			Text work = expand(POS_LEFT);
			DrawLine(left, nY, work.c_str(), int(work.size()), 0, int(work.size()), 0);
			// 中央寄せ
			work = expand(POS_CENTER);
			int nTextWidth = CalcTextWidth2(work.c_str(), int(work.size()), nDx, spaceing, vDxArray);
			DrawLine((right + left - nTextWidth) / 2, nY, work.c_str(), int(work.size()), 0, int(work.size()), 0);
			// 右寄せ
			work = expand(POS_RIGHT);
			nTextWidth = CalcTextWidth2(work.c_str(), int(work.size()), nDx, spaceing, vDxArray);
			DrawLine(right - nTextWidth, nY, work.c_str(), int(work.size()), 0, int(work.size()), 0);
		}

		//! 原版 DrawPageTextFirst
		CColorStrategy* DrawPageTextFirst(int nPageNum)
		{
			CColorStrategy* pStrategy = nullptr;
			if (ps().m_bColorPrint) {
				const CLayoutInt nPageTopLineNum((nPageNum * ps().m_nPrintDansuu) * impl.enableLines);
				const CLayout* pcPageTopLayout = impl.layout.SearchLineByLayoutY(nPageTopLineNum);
				if (pcPageTopLayout != nullptr) {
					const int nPageTopOff = (Int)pcPageTopLayout->GetLogicOffset();
					// ページトップの物理行の先頭を検索
					while (pcPageTopLayout->GetLogicOffset()) {
						pcPageTopLayout = pcPageTopLayout->GetPrevLayout();
					}
					// 論理行先頭のCColorStrategy取得
					pStrategy = pool->GetStrategyByColor(pcPageTopLayout->GetColorTypePrev());
					pool->NotifyOnStartScanLogic();
					if (pStrategy) {
						pStrategy->InitStrategyStatus();
						pStrategy->SetStrategyColorInfo(pcPageTopLayout->GetColorInfo());
					}
					if (nPageTopOff) {
						CStringRef csr = pcPageTopLayout->GetDocLineRef()->GetStringRefWithEOL();
						for (int iLogic = 0; iLogic < nPageTopOff; ++iLogic) {
							bool bChange;
							pStrategy = GetColorStrategy(csr, iLogic, pStrategy, bChange);
						}
					}
				}
			}
			return pStrategy;
		}

		//! 原版 DrawPageText
		CColorStrategy* DrawPageText(int nOffX, int nOffY, int nPageNum, CColorStrategy* pStrategyStart)
		{
			const PRINTSETTING& s = ps();
			const STypeConfig& type = *impl.source.type;
			const int nLineHeight = s.m_nPrintFontHeight + (s.m_nPrintFontHeight * s.m_nPrintLineSpacing / 100);
			// 段と段の間隔の幅
			const int nDanWidth = impl.enableColumns * s.m_nPrintFontWidth + s.m_nPrintDanSpace;
			// 行番号の幅
			const int nLineNumWidth = impl.lineNumberColumns * s.m_nPrintFontWidth;

			CColorStrategy* pStrategy = pStrategyStart;
			for (int nDan = 0; nDan < s.m_nPrintDansuu; ++nDan) {
				// 本文1桁目の左隅の座標(行番号がある場合はこの座標より左側)
				const int nBasePosX = nOffX + nDanWidth * nDan + nLineNumWidth * (nDan + 1);
				const int charWidth = s.m_nPrintFontWidth;
				int i;
				for (i = 0; i < impl.enableLines; ++i) {
					const CLayoutInt nLineNum((nPageNum * s.m_nPrintDansuu + nDan) * impl.enableLines + i);
					const CLayout* pcLayout = impl.layout.SearchLineByLayoutY(nLineNum);
					if (nullptr == pcLayout) {
						break;
					}
					const int lineTop = nOffY + nLineHeight * i;
					// 行番号を表示するか
					if (s.m_bPrintLineNumber) {
						WCHAR szLineNum[64];
						// 行番号の表示 false=折り返し単位／true=改行単位
						if (type.m_bLineNumIsCRLF) {
							if (0 != pcLayout->GetLogicOffset()) {
								wcscpy(szLineNum, LTEXT(" "));
							} else {
								_itow((Int)pcLayout->GetLogicLineNo() + 1, szLineNum, 10);
							}
						} else {
							_itow((Int)nLineNum + 1, szLineNum, 10);
						}
						// 行番号区切り  0=なし 1=縦線 2=任意
						if (2 == type.m_nLineTermType) {
							WCHAR szLineTerm[2];
							szLineTerm[0] = type.m_cLineTermChar;
							szLineTerm[1] = LCHAR('\0');
							wcscat(szLineNum, szLineTerm);
						} else {
							wcscat(szLineNum, LTEXT(" "));
						}
						const auto nLineCols = int(wcslen(szLineNum));
						std::vector<int> vDxArray;
						const int spacing = 0;
						const int* pDxArray = GenerateDxArray(&vDxArray, szLineNum, nLineCols, s.m_nPrintFontWidth, spacing);
						PrintRun run;
						run.x = nBasePosX - nLineCols * charWidth;
						run.baseline = lineTop + s.m_nPrintFontHeight;
						run.text.assign(szLineNum, nLineCols);
						run.dx.assign(pDxArray, pDxArray + nLineCols);
						// 原版は直前の Print_DrawLine が戻した色（テキストの色）で描く
						if (s.m_bColorPrint) {
							const int textColorIndex = ToColorInfoArrIndex(COLORIDX_TEXT);
							if (-1 != textColorIndex) run.color = ColorRgb(type.m_ColorInfoArr[textColorIndex].m_sColorAttr.m_cTEXT);
						}
						page.runs.push_back(std::move(run));
					}

					const int nLineLen = (Int)pcLayout->GetLengthWithoutEOL();
					if (0 == nLineLen) {
						continue;
					}
					// 物理行頭の色指定を取得
					if (s.m_bColorPrint && !(nDan == 0 && i == 0) && pcLayout->GetLogicOffset() == 0) {
						pStrategy = pool->GetStrategyByColor(pcLayout->GetColorTypePrev());
						pool->NotifyOnStartScanLogic();
						if (pStrategy) {
							pStrategy->InitStrategyStatus();
							pStrategy->SetStrategyColorInfo(pcLayout->GetColorInfo());
						}
					}
					pStrategy = DrawLine(nBasePosX, lineTop,
						pcLayout->GetDocLineRef()->GetPtr(),
						(Int)pcLayout->GetDocLineRef()->GetLengthWithEOL(),
						(Int)pcLayout->GetLogicOffset(),
						nLineLen,
						(Int)pcLayout->GetIndent(),
						s.m_bColorPrint ? pcLayout : nullptr,
						pStrategy);
				}

				// 2006.08.14 Moca 行番号が縦線の場合は1度に引く
				if (s.m_bPrintLineNumber && 1 == type.m_nLineTermType) {
					// 縦線は本文と行番号の隙間1桁の中心に作画する
					page.rules.push_back(PrintRule{ nBasePosX - (s.m_nPrintFontWidth / 2), nOffY, nOffY + nLineHeight * i });
				}
			}
			return pStrategy;
		}
	};
};

PrintLayout::PrintLayout() : m_impl(std::make_unique<Impl>()) {}
PrintLayout::~PrintLayout() = default;

const PrintSetting& PrintLayout::Setting() const { return m_impl->setting; }
PaperSize PrintLayout::Paper() const { return m_impl->paper; }
std::int32_t PrintLayout::Columns() const { return m_impl->enableColumns; }
std::int32_t PrintLayout::Lines() const { return m_impl->enableLines; }
std::int32_t PrintLayout::LineNumberColumns() const { return m_impl->lineNumberColumns; }
std::int32_t PrintLayout::PageCount() const { return m_impl->allPageNum; }
bool PrintLayout::IsEmpty() const { return m_impl->IsEmpty(); }

PrintPage PrintLayout::GetPage(std::int32_t pageNum, const ExpandParameterView& viewIn) const
{
	const Impl& d = *m_impl;
	PrintPage page;
	if (d.IsEmpty() || pageNum < 0 || d.allPageNum <= pageNum) return page;

	d.source.activateColors();
	PrintCharWidthScope widthScope(d.ps);
	ExpandParameterView view = viewIn;
	view.printPage = pageNum + 1;			// $p（原版 m_nCurPageNum + 1）
	view.printPageCount = d.allPageNum;		// $P

	Impl::Painter painter{ d, page };
	if (d.ps.m_bColorPrint) painter.pool = CColorStrategyPool::getInstance();

	const PRINTSETTING& s = d.ps;
	// 紙の大きさをあらわすRECT（原版 OnPrint・OnPaint の cRect。下向き）
	const int left = s.m_nPrintMarginLX - d.paperOffsetLeft + 5;
	const int right = d.paper.width - (s.m_nPrintMarginRX + d.paperOffsetLeft + 5);
	const int top = s.m_nPrintMarginTY - d.paperOffsetTop + 5;
	const int bottom = d.paper.height - (s.m_nPrintMarginBY + d.paperOffsetTop + 5);

	const int nHeaderHeight = CPrint::CalcHeaderHeight(const_cast<PRINTSETTING*>(&s));
	// ヘッダー
	if (nHeaderHeight) {
		painter.DrawHeaderFooter(left, top, right, bottom, true, view);
	}
	// 本文（原版：ページトップの色は前のページから引き継ぐ。ここでは各ページで DrawPageTextFirst から求める。
	// 原版のプレビューも OnPaint のたびに DrawPageTextFirst から描く）
	CColorStrategy* pStrategy = painter.DrawPageTextFirst(pageNum);
	painter.DrawPageText(
		s.m_nPrintMarginLX - d.paperOffsetLeft,
		s.m_nPrintMarginTY - d.paperOffsetTop + nHeaderHeight * 2,
		pageNum,
		pStrategy);
	// フッター
	if (CPrint::CalcFooterHeight(const_cast<PRINTSETTING*>(&s))) {
		painter.DrawHeaderFooter(left, top, right, bottom, false, view);
	}
	return page;
}

std::unique_ptr<PrintLayout> CreatePrintLayoutMac(const PrintSourceMac& source, const PrintSetting& setting)
{
	std::unique_ptr<PrintLayout> result(new PrintLayout());
	auto& d = *result->m_impl;
	d.source = source;
	d.ps = ToNative(setting);
	// 用紙（原版 GetPrintMetrics が失敗したとき：A4 縦）
	if (const auto paper = GetPaperSize(d.ps.m_nPrintPaperSize,
			d.ps.m_nPrintPaperOrientation == DMORIENT_LANDSCAPE ? PaperOrientation::Landscape : PaperOrientation::Portrait)) {
		d.paper = *paper;
	} else {
		d.paper = PaperSize{ 210 * 10, 297 * 10 };
		d.ps.m_nPrintPaperSize = DMPAPER_A4;
		d.ps.m_nPrintPaperOrientation = DMORIENT_PORTRAIT;
	}
	d.setting = ToPrintSetting(d.ps);
	// 与原版 PrintSetting 的字段相同的部分以外（printerName 等）は渡されたものを残す
	d.setting.printerName = setting.printerName;

	source.activateColors();
	PrintCharWidthScope widthScope(d.ps);
	d.Build();
	return result;
}

} // namespace sakura::core
