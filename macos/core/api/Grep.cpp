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
#include "config/maxdata.h"
#include "env/CDocTypeManager.h"
#include "env/CSearchKeywordManager.h"
#include "env/DLLSHAREDATA.h"
#include "grep/CGrepEnumKeys.h"
#include "mem/CNativeW.h"
#include "recent/CRecentExcludeFile.h"
#include "recent/CRecentExcludeFolder.h"
#include "recent/CRecentGrepFile.h"
#include "recent/CRecentGrepFolder.h"
#include "types/CType.h"
#include "util/file.h"
#include "util/string_ex2.h"
#include "CSelectLang.h"
#include "sakura_rc.h"

#include <atomic>
#include <filesystem>
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

// ---------------------------------------------------------------------------
// Grep 对话框（原版 CDlgGrep 的数据部分）
// ---------------------------------------------------------------------------

namespace {

template <class TRecent>
std::vector<Text> RecentItems()
{
	TRecent recent;
	std::vector<Text> result;
	for (int i = 0; i < recent.GetItemCount(); i++) {
		if (const WCHAR* p = recent.GetItemText(i)) result.emplace_back(p);
	}
	return result;
}

//! 原版 CDlgGrep.h の DEFAULT_EXCLUDE_FILE_PATTERN・DEFAULT_EXCLUDE_FOLDER_PATTERN
constexpr const WCHAR* kDefaultExcludeFile = LTEXT("*.msi;*.exe;*.obj;*.pdb;*.ilk;*.res;*.pch;*.iobj;*.ipdb");
constexpr const WCHAR* kDefaultExcludeFolder = LTEXT(".git;.svn;.vs");

//! 相对路径从 baseFolder 开始的绝对路径（原版：当前文件夹 + GetLongFileName）。"." ".." 去掉，最后的 / 留着（CGrepAgent::ChopYen 去掉）
Text AbsoluteFolder(const Text& path, const Text& baseFolder)
{
	namespace fs = std::filesystem;
	fs::path p{ path };
	if (_IS_REL_PATH(path.c_str())) {
		p = fs::path{ baseFolder.empty() ? Text(LTEXT("/")) : baseFolder } / p;
	}
	return sakura::path_to_wstring(p.lexically_normal());
}

} // namespace

std::vector<Text> GrepHistoryItems(GrepHistory kind)
{
	if (!IsStarted()) return {};
	switch (kind) {
	case GrepHistory::File: return RecentItems<CRecentGrepFile>();
	case GrepHistory::Folder: return RecentItems<CRecentGrepFolder>();
	case GrepHistory::ExcludeFile: return RecentItems<CRecentExcludeFile>();
	case GrepHistory::ExcludeFolder: return RecentItems<CRecentExcludeFolder>();
	}
	return {};
}

void AddGrepHistory(GrepHistory kind, const Text& text)
{
	if (!IsStarted()) return;
	CSearchKeywordManager manager;
	switch (kind) {
	case GrepHistory::File: manager.AddToGrepFileArr(text.c_str()); break;
	case GrepHistory::Folder: manager.AddToGrepFolderArr(text.c_str()); break;
	case GrepHistory::ExcludeFile: manager.AddToExcludeFileArr(text.c_str()); break;
	case GrepHistory::ExcludeFolder: manager.AddToExcludeFolderArr(text.c_str()); break;
	}
}

GrepDialogDefaults GetGrepDialogDefaults()
{
	GrepDialogDefaults d;
	if (!IsStarted()) return d;
	auto& keywords = GetDllShareData().m_sSearchKeywords;
	if (keywords.m_aGrepFiles.size()) d.file = Text(keywords.m_aGrepFiles[0]);
	if (keywords.m_aGrepFolders.size()) d.folder = Text(keywords.m_aGrepFolders[0]);
	// ユーザーの利便性向上のために除外ファイル・除外フォルダーに対して初期値を設定し、履歴に残して後で選択できるようにする
	if (keywords.m_aExcludeFiles.size()) {
		d.excludeFile = Text(keywords.m_aExcludeFiles[0]);
	} else {
		d.excludeFile = kDefaultExcludeFile;
		keywords.m_aExcludeFiles.push_back(kDefaultExcludeFile);
	}
	if (keywords.m_aExcludeFolders.size()) {
		d.excludeFolder = Text(keywords.m_aExcludeFolders[0]);
	} else {
		d.excludeFolder = kDefaultExcludeFolder;
		keywords.m_aExcludeFolders.push_back(kDefaultExcludeFolder);
	}
	return d;
}

