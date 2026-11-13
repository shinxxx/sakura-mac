/*! @file
	@brief Mac 版核心库的对外接口（计划第 22 步）的实现

	尽量直接调用原版的类，处理方式与原版相同：
	- 读入：env/CReadManager.cpp（类型别设置、编码的自动识别、默认 BOM，CFileLoad 逐行读入）。
	  原版用多个线程分段读入并显示进度；这里在一个线程里从头读到尾，结果相同
	  （第 18 步的往返测试确认过分段读入与一次读入相同）。CReadManager 本身在第 29 步编入。
	- 保存：env/CWriteManager.cpp（第一行前加 BOM，逐行 UnicodeToCode）。
	- 编辑：view/CEditView_Command_New.cpp 的 ReplaceData_CEditView3 中 bFastMode 的处理
	  （逻辑位置上的 CSearchAgent::ReplaceData，记录 CReplaceOpe）。
	- 撤销、重做：cmd/CViewCommander_Edit.cpp 的 Command_UNDO、Command_REDO 中 OPE_REPLACE 的处理。
	- 查找：CSearchAgent::SearchWord。全部替换：cmd/CViewCommander_Search.cpp 的 Command_REPLACE_ALL
	  （整个文档、一括置换）。
	- 排版（第 27 步）：doc/layout 的 CLayoutMgr。文档的编辑改成经过 CLayoutMgr::ReplaceData_CLayoutMgr
	  （ReplaceData_CEditView3 的非 bFastMode 的处理），排版随编辑逐段更新，与原版相同。
	  排版的设置与 CEditDoc::OnChangeSetting、CLoadAgent::OnLoad 相同。
*/
/*
	Copyright (C) 2026, Sakura Editor Organization

	SPDX-License-Identifier: Zlib
*/
#include "StdAfx.h"
#include "sakura_core/SakuraCore.h"

#include "Funccode_enum.h"
#include "agent/CSearchAgent.h"
#include "basis/CEol.h"
#include "charset/CCodeFactory.h"
#include "charset/CCodeMediator.h"
#include "charset/CCodePage.h"
#include "charset/CUnicode.h"
#include "cmd/COpe.h"
#include "cmd/COpeBlk.h"
#include "cmd/COpeBuf.h"
#include "doc/logic/CDocLine.h"
#include "doc/logic/CDocLineMgr.h"
#include "doc/layout/CLayout.h"
#include "doc/layout/CLayoutMgr.h"
#include "docplus/CModifyManager.h"
#include "view/colors/EColorIndexType.h"
#include "mem/CMemoryIterator.h"
#include "config/app_constants.h"
#include "env/CDocTypeManager.h"
#include "CSelectLang.h"
#include "env/CShareData.h"
#include "env/CShareData_IO.h"
#include "env/DLLSHAREDATA.h"
#include "extmodule/CBregexp.h"
#include "io/CBinaryStream.h"
#include "io/CFileLoad.h"
#include "util/file.h"
#include "sakura_platform_hooks.h"

#include <atomic>
#include <type_traits>
#include <utility>

namespace sakura::core {

// 公开的数值与原版相同
static_assert(encoding::SJIS == CODE_SJIS && encoding::JIS == CODE_JIS && encoding::EUC == CODE_EUC);
static_assert(encoding::UTF16LE == CODE_UNICODE && encoding::UTF8 == CODE_UTF8 && encoding::UTF7 == CODE_UTF7);
static_assert(encoding::UTF16BE == CODE_UNICODEBE && encoding::CESU8 == CODE_CESU8 && encoding::Latin1 == CODE_LATIN1);
static_assert(encoding::UTF32LE == CODE_UTF32LE && encoding::UTF32BE == CODE_UTF32BE);
static_assert(encoding::AutoDetect == CODE_AUTODETECT && encoding::None == CODE_NONE);
static_assert(static_cast<int>(Eol::None) == static_cast<int>(EEolType::none));
static_assert(static_cast<int>(Eol::CRLF) == static_cast<int>(EEolType::cr_and_lf));
static_assert(static_cast<int>(Eol::LF) == static_cast<int>(EEolType::line_feed));
static_assert(static_cast<int>(Eol::CR) == static_cast<int>(EEolType::carriage_return));
static_assert(static_cast<int>(Eol::NEL) == static_cast<int>(EEolType::next_line));
static_assert(static_cast<int>(Eol::LineSeparator) == static_cast<int>(EEolType::line_separator));
static_assert(static_cast<int>(Eol::ParagraphSeparator) == static_cast<int>(EEolType::paragraph_separator));
static_assert(command::FileSave == F_FILESAVE && command::Undo == F_UNDO && command::Redo == F_REDO);
static_assert(command::NewLineCRLF == F_CHGMOD_EOL_CRLF && command::NewLineLF == F_CHGMOD_EOL_LF && command::NewLineCR == F_CHGMOD_EOL_CR);
static_assert(command::NewLineNEL == F_CHGMOD_EOL_NEL && command::NewLinePS == F_CHGMOD_EOL_PS && command::NewLineLS == F_CHGMOD_EOL_LS);
static_assert(std::is_same_v<Text::value_type, WCHAR>, "Text 与原版的 WCHAR 是同一种字符");
static_assert(static_cast<int>(WrapMethod::None) == WRAP_NO_TEXT_WRAP && static_cast<int>(WrapMethod::SettingWidth) == WRAP_SETTING_WIDTH);
static_assert(static_cast<int>(WrapMethod::WindowWidth) == WRAP_WINDOW_WIDTH);
static_assert(static_cast<int>(TabMark::String) == TABARROW_STRING && static_cast<int>(TabMark::ShortArrow) == TABARROW_SHORT);
static_assert(static_cast<int>(TabMark::LongArrow) == TABARROW_LONG);

namespace {

std::unique_ptr<CShareData> g_shareData;

//! 排版用的字体（原版 CEditWnd::GetLogfont）。SetLayoutFont 改变
LOGFONT g_layoutFont{};

//! 界面层登记的测量函数（SetTextMeasureFunction）
std::atomic<TextMeasureFunction> g_measure{ nullptr };

//! 平台层的测量接口（LOGFONT）→ 界面层的测量函数（字体名、大小）
int MeasureWithLogfont(const LOGFONT& lf, const WCHAR* text, size_t length)
{
	const TextMeasureFunction f = g_measure.load();
	if (!f) return 0;
	return f(lf.lfFaceName, lf.lfHeight < 0 ? -lf.lfHeight : lf.lfHeight, text, length);
}

//! 字体改变后，文字宽度的缓存重新开始（CEditDoc::OnChangeSetting 的 InitCharWidthCache）
void ApplyLayoutFont()
{
	SelectCharWidthCache(CWM_FONT_EDIT, CWM_CACHE_LOCAL);
	InitCharWidthCache(g_layoutFont);
}

bool ExtEolEnabled()
{
	return GetDllShareData().m_Common.m_sEdit.m_bEnableExtEol;
}

CLogicPoint ToLogic(const Position& p) { return CLogicPoint(CLogicInt(p.column), CLogicInt(p.line)); }
Position FromLogic(const CLogicPoint& p) { return Position{ p.GetY2(), p.GetX2() }; }

//! 与 view/CEditView_Command_New.cpp 的 StringToOpeLineData 相同：把文字分成行（换行符算在行内）
void StringToOpeLineData(const WCHAR* pLineData, int nLineDataLen, COpeLineData& lineData, int opeSeq)
{
	int nBegin = 0;
	int i;
	const bool bExtEol = ExtEolEnabled();
	for (i = 0; i < nLineDataLen; i++) {
		if (WCODE::IsLineDelimiter(pLineData[i], bExtEol)) {
			if (i + 1 < nLineDataLen && WCODE::CR == pLineData[i] && WCODE::LF == pLineData[i + 1]) {
				i++;
			}
			CLineData& insertLine = lineData.emplace_back(CLineData());
			insertLine.cmemLine.SetString(&pLineData[nBegin], i - nBegin + 1);
			insertLine.nSeq = opeSeq;
			nBegin = i + 1;
		}
	}
	if (nBegin < i) {
		CLineData& insertLine = lineData.emplace_back(CLineData());
		insertLine.cmemLine.SetString(&pLineData[nBegin], nLineDataLen - nBegin);
		insertLine.nSeq = opeSeq;
	}
}

Result FromConvertResult(EConvertResult r)
{
	switch (r) {
	case RESULT_COMPLETE: return Result::Ok;
	case RESULT_LOSESOME: return Result::LostSome;
	default:              return Result::Failed;
	}
}

} // namespace

// ---------------------------------------------------------------------------
// 启动和结束
// ---------------------------------------------------------------------------

bool Startup()
{
	if (g_shareData) return true;
	// 与原版 CControlProcess::InitializeProcess 相同的顺序
	CSelectLang::InitializeLanguageEnvironment();
	g_shareData = std::make_unique<CShareData>();
	g_shareData->InitShareData();
	if (!CShareData_IO::LoadShareData()) {
		CShareData_IO::SaveShareData();
	}
	g_shareData->RefreshString();
	// 排版的字体：先用共通设置的字体，界面层再用 SetLayoutFont 换成 Mac 的字体
	g_layoutFont = GetDllShareData().m_Common.m_sView.m_lf;
	ApplyLayoutFont();
	return true;
}

void SetTextMeasureFunction(TextMeasureFunction func)
{
	g_measure.store(func);
	sakura::platform::SetTextMeasureFunction(func ? &MeasureWithLogfont : nullptr);
	if (IsStarted()) ApplyLayoutFont();	// 测量方法变了，宽度的缓存重新开始
}

void SetLayoutFont(const Text& faceName, std::int32_t size)
{
	LOGFONT lf{};
	lf.lfHeight = -std::max(1, size);
	lf.lfWeight = FW_NORMAL;
	lf.lfCharSet = DEFAULT_CHARSET;
	lf.lfPitchAndFamily = FIXED_PITCH;	// 等宽字体：比半角宽的字符算半角的 2 倍
	const size_t n = std::min(faceName.size(), std::size(lf.lfFaceName) - 1);
	std::copy_n(faceName.data(), n, lf.lfFaceName);
	g_layoutFont = lf;
	ApplyLayoutFont();
}

void Shutdown(bool saveSettings)
{
	if (!g_shareData) return;
	if (saveSettings) {
		CShareData_IO::SaveShareData();
	}
	// 在静态对象析构之前销毁共通设置（第 21 步：析构顺序不对时 macOS 上会异常结束）
	g_shareData.reset();
}

bool IsStarted() { return g_shareData != nullptr; }

Text SettingsFilePath()
{
	return Text(sakura::path_to_wstring(GetIniFileName()));
}

// ---------------------------------------------------------------------------
// 编码、换行符、命令名
// ---------------------------------------------------------------------------

Text EncodingName(Encoding code)
{
	if (!IsValidCodeOrCPType(code)) return {};
	WCHAR name[100] = {};
	CCodePage::GetNameNormal(name, code);
	return Text(name);
}

bool IsValidEncoding(Encoding code)
{
	return IsValidCodeOrCPType(code);
}

Text EolText(Eol eol)
{
	const CEol cEol(static_cast<EEolType>(eol));
	return Text(cEol.GetValue2(), cEol.GetLen());
}

Text CommandName(FunctionCode code)
{
	if (code <= 0) return {};
	const WCHAR* psz = LS(static_cast<UINT>(code));
	return psz ? Text(psz) : Text();
}

// ---------------------------------------------------------------------------
// 文档
// ---------------------------------------------------------------------------

struct Document::Impl {
	CDocLineMgr lines;
	CLayoutMgr layout;			//!< 排版（第 27 步）。行数据之后析构
	STypeConfig typeConfig{};	//!< 类型别设置的复制（原版 CDocType::m_typeConfig）。layout 指着它
	int wrapMethodCur = WRAP_SETTING_WIDTH;	//!< 现在的折り返し方法（原版 CEditDoc::m_nTextWrapMethodCur）
	CKetaXInt wrapColumnsCur{ 80 };			//!< 现在的折り返し桁数
	COpeBuf opeBuf;
	COpeBlk* pOpeBlk = nullptr;	//!< BeginEdit 中的操作块（原版 CViewCommander 的 m_pcOpeBlk）
	int editDepth = 0;
	bool modified = false;
	CEol newLineEol{ EEolType::cr_and_lf };
	FileInfo info;
	Text lastSearchError;

