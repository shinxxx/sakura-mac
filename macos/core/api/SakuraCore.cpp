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
#include "env/CDocTypeManager.h"
#include "CSelectLang.h"
#include "env/CShareData.h"
#include "env/CShareData_IO.h"
#include "env/DLLSHAREDATA.h"
#include "extmodule/CBregexp.h"
#include "io/CBinaryStream.h"
#include "io/CFileLoad.h"
#include "util/file.h"

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

namespace {

std::unique_ptr<CShareData> g_shareData;

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
	return true;
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
		DocLineReplaceArg arg;
		arg.sDelRange = range;
		arg.pcmemDeleted = pDeleted;
		arg.pInsData = pInsData;
		arg.nDelSeq = nDelSeq;
		CSearchAgent(&lines).ReplaceData(&arg, ExtEolEnabled());
		if (pnInsSeq) *pnInsSeq = arg.nInsSeq;
		return arg.ptNewPos;
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
		lines.DeleteAllLine();
		modified = false;
	}
};

Document::Document() : m_impl(std::make_unique<Impl>()) {}

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
		return Result::Failed;
	}
	catch (const CError_FileRead&) {
		d.lines.DeleteAllLine();
		return Result::Failed;
	}

	d.info.path = path;
	d.info.encoding = eCharCode;
	d.info.bom = bBom;
	d.ResetNewLineEol();
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
	if (bTypeChanged) d.ResetForType(path);	// 另存为：扩展名变了，类型别设置也跟着变
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

} // namespace sakura::core