Text PackGrepFiles(const Text& file, const Text& excludeFile, const Text& excludeFolder)
{
	// 原版 CDlgGrep::GetPackedGFileString：除外フォルダー、除外ファイルの順
	Text packed = file;
	for (const auto& pattern : CGrepEnumKeys::SplitPatternKeepQuotes(excludeFolder.c_str())) {
		packed += LTEXT(";#");
		packed.append(pattern.data(), pattern.size());
	}
	for (const auto& pattern : CGrepEnumKeys::SplitPatternKeepQuotes(excludeFile.c_str())) {
		packed += LTEXT(";!");
		packed.append(pattern.data(), pattern.size());
	}
	return packed;
}

std::vector<Text> SplitGrepFolders(const Text& folders, const Text& baseFolder)
{
	// 原版 CGrepAgent::CreateFolders と同じに分け（; で区切り、" を取り除く）、相対パスは baseFolder から
	std::vector<Text> result;
	Text work = folders;
	const int nLen = static_cast<int>(work.length());
	int nPos = 0;
	while (WCHAR* token = my_strtok<WCHAR>(work.data(), nLen, &nPos, LTEXT(";"))) {
		Text item(token);
		std::erase(item, LCHAR('"'));
		result.push_back(AbsoluteFolder(item, baseFolder));
	}
	return result;
}

Text JoinGrepFolders(const std::vector<Text>& folders)
{
	Text joined;
	for (size_t i = 0; i < folders.size(); ++i) {
		if (i) joined += LCHAR(';');
		// ;がフォルダー名に含まれていたら""で囲う
		if (folders[i].find(LCHAR(';')) != Text::npos) {
			joined += LCHAR('"') + folders[i] + LCHAR('"');
		} else {
			joined += folders[i];
		}
	}
	return joined;
}

std::optional<Text> GrepFoldersUp(const Text& folders, const Text& baseFolder)
{
	auto paths = SplitGrepFolders(folders, baseFolder);
	if (paths.empty()) return std::nullopt;
	// 最後のパスが操作対象（原版 CDialog::DirectoryUp：ルートより長いときだけ。Mac 版のルートは /）
	Text last = paths.back();
	while (1 < last.size() && last.back() == LCHAR('/')) last.pop_back();
	if (last.size() <= 1) return std::nullopt;
	const auto slash = last.find_last_of(LCHAR('/'));
	if (slash == Text::npos) return std::nullopt;
	last.resize(slash == 0 ? 1 : slash);
	paths.back() = last;
	return JoinGrepFolders(paths);
}

GrepDialogCheck CheckGrepDialog(const Text& file, const Text& excludeFile, const Text& excludeFolder,
								const Text& folders, const Text& baseFolder, bool fromThisText)
{
	GrepDialogCheck check;
	check.file = file;
	if (!fromThisText && file.starts_with(LTEXT(":HWND:"))) {
		check.error = LS(STR_DLGGREP_THISDOC_ERROR);
		return check;
	}
	// 引用符の閉じ忘れがあると、後ろに連結する除外パターンまで引用符の中に入ってしまう
	if (CGrepEnumKeys::HasUnclosedQuote(file.c_str()) || CGrepEnumKeys::HasUnclosedQuote(excludeFile.c_str())
		|| CGrepEnumKeys::HasUnclosedQuote(excludeFolder.c_str())) {
		check.error = LS(STR_DLGGREP_QUOTE_ERROR);
		return check;
	}
	if (!file.empty()) {
		CGrepEnumKeys enumKeys;
		const int nErrorNo = enumKeys.SetFileKeys(file.c_str());
		if (nErrorNo == 1) {
			check.error = LS(STR_DLGGREP2);
			return check;
		} else if (nErrorNo == 2) {
			check.error = LS(STR_DLGGREP3);
			return check;
		}
	}
	if (check.file.empty()) {
		check.file = LTEXT("*.*");	// 検索パターンが指定されていない場合は「*.*」が指定されたものと見なす
	}
	if (folders.empty()) {
		check.error = LS(STR_DLGGREP4);
		return check;
	}
	if (fromThisText) {
		check.folders.clear();
		return check;
	}
	const auto paths = SplitGrepFolders(folders, baseFolder);
	for (const auto& path : paths) {
		std::error_code ec;
		if (!std::filesystem::is_directory(std::filesystem::path{ path }, ec)) {
			check.error = LS(STR_DLGGREP5);
			return check;
		}
	}
	std::vector<Text> normalized;
	for (auto path : paths) {
		while (1 < path.size() && path.back() == LCHAR('/')) path.pop_back();
		normalized.push_back(path);
	}
	check.folders = JoinGrepFolders(normalized);
	if (MAX_GREP_PATH < static_cast<int>(check.folders.size()) + 1) {
		check.error = LS(STR_DLGGREP6);
		check.folders.clear();
	}
	return check;
}

