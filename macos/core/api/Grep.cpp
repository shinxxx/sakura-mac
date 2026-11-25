/*! @file
	@brief Grep・Grep置換（计划第 43 步）

	检索本身是原版的 CGrepAgent::DoGrep（agent/CGrepAgent.cpp，文件的枚举是 grep/CGrepEnum*.h），不改。
	原版的 DoGrep 在编辑窗口的线程里运行，一边处理窗口消息一边把结果加到 Grep 窗口（Command_ADDTAIL）。
	Mac 版在别的线程运行 DoGrep，下面的几个类代替原版的窗口部分：
	- 「Grep実行中」对话框（原版 CDlgGrepRunning）→ ProgressAdapter：检查中断、记下进度（间隔与原版相同）
	- 结果的文档（原版 CGrepOutputToView）→ OutputAdapter：结果的文字先存起来，界面层用 TakeOutput 取出
	- 结果的文档的设置、消息框、剪贴板（原版 CEditView）→ ResultView
	- 「編集中のテキストから検索」的窗口（原版 :HWND: 的窗口和 MYWM_GETLINEDATA）→ SourceDoc
*/
/*
	Copyright (C) 2026, Sakura Editor Organization

	SPDX-License-Identifier: Zlib
*/
#include "StdAfx.h"
#include "sakura_core/SakuraCore.h"

#include "agent/CGrepAgent.h"
#include "basis/GrepInfo.h"
#include "env/CDocTypeManager.h"
#include "env/DLLSHAREDATA.h"
#include "mem/CNativeW.h"
#include "types/CType.h"

#include <atomic>
#include <mutex>

namespace sakura::core {

namespace {

//! 前回から nInterval ミリ秒を過ぎたか（原版 CDlgGrepRunning::IsIntervalPassed）
bool IsIntervalPassed(ULONGLONG& nNextTime, ULONGLONG nInterval)
{
	const ULONGLONG nNow = ::GetTickCount64();
	if (nNow <= nNextTime) {
		return false;
	}
	nNextTime = nNow + nInterval;
	return true;
}

//! 原版 CGrepAgent.cpp 的 UICHECK_INTERVAL_MILLISEC、UIFILENAME_INTERVAL_MILLISEC
constexpr ULONGLONG kCheckInterval = 100;
constexpr ULONGLONG kFileNameInterval = 15;

//! 「編集中のテキストから検索」的文档（原版：别的窗口）
class SourceDoc final : public IGrepSourceDoc {
public:
	explicit SourceDoc(const GrepSourceText& source) : m_source(source) {}
	sakura::wstring GetFilePath() const override { return m_source.filePath; }
	sakura::wstring GetWindowLabel() const override { return m_source.windowLabel; }
	bool IsGrep() const override { return m_source.isGrep; }
	ECodeType GetCharCode() const override { return static_cast<ECodeType>(m_source.encoding); }
	int GetLineCount() const override { return static_cast<int>(m_source.lines.size()); }
	sakura::wstring GetLine(int nLine) const override
	{
		return (0 <= nLine && nLine < GetLineCount()) ? m_source.lines[static_cast<size_t>(nLine)] : sakura::wstring();
	}

private:
	const GrepSourceText& m_source;
};

} // namespace

struct GrepSession::Impl final : public IGrepProgress, public IGrepOutputTarget, public IGrepResultView {
	GrepOptions options;
	std::vector<GrepSourceText> sources;
	std::vector<std::unique_ptr<SourceDoc>> sourceDocs;
	STypeConfig resultType;					//!< 结果的文档的タイプ別設定（grepout）

	mutable std::mutex mutex;
	Text output;							//!< 还没取出的结果
	GrepProgress progress;
	std::atomic<bool> cancelRequested{ false };
	std::atomic<bool> cancelled{ false };
	std::atomic<bool> realTimeView{ false };
	std::atomic<bool> running{ false };
	bool ran = false;
	Text errorMessage;

	ULONGLONG nextCheckTime = 0;
	ULONGLONG nextFileNameTime = 0;

	// ----- IGrepProgress（原版 CDlgGrepRunning）-----
	bool IsCheckTime() override { return IsIntervalPassed(nextCheckTime, kCheckInterval); }
	bool IsFileNameTime() override { return IsIntervalPassed(nextFileNameTime, kFileNameInterval); }
	bool IsCancelRequested() override
	{
		if (cancelRequested.load()) {
			cancelled = true;
			return true;
		}
		return false;
	}
	void ApplyRealTimeView() override {}	// IsDrawing 每次读复选框的状态
	void SetHitCount(int nHitCount) override
	{
		std::lock_guard lock(mutex);
		progress.hitCount = nHitCount;
	}
	void SetFileName(sakura::wstring_view fileName) override
	{
		std::lock_guard lock(mutex);
		progress.file.assign(fileName);
	}
	void SetFolder(sakura::wstring_view folder) override
	{
		std::lock_guard lock(mutex);
		progress.folder.assign(folder);
	}

	// ----- IGrepOutputTarget（原版 CGrepOutputToView）-----
	void Append(const CNativeW& cmem) override
	{
		std::lock_guard lock(mutex);
		output.append(cmem.GetStringPtr(), static_cast<size_t>(cmem.GetStringLength()));
	}
	bool IsDrawing() const override { return realTimeView.load(); }

