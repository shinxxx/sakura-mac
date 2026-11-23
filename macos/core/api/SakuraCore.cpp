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
#include "view/colors/CColorStrategy.h"
#include "env/CRegexKeyword.h"
#include "../src/color_support.h"
#include "mem/CMemoryIterator.h"
#include "config/app_constants.h"
#include "env/CDocTypeManager.h"
#include "doc/CDocTypeSetting.h"
#include "typeprop/CImpExpManager.h"
#include "func/CFuncLookup.h"
#include "func/CKeyBind.h"
#include "mem/CNativeW.h"
#include "util/string_ex2.h"
#include "types/CType.h"
#include "CSelectLang.h"
#include "env/CShareData.h"
#include "env/CShareData_IO.h"
#include "env/CDataProfile.h"
#include "env/CSearchKeywordManager.h"
#include "parse/CWordParse.h"
#include "recent/CRecentSearch.h"
#include "recent/CRecentReplace.h"
#include "env/DLLSHAREDATA.h"
#include "extmodule/CBregexp.h"
#include "io/CBinaryStream.h"
#include "io/CFileLoad.h"
#include "io/CTextStream.h"
#include "io/CIoBridge.h"
#include "recent/CMRUFile.h"
#include "recent/CMRUFolder.h"
#include "env/CFileNameManager.h"
#include "charset/charset.h"
#include "util/file.h"
#include "util/zoom.h"
#include "util/zoom.h"
#include "sakura_platform_hooks.h"

#include <algorithm>
#include <array>
#include <atomic>
#include <limits>
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