// ---------------------------------------------------------------------------
// タグジャンプ（原版 cmd/CViewCommander_TagJump.cpp の Command_TagJumpNoMessage。tags ファイルの部分は第 44 步）
// ---------------------------------------------------------------------------

namespace {

//! "までを切り取る（原版 GetQuoteFilePath）
bool GetQuoteFilePath(const WCHAR* pLine, sakura::wstring& str, size_t size)
{
	const WCHAR* pFileEnd = wcschr(pLine, LCHAR('\"'));
	str.clear();
	if (pFileEnd == nullptr) {
		return false;
	}
	size_t nFileLen = pFileEnd - pLine;
	if (0 == nFileLen || size <= nFileLen) {
		return false;
	}
	str.assign(pLine, nFileLen);
	return !str.empty();
}

bool IsFileExists2(const WCHAR* pszFile)
{
	for (int i = 0; pszFile[i]; i++) {
		if (!WCODE::IsValidFilenameChar(pszFile[i])) {
			return false;
		}
	}
	if (_IS_REL_PATH(pszFile)) {
		return false;
	}
	return IsFileExists(pszFile, true);
}

bool IsHWNDTag(const WCHAR* pLine, sakura::wstring& str, int* pnLen = nullptr)
{
	if (0 == wcsncmp(pLine, LTEXT(":HWND:["), 7)) {
		const WCHAR* pFileEnd = wcschr(pLine, LCHAR(']'));
		if (pFileEnd) {
			const int nLen = int(pFileEnd - pLine + 1);
			int i = 7;
			for (; i < nLen; i++) {
				if (!(WCODE::Is09(pLine[i]) || (LCHAR('a') <= pLine[i] && LCHAR('f') <= pLine[i]))) {
					break;
				}
			}
			if (i != nLen && nLen <= 16 + 8) {
				if (pnLen) {
					*pnLen = nLen;
					return true;
				}
				str.assign(pLine, nLen);
				return true;
			}
		}
	}
	return false;
}

int GetLineColumnPos(const WCHAR* pLine)
{
	// filename(1234,56): str
	const WCHAR* pTagEnd = wcsstr(pLine, LTEXT("): "));
	if (!pTagEnd) {
		// filename(1234,56)  [SJIS]: str
		pTagEnd = wcsstr(pLine, LTEXT("]: "));
		if (pTagEnd) {
			int fileEnd = int(pTagEnd - pLine - 1);
			for (; 1 < fileEnd; fileEnd--) {
				if (LCHAR('[') == pLine[fileEnd]) {
					fileEnd--;
					break;
				}
			}
			for (; 1 < fileEnd && LCHAR(' ') == pLine[fileEnd]; fileEnd--) {}
			if (')' == pLine[fileEnd]) {
				pTagEnd = &pLine[fileEnd];
			} else {
				pTagEnd = nullptr;
			}
		}
	}
	if (pTagEnd) {
		int fileEnd = int(pTagEnd - pLine - 1);
		for (; 1 < fileEnd && (LCHAR('0') <= pLine[fileEnd] && pLine[fileEnd] <= LCHAR('9')); fileEnd--) {}
		if (1 < fileEnd && (LCHAR(',') == pLine[fileEnd])) { fileEnd--; }
		for (; 1 < fileEnd && (LCHAR('0') <= pLine[fileEnd] && pLine[fileEnd] <= LCHAR('9')); fileEnd--) {}
		if (1 < fileEnd && LCHAR('(') == pLine[fileEnd]) {
			return fileEnd;
		}
	}
	return 0;
}

} // namespace