	void ResetForType(const Text& path)
	{
		// 按文件名决定类型别设置（CDocTypeManager::GetDocumentTypeOfPath）
		const CTypeConfig type = path.empty() ? CTypeConfig(0) : CDocTypeManager().GetDocumentTypeOfPath(path.c_str());
		info.typeIndex = type.GetIndex();
		if (!CDocTypeManager().GetTypeConfig(type, typeConfig)) {
			(void)CDocTypeManager().GetTypeConfig(CTypeConfig(0), typeConfig);
		}
		const STypeConfigMini* mini = nullptr;
		if (CDocTypeManager().GetTypeConfigMini(type, &mini)) {
			info.typeName = Text(mini->m_szTypeName.c_str());
		}
	}

	const STypeConfigMini* TypeMini() const
	{
		const STypeConfigMini* mini = nullptr;
		if (!CDocTypeManager().GetTypeConfigMini(CTypeConfig(info.typeIndex), &mini)) return nullptr;
		return mini;
	}

	//! 与 CDocEditor::OnAfterLoad 相同：输入换行符用类型别设置的默认值，第一行有换行符时用它
	void ResetNewLineEol()
	{
		const STypeConfigMini* mini = TypeMini();
		if (mini && info.encoding == mini->m_encoding.m_eDefaultCodetype) {
			newLineEol.SetType(mini->m_encoding.m_eDefaultEoltype);
		} else {
			newLineEol.SetType(EEolType::cr_and_lf);
		}
		if (const CDocLine* pFirst = lines.GetLine(CLogicInt(0)); pFirst && pFirst->GetEol().IsValid()) {
			newLineEol.SetType(pFirst->GetEol().GetType());
		}
	}

	//! 指向换行符中间或之后的位置（正则表达式匹配的末尾等）改成下一行的开头
	Position NormalizePosition(const CLogicPoint& pt) const
	{
		const CDocLine* pLine = lines.GetLine(pt.GetY2());
		if (pLine && pt.GetX2() > pLine->GetLengthWithoutEOL()) {
			return Position{ pt.GetY2() + 1, 0 };
		}
		return FromLogic(pt);
	}

	bool IsValidPosition(const Position& p) const
	{
		const int nLines = lines.GetLineCount();
		if (p.line < 0 || p.column < 0) return false;
		if (p.line == nLines) {
			// 文档末尾（EOF）：空文档的开头，或者最后一行以换行结束时的下一行开头
			if (p.column != 0) return false;
			if (nLines == 0) return true;
			const CDocLine* pLast = lines.GetLine(CLogicInt(nLines - 1));
			return pLast && pLast->GetEol().IsValid();
		}
		if (p.line > nLines) return false;
		const CDocLine* pLine = lines.GetLine(CLogicInt(p.line));
		return pLine && p.column <= pLine->GetLengthWithoutEOL();
	}

	/*!
		与 ReplaceData_CEditView3 的 bFastMode 相同的替换。
		@param pInsData   [in] 要插入的数据（内容会被移走）。可以是 nullptr
		@param pDeleted   [out] 被删除的数据。可以是 nullptr
		@param pnInsSeq   [out] 插入的行原来的序号
	*/
	CLogicPoint ReplaceRaw(const CLogicRange& range, COpeLineData* pInsData, COpeLineData* pDeleted, int nDelSeq, int* pnInsSeq)
	{
		// 经过排版来替换（CLayoutMgr::ReplaceData_CLayoutMgr 里调用 CSearchAgent::ReplaceData），排版随着更新
		LayoutReplaceArg arg;
		layout.LogicToLayout(range, &arg.sDelRange);
		arg.pcmemDeleted = pDeleted;
		arg.pInsData = pInsData;
		arg.nDelSeq = nDelSeq;
		layout.ReplaceData_CLayoutMgr(&arg);
		if (pnInsSeq) *pnInsSeq = arg.nInsSeq;
		CLogicPoint ptNew;
		layout.LayoutToLogic(arg.ptLayoutNew, &ptNew);
		return ptNew;
	}

	//! 折り返し方法回到类型别设置（CLoadAgent::OnAfterLoad：解除临时设置）
	void ResetWrap()
	{
		wrapMethodCur = typeConfig.m_nTextWrapMethod;
		wrapColumnsCur = typeConfig.m_nMaxLineKetas;
	}

	/*!
		按现在的设置重新排版（CEditDoc::OnChangeSetting、CLoadAgent::OnLoad 的 SetLayoutInfo）。
		「指定桁で折り返す」以外的折り返し桁数：「折り返さない」是 MAXLINEKETAS，
		「右端で折り返す」是界面层按窗口宽度给的桁数（SetWrap）。
	*/
	void DoLayout()
	{
		const STypeConfig& ref = typeConfig;
		CKetaXInt nMaxLineKetas = wrapColumnsCur;
		if (wrapMethodCur == WRAP_NO_TEXT_WRAP) {
			nMaxLineKetas = CKetaXInt(MAXLINEKETAS);
		}
		layout.m_nTextWrapMethodCurMac = wrapMethodCur;
		// CLoadAgent::OnLoad：读入文件后重新计算 TAB 位置（TSV 模式）
		if (ref.m_nTsvMode != TSV_MODE_NONE) {
			layout.m_tsvInfo.m_nTsvMode = ref.m_nTsvMode;
			layout.m_tsvInfo.CalcTabLength(&lines);
		}
		layout.SetLayoutInfo(true, false, ref, ref.m_nTabSpace, ref.m_nTsvMode, nMaxLineKetas, CLayoutXInt(-1), &g_layoutFont);
		// 「折り返さない」时计算文字的最大宽度，其他时候清除
		if (wrapMethodCur == WRAP_NO_TEXT_WRAP) {
			layout.CalculateTextWidth(FALSE);
		} else {
			layout.ClearLayoutLineWidth();
		}
	}

	//! 编辑（记入撤销缓冲）。序号与 ReplaceData_CEditView 相同
	CLogicPoint ReplaceWithUndo(const CLogicRange& range, const WCHAR* pData, int nDataLen)
	{
		const int opeSeq = opeBuf.GetNextSeq();
		COpeLineData insData;
		if (0 < nDataLen) {
			StringToOpeLineData(pData, nDataLen, insData, opeSeq);
		}
		auto* pcReplaceOpe = new CReplaceOpe();
		pcReplaceOpe->m_ptCaretPos_PHY_Before = range.GetFrom();
		pcReplaceOpe->m_ptCaretPos_PHY_To = range.GetTo();
		COpeLineData deleted;
		int nInsSeq = 0;
		const CLogicPoint ptNew = ReplaceRaw(range, 0 < nDataLen ? &insData : nullptr, &deleted, opeSeq, &nInsSeq);
		pcReplaceOpe->m_pcmemDataDel.swap(deleted);
		pcReplaceOpe->m_ptCaretPos_PHY_After = ptNew;
		pcReplaceOpe->m_nOrgInsSeq = nInsSeq;

		const bool bOwnBlock = (pOpeBlk == nullptr);
		if (bOwnBlock) pOpeBlk = new COpeBlk();
		pOpeBlk->AppendOpe(pcReplaceOpe);
		if (bOwnBlock) CommitBlock();
		modified = true;
		return ptNew;
	}

	//! 把操作块放进撤销缓冲（CEditView::SetUndoBuffer）
	void CommitBlock()
	{
		if (!pOpeBlk) return;
		if (0 < pOpeBlk->GetNum()) {
			opeBuf.AppendOpeBlk(pOpeBlk);	// 之后由 COpeBuf 负责释放
		} else {
			delete pOpeBlk;
		}
		pOpeBlk = nullptr;
	}