	// ----- IGrepResultView（原版 CEditView）-----
	const STypeConfig& GetDocumentAttribute() const override { return resultType; }
	bool GetPasteText(CNativeW& cmemText) override
	{
		if (!options.pasteText) return false;
		cmemText.SetString(options.pasteText->c_str(), options.pasteText->length());
		return true;
	}
	void ErrorMessage(const WCHAR* pszMessage) override { errorMessage = pszMessage ? pszMessage : LTEXT(""); }
	IGrepSourceDoc* FindSourceDoc(const WCHAR* pszToken) override
	{
		std::uint64_t id = 0;
		for (const WCHAR* p = pszToken; *p; ++p) {
			const WCHAR c = *p;
			const int d = (u'0' <= c && c <= u'9') ? c - u'0' : (u'a' <= c && c <= u'f') ? c - u'a' + 10
				: (u'A' <= c && c <= u'F') ? c - u'A' + 10 : -1;
			if (d < 0) break;
			id = id * 16 + static_cast<std::uint64_t>(d);
		}
		for (size_t i = 0; i < sources.size(); ++i) {
			if (sources[i].id == id) return sourceDocs[i].get();
		}
		return nullptr;
	}
};

GrepSession::GrepSession(GrepOptions options, std::vector<GrepSourceText> sources)
	: m_impl(std::make_unique<Impl>())
{
	m_impl->options = std::move(options);
	m_impl->sources = std::move(sources);
	for (const auto& source : m_impl->sources) {
		m_impl->sourceDocs.push_back(std::make_unique<SourceDoc>(source));
	}
	if (IsStarted()) {
		m_impl->realTimeView = GetDllShareData().m_Common.m_sSearch.m_bGrepRealTimeView != FALSE;
		if (!CDocTypeManager().GetTypeConfig(CTypeConfig(GrepOutputTypeIndex()), m_impl->resultType)) {
			CDocTypeManager().GetTypeConfig(CTypeConfig(0), m_impl->resultType);
		}
	}
}

GrepSession::~GrepSession() = default;

GrepResult GrepSession::Run()
{
	GrepResult result;
	auto& impl = *m_impl;
	if (impl.ran || !IsStarted()) return result;
	impl.ran = true;
	impl.running = true;

	const GrepOptions& o = impl.options;
	GrepInfo gi;
	gi.cmGrepKey.SetString(o.key.c_str(), o.key.length());
	gi.cmGrepRep.SetString(o.replacement.c_str(), o.replacement.length());
	gi.cmGrepFile.SetString(o.files.c_str(), o.files.length());
	gi.cmGrepFolder.SetString(o.folders.c_str(), o.folders.length());
	gi.sGrepSearchOption.bRegularExp = o.search.regularExpression;
	gi.sGrepSearchOption.bLoHiCase = o.search.matchCase;
	gi.sGrepSearchOption.bWordOnly = o.search.wholeWord;
	gi.bGrepCurFolder = true;			// Mac 版不改当前文件夹
	gi.bGrepStdout = false;
	gi.bGrepHeader = o.header;
	gi.bGrepSubFolder = o.subFolder;
	gi.nGrepCharSet = static_cast<ECodeType>(o.charSet);
	gi.nGrepOutputStyle = o.outputStyle;
	gi.nGrepOutputLineType = o.outputLineType;
	gi.bGrepOutputFileOnly = o.fileOnly;
	gi.bGrepOutputBaseFolder = o.baseFolder;
	gi.bGrepSeparateFolder = o.separateFolder;
	gi.bGrepReplace = o.replace;
	gi.bGrepPaste = o.paste;
	gi.bGrepBackup = o.backup;
	gi.bGrepExceptFileRegexp = o.exceptFileRegexp;

	CGrepAgent agent;
	const DWORD hits = agent.DoGrep(&impl, gi, &impl, &impl);
	result.hitCount = static_cast<std::int32_t>(hits);
	result.cancelled = impl.cancelled.load();
	result.errorMessage = impl.errorMessage;
	impl.running = false;
	return result;
}

void GrepSession::Cancel() { m_impl->cancelRequested = true; }
void GrepSession::SetRealTimeView(bool on) { m_impl->realTimeView = on; }
bool GrepSession::IsRealTimeView() const { return m_impl->realTimeView.load(); }
bool GrepSession::IsRunning() const { return m_impl->running.load(); }

Text GrepSession::TakeOutput()
{
	std::lock_guard lock(m_impl->mutex);
	Text text;
	text.swap(m_impl->output);
	return text;
}

GrepProgress GrepSession::Progress() const
{
	std::lock_guard lock(m_impl->mutex);
	return m_impl->progress;
}

Text GrepSourceToken(std::uint64_t id)
{
	return sakura::format(LTEXT(":HWND:{:016x}"), id);
}

std::int32_t GrepOutputTypeIndex()
{
	if (!IsStarted()) return 0;
	const CTypeConfig type = CDocTypeManager().GetDocumentTypeOfExt(LTEXT("grepout"));
	return type.IsValidType() ? type.GetIndex() : 0;
}

} // namespace sakura::core