std::optional<TagJumpTarget> FindTagJump(const Document& document, std::int32_t line)
{
	int nJumpToLine = 0;
	int nJumpToColumn = 0;
	size_t nBgn;
	size_t nPathLen;
	if (line < 0 || document.LineCount() <= line) return std::nullopt;
	Text lineText = document.GetLine(line, true);
	const WCHAR* pLine = lineText.c_str();
	int nLineLen = static_cast<int>(lineText.size());
	int y = line;

	sakura::wstring strJumpToFile;
	sakura::wstring strFile;
	constexpr int MAX_TAG_PATH = MAX_PATH;

	do {
		enum TagListSeachMode {
			TAGLIST_FILEPATH,
			TAGLIST_SUBPATH,
			TAGLIST_ROOT,
		} searchMode = TAGLIST_FILEPATH;
		if (2 <= nLineLen && 0 == wmemcmp(pLine, LTEXT("■\""), 2)) {
			/* WZ風のタグリストか */
			if (IsFilePath(&pLine[2], &nBgn, &nPathLen) && !_IS_REL_PATH(&pLine[2])) {
				strJumpToFile.assign(&pLine[2 + nBgn], nPathLen);
				GetLineColumn(&pLine[2 + nPathLen], &nJumpToLine, &nJumpToColumn);
				break;
			} else if (!GetQuoteFilePath(&pLine[2], strFile, MAX_TAG_PATH)) {
				break;
			}
			searchMode = TAGLIST_ROOT;
		} else if (2 <= nLineLen && 0 == wmemcmp(pLine, LTEXT("◆\""), 2)) {
			if (!GetQuoteFilePath(&pLine[2], strFile, MAX_TAG_PATH)) {
				break;
			} else if (IsHWNDTag(&pLine[2], strJumpToFile)) {
				break;
			}
			searchMode = TAGLIST_SUBPATH;
		} else if (1 <= nLineLen && 0 == wmemcmp(pLine, LTEXT("・"), 1)) {
			if (pLine[1] == LCHAR('"')) {
				// ・"FileName.ext"
				if (!GetQuoteFilePath(&pLine[2], strFile, MAX_TAG_PATH)) {
					break;
				}
				if (IsHWNDTag(&pLine[2], strJumpToFile)) {
					break;
				}
				searchMode = TAGLIST_SUBPATH;
			} else if (pLine[1] == LCHAR('(')) {
				// ファイル毎(WZ風)
				GetLineColumn(&pLine[1], &nJumpToLine, &nJumpToColumn);
				searchMode = TAGLIST_FILEPATH;
			} else {
				// ノーマル/ファイル相対パス
				int fileEnd = GetLineColumnPos(pLine);
				if (1 < fileEnd && LCHAR('(') == pLine[fileEnd] && fileEnd - 1 < MAX_TAG_PATH) {
					strFile.assign(pLine + 1, fileEnd - 1);
					GetLineColumn(&pLine[fileEnd + 1], &nJumpToLine, &nJumpToColumn);
					if (IsHWNDTag(pLine + 1, strJumpToFile)) {
						break;
					}
					searchMode = TAGLIST_SUBPATH;
				} else {
					break;
				}
			}
		} else {
			break;
		}
		y--;

		for (; 0 <= y; y--) {
			lineText = document.GetLine(y, true);
			pLine = lineText.c_str();
			nLineLen = static_cast<int>(lineText.size());
			if (1 <= nLineLen && 0 == wmemcmp(pLine, LTEXT("・"), 1)) {
				continue;
			} else if (3 <= nLineLen && 0 == wmemcmp(pLine, LTEXT("◆\""), 2)) {
				if (searchMode == TAGLIST_SUBPATH || searchMode == TAGLIST_ROOT) {
					continue;
				}
				if (IsHWNDTag(&pLine[2], strJumpToFile)) {
					break;
				}
				// フォルダー毎：ファイル名
				if (GetQuoteFilePath(&pLine[2], strFile, MAX_TAG_PATH)) {
					searchMode = TAGLIST_SUBPATH;
					continue;
				}
				break;
			} else if (2 <= nLineLen && pLine[0] == LCHAR('■') && (pLine[1] == LCHAR('\r') || pLine[1] == LCHAR('\n'))) {
				// ルートフォルダー
				if (searchMode == TAGLIST_ROOT) {
					continue;
				}
				searchMode = TAGLIST_ROOT;
			} else if (3 <= nLineLen && 0 == wmemcmp(pLine, LTEXT("■\""), 2)) {
				if (searchMode == TAGLIST_ROOT) {
					continue;
				}
				if (IsHWNDTag(&pLine[2], strJumpToFile)) {
					break;
				}
				// ファイル毎(WZ風)：フルパス
				if (IsFilePath(&pLine[2], &nBgn, &nPathLen) && !_IS_REL_PATH(&pLine[2])) {
					strJumpToFile.assign(&pLine[2 + nBgn], nPathLen);
					break;
				}
				// 相対フォルダーorファイル名
				sakura::wstring strPath;
				if (GetQuoteFilePath(&pLine[2], strPath, MAX_TAG_PATH)) {
					if (strFile.empty() == false) {
						strPath = AddLastYenPath(strPath);
					}
					strPath.append(strFile);
					if (MAX_TAG_PATH <= strPath.size()) {
						break;
					}
					if (IsFileExists2(strPath.c_str())) {
						strJumpToFile = strPath;
						break;
					}
					// 相対パスだった→◎”を探す
					strFile = std::move(strPath);
					searchMode = TAGLIST_ROOT;
					continue;
				}
				break;
			} else if (3 <= nLineLen && 0 == wmemcmp(pLine, LTEXT("◎\""), 2)) {
				sakura::wstring strPath;
				if (GetQuoteFilePath(&pLine[2], strPath, MAX_TAG_PATH)) {
					strPath = AddLastYenPath(strPath);
					strPath.append(strFile);
					if (MAX_TAG_PATH <= strPath.size()) {
						break;
					}
					if (IsFileExists2(strPath.c_str())) {
						strJumpToFile = std::move(strPath);
						break;
					}
				}
				break;
			} else {
				break;
			}
		}
	} while (0);

	if (strJumpToFile.empty()) {
		lineText = document.GetLine(line, true);
		pLine = lineText.c_str();
		nLineLen = static_cast<int>(lineText.size());
		int nLen = 0;
		sakura::wstring test;
		if (IsHWNDTag(pLine, test, &nLen)) {
			int nFileEnd = GetLineColumnPos(pLine);
			if (nFileEnd) {
				strJumpToFile.assign(pLine, nLen);
				GetLineColumn(&pLine[nFileEnd + 1], &nJumpToLine, &nJumpToColumn);
			}
		}
	}
	if (strJumpToFile.empty()) {
		//	Borland 形式のメッセージからのTAG JUMP
		const WCHAR* p = pLine;
		const WCHAR* p_end = p + nLineLen;
		while (p < p_end) {
			//	skip space
			for (; p < p_end && (*p == LCHAR(' ') || *p == LCHAR('\t') || WCODE::IsLineDelimiter(*p, GetDllShareData().m_Common.m_sEdit.m_bEnableExtEol)); ++p)
				;
			if (p >= p_end)
				break;

			//	Check Path
			if (IsFilePath(p, &nBgn, &nPathLen)) {
				strJumpToFile.assign(&p[nBgn], nPathLen);
				GetLineColumn(&p[nBgn + nPathLen], &nJumpToLine, &nJumpToColumn);
				break;
			}
			//	skip non-space
			for (; p < p_end && (*p != LCHAR(' ') && *p != LCHAR('\t')); ++p)
				;
		}
	}
	if (strJumpToFile.empty()) return std::nullopt;

	TagJumpTarget target;
	target.line = nJumpToLine;
	target.column = nJumpToColumn;
	// :HWND:[番号] は「編集中のテキストから検索」の文書（原版 TagJumpSub はウィンドウハンドルとして読む）
	constexpr std::u16string_view prefix = LTEXT(":HWND:[");
	if (strJumpToFile.starts_with(prefix)) {
		std::uint64_t id = 0;
		size_t i = prefix.size();
		for (; i < strJumpToFile.size(); ++i) {
			const WCHAR c = strJumpToFile[i];
			const int d = (u'0' <= c && c <= u'9') ? c - u'0' : (u'a' <= c && c <= u'f') ? c - u'a' + 10
				: (u'A' <= c && c <= u'F') ? c - u'A' + 10 : -1;
			if (d < 0) break;
			id = id * 16 + static_cast<std::uint64_t>(d);
		}
		if (i == prefix.size()) return std::nullopt;
		target.sourceId = id;
		return target;
	}
	target.path = strJumpToFile;
	return target;
}

} // namespace sakura::core