//! 导入了设置、还没有重新启动（第 35 步）。这时 Shutdown 不写出设置，以免盖掉导入的 sakura.ini
bool g_settingsImportPending = false;

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
	g_settingsImportPending = false;
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
	if (saveSettings && !g_settingsImportPending) {
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
// 导入设置（第 35 步）
// ---------------------------------------------------------------------------

namespace {

//! 用来调用 CShareData_IO 的各节的读写（protected）
class SettingsImportIO : private CShareData_IO {
public:
	//! 现在的历史（MRU、Keys、Grep、Folders、Cmd 这几节）写进 profile
	static void WriteHistory(CDataProfile& profile)
	{
		profile.SetWritingMode();
		ShareData_IO_Mru(profile);
		ShareData_IO_Keys(profile);
		ShareData_IO_Grep(profile);
		ShareData_IO_Folders(profile);
		ShareData_IO_Cmd(profile);
	}
};

//! 读入 path 的 ini。サクラエディタ的设置文件以外（没有 [Common] 的 nCaretType）返回 NotSettingsFile
ImportResult ReadSettingsFile(const Text& path, CDataProfile& profile)
{
	if (path.empty()) return ImportResult::ReadFailed;
	const std::filesystem::path file(path);
	std::error_code ec;
	if (!std::filesystem::is_regular_file(file, ec)) return ImportResult::ReadFailed;
	profile.SetReadingMode();
	if (!profile.ReadProfile(file)) return ImportResult::ReadFailed;
	// 共通設定的第一项（原版 ShareData_IO_Common。旧版本的 ini 也有）
	sakura::wstring value;
	if (!profile.GetProfileData(LTEXT("Common"), LTEXT("nCaretType"), value)) return ImportResult::NotSettingsFile;
	return ImportResult::Imported;
}

} // namespace

ImportResult CheckSettingsFile(const Text& path)
{
	CDataProfile profile;
	return ReadSettingsFile(path, profile);
}

Text SettingsBackupPath()
{
	auto path = GetIniFileName();
	path += ".before-import";
	return Text(sakura::path_to_wstring(path));
}

ImportResult ImportSettings(const Text& path)
{
	if (!IsStarted()) return ImportResult::WriteFailed;
	CDataProfile profile;
	if (const auto r = ReadSettingsFile(path, profile); r != ImportResult::Imported) return r;

	// 导入前的设置：现在的设置写出，留一份备份（sakura.ini.before-import）
	const auto iniPath = GetIniFileName();
	std::error_code ec;
	if (!g_settingsImportPending) {
		CShareData_IO::SaveShareData();
		if (std::filesystem::exists(iniPath, ec)) {
			std::filesystem::copy_file(iniPath, std::filesystem::path(SettingsBackupPath()),
				std::filesystem::copy_options::overwrite_existing, ec);
		}
	}

	// 历史（最近使ったファイル、検索・置換・Grep 的历史等）是这台 Mac 的文件，保留 Mac 的。
	// 除此以外（共通設定、キー割り当て、ツールバー、メインメニュー、タイプ別設定、強調キーワード等）全部用导入的
	SettingsImportIO::WriteHistory(profile);
	std::filesystem::create_directories(iniPath.parent_path(), ec);
	if (!profile.WriteProfile(iniPath, sakura::wstring(LTEXT(" sakura.ini テキストエディタ設定ファイル")))) {
		return ImportResult::WriteFailed;
	}
	// 与在 Windows 版换掉 sakura.ini 相同，重新启动以后生效。在那之前不写出设置
	g_settingsImportPending = true;
	return ImportResult::Imported;
}

bool IsSettingsImportPending() { return g_settingsImportPending; }

// ---------------------------------------------------------------------------
// 共通設定的读写（第 39 步）
// ---------------------------------------------------------------------------

namespace {

//! 共通設定的节的读写（CShareData_IO 的 protected 函数）
class CommonSettingIO : private CShareData_IO {
public:
	//! 节的读写。不是共通設定窗口、タイプ別設定窗口用的节时 false
	static bool IO(CDataProfile& profile, sakura::wstring_view section)
	{
		if (const int nType = TypeIndexOfSection(section); 0 <= nType) {
			// タイプ別設定（第 40 步）：Types(N) 与读写 sakura.ini 时相同（ShareData_IO_TypeConfig），
			// 读入后与原版 OK 时相同地换掉这个类型的设置（CPropTypes → CDocTypeManager::SetTypeConfig）
			STypeConfig type;
			if (!CDocTypeManager().GetTypeConfig(CTypeConfig(nType), type)) return false;
			ShareData_IO_TypeConfig(profile, section, type);
			if (profile.IsReadingMode()) {
				type.m_nIdx = nType;
				(void)CDocTypeManager().SetTypeConfig(CTypeConfig(nType), type);
			}
		} else if (section == LTEXT("KeyWords")) {
			ShareData_IO_KeyWords(profile);	// 第 40 步：共通設定 > 強調キーワード
		} else if (section == LTEXT("KeyBind")) {
			// 第 41 步：共通設定 > キー割り当て
			::ShareData_IO_KeyBind(profile, GetDllShareData().m_Common.m_sKeyBind, false);
		} else if (section == LTEXT("Common")) {
			ShareData_IO_Common(profile);
		} else if (section == LTEXT("Nickname")) {
			ShareData_IO_Nickname(profile);
		} else if (section == LTEXT("Statusbar")) {
			ShareData_IO_Statusbar(profile);
		} else {
			return false;
		}
		return true;
	}

	//! "Types(N)" 的 N（タイプ別設定 的编号）。不是这个形式或没有这个类型时 -1
	static int TypeIndexOfSection(sakura::wstring_view section)
	{
		constexpr sakura::wstring_view prefix = LTEXT("Types(");
		if (section.size() <= prefix.size() + 1 || section.substr(0, prefix.size()) != prefix || section.back() != LCHAR(')')) {
			return -1;
		}
		const auto digits = section.substr(prefix.size(), section.size() - prefix.size() - 1);
		int n = 0;
		for (const auto ch : digits) {
			if (ch < LCHAR('0') || LCHAR('9') < ch || 1000 <= n) return -1;
			n = n * 10 + (ch - LCHAR('0'));
		}
		if (1 < digits.size() && digits.front() == LCHAR('0')) return -1;	// Types(01) 等不是 sakura.ini 的名字
		return n < GetDllShareData().m_nTypesCount ? n : -1;
	}
};

} // namespace

std::optional<Text> GetCommonSetting(const Text& section, const Text& key)
{
	if (!IsStarted()) return std::nullopt;
	CDataProfile profile;
	profile.SetWritingMode();
	if (!CommonSettingIO::IO(profile, section)) return std::nullopt;
	sakura::wstring value;
	if (!profile.GetProfileData(section, key, value)) return std::nullopt;
	return Text(value);
}

bool SetCommonSetting(const Text& section, const Text& key, const Text& value)
{
	return SetCommonSettings(section, { { key, value } });
}

bool SetCommonSettings(const Text& section, const std::vector<std::pair<Text, Text>>& values)
{
	if (!IsStarted()) return false;
	// 这一节现在的值写进 profile（失败时恢复用）
	CDataProfile before;
	before.SetWritingMode();
	if (!CommonSettingIO::IO(before, section)) return false;
	// 再写一次，换这些项，按原版读入（范围限制、ArrNum 以后的项清空等与读 sakura.ini 时相同）
	CDataProfile profile;
	profile.SetWritingMode();
	CommonSettingIO::IO(profile, section);
	for (const auto& [key, value] : values) {
		profile.SetProfileData(section, key, value);
	}
	profile.SetReadingMode();
	CommonSettingIO::IO(profile, section);
	// 读入以后这一节里没有的项目（不存在的项目、ArrNum 以外的 From%02d 等）：失败，恢复原来的值
	CDataProfile after;
	after.SetWritingMode();
	CommonSettingIO::IO(after, section);
	for (const auto& [key, value] : values) {
		sakura::wstring current;
		if (!after.GetProfileData(section, key, current) && !value.empty()) {	// 空的值：列表变短了（第 40 步）
			before.SetReadingMode();
			CommonSettingIO::IO(before, section);
			return false;
		}
	}
	return true;
}

std::vector<TypeSettingInfo> TypeSettings()
{
	std::vector<TypeSettingInfo> result;
	if (!IsStarted()) return result;
	for (int i = 0; i < GetDllShareData().m_nTypesCount; ++i) {
		const STypeConfigMini* mini = nullptr;
		if (!CDocTypeManager().GetTypeConfigMini(CTypeConfig(i), &mini)) continue;
		result.push_back({ i, Text(mini->m_szTypeName.c_str()), Text(mini->m_szTypeExts.c_str()) });
	}
	return result;
}

std::vector<ColorItemInfo> ColorItems()
{
	std::vector<ColorItemInfo> result;
	for (int i = 0; i < COLORIDX_LAST; ++i) {
		ColorInfo info{};
		GetDefaultColorInfoName(&info, i);
		const DWORD attr = g_ColorAttributeArr[i].fAttribute;
		ColorItemInfo item;
		item.index = i;
		item.name = Text(info.m_szName);
		item.key = Text(LTEXT("C[")) + GetColorNameByIndex(i) + LTEXT("]");
		item.forceDisplay = (attr & COLOR_ATTRIB_FORCE_DISP) != 0;
		item.noText = (attr & COLOR_ATTRIB_NO_TEXT) != 0;
		item.noBack = (attr & COLOR_ATTRIB_NO_BACK) != 0;
		item.noBold = (attr & COLOR_ATTRIB_NO_BOLD) != 0;
		item.noUnderline = (attr & COLOR_ATTRIB_NO_UNDERLINE) != 0;
		result.push_back(std::move(item));
	}
	return result;
}

std::vector<Text> KeywordSetNames()
{
	std::vector<Text> result;
	if (!IsStarted()) return result;
	auto& mgr = GetDllShareData().m_Common.m_sSpecialKeyword.m_CKeyWordSetMgr;
	for (int i = 0; i < mgr.m_nKeyWordSetNum; ++i) {
		result.emplace_back(mgr.GetTypeName(i));
	}
	return result;
}

namespace {

//! 第 nType 个类型的设置加上窗口里的值（[Types(N)] 的项目）。核心库的设置不改
bool TypeConfigWithPending(int nType, const std::vector<std::pair<Text, Text>>& pending, STypeConfig& type)
{
	if (!IsStarted() || !CDocTypeManager().GetTypeConfig(CTypeConfig(nType), type)) return false;
	constexpr auto section = LTEXT("Types");
	CDataProfile profile;
	profile.SetWritingMode();
	ShareData_IO_TypeConfig(profile, section, type);
	for (const auto& [key, value] : pending) {
		profile.SetProfileData(section, key, value);
	}
	profile.SetReadingMode();
	ShareData_IO_TypeConfig(profile, section, type);
	type.m_nIdx = nType;
	for (int i = 0; i < COLORIDX_LAST; ++i) {
		GetDefaultColorInfoName(&type.m_ColorInfoArr[i], i);	// 正規表現キーワードのインポートは色の名前でも探す
	}
	return true;
}

//! 导入后要返回的项目
std::vector<sakura::wstring> TypeSettingFileKeys(TypeSettingFile kind)
{
	std::vector<sakura::wstring> keys;
	switch (kind) {
	case TypeSettingFile::Colors:
		for (int i = 0; i < COLORIDX_LAST; ++i) keys.push_back(strprintf(LTEXT("C[%s]"), GetColorNameByIndex(i)));
		break;
	case TypeSettingFile::RegexKeywords:
		for (int i = 0; i < MAX_REGEX_KEYWORD; ++i) keys.push_back(strprintf(LTEXT("RxKey[%03d]"), i));
		break;
	case TypeSettingFile::KeywordHelp:
		for (int i = 0; i < MAX_KEYHELP_FILE; ++i) keys.push_back(strprintf(LTEXT("KDct[%02d]"), i));
		break;
	}
	return keys;
}

std::unique_ptr<CImpExpManager> TypeSettingFileManager(TypeSettingFile kind, STypeConfig& type)
{
	switch (kind) {
	case TypeSettingFile::Colors: return std::make_unique<CImpExpColors>(type.m_ColorInfoArr);
	case TypeSettingFile::RegexKeywords: return std::make_unique<CImpExpRegex>(type);
	case TypeSettingFile::KeywordHelp: return std::make_unique<CImpExpKeyHelp>(type);
	}
	return nullptr;
}

} // namespace

TypeSettingFileResult ImportTypeSettingFile(TypeSettingFile kind, std::int32_t typeIndex,
	const std::vector<std::pair<Text, Text>>& pending, const Text& path)
{
	TypeSettingFileResult result;
	STypeConfig type;
	if (!TypeConfigWithPending(typeIndex, pending, type)) return result;
	auto manager = TypeSettingFileManager(kind, type);
	sakura::wstring message;
	try {
		result.succeeded = manager && manager->Import(sakura::wstring(path), message);
	} catch (...) {
		// BOM のないファイルは Shift_JIS として読む（原版 CTextInputStream）。変換できない文字があると Mac 版の変換は例外になる
		result.succeeded = false;
		message = LS(STR_IMPEXP_ERR_FILEOPEN) + sakura::wstring(path);
	}
	result.message = Text(message);
	if (!result.succeeded) return result;
	// 读入以后的值（sakura.ini 的写法）
	constexpr auto section = LTEXT("Types");
	CDataProfile profile;
	profile.SetWritingMode();
	ShareData_IO_TypeConfig(profile, section, type);
	for (const auto& key : TypeSettingFileKeys(kind)) {
		sakura::wstring value;
		(void)profile.GetProfileData(section, key, value);
		result.values.emplace_back(Text(key), Text(value));
	}
	return result;
}

TypeSettingFileResult ExportTypeSettingFile(TypeSettingFile kind, std::int32_t typeIndex,
	const std::vector<std::pair<Text, Text>>& pending, const Text& path)
{
	TypeSettingFileResult result;
	STypeConfig type;
	if (!TypeConfigWithPending(typeIndex, pending, type)) return result;
	auto manager = TypeSettingFileManager(kind, type);
	sakura::wstring message;
	try {
		result.succeeded = manager && manager->Export(sakura::wstring(path), message);
	} catch (...) {
		result.succeeded = false;
		message = LS(STR_IMPEXP_ERR_EXPORT) + sakura::wstring(path);
	}
	result.message = Text(message);
	return result;
}

// ---------------------------------------------------------------------------
// タイプ別設定一覧（第 40 步。原版 CDlgTypeList）
// ---------------------------------------------------------------------------

std::int32_t MaxTypeSettings() { return MAX_TYPES; }

std::int32_t AddTypeSetting()
{
	if (!IsStarted()) return -1;
	const int nNew = GetDllShareData().m_nTypesCount;
	return CDocTypeManager().AddTypeConfig(CTypeConfig(nNew)) ? nNew : -1;
}

std::int32_t CopyTypeSetting(std::int32_t index)
{
	// 原版 CDlgTypeList::CopyType
	if (!IsStarted()) return -1;
	const int nNewTypeIndex = GetDllShareData().m_nTypesCount;
	STypeConfig type;
	if (!CDocTypeManager().GetTypeConfig(CTypeConfig(index), type)) return -1;
	int n = 1;
	bool bUpdate = true;
	for (int i = 0; i < nNewTypeIndex; i++) {
		if (bUpdate) {
			WCHAR* p = nullptr;
			for (int k = (int)wcslen(type.m_szTypeName) - 1; 0 <= k; k--) {
				if (WCODE::Is09(type.m_szTypeName[k])) {
					p = &type.m_szTypeName[k];
				} else {
					break;
				}
			}
			if (p) {
				n = _wtoi(p) + 1;
				*p = LCHAR('\0');
			} else {
				n++;
			}
			WCHAR szNum[12];
			auto_sprintf(szNum, LTEXT("%d"), n);
			const auto nLen = int(wcslen(szNum));
			WCHAR szTemp[std::size(type.m_szTypeName) + 12];
			wcscpy(szTemp, type.m_szTypeName);
			const auto nTempLen = int(wcslen(szTemp));
			CNativeW cmem;
			LimitStringLengthW(szTemp, nTempLen, int(std::size(type.m_szTypeName)) - nLen - 1, cmem);
			wcscpy(type.m_szTypeName, cmem.GetStringPtr());
			wcscat(type.m_szTypeName, szNum);
			bUpdate = false;
		}
		const STypeConfigMini* typeMini = nullptr;
		if (!CDocTypeManager().GetTypeConfigMini(CTypeConfig(i), &typeMini)) continue;
		if (wcscmp(typeMini->m_szTypeName, type.m_szTypeName) == 0) {
			i = -1;
			bUpdate = true;
		}
	}
	if (!CDocTypeManager().AddTypeConfig(CTypeConfig(nNewTypeIndex))) return -1;
	type.m_id = int(::GetTickCount64() & 0x3fffffff) + nNewTypeIndex * 0x10000;
	type.m_nIdx = nNewTypeIndex;
	type.m_nRegexKeyMagicNumber = CRegexKeyword::GetNewMagicNumber();
	CDocTypeManager().SetTypeConfig(CTypeConfig(nNewTypeIndex), type);
	return nNewTypeIndex;
}

bool DeleteTypeSetting(std::int32_t index)
{
	if (!IsStarted() || index <= 0) return false;
	return CDocTypeManager().DelTypeConfig(CTypeConfig(index));
}

std::int32_t MoveTypeSetting(std::int32_t index, bool up)
{
	// 原版 CDlgTypeList::UpType / DownType：「基本」は動かない
	if (!IsStarted() || index <= 0) return -1;
	const int other = up ? index - 1 : index + 1;
	if (other <= 0 || GetDllShareData().m_nTypesCount <= other) return -1;
	auto type1 = std::make_unique<STypeConfig>();
	auto type2 = std::make_unique<STypeConfig>();
	CDocTypeManager().GetTypeConfig(CTypeConfig(index), *type1);
	CDocTypeManager().GetTypeConfig(CTypeConfig(other), *type2);
	type1->m_nIdx = other;
	type2->m_nIdx = index;
	CDocTypeManager().SetTypeConfig(CTypeConfig(index), *type2);
	CDocTypeManager().SetTypeConfig(CTypeConfig(other), *type1);
	return other;
}

Text InitializeTypeSetting(std::int32_t index)
{
	// 原版 CDlgTypeList::InitializeType（確認は画面側）
	if (!IsStarted()) return {};
	const STypeConfigMini* typeMini = nullptr;
	if (!CDocTypeManager().GetTypeConfigMini(CTypeConfig(index), &typeMini)) return {};
	const int iDocType = CDocTypeManager().GetDocumentTypeOfId(typeMini->m_id).GetIndex();
	if (iDocType < 0) return {};
	auto type = std::make_unique<STypeConfig>();
	if (0 != iDocType) {
		CDocTypeManager().GetTypeConfig(CTypeConfig(0), *type);	// 基本をコピー
		int nNameNum = iDocType + 1;
		bool bUpdate = true;
		for (int i = 1; i < GetDllShareData().m_nTypesCount; i++) {
			if (bUpdate) {
				auto_sprintf(type->m_szTypeName, LS(STR_DLGTYPELIST_SETNAME), nNameNum);
				nNameNum++;
				bUpdate = false;
			}
			if (iDocType == i) continue;
			const STypeConfigMini* typeMini2 = nullptr;
			if (!CDocTypeManager().GetTypeConfigMini(CTypeConfig(i), &typeMini2)) continue;
			if (wcscmp(typeMini2->m_szTypeName, type->m_szTypeName) == 0) {
				i = 0;
				bUpdate = true;
			}
		}
		type->m_szTypeExts[0] = LCHAR('\0');
		type->m_nIdx = iDocType;
		type->m_id = int(::GetTickCount64() & 0x3fffffff) + iDocType * 0x10000;
		type->m_nRegexKeyMagicNumber = CRegexKeyword::GetNewMagicNumber();
	} else {
		CType_Basis basis;
		basis.InitTypeConfig(0, *type);
	}
	CDocTypeManager().SetTypeConfig(CTypeConfig(iDocType), *type);
	return Text(type->m_szTypeName.c_str());
}

namespace {

//! インポート・エクスポートのフォルダー（原版 CImpExpManager::SetImportFolder。キーワード・色のファイルはここ）
void SetImportFolderOf(const Text& path)
{
	auto& folder = GetDllShareData().m_sHistory.m_szIMPORTFOLDER;
	::SplitPath_FolderAndFile(path.c_str(), folder, nullptr);
	wcscat_s(folder, LTEXT("/"));
}

} // namespace

TypeSettingFileInfo CheckTypeSettingFile(const Text& path)
{
	TypeSettingFileInfo info;
	if (!IsStarted()) return info;
	STypeConfig type;
	CImpExpType imp(0, type, nullptr);
	sakura::wstring message;
	try {
		info.succeeded = imp.ImportAscertain(nullptr, nullptr, sakura::wstring(path), message);
	} catch (...) {
		info.succeeded = false;
		message = LS(STR_IMPEXP_ERR_FILEOPEN) + sakura::wstring(path);
	}
	info.message = Text(message);
	if (!info.succeeded) return info;
	sakura::wstring name, version;
	int nStructureVersion = 0;
	imp.GetFileInfoMac(name, version, nStructureVersion);
	info.typeName = Text(name);
	info.version = Text(version);
	info.structureVersion = nStructureVersion;
	info.versionDiffers = static_cast<unsigned int>(nStructureVersion) != GetDllShareData().m_vStructureVersion;
	// 同じフォルダーの *.col（原版 CDlgTypeAscertain::SetData）
	std::error_code ec;
	const auto dir = std::filesystem::path(path).parent_path();
	for (const auto& entry : std::filesystem::directory_iterator(dir, ec)) {
		if (entry.is_regular_file(ec) && entry.path().extension() == ".col") {
			info.colorFiles.push_back(entry.path().filename().u16string());
		}
	}
	std::sort(info.colorFiles.begin(), info.colorFiles.end());
	return info;
}

TypeSettingImportResult ImportTypeSetting(const Text& path, std::int32_t index, const TypeSettingImportChoice& choice)
{
	// 原版 CDlgTypeList::Import
	TypeSettingImportResult result;
	if (!IsStarted()) return result;
	const STypeConfigMini* typeMini = nullptr;
	if (!CDocTypeManager().GetTypeConfigMini(CTypeConfig(index), &typeMini)) return result;
	const int id = typeMini->m_id;
	STypeConfig type;
	CDocTypeManager().GetTypeConfig(CTypeConfig(0), type);
	CImpExpType imp(index, type, nullptr);
	sakura::wstring message;
	try {
		if (!imp.ImportAscertain(nullptr, nullptr, sakura::wstring(path), message)) {
			result.message = Text(message);
			return result;
		}
		SetImportFolderOf(path);
		int nColorType = choice.colorType;
		if (!choice.colorFile.empty()) nColorType = MAX_TYPES;
		imp.SetAscertainResultMac(nColorType, sakura::wstring(choice.colorFile), choice.addNew);
		if (!imp.Import(sakura::wstring(path), message)) {
			result.message = Text(message);
			return result;
		}
	} catch (...) {
		result.message = Text(LS(STR_IMPEXP_ERR_FILEOPEN) + sakura::wstring(path));
		return result;
	}
	int nIdx;
	if (choice.addNew) {
		nIdx = AddTypeSetting();
		if (nIdx < 0) return result;
	} else {
		nIdx = CDocTypeManager().GetDocumentTypeOfId(id).GetIndex();
		if (nIdx < 0) return result;
	}
	type.m_nIdx = nIdx;
	type.m_nRegexKeyMagicNumber = CRegexKeyword::GetNewMagicNumber();
	CDocTypeManager().SetTypeConfig(CTypeConfig(nIdx), type);
	result.succeeded = true;
	result.message = Text(message);
	result.index = nIdx;
	result.added = choice.addNew;
	return result;
}

TypeSettingFileResult ExportTypeSetting(std::int32_t index, const Text& path)
{
	TypeSettingFileResult result;
	if (!IsStarted()) return result;
	STypeConfig type;
	if (!CDocTypeManager().GetTypeConfig(CTypeConfig(index), type)) return result;
	CImpExpType imp(index, type, nullptr);
	imp.SetBaseName(sakura::wstring(type.m_szTypeName.c_str()));
	SetImportFolderOf(path);
	sakura::wstring message;
	try {
		result.succeeded = imp.Export(sakura::wstring(path), message);
	} catch (...) {
		result.succeeded = false;
		message = LS(STR_IMPEXP_ERR_EXPORT) + sakura::wstring(path);
	}
	result.message = Text(message);
	return result;
}

// ---------------------------------------------------------------------------
// 共通設定 > 強調キーワード（第 40 步）
// ---------------------------------------------------------------------------

struct KeywordSetEditor::Impl {
	std::unique_ptr<CommonSetting> common;	//!< 原版 CPropCommon::m_Common と同じ複製（CImpExpKeyWord はこれを使う）
	int initialSetCount = 0;				//!< 作ったときのセット数（減ったセットの項目を空にする）
	CKeyWordSetMgr& Mgr() { return common->m_sSpecialKeyword.m_CKeyWordSetMgr; }
	const CKeyWordSetMgr& Mgr() const { return common->m_sSpecialKeyword.m_CKeyWordSetMgr; }
	bool Valid(int set) const { return 0 <= set && set < Mgr().m_nKeyWordSetNum; }
};

KeywordSetEditor::KeywordSetEditor() : m_impl(std::make_unique<Impl>()) {}
KeywordSetEditor::~KeywordSetEditor() = default;

std::unique_ptr<KeywordSetEditor> KeywordSetEditor::Create()
{
	if (!IsStarted()) return nullptr;
	std::unique_ptr<KeywordSetEditor> editor(new KeywordSetEditor());
	editor->m_impl->common = std::make_unique<CommonSetting>(GetDllShareData().m_Common);
	editor->m_impl->initialSetCount = editor->m_impl->Mgr().m_nKeyWordSetNum;
	return editor;
}

std::int32_t KeywordSetEditor::SetCount() const { return m_impl->Mgr().m_nKeyWordSetNum; }

Text KeywordSetEditor::SetName(std::int32_t set) const
{
	return m_impl->Valid(set) ? Text(const_cast<CKeyWordSetMgr&>(m_impl->Mgr()).GetTypeName(set)) : Text();
}

bool KeywordSetEditor::IsCaseSensitive(std::int32_t set) const
{
	return m_impl->Valid(set) && const_cast<CKeyWordSetMgr&>(m_impl->Mgr()).GetKeyWordCase(set);
}

std::int32_t KeywordSetEditor::CurrentSet() const
{
	const auto& mgr = m_impl->Mgr();
	if (mgr.m_nKeyWordSetNum <= 0) return -1;
	return std::clamp(mgr.m_nCurrentKeyWordSetIdx, 0, mgr.m_nKeyWordSetNum - 1);
}

void KeywordSetEditor::SetCurrentSet(std::int32_t set)
{
	if (m_impl->Valid(set)) m_impl->Mgr().m_nCurrentKeyWordSetIdx = set;
}

std::vector<KeywordSetEditor::Keyword> KeywordSetEditor::Keywords(std::int32_t set) const
{
	std::vector<Keyword> result;
	if (!m_impl->Valid(set)) return result;
	auto& mgr = const_cast<CKeyWordSetMgr&>(m_impl->Mgr());
	for (int i = 0; i < mgr.GetKeyWordNum(set); ++i) {
		result.push_back({ i, Text(mgr.GetKeyWord(set, i)) });
	}
	std::stable_sort(result.begin(), result.end(), [](const Keyword& a, const Keyword& b) { return a.text < b.text; });
	return result;
}

std::int32_t KeywordSetEditor::FreeCount(std::int32_t set) const
{
	if (!m_impl->Valid(set)) return 0;
	auto& mgr = const_cast<CKeyWordSetMgr&>(m_impl->Mgr());
	// 原版 DispKeywordCount：確保済みの空き + 未割り当て
	return mgr.GetAllocSize(set) - mgr.GetKeyWordNum(set) + mgr.GetFreeSize();
}

bool KeywordSetEditor::CanAddKeyword(std::int32_t set) const
{
	return m_impl->Valid(set) && const_cast<CKeyWordSetMgr&>(m_impl->Mgr()).CanAddKeyWord(set);
}

bool KeywordSetEditor::AddSet(const Text& name)
{
	auto& mgr = m_impl->Mgr();
	if (MAX_SETNUM <= mgr.m_nKeyWordSetNum || name.empty()) return false;
	if (!mgr.AddKeyWordSet(name.c_str(), false)) return false;
	mgr.m_nCurrentKeyWordSetIdx = mgr.m_nKeyWordSetNum - 1;
	return true;
}

bool KeywordSetEditor::DeleteSet(std::int32_t set)
{
	if (!m_impl->Valid(set)) return false;
	return m_impl->Mgr().DelKeyWordSet(set);
}

void KeywordSetEditor::RenameSet(std::int32_t set, const Text& name)
{
	if (m_impl->Valid(set) && !name.empty()) m_impl->Mgr().SetTypeName(set, name.c_str());
}

void KeywordSetEditor::SetCaseSensitive(std::int32_t set, bool on)
{
	if (m_impl->Valid(set)) m_impl->Mgr().SetKeyWordCase(set, on ? 1 : 0);
}

std::int32_t KeywordSetEditor::AddKeyword(std::int32_t set, const Text& keyword)
{
	if (!m_impl->Valid(set)) return 1;
	return m_impl->Mgr().AddKeyWord(set, keyword.c_str());
}

bool KeywordSetEditor::UpdateKeyword(std::int32_t set, std::int32_t index, const Text& keyword)
{
	if (!m_impl->Valid(set)) return false;
	return m_impl->Mgr().UpdateKeyWord(set, index, keyword.c_str()) != nullptr;
}

void KeywordSetEditor::DeleteKeyword(std::int32_t set, std::int32_t index)
{
	if (m_impl->Valid(set)) m_impl->Mgr().DelKeyWord(set, index);
}

std::int32_t KeywordSetEditor::Clean(std::int32_t set)
{
	return m_impl->Valid(set) ? m_impl->Mgr().CleanKeyWords(set) : 0;
}

bool KeywordSetEditor::Import(std::int32_t set, const Text& path, Text& message)
{
	if (!m_impl->Valid(set)) return false;
	bool bCase = false;	// 原版 Import_List_KeyWord：ファイルに CASE がなければ区別しない
	CImpExpKeyWord cImpExpKeyWord(*m_impl->common, set, bCase);
	sakura::wstring msg;
	bool ok = false;
	try {
		ok = cImpExpKeyWord.Import(sakura::wstring(path), msg);
	} catch (...) {
		ok = false;
		msg = LS(STR_IMPEXP_ERR_FILEOPEN) + sakura::wstring(path);
	}
	message = Text(msg);
	return ok;
}

bool KeywordSetEditor::Export(std::int32_t set, const Text& path, Text& message)
{
	if (!m_impl->Valid(set)) return false;
	bool bCase = m_impl->Mgr().GetKeyWordCase(set);
	CImpExpKeyWord cImpExpKeyWord(*m_impl->common, set, bCase);
	sakura::wstring msg;
	bool ok = false;
	try {
		ok = cImpExpKeyWord.Export(sakura::wstring(path), msg);
	} catch (...) {
		ok = false;
		msg = LS(STR_IMPEXP_ERR_EXPORT) + sakura::wstring(path);
	}
	message = Text(msg);
	return ok;
}

std::vector<std::pair<Text, Text>> KeywordSetEditor::IniValues() const
{
	// 原版 ShareData_IO_KeyWords の書き込みと同じ
	auto& mgr = const_cast<CKeyWordSetMgr&>(m_impl->Mgr());
	constexpr auto section = LTEXT("KeyWords");
	CDataProfile profile;
	profile.SetWritingMode();
	int nCurrent = mgr.m_nCurrentKeyWordSetIdx;
	int nSetNum = mgr.m_nKeyWordSetNum;
	profile.IOProfileData(section, LTEXT("nCurrentKeyWordSetIdx"), nCurrent);
	profile.IOProfileData(section, LTEXT("nKeyWordSetNum"), nSetNum);
	std::vector<sakura::wstring> keys = { LTEXT("nCurrentKeyWordSetIdx"), LTEXT("nKeyWordSetNum") };
	const int nKeys = std::max(nSetNum, m_impl->initialSetCount);
	for (int i = 0; i < nKeys; ++i) {
		const auto sn = strprintf(LTEXT("szSN[%02d]"), i), cs = strprintf(LTEXT("nCASE[%02d]"), i);
		const auto kwn = strprintf(LTEXT("nKWN[%02d]"), i), size = strprintf(LTEXT("szKW[%02d].Size"), i);
		const auto kw = strprintf(LTEXT("szKW[%02d]"), i);
		keys.insert(keys.end(), { sn, cs, kwn, size, kw });
		if (nSetNum <= i) continue;	// 減ったセット：空の値
		profile.IOProfileData(section, sn, StringBufferW(mgr.m_szSetNameArr[i]));
		profile.IOProfileData(section, cs, mgr.m_bKEYWORDCASEArr[i]);
		profile.IOProfileData(section, kwn, mgr.m_nKeyWordNumArr[i]);
		sakura::wstring strMem;
		for (int j = 0; j < mgr.m_nKeyWordNumArr[i]; ++j) {
			strMem += mgr.GetKeyWord(i, j);
			strMem += LCHAR('\t');
		}
		auto nMemLen = static_cast<int>(strMem.length() + 1);
		profile.IOProfileData(section, size, nMemLen);
		profile.IOProfileData(section, kw, strMem);
	}
	std::vector<std::pair<Text, Text>> result;
	for (const auto& key : keys) {
		sakura::wstring value;
		(void)profile.GetProfileData(section, key, value);
		result.emplace_back(Text(key), Text(value));
	}
	return result;
}

// ---------------------------------------------------------------------------
// 共通設定 > キー割り当て・メインメニュー・ツールバー・カスタムメニュー（第 41 步）
// ---------------------------------------------------------------------------

struct CommandSettingsEditor::Impl {
	std::unique_ptr<CommonSetting> common;	//!< 原版 CPropCommon::m_Common と同じ複製
	CFuncLookup lookup;						//!< 原版 CPropCommon::m_cLookup（この複製を見る）
	CommonSetting_KeyBind& KeyBind() { return common->m_sKeyBind; }
	const CommonSetting_KeyBind& KeyBind() const { return common->m_sKeyBind; }
	bool ValidKey(int key) const { return 0 <= key && key < KeyBind().m_nKeyNameArrNum; }
};

CommandSettingsEditor::CommandSettingsEditor() : m_impl(std::make_unique<Impl>()) {}
CommandSettingsEditor::~CommandSettingsEditor() = default;

std::unique_ptr<CommandSettingsEditor> CommandSettingsEditor::Create()
{
	if (!IsStarted()) return nullptr;
	std::unique_ptr<CommandSettingsEditor> editor(new CommandSettingsEditor());
	auto& impl = *editor->m_impl;
	impl.common = std::make_unique<CommonSetting>(GetDllShareData().m_Common);
	impl.lookup.Init(impl.common->m_sMacro.m_MacroTable, impl.common.get());
	return editor;
}

std::vector<Text> CommandSettingsEditor::FunctionCategories() const
{
	std::vector<Text> result;
	for (int i = 0; i < m_impl->lookup.GetCategoryCount(); ++i) {
		const WCHAR* name = m_impl->lookup.Category2Name(i);
		result.emplace_back(name ? name : LTEXT(""));
	}
	return result;
}

std::vector<FunctionInfo> CommandSettingsEditor::Functions(std::int32_t category) const
{
	// 原版 CFuncLookup::SetListItem
	std::vector<FunctionInfo> result;
	const int n = m_impl->lookup.GetItemCount(category);
	for (int i = 0; i < n; ++i) {
		const EFunctionCode code = m_impl->lookup.Pos2FuncCode(category, i);
		if (code == F_DISABLE) continue;
		WCHAR label[256];
		m_impl->lookup.Pos2FuncName(category, i, label, std::size(label));
		result.push_back({ static_cast<FunctionCode>(code), Text(label) });
	}
	return result;
}

Text CommandSettingsEditor::FunctionName(FunctionCode code) const
{
	WCHAR label[256];
	m_impl->lookup.Funccode2Name(code, label, std::size(label));
	return Text(label);
}

std::int32_t CommandSettingsEditor::KeyCount() const { return m_impl->KeyBind().m_nKeyNameArrNum; }

Text CommandSettingsEditor::KeyName(std::int32_t key) const
{
	return m_impl->ValidKey(key) ? Text(m_impl->KeyBind().m_pKeyNameArr[key].m_szKeyName) : Text();
}

FunctionCode CommandSettingsEditor::KeyFunction(std::int32_t key, std::uint8_t modifiers) const
{
	if (!m_impl->ValidKey(key) || 8 <= modifiers) return 0;
	return m_impl->KeyBind().m_pKeyNameArr[key].m_nFuncCodeArr[modifiers];
}

void CommandSettingsEditor::SetKeyFunction(std::int32_t key, std::uint8_t modifiers, FunctionCode code)
{
	if (!m_impl->ValidKey(key) || 8 <= modifiers) return;
	m_impl->KeyBind().m_pKeyNameArr[key].m_nFuncCodeArr[modifiers] = static_cast<EFunctionCode>(code);
}

std::vector<Text> CommandSettingsEditor::AssignedKeys(FunctionCode code) const
{
	auto& keyBind = m_impl->KeyBind();
	CNativeW** list = nullptr;
	const int n = CKeyBind::GetKeyStrList(nullptr, keyBind.m_nKeyNameArrNum, keyBind.m_pKeyNameArr,
		&list, code, FALSE);	// 原版：デフォルト機能は取得しない
	std::vector<Text> result;
	for (int i = 0; i < n; ++i) {
		result.emplace_back(list[i]->GetStringPtr());
		delete list[i];
	}
	delete[] list;
	return result;
}

namespace {

bool RunImpExp(CImpExpManager& manager, bool import, const Text& path, Text& message)
{
	sakura::wstring msg;
	bool ok = false;
	try {
		ok = import ? manager.Import(sakura::wstring(path), msg) : manager.Export(sakura::wstring(path), msg);
	} catch (...) {
		ok = false;
		msg = (import ? LS(STR_IMPEXP_ERR_FILEOPEN) : LS(STR_IMPEXP_ERR_EXPORT)) + sakura::wstring(path);
	}
	message = Text(msg);
	return ok;
}

} // namespace

bool CommandSettingsEditor::ImportKeyBind(const Text& path, Text& message)
{
	CImpExpKeybind manager(*m_impl->common);
	return RunImpExp(manager, true, path, message);
}

bool CommandSettingsEditor::ExportKeyBind(const Text& path, Text& message)
{
	CImpExpKeybind manager(*m_impl->common);
	return RunImpExp(manager, false, path, message);
}

std::vector<std::pair<Text, Text>> CommandSettingsEditor::IniValues(const Text& section) const
{
	std::vector<std::pair<Text, Text>> result;
	CDataProfile profile;
	profile.SetWritingMode();
	std::vector<sakura::wstring> keys;
	if (section == LTEXT("KeyBind")) {
		ShareData_IO_KeyBind(profile, m_impl->common->m_sKeyBind, false);	// 原版 sakura.ini の書き込みと同じ
		for (int i = 0; i < m_impl->KeyBind().m_nKeyNameArrNum; ++i) keys.push_back(strprintf(LTEXT("KeyBind[%03d]"), i));
	} else {
		return result;
	}
	for (const auto& key : keys) {
		sakura::wstring value;
		if (profile.GetProfileData(section, key, value)) result.emplace_back(Text(key), Text(value));
	}
	return result;
}

RegexKeywordCheck CheckRegexKeyword(const Text& keyword)
{
	RegexKeywordCheck result;
	result.hasDelimiters = CRegexKeyword::RegexKeyCheckSyntax(keyword.c_str()) != FALSE;
	result.syntaxOK = CheckRegexpSyntax(keyword.c_str(), nullptr, false, -1, true);
	return result;
}

std::optional<Text> KeywordHelpDictionaryAbout(const Text& path)
{
	if (!IsStarted() || path.empty()) return std::nullopt;
	try {
		CTextInputStream_AbsIni in(path.c_str());
		if (!in) return std::nullopt;
		WCHAR szAbout[DICT_ABOUT_LEN]{};
		wcsncpy_s(szAbout, in.ReadLineW().c_str(), _TRUNCATE);
		in.Close();
		// 原版 strcnv：改行を削除、カンマを「.」に
		sakura::wstring about(szAbout);
		if (const auto pos = about.find_first_of(LTEXT("\r\n")); pos != sakura::wstring::npos) about.resize(pos);
		std::replace(about.begin(), about.end(), LCHAR(','), LCHAR('.'));
		return Text(about);
	} catch (...) {
		return std::nullopt;	// Shift_JIS として読めない文字
	}
}

bool SaveSettings()
{
	if (!IsStarted() || g_settingsImportPending) return false;
	CShareData_IO::SaveShareData();
	return true;
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

// 最近使ったファイル、最近使ったフォルダー（第 31 步）

namespace {

Text MenuLabelOfRecentFile(const EditInfo& fi, int index, bool bFavorite)
{
	WCHAR szMenu[_MAX_PATH * 2 + 10] = {};
	CFileNameManager::getInstance()->TransformFileName_MakeCache();
	CFileNameManager::getInstance()->GetMenuFullLabel_MRU(szMenu, int(std::size(szMenu)), &fi, -1, bFavorite, index, nullptr);
	return Text(szMenu);
}

RecentFile ToRecentFile(const EditInfo& fi)
{
	RecentFile r;
	r.path = Text(fi.m_szPath.c_str());
	r.encoding = fi.m_nCharCode;
	r.caret = Position{ std::max(0, static_cast<int>(fi.m_ptCursor.y)), std::max(0, static_cast<int>(fi.m_ptCursor.x)) };
	r.viewTopLine = std::max(0, static_cast<int>(fi.m_nViewTopLine));
	return r;
}

} // namespace

std::vector<RecentFile> RecentFiles()
{
	// 与原版 CMRUFile::CreateMenu 相同（到「ファイルの履歴MAX」为止）
	std::vector<RecentFile> result;
	if (!IsStarted()) return result;
	CRecentFile cRecentFile;
	for (int i = 0; i < cRecentFile.GetItemCount() && i < cRecentFile.GetViewCount(); ++i) {
		const EditInfo* p = cRecentFile.GetItem(i);
		if (!p) continue;
		RecentFile r = ToRecentFile(*p);
		r.favorite = cRecentFile.IsFavorite(i);
		r.menuLabel = MenuLabelOfRecentFile(*p, i, false);
		result.push_back(std::move(r));
	}
	cRecentFile.Terminate();
	return result;
}

std::vector<RecentFolder> RecentFolders()
{
	// 与原版 CMRUFolder::CreateMenu 相同（到「フォルダーの履歴MAX」为止）
	std::vector<RecentFolder> result;
	if (!IsStarted()) return result;
	CRecentFolder cRecentFolder;
	CFileNameManager::getInstance()->TransformFileName_MakeCache();
	for (int i = 0; i < cRecentFolder.GetItemCount() && i < cRecentFolder.GetViewCount(); ++i) {
		const WCHAR* pszFolder = cRecentFolder.GetItemText(i);
		if (!pszFolder) continue;
		RecentFolder r;
		r.path = Text(pszFolder);
		r.favorite = cRecentFolder.IsFavorite(i);
		WCHAR szMenu[_MAX_PATH * 2 + 10] = {};
		CFileNameManager::getInstance()->GetMenuFullLabel(szMenu, int(std::size(szMenu)), false, pszFolder, -1, false, CODE_NONE, false, i, true, nullptr);
		r.menuLabel = Text(szMenu);
		result.push_back(std::move(r));
	}
	cRecentFolder.Terminate();
	return result;
}

std::optional<RecentFile> FindRecentFile(const Text& path)
{
	if (!IsStarted() || path.empty()) return std::nullopt;
	EditInfo fi;
	if (!CMRUFile().GetEditInfo(path.c_str(), &fi)) return std::nullopt;
	return ToRecentFile(fi);
}

void RemoveRecentFile(const Text& path)
{
	if (!IsStarted() || path.empty()) return;
	CRecentFile cRecentFile;
	const int n = cRecentFile.FindItemByPath(path.c_str());
	if (0 <= n) cRecentFile.DeleteItem(n);
	cRecentFile.Terminate();
}

void ClearRecentFiles()
{
	if (!IsStarted()) return;
	CMRUFile cMRU;
	cMRU.ClearAll();
}

void ClearRecentFolders()
{
	if (!IsStarted()) return;
	CMRUFolder cMRUFolder;
	cMRUFolder.ClearAll();
}

// 文件对话框的编码列表（第 30 步）

std::vector<EncodingChoice> EncodingChoices()
{
	// 顺序与原版 CDlgOpenFile_CommonItemDialog::Customize 相同
	std::vector<EncodingChoice> result;
	CCodeTypesForCombobox cCodeTypes;
	for (size_t i = 0; i < cCodeTypes.GetCount(); ++i) {
		result.push_back({ cCodeTypes.GetCode(i), Text(cCodeTypes.GetName(i)) });
	}
	return result;
}

std::vector<EncodingChoice> CodePageChoices()
{
	// 与原版 CDlgOpenFile_CommonItemDialog::AddComboCodePages 相同
	std::vector<EncodingChoice> result;
	result.push_back({ CODE_CPACP, Text(LTEXT("CP_ACP")) });
	result.push_back({ CODE_CPOEM, Text(LTEXT("CP_OEM")) });
	for (const auto& cp : CCodePage::GetCodePageList()) {
		result.push_back({ cp.first, Text(cp.second) });
	}
	return result;
}

bool EncodingCanHaveBom(Encoding code)
{
	if (!IsValidCodeOrCPType(code)) return false;
	return CCodeTypeName(static_cast<ECodeType>(code)).UseBom();
}

bool EncodingBomDefault(Encoding code)
{
	if (!IsValidCodeOrCPType(code)) return false;
	return CCodeTypeName(static_cast<ECodeType>(code)).IsBomDefOn();
}

bool EncodingCanBeDefault(Encoding code)
{
	if (!IsValidCodeOrCPType(code)) return false;
	return CCodeTypeName(static_cast<ECodeType>(code)).CanDefault();
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
// 菜单与按键分配（第 34 步）
// ---------------------------------------------------------------------------

std::vector<MenuItem> MainMenu()
{
	std::vector<MenuItem> result;
	if (!IsStarted()) return result;
	const auto& menu = GetDllShareData().m_Common.m_sMainMenu;
	const int n = std::clamp<int>(menu.m_nMainMenuNum, 0, MAX_MAINMENU);
	result.reserve(n);
	for (int i = 0; i < n; ++i) {
		const CMainMenu& m = menu.m_cMainMenuTbl[i];
		MenuItem item;
		item.level = m.m_nLevel;
		item.type = static_cast<MenuItemType>(m.m_nType);
		item.code = m.m_nFunc;
		// 原版 CEditWnd::LayoutMainMenu：名字没有设置并且有功能编号时用字符串表
		if (m.m_sName[0] != L'\0') {
			item.name = Text(m.m_sName.c_str());
		} else if (m.m_nFunc != F_NODE && m.m_nFunc != F_0) {
			item.name = CommandName(m.m_nFunc);
		}
		item.accessKey = Text(m.m_sKey.c_str());
		result.push_back(std::move(item));
	}
	return result;
}

std::vector<KeyBinding> KeyBindings()
{
	std::vector<KeyBinding> result;
	if (!IsStarted()) return result;
	const auto& bind = GetDllShareData().m_Common.m_sKeyBind;
	const int n = std::clamp<int>(bind.m_nKeyNameArrNum, 0, int(std::size(bind.m_pKeyNameArr)) - 1);
	for (int i = 0; i < n; ++i) {
		const KEYDATA& key = bind.m_pKeyNameArr[i];
		// 鼠标（VKEX_DBL_CLICK 以后，0x100～）不是键盘
		if (key.m_nKeyCode <= 0 || 0x100 <= key.m_nKeyCode) continue;
		for (int mod = 0; mod < 8; ++mod) {
			if (key.m_nFuncCodeArr[mod] == F_0) continue;
			result.push_back(KeyBinding{ static_cast<std::uint16_t>(key.m_nKeyCode), static_cast<std::uint8_t>(mod),
				key.m_nFuncCodeArr[mod], Text(key.m_szKeyName) });
		}
	}
	return result;
}

FunctionCode FunctionForKey(std::uint16_t keyCode, std::uint8_t modifiers)
{
	if (!IsStarted() || 0x100 <= keyCode || 8 <= modifiers) return 0;
	const auto& bind = GetDllShareData().m_Common.m_sKeyBind;
	// 原版 CKeyBind::GetFuncCode：键码→表的下标（m_VKeyToKeyNameArr）
	const int idx = bind.m_VKeyToKeyNameArr[keyCode];
	if (idx < 0 || bind.m_nKeyNameArrNum < idx || int(std::size(bind.m_pKeyNameArr)) <= idx) return 0;
	const KEYDATA& key = bind.m_pKeyNameArr[idx];
	if (key.m_nKeyCode != keyCode) return 0;
	return key.m_nFuncCodeArr[modifiers];
}

// ---------------------------------------------------------------------------
// 文档
// ---------------------------------------------------------------------------

struct SearchMarkCache;	// 第 32 步：查找文字标记用的条件（定义在后面）

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
	std::uint64_t changeCount = 0;	//!< 文字、排版变了的次数（第 36 步：界面层的缓存是否还有效）
	CEol newLineEol{ EEolType::cr_and_lf };
	FileInfo info;
	//! 打开（保存）时的编码和 BOM（原版 SFileInfo 的 eCharCodeLoad、bBomExistLoad，第 34 步）
	Encoding loadedEncoding = encoding::UTF8;
	bool loadedBom = false;
	//! 挿入モード（原版 CDocEditor::m_bInsMode：按共通設定「挿入モード」开始，第 34 步）
	bool insertMode = GetDllShareData().m_Common.m_sGeneral.m_bIsINSMode;
	Text lastSearchError;
	std::optional<RestoredView> restoredView;	//!< 打开时从历史恢复的位置（第 31 步）
	std::shared_ptr<SearchMarkCache> searchMarkCache;	//!< 查找文字标记用的条件（第 32 步）
	std::unique_ptr<CRegexKeyword> regexKeyword;	//!< 正規表現キーワード（第 33 步，原版 CEditView::m_cRegexKeyword）
	bool typeLocked = false;	//!< タイプ別設定一覧の一時適用（原版 CDocType::m_nSettingTypeLocked。第 40 步）

	~Impl()
	{
		// 色分け对象是这个文档时清除（不留下指向已经释放的设置的指针）
		if (GetColorTypeConfigMac() == &typeConfig) SetColorTargetMac(nullptr, nullptr);
	}

	/*!
		让色分け（CColorStrategyPool）以这个文档为对象（第 33 步）。排版和取颜色之前调用。
		原版一个进程一个文档，CDocType::SetDocumentType 时 CColorStrategyPool::OnChangeSetting；
		Mac 版一个进程多个文档，切换文档时也重新读设置。
		@param force 类型别设置的内容改了时 true
	*/
	void ActivateColors(bool force = false)
	{
		// 正規表現キーワードの設定（CEditView::OnPaint2：変更があればタイプ設定を行う）
		if (typeConfig.m_bUseRegexKeyword || (regexKeyword && regexKeyword->m_bUseRegexKeyword)) {
			if (!regexKeyword) {
				regexKeyword = std::make_unique<CRegexKeyword>(GetDllShareData().m_Common.m_sSearch.m_szRegexpLib);
			}
			regexKeyword->RegexKeySetTypes(&typeConfig);
		}
		SetColorTargetMac(&typeConfig, regexKeyword.get(), force);
	}

	//! typeId 是历史里上次的类型（原版 EditInfo::m_nTypeId）。-1 或找不到时按文件名决定
	void ResetForType(const Text& path, int typeId = -1)
	{
		// 按文件名决定类型别设置（CDocTypeManager::GetDocumentTypeOfPath）
		CTypeConfig type = (0 <= typeId) ? CDocTypeManager().GetDocumentTypeOfId(typeId) : CTypeConfig(-1);
		if (!type.IsValidType()) {
			type = path.empty() ? CTypeConfig(0) : CDocTypeManager().GetDocumentTypeOfPath(path.c_str());
		}
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
		ActivateColors();	// 排版时记下每行开头的色分け状态（第 33 步）
		LayoutReplaceArg arg;
		layout.LogicToLayout(range, &arg.sDelRange);
		arg.pcmemDeleted = pDeleted;
		arg.pInsData = pInsData;
		arg.nDelSeq = nDelSeq;
		layout.ReplaceData_CLayoutMgr(&arg);
		++changeCount;
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
		ActivateColors(true);	// 类型别设置可能改了，重新读色分け的设置（第 33 步）
		layout.SetLayoutInfo(true, false, ref, ref.m_nTabSpace, ref.m_nTsvMode, nMaxLineKetas, CLayoutXInt(-1), &g_layoutFont);
		++changeCount;
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

	//! 新文档的状态（类型「基本」，编码是它的默认值）。Create 和 CloseToUntitled 用
	void InitNew()
	{
		ResetForType(Text());
		if (const STypeConfigMini* mini = TypeMini()) {
			info.encoding = mini->m_encoding.m_eDefaultCodetype;
			info.bom = mini->m_encoding.m_bDefaultBom;
		}
		loadedEncoding = info.encoding;
		loadedBom = info.bom;
		ResetNewLineEol();
		ResetWrap();
		DoLayout();
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
		++changeCount;
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
	doc->m_impl->InitNew();
	return doc;
}

void Document::CloseToUntitled()
{
	// CDocFileOperation::FileClose：既存データのクリア（CEditDoc::InitDoc）→ 新規文書
	auto& d = *m_impl;
	d.ClearDocument();
	d.info = FileInfo{};
	d.restoredView.reset();
	d.InitNew();
}

// ----- 打开、保存 -----

Result Document::Open(const Text& path, const OpenOptions& options)
{
	auto& d = *m_impl;
	if (path.empty()) return Result::InvalidArgument;
	if (options.encoding != encoding::AutoDetect && !IsValidCodeOrCPType(options.encoding)) return Result::InvalidArgument;

	d.ClearDocument();
	d.info = FileInfo{};
	d.restoredView.reset();

	// 历史里上次的编码和类型（CMruListener::OnBeforeLoad。第 31 步）
	EditInfo fiPrev;
	const bool bInMRU = options.useHistory && CMRUFile().GetEditInfo(path.c_str(), &fiPrev);
	const ECodeType ePrevCode = bInMRU ? fiPrev.m_nCharCode : CODE_NONE;
	d.ResetForType(path, bInMRU ? fiPrev.m_nTypeId : -1);
	d.ResetWrap();
	const STypeConfigMini* type = d.TypeMini();
	if (!type) return Result::Failed;

	// 以下与 CReadManager::ReadFile_To_CDocLineMgr 相同
	ECodeType eCharCode = static_cast<ECodeType>(options.encoding);
	const bool bSpecified = IsValidCodeOrCPType(eCharCode);	// 是否指定了编码
	if (CODE_AUTODETECT == eCharCode) {
		CCodeMediator cmediator(type->m_encoding);
		eCharCode = cmediator.CheckKanjiCodeOfFile(path.c_str());
	}
	if (!IsValidCodeOrCPType(eCharCode)) {
		eCharCode = type->m_encoding.m_eDefaultCodetype;
	}
	// 与上次的编码不同时（原版 CMruListener::OnBeforeLoad）
	if (IsValidCodeOrCPType(ePrevCode) && eCharCode != ePrevCode) {
		if (GetDllShareData().m_Common.m_sFile.GetQueryIfCodeChange() && options.askUsePreviousEncoding) {
			// 共通设置「前回と異なる文字コードの時に問い合わせを行う」
			if (options.askUsePreviousEncoding(eCharCode, ePrevCode)) {
				eCharCode = ePrevCode;
			}
		} else if (!bSpecified) {
			// 不问时：自动识别时用上次的编码，指定时用指定的编码（原版的默认回答）
			eCharCode = ePrevCode;
		}
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
	d.loadedEncoding = eCharCode;
	d.loadedBom = bBom;
	d.ResetNewLineEol();
	d.DoLayout();	// CLoadAgent::OnLoad

	// 恢复光标位置，登记到历史（与原版 CMruListener::OnAfterLoad 相同，第 31 步）
	if (options.useHistory) {
		Position caret{};
		std::int32_t viewTopLine = 0;
		if (bInMRU && GetDllShareData().m_Common.m_sFile.GetRestoreCurPosition()) {
			RestoredView view;
			CLayoutPoint ptCaretPos;
			d.layout.LogicToLayout(fiPrev.m_ptCursor, &ptCaretPos);
			if (ptCaretPos.GetY2() >= d.layout.GetLineCount()) {
				// 超过文件末尾时移到文件末尾
				view.toEnd = true;
				view.caret = EndPosition();
			} else {
				// 光标不放在换行符的中间（原版在排版位置上退 1 桁；这里收在行的长度以内）
				CLogicInt x = fiPrev.m_ptCursor.x;
				if (const CDocLine* pTmpDocLine = d.lines.GetLine(fiPrev.m_ptCursor.GetY2())) {
					if (pTmpDocLine->GetLengthWithoutEOL() < x) x = pTmpDocLine->GetLengthWithoutEOL();
				}
				view.caret = Position{ static_cast<std::int32_t>(fiPrev.m_ptCursor.y), static_cast<std::int32_t>(x) };
				view.viewTopLine = std::max<std::int32_t>(0, static_cast<std::int32_t>(fiPrev.m_nViewTopLine));
			}
			d.restoredView = view;
			caret = view.caret;
			viewTopLine = view.viewTopLine;
		}
		AddToRecent(caret, viewTopLine);
	}
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
	d.loadedEncoding = eCharCode;
	d.loadedBom = bBom;
	if (bTypeChanged && !d.typeLocked) {	// 一時適用中はそのまま（原版 SetDocumentType(…, false) は lock 中は何もしない。第 40 步）
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

// 保存前的检查（与原版 CCodeChecker::OnCheckSave 相同，第 30 步）。注释是原版的

namespace {

//! CDocLineMgrが保持するデータに異なる改行コードが混在しているかどうか判定する（原版 CCodeChecker.cpp 的 _CheckSavingEolcode）
bool CheckSavingEolcode(const CDocLineMgr& pcDocLineMgr, CEol cEolType)
{
	bool bMix = false;
	if( cEolType.IsNone() ){	//改行コード変換なし
		CEol cEolCheck;	//比較対象EOL
		const CDocLine* pcDocLine = pcDocLineMgr.GetDocLineTop();
		if( pcDocLine ){
			cEolCheck = pcDocLine->GetEol();
		}
		while( pcDocLine ){
			CEol cEol = pcDocLine->GetEol();
			if( cEol != cEolCheck && cEol.IsValid() ){
				bMix = true;
				break;
			}
			pcDocLine = pcDocLine->GetNextLine();
		}
	}
	return bMix;
}

//! CDocLineMgrが保持するデータを指定文字コードで安全に保存できるかどうか判定する（原版 CCodeChecker.cpp 的 _CheckSavingCharcode）
EConvertResult CheckSavingCharcode(const CDocLineMgr& pcDocLineMgr, ECodeType eCodeType, CLogicPoint& point, CNativeW& wc)
{
	const CDocLine*	pcDocLine = pcDocLineMgr.GetDocLineTop();
	const bool bCodePageMode = IsValidCodeOrCPType(eCodeType) && !IsValidCodeType(eCodeType);
	std::unique_ptr<CCodeBase> pCodeBase(CCodeFactory::CreateCodeBase(eCodeType,0));
	CMemory cmemTmp;	// バッファを再利用
	CNativeW cmemTmp2;
	CLogicInt nLine = CLogicInt(0);
	while( pcDocLine ){
		// コード変換 pcDocLine -> cmemTmp
		EConvertResult e = CIoBridge::ImplToFile(
			pcDocLine->_GetDocLineDataWithEOL(),
			&cmemTmp,
			pCodeBase.get()
		);
		if( bCodePageMode ){
			// コードページはRESULT_LOSESOMEを返さないので、自分で文字列比較する
			CIoBridge::FileToImpl(
				cmemTmp,
				&cmemTmp2,
				pCodeBase.get(),
				0
			);
			const int nDocLineLen = (Int)pcDocLine->GetLengthWithEOL();
			const int nConvertLen = (Int)cmemTmp2.GetStringLength();
			const int nDataMinLen = t_min(nDocLineLen, nConvertLen);
			const WCHAR* p = pcDocLine->GetPtr();
			const WCHAR* r = cmemTmp2.GetStringPtr();
			int nPos = -1;
			for( int i = 0; i < nDataMinLen; i++ ){
				if( p[i] != r[i] ){
					nPos = i;
					break;
				}
			}
			if( nPos == -1 && nDocLineLen != nConvertLen ){
				nPos = nDataMinLen;
			}
			if( nPos != -1 ){
				point.y = nLine;
				point.x = CLogicInt(nPos);
				// 変換できなかった位置の1文字取得
				wc.SetString( p + nPos, (Int)CNativeW::GetSizeOfChar( p, nDocLineLen, nPos ) );
				return RESULT_LOSESOME;
			}
		}
		if(e!=RESULT_COMPLETE){
			if( e == RESULT_LOSESOME ){
				// 行内の位置を特定
				point.y = nLine;
				point.x = CLogicInt(-1);
				const WCHAR* pLine = pcDocLine->GetPtr();
				const CLogicInt nLineLen = pcDocLine->GetLengthWithEOL();
				CLogicInt chars = CNativeW::GetSizeOfChar( pLine, nLineLen, 0 );
				CLogicInt nPos = CLogicInt(0);
				CNativeW mem;
				while( 0 < chars ){
					mem.SetStringHoldBuffer( pLine + nPos, chars );
					EConvertResult e2 = CIoBridge::ImplToFile(
						mem,
						&cmemTmp,
						pCodeBase.get()
					);
					if( e2 == RESULT_LOSESOME ){
						point.x = nPos;
						wc = mem;
						break;
					}
					nPos += chars;
					chars = CNativeW::GetSizeOfChar( pLine, nLineLen, nPos );
				}
			}
			return e;
		}

		//次の行へ
		pcDocLine = pcDocLine->GetNextLine();
		nLine++;
	}
	return RESULT_COMPLETE;
}

} // namespace

SaveCheck Document::CheckSave(const SaveOptions& options) const
{
	const auto& d = *m_impl;
	SaveCheck result;
	const ECodeType eCharCode = static_cast<ECodeType>(options.encoding.value_or(d.info.encoding));

	//改行コードが混在しているかどうか判定
	if (d.typeConfig.m_bChkEnterAtEnd) {
		result.eolMixed = CheckSavingEolcode(d.lines, CEol(static_cast<EEolType>(options.eol)));
	}

	//指定文字コードで安全に保存できるかどうか判定
	if (!IsValidCodeOrCPType(eCharCode)) return result;
	CLogicPoint point;
	CNativeW cmemChar(LTEXT(""), 0);
	if (CheckSavingCharcode(d.lines, eCharCode, point, cmemChar) == RESULT_LOSESOME) {
		result.lostSome = true;
		result.lostAt = { point.y, point.x };
		if (point.x != -1) {
			result.lostChar = Text(cmemChar.GetStringPtr(), cmemChar.GetStringLength());
			WCHAR szCharCode[32] = {};	// U+12ab or 1234abcd（原版是 12，异体字选择符的格式 "1234, U+E0100" 放不下，这里放大）
			CUnicode().UnicodeToHex(cmemChar.GetStringPtr(), cmemChar.GetStringLength(),
				szCharCode, &GetDllShareData().m_Common.m_sStatusbar);
			result.lostCharCode = Text(szCharCode);
		}
	}
	return result;
}

std::optional<RestoredView> Document::GetRestoredView() const { return m_impl->restoredView; }

void Document::AddToRecent(const Position& caret, std::int32_t viewTopLine)
{
	// 原版 CMruListener::_HoldBookmarks_And_AddToMRU（内容是 CEditDoc::GetEditInfo）。书签（ブックマーク）还没有移植
	const auto& d = *m_impl;
	if (d.info.path.empty() || d.info.path.size() >= _MAX_PATH) return;
	EditInfo fi;
	fi.m_szPath = d.info.path.c_str();
	fi.m_nViewTopLine = CLayoutInt(viewTopLine);
	fi.m_nViewLeftCol = CLayoutInt(0);
	fi.m_ptCursor.Set(CLogicInt(caret.column), CLogicInt(caret.line));
	fi.m_bIsModified = d.modified;
	fi.m_nCharCode = static_cast<ECodeType>(d.info.encoding);
	fi.m_bBom = d.info.bom;
	fi.m_nTypeId = d.typeConfig.m_id;
	CMRUFile().Add(&fi);
}

const FileInfo& Document::GetFileInfo() const { return m_impl->info; }
bool Document::IsModified() const { return m_impl->modified; }

void Document::SetEncoding(Encoding encoding, bool bom)
{
	// Command_CHG_CHARSET：SetCodeSetChg( eCharSet, CCodeTypeName( eCharSet ).UseBom() & bBom )
	const auto eCharSet = static_cast<ECodeType>(encoding);
	if (!IsValidCodeOrCPType(eCharSet)) return;
	m_impl->info.encoding = encoding;
	m_impl->info.bom = CCodeTypeName(eCharSet).UseBom() && bom;
}

bool Document::IsEncodingChanged() const
{
	// CDocFile::IsChgCodeSet：新規ファイルでなく、文字コードセットか BOM が読み込み時と違う
	const auto& d = *m_impl;
	return !d.info.path.empty() && (d.info.encoding != d.loadedEncoding || d.info.bom != d.loadedBom);
}

// ----- 内容 -----

std::int32_t Document::LineCount() const { return m_impl->lines.GetLineCount(); }

Text Document::GetLine(std::int32_t line, bool withEol) const
{
	if (line < 0) return {};
	const CDocLine* p = m_impl->lines.GetLine(CLogicInt(line));
	if (!p) return {};
	return Text(p->GetPtr(), withEol ? p->GetLengthWithEOL() : p->GetLengthWithoutEOL());
}

std::uint64_t Document::ChangeCount() const
{
	return m_impl->changeCount;
}

std::int32_t Document::LineLength(std::int32_t line) const
{
	if (line < 0) return 0;
	const CDocLine* p = m_impl->lines.GetLine(CLogicInt(line));
	return p ? static_cast<std::int32_t>(p->GetLengthWithoutEOL()) : 0;
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

std::int64_t Document::TextLength() const
{
	std::int64_t length = 0;
	for (const CDocLine* p = m_impl->lines.GetDocLineTop(); p; p = p->GetNextLine()) {
		length += p->GetLengthWithEOL();
	}
	return length;
}

std::int64_t Document::OffsetOf(const Position& position) const
{
	std::int64_t offset = 0;
	int line = 0;
	for (const CDocLine* p = m_impl->lines.GetDocLineTop(); p; p = p->GetNextLine(), ++line) {
		if (line == position.line) {
			return offset + std::clamp<std::int64_t>(position.column, 0, p->GetLengthWithoutEOL());
		}
		offset += p->GetLengthWithEOL();
	}
	return offset;	// 超过最后一行：文档末尾
}

Position Document::PositionAtOffset(std::int64_t offset) const
{
	std::int64_t rest = std::max<std::int64_t>(0, offset);
	int line = 0;
	for (const CDocLine* p = m_impl->lines.GetDocLineTop(); p; p = p->GetNextLine(), ++line) {
		const int body = p->GetLengthWithoutEOL();
		if (rest <= body) return Position{ line, static_cast<std::int32_t>(rest) };
		const int whole = p->GetLengthWithEOL();
		if (rest < whole) return Position{ line, body };
		rest -= whole;
	}
	return EndPosition();
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
	// 第 32 步：Command_REPLACE_ALL の移植（下の ReplaceAll）で、ファイル全体・選択文字の置換をする
	auto& d = *m_impl;
	d.lastSearchError.clear();
	if (pattern.empty()) {
		d.lastSearchError = u"empty pattern";
		return -1;
	}
	ReplaceOptions o;
	o.search = options;
	const ReplaceResult r = ReplaceAll(pattern, replacement, o, SearchView{});
	if (r.status == SearchStatus::InvalidPattern) {
		d.lastSearchError = r.error;
		return -1;
	}
	return r.count;
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
	case F_CHGMOD_INS:
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
	case F_CHGMOD_INS:
		return true;
	default:
		return false;
	}
}

bool Document::IsCommandChecked(FunctionCode code) const
{
	// 原版 IsFuncChecked（func/Funccode.cpp）
	const EEolType eol = m_impl->newLineEol.GetType();
	const ECodeType eDocCode = static_cast<ECodeType>(m_impl->info.encoding);
	switch (code) {
	case F_FILE_REOPEN_SJIS:		return CODE_SJIS == eDocCode;
	case F_FILE_REOPEN_JIS:			return CODE_JIS == eDocCode;
	case F_FILE_REOPEN_EUC:			return CODE_EUC == eDocCode;
	case F_FILE_REOPEN_LATIN1:		return CODE_LATIN1 == eDocCode;
	case F_FILE_REOPEN_UNICODE:		return CODE_UNICODE == eDocCode;
	case F_FILE_REOPEN_UNICODEBE:	return CODE_UNICODEBE == eDocCode;
	case F_FILE_REOPEN_UTF8:		return CODE_UTF8 == eDocCode;
	case F_FILE_REOPEN_CESU8:		return CODE_CESU8 == eDocCode;
	case F_FILE_REOPEN_UTF7:		return CODE_UTF7 == eDocCode;
	case F_CHGMOD_EOL_CRLF: return eol == EEolType::cr_and_lf;
	case F_CHGMOD_EOL_LF:   return eol == EEolType::line_feed;
	case F_CHGMOD_EOL_CR:   return eol == EEolType::carriage_return;
	// NEL、PS、LS 在原版也不打勾
	case F_CHGMOD_INS:      return m_impl->insertMode;
	default:                return false;
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
	case F_CHGMOD_INS:      SetInsertMode(!IsInsertMode()); return Result::Ok;	// Command_CHGMOD_INS
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

bool Document::ApplyTypeListChange()
{
	auto& d = *m_impl;
	const CTypeConfig type = CDocTypeManager().GetDocumentTypeOfId(d.typeConfig.m_id);
	if (type.IsValidType()) {
		// 原版 CDocType::SetDocumentTypeIdx：番号と名前だけ
		d.info.typeIndex = type.GetIndex();
		d.typeConfig.m_nIdx = type.GetIndex();
		if (const STypeConfigMini* mini = d.TypeMini()) d.info.typeName = Text(mini->m_szTypeName.c_str());
		return false;
	}
	// 削除された：ファイル名で決め直す（原版 PM_CHANGESETTING_ALL → OnChangeSetting）
	d.typeLocked = false;
	d.ResetForType(d.info.path);
	d.ResetWrap();
	d.DoLayout();
	return true;
}

bool Document::ChangeTypeTemporarily(std::int32_t typeIndex)
{
	// 原版 Command_CHANGETYPE：SetDocumentTypeIdx(id, true) → LockDocumentType → OnChangeType
	auto& d = *m_impl;
	const STypeConfigMini* mini = nullptr;
	if (!CDocTypeManager().GetTypeConfigMini(CTypeConfig(typeIndex), &mini)) return false;
	d.ResetForType(d.info.path, mini->m_id);
	d.typeLocked = true;
	d.ResetWrap();
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

bool Document::ApplyTypeSettingChange(std::int32_t typeIndex)
{
	// 原版 CEditWnd::OnChangeSetting（PM_CHANGESETTING_TYPE）：这个文档的类型，或按文件名决定的类型是改了的类型时
	auto& d = *m_impl;
	const Text& path = d.info.path;
	const int nTypeByPath = path.empty() ? 0 : CDocTypeManager().GetDocumentTypeOfPath(path.c_str()).GetIndex();
	if (d.info.typeIndex != typeIndex && nTypeByPath != typeIndex) return false;

	// 以下与 CEditDoc::OnChangeSetting 相同
	const STypeConfig old = d.typeConfig;
	// 折り返し方法的临时设置（原版 m_bTextWrapMethodCurTemp）：现在的与原来的类型别设置不同
	const bool bWrapTemp = d.wrapMethodCur != old.m_nTextWrapMethod
		|| (d.wrapMethodCur == WRAP_SETTING_WIDTH && d.wrapColumnsCur != old.m_nMaxLineKetas);
	// 文書種別：按文件名重新决定（CDocTypeManager::GetDocumentTypeOfPath）。一時適用中はそのタイプのまま（原版 SetDocumentType の lock）
	if (d.typeLocked && CDocTypeManager().GetDocumentTypeOfId(old.m_id).IsValidType()) {
		d.ResetForType(path, old.m_id);
	} else {
		d.typeLocked = false;
		d.ResetForType(path);
	}
	const STypeConfig& ref = d.typeConfig;
	bool bTemp = bWrapTemp && old.m_id == ref.m_id;	// 类型变了时解除临时设置
	// 折り返し方法的临时设置与类型别设置一致时解除（指定桁で折り返す 的桁数不同时保留）
	if (bTemp && d.wrapMethodCur == ref.m_nTextWrapMethod
		&& !(d.wrapMethodCur == WRAP_SETTING_WIDTH && d.wrapColumnsCur != ref.m_nMaxLineKetas)) {
		bTemp = false;
	}
	if (!bTemp) {
		d.wrapMethodCur = ref.m_nTextWrapMethod;
		// 指定桁で折り返す：类型别设置的桁数。右端で折り返す：暂时用现在的桁数（界面层按窗口宽度再设）
		if (d.wrapMethodCur == WRAP_SETTING_WIDTH) d.wrapColumnsCur = ref.m_nMaxLineKetas;
	}
	d.DoLayout();
	return true;
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
static_assert(static_cast<int>(ColorIndex::Search) == COLORIDX_SEARCH && static_cast<int>(ColorIndex::Search5) == COLORIDX_SEARCH5);

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
	e.boxSelectLock = sEdit.m_bBoxSelectLock;
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

// ---------------------------------------------------------------------------
// 查找、替换、跳转（第 32 步）
// ---------------------------------------------------------------------------

namespace sakura::core {

SearchSettings GetSearchSettings()
{
	const auto& sShare = GetDllShareData();
	const auto& s = sShare.m_Common.m_sSearch;
	SearchSettings r;
	r.options.regularExpression = s.m_sSearchOption.bRegularExp;
	r.options.matchCase = s.m_sSearchOption.bLoHiCase;
	r.options.wholeWord = s.m_sSearchOption.bWordOnly;
	r.notifyNotFound = s.m_bNOTIFYNOTFOUND != FALSE;
	r.autoCloseFind = s.m_bAutoCloseDlgFind != FALSE;
	r.autoCloseReplace = s.m_bAutoCloseDlgReplace != FALSE;
	r.searchAll = s.m_bSearchAll != FALSE;
	r.consecutiveAll = s.m_bConsecutiveAll != FALSE;
	r.selectedArea = s.m_bSelectedArea != FALSE;
	r.caretTextForSearch = s.m_bCaretTextForSearch != FALSE;
	r.inheritKeyOtherView = s.m_bInheritKeyOtherView;
	r.jumpLineNumIsCRLF = sShare.m_bLineNumIsCRLF_ForJump;
	return r;
}

void SetSearchSettings(const SearchSettings& r)
{
	auto& sShare = GetDllShareData();
	auto& s = sShare.m_Common.m_sSearch;
	s.m_sSearchOption = SSearchOption(r.options.regularExpression, r.options.matchCase, r.options.wholeWord);
	s.m_bNOTIFYNOTFOUND = r.notifyNotFound;
	s.m_bAutoCloseDlgFind = r.autoCloseFind;
	s.m_bAutoCloseDlgReplace = r.autoCloseReplace;
	s.m_bSearchAll = r.searchAll;
	s.m_bConsecutiveAll = r.consecutiveAll;
	s.m_bSelectedArea = r.selectedArea;
	s.m_bCaretTextForSearch = r.caretTextForSearch;
	s.m_bInheritKeyOtherView = r.inheritKeyOtherView;
	sShare.m_bLineNumIsCRLF_ForJump = r.jumpLineNumIsCRLF;
}

namespace {

template <class TRecent>
std::vector<Text> RecentTexts()
{
	TRecent recent;
	std::vector<Text> result;
	for (int i = 0; i < recent.GetItemCount(); i++) {
		if (const WCHAR* p = recent.GetItemText(i)) result.emplace_back(p);
	}
	return result;
}

} // namespace

std::vector<Text> SearchKeyHistory() { return RecentTexts<CRecentSearch>(); }
std::vector<Text> ReplaceKeyHistory() { return RecentTexts<CRecentReplace>(); }

void AddSearchKey(const Text& key)
{
	// CDlgFind::GetData：_MAX_PATH 以上の長さは履歴に入れない
	if (key.size() < _MAX_PATH) CSearchKeywordManager().AddToSearchKeyArr(key.c_str());
}

void AddReplaceKey(const Text& key)
{
	if (key.size() < _MAX_PATH) CSearchKeywordManager().AddToReplaceKeyArr(key.c_str());
}

std::int32_t SearchKeySequence() { return GetDllShareData().m_Common.m_sSearch.m_nSearchKeySequence; }
std::int32_t ReplaceKeySequence() { return GetDllShareData().m_Common.m_sSearch.m_nReplaceKeySequence; }

std::optional<Text> RegexpSyntaxError(const Text& pattern, bool matchCase)
{
	// CheckRegexpSyntax（メッセージは界面层が「正規表現の構文に誤りがあります。」と一緒に出す）
	CBregexp cRegexp;
	if (!InitRegexp(nullptr, cRegexp, false)) {
		return Text(u"regular expression library is not available");
	}
	const int nOption = matchCase ? CBregexp::optCaseSensitive : CBregexp::optNothing;
	if (!cRegexp.Compile(pattern.c_str(), nullptr, nOption, false)) {
		return Text(cRegexp.GetLastMessage());
	}
	return std::nullopt;
}

Text RegexpVersion()
{
	CBregexp cRegexp;
	if (!InitRegexp(nullptr, cRegexp, false)) return Text();
	const WCHAR* p = cRegexp.GetVersionW();
	return p ? Text(p) : Text();
}

//! 查找文字标记用的条件（每次绘制一行都要用，编译好留着）
struct SearchMarkCache {
	Text key;
	SearchOptions options;
	std::unique_ptr<PreparedPattern> prepared;
};

namespace {

//! 指向换行符中间或之后的位置改成下一行的开头（与 Document::Impl::NormalizePosition 相同）
Position NormalizeLogic(const CDocLineMgr& lines, const CLogicPoint& pt)
{
	const CDocLine* pLine = lines.GetLine(pt.GetY2());
	if (pLine && pt.GetX2() > pLine->GetLengthWithoutEOL()) {
		return Position{ pt.GetY2() + 1, 0 };
	}
	return FromLogic(pt);
}

//! 一个字的长度（原版 CNativeW::GetSizeOfChar：补充平面的字是 2，其余是 1）
int CharSizeAt(const WCHAR* pLine, int nLen, int nIdx)
{
	return CNativeW::GetSizeOfChar(pLine, nLen, nIdx) == 2 ? 2 : 1;
}

} // namespace

/*!
	Command_SEARCH_NEXT（選択状態のロックなし）を論理位置で行う。
	@param bReplaceAll すべて置換の途中（先頭からの再検索はしない）
	@param pMatch [out] 見つかった範囲（論理位置そのまま。NormalizePosition の前）
*/
static SearchStatus SearchNextLogic(CDocLineMgr& lines, const CSearchStringPattern& pattern, const SearchView& view,
									bool searchAll, bool bReplaceAll, CLogicRange* pMatch)
{
	// 検索開始位置を調整：選択があれば選択の終わりから。長さ０の選択（長さ０の一致）は１文字進める
	bool b0Match = false;
	CLogicPoint ptStart = ToLogic(view.caret);
	if (view.selection) {
		ptStart = ToLogic(view.selection->to);
		b0Match = view.selection->IsEmpty();
	}
	CLogicInt nLineNum = ptStart.GetY2();
	CLogicInt nIdx = ptStart.GetX2();
	if (b0Match) {
		const CDocLine* pDocLine = lines.GetLine(nLineNum);
		const int nLineLen = pDocLine ? pDocLine->GetLengthWithEOL() : 0;
		if (pDocLine && nIdx < nLineLen) {
			nIdx += CLogicInt(CharSizeAt(pDocLine->GetPtr(), nLineLen, nIdx));
		} else {
			++nIdx;	// 念のため行末は別処理
		}
	}
	const CLogicInt nLineNumOld = nLineNum;
	const CLogicInt nIdxOld = nIdx;

	CSearchAgent agent(&lines);
	if (agent.SearchWord(CLogicPoint(nIdx, nLineNum), SEARCH_FORWARD, pMatch, pattern)) {
		return SearchStatus::Found;
	}
	// 先頭から再検索（すべて置換の実行中は行わない）
	if (searchAll && !bReplaceAll) {
		if (agent.SearchWord(CLogicPoint(0, 0), SEARCH_FORWARD, pMatch, pattern)) {
			// 原版：(nLineNumOld > nLineNum) || (nLineNumOld == nLineNum && nIdxOld > nIdx) で「▼先頭から再検索しました」
			return (0 < nLineNumOld || 0 < nIdxOld) ? SearchStatus::Wrapped : SearchStatus::Found;
		}
	}
	return SearchStatus::NotFound;
}

//! 見つかった範囲を選択して、カーソルを先頭へ（原版 SetSelectArea、MoveCursor(sRangeA.GetFrom())）
static SearchView SelectMatch(const CDocLineMgr& lines, const CLogicRange& match)
{
	const Range range{ NormalizeLogic(lines, match.GetFrom()), NormalizeLogic(lines, match.GetTo()) };
	return SearchView{ range.from, range };
}

SearchResult Document::SearchNext(const Text& key, const SearchOptions& options, const SearchView& view, bool searchAll)
{
	auto& d = *m_impl;
	SearchResult r;
	// 選択を解除して、カーソルは選択の終わりへ（原版：見つからないときもこの位置）
	r.view = SearchView{ view.selection ? view.selection->to : view.caret, std::nullopt };
	if (key.empty()) return r;
	PreparedPattern prepared(key, options);
	if (!prepared.ok) {
		r.status = SearchStatus::InvalidPattern;
		r.error = prepared.error;
		return r;
	}
	CLogicRange match;
	r.status = SearchNextLogic(d.lines, prepared.pattern, view, searchAll, false, &match);
	if (r.status == SearchStatus::Found || r.status == SearchStatus::Wrapped) {
		r.view = SelectMatch(d.lines, match);
	}
	return r;
}

SearchResult Document::SearchPrev(const Text& key, const SearchOptions& options, const SearchView& view, bool searchAll)
{
	auto& d = *m_impl;
	SearchResult r;
	r.view = SearchView{ view.caret, std::nullopt };	// 選択を解除（カーソルはそのまま）
	if (key.empty()) return r;
	PreparedPattern prepared(key, options);
	if (!prepared.ok) {
		r.status = SearchStatus::InvalidPattern;
		r.error = prepared.error;
		return r;
	}

	CLogicInt nLineNum = CLogicInt(view.caret.line);
	CLogicInt nIdx = CLogicInt(view.caret.column);
	bool bStart = true;
	if (d.lines.GetLineCount() <= nLineNum) {
		// [EOF] から前検索：１行前の行末（行末の \0 にも一致させるため +1）から
		nLineNum = CLogicInt(d.lines.GetLineCount() - 1);
		const CDocLine* pDocLine = d.lines.GetLine(nLineNum);
		if (!pDocLine) {
			bStart = false;
		} else {
			nIdx = CLogicInt(pDocLine->GetLengthWithEOL() + 1);
		}
	}
	CSearchAgent agent(&d.lines);
	CLogicRange match;
	if (bStart && agent.SearchWord(CLogicPoint(nIdx, nLineNum), SEARCH_BACKWARD, &match, prepared.pattern)) {
		r.status = SearchStatus::Found;
	} else if (searchAll) {
		// 末尾から再検索（原版は最終レイアウト行の MAXLINEKETAS から）
		const CLogicInt nLast = CLogicInt(d.lines.GetLineCount() - 1);
		if (0 <= nLast && agent.SearchWord(CLogicPoint(CLogicInt(std::numeric_limits<int>::max() / 2), nLast),
										   SEARCH_BACKWARD, &match, prepared.pattern)) {
			r.status = bStart ? SearchStatus::Wrapped : SearchStatus::Found;
		}
	}
	if (r.status != SearchStatus::NotFound) {
		r.view = SelectMatch(d.lines, match);
	}
	return r;
}

namespace {

//! 正規表現の置換後文字列：選択始点挿入は「置換後$&」、選択終点追加は「$&置換後」（原版 Command_REPLACE）
Text RegexReplacementFor(const Text& replacement, ReplaceTarget target)
{
	switch (target) {
	case ReplaceTarget::InsertBefore: return replacement + u"$&";
	case ReplaceTarget::InsertAfter:  return u"$&" + replacement;
	default:                          return replacement;
	}
}

//! 行削除の範囲：行頭から次の行の行頭まで（最終行に改行がなければ行末まで）
CLogicRange LineRange(const CDocLineMgr& lines, CLogicInt nLine)
{
	CLogicPoint ptTo(CLogicInt(0), nLine + 1);
	if (lines.GetLineCount() <= nLine + 1) {
		const CDocLine* pDocLine = lines.GetLine(nLine);
		if (pDocLine && pDocLine->GetEol().IsNone()) {
			ptTo = CLogicPoint(pDocLine->GetLengthWithEOL(), nLine);
		}
	}
	return CLogicRange(CLogicPoint(CLogicInt(0), nLine), ptTo);
}

} // namespace

ReplaceResult Document::ReplaceNext(const Text& key, const Text& replacement, const ReplaceOptions& options, const SearchView& view)
{
	auto& d = *m_impl;
	ReplaceResult r;
	// 選択があれば、その先頭にカーソルを移して選択を解除（原版 Command_LEFT）
	const SearchView start{ view.selection ? view.selection->from : view.caret, std::nullopt };
	r.view = start;
	if (key.empty()) return r;
	PreparedPattern prepared(key, options.search);
	if (!prepared.ok) {
		r.status = SearchStatus::InvalidPattern;
		r.error = prepared.error;
		return r;
	}
	const bool bRegularExp = options.search.regularExpression;
	const ReplaceTarget target = options.target;
	const bool bPaste = options.paste && target != ReplaceTarget::DeleteLine;	// 行削除のときは貼り付けない

	CBregexp cRegexp;
	if (bRegularExp && !bPaste && target != ReplaceTarget::DeleteLine) {
		if (!InitRegexp(nullptr, cRegexp, false)) {
			r.status = SearchStatus::InvalidPattern;
			r.error = u"regular expression library is not available";
			return r;
		}
	}

	/* 次を検索 */
	CLogicRange match;
	r.status = SearchNextLogic(d.lines, prepared.pattern, start, options.searchAll, false, &match);
	if (r.status == SearchStatus::NotFound) return r;
	r.view = SelectMatch(d.lines, match);

	BeginEdit();
	CLogicRange sel = match;						// 置換する範囲（選択範囲）
	CLogicPoint ptCaret = match.GetFrom();
	CLogicPoint ptTmp(CLogicInt(0), CLogicInt(0));	// 選択始点挿入のときの、挿入後に進める量
	if (bPaste || !bRegularExp) {
		if (target == ReplaceTarget::InsertBefore) {
			ptTmp = CLogicPoint(sel.GetTo().GetX2() - sel.GetFrom().GetX2(), sel.GetTo().GetY2() - sel.GetFrom().GetY2());
			sel.SetTo(sel.GetFrom());
		} else if (target == ReplaceTarget::InsertAfter) {
			ptCaret = sel.GetTo();
			sel.SetFrom(sel.GetTo());
		}
	}
	if (target == ReplaceTarget::DeleteLine) {
		sel = LineRange(d.lines, match.GetFrom().GetY2());
	}

	bool bReplaced = true;
	CLogicPoint ptNew = ptCaret;
	if (bPaste) {
		const Text text = GetEditSettings().convertEolOnPaste ? ConvertEolToNewLine(replacement) : replacement;
		ptNew = d.ReplaceWithUndo(sel, text.data(), static_cast<int>(text.size()));
	} else if (target == ReplaceTarget::DeleteLine) {
		ptNew = d.ReplaceWithUndo(sel, nullptr, 0);
	} else if (bRegularExp) {
		// 物理行、物理行長、物理行での検索マッチ位置
		const CLogicInt nLine = sel.GetFrom().GetY2();
		const CDocLine* pcDocLine = d.lines.GetLine(nLine);
		const WCHAR* pLine = pcDocLine->GetPtr();
		const CLogicInt nIdx = sel.GetFrom().GetX2();
		const CLogicInt nLen = pcDocLine->GetLengthWithEOL();
		const Text rep2 = RegexReplacementFor(replacement, target);
		const int nFlag = options.search.matchCase ? CBregexp::optCaseSensitive : CBregexp::optNothing;
		cRegexp.Compile(key.c_str(), rep2.c_str(), nFlag);
		if (cRegexp.Replace(pLine, nLen, nIdx)) {
			const CLogicInt matchLen = cRegexp.GetMatchLen();
			CLogicInt nIdxTo = nIdx + matchLen;		// 検索文字列の末尾
			if (matchLen == 0) {
				// ０文字マッチの時(無限置換にならないように１文字進める)
				if (nIdxTo < nLen) {
					nIdxTo += CLogicInt(CharSizeAt(pLine, nLen, nIdxTo));
				}
				sel.SetTo(CLogicPoint(nIdxTo, nLine));
			}
			// 行末から検索文字列末尾までの文字数
			CLogicInt colDiff = nLen - nIdxTo;
			// \rを置換するとその後ろの\nが消えてしまう問題の対応：改行にかかっていたら、行全体を置換する
			if (colDiff < pcDocLine->GetEol().GetLen()) {
				colDiff = CLogicInt(0);
				sel.SetTo(CLogicPoint(nLen, nLine));
			}
			const Text replaced(cRegexp.GetString(), cRegexp.GetStringLen() - colDiff);
			ptNew = d.ReplaceWithUndo(sel, replaced.data(), static_cast<int>(replaced.size()));
		} else {
			bReplaced = false;
		}
	} else {
		ptNew = d.ReplaceWithUndo(sel, replacement.data(), static_cast<int>(replacement.size()));
	}
	if (bReplaced) r.count = 1;

	// 挿入後の検索開始位置を調整
	if (target == ReplaceTarget::InsertBefore) {
		ptNew = CLogicPoint(ptNew.GetX2() + ptTmp.GetX2(), ptNew.GetY2() + ptTmp.GetY2());
	}
	const SearchView after{ bReplaced ? d.NormalizePosition(ptNew) : FromLogic(ptCaret), std::nullopt };
	EndEdit();

	/* 次を検索 */
	r.view = after;
	r.next = SearchNextLogic(d.lines, prepared.pattern, after, options.searchAll, false, &match);
	if (r.next != SearchStatus::NotFound) {
		r.view = SelectMatch(d.lines, match);
	}
	return r;
}

ReplaceResult Document::ReplaceAll(const Text& key, const Text& replacement, const ReplaceOptions& options, const SearchView& view)
{
	auto& d = *m_impl;
	ReplaceResult r;
	r.view = view;
	if (key.empty()) return r;
	PreparedPattern prepared(key, options.search);
	if (!prepared.ok) {
		r.status = SearchStatus::InvalidPattern;
		r.error = prepared.error;
		return r;
	}
	const bool bRegularExp = options.search.regularExpression;
	const ReplaceTarget target = options.target;
	const bool bPaste = options.paste && target != ReplaceTarget::DeleteLine;
	const bool bConsecutiveAll = options.consecutiveAll;
	const bool bSelectedArea = options.selectedArea && view.selection && !view.selection->IsEmpty();

	// 置換後文字列（原版：「改行コードを変換して貼り付ける」のときは、貼り付けでなくても変換する）
	Text repKey = replacement;
	if (GetEditSettings().convertEolOnPaste) repKey = ConvertEolToNewLine(repKey);

	CBregexp cRegexp;
	if (bRegularExp && !bPaste) {
		if (!InitRegexp(nullptr, cRegexp, false)) {
			r.status = SearchStatus::InvalidPattern;
			r.error = u"regular expression library is not available";
			return r;
		}
		int nFlag = options.search.matchCase ? CBregexp::optCaseSensitive : CBregexp::optNothing;
		nFlag |= bConsecutiveAll ? CBregexp::optNothing : CBregexp::optGlobal;
		const Text rep2 = RegexReplacementFor(repKey, target);
		if (!cRegexp.Compile(key.c_str(), rep2.c_str(), nFlag)) {
			r.status = SearchStatus::InvalidPattern;
			r.error = Text(cRegexp.GetLastMessage());
			return r;
		}
	}
	r.status = SearchStatus::Found;

	// 範囲：選択範囲置換は選択の始点から、ファイル全体置換はファイルの先頭から
	CLogicPoint ptColLineP;	// 選択範囲の終点
	Position ptStart{ 0, 0 };
	if (bSelectedArea) {
		ptColLineP = ToLogic(view.selection->to);
		ptStart = view.selection->from;
	}
	CLogicPoint ptLastLogic = ToLogic(ptStart);

	BeginEdit();
	CLogicRange cSelectLogic;
	SearchView cur{ ptStart, std::nullopt };
	bool bFound = SearchNextLogic(d.lines, prepared.pattern, cur, false, true, &cSelectLogic) != SearchStatus::NotFound;

	int lineCnt = 0;				// 置換前の行数
	int linDif = 0;					// 置換後の行調整
	int colDif = 0;					// 置換後の桁調整
	int linOldLen = 0;				// 検査後の行の長さ
	CLogicPoint ptOld(CLogicInt(0), CLogicInt(-1));
	std::optional<CLogicPoint> ptPrevEnd;	// 前回の置換の後ろ（長さ０の一致の無限置換を止めるため）
	while (bFound) {
		const CLogicRange found = cSelectLogic;
		// 文書の末尾で長さ０の一致を置換した直後に、また同じ位置で一致したら止める（原版は止まらない）
		if (found.GetFrom() == found.GetTo() && ptPrevEnd && *ptPrevEnd == found.GetFrom()
			&& d.NormalizePosition(found.GetFrom()) == EndPosition()) {
			break;
		}

		/* 検索後の位置を確認 */
		if (bSelectedArea) {
			lineCnt = d.lines.GetLineCount();
			ptOld = cSelectLogic.GetTo();
			// 置換前の行の長さ(改行は１文字と数える)
			linOldLen = d.lines.GetLine(ptOld.GetY2())->GetLengthWithoutEOL() + 1;
			// 行は範囲内？ 選択終点が行頭なら、その行は範囲に含まない
			if ((ptColLineP.y + linDif == ptOld.y && (ptColLineP.x + colDif < ptOld.x || ptColLineP.x == 0))
				|| ptColLineP.y + linDif < ptOld.y) {
				break;
			}
		}

		CLogicPoint ptCaret = cSelectLogic.GetFrom();	// MoveCursorFastMode(pcSelectLogic->GetFrom())
		CLogicPoint ptTmpLogic(CLogicInt(0), CLogicInt(0));
		if (bPaste || !bRegularExp) {
			if (target == ReplaceTarget::InsertBefore) {
				ptTmpLogic = CLogicPoint(cSelectLogic.GetTo().x - cSelectLogic.GetFrom().x, cSelectLogic.GetTo().y - cSelectLogic.GetFrom().y);
				cSelectLogic.SetTo(cSelectLogic.GetFrom());
			} else if (target == ReplaceTarget::InsertAfter) {
				ptCaret = cSelectLogic.GetTo();
				cSelectLogic.SetFrom(cSelectLogic.GetTo());
			}
		}
		// 行削除 選択範囲を行全体に拡大。カーソル位置を行頭へ
		if (target == ReplaceTarget::DeleteLine) {
			cSelectLogic = LineRange(d.lines, cSelectLogic.GetFrom().GetY2());
			ptCaret = cSelectLogic.GetFrom();
		}

		bool bReplaced = true;
		bool bWholeLine = false;	// 一括置換で行の残りを全部置換した
		CLogicPoint ptNew = ptCaret;
		if (bPaste || target == ReplaceTarget::DeleteLine || !bRegularExp) {
			const Text& text = (target == ReplaceTarget::DeleteLine) ? Text() : repKey;
			ptNew = d.ReplaceWithUndo(cSelectLogic, text.data(), static_cast<int>(text.size()));
			++r.count;
		} else {
			// 物理行、物理行長、物理行での検索マッチ位置
			const CLogicInt nLogicLineNum = cSelectLogic.GetFrom().GetY2();
			const CDocLine* pcDocLine = d.lines.GetLine(nLogicLineNum);
			const WCHAR* pLine = pcDocLine->GetPtr();
			const CLogicInt nIdx = cSelectLogic.GetFrom().GetX2();
			CLogicInt nLen = pcDocLine->GetLengthWithEOL();
			if (!bConsecutiveAll && bSelectedArea) {
				// 選択範囲置換の場合は行内の選択範囲末尾まで置換範囲を縮める
				if (ptColLineP.y + linDif == ptOld.y) {
					if (nLen - pcDocLine->GetEol().GetLen() > ptColLineP.x + colDif) {
						nLen = ptColLineP.GetX2() + CLogicInt(colDif);
					}
				}
			}
			if (const int nReplace = cRegexp.Replace(pLine, nLen, nIdx)) {
				r.count += nReplace;
				CLogicInt exTail(0);	// 置換せずに残す部分の長さ
				if (!bConsecutiveAll) {
					// 行単位での置換処理：選択範囲を物理行末までのばす
					cSelectLogic.SetTo(CLogicPoint(nLen, nLogicLineNum));
					bWholeLine = true;
				} else {
					CLogicInt nIdxTo = nIdx + cRegexp.GetMatchLen();	// 検索文字列の末尾
					if (nIdx == nIdxTo && nIdxTo < nLen) {
						// ０文字マッチの時：無限置換にならないように１文字進める
						nIdxTo += CLogicInt(CharSizeAt(pLine, nLen, nIdxTo));
					}
					// \rを置換するとその後ろの\nが消えてしまう問題の対応：改行にかかっていたら、行全体を置換する
					if (nLen < nIdxTo + pcDocLine->GetEol().GetLen()) {
						nIdxTo = nLen;
					}
					exTail = nLen - nIdxTo;
					if (nIdxTo != nIdx + cRegexp.GetMatchLen()) {
						cSelectLogic.SetTo(CLogicPoint(nIdxTo, nLogicLineNum));
					}
				}
				ptOld.x = nLen - exTail;
				const Text replaced(cRegexp.GetString(), cRegexp.GetStringLen() - exTail);
				ptNew = d.ReplaceWithUndo(cSelectLogic, replaced.data(), static_cast<int>(replaced.size()));
			} else {
				bReplaced = false;
			}
		}

		// 挿入後の位置調整
		if (bReplaced) {
			if (target == ReplaceTarget::InsertBefore) {
				ptNew = CLogicPoint(ptNew.x + ptTmpLogic.x, ptNew.y + ptTmpLogic.y);
			}
			ptLastLogic = ptNew;
		} else {
			// 置換できなかった（原版は同じ位置を探し続ける）：一致の後ろから探す
			ptNew = found.GetTo();
			if (found.GetFrom() == found.GetTo()) ptNew.x += 1;
		}

		/* 置換後の位置を確認 */
		if (bSelectedArea && bReplaced) {
			const CLogicPoint ptTmp2 = ptNew;
			const int linDif_thistime = d.lines.GetLineCount() - lineCnt;	// 今回置換での行数変化
			linDif += linDif_thistime;
			if (ptColLineP.y + linDif == ptTmp2.y) {
				// 最終行で置換した時、又は、置換の結果、選択エリア最終行まで到達した時
				colDif += ptTmp2.GetX2() - ptOld.GetX2();
				// 行連結や改行の置換で、置換前後で行が異なってしまうときは行の長さで補正する
				if (linDif_thistime < 0 || ptTmp2.y != ptOld.y) {
					colDif += linOldLen;
				}
			}
		}

		/* 次を検索 */
		CLogicPoint ptNext = ptNew;
		if (bWholeLine && ptNext.x != 0) {
			// 行の残りを一括置換した：置換後の文字列が改行で終わらないとき（改行のない最終行）は次の行から
			ptNext = CLogicPoint(CLogicInt(0), ptNext.y + 1);
		}
		ptPrevEnd = ptNew;
		cur = SearchView{ FromLogic(ptNext), std::nullopt };
		bFound = d.lines.GetLine(ptNext.GetY2()) != nullptr
			&& SearchNextLogic(d.lines, prepared.pattern, cur, false, true, &cSelectLogic) != SearchStatus::NotFound;
	}
	EndEdit();

	/* カーソル・選択範囲復元 */
	if (!bSelectedArea) {
		// 最後に置換した文字列の右へ
		r.view = SearchView{ d.NormalizePosition(ptLastLogic), std::nullopt };
	} else {
		ptColLineP.x += colDif;
		if (ptColLineP.x < 0) ptColLineP.x = 0;
		ptColLineP.y += linDif;
		if (ptColLineP.y < 0) ptColLineP.y = 0;
		Position to = d.NormalizePosition(ptColLineP);
		if (EndPosition() < to) to = EndPosition();
		r.view.caret = to;
		r.view.selection = (view.selection->from < to) ? std::optional<Range>(Range{ view.selection->from, to }) : std::nullopt;
	}
	return r;
}

std::optional<Position> Document::JumpPosition(const JumpOptions& options) const
{
	const auto& d = *m_impl;
	if (d.layout.GetLineCount() == 0) return std::nullopt;	// ErrorBeep

	int nLineNum = options.lineNumber;
	if (!options.plsql) {
		if (nLineNum <= 0) nLineNum = 1;
		if (options.lineNumIsCRLF) {
			// 改行単位：その論理行の先頭
			if (d.lines.GetLineCount() <= nLineNum - 1) return EndPosition();
			return Position{ nLineNum - 1, 0 };
		}
		// 折り返し単位：そのレイアウト行の先頭
		if (nLineNum > d.layout.GetLineCount()) nLineNum = static_cast<int>(d.layout.GetLineCount());
		CLogicPoint pt;
		d.layout.LayoutToLogic(CLayoutPoint(CLayoutInt(0), CLayoutInt(nLineNum - 1)), &pt);
		return d.NormalizePosition(pt);
	}

	// PL/SQLコンパイルエラー行を処理する：ブロックの１行目から、有効な行（空行とコメントだけの行以外）を数える
	int nMode = 0;
	int nCurrentLine = 0;			// m_nPLSQL_E2 - 1（原版は常に 1）
	int nCommentBegin = 0;
	int nLineCount = options.plsqlBlockFirstLine - 1;
	if (!d.typeConfig.m_bLineNumIsCRLF) {
		// 行番号がレイアウト単位のとき：レイアウト位置→物理位置
		CLogicPoint ptPosXY;
		d.layout.LayoutToLogic(CLayoutPoint(CLayoutInt(0), CLayoutInt(nLineCount)), &ptPosXY);
		nLineCount = ptPosXY.y;
	}
	const bool bExtEol = ExtEolEnabled();
	for (; nLineCount < d.lines.GetLineCount(); ++nLineCount) {
		CLogicInt nLineLen;
		const WCHAR* pLine = d.lines.GetLine(CLogicInt(nLineCount))->GetDocLineStrWithEOL(&nLineLen);
		bool bValidLine = false;
		int i;
		for (i = 0; i < nLineLen; ++i) {
			if (L' ' != pLine[i] && WCODE::TAB != pLine[i]) break;
		}
		const int nBgn = i;
		for (i = nBgn; i < nLineLen; ++i) {
			if (20 == nMode) {			// シングルクォーテーション文字列読み込み中
				bValidLine = true;
				if (L'\'' == pLine[i] && !(i > 0 && L'\\' == pLine[i - 1])) {
					nMode = 0;
					continue;
				}
			} else if (21 == nMode) {	// ダブルクォーテーション文字列読み込み中
				bValidLine = true;
				if (L'"' == pLine[i] && !(i > 0 && L'\\' == pLine[i - 1])) {
					nMode = 0;
					continue;
				}
			} else if (8 == nMode) {	// コメント読み込み中
				if (i < nLineLen - 1 && L'*' == pLine[i] && L'/' == pLine[i + 1]) {
					if (nCommentBegin != 0) bValidLine = true;
					++i;
					nMode = 0;
					continue;
				}
			} else if (0 == nMode) {	// ノーマルモード
				if (L'\t' == pLine[i] || L' ' == pLine[i] || WCODE::IsLineDelimiter(pLine[i], bExtEol)) {
					continue;
				} else if (i < nLineLen - 1 && L'-' == pLine[i] && L'-' == pLine[i + 1]) {
					bValidLine = true;
					break;
				} else if (i < nLineLen - 1 && L'/' == pLine[i] && L'*' == pLine[i + 1]) {
					++i;
					nMode = 8;
					nCommentBegin = nLineCount;
					continue;
				} else if (L'\'' == pLine[i]) {
					nMode = 20;
					continue;
				} else if (L'"' == pLine[i]) {
					nMode = 21;
					continue;
				} else {
					bValidLine = true;
				}
			}
		}
		if (8 == nMode) {
			if (nCommentBegin != 0) bValidLine = true;
			// コメントブロック内の改行だけの行
			if (nBgn < nLineLen && WCODE::IsLineDelimiter(pLine[nBgn], bExtEol)) bValidLine = false;
		}
		if (bValidLine) {
			++nCurrentLine;
			if (nCurrentLine >= nLineNum) break;
		}
	}
	if (d.lines.GetLineCount() <= nLineCount) return EndPosition();
	return Position{ nLineCount, 0 };
}

namespace {

/*!
	単語単位で探すとき、一致した単語が検索語の何番目の単語か（原版 CEditView::IsSearchString。最初は 1）
*/
int WordIndexInKey(const Text& key, const WCHAR* pWord, int wordLength, bool bLoHiCase)
{
	const bool bExtEol = ExtEolEnabled();
	const auto fcmp = [bLoHiCase](const WCHAR* a, const WCHAR* b, size_t n) {
		return bLoHiCase ? wcsncmp(a, b, n) : _wcsnicmp(a, b, n);
	};
	int wordIndex = 0;
	const WCHAR* const searchKeyEnd = key.data() + key.size();
	for (const WCHAR* p = key.data(); p < searchKeyEnd;) {
		CLogicInt begin, end;
		if (CWordParse::WhereCurrentWord_2(p, CLogicInt(searchKeyEnd - p), CLogicInt(0), bExtEol, &begin, &end, nullptr, nullptr)
			&& begin == 0 && begin < end) {
			if (!WCODE::IsWordDelimiter(*p)) {
				++wordIndex;
				if (wordLength == end && 0 == fcmp(p, pWord, wordLength)) {
					return wordIndex;
				}
			}
			p += end;
		} else {
			p += CNativeW::GetSizeOfChar(p, searchKeyEnd - p, 0);
		}
	}
	return 1;
}

} // namespace

std::vector<SyntaxColorRun> Document::SyntaxColors(std::int32_t line)
{
	auto& d = *m_impl;
	std::vector<SyntaxColorRun> result;
	const CDocLine* pDocLine = d.lines.GetLine(CLogicInt(line));
	if (!pDocLine) return result;

	d.ActivateColors();
	CColorStrategyPool* pool = CColorStrategyPool::getInstance();
	// 色分けしない设置时全部是テキスト（CEditView::GetColorIndex 的 IsSkipBeforeLayout）
	if (pool->IsSkipBeforeLayout()) return result;

	// 逻辑行的第一个排版行：排版时记下的行首颜色（CEditView::GetColorIndex 的 pcLayoutLineFirst）
	CLayoutPoint ptLayout;
	d.layout.LogicToLayout(CLogicPoint(CLogicInt(0), CLogicInt(line)), &ptLayout);
	const CLayout* pcLayout = d.layout.SearchLineByLayoutY(ptLayout.GetY2());
	if (!pcLayout || pcLayout->GetDocLineRef() != pDocLine) return result;
	while (pcLayout->GetLogicOffset() != 0 && pcLayout->GetPrevLayout()) {
		pcLayout = pcLayout->GetPrevLayout();
	}

	const CStringRef cLineStr(pDocLine->GetPtr(), pDocLine->GetLengthWithEOL());
	const int nLenNoEol = pDocLine->GetLengthWithoutEOL();
	pool->NotifyOnStartScanLogic();
	CColorStrategy* pStrategy = pool->GetStrategyByColor(pcLayout->GetColorTypePrev());
	if (pStrategy) {
		pStrategy->InitStrategyStatus();
		pStrategy->SetStrategyColorInfo(pcLayout->GetColorInfo());
	}

	// SColorStrategyInfo::CheckChangeColor の「色終了」「色開始」と同じ順序で 1 文字ずつ調べる
	const int nStrategies = pool->GetStrategyCount();
	int nPos = 0;
	while (nPos < nLenNoEol) {
		if (pStrategy && pStrategy->EndColor(cLineStr, nPos)) {
			pStrategy = nullptr;
		}
		if (!pStrategy) {
			for (int i = 0; i < nStrategies; ++i) {
				if (pool->GetStrategy(i)->BeginColor(cLineStr, nPos)) {
					pStrategy = pool->GetStrategy(i);
					break;
				}
			}
		}
		const int nNext = nPos + std::max<int>(1, CNativeW::GetSizeOfChar(cLineStr.GetPtr(), cLineStr.GetLength(), nPos));
		const int nColor = ToColorInfoArrIndex(CColorStrategy::GetStrategyColorSafe(pStrategy));
		if (nColor != COLORIDX_TEXT) {
			const auto color = static_cast<std::uint8_t>(nColor);
			if (!result.empty() && result.back().to == nPos && result.back().color == color) {
				result.back().to = std::min(nNext, nLenNoEol);
			} else {
				result.push_back(SyntaxColorRun{ nPos, std::min(nNext, nLenNoEol), color });
			}
		}
		nPos = nNext;
	}
	return result;
}

std::vector<SearchMark> Document::SearchMarks(std::int32_t line, const Text& key, const SearchOptions& options)
{
	auto& d = *m_impl;
	std::vector<SearchMark> result;
	const CDocLine* pDocLine = d.lines.GetLine(CLogicInt(line));
	if (!pDocLine || key.empty()) return result;

	// チェックが付いている検索文字列色（CColor_Found::OnStartScanLogic）
	std::vector<std::uint8_t> colors;
	for (int color = COLORIDX_SEARCH; color <= COLORIDX_SEARCHTAIL; ++color) {
		if (d.typeConfig.m_ColorInfoArr[color].m_bDisp) colors.push_back(static_cast<std::uint8_t>(color));
	}
	if (colors.empty()) return result;

	auto& cache = d.searchMarkCache;
	if (!cache || cache->key != key || cache->options.regularExpression != options.regularExpression
		|| cache->options.matchCase != options.matchCase || cache->options.wholeWord != options.wholeWord) {
		cache = std::make_shared<SearchMarkCache>();
		cache->key = key;
		cache->options = options;
		cache->prepared = std::make_unique<PreparedPattern>(key, options);
	}
	if (!cache->prepared->ok) return result;

	const CLineMatchFinder finder(cache->prepared->pattern, cache->prepared->pattern.GetRegexp());
	const WCHAR* pLine = pDocLine->GetPtr();
	const int nLen = pDocLine->GetLengthWithEOL();
	const bool bWordOnly = options.wholeWord && !options.regularExpression;
	int nStart = 0;
	while (nStart < nLen) {
		const auto m = finder.Find(pLine, nLen, nStart);
		if (!m) break;
		if (0 < m->nLength) {
			const int n = bWordOnly ? WordIndexInKey(key, pLine + m->nIndex, m->nLength, options.matchCase) : 1;
			result.push_back(SearchMark{ m->nIndex, m->nIndex + m->nLength, colors[(n - 1) % colors.size()] });
		}
		nStart = CLineMatchFinder::GetNextStart(pLine, nLen, *m);
	}
	return result;
}

std::optional<Range> Document::WordRangeAt(const Position& position) const
{
	const auto& d = *m_impl;
	if (!d.IsValidPosition(position) || d.lines.GetLineCount() <= position.line) return std::nullopt;
	CLogicInt nFrom, nTo;
	if (!CSearchAgent(const_cast<CDocLineMgr*>(&d.lines)).WhereCurrentWord(
			CLogicInt(position.line), CLogicInt(position.column), &nFrom, &nTo, nullptr, nullptr)) {
		return std::nullopt;
	}
	return Range{ Position{ position.line, nFrom }, Position{ position.line, nTo } };
}

// ---------------------------------------------------------------------------
// 光标移动的目标（第 34 步）
// ---------------------------------------------------------------------------

std::optional<Position> Document::WordMoveTarget(const Position& position, bool left) const
{
	const auto& d = *m_impl;
	if (!d.IsValidPosition(position) || d.lines.GetLineCount() <= position.line) return std::nullopt;
	CLogicInt nNew;
	if (!CSearchAgent(const_cast<CDocLineMgr*>(&d.lines)).PrevOrNextWord(CLogicInt(position.line), CLogicInt(position.column),
			&nNew, left ? TRUE : FALSE, GetDllShareData().m_Common.m_sGeneral.m_bStopsBothEndsWhenSearchWord ? TRUE : FALSE)) {
		return std::nullopt;
	}
	return Position{ position.line, nNew };
}

std::optional<std::int32_t> Document::ParagraphTarget(std::int32_t line, bool next) const
{
	const auto& d = *m_impl;
	const bool bStopsBothEnds = GetDllShareData().m_Common.m_sGeneral.m_bStopsBothEndsWhenSearchParagraph;
	auto getLine = [&d](std::int32_t y) -> const CDocLine* { return 0 <= y ? d.lines.GetLine(CLogicInt(y)) : nullptr; };
	const CDocLine* pcDocLine;
	if (next) {
		// 原版 Command_GONEXTPARAGRAPH
		int nCaretPointer = 0;
		bool bFirstEmpty = false;
		if ((pcDocLine = getLine(line + nCaretPointer)) != nullptr) {
			bFirstEmpty = pcDocLine->IsEmptyLine();
			nCaretPointer++;
		} else {
			return std::nullopt;	// EOF 行
		}
		while ((pcDocLine = getLine(line + nCaretPointer)) != nullptr && pcDocLine->IsEmptyLine() == bFirstEmpty) {
			nCaretPointer++;
		}
		if (!bFirstEmpty && !bStopsBothEnds) {
			while ((pcDocLine = getLine(line + nCaretPointer)) != nullptr && pcDocLine->IsEmptyLine()) {
				nCaretPointer++;
			}
		}
		return line + nCaretPointer;
	}
	// 原版 Command_GOPREVPARAGRAPH
	int nCaretPointer = -1;
	bool bFirstEmpty;
	if ((pcDocLine = getLine(line + nCaretPointer)) != nullptr) {
		bFirstEmpty = pcDocLine->IsEmptyLine();
	} else {
		bFirstEmpty = true;
	}
	nCaretPointer--;
	while ((pcDocLine = getLine(line + nCaretPointer)) != nullptr && pcDocLine->IsEmptyLine() == bFirstEmpty) {
		nCaretPointer--;
	}
	if (bFirstEmpty) {
		if (!bStopsBothEnds) {
			while ((pcDocLine = getLine(line + nCaretPointer)) != nullptr && !pcDocLine->IsEmptyLine()) {
				nCaretPointer--;
			}
		}
		nCaretPointer++;	// 空行の最上行（段落の末端の次の行）で止まる
	} else {
		nCaretPointer++;
	}
	if (line + nCaretPointer < 0) return std::nullopt;
	return line + nCaretPointer;
}

std::optional<Document::ModifiedLineJump> Document::ModifiedLineTarget(const Position& position, bool next) const
{
	const auto& d = *m_impl;
	const int nSaveSeq = d.opeBuf.GetNoModifiedSeq();
	const bool bSearchAll = GetDllShareData().m_Common.m_sSearch.m_bSearchAll;
	auto isModified = [nSaveSeq](const CDocLine* p) { return CModifyVisitor().IsLineModified(p, nSaveSeq); };
	const int nLineCount = d.lines.GetLineCount();
	const CLogicPoint ptCaret(position.column, position.line);
	auto at = [](CLogicInt x, CLogicInt y, bool wrapped) { return ModifiedLineJump{ Position{ y, x }, wrapped }; };

	if (next) {
		// 原版 Command_MODIFYLINE_NEXT
		const CLogicInt nYOld = CLogicInt(position.line);
		CLogicPoint ptXY(0, nYOld);
		const CDocLine* pcDocLine = d.lines.GetLine(ptXY.GetY2());
		bool bModified = false;
		if (nLineCount == 0) return std::nullopt;
		if (pcDocLine) {
			bModified = isModified(pcDocLine);
			ptXY.y++;
			pcDocLine = pcDocLine->GetNextLine();
		}
		for (int n = 0; n < 2; n++) {
			while (pcDocLine) {
				if (isModified(pcDocLine) != bModified || (0 == ptXY.y && isModified(pcDocLine))) {
					return at(ptXY.x, ptXY.y, nYOld >= ptXY.GetY2());
				}
				ptXY.y++;
				pcDocLine = pcDocLine->GetNextLine();
			}
			if (n == 0 && bModified) {
				const CDocLine* pcDocLineLast = d.lines.GetDocLineBottom();
				bool bSkip = false;
				CLogicPoint pos;
				if (pcDocLineLast != nullptr) {
					if (pcDocLineLast->GetEol().IsNone()) {
						// ぶら下がり[EOF]
						pos.x = pcDocLineLast->GetLengthWithoutEOL();
						pos.y = CLogicInt(nLineCount - 1);
						if (ptCaret == pos) bSkip = true;
					} else {
						pos = ptXY;	// 単独[EOF]
					}
				} else {
					bSkip = true;
				}
				if (!bSkip) return at(pos.x, pos.y, false);
			}
			if (n == 0) {
				ptXY.y = CLogicInt(0);
				pcDocLine = d.lines.GetLine(ptXY.GetY2());
				bModified = false;
			}
			if (!bSearchAll) break;
		}
		return std::nullopt;
	}

	// 原版 Command_MODIFYLINE_PREV
	CLogicPoint ptXY(0, CLogicInt(position.line));
	CLogicInt nYOld2 = ptXY.y;
	const CDocLine* pcDocLine = d.lines.GetLine(ptXY.GetY2());
	bool bModified = false;
	bool bLast = false;
	if (pcDocLine == nullptr) {
		// [EOF]
		const CDocLine* pcDocLineLast = d.lines.GetLine(ptXY.GetY2() - 1);
		if (nullptr == pcDocLineLast) return std::nullopt;	// 1行もない
		ptXY.y--;
		pcDocLine = pcDocLineLast;
		bLast = true;
	}
	if (!bLast) {
		const CDocLine* pcDocLineLast = d.lines.GetDocLineBottom();
		if (pcDocLineLast != nullptr && pcDocLineLast->GetEol().IsNone()) {
			CLogicPoint pos;
			pos.x = pcDocLine->GetLengthWithoutEOL();
			pos.y = CLogicInt(nLineCount - 1);
			if (ptCaret == pos) bLast = true;	// ぶら下がり[EOF]の位置だった
		}
	}
	bModified = isModified(pcDocLine);
	nYOld2 = ptXY.y;
	ptXY.y--;
	pcDocLine = pcDocLine->GetPrevLine();
	if (pcDocLine && !bLast) {
		bModified = isModified(pcDocLine);
		nYOld2 = ptXY.y;
		ptXY.y--;
		pcDocLine = pcDocLine->GetPrevLine();
	}
	for (int n = 0; n < 2; n++) {
		while (pcDocLine) {
			if (isModified(pcDocLine) != bModified) {
				// 検出された位置の1行後ろ(MODIFYLINE_NEXTと同じ位置)に止まる
				return at(CLogicInt(0), nYOld2, n == 1);
			}
			nYOld2 = ptXY.y;
			ptXY.y--;
			pcDocLine = pcDocLine->GetPrevLine();
		}
		if (n == 0) {
			// 先頭行チェック
			const CDocLine* pcDocLineTemp = d.lines.GetDocLineTop();
			if (pcDocLineTemp && isModified(pcDocLineTemp) && ptCaret != CLogicPoint(0, 0)) {
				return at(CLogicInt(0), CLogicInt(0), false);
			}
			ptXY.y = CLogicInt(nLineCount - 1);
			nYOld2 = ptXY.y;
			pcDocLine = d.lines.GetLine(ptXY.GetY2());
			bModified = false;
		}
		if (!bSearchAll) break;
		if (n == 0) {
			const CDocLine* pcDocLineTemp = d.lines.GetDocLineBottom();
			if (pcDocLineTemp && isModified(pcDocLineTemp)) {
				// 最終行が変更行の場合は、[EOF]に止まる
				CLogicPoint pos;
				if (pcDocLineTemp->GetEol().IsValid()) {
					pos.x = CLogicInt(0);
					pos.y = CLogicInt(nLineCount);
				} else {
					pos.x = pcDocLineTemp->GetLengthWithoutEOL();
					pos.y = CLogicInt(nLineCount - 1);
				}
				if (ptCaret != pos) return at(pos.x, pos.y, true);
			}
		}
	}
	return std::nullopt;
}

std::int32_t Document::IndentEnd(std::int32_t line, std::int32_t from, std::int32_t to) const
{
	const auto& d = *m_impl;
	const CDocLine* pDocLine = (0 <= line) ? d.lines.GetLine(CLogicInt(line)) : nullptr;
	if (pDocLine == nullptr) return from;
	const WCHAR* pLine = pDocLine->GetPtr();
	const int nLen = std::min<int>(to, pDocLine->GetLengthWithEOL());
	const bool bZenSpace = d.typeConfig.m_bAutoIndent_ZENSPACE;
	const bool bExtEol = GetDllShareData().m_Common.m_sEdit.m_bEnableExtEol;
	// 原版 Command_GOLINETOP：空白或TAB以外的第一个字。只有空白和换行时是行头
	for (int i = std::max(0, from); i < nLen; ++i) {
		if (WCODE::IsIndentChar(pLine[i], bZenSpace)) continue;
		if (WCODE::IsLineDelimiter(pLine[i], bExtEol)) return from;
		return i;
	}
	return from;
}

// ----- 模式（第 34 步） -----

bool Document::IsInsertMode() const { return m_impl->insertMode; }
void Document::SetInsertMode(bool insert) { m_impl->insertMode = insert; }

Result Document::OverwriteText(const Position& at, const Text& text, Position* pNewCaret)
{
	auto& d = *m_impl;
	if (!d.IsValidPosition(at)) return Result::InvalidArgument;
	const auto& sEdit = GetDllShareData().m_Common.m_sEdit;
	const bool bExtEol = sEdit.m_bEnableExtEol;
	Position caret = at;
	Result result = Result::Ok;
	BeginEdit();
	for (size_t i = 0; i < text.size() && result == Result::Ok; ) {
		size_t n = CNativeW::GetSizeOfChar(text.data(), text.size(), i);
		if (n == 0) n = 1;
		const Text input = text.substr(i, n);
		i += n;
		// 改行は上書き削除しない（原版 Command_WCHAR：改行のときは DelCharForOverwrite を通らない）
		if (!WCODE::IsLineDelimiter(input[0], bExtEol)) {
			// 原版 DelCharForOverwrite
			bool bEol = false;
			bool bDelete = true;
			int nDelLen = 0;
			int nKetaDiff = 0;
			int nKetaAfterIns = 0;
			CLayoutPoint ptLayout;
			d.layout.LogicToLayout(ToLogic(caret), &ptLayout);
			const CLayout* pcLayout = d.layout.SearchLineByLayoutY(ptLayout.GetY2());
			const CDocLine* pcDocLine = d.lines.GetLine(CLogicInt(caret.line));
			if (pcLayout != nullptr && pcDocLine != nullptr) {
				// 指定された桁に対応する行のデータ内の位置
				const int nIdxTo = caret.column - static_cast<int>(pcLayout->GetLogicOffset());
				if (nIdxTo >= static_cast<int>(pcLayout->GetLengthWithoutEOL())) {
					bEol = true;	// 現在位置は改行または折り返し以後
					if (pcLayout->GetLayoutEol().IsValid() && sEdit.m_bNotOverWriteCRLF) {
						bDelete = false;	// 改行は上書きしない
					}
				} else if (sEdit.m_bOverWriteFixMode) {
					// 文字幅に合わせてスペースを詰める
					const CStringRef line = pcDocLine->GetStringRefWithEOL();
					size_t nPos = caret.column;
					if (line.At(nPos) != WCODE::TAB) {
						const int nKetaBefore = static_cast<int>((Int)CNativeW::GetKetaOfChar(line, nPos));
						const int nKetaAfter = static_cast<int>((Int)CNativeW::GetKetaOfChar(input.data(), input.size(), 0));
						nKetaDiff = nKetaBefore - nKetaAfter;
						nPos += CNativeW::GetSizeOfChar(line.GetPtr(), line.GetLength(), nPos);
						nDelLen = 1;
						if (nKetaDiff < 0 && nPos < static_cast<size_t>(line.GetLength())) {
							const WCHAR c = line.At(nPos);
							if (c != WCODE::TAB && !WCODE::IsLineDelimiter(c, bExtEol)) {
								nDelLen = 2;
								const int nKetaBefore2 = static_cast<int>((Int)CNativeW::GetKetaOfChar(line, nPos));
								nKetaAfterIns = nKetaBefore + nKetaBefore2 - nKetaAfter;
							}
						}
					}
				}
			}
			if (bDelete && pcDocLine != nullptr) {
				// 上書きモードなので、現在位置の文字を１文字消去（行末では改行を消す。Command_DELETE と同じ）
				const CStringRef line = pcDocLine->GetStringRefWithEOL();
				const size_t nLength = static_cast<size_t>(line.GetLength());
				size_t nEnd = caret.column;
				const int nCount = bEol ? 1 : std::max(1, nDelLen);
				for (int k = 0; k < nCount && nEnd < nLength; ++k) {
					nEnd += std::max<size_t>(1, CNativeW::GetSizeOfChar(line.GetPtr(), line.GetLength(), nEnd));
				}
				Range range{ caret, caret };
				if (static_cast<size_t>(pcDocLine->GetLengthWithoutEOL()) < nEnd) {
					range.to = Position{ caret.line + 1, 0 };	// 改行を削除
				} else {
					range.to = Position{ caret.line, static_cast<std::int32_t>(nEnd) };
				}
				if (range.from.line != range.to.line || range.from.column != range.to.column) {
					result = Delete(range);
				}
				// 削った幅の分の空白（入力した文字の後ろに残る）
				const int nSpaces = std::max(0, nKetaDiff) + std::max(0, nKetaAfterIns);
				if (result == Result::Ok && 0 < nSpaces) {
					result = Insert(caret, Text(static_cast<size_t>(nSpaces), u' '));
				}
			}
		}
		if (result == Result::Ok) result = Insert(caret, input, &caret);
	}
	EndEdit();
	if (pNewCaret) *pNewCaret = caret;
	return result;
}

std::optional<std::int32_t> Document::WrapWindowWidthColumns(std::int32_t width) const
{
	// 原版 CEditView::GetWrapMode。現在の幅に合わせるのを最優先に．
	//	基本動作： 設定値→ウィンドウ幅
	//		→(ウィンドウ幅と合っていなければ)→ウィンドウ幅→上へ戻る
	//		→(ウィンドウ幅と合っていたら)→最大値→設定値
	//		ただし，最大値==設定値の場合には最大値→設定値の遷移が省略されて上に戻る
	const auto& d = *m_impl;
	const std::int32_t nCurrent = static_cast<std::int32_t>((Int)d.layout.GetMaxLineKetas());
	const std::int32_t nType = static_cast<std::int32_t>((Int)d.typeConfig.m_nMaxLineKetas);
	const std::int32_t nWindow = WrapColumnsForWidth(width);
	if (nCurrent == nWindow) {
		return MAXLINEKETAS;	// 1) 現在の折り返し幅==ウィンドウ幅 : 最大値
	}
	// 2) 現在の折り返し幅!=ウィンドウ幅
	// 原版は MINLINEKETAS > m_nViewColNum - GetWrapOverhang()（ぶら下げ余白を引いた幅が MINLINEKETAS 桁に足りない）。
	// WrapColumnsForWidth は MINLINEKETAS で切り上げるので、1 桁広い幅でも MINLINEKETAS なら足りない
	if (nWindow == MINLINEKETAS && WrapColumnsForWidth(width + CharWidth()) == MINLINEKETAS) {
		// 3) ウィンドウ幅が極端に狭い場合
		if (nCurrent != MAXLINEKETAS) return MAXLINEKETAS;	// 4) 折り返し幅!=最大値 : 最大値
		if (nType == MAXLINEKETAS) return std::nullopt;		// 6) 最大値==設定値 : 変更不能
		return nType;										// 7) 最大値!=設定値 : 設定値
	}
	// 8) ウィンドウ幅が十分にある
	if (nCurrent == MAXLINEKETAS && nType != MAXLINEKETAS) {
		return nType;		// 9) a) 最大値!=設定値 : 設定値
	}
	return nWindow;			// b) c) ウィンドウ幅
}

// ----- フォントサイズ（第 34 步） -----

std::optional<FontZoom> ZoomFontSize(double basePointSize, double zoom, std::int32_t steps, double unit)
{
	// 原版 Command_SETFONTSIZE 的倍率表和上下限（1/10 点单位）
	constexpr std::array<double, 72> aZoomFactors = {
		0.01, 0.011, 0.0125, 0.015, 0.0175, 0.02, 0.0225, 0.025, 0.0275, 0.03, 0.035, 0.04, 0.045, 0.05, 0.06, 0.07, 0.08, 0.09,
		0.1, 0.11, 0.125, 0.15, 0.175, 0.2, 0.225, 0.25, 0.275, 0.3, 0.35, 0.4, 0.45, 0.5, 0.6, 0.7, 0.8, 0.9,
		1.0, 1.1, 1.25, 1.5, 1.75, 2.0, 2.25, 2.5, 2.75, 3.0, 3.5, 4.0, 4.5, 5.0, 6.0, 7.0, 8.0, 9.0,
		10.0, 11.0, 12.5, 15.0, 17.5, 20.0, 22.5, 25.0, 27.5, 30.0, 35.0, 40.0, 45.0, 50.0, 60.0, 70.0, 80.0, 90.0
	};
	constexpr double nPointSizeMin = 10;
	constexpr double nPointSizeMax = 720;
	const ZoomSetting zoomSetting(aZoomFactors.begin(), aZoomFactors.end(), nPointSizeMin, nPointSizeMax, std::max(0.0, unit) * 10.0);
	double nPointSize = 0;
	double nNewZoom = zoom;
	if (!GetZoomedValue(zoomSetting, basePointSize * 10.0, zoom, steps, &nPointSize, &nNewZoom)) {
		return std::nullopt;
	}
	return FontZoom{ nPointSize / 10.0, nNewZoom };
}

} // namespace sakura::core