	void ClearDocument()
	{
		if (pOpeBlk) {
			delete pOpeBlk;
			pOpeBlk = nullptr;
		}
		editDepth = 0;
		opeBuf.ClearAll();
		// 排版行指着行数据，先清空排版
		layout._Empty();
		layout.Init();
		lines.DeleteAllLine();
		modified = false;
	}
};

Document::Document() : m_impl(std::make_unique<Impl>())
{
	m_impl->layout.Create(nullptr, &m_impl->lines);	// Mac 版没有 CEditDoc
}

Document::~Document()
{
	if (m_impl && m_impl->pOpeBlk) delete m_impl->pOpeBlk;
}

std::unique_ptr<Document> Document::Create()
{
	if (!IsStarted()) return nullptr;
	std::unique_ptr<Document> doc(new Document());
	auto& d = *doc->m_impl;
	d.ResetForType(Text());
	// 新文档的编码是类型别设置（基本）的默认值
	if (const STypeConfigMini* mini = d.TypeMini()) {
		d.info.encoding = mini->m_encoding.m_eDefaultCodetype;
		d.info.bom = mini->m_encoding.m_bDefaultBom;
	}
	d.ResetNewLineEol();
	d.ResetWrap();
	d.DoLayout();
	return doc;
}

// ----- 打开、保存 -----

Result Document::Open(const Text& path, const OpenOptions& options)
{
	auto& d = *m_impl;
	if (path.empty()) return Result::InvalidArgument;
	if (options.encoding != encoding::AutoDetect && !IsValidCodeOrCPType(options.encoding)) return Result::InvalidArgument;

	d.ClearDocument();
	d.info = FileInfo{};
	d.ResetForType(path);
	d.ResetWrap();
	const STypeConfigMini* type = d.TypeMini();
	if (!type) return Result::Failed;

	// 以下与 CReadManager::ReadFile_To_CDocLineMgr 相同
	ECodeType eCharCode = static_cast<ECodeType>(options.encoding);
	if (CODE_AUTODETECT == eCharCode) {
		CCodeMediator cmediator(type->m_encoding);
		eCharCode = cmediator.CheckKanjiCodeOfFile(path.c_str());
	}
	if (!IsValidCodeOrCPType(eCharCode)) {
		eCharCode = type->m_encoding.m_eDefaultCodetype;
	}
	bool bBom;
	if (eCharCode == type->m_encoding.m_eDefaultCodetype) {
		bBom = type->m_encoding.m_bDefaultBom;
	} else {
		bBom = CCodeTypeName(eCharCode).IsBomDefOn();
	}

	EConvertResult eRet = RESULT_COMPLETE;
	try {
		CFileLoad cfl(type->m_encoding);
		cfl.FileOpen(path.c_str(), true, eCharCode, GetDllShareData().m_Common.m_sFile.GetAutoMIMEdecode(), &bBom);
		CNativeW cUnicodeBuffer;
		CEol cEol;
		EConvertResult eRead;
		const bool bExtEol = ExtEolEnabled();
		while (RESULT_FAILURE != (eRead = cfl.ReadLine(&cUnicodeBuffer, &cEol))) {
			if (eRead == RESULT_LOSESOME) {
				eRet = RESULT_LOSESOME;
			}
			// CDocEditAgent::AddLineStrX
			d.lines.AddNewLine()->SetDocLineString(cUnicodeBuffer.GetStringPtr(), cUnicodeBuffer.GetStringLength(), bExtEol);
		}
		cfl.FileClose();
	}
	catch (const CError_FileOpen&) {
		d.lines.DeleteAllLine();
		d.DoLayout();
		return Result::Failed;
	}
	catch (const CError_FileRead&) {
		d.lines.DeleteAllLine();
		d.DoLayout();
		return Result::Failed;
	}

	d.info.path = path;
	d.info.encoding = eCharCode;
	d.info.bom = bBom;
	d.ResetNewLineEol();
	d.DoLayout();	// CLoadAgent::OnLoad
	return FromConvertResult(eRet);
}

Result Document::SaveAs(const Text& path, const SaveOptions& options)
{
	auto& d = *m_impl;
	if (path.empty()) return Result::InvalidArgument;
	const ECodeType eCharCode = static_cast<ECodeType>(options.encoding.value_or(d.info.encoding));
	if (!IsValidCodeOrCPType(eCharCode)) return Result::InvalidArgument;
	const bool bBom = options.bom.value_or(d.info.bom);

	// 统一换行符（CSaveAgent::OnPreBeforeSave → CDocVisitor::SetAllEol，可以撤销）
	if (options.eol != Eol::None) {
		const CEol cEol(static_cast<EEolType>(options.eol));
		BeginEdit();
		for (int nLine = 0; ; nLine++) {
			const CDocLine* pcDocLine = d.lines.GetLine(CLogicInt(nLine));
			if (!pcDocLine) break;
			if (pcDocLine->GetEol().IsValid() && pcDocLine->GetEol() != cEol) {
				CLogicRange sRange;
				sRange.SetFrom(CLogicPoint(pcDocLine->GetLengthWithoutEOL(), CLogicInt(nLine)));
				sRange.SetTo(CLogicPoint(pcDocLine->GetLengthWithEOL(), CLogicInt(nLine)));
				d.ReplaceWithUndo(sRange, cEol.GetValue2(), cEol.GetLen());
			}
		}
		EndEdit();
		d.newLineEol = cEol;	// CSaveAgent::OnAfterSave：输入换行符也改掉
	}

	// 以下与 CWriteManager::WriteFile_From_CDocLineMgr 相同
	EConvertResult nRetVal = RESULT_COMPLETE;
	std::unique_ptr<CCodeBase> pcCodeBase(CCodeFactory::CreateCodeBase(eCharCode, 0));
	{
		// 先试一下能否转换
		CNativeW buffer = LTEXT("abcde");
		CMemory tmp;
		if (pcCodeBase->UnicodeToCode(buffer, &tmp) == RESULT_FAILURE) {
			return Result::Failed;
		}
	}
	try {
		CBinaryOutputStream out(path.c_str(), true);
		const CDocLine* pcDocLine = d.lines.GetDocLineTop();
		// 1行目
		{
			CMemory cmemOutputBuffer;
			CNativeW cstrSrc;
			CMemory cstrBomCheck;
			pcCodeBase->GetBom(&cstrBomCheck);
			if (bBom && 0 < cstrBomCheck.GetRawLength()) {
				// 第一行前加 BOM（只在这个编码有 BOM 时）
				CUnicode().GetBom(cstrSrc._GetMemory());
			}
			if (pcDocLine) {
				cstrSrc.AppendNativeData(pcDocLine->_GetDocLineDataWithEOL());
			}
			const EConvertResult e = pcCodeBase->UnicodeToCode(cstrSrc, &cmemOutputBuffer);
			if (e == RESULT_LOSESOME) nRetVal = RESULT_LOSESOME;
			if (e == RESULT_FAILURE) throw CError_FileWrite();
			out.Write(cmemOutputBuffer.GetRawPtr(), cmemOutputBuffer.GetRawLength());
			if (pcDocLine) pcDocLine = pcDocLine->GetNextLine();
		}
		CMemory cmemOutputBuffer;
		while (pcDocLine) {
			const EConvertResult e = pcCodeBase->UnicodeToCode(pcDocLine->_GetDocLineDataWithEOL(), &cmemOutputBuffer);
			if (e == RESULT_LOSESOME && nRetVal == RESULT_COMPLETE) nRetVal = RESULT_LOSESOME;
			if (e == RESULT_FAILURE) throw CError_FileWrite();
			out.Write(cmemOutputBuffer.GetRawPtr(), cmemOutputBuffer.GetRawLength());
			pcDocLine = pcDocLine->GetNextLine();
		}
		out.Close();
	}
	catch (const CError_FileOpen&) {
		return Result::Failed;
	}
	catch (const CError_FileWrite&) {
		return Result::Failed;
	}

	// CDocEditor::OnAfterSave：清除修改标记，告诉撤销缓冲当前位置是未修改的状态
	const bool bTypeChanged = (d.info.path != path);
	d.info.path = path;
	d.info.encoding = eCharCode;
	d.info.bom = bBom;
	if (bTypeChanged) {
		// 另存为：扩展名变了，类型别设置也跟着变（CEditDoc::OnChangeType → OnChangeSetting 重新排版）
		const std::int32_t oldType = d.info.typeIndex;
		d.ResetForType(path);
		if (d.info.typeIndex != oldType) {
			d.ResetWrap();
			d.DoLayout();
		}
	}
	d.modified = false;
	d.opeBuf.SetNoModified();
	return FromConvertResult(nRetVal);
}

Result Document::Save()
{
	if (m_impl->info.path.empty()) return Result::InvalidArgument;
	return SaveAs(Text(m_impl->info.path));
}

const FileInfo& Document::GetFileInfo() const { return m_impl->info; }
bool Document::IsModified() const { return m_impl->modified; }

// ----- 内容 -----

std::int32_t Document::LineCount() const { return m_impl->lines.GetLineCount(); }

Text Document::GetLine(std::int32_t line, bool withEol) const
{
	if (line < 0) return {};
	const CDocLine* p = m_impl->lines.GetLine(CLogicInt(line));
	if (!p) return {};
	return Text(p->GetPtr(), withEol ? p->GetLengthWithEOL() : p->GetLengthWithoutEOL());
}

Eol Document::GetLineEol(std::int32_t line) const
{
	if (line < 0) return Eol::None;
	const CDocLine* p = m_impl->lines.GetLine(CLogicInt(line));
	if (!p) return Eol::None;
	return static_cast<Eol>(p->GetEol().GetType());
}

Text Document::GetText() const
{
	Text text;
	for (const CDocLine* p = m_impl->lines.GetDocLineTop(); p; p = p->GetNextLine()) {
		text.append(p->GetPtr(), p->GetLengthWithEOL());
	}
	return text;
}

Text Document::GetText(const Range& range) const
{
	const auto& d = *m_impl;
	if (!d.IsValidPosition(range.from) || !d.IsValidPosition(range.to) || range.to < range.from) return {};
	Text text;
	for (int line = range.from.line; line <= range.to.line && line < d.lines.GetLineCount(); line++) {
		const CDocLine* p = d.lines.GetLine(CLogicInt(line));
		const int begin = (line == range.from.line) ? range.from.column : 0;
		const int end = (line == range.to.line) ? range.to.column : p->GetLengthWithEOL();
		text.append(p->GetPtr() + begin, end - begin);
	}
	return text;
}

Position Document::EndPosition() const
{
	const auto& d = *m_impl;
	const int nLines = d.lines.GetLineCount();
	if (nLines == 0) return Position{};
	const CDocLine* pLast = d.lines.GetLine(CLogicInt(nLines - 1));
	if (pLast->GetEol().IsValid()) return Position{ nLines, 0 };
	return Position{ nLines - 1, pLast->GetLengthWithoutEOL() };
}

// ----- 编辑 -----

Result Document::Replace(const Range& range, const Text& text, Position* pNewEnd)
{
	auto& d = *m_impl;
	if (!d.IsValidPosition(range.from) || !d.IsValidPosition(range.to) || range.to < range.from) {
		return Result::InvalidArgument;
	}
	if (range.IsEmpty() && text.empty()) {
		if (pNewEnd) *pNewEnd = range.from;
		return Result::Ok;
	}
	const CLogicRange sRange(ToLogic(range.from), ToLogic(range.to));
	const CLogicPoint ptNew = d.ReplaceWithUndo(sRange, text.data(), static_cast<int>(text.size()));
	if (pNewEnd) *pNewEnd = FromLogic(ptNew);
	return Result::Ok;
}

Result Document::Insert(const Position& at, const Text& text, Position* pNewEnd)
{
	return Replace(Range{ at, at }, text, pNewEnd);
}

Result Document::Delete(const Range& range)
{
	return Replace(range, Text());
}

void Document::BeginEdit()
{
	auto& d = *m_impl;
	if (d.editDepth++ == 0 && !d.pOpeBlk) {
		d.pOpeBlk = new COpeBlk();
	}
}

void Document::EndEdit()
{
	auto& d = *m_impl;
	if (d.editDepth <= 0) return;
	if (--d.editDepth == 0) {
		d.CommitBlock();
	}
}

bool Document::CanUndo() const { return m_impl->opeBuf.IsEnableUndo(); }
bool Document::CanRedo() const { return m_impl->opeBuf.IsEnableRedo(); }

Result Document::Undo(Position* pCaret)
{
	auto& d = *m_impl;
	if (0 < d.editDepth) return Result::InvalidArgument;	// 编辑还没结束
	bool bIsModified = false;
	COpeBlk* pcOpeBlk = d.opeBuf.DoUndo(&bIsModified);
	if (!pcOpeBlk) return Result::InvalidArgument;
	CLogicPoint ptCaret;
	// Command_UNDO：从后面的操作开始撤销
	for (int i = pcOpeBlk->GetNum() - 1; i >= 0; i--) {
		COpe* pcOpe = pcOpeBlk->GetOpe(i);
		switch (pcOpe->GetCode()) {
		case OPE_REPLACE: {
			auto* pcReplaceOpe = static_cast<CReplaceOpe*>(pcOpe);
			const CLogicRange cSelectLogic(pcOpe->m_ptCaretPos_PHY_Before, pcOpe->m_ptCaretPos_PHY_After);
			d.ReplaceRaw(cSelectLogic, &pcReplaceOpe->m_pcmemDataDel, &pcReplaceOpe->m_pcmemDataIns,
						 pcReplaceOpe->m_nOrgInsSeq, &pcReplaceOpe->m_nOrgDelSeq);
			pcReplaceOpe->m_pcmemDataDel.clear();
			break;
		}
		default:
			// Mac 版核心库只记录 OPE_REPLACE（原版 2013 年以后的编辑也只记录 ReplaceOpe）
			break;
		}
		ptCaret = pcOpe->m_ptCaretPos_PHY_Before;
	}
	d.modified = bIsModified;
	if (pCaret) *pCaret = FromLogic(ptCaret);
	return Result::Ok;
}

Result Document::Redo(Position* pCaret)
{
	auto& d = *m_impl;
	if (0 < d.editDepth) return Result::InvalidArgument;
	bool bIsModified = false;
	COpeBlk* pcOpeBlk = d.opeBuf.DoRedo(&bIsModified);
	if (!pcOpeBlk) return Result::InvalidArgument;
	CLogicPoint ptCaret;
	// Command_REDO：从前面的操作开始重做
	for (int i = 0; i < pcOpeBlk->GetNum(); i++) {
		COpe* pcOpe = pcOpeBlk->GetOpe(i);
		switch (pcOpe->GetCode()) {
		case OPE_REPLACE: {
			auto* pcReplaceOpe = static_cast<CReplaceOpe*>(pcOpe);
			const CLogicRange cSelectLogic(pcOpe->m_ptCaretPos_PHY_Before, pcReplaceOpe->m_ptCaretPos_PHY_To);
			d.ReplaceRaw(cSelectLogic, &pcReplaceOpe->m_pcmemDataIns, &pcReplaceOpe->m_pcmemDataDel,
						 pcReplaceOpe->m_nOrgDelSeq, &pcReplaceOpe->m_nOrgInsSeq);
			pcReplaceOpe->m_pcmemDataIns.clear();
			break;
		}
		default:
			break;
		}
		ptCaret = pcOpe->m_ptCaretPos_PHY_After;
	}
	d.modified = bIsModified;
	if (pCaret) *pCaret = FromLogic(ptCaret);
	return Result::Ok;
}

Eol Document::GetNewLineEol() const { return static_cast<Eol>(m_impl->newLineEol.GetType()); }

void Document::SetNewLineEol(Eol eol)
{
	// Command_CHGMOD_EOL：只接受有效的换行符
	if (CEol::IsValid(static_cast<EEolType>(eol))) {
		m_impl->newLineEol.SetType(static_cast<EEolType>(eol));
	}
}

// ----- 查找、替换 -----

namespace {

SSearchOption ToSearchOption(const SearchOptions& o)
{
	return SSearchOption(o.regularExpression, o.matchCase, o.wholeWord);
}

//! 准备查找条件（CSearchStringPattern::SetPattern，正则表达式在这里编译）
struct PreparedPattern {
	SSearchOption option;
	CBregexp regexp;
	CSearchStringPattern pattern;
	bool ok = false;
	Text error;

	PreparedPattern(const Text& key, const SearchOptions& o)
		: option(ToSearchOption(o))
	{
		if (key.empty()) {
			error = u"empty pattern";
			return;
		}
		ok = pattern.SetPattern(nullptr, key.c_str(), key.size(), option, &regexp);
		if (!ok) {
			const WCHAR* msg = option.bRegularExp ? regexp.GetLastMessage() : nullptr;
			error = (msg && *msg) ? Text(msg) : Text(u"invalid pattern");
		}
	}
};

} // namespace

std::optional<Range> Document::Find(const Text& pattern, const Position& from, SearchDirection direction, const SearchOptions& options)
{
	auto& d = *m_impl;
	d.lastSearchError.clear();
	if (!d.IsValidPosition(from)) return std::nullopt;
	PreparedPattern prepared(pattern, options);
	if (!prepared.ok) {
		d.lastSearchError = prepared.error;
		return std::nullopt;
	}
	CLogicRange match;
	const ESearchDirection eDir = (direction == SearchDirection::Forward) ? SEARCH_FORWARD : SEARCH_BACKWARD;
	if (!CSearchAgent(&d.lines).SearchWord(ToLogic(from), eDir, &match, prepared.pattern)) {
		return std::nullopt;
	}
	return Range{ d.NormalizePosition(match.GetFrom()), d.NormalizePosition(match.GetTo()) };
}

std::vector<Range> Document::FindAll(const Text& pattern, const SearchOptions& options)
{
	auto& d = *m_impl;
	d.lastSearchError.clear();
	std::vector<Range> result;
	PreparedPattern prepared(pattern, options);
	if (!prepared.ok) {
		d.lastSearchError = prepared.error;
		return result;
	}
	// 逐行从前往后找（与 CSearchAgent::SearchWord 相同，用 CLineMatchFinder）
	const CLineMatchFinder finder(prepared.pattern, prepared.pattern.GetRegexp());
	int nLine = 0;
	for (const CDocLine* p = d.lines.GetDocLineTop(); p; p = p->GetNextLine(), nLine++) {
		const WCHAR* pLine = p->GetPtr();
		const int nLen = p->GetLengthWithEOL();
		int nStart = 0;
		while (nStart < nLen) {
			const auto m = finder.Find(pLine, nLen, nStart);
			if (!m) break;
			result.push_back(Range{ d.NormalizePosition(CLogicPoint(m->nIndex, nLine)),
									d.NormalizePosition(CLogicPoint(m->nIndex + m->nLength, nLine)) });
			nStart = CLineMatchFinder::GetNextStart(pLine, nLen, *m);
		}
	}
	return result;
}

std::int32_t Document::ReplaceAll(const Text& pattern, const Text& replacement, const SearchOptions& options)
{
	auto& d = *m_impl;
	d.lastSearchError.clear();
	PreparedPattern prepared(pattern, options);
	if (!prepared.ok) {
		d.lastSearchError = prepared.error;
		return -1;
	}

	// 准备正则表达式的替换（Command_REPLACE_ALL：一括置换用 optGlobal）
	CBregexp cRegexp;
	if (prepared.option.bRegularExp) {
		if (!InitRegexp(nullptr, cRegexp, false)) {
			d.lastSearchError = u"regular expression library is not available";
			return -1;
		}
		int nFlag = prepared.option.bLoHiCase ? CBregexp::optCaseSensitive : CBregexp::optNothing;
		nFlag |= CBregexp::optGlobal;
		if (!cRegexp.Compile(pattern.c_str(), replacement.c_str(), nFlag)) {
			d.lastSearchError = Text(cRegexp.GetLastMessage());
			return -1;
		}
	}

	std::int32_t nReplaceNum = 0;
	BeginEdit();
	CLogicPoint ptFrom(CLogicInt(0), CLogicInt(0));
	CLogicRange match;
	while (CSearchAgent(&d.lines).SearchWord(ptFrom, SEARCH_FORWARD, &match, prepared.pattern)) {
		const CLogicInt nLogicLineNum = match.GetFrom().GetY2();
		const CDocLine* pcDocLine = d.lines.GetLine(nLogicLineNum);
		if (!pcDocLine) break;
		CLogicPoint ptNext;
		if (prepared.option.bRegularExp) {
			// 按行替换：把匹配开头到行末（包括换行符）换成替换后的文字
			const WCHAR* pLine = pcDocLine->GetPtr();
			const CLogicInt nIdx = match.GetFrom().GetX2();
			const CLogicInt nLen = pcDocLine->GetLengthWithEOL();
			const int nReplace = cRegexp.Replace(pLine, nLen, nIdx);
			if (nReplace <= 0) {
				ptNext = CLogicPoint(CLogicInt(0), nLogicLineNum + 1);
			} else {
				nReplaceNum += nReplace;
				const Text replaced(cRegexp.GetString(), cRegexp.GetStringLen());
				const CLogicRange sRange(CLogicPoint(nIdx, nLogicLineNum), CLogicPoint(nLen, nLogicLineNum));
				ptNext = d.ReplaceWithUndo(sRange, replaced.data(), static_cast<int>(replaced.size()));
				// 替换后的文字不以换行结束时，跳到下一行（这一行已经用 optGlobal 全部替换了）
				if (ptNext.GetX2() != 0) {
					ptNext = CLogicPoint(CLogicInt(0), ptNext.GetY2() + 1);
				}
			}
		} else {
			ptNext = d.ReplaceWithUndo(match, replacement.data(), static_cast<int>(replacement.size()));
			nReplaceNum++;
		}
		if (ptNext.GetY2() >= d.lines.GetLineCount()) break;
		ptFrom = ptNext;
	}
	EndEdit();
	return nReplaceNum;
}

Text Document::GetLastSearchError() const { return m_impl->lastSearchError; }

// ----- 命令 -----

bool Document::IsCommandSupported(FunctionCode code)
{
	switch (code) {
	case F_FILESAVE:
	case F_UNDO:
	case F_REDO:
	case F_CHGMOD_EOL_CRLF:
	case F_CHGMOD_EOL_LF:
	case F_CHGMOD_EOL_CR:
	case F_CHGMOD_EOL_NEL:
	case F_CHGMOD_EOL_PS:
	case F_CHGMOD_EOL_LS:
		return true;
	default:
		return false;
	}
}

bool Document::IsCommandEnabled(FunctionCode code) const
{
	const auto& d = *m_impl;
	switch (code) {
	case F_FILESAVE:
		// IsFuncEnable：有修改时，或者设置了“无修改也覆盖保存”时
		if (d.info.path.empty()) return false;	// 无题文档要“另存为”（界面的步骤）
		return d.modified || GetDllShareData().m_Common.m_sFile.m_bEnableUnmodifiedOverwrite;
	case F_UNDO: return CanUndo();
	case F_REDO: return CanRedo();
	case F_CHGMOD_EOL_CRLF:
	case F_CHGMOD_EOL_LF:
	case F_CHGMOD_EOL_CR:
		return true;
	case F_CHGMOD_EOL_NEL:
	case F_CHGMOD_EOL_PS:
	case F_CHGMOD_EOL_LS:
		return ExtEolEnabled();
	default:
		return false;
	}
}

Result Document::ExecuteCommand(FunctionCode code)
{
	if (!IsCommandSupported(code)) return Result::NotSupported;
	switch (code) {
	case F_FILESAVE:        return Save();
	case F_UNDO:            return Undo();
	case F_REDO:            return Redo();
	case F_CHGMOD_EOL_CRLF: SetNewLineEol(Eol::CRLF); return Result::Ok;
	case F_CHGMOD_EOL_LF:   SetNewLineEol(Eol::LF); return Result::Ok;
	case F_CHGMOD_EOL_CR:   SetNewLineEol(Eol::CR); return Result::Ok;
	case F_CHGMOD_EOL_NEL:  SetNewLineEol(Eol::NEL); return Result::Ok;
	case F_CHGMOD_EOL_PS:   SetNewLineEol(Eol::ParagraphSeparator); return Result::Ok;
	case F_CHGMOD_EOL_LS:   SetNewLineEol(Eol::LineSeparator); return Result::Ok;
	default:                return Result::NotSupported;
	}
}


// ----- 排版（第 27 步） -----

ViewSettings Document::GetViewSettings() const
{
	const auto& d = *m_impl;
	const STypeConfig& t = d.typeConfig;
	ViewSettings v;
	v.wrapMethod = static_cast<WrapMethod>(d.wrapMethodCur);
	v.wrapColumns = static_cast<std::int32_t>(d.wrapColumnsCur);
	v.typeWrapColumns = static_cast<std::int32_t>(t.m_nMaxLineKetas);
	v.tabColumns = static_cast<std::int32_t>(d.layout.GetTabSpaceKetas());
	v.columnSpacing = t.m_nColumnSpace;
	v.lineSpacing = t.m_nLineSpace;
	v.showLineNumbers = t.m_ColorInfoArr[COLORIDX_GYOU].m_bDisp;
	v.lineNumberPerLogicalLine = t.m_bLineNumIsCRLF;
	v.lineNumberMinDigits = t.m_nLineNumWidth;
	v.showTab = t.m_ColorInfoArr[COLORIDX_TAB].m_bDisp;
	v.tabMark = static_cast<TabMark>(t.m_bTabArrow);
	v.tabString = Text(t.m_szTabViewString.c_str());
	v.showSpace = t.m_ColorInfoArr[COLORIDX_SPACE].m_bDisp;
	v.showFullWidthSpace = t.m_ColorInfoArr[COLORIDX_ZENSPACE].m_bDisp;
	v.showEol = t.m_ColorInfoArr[COLORIDX_EOL].m_bDisp;
	v.showWrapMark = t.m_ColorInfoArr[COLORIDX_WRAP].m_bDisp;
	v.showEof = t.m_ColorInfoArr[COLORIDX_EOF].m_bDisp;
	v.hideHanging = t.m_bKinsokuHide;
	v.hangEol = t.m_bKinsokuRet;
	v.hangPunctuation = t.m_bKinsokuKuto;
	return v;
}

bool Document::SetWrap(WrapMethod method, std::int32_t columns)
{
	auto& d = *m_impl;
	const int nMethod = static_cast<int>(method);
	if (nMethod < WRAP_NO_TEXT_WRAP || WRAP_WINDOW_WIDTH < nMethod) return false;
	// 折り返し桁数的范围（与 CEditWnd::ChangeLayoutParam、ViewColNumToWrapColNum 相同）
	const CKetaXInt nColumns(std::clamp<std::int32_t>(columns, MINLINEKETAS, MAXLINEKETAS));
	if (nMethod == d.wrapMethodCur && (nMethod == WRAP_NO_TEXT_WRAP || nColumns == d.wrapColumnsCur)) {
		return false;
	}
	d.wrapMethodCur = nMethod;
	if (nMethod != WRAP_NO_TEXT_WRAP) d.wrapColumnsCur = nColumns;
	d.DoLayout();
	return true;
}

std::int32_t Document::WrapColumnsForWidth(std::int32_t width) const
{
	// CEditView::GetWrapOverhang：减去折り返し記号和ぶら下げ的宽度
	const auto& d = *m_impl;
	const STypeConfig& t = d.typeConfig;
	const std::int32_t nCharWidth = CharWidth();
	std::int32_t nMargin = nCharWidth;	// 折り返し記号
	if (!t.m_bKinsokuHide) {
		if (t.m_bKinsokuRet) nMargin += nCharWidth;		// 改行ぶら下げ
		if (t.m_bKinsokuKuto) nMargin += nCharWidth * 2;	// 句読点ぶら下げ
	}
	// CEditView::ViewColNumToWrapColNum：少于 MINLINEKETAS 时按 MINLINEKETAS
	return std::max<std::int32_t>(MINLINEKETAS, (width - nMargin) / std::max<std::int32_t>(1, nCharWidth));
}

void Document::Relayout()
{
	m_impl->DoLayout();
}

std::int32_t Document::LayoutLineCount() const
{
	return static_cast<std::int32_t>(m_impl->layout.GetLineCount());
}

LayoutLine Document::GetLayoutLine(std::int32_t line) const
{
	const CLayout* pLayout = m_impl->layout.SearchLineByLayoutY(CLayoutInt(line));
	if (line < 0 || !pLayout) return {};
	LayoutLine result;
	result.start = FromLogic(pLayout->GetLogicPos());
	result.length = pLayout->GetLengthWithoutEOL();
	result.eol = static_cast<Eol>(pLayout->GetLayoutEol().GetType());
	result.indent = static_cast<std::int32_t>(pLayout->GetIndent());
	return result;
}

std::vector<std::int32_t> Document::GetLayoutCharPositions(std::int32_t line) const
{
	const CLayout* pLayout = m_impl->layout.SearchLineByLayoutY(CLayoutInt(line));
	if (line < 0 || !pLayout) return { 0 };
	// 与 CEditView 的绘制相同，用 CMemoryIterator 一个字一个字地前进（包括 TAB 的展开、文字间隔）
	const int nLength = pLayout->GetLengthWithoutEOL();
	std::vector<std::int32_t> positions(nLength + 1, 0);
	CMemoryIterator it = m_impl->layout.CreateCMemoryIterator(pLayout);
	while (!it.end() && it.getIndex() < nLength) {
		it.scanNext();
		const int nIndex = it.getIndex();
		const std::int32_t x = static_cast<std::int32_t>(it.getColumn());
		for (int i = nIndex; i < nIndex + it.getIndexDelta() && i < nLength; i++) {
			positions[i] = x;	// 补充平面字符的后一半与前一半位置相同
		}
		it.addDelta();
	}
	positions[nLength] = static_cast<std::int32_t>(it.getColumn());
	return positions;
}

LayoutPosition Document::LogicToLayout(const Position& position) const
{
	CLayoutPoint ptLayout;
	m_impl->layout.LogicToLayout(ToLogic(position), &ptLayout);
	return LayoutPosition{ static_cast<std::int32_t>(ptLayout.GetY2()), static_cast<std::int32_t>(ptLayout.GetX2()) };
}

Position Document::LayoutToLogic(const LayoutPosition& position) const
{
	CLogicPoint ptLogic;
	m_impl->layout.LayoutToLogic(CLayoutPoint(CLayoutInt(position.x), CLayoutInt(position.line)), &ptLogic);
	return FromLogic(ptLogic);
}

std::int32_t Document::CharWidth() const
{
	return static_cast<std::int32_t>(m_impl->layout.GetWidthPerKeta());
}

std::int32_t Document::LayoutWidth() const
{
	const auto& d = *m_impl;
	if (d.wrapMethodCur == WRAP_NO_TEXT_WRAP) {
		return static_cast<std::int32_t>(d.layout.GetMaxTextWidth());
	}
	return static_cast<std::int32_t>(d.layout.GetMaxLineLayout());
}


// ---------------------------------------------------------------------------
// 颜色（第 28 步）
// ---------------------------------------------------------------------------

static_assert(static_cast<int>(ColorIndex::Text) == COLORIDX_TEXT);
static_assert(static_cast<int>(ColorIndex::Caret) == COLORIDX_CARET);
static_assert(static_cast<int>(ColorIndex::CaretIme) == COLORIDX_CARET_IME);
static_assert(static_cast<int>(ColorIndex::CaretLineBackground) == COLORIDX_CARETLINEBG);
static_assert(static_cast<int>(ColorIndex::CaretLineUnderline) == COLORIDX_UNDERLINE);
static_assert(static_cast<int>(ColorIndex::CursorColumnLine) == COLORIDX_CURSORVLINE);
static_assert(static_cast<int>(ColorIndex::LineNumber) == COLORIDX_GYOU);
static_assert(static_cast<int>(ColorIndex::LineNumberModified) == COLORIDX_GYOU_MOD);
static_assert(static_cast<int>(ColorIndex::EvenLineBackground) == COLORIDX_EVENLINEBG);
static_assert(static_cast<int>(ColorIndex::Tab) == COLORIDX_TAB);
static_assert(static_cast<int>(ColorIndex::FullWidthSpace) == COLORIDX_ZENSPACE);
static_assert(static_cast<int>(ColorIndex::Eol) == COLORIDX_EOL);
static_assert(static_cast<int>(ColorIndex::WrapMark) == COLORIDX_WRAP);
static_assert(static_cast<int>(ColorIndex::Eof) == COLORIDX_EOF);
static_assert(static_cast<int>(ColorIndex::Select) == COLORIDX_SELECT);

namespace {

//! COLORREF（0x00BBGGRR）→ 0xRRGGBB
std::uint32_t ToRgb(COLORREF c)
{
	const auto v = static_cast<std::uint32_t>(c);
	return ((v & 0xFFu) << 16) | (v & 0xFF00u) | ((v >> 16) & 0xFFu);
}

} // namespace

ColorSetting Document::GetColor(ColorIndex index) const
{
	const int i = static_cast<int>(index);
	if (i < 0 || COLORIDX_LAST <= i) return {};
	const ColorInfo& info = m_impl->typeConfig.m_ColorInfoArr[i];
	ColorSetting c;
	c.display = info.m_bDisp;
	c.bold = info.m_sFontAttr.m_bBoldFont;
	c.underline = info.m_sFontAttr.m_bUnderLine;
	c.text = ToRgb(info.m_sColorAttr.m_cTEXT);
	c.back = ToRgb(info.m_sColorAttr.m_cBACK);
	return c;
}

bool Document::IsLineModified(std::int32_t line) const
{
	const auto& d = *m_impl;
	// 原版 CTextDrawer::DispLineNumber：文档没有修改时一律不算
	if (!d.modified) return false;
	const CDocLine* pDocLine = d.lines.GetLine(CLogicInt(line));
	if (pDocLine == nullptr) return false;
	return CModifyVisitor().IsLineModified(pDocLine, d.opeBuf.GetNoModifiedSeq());
}


// ---------------------------------------------------------------------------
// 编辑命令（第 29 步）
//
// 与原版 view/CViewCalc.cpp、view/CEditView_Command_New.cpp、view/CEditView.cpp、
// cmd/CViewCommander_Clipboard.cpp、cmd/CViewCommander_Edit_advanced.cpp 的处理相同。
// 原版的光标、选择范围在 CEditView 里，这里由参数给出，结果作为返回值交给界面层。
// ---------------------------------------------------------------------------

namespace {

//! CViewCalc::LineColumnToIndex：排版行里横向位置 nColumn 处的字符下标（跨在 nColumn 上的字符算在前面）
CLogicInt LineColumnToIndex(const CLayoutMgr& mgr, const CLayout* pcLayout, CLayoutInt nColumn)
{
	CMemoryIterator it = mgr.CreateCMemoryIterator(pcLayout);
	while (!it.end()) {
		it.scanNext();
		if (it.getColumn() + it.getColumnDelta() > nColumn) {
			break;
		}
		it.addDelta();
	}
	return it.getIndex();
}

//! CViewCalc::LineColumnToIndex2：nColumn 在行末（包括换行符）之后时，pnLineAllColLen 是整行的宽度，否则是 0
CLogicInt LineColumnToIndex2(const CLayoutMgr& mgr, const CLayout* pcLayout, CLayoutInt nColumn, CLayoutInt* pnLineAllColLen)
{
	*pnLineAllColLen = CLayoutInt(0);
	CMemoryIterator it = mgr.CreateCMemoryIterator(pcLayout);
	while (!it.end()) {
		it.scanNext();
		if (it.getColumn() + it.getColumnDelta() > nColumn) {
			break;
		}
		it.addDelta();
	}
	const CLogicInt i2 = it.getIndex();
	if (i2 >= pcLayout->GetLengthWithEOL()) {
		*pnLineAllColLen = it.getColumn();
	}
	return i2;
}

//! CViewCalc::LineIndexToColumn：排版行里字符下标 nIndex 的横向位置
CLayoutInt LineIndexToColumn(const CLayoutMgr& mgr, const CLayout* pcLayout, CLogicInt nIndex)
{
	CMemoryIterator it = mgr.CreateCMemoryIterator(pcLayout);
	while (!it.end()) {
		it.scanNext();
		if (it.getIndex() + it.getIndexDelta() > nIndex) {
			break;
		}
		it.addDelta();
	}
	return it.getColumn();
}

//! 排版行里的下标 → 逻辑位置
CLogicPoint LayoutIndexToLogic(const CLayout* pcLayout, CLogicInt nIndex)
{
	return CLogicPoint(pcLayout->GetLogicOffset() + nIndex, pcLayout->GetLogicLineNo());
}

//! 排版位置 → 逻辑位置。行末之后的位置（原版的フリーカーソル）改成行末：界面层的光标不放在行末之后
Position LayoutToLogicInLine(const Document& doc, const LayoutPosition& position)
{
	Position p = doc.LayoutToLogic(position);
	const std::int32_t nLines = doc.LineCount();
	if (p.line >= nLines) return doc.EndPosition();
	p.column = std::min<std::int32_t>(p.column, static_cast<std::int32_t>(doc.GetLine(p.line).size()));
	return p;
}

//! Command_INDENT 里的 IsIndentCharSpaceTab
bool IsSpaceOrTab(WCHAR ch)
{
	return ch == WCODE::SPACE || ch == WCODE::TAB;
}

} // namespace

EditSettings Document::GetEditSettings() const
{
	const auto& sEdit = GetDllShareData().m_Common.m_sEdit;
	const STypeConfig& t = m_impl->typeConfig;
	EditSettings e;
	e.copyWithoutSelection = sEdit.m_bEnableNoSelectCopy;
	e.lineModePaste = sEdit.m_bEnableLineModePaste;
	e.clearSelectionAfterCopy = sEdit.m_bCopyAndDisablSelection;
	e.autoColumnPaste = sEdit.m_bAutoColumnPaste;
	e.convertEolOnPaste = sEdit.m_bConvertEOLPaste;
	e.addEolAtWrapOnCopy = sEdit.m_bAddCRLFWhenCopy;
	e.insertSpacesForTab = t.m_bInsSpace;
	e.autoIndent = t.m_bAutoIndent;
	return e;
}

Text Document::GetCopyText(const Range& range) const
{
	// CEditView::GetSelectedData の通常選択（引用符、行番号なし、改行コードはそのまま）
	const auto& d = *m_impl;
	if (!d.IsValidPosition(range.from) || !d.IsValidPosition(range.to) || !(range.from < range.to)) return {};
	const LayoutPosition from = LogicToLayout(range.from);
	const LayoutPosition to = LogicToLayout(range.to);
	const bool bAddCRLFWhenCopy = GetDllShareData().m_Common.m_sEdit.m_bAddCRLFWhenCopy;
	Text buffer;
	for (std::int32_t nLineNum = from.line; nLineNum <= to.line; ++nLineNum) {
		CLogicInt nLineLen;
		const CLayout* pcLayout = nullptr;
		const WCHAR* pLine = d.layout.GetLineStr(CLayoutInt(nLineNum), &nLineLen, &pcLayout);
		if (!pLine) break;
		const CLogicInt nIdxFrom = (nLineNum == from.line) ? LineColumnToIndex(d.layout, pcLayout, CLayoutInt(from.x)) : CLogicInt(0);
		const CLogicInt nIdxTo = (nLineNum == to.line) ? LineColumnToIndex(d.layout, pcLayout, CLayoutInt(to.x)) : nLineLen;
		if (nIdxTo - nIdxFrom == 0) continue;
		if (pcLayout->GetLayoutEol().IsValid()) {
			if (nIdxTo >= nLineLen) {
				buffer.append(&pLine[nIdxFrom], nLineLen - 1 - nIdxFrom);
				const CEol& eol = pcLayout->GetLayoutEol();
				buffer.append(eol.GetValue2(), eol.GetLen());
			} else {
				buffer.append(&pLine[nIdxFrom], nIdxTo - nIdxFrom);
			}
		} else {
			buffer.append(&pLine[nIdxFrom], nIdxTo - nIdxFrom);
			if (nIdxTo >= nLineLen && bAddCRLFWhenCopy) {	// 折り返し行に改行を付けてコピー
				buffer.append(d.newLineEol.GetValue2(), d.newLineEol.GetLen());
			}
		}
	}
	return buffer;
}

Text Document::GetBoxText(const BoxRange& box) const
{
	// CEditView::GetSelectedData の矩形選択：各行の末尾に CRLF
	const auto& d = *m_impl;
	const bool bExtEol = ExtEolEnabled();
	Text buffer;
	for (std::int32_t nLineNum = box.top; nLineNum <= box.bottom; ++nLineNum) {
		CLogicInt nLineLen;
		const CLayout* pcLayout = nullptr;
		const WCHAR* pLine = d.layout.GetLineStr(CLayoutInt(nLineNum), &nLineLen, &pcLayout);
		if (pLine) {
			const CLogicInt nIdxFrom = LineColumnToIndex(d.layout, pcLayout, CLayoutInt(box.left));
			const CLogicInt nIdxTo = LineColumnToIndex(d.layout, pcLayout, CLayoutInt(box.right));
			if (nIdxTo - nIdxFrom > 0) {
				if (WCODE::IsLineDelimiter(pLine[nIdxTo - 1], bExtEol)) {
					buffer.append(&pLine[nIdxFrom], nIdxTo - nIdxFrom - 1);
				} else {
					buffer.append(&pLine[nIdxFrom], nIdxTo - nIdxFrom);
				}
			}
		}
		buffer.append(WCODE::CRLF, 2);
	}
	return buffer;
}

Text Document::GetLayoutLineCopyText(std::int32_t layoutLine) const
{
	// CEditView::CopyCurLine（改行コードはそのまま）
	const auto& d = *m_impl;
	const CLayout* pcLayout = d.layout.SearchLineByLayoutY(CLayoutInt(layoutLine));
	if (layoutLine < 0 || !pcLayout) return {};
	Text buffer(pcLayout->GetPtr(), pcLayout->GetLengthWithoutEOL());
	if (pcLayout->GetLayoutEol().GetLen() != 0) {
		buffer.append(pcLayout->GetLayoutEol().GetValue2(), pcLayout->GetLayoutEol().GetLen());
	} else if (GetDllShareData().m_Common.m_sEdit.m_bAddCRLFWhenCopy) {
		buffer.append(WCODE::CRLF, 2);
	}
	return buffer;
}

LayoutPosition Document::InsertAtLayout(const LayoutPosition& at, const Text& text)
{
	// CEditView::InsertData_CEditView：行末より右に挿入するときは空白を埋める
	auto& d = *m_impl;
	CLogicInt nLineLen;
	const CLayout* pcLayout = nullptr;
	const WCHAR* pLine = d.layout.GetLineStr(CLayoutInt(at.line), &nLineLen, &pcLayout);
	const int nSpWidth = std::max<int>(1, CharWidth());	// 原版 CalcTextWidth3(L" ", 1)
	Text data;
	CLogicPoint ptInsert;
	if (pLine) {
		CLayoutInt nLineAllColLen;
		LineColumnToIndex2(d.layout, pcLayout, CLayoutInt(at.x), &nLineAllColLen);
		if (nLineAllColLen > 0) {
			// 行終端より右に挿入しようとした：終端直前から挿入位置まで空白を埋める
			const int nGap = pcLayout->GetLayoutEol().IsValid() ? at.x - static_cast<int>(nLineAllColLen) + 1
															   : at.x - static_cast<int>(nLineAllColLen);
			for (int i = 0; i < nGap; i += nSpWidth) {
				data += u' ';
			}
			ptInsert = LayoutIndexToLogic(pcLayout, pcLayout->GetLengthWithoutEOL());
		} else {
			d.layout.LayoutToLogic(CLayoutPoint(CLayoutInt(at.x), CLayoutInt(at.line)), &ptInsert);
		}
	} else {
		// EOF より下：行頭から空白を埋める
		for (int i = 0; i < at.x; i += nSpWidth) {
			data += u' ';
		}
		const Position end = EndPosition();
		ptInsert = ToLogic(end);
	}
	data += text;
	if (data.empty()) {
		return LogicToLayout(FromLogic(ptInsert));
	}
	const CLogicPoint ptNew = d.ReplaceWithUndo(CLogicRange(ptInsert, ptInsert), data.data(), static_cast<int>(data.size()));
	return LogicToLayout(FromLogic(ptNew));
}

Position Document::DeleteBox(const BoxRange& box)
{
	// CEditView::DeleteData の矩形選択：下の行から削除する
	auto& d = *m_impl;
	const bool bExtEol = ExtEolEnabled();
	BeginEdit();
	for (std::int32_t nLineNum = box.bottom; nLineNum >= box.top; nLineNum--) {
		CLogicInt nLineLen;
		const CLayout* pcLayout = nullptr;
		const WCHAR* pLine = d.layout.GetLineStr(CLayoutInt(nLineNum), &nLineLen, &pcLayout);
		if (!pLine) continue;
		const CLogicInt nIdxFrom = LineColumnToIndex(d.layout, pcLayout, CLayoutInt(box.left));
		CLogicInt nIdxTo = LineColumnToIndex(d.layout, pcLayout, CLayoutInt(box.right));
		for (CLogicInt i = nIdxFrom; i <= nIdxTo && i < nLineLen; ++i) {
			if (WCODE::IsLineDelimiter(pLine[i], bExtEol)) {
				nIdxTo = i;
				break;
			}
		}
		if (0 < nIdxTo - nIdxFrom) {
			d.ReplaceWithUndo(CLogicRange(LayoutIndexToLogic(pcLayout, nIdxFrom), LayoutIndexToLogic(pcLayout, nIdxTo)), nullptr, 0);
		}
	}
	EndEdit();
	// 選択エリアの先頭へカーソルを移動。EOL より左なら文字の単位にそろえる
	CLayoutPoint caretOld(CLayoutInt(box.left), CLayoutInt(box.top));
	if (const CLayout* pcLayout = d.layout.SearchLineByLayoutY(CLayoutInt(box.top));
		pcLayout && CLayoutInt(box.left) <= pcLayout->CalcLayoutWidth(d.layout)) {
		const CLogicInt nIdxCaret = LineColumnToIndex(d.layout, pcLayout, CLayoutInt(box.left));
		caretOld.SetX(LineIndexToColumn(d.layout, pcLayout, nIdxCaret));
	}
	return LayoutToLogicInLine(*this, LayoutPosition{ static_cast<std::int32_t>(caretOld.GetY2()), static_cast<std::int32_t>(caretOld.GetX2()) });
}

void Document::PasteBox(const LayoutPosition& at, const Text& text)
{
	// Command_PASTEBOX：各行を同じ桁に挿入する
	auto& d = *m_impl;
	const bool bExtEol = ExtEolEnabled();
	const int nPasteSize = static_cast<int>(text.size());
	const WCHAR* szPaste = text.data();
	BeginEdit();
	std::int32_t nCount = 0;	// カーソル位置からのオフセット行数
	for (int nBgn = 0, nPos = 0; nBgn < nPasteSize;) {
		if (nPos == nPasteSize || WCODE::IsLineDelimiter(szPaste[nPos], bExtEol)) {
			const std::int32_t row = at.line + nCount;
			// 現在位置にデータを挿入
			if (nPos - nBgn > 0) {
				InsertAtLayout(LayoutPosition{ row, at.x }, Text(&szPaste[nBgn], nPos - nBgn));
			}
			// 行末に改行が無い場合（最後の行、折り返し行）は改行を挿入する
			bool bAddLastCR = false;
			CLogicInt nLineLen;
			const CLayout* pcLayout = nullptr;
			const WCHAR* pLine = d.layout.GetLineStr(CLayoutInt(row), &nLineLen, &pcLayout);
			if (pLine && 1 <= nLineLen) {
				if (!WCODE::IsLineDelimiter(pLine[nLineLen - 1], bExtEol)) {
					bAddLastCR = true;
				}
			} else {
				bAddLastCR = true;
			}
			if (bAddLastCR) {
				const CLogicPoint ptEnd = pcLayout ? LayoutIndexToLogic(pcLayout, nLineLen) : ToLogic(EndPosition());
				d.ReplaceWithUndo(CLogicRange(ptEnd, ptEnd), d.newLineEol.GetValue2(), d.newLineEol.GetLen());
			}
			if (nPos + 1 < nPasteSize && szPaste[nPos] == WCODE::CR && szPaste[nPos + 1] == WCODE::LF) {
				nBgn = nPos + 2;
			} else {
				nBgn = nPos + 1;
			}
			nPos = nBgn;
			++nCount;
		} else {
			++nPos;
		}
	}
	EndEdit();
}

BoxRange Document::IndentBox(const BoxRange& boxIn, const Text& text, IndentKind kind, Position* pCaret)
{
	auto& d = *m_impl;
	BoxRange box = boxIn;
	const CLayoutInt nMaxLineLayout = d.layout.GetMaxLineLayout();
	// Command_INDENT ver1：SPACE か TAB のインデントで矩形選択桁がゼロの時は選択範囲を最大にする
	if (kind != IndentKind::None && box.left == box.right) {
		box.right = static_cast<std::int32_t>(nMaxLineLayout);
		return box;
	}
	if (text.empty()) return box;

	// Command_INDENT ver0 の矩形選択
	const bool bSoftTab = (kind == IndentKind::Tab && d.typeConfig.m_bInsSpace);
	const CLayoutInt nTabSpace = d.layout.GetTabSpace();
	const CLayoutInt left(box.left), right(box.right);
	CLayoutInt minOffset(-1);
	bool alignFullWidthChar = kind == IndentKind::Tab && 0 == left % nTabSpace;
	alignFullWidthChar = alignFullWidthChar || (kind == IndentKind::Space && 1 == right - left);
	BeginEdit();
	for (bool insertionWasDone = false;; alignFullWidthChar = false) {
		minOffset = CLayoutInt(-1);
		for (std::int32_t nLineNum = box.top; nLineNum <= box.bottom; ++nLineNum) {
			const CLayout* pcLayout = d.layout.SearchLineByLayoutY(CLayoutInt(nLineNum));
			CLogicInt nIdxFrom, nIdxTo;
			CLayoutInt xLayoutFrom, xLayoutTo;
			bool reachEndOfLayout = false;
			if (pcLayout) {
				// 指定された桁に対応する行のデータ内の位置を調べる
				const struct {
					CLayoutInt keta;
					CLogicInt* outLogicX;
					CLayoutInt* outLayoutX;
				} sortedKetas[] = {
					{ left, &nIdxFrom, &xLayoutFrom },
					{ right, &nIdxTo, &xLayoutTo },
					{ CLayoutInt(-1), nullptr, nullptr }
				};
				CMemoryIterator it = d.layout.CreateCMemoryIterator(pcLayout);
				for (int i = 0; 0 <= sortedKetas[i].keta; ++i) {
					for (; !it.end(); it.addDelta()) {
						if (sortedKetas[i].keta == it.getColumn()) {
							break;
						}
						it.scanNext();
						if (sortedKetas[i].keta < it.getColumn() + it.getColumnDelta()) {
							break;
						}
					}
					*sortedKetas[i].outLogicX = it.getIndex();
					*sortedKetas[i].outLayoutX = it.getColumn();
				}
				reachEndOfLayout = it.end();
			} else {
				nIdxFrom = nIdxTo = CLogicInt(0);
				xLayoutFrom = xLayoutTo = CLayoutInt(0);
				reachEndOfLayout = true;
			}
			const bool emptyLine = !pcLayout || 0 == pcLayout->GetLengthWithoutEOL();
			const bool selectionIsOutOfLine = reachEndOfLayout && (
				(pcLayout && pcLayout->GetLayoutEol().IsValid()) ? xLayoutFrom == xLayoutTo : xLayoutTo < left);

			// 入力文字の挿入位置
			const CLayoutInt xInsert = selectionIsOutOfLine ? left : xLayoutFrom;

			// TABやスペースインデントの時
			if (kind != IndentKind::None) {
				if (emptyLine || selectionIsOutOfLine) {
					continue;	// インデント対象が存在しない部分（改行文字の後ろや空行）には挿入しない
				}
				// 範囲の左端にある文字がインデント文字で、右端までに末尾が含まれていないときは挿入しない
				if (nIdxFrom == nIdxTo && pcLayout && IsSpaceOrTab(pcLayout->GetPtr()[nIdxFrom]) && left < right) {
					continue;
				}
				// 全角文字の左側の桁揃え
				if (alignFullWidthChar && (xInsert == left || (pcLayout && IsSpaceOrTab(pcLayout->GetPtr()[nIdxFrom])))) {
					minOffset = CLayoutInt(0);
					continue;
				}
			}

			// 現在位置にデータを挿入
			const LayoutPosition inserted = InsertAtLayout(LayoutPosition{ nLineNum, static_cast<std::int32_t>(xInsert) },
														   bSoftTab ? TabText(static_cast<std::int32_t>(xInsert)) : text);
			insertionWasDone = true;
			const CLayoutInt xInserted(inserted.x);
			minOffset = t_min(
				0 <= minOffset ? minOffset : nMaxLineLayout,
				xInsert <= xInserted ? xInserted - xInsert : t_max(CLayoutInt(0), nMaxLineLayout - xInsert));
		}
		if (insertionWasDone || !alignFullWidthChar) {
			break;	// 文字の挿入が行われた、または挿入を控えたせいではない
		}
	}
	EndEdit();

	// 挿入された文字の分だけ選択範囲を後ろにずらす
	if (0 < minOffset) {
		box.left = static_cast<std::int32_t>(t_min(left + minOffset, nMaxLineLayout));
		box.right = static_cast<std::int32_t>(t_min(right + minOffset, nMaxLineLayout));
	}
	// カーソルを選択範囲の左上へ移動
	if (pCaret) *pCaret = LayoutToLogicInLine(*this, LayoutPosition{ box.top, box.left });
	return box;
}

std::int32_t Document::IndentLines(std::int32_t top, std::int32_t bottom, const Text& text)
{
	// Command_INDENT の通常選択(複数行)
	auto& d = *m_impl;
	if (text.empty()) return bottom;
	BeginEdit();
	for (std::int32_t i = top; i < bottom; i++) {
		const CLayoutInt nLineCountPrev = d.layout.GetLineCount();
		const CLayout* pcLayout = d.layout.SearchLineByLayoutY(CLayoutInt(i));
		if (nullptr == pcLayout ||						// テキストが無いEOLの行は無視
			pcLayout->GetLogicOffset() > 0 ||			// 折り返し行は無視
			pcLayout->GetLengthWithoutEOL() == 0) {		// 改行のみの行は無視する
			continue;
		}
		InsertAtLayout(LayoutPosition{ i, 0 }, text);
		if (nLineCountPrev != d.layout.GetLineCount()) {
			bottom += static_cast<std::int32_t>(d.layout.GetLineCount() - nLineCountPrev);	// 行数が変化した
		}
	}
	EndEdit();
	return bottom;
}

std::int32_t Document::UnindentLines(std::int32_t top, std::int32_t bottom, char16_t ch)
{
	// Command_UNINDENT の通常選択
	auto& d = *m_impl;
	const WCHAR wcChar = static_cast<WCHAR>(ch);
	BeginEdit();
	for (std::int32_t i = top; i < bottom; i++) {
		const CLayoutInt nLineCountPrev = d.layout.GetLineCount();
		CLogicInt nLineLen;
		const CLayout* pcLayout = nullptr;
		const WCHAR* pLine = d.layout.GetLineStr(CLayoutInt(i), &nLineLen, &pcLayout);
		if (nullptr == pcLayout || pcLayout->GetLogicOffset() > 0) {	// 折り返し以降の行はインデント処理を行わない
			continue;
		}
		CLogicInt nDelLen;
		if (WCODE::TAB == wcChar) {
			if (pLine[0] == wcChar) {
				nDelLen = CLogicInt(1);
			} else {
				// 削り取る半角スペース数 (1～タブ幅分)
				CLogicInt i2;
				const CLogicInt nTabSpaces = CLogicInt(static_cast<Int>(d.layout.GetTabSpaceKetas()));
				for (i2 = CLogicInt(0); i2 < nLineLen; i2++) {
					if (WCODE::SPACE != pLine[i2]) break;
					if (i2 >= nTabSpaces) break;
				}
				if (0 == i2) continue;
				nDelLen = i2;
			}
		} else {
			if (pLine[0] != wcChar) continue;
			nDelLen = CLogicInt(1);
		}
		d.ReplaceWithUndo(CLogicRange(LayoutIndexToLogic(pcLayout, CLogicInt(0)), LayoutIndexToLogic(pcLayout, nDelLen)), nullptr, 0);
		if (nLineCountPrev != d.layout.GetLineCount()) {
			bottom += static_cast<std::int32_t>(d.layout.GetLineCount() - nLineCountPrev);
		}
	}
	EndEdit();
	return bottom;
}

Text Document::TabText(std::int32_t x) const
{
	// Command_INDENT の SSoftTabData：[SPACEの挿入] のときは次の TAB 位置までの空白
	const auto& d = *m_impl;
	if (!d.typeConfig.m_bInsSpace) return Text(1, u'\t');
	const int nTab = std::max<int>(1, static_cast<int>(d.layout.GetTabSpace()));
	const int nSpWidth = std::max<int>(1, static_cast<int>(d.layout.GetWidthPerKeta()));
	const int nXWidth = nSpWidth - 1;
	const int nLen = (nTab + nXWidth - (x + nXWidth) % nTab) / nSpWidth;
	return Text(std::max(1, nLen), u' ');
}

Text Document::AutoIndentText(const Position& caret) const
{
	// Command_WCHAR のオートインデント
	const auto& d = *m_impl;
	const STypeConfig& t = d.typeConfig;
	if (!t.m_bAutoIndent) return {};
	const CDocLine* pcDocLine = d.lines.GetLine(CLogicInt(caret.line));
	if (!pcDocLine) return {};
	CLogicInt nLineLen;
	const WCHAR* pLine = pcDocLine->GetDocLineStrWithEOL(&nLineLen);
	if (!pLine) return {};
	CLogicInt nPos(0);
	for (; nPos < nLineLen && nPos < caret.column;) {
		const CLogicInt nCharChars = CNativeW::GetSizeOfChar(pLine, nLineLen, nPos);
		bool bIndentChar = false;
		// その他のインデント文字
		if (0 < nCharChars && pLine[nPos] != L'\0' && t.m_szIndentChars[0] != L'\0') {
			WCHAR szCurrent[10];
			wmemcpy(szCurrent, &pLine[nPos], nCharChars);
			szCurrent[nCharChars] = L'\0';
			bIndentChar = nullptr != wcsstr(t.m_szIndentChars, szCurrent);
		}
		if (!bIndentChar && !(nCharChars == 1 && WCODE::IsIndentChar(pLine[nPos], t.m_bAutoIndent_ZENSPACE))) {
			break;
		}
		nPos += nCharChars;
	}
	return Text(pLine, nPos);
}

Text Document::ConvertEolToNewLine(const Text& text) const
{
	// CViewCommander::ConvertEol
	const CEol& eol = m_impl->newLineEol;
	const bool bExtEol = ExtEolEnabled();
	Text converted;
	converted.reserve(text.size());
	for (size_t i = 0; i < text.size(); i++) {
		if (WCODE::IsLineDelimiter(text[i], bExtEol)) {
			if (text[i] == WCODE::CR && i + 1 < text.size() && text[i + 1] == WCODE::LF) {
				i++;
			}
			converted.append(eol.GetValue2(), eol.GetLen());
		} else {
			converted += text[i];
		}
	}
	return converted;
}

Position Document::DeleteLayoutLine(std::int32_t layoutLine, std::int32_t x)
{
	// Command_DELETE_LINE：レイアウト行を改行まで削除して、カーソルは元の桁へ
	auto& d = *m_impl;
	const CLayout* pcLayout = d.layout.SearchLineByLayoutY(CLayoutInt(layoutLine));
	if (layoutLine < 0 || !pcLayout) return EndPosition();
	const CLogicPoint ptFrom = LayoutIndexToLogic(pcLayout, CLogicInt(0));
	CLogicPoint ptTo;
	if (const CLayout* pNext = pcLayout->GetNextLayout()) {
		ptTo = LayoutIndexToLogic(pNext, CLogicInt(0));
	} else if (pcLayout->GetLayoutEol().IsValid()) {
		ptTo = CLogicPoint(CLogicInt(0), pcLayout->GetLogicLineNo() + 1);
	} else {
		ptTo = LayoutIndexToLogic(pcLayout, pcLayout->GetLengthWithoutEOL());
	}
	d.ReplaceWithUndo(CLogicRange(ptFrom, ptTo), nullptr, 0);

	// 行削除した後、カーソル位置が行端より右にならないように調整する（フリーカーソルでないとき）
	const CLayout* pcNew = d.layout.SearchLineByLayoutY(CLayoutInt(layoutLine));
	if (!pcNew) return EndPosition();
	CLayoutInt nAllColLen;
	const CLogicInt nIndex = LineColumnToIndex2(d.layout, pcNew, CLayoutInt(x), &nAllColLen);
	CLayoutInt xNew = nAllColLen;
	if (0 < xNew) {
		xNew--;
	} else {
		xNew = LineIndexToColumn(d.layout, pcNew, nIndex);
	}
	return LayoutToLogicInLine(*this, LayoutPosition{ layoutLine, static_cast<std::int32_t>(xNew) });
}

} // namespace sakura::core
