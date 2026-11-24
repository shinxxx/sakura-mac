/*! @file
	@brief Mac 版核心库的对外接口（计划第 22 步）

	界面层（第 24 步起的 Objective-C++ 桥接层和 Swift）只通过这个头文件使用核心库。
	这个头文件只引用 C++ 标准库，不引用 Windows 的头文件、平台抽象层（macos/platform）
	和 sakura_core 的头文件。CMake 的 sakura_core_api_header_check 目标在只有这个目录的
	包含路径下编译它，确认这一点。

	- 文字一律是 UTF-16（std::u16string），与原版内部的宽字符相同。
	- 位置是“逻辑位置”：行号从 0 开始，列是行内的 UTF-16 下标（原版的 CLogicPoint）。
	  自动换行后的“排版位置”是 LayoutPosition（第 27 步，原版的 CLayoutPoint）。
	- 编码、换行符、功能编号的数值与原版相同（ECodeType、EEolType、EFunctionCode），
	  所以 sakura.ini 和宏里的数值可以直接使用。
*/
/*
	Copyright (C) 2026, Sakura Editor Organization

	SPDX-License-Identifier: Zlib
*/
#pragma once

#include <cstdint>
#include <functional>
#include <memory>
#include <optional>
#include <string>
#include <utility>
#include <vector>

namespace sakura::core {

//! 文字（UTF-16）
using Text = std::u16string;

// ---------------------------------------------------------------------------
// 启动和结束
// ---------------------------------------------------------------------------

/*!
	启动核心库：建立共通设置，读入 sakura.ini（没有时写出默认设置）。
	与原版控制进程（CControlProcess::InitializeProcess）的顺序相同。
	使用 Document 之前调用一次。已经启动时什么也不做，返回 true。
*/
bool Startup();

/*!
	结束核心库。saveSettings 为 true 时写出 sakura.ini（与原版控制进程结束时相同）。
	结束后所有 Document 都不能再使用。
*/
void Shutdown(bool saveSettings = true);

//! 是否已经启动
bool IsStarted();

//! 设置文件 sakura.ini 的路径（~/Library/Application Support/sakura/sakura.ini）
Text SettingsFilePath();

// ---------------------------------------------------------------------------
// 导入设置（第 35 步）
// ---------------------------------------------------------------------------

//! 导入设置的结果
enum class ImportResult {
	Imported,			//!< 成功（CheckSettingsFile：是设置文件）
	NotSettingsFile,	//!< 不是サクラエディタ的设置文件
	ReadFailed,			//!< 读不了（没有这个文件等）
	WriteFailed,		//!< 写不了 sakura.ini
};

/*!
	path 是不是サクラエディタ的设置文件（sakura.ini）。
	UTF-8（带 BOM）和旧版本的 Shift_JIS 都可以；有 [Common] 节的 nCaretType 就当作设置文件。
*/
ImportResult CheckSettingsFile(const Text& path);

/*!
	导入 Windows 版的设置文件 sakura.ini。
	- 共通設定、キー割り当て、ツールバー、メインメニュー、タイプ別設定、強調キーワード、印刷設定等全部用导入的。
	  ini 的格式与 Windows 版相同，读入后的值也相同（Windows 的路径、字体名原样保留）。
	- 历史（最近使ったファイル・フォルダー、検索・置換・Grep・コマンドの履歴）保留这台 Mac 的。
	- 导入前的设置备份在 SettingsBackupPath()。
	与在 Windows 版换掉 sakura.ini 后重新启动相同：导入的设置在下一次 Startup 时读入。
	在那之前 Shutdown 不写出设置（IsSettingsImportPending）。
*/
ImportResult ImportSettings(const Text& path);

//! 导入以后、重新启动之前是 true
bool IsSettingsImportPending();

//! 导入前的设置的备份（sakura.ini.before-import）
Text SettingsBackupPath();

// ---------------------------------------------------------------------------
// 共通設定的读写（第 39 步：共通設定窗口）
// ---------------------------------------------------------------------------

/*!
	共通設定的一项的值。节和项目与 sakura.ini 相同（例："Common" / "bIsFreeCursorMode"）。
	值是 sakura.ini 里的写法（数值是十进制，字符串原样）。
	能用的节：Common、Nickname（ファイル名表示）、Statusbar（ステータスバー）、
	Types(N)（タイプ別設定 的第 N 个，0 是「基本」。第 40 步）、KeyWords（第 40 步）、KeyBind・MainMenu・CustMenu・Toolbar（第 41 步）。没有这一项时是空的 optional。
*/
std::optional<Text> GetCommonSetting(const Text& section, const Text& key);

/*!
	改共通設定的一项。与把 sakura.ini 的这一项改成 value 再读入相同（原版读入时的范围限制等照样）。
	没有这一项时 false，什么也不改。
*/
bool SetCommonSetting(const Text& section, const Text& key, const Text& value);

/*!
	一次改同一节的几项（key, value）。与把 sakura.ini 的这些项改了再读入一次相同。
	ファイル名表示 的置換リスト（Nickname 的 ArrNum、From%02d、To%02d）要一起改：项数变了时，
	一项一项地改的话 ArrNum 以外的项目还没有。
	读入以后有一项不在这一节里时（没有的项目、ArrNum 以外的 From%02d 等）false，什么也不改。
	值是空字符串的项读入以后没有也可以（列表变短了：タイプ別設定的 RxKey[nnn]、KDct[nn] 等。第 40 步）。
*/
bool SetCommonSettings(const Text& section, const std::vector<std::pair<Text, Text>>& values);

//! タイプ別設定 的一个（原版 STypeConfigMini 的一部分。第 40 步）
struct TypeSettingInfo {
	std::int32_t index = 0;	//!< 编号（sakura.ini 的 Types(N) 的 N）。0 是「基本」
	Text name;				//!< 設定の名前
	Text extensions;		//!< ファイル拡張子
};

//! タイプ別設定 的一览（顺序与 sakura.ini 的 Types(0)、Types(1)… 相同）
std::vector<TypeSettingInfo> TypeSettings();

//! タイプ別設定「カラー」页的一行（原版 ColorInfo 的名字和 g_ColorAttributeArr 的属性。第 40 步）
struct ColorItemInfo {
	std::int32_t index = 0;		//!< 颜色的编号（ColorIndex 的数值）
	Text name;					//!< 显示的名字（「テキスト」等）
	Text key;					//!< sakura.ini 的项目（「C[TXT]」等）。值是「表示,太字,文字色,背景色,下線」（色是 6 位 16 进制的 BGR）
	bool forceDisplay = false;	//!< 一直显示（「色分け/表示」不能关，COLOR_ATTRIB_FORCE_DISP）
	bool noText = false;		//!< 没有文字色（COLOR_ATTRIB_NO_TEXT）
	bool noBack = false;		//!< 没有背景色（COLOR_ATTRIB_NO_BACK）
	bool noBold = false;		//!< 不能是太字（COLOR_ATTRIB_NO_BOLD）
	bool noUnderline = false;	//!< 不能加下線（COLOR_ATTRIB_NO_UNDERLINE）
};

//! 「カラー」页的全部的行（顺序与原版的色指定列表相同）
std::vector<ColorItemInfo> ColorItems();

//! 強調キーワード的セット名（共通設定 > 強調キーワード。顺序就是编号：nKeywordSelect 等的值）
std::vector<Text> KeywordSetNames();

//! タイプ別設定的导入・导出的文件（原版 CImpExpColors、CImpExpRegex、CImpExpKeyHelp。第 40 步）
enum class TypeSettingFile {
	Colors,			//!< 色設定（*.col）
	RegexKeywords,	//!< 正規表現キーワード（*.rkw）
	KeywordHelp,	//!< キーワード辞書の一覧（*.txt）
};

//! 导入・导出的结果
struct TypeSettingFileResult {
	bool succeeded = false;
	Text message;	//!< 原版显示的消息（失败的原因、读入时的警告）。没有时是空
	//! 导入后的 sakura.ini 的值（[Types(N)] 的项目）。色是全部的「C[…]」，正規表現キーワード是
	//! RxKey[000]～RxKey[099]，キーワード辞書是 KDct[00]～KDct[19]（没有的项是空字符串）
	std::vector<std::pair<Text, Text>> values;
};

/*!
	从文件读入第 typeIndex 个类型的色設定・正規表現キーワード・キーワード辞書（文件格式与原版相同）。
	pending 是窗口里还没有 OK 的值（[Types(N)] 的项目）：在这个类型的现在的设置上加上 pending 再读入。
	不改核心库的设置（OK 时由窗口写回）。
*/
TypeSettingFileResult ImportTypeSettingFile(TypeSettingFile kind, std::int32_t typeIndex,
	const std::vector<std::pair<Text, Text>>& pending, const Text& path);

// ----- タイプ別設定一覧（第 40 步。原版 CDlgTypeList）-----
//! 类型的最大个数（MAX_TYPES）
std::int32_t MaxTypeSettings();
//! 追加：在最后加一个「基本」的复制（名字是「設定N」，没有拡張子）。返回编号，不能加时 -1
std::int32_t AddTypeSetting();
//! 複製：在最后加这个类型的复制（名字后面的数字加 1，与原版相同）。返回编号，不能加时 -1
std::int32_t CopyTypeSetting(std::int32_t index);
//! 削除（「基本」不能删）
bool DeleteTypeSetting(std::int32_t index);
//! ↑・↓：与上・下一个交换（「基本」不动）。返回新的编号，不能动时 -1
std::int32_t MoveTypeSetting(std::int32_t index, bool up);
//! 初期化：「基本」回到内置的设置，别的类型换成「基本」的复制（名字「設定N」、没有拡張子）。返回新的名字，失败时空
Text InitializeTypeSetting(std::int32_t index);

//! タイプ別設定的文件（*.ini）的内容（原版 CImpExpType::ImportAscertain 读的部分）
struct TypeSettingFileInfo {
	bool succeeded = false;
	Text message;				//!< 读不了时的原因
	Text typeName;				//!< 文件里的設定の名前
	Text version;				//!< 写出这个文件的サクラエディタ的版本
	std::int32_t structureVersion = 0;
	bool versionDiffers = false;	//!< 设置的结构版本与这个 App 不同（原版要确认）
	std::vector<Text> colorFiles;	//!< 同一个文件夹里的色設定文件（*.col，确认对话框的「色選択」）
};
TypeSettingFileInfo CheckTypeSettingFile(const Text& path);

//! インポート確認（原版 CDlgTypeAscertain）的选择
struct TypeSettingImportChoice {
	bool addNew = true;			//!< 新規追加（false 时换掉选着的类型）
	std::int32_t colorType = -1;	//!< 色：-1 文件里的、0 以上是那个类型的色
	Text colorFile;				//!< 色：同一个文件夹里的色設定文件（不是空时优先）
};

//! インポート的结果
struct TypeSettingImportResult {
	bool succeeded = false;
	Text message;				//!< 原版的消息（成功时也有：读入的文件的一览）
	std::int32_t index = -1;	//!< 读入的类型的编号
	bool added = false;
};

/*!
	从文件读入タイプ別設定（原版 CDlgTypeList::Import + CImpExpType::Import）。index 是选着的类型。
	文件里的強調キーワード（*.kwd）也读入共通設定。
*/
TypeSettingImportResult ImportTypeSetting(const Text& path, std::int32_t index, const TypeSettingImportChoice& choice);
//! 写出这个类型（*.ini，用到的強調キーワード也写成同一个文件夹的 *.kwd）
TypeSettingFileResult ExportTypeSetting(std::int32_t index, const Text& path);

/*!
	共通設定 > 強調キーワード 的编辑（第 40 步。原版 CPropKeyword 在 CommonSetting 的复制上编辑）。
	Create 时复制核心库现在的强调关键字，编辑只改这个复制；OK 时把 IniValues() 的值写进 sakura.ini 的 [KeyWords] 节
	（SetCommonSettings(u"KeyWords", …)），与原版读入 sakura.ini 时相同地换掉。
*/
class KeywordSetEditor {
public:
	static std::unique_ptr<KeywordSetEditor> Create();
	~KeywordSetEditor();
	KeywordSetEditor(const KeywordSetEditor&) = delete;
	KeywordSetEditor& operator=(const KeywordSetEditor&) = delete;

	std::int32_t SetCount() const;
	Text SetName(std::int32_t set) const;
	bool IsCaseSensitive(std::int32_t set) const;
	//! 选着的セット（原版 m_nCurrentKeyWordSetIdx：别的窗口的设置画面也从这个セット开始）。没有セット时 -1
	std::int32_t CurrentSet() const;
	void SetCurrentSet(std::int32_t set);

	//! 一个关键字：编号（Update・Delete 用）和文字
	struct Keyword {
		std::int32_t index = 0;
		Text text;
	};
	//! 这个セット的关键字（按文字排好的顺序，原版的列表 LVS_SORTASCENDING）
	std::vector<Keyword> Keywords(std::int32_t set) const;
	//! 还能登录几个（原版 DispKeywordCount 的「空き」）
	std::int32_t FreeCount(std::int32_t set) const;
	//! 还能再加一个吗（原版 CanAddKeyWord）
	bool CanAddKeyword(std::int32_t set) const;

	//! セット追加（原版 AddKeyWordSet：区分大小写是 false）。セット已经有 MAX_SETNUM 个时 false
	bool AddSet(const Text& name);
	//! セット削除。使用这个セット的タイプ别设置的编号由界面层调整（原版 CPropKeyword 的 m_Types_nKeyWordSetIdx）
	bool DeleteSet(std::int32_t set);
	void RenameSet(std::int32_t set, const Text& name);
	void SetCaseSensitive(std::int32_t set, bool on);

	//! 关键字的追加：0 成功、1 セット番号エラー、2 已满、3 空的关键字、4 重复（与原版 AddKeyWord 相同）
	std::int32_t AddKeyword(std::int32_t set, const Text& keyword);
	//! 关键字的编辑（重复的、空的不改）。改了时 true
	bool UpdateKeyword(std::int32_t set, std::int32_t index, const Text& keyword);
	void DeleteKeyword(std::int32_t set, std::int32_t index);
	//! 整理：删掉现在的设置下不能作为强调关键字显示的关键字（重复等，原版 CleanKeyWords）。返回删掉的个数
	std::int32_t Clean(std::int32_t set);

	//! 从文件读入关键字（*.kwd，原版 CImpExpKeyWord）。成功时 true，message 是原版的消息
	bool Import(std::int32_t set, const Text& path, Text& message);
	bool Export(std::int32_t set, const Text& path, Text& message);

	//! sakura.ini 的 [KeyWords] 节的值（项目, 值）。セット减少了时，没有了的项目是空字符串
	std::vector<std::pair<Text, Text>> IniValues() const;

private:
	KeywordSetEditor();
	struct Impl;
	std::unique_ptr<Impl> m_impl;
};

/*!
	正規表現キーワード的检查（タイプ別設定 > 正規表現キーワード 的登录时，原版 CPropTypesRegex::CheckKeywordList）。
	hasDelimiters：用「/…/k」「m#…#k」等围起来了（原版 CRegexKeyword::RegexKeyCheckSyntax）。
	syntaxOK：正则表达式的语法正确（原版 CheckRegexpSyntax(…, bKakomi = true)）。
*/
struct RegexKeywordCheck {
	bool hasDelimiters = false;
	bool syntaxOK = false;
};
RegexKeywordCheck CheckRegexKeyword(const Text& keyword);

/*!
	キーワード辞書的「辞書の説明」：辞書文件的第 1 行（原版 CPropTypesKeyHelp：去掉换行，逗号换成「.」）。
	打不开时 nullopt。相对路径从设置文件的文件夹找（原版 CTextInputStream_AbsIni）。
*/
std::optional<Text> KeywordHelpDictionaryAbout(const Text& path);

//! 写出到文件（与原版的エクスポート相同的格式）。pending 同上
TypeSettingFileResult ExportTypeSettingFile(TypeSettingFile kind, std::int32_t typeIndex,
	const std::vector<std::pair<Text, Text>>& pending, const Text& path);

//! 现在的设置写进 sakura.ini（与结束时相同）。导入设置以后、重新启动之前不写，返回 false
bool SaveSettings();

// ---------------------------------------------------------------------------
// 编码、换行符
// ---------------------------------------------------------------------------

/*!
	编码。数值与原版的 ECodeType 相同。
	下面以外的值是代码页编号（例如 1252、20936），与原版的“代码页”指定相同。
*/
using Encoding = std::int32_t;
namespace encoding {
	constexpr Encoding SJIS       = 0;
	constexpr Encoding JIS        = 1;
	constexpr Encoding EUC        = 2;
	constexpr Encoding UTF16LE    = 3;
	constexpr Encoding UTF8       = 4;
	constexpr Encoding UTF7       = 5;
	constexpr Encoding UTF16BE    = 6;
	constexpr Encoding CESU8      = 7;
	constexpr Encoding Latin1     = 8;
	constexpr Encoding UTF32LE    = 12000;
	constexpr Encoding UTF32BE    = 12001;
	constexpr Encoding AutoDetect = 99;	//!< 打开文件时自动识别
	constexpr Encoding None       = -1;
}

//! 编码的显示名（与原版状态栏、对话框里的名字相同，例如 "SJIS"、"UTF-8"）
Text EncodingName(Encoding code);

//! 能否用于打开和保存
bool IsValidEncoding(Encoding code);

//! 文件对话框的编码列表里的一项（第 30 步）
struct EncodingChoice {
	Encoding code = encoding::None;
	Text name;		//!< 列表里显示的名字（"自動選択"、"EUC-JP"、"932 (ANSI/OEM - Japanese Shift-JIS)" 等）
};

/*!
	打开、保存对话框的「文字コードセット」列表（原版 CCodeTypesForCombobox）。
	第一项是「自動選択」（encoding::AutoDetect），保存对话框不用这一项。
*/
std::vector<EncodingChoice> EncodingChoices();

/*!
	勾选「CP」后追加到列表里的代码页（原版 CDlgOpenFile::AddComboCodePages）：
	CP_ACP、CP_OEM，然后是系统的代码页和 UTF-32。
*/
std::vector<EncodingChoice> CodePageChoices();

//! 这个编码能否加 BOM（原版 CCodeTypeName::UseBom）。不能时保存对话框的 BOM 不可选
bool EncodingCanHaveBom(Encoding code);

//! 保存对话框里换成这个编码时 BOM 是否默认勾选（原版 CCodeTypeName::IsBomDefOn）
bool EncodingBomDefault(Encoding code);

//! 能否作为タイプ別設定的デフォルトの文字コード（原版 CCodeTypeName::CanDefault。第 40 步）
bool EncodingCanBeDefault(Encoding code);

//! 换行符。数值与原版的 EEolType 相同
enum class Eol : std::uint8_t {
	None               = 0,	//!< 没有换行符（最后一行）。保存时表示“不转换”
	CRLF               = 1,
	LF                 = 2,
	CR                 = 3,
	NEL                = 4,	//!< U+0085（扩展换行符）
	LineSeparator      = 5,	//!< U+2028（扩展换行符）
	ParagraphSeparator = 6,	//!< U+2029（扩展换行符）
};

//! 换行符的文字（Eol::None 时是空）
Text EolText(Eol eol);

// ---------------------------------------------------------------------------
// 位置、结果
// ---------------------------------------------------------------------------

//! 逻辑位置：行号和行内的 UTF-16 下标，都从 0 开始
struct Position {
	std::int32_t line = 0;
	std::int32_t column = 0;

	friend bool operator==(const Position&, const Position&) = default;
	friend auto operator<=>(const Position& a, const Position& b) = default;
};

//! 范围 [from, to)
struct Range {
	Position from;
	Position to;

	bool IsEmpty() const { return from == to; }
	friend bool operator==(const Range&, const Range&) = default;
};

enum class Result {
	Ok,
	LostSome,			//!< 完成，但有的字符不能用这个编码表示（原版的 RESULT_LOSESOME）
	Failed,				//!< 文件打不开、读写失败、编码不能转换等
	InvalidArgument,	//!< 位置超出范围、编码不对等
	NotFound,			//!< 查找没有找到
	NotSupported,		//!< 这个功能在 Mac 版还没有移植
};

// ---------------------------------------------------------------------------
// 打开、保存
// ---------------------------------------------------------------------------

struct OpenOptions {
	Encoding encoding = encoding::AutoDetect;	//!< 指定编码，或者自动识别
	/*!
		「最近使ったファイル」的历史（原版 CMruListener，第 31 步）：
		- 历史里有这个文件时，用上次的类型别设置；自动识别的结果与上次的编码不同时用上次的编码
		- 打开后恢复光标位置（GetRestoredView），并登记到历史
		false 时这些都不做（测试、内部用）。
	*/
	bool useHistory = true;
	/*!
		打开时的编码与上次不同、并且共通设置「前回と異なる文字コードの時に問い合わせを行う」打开时调用
		（原版的确认消息 STR_ERR_DLGEDITDOC6）。返回 true 用上次的编码，false 用这次的编码。
		没有设置时与不问时相同：自动识别时用上次的编码，指定时用指定的编码。
	*/
	std::function<bool(Encoding current, Encoding previous)> askUsePreviousEncoding;
};

struct SaveOptions {
	std::optional<Encoding> encoding;	//!< 不指定时用打开时的编码
	std::optional<bool> bom;			//!< 不指定时与打开时相同
	Eol eol = Eol::None;				//!< 统一换行符。None 是不转换（原版“名前を付けて保存”的改行コード）
};

/*!
	保存前的检查结果（原版 CCodeChecker::OnCheckSave，第 30 步）。
	界面层据此问用户：换行符统一吗？有字符会丢失，继续保存吗？
*/
struct SaveCheck {
	//! 换行符混在。只在类型别设置「保存時に改行コードの混在を警告する」打开、并且保存时不转换换行符时检查
	bool eolMixed = false;
	//! 有不能用这个编码表示的字符
	bool lostSome = false;
	//! 最初不能表示的位置。column 为 -1 表示行内的位置不明
	Position lostAt;
	//! 不能表示的那个字（不明时是空）
	Text lostChar;
	//! 那个字的代码（"U+3042" 等，与状态栏的显示方式相同；不明时是空）
	Text lostCharCode;
};

// ---------------------------------------------------------------------------
// 最近使ったファイル、最近使ったフォルダー（原版 CMRUFile、CMRUFolder，第 31 步）
// ---------------------------------------------------------------------------

struct RecentFile {
	Text path;
	Encoding encoding = encoding::None;		//!< 上次的编码
	Position caret;							//!< 上次的光标位置
	std::int32_t viewTopLine = 0;			//!< 上次表示域的第一行（排版行）
	bool favorite = false;					//!< お気に入り
	//! 菜单里显示的文字（原版 GetMenuFullLabel_MRU。开头是快捷键 "&1 " 这样的部分，编码不是 SJIS 时后面加 "  [UTF-8]"）
	Text menuLabel;
};

struct RecentFolder {
	Text path;								//!< 末尾带 "/"
	bool favorite = false;
	Text menuLabel;
};

//! 菜单里显示的历史（新的在前。个数是共通设置「ファイルの履歴MAX」，默认 15）
std::vector<RecentFile> RecentFiles();
//! 同上（「フォルダーの履歴MAX」）
std::vector<RecentFolder> RecentFolders();
//! 历史里这个文件的记录（菜单里不显示的也算）
std::optional<RecentFile> FindRecentFile(const Text& path);
//! 删除这个文件的历史（打不开的文件，原版 F_FILE_USED_RECENTLY 打开失败时）
void RemoveRecentFile(const Text& path);
//! 删除全部「最近使ったファイル」（共通設定 > 全般「履歴をクリア」，原版 CMRUFile::ClearAll。お気に入り也删除，第 39 步）
void ClearRecentFiles();
//! 删除全部「最近使ったフォルダー」（原版 CMRUFolder::ClearAll，第 39 步）
void ClearRecentFolders();

//! 打开时从历史恢复的位置（原版 CMruListener::OnAfterLoad）
struct RestoredView {
	Position caret;
	std::int32_t viewTopLine = 0;	//!< 表示域的第一行（排版行）
	bool toEnd = false;				//!< 上次的位置超过了文件末尾：移到文件末尾（原版 F_GOFILEEND）
};

//! 文件的信息（原版的 SFileInfo 的一部分）
struct FileInfo {
	Text path;							//!< 空表示新文件（无题）
	Encoding encoding = encoding::UTF8;
	bool bom = false;
	std::int32_t typeIndex = 0;			//!< 类型别设置的编号（0 是“基本”）
	Text typeName;						//!< 类型别设置的名字
};

// ---------------------------------------------------------------------------
// 查找
// ---------------------------------------------------------------------------

//! 查找条件（原版的 SSearchOption）
struct SearchOptions {
	bool regularExpression = false;
	bool matchCase = false;		//!< 区分大小写（原版的 bLoHiCase）
	bool wholeWord = false;		//!< 单词单位（原版的 bWordOnly）
};

enum class SearchDirection { Forward, Backward };

/*!
	查找、替换、跳转的共通设置（第 32 步。原版 CommonSetting_Search 里对话框用的部分，
	和 DLLSHAREDATA::m_bLineNumIsCRLF_ForJump）。保存在 sakura.ini，与原版相同。
*/
struct SearchSettings {
	SearchOptions options;				//!< 上次的查找条件（m_sSearchOption）
	bool notifyNotFound = false;		//!< 見つからないときにメッセージを表示（m_bNOTIFYNOTFOUND）
	bool autoCloseFind = false;			//!< 検索ダイアログを自動的に閉じる（m_bAutoCloseDlgFind）
	bool autoCloseReplace = false;		//!< 置換ダイアログを自動的に閉じる（m_bAutoCloseDlgReplace）
	bool searchAll = false;				//!< 先頭（末尾）から再検索する（m_bSearchAll）
	bool consecutiveAll = false;		//!< 「すべて置換」は置換の繰返し（m_bConsecutiveAll）
	bool selectedArea = false;			//!< 置換の範囲が「選択範囲」（m_bSelectedArea）
	bool caretTextForSearch = true;		//!< カーソル位置の文字列をデフォルトの検索文字列にする（m_bCaretTextForSearch）
	bool inheritKeyOtherView = true;	//!< 次・前検索で他のビューの検索条件を引き継ぐ（m_bInheritKeyOtherView）
	bool jumpLineNumIsCRLF = true;		//!< 指定行へジャンプ：改行単位の行番号（m_bLineNumIsCRLF_ForJump）
};

SearchSettings GetSearchSettings();
void SetSearchSettings(const SearchSettings& settings);

/*!
	查找、置换后的文字的历史（原版 CRecentSearch、CRecentReplace，sakura.ini 的 [Keys]）。新的在前。
*/
std::vector<Text> SearchKeyHistory();
std::vector<Text> ReplaceKeyHistory();

/*!
	登记到历史（原版 CSearchKeywordManager::AddToSearchKeyArr、AddToReplaceKeyArr）。
	与原版的对话框相同，_MAX_PATH 以上长度的不登记。登记后序号加 1。
*/
void AddSearchKey(const Text& key);
void AddReplaceKey(const Text& key);

/*!
	历史的序号（原版 m_nSearchKeySequence、m_nReplaceKeySequence）：每次登记加 1，不保存。
	画面和对话框记住上次用的序号，用来知道别的窗口登记了新的文字。
*/
std::int32_t SearchKeySequence();
std::int32_t ReplaceKeySequence();

/*!
	正则表达式的语法检查（原版 CheckRegexpSyntax）。
	@return 错误时是正则表达式库的消息（原版在「正規表現の構文に誤りがあります。」后面显示的部分），没有错误时是 nullopt
*/
std::optional<Text> RegexpSyntaxError(const Text& pattern, bool matchCase);

//! 正则表达式库的版本（查找对话框里显示的，原版 CheckRegexpVersion）。不能用时是空
Text RegexpVersion();

/*!
	编辑画面的光标和选择范围（第 32 步：查找、替换命令的输入和结果）。
	原版的命令直接移动 CEditView 的光标、改变选择范围；Mac 版的编辑画面在界面层，
	所以命令接受现在的光标和选择，返回之后的光标和选择。
*/
struct SearchView {
	Position caret;
	/*!
		普通选择（from <= to）。没有选择时是 nullopt。
		from == to 的选择是上次长度 0 的匹配（原版 IsOne() 的选择），下検索时先前进一个字。
	*/
	std::optional<Range> selection;
};

enum class SearchStatus : std::uint8_t {
	Found,			//!< 找到了
	Wrapped,		//!< 找到了，是从先頭（末尾）再查找的（原版状态栏的「▼先頭から再検索しました」）
	NotFound,		//!< 没有找到
	InvalidPattern,	//!< 正则表达式有错误（error 是原因）
};

struct SearchResult {
	SearchStatus status = SearchStatus::NotFound;
	SearchView view;	//!< 之后的光标和选择（找到时选中匹配的部分，光标在匹配的开头）
	Text error;
};

//! 置換対象（置换对话框的「置換対象」。数值与原版的 m_nReplaceTarget 相同）
enum class ReplaceTarget : std::uint8_t {
	Selection = 0,		//!< 選択文字：换成置换后的文字
	InsertBefore = 1,	//!< 選択始点挿入：插在匹配的前面
	InsertAfter = 2,	//!< 選択終点追加：加在匹配的后面
	DeleteLine = 3,		//!< 行削除：删除匹配所在的行
};

struct ReplaceOptions {
	SearchOptions search;
	ReplaceTarget target = ReplaceTarget::Selection;
	/*!
		クリップボードから貼り付ける：replacement 是剪贴板的文字。
		与原版相同，这时正则表达式也不做「$1」等的替换，原样插入；
		共通设置「改行コードを変換して貼り付ける」打开时换成输入用的换行符。
	*/
	bool paste = false;
	bool searchAll = false;			//!< 先頭（末尾）から再検索する（置換时的下一次查找）
	bool consecutiveAll = false;	//!< 「すべて置換」は置換の繰返し（只在正则表达式时有用）
	bool selectedArea = false;		//!< すべて置換：只换选择范围里的（没有选择时换整个文件）
};

struct ReplaceResult {
	/*!
		置換：第一次查找（找要换的地方）的结果。NotFound 时什么也没换。
		すべて置換：正则表达式有错误时是 InvalidPattern，否则是 Found。
	*/
	SearchStatus status = SearchStatus::NotFound;
	//! 置換：换了之后下一次查找的结果（NotFound 时原版显示「最後まで置換しました。」）
	SearchStatus next = SearchStatus::NotFound;
	std::int32_t count = 0;		//!< 换了的个数
	SearchView view;			//!< 之后的光标和选择
	Text error;
};

//! 指定行へジャンプ（原版 CDlgJump 的设置）
struct JumpOptions {
	std::int32_t lineNumber = 1;		//!< 行番号（从 1 开始）
	bool lineNumIsCRLF = true;			//!< true：改行単位の行番号，false：折り返し単位の行番号
	bool plsql = false;					//!< PL/SQLコンパイルエラー行を処理する
	std::int32_t plsqlBlockFirstLine = 1;	//!< PL/SQL：「テキストの n 行目をブロックの1行目とする」
};

//! 查找文字的标记（第 32 步：画面上用「検索文字列」的颜色显示查找到的文字，原版 CColor_Found）
struct SearchMark {
	std::int32_t from = 0;		//!< 逻辑行内的 UTF-16 下标
	std::int32_t to = 0;
	std::uint8_t color = 0;		//!< ColorIndex（Search～Search5）
};

//! 语法颜色的一段（第 33 步：原版 CEditView::DrawLogicLine 的色分け，CColor_Comment 等）
struct SyntaxColorRun {
	std::int32_t from = 0;		//!< 逻辑行内的 UTF-16 下标
	std::int32_t to = 0;
	std::uint8_t color = 0;		//!< ColorIndex（Digit、Comment～Regex10）
};

// ---------------------------------------------------------------------------
// 排版（第 27 步）
// ---------------------------------------------------------------------------

/*!
	测量文字宽度的函数（界面层用 Core Text 实现）：字体名（以 0 结尾）、大小（点）、文字，返回宽度（点，整数）。
	原版用 GDI 的 GetTextExtentPoint32 测量。没有登记时用简单的估算（半角是大小的一半，宽字符是两倍），
	单元测试用这个估算。
*/
using TextMeasureFunction = std::int32_t (*)(const char16_t* faceName, std::int32_t size, const char16_t* text, std::size_t length);
void SetTextMeasureFunction(TextMeasureFunction func);

/*!
	排版用的字体（原版的共通设置「フォント」）。字体名和大小（点）。
	字符宽度用界面层登记的测量函数（Core Text）来测，与原版相同：
	等宽字体里比半角宽的字符一律算半角的 2 倍。
	改变后，已经打开的文档要调用 Document::Relayout。
*/
void SetLayoutFont(const Text& faceName, std::int32_t size);

//! フォントサイズ拡大／縮小的结果（第 34 步）
struct FontZoom {
	double pointSize = 0;	//!< 新的大小（点）
	double zoom = 1.0;		//!< 新的倍率
};
/*!
	フォントサイズ拡大／縮小（原版 Command_SETFONTSIZE 的 shift）：按原版的倍率表（1%～9000%），
	从基准的大小 basePointSize（点）和现在的倍率 zoom 移动 steps 级。
	大小在 1～72 点之间，按 unit 点取整（原版 0.5 点；Mac 版的排版字体只能用整数点，界面层传 1）。
	不能再大（小）时 nullopt。
*/
std::optional<FontZoom> ZoomFontSize(double basePointSize, double zoom, std::int32_t steps, double unit = 0.5);

//! 折り返し方法。数值与原版的 WRAP_NO_TEXT_WRAP 等相同
enum class WrapMethod : std::uint8_t {
	None         = 0,	//!< 折り返さない
	SettingWidth = 1,	//!< 指定桁で折り返す（类型别设置的桁数）
	WindowWidth  = 2,	//!< 右端で折り返す
};

//! TAB 记号的样式。数值与原版的 ETabArrow 相同
enum class TabMark : std::uint8_t {
	String     = 0,	//!< 文字指定（类型别设置的「TAB表示」文字）
	ShortArrow = 1,	//!< 短い矢印
	LongArrow  = 2,	//!< 長い矢印
};

//! 编辑画面的显示设置：类型别设置里与排版、记号有关的部分
struct ViewSettings {
	WrapMethod wrapMethod = WrapMethod::SettingWidth;	//!< 现在的折り返し方法
	std::int32_t wrapColumns = 80;		//!< 现在的折り返し桁数
	std::int32_t typeWrapColumns = 80;	//!< 类型别设置的折り返し桁数（「指定桁で折り返す」用）
	std::int32_t tabColumns = 4;		//!< TAB 幅（桁）
	std::int32_t columnSpacing = 0;		//!< 文字と文字の隙間（点）
	std::int32_t lineSpacing = 1;		//!< 行間のすきま（点）
	bool showLineNumbers = true;		//!< 行番号
	bool lineNumberPerLogicalLine = true;	//!< 行番号を改行単位で数える（false は折り返し単位）
	std::int32_t lineNumberMinDigits = 3;	//!< 行番号の最小桁数
	bool showTab = true;				//!< TAB 記号
	TabMark tabMark = TabMark::String;
	Text tabString;						//!< TabMark::String のときの文字
	bool showSpace = false;				//!< 半角空白
	bool showFullWidthSpace = true;		//!< 日本語空白（全角空白）
	bool showEol = true;				//!< 改行記号
	bool showWrapMark = true;			//!< 折り返し記号
	bool showEof = true;				//!< EOF 記号
	bool hideHanging = false;			//!< ぶら下げを隠す
	bool hangEol = false;				//!< 改行文字をぶら下げる
	bool hangPunctuation = false;		//!< 句読点ぶら下げ
};

/*!
	排版位置（原版的 CLayoutPoint）：排版行的行号（从 0 开始）和横向位置。
	横向位置的单位是点（与原版的像素相同），从排版行的左端量起，包括行首的缩进。
*/
struct LayoutPosition {
	std::int32_t line = 0;
	std::int32_t x = 0;

	friend bool operator==(const LayoutPosition&, const LayoutPosition&) = default;
};

//! 一个排版行（原版的 CLayout）：逻辑行自动换行后的一段
struct LayoutLine {
	Position start;				//!< 这一段在逻辑行里的开始位置
	std::int32_t length = 0;	//!< 长度（UTF-16，不含换行符）
	Eol eol = Eol::None;		//!< 逻辑行的最后一段带换行符，其他段是 None
	std::int32_t indent = 0;	//!< 行首的缩进（点）。折り返し行の字下げ
};

// ---------------------------------------------------------------------------
// 颜色（第 28 步）
// ---------------------------------------------------------------------------

/*!
	颜色的种类。数值与原版的 EColorIndexType（COLORIDX_TEXT 等）相同。
	Comment 以后是语法颜色（第 33 步，类型别设置「カラー」页的后半）。
*/
enum class ColorIndex : std::uint8_t {
	Text = 0,				//!< テキスト
	Ruler,					//!< ルーラー
	Caret,					//!< キャレット
	CaretIme,				//!< IMEキャレット
	CaretLineBackground,	//!< カーソル行背景色
	CaretLineUnderline,		//!< カーソル行アンダーライン
	CursorColumnLine,		//!< カーソル位置縦線
	NoteLine,				//!< ノート線
	LineNumber,				//!< 行番号
	LineNumberModified,		//!< 行番号（変更行）
	EvenLineBackground,		//!< 奇数行の背景色
	Tab,					//!< TAB記号
	Space,					//!< 半角空白
	FullWidthSpace,			//!< 日本語空白
	ControlCode,			//!< コントロールコード
	Eol,					//!< 改行記号
	WrapMark,				//!< 折り返し記号
	VerticalLine,			//!< 指定桁縦線
	Eof,					//!< EOF記号
	Digit,					//!< 半角数値
	BracketPair,			//!< 対括弧
	Select,					//!< 選択範囲
	Search,					//!< 検索文字列（第 32 步）
	Search2,				//!< 検索文字列2（単語単位で探す时第 2 个单词）
	Search3,				//!< 検索文字列3
	Search4,				//!< 検索文字列4
	Search5,				//!< 検索文字列5
	// 语法颜色（第 33 步）
	Comment,				//!< コメント（行コメント、ブロックコメント）
	SingleQuote,			//!< シングルクォーテーション文字列
	DoubleQuote,			//!< ダブルクォーテーション文字列
	Heredoc,				//!< ヒアドキュメント
	Url,					//!< URL
	Keyword1,				//!< 強調キーワード1
	Keyword2,				//!< 強調キーワード2
	Keyword3,				//!< 強調キーワード3
	Keyword4,				//!< 強調キーワード4
	Keyword5,				//!< 強調キーワード5
	Keyword6,				//!< 強調キーワード6
	Keyword7,				//!< 強調キーワード7
	Keyword8,				//!< 強調キーワード8
	Keyword9,				//!< 強調キーワード9
	Keyword10,				//!< 強調キーワード10
	Regex1,					//!< 正規表現キーワード1
	Regex2,					//!< 正規表現キーワード2
	Regex3,					//!< 正規表現キーワード3
	Regex4,					//!< 正規表現キーワード4
	Regex5,					//!< 正規表現キーワード5
	Regex6,					//!< 正規表現キーワード6
	Regex7,					//!< 正規表現キーワード7
	Regex8,					//!< 正規表現キーワード8
	Regex9,					//!< 正規表現キーワード9
	Regex10,				//!< 正規表現キーワード10
	DiffAppend,				//!< DIFF差分表示(追加)
	DiffChange,				//!< DIFF差分表示(変更)
	DiffDelete,				//!< DIFF差分表示(削除)
	Mark,					//!< ブックマーク
	PageView,				//!< ミニマップの表示範囲
};

/*!
	一种颜色的设置（原版的 ColorInfo：类型别设置「カラー」页的一行）。
	颜色是 0xRRGGBB。文字色和背景色相同时，原版把它当作「反転表示」或半透明处理
	（CEditView::GetTextColorByColorInfo2），选择范围的默认值就是这样。
*/
struct ColorSetting {
	bool display = false;		//!< 表示
	bool bold = false;			//!< 太字
	bool underline = false;		//!< 下線
	std::uint32_t text = 0;		//!< 文字色
	std::uint32_t back = 0;		//!< 背景色
};

// ---------------------------------------------------------------------------
// 编辑命令（第 29 步）
// ---------------------------------------------------------------------------

/*!
	矩形范围（原版 TwoPointToRect 的结果 CLayoutRect）：排版行 top～bottom（包括 bottom），
	横向 left～right（点，与 LayoutPosition::x 相同）。left == right 是宽度 0 的矩形选择。
*/
struct BoxRange {
	std::int32_t top = 0;
	std::int32_t bottom = 0;
	std::int32_t left = 0;
	std::int32_t right = 0;

	friend bool operator==(const BoxRange&, const BoxRange&) = default;
};

//! 缩进的种类（原版的 EIndentType）
enum class IndentKind : std::uint8_t {
	None  = 0,	//!< 普通的输入（矩形选择中输入文字时）
	Tab   = 1,	//!< TABインデント
	Space = 2,	//!< SPACEインデント
};

/*!
	编辑用的设置：共通设置「編集」页和类型别设置的一部分。
	剪贴板、TAB 键、改行时的处理按这些设置决定（与原版相同）。
*/
struct EditSettings {
	bool copyWithoutSelection = true;		//!< 選択なしでコピーを可能にする（m_bEnableNoSelectCopy）
	bool lineModePaste = true;				//!< ラインモード貼り付けを可能にする（m_bEnableLineModePaste）
	bool clearSelectionAfterCopy = false;	//!< コピーしたら選択解除（m_bCopyAndDisablSelection）
	bool autoColumnPaste = true;			//!< 矩形コピーのテキストは常に矩形貼り付け（m_bAutoColumnPaste）
	bool convertEolOnPaste = false;			//!< 改行コードを変換して貼り付ける（m_bConvertEOLPaste）
	bool addEolAtWrapOnCopy = false;		//!< 折り返し行に改行を付けてコピー（m_bAddCRLFWhenCopy）
	bool insertSpacesForTab = false;		//!< 类型别「スペースの挿入」：TAB 键输入空白（m_bInsSpace）
	bool autoIndent = true;					//!< 类型别「オートインデント」（m_bAutoIndent）
	bool boxSelectLock = true;				//!< 矩形選択移動で選択をロックする（m_bBoxSelectLock，第 34 步）
};

// ---------------------------------------------------------------------------
// 命令
// ---------------------------------------------------------------------------

/*!
	功能编号。数值与原版的 EFunctionCode 相同（sakura_core/Funccode_x.hsrc），
	菜单、按键分配、宏里的编号可以直接使用。
*/
using FunctionCode = std::int32_t;
namespace command {
	constexpr FunctionCode FileSave       = 30103;	//!< F_FILESAVE（上書き保存）
	constexpr FunctionCode Undo           = 30210;	//!< F_UNDO
	constexpr FunctionCode Redo           = 30211;	//!< F_REDO
	constexpr FunctionCode NewLineCRLF    = 31081;	//!< F_CHGMOD_EOL_CRLF（入力改行コード指定）
	constexpr FunctionCode NewLineLF      = 31082;	//!< F_CHGMOD_EOL_LF
	constexpr FunctionCode NewLineCR      = 31083;	//!< F_CHGMOD_EOL_CR
	constexpr FunctionCode NewLineNEL     = 31084;	//!< F_CHGMOD_EOL_NEL
	constexpr FunctionCode NewLinePS      = 31085;	//!< F_CHGMOD_EOL_PS
	constexpr FunctionCode NewLineLS      = 31086;	//!< F_CHGMOD_EOL_LS
	constexpr FunctionCode ChangeInsMode  = 31001;	//!< F_CHGMOD_INS（挿入／上書きモード切り替え，第 34 步）
}

/*!
	功能的名字（与原版的菜单、按键分配对话框里的名字相同，日文）。
	编号不存在时是空。界面的多语言化在第 48 步。
*/
Text CommandName(FunctionCode code);

// ---------------------------------------------------------------------------
// 菜单与按键分配（第 34 步）
// ---------------------------------------------------------------------------

//! 主菜单的项目种类（原版 EMainMenuType）
enum class MenuItemType : std::uint8_t {
	Submenu = 0,	//!< 子菜单（T_NODE）
	Command = 1,	//!< 命令（T_LEAF）
	Separator = 2,	//!< 分隔线（T_SEPARATOR）
	Special = 3,	//!< 特殊项目（T_SPECIAL：最近使ったファイル、ウィンドウリスト等的列表）
};

//! 主菜单的一项（原版共通设置「メインメニュー」：CMainMenu）
struct MenuItem {
	std::int32_t level = 0;		//!< 0 是菜单栏，1 是它下面，2 是子菜单里
	MenuItemType type = MenuItemType::Command;
	FunctionCode code = 0;		//!< 功能编号（子菜单是菜单名的编号，如 F_FILE_TOPMENU）
	Text name;					//!< 名字：设置里的名字，没有时是 CommandName(code)（原版 LayoutMainMenu）
	Text accessKey;				//!< アクセスキー（Mac 版不显示）
};

/*!
	主菜单的结构（原版共通设置「メインメニュー」，默认是 MainMenu.ini）。按菜单的顺序排列。
	sakura.ini 里改过时就是改过的结构。
*/
std::vector<MenuItem> MainMenu();

//! 按键的修饰键（原版按键分配表的 Shift / Ctrl / Alt。数值的组合是原版 m_nFuncCodeArr 的下标）
namespace keymod {
	constexpr std::uint8_t Shift = 1;
	constexpr std::uint8_t Ctrl  = 2;
	constexpr std::uint8_t Alt   = 4;
}

//! 一个按键分配（原版共通设置「キー割り当て」）
struct KeyBinding {
	std::uint16_t keyCode = 0;	//!< 键码（原版的 Windows 虚拟键码 VK_*。字母、数字是大写的 ASCII）
	std::uint8_t modifiers = 0;	//!< keymod 的组合
	FunctionCode code = 0;
	Text keyName;				//!< 键的名字（原版的「Home」「F3」「A」等）
};

/*!
	键盘的全部按键分配（原版共通设置「キー割り当て」，默认是 CKeyBind.cpp 的 KeyDataInit）。
	只有分配了功能的组合。鼠标（双击、滚轮等）不包括。按原版表的顺序。
*/
std::vector<KeyBinding> KeyBindings();

//! 这个键（keyCode + modifiers）分配的功能（原版 CKeyBind::GetFuncCode）。没有分配时是 0
FunctionCode FunctionForKey(std::uint16_t keyCode, std::uint8_t modifiers);

//! 一个功能（共通設定的「機能」列表的一行）
struct FunctionInfo {
	FunctionCode code = 0;
	Text name;
};

/*!
	共通設定 > キー割り当て・メインメニュー・ツールバー・カスタムメニュー 的编辑（第 41 步）。
	与原版 CPropCommon 相同，Create 时复制核心库现在的共通設定（m_Common），这些页都在这个复制上编辑：
	在カスタムメニュー 页改的名字，キー割り当て 页的「機能」列表马上用（原版 CFuncLookup 看 m_Common）。
	OK 时把 IniValues(节) 的值写进 sakura.ini 的那一节（SetCommonSettings），与原版读入 sakura.ini 时相同地换掉。
*/
class CommandSettingsEditor {
public:
	static std::unique_ptr<CommandSettingsEditor> Create();
	~CommandSettingsEditor();
	CommandSettingsEditor(const CommandSettingsEditor&) = delete;
	CommandSettingsEditor& operator=(const CommandSettingsEditor&) = delete;

	// ----- 機能の検索（原版 CFuncLookup）-----
	//! 「種別」：原版的分类 + 外部マクロ + カスタムメニュー + プラグイン（SetCategory2Combo）
	std::vector<Text> FunctionCategories() const;
	//! 「機能」：这个分类的功能（原版 SetListItem：没有定义的不要。Mac 版プラグイン 是空的）
	std::vector<FunctionInfo> Functions(std::int32_t category) const;
	//! 功能的名字（原版 Funccode2Name：カスタムメニュー的名字、外部マクロ的名字用这个复制的）
	Text FunctionName(FunctionCode code) const;

	// ----- キー割り当て（原版 CPropKeybind）-----
	//! 键的个数和名字（原版 m_pKeyNameArr、m_nKeyNameArrNum：鼠标的「ダブルクリック」等也在里面）
	std::int32_t KeyCount() const;
	Text KeyName(std::int32_t key) const;
	//! 这个键 + keymod 的组合的功能（原版 m_nFuncCodeArr[i]。0 是未割当）
	FunctionCode KeyFunction(std::int32_t key, std::uint8_t modifiers) const;
	//! 割当（code）・解除（0）
	void SetKeyFunction(std::int32_t key, std::uint8_t modifiers, FunctionCode code);
	//! 機能に割り当てられているキー（原版 CKeyBind::GetKeyStrList：「Shift+Ctrl+F3」等，デフォルト機能は含めない）
	std::vector<Text> AssignedKeys(FunctionCode code) const;
	//! キー割り当て的インポート・エクスポート（*.key，原版 CImpExpKeybind）。message 是原版的消息
	bool ImportKeyBind(const Text& path, Text& message);
	bool ExportKeyBind(const Text& path, Text& message);

	// ----- メインメニュー（原版 CPropMainMenu。第 41 步第 2 个 PR）-----
	//! 菜单的一项（原版 SMainMenuWork + 层次）
	struct MainMenuEntry {
		std::int32_t level = 0;	//!< 0 是菜单栏
		bool isNode = false;	//!< 子菜单（功能编号不是 F_NODE 的子菜单也是）
		FunctionCode code = 0;	//!< 功能编号（F_NODE 0、F_SEPARATOR 1、特別機能、命令）
		Text name;				//!< 显示的名字（原版 SetData：命令是功能名，区切線是「――」，子菜单是设置的名字）
		Text accessKey;			//!< アクセスキー（0 或 1 个字）
	};
	//! 复制里的メインメニュー（原版 SetData）
	std::vector<MainMenuEntry> MainMenuEntries() const;
	bool MainMenuKeyParentheses() const;
	/*!
		页的内容写进复制（原版 GetData）：每一项的种类按功能编号决定，菜单栏的项目最多 MAX_MAINMENU_TOP 个，
		没有「共通設定」时加在最后（原版的 auto_add）。全部写进去时 true
	*/
	bool SetMainMenu(const std::vector<MainMenuEntry>& entries, bool keyParentheses);
	//! 初期設定：内置的 MainMenu.ini（原版 IDR_MENU1）
	void InitializeMainMenu();
	//! 「特別機能」的分类名和功能（原版 STR_SPECIAL_FUNC、nsFuncCode::pnFuncList_Special）
	Text SpecialFunctionCategory() const;
	std::vector<FunctionInfo> SpecialFunctions() const;
	//! メインメニュー的インポート・エクスポート（*.ini，原版 CImpExpMainMenu）
	bool ImportMainMenu(const Text& path, Text& message);
	bool ExportMainMenu(const Text& path, Text& message);

	// ----- カスタムメニュー（原版 CPropCustmenu。第 41 步第 3 个 PR）-----
	//! カスタムメニュー的一项：功能（0 是区切線）和アクセスキー（ASCII 1 个字，没有时是 0）
	struct CustomMenuItem {
		FunctionCode code = 0;
		char16_t accessKey = 0;
	};
	//! カスタムメニュー的个数（MAX_CUSTOM_MENU：0 是右クリックメニュー，最后是タブメニュー）和一个的项目数的上限
	std::int32_t CustomMenuCount() const;
	std::int32_t MaxCustomMenuItems() const;
	//! 显示的名字（原版 Custmenu2Name：没有设置名字时「右クリックメニュー」「カスタムメニュー1」等）和设置的名字
	Text CustomMenuDisplayName(std::int32_t menu) const;
	Text CustomMenuName(std::int32_t menu) const;
	void SetCustomMenuName(std::int32_t menu, const Text& name);
	bool CustomMenuIsSubmenu(std::int32_t menu) const;
	void SetCustomMenuIsSubmenu(std::int32_t menu, bool on);
	std::vector<CustomMenuItem> CustomMenuItems(std::int32_t menu) const;
	//! 换掉这个菜单的项目（多于上限的不要）
	void SetCustomMenuItems(std::int32_t menu, const std::vector<CustomMenuItem>& items);
	//! カスタムメニュー的インポート・エクスポート（*.mnu，原版 CImpExpCustMenu）
	bool ImportCustomMenu(const Text& path, Text& message);
	bool ExportCustomMenu(const Text& path, Text& message);

	// ----- ツールバー（原版 CPropToolBar。第 41 步第 3 个 PR）-----
	//! ツールバーボタンの種類（原版 TBBUTTON の fsStyle と idCommand）
	enum class ToolbarButtonKind : std::uint8_t { Button, Separator, Wrap, Unknown };
	//! ボタン番号（sakura.ini の nTBB[nnn]）のボタン
	struct ToolbarButtonInfo {
		ToolbarButtonKind kind = ToolbarButtonKind::Unknown;
		FunctionCode code = 0;
		std::int32_t icon = -1;	//!< mytool.bmp のアイコン番号（16×16，横 32 個）
	};
	//! 复制里的ツールバー的ボタン番号（原版 m_nToolBarButtonIdxArr）
	std::vector<std::int32_t> ToolbarButtons() const;
	bool ToolbarIsFlat() const;
	void SetToolbar(const std::vector<std::int32_t>& buttons, bool flat);
	ToolbarButtonInfo ToolbarButton(std::int32_t number) const;
	//! この機能のボタン番号（原版 FindToolbarNoFromCommandId）。ボタンが無い機能は -1
	std::int32_t ToolbarButtonNumber(FunctionCode code) const;
	//! 区切・折返のボタン番号（TOOLBAR_BUTTON_F_SEPARATOR、TOOLBAR_BUTTON_F_TOOLBARWRAP）
	std::int32_t ToolbarSeparatorNumber() const;
	std::int32_t ToolbarWrapNumber() const;

	/*!
		sakura.ini 的这一节的值（项目, 值）。能用的节：KeyBind、MainMenu、CustMenu、Toolbar。
		写法与原版保存 sakura.ini 时相同。
	*/
	std::vector<std::pair<Text, Text>> IniValues(const Text& section) const;

private:
	CommandSettingsEditor();
	struct Impl;
	std::unique_ptr<Impl> m_impl;
};

// ---------------------------------------------------------------------------
// アウトライン解析（第 42 步。原版 Command_FUNCLIST、CDocOutline、CDlgFuncList 的数据部分）
// ---------------------------------------------------------------------------

//! アウトライン解析方法（数值与原版的 EOutlineType 相同）
enum class OutlineType : std::int32_t {
	Default = -1,		//!< 类型别设置的「アウトライン解析方法」
	C = 0,
	CCpp = 1,			//!< C/C++（按扩展名决定 C 或 C++）
	PlSql = 2,
	Text = 3,
	Java = 4,
	Cobol = 5,
	Asm = 6,
	Perl = 7,
	VisualBasic = 8,
	WzText = 9,			//!< WZ階層付テキスト
	Html = 10,
	Tex = 11,
	RuleFile = 12,		//!< ルールファイル
	Python = 13,
	Erlang = 14,
	Xml = 15,
	Cpp = 16,
	Bookmark = 18,		//!< ブックマークの一覧
	FileTree = 20,		//!< ファイルツリー
	Tree = 100,			//!< 汎用ツリー（プラグイン）
	TreeTagJump = 101,	//!< 汎用ツリー(タグジャンプ付き)
	ClassTree = 200,	//!< 汎用クラスツリー
	List = 300,			//!< 汎用リスト
};

//! ツリーの順序（原版的「順序」：SORTTYPE_DEFAULT 等。数值相同）
enum class OutlineSort : std::int32_t {
	Default = 0,		//!< デフォルト
	DefaultDesc = 1,	//!< デフォルト(降順)
	AtoZ = 2,			//!< アルファベット順
	ZtoA = 3,			//!< アルファベット(降順)
};

//! 解析结果的一项（原版 CFuncInfo）
struct OutlineItem {
	std::int32_t line = 0;			//!< 逻辑行（1 开始。原版 m_nFuncLineCRLF）
	std::int32_t column = 0;		//!< 逻辑桁（1 开始。原版 m_nFuncColCRLF）
	std::int32_t layoutLine = 0;	//!< 排版行（1 开始。原版 m_nFuncLineLAYOUT）
	std::int32_t layoutColumn = 0;	//!< 排版桁（1 开始）
	Text name;						//!< 原版 m_cmemFuncName
	Text fileName;					//!< 别的文件的项目（原版 m_cmemFileName。没有时空）
	std::int32_t info = 0;			//!< 原版 m_nInfo（FL_OBJ_FUNCTION 等）
	std::int32_t depth = 0;			//!< 原版 m_nDepth
};

//! ツリーの一つの項目（原版 CDlgFuncList 在 TreeView 里加的项目）
struct OutlineNode {
	Text label;
	std::int32_t item = -1;		//!< items 的下标。クラス名、グローバル 等的项目是 -1
	std::int32_t order = 0;		//!< 加入的顺序（原版的 lParam。「デフォルト」的顺序）
	bool expanded = false;		//!< 打开窗口时展开着（原版：Java/C++ 等的第一层）
	std::vector<OutlineNode> children;
};

//! リストの一行（原版 CDlgFuncList 的 ListView 的一行）
struct OutlineRow {
	std::int32_t item = 0;		//!< items 的下标
	std::int32_t line = 0;		//!< 「行」（タイプ別設定「行番号の表示」：改行単位 / 折り返し単位）
	std::int32_t column = 0;	//!< 「桁」
	Text name;					//!< 「関数名」
	Text remark;				//!< 第 4 列（「関数」「宣言」等）
};

//! アウトライン解析的结果（原版 Command_FUNCLIST 的解析 + CDlgFuncList::SetData）
struct OutlineResult {
	OutlineType type = OutlineType::Text;		//!< 实际用的解析方法（C/C++ 时是 C 或 Cpp）
	OutlineType listType = OutlineType::Text;	//!< 一覧的形式（原版 m_nListType）
	Text title;									//!< 窗口标题（原版 SetWindowText）
	Text filePath;								//!< 解析的文件（原版 m_szFilePath。新文件时空）
	bool isTree = true;							//!< ツリー（false 是リスト）
	std::vector<OutlineItem> items;
	std::vector<OutlineNode> tree;				//!< ツリー时
	std::vector<OutlineRow> rows;				//!< リスト时（已经按「行」等排好）
	Text columnTitles[4];						//!< リスト的列名（排序的列后面有「 *」）
	Text clipText;								//!< 「コピー」的文字（原版 m_cmemClipText）
	OutlineSort sort = OutlineSort::Default;	//!< ツリー的顺序（タイプ別設定 nOutlineSortType）
	std::int32_t sortColumn = 0;				//!< リスト的排序列（nOutlineSortCol）
	bool sortDescending = false;				//!< リスト的降順（bOutlineSortDesc）
	bool lineNumIsCRLF = true;					//!< 行番号は改行単位（タイプ別設定 bLineNumIsCRLF）
};

/*!
	ツリーの順序を変える（原版 CDlgFuncList::SortTree：所有层次。アルファベット順 是不区分大小写的比较，
	相同时按加入的顺序）。result.sort 也改。
*/
void SortOutlineTree(OutlineResult& result, OutlineSort sort);

/*!
	リストを並べ替える（原版 SortListView：0「行」、1「桁」、2「関数名」、3 第 4 列）。
	列名（columnTitles）也改，result.sortColumn、sortDescending 也改。
*/
void SortOutlineRows(OutlineResult& result, std::int32_t column, bool descending);

/*!
	光标所在的项目（原版 CDlgFuncList::GetFuncInfoIndex）：光标之前最后一个项目，
	光标在第一个项目之前时是第一个项目。没有项目时 -1。
	@param layoutLine, layoutColumn 光标的排版位置（1 开始）
*/
std::int32_t OutlineItemAt(const OutlineResult& result, std::int32_t layoutLine, std::int32_t layoutColumn);

/*!
	ツリー里这个项目的位置：从根开始的下标（tree[p0].children[p1]…）。没有时空。
*/
std::vector<std::int32_t> OutlineNodePath(const OutlineResult& result, std::int32_t item);

// ---------------------------------------------------------------------------
// 文档
// ---------------------------------------------------------------------------

/*!
	一个文档（一个文件）。原版的 CEditDoc 中不依赖窗口的部分：
	行数据（CDocLineMgr）、撤销缓冲（COpeBuf）、文件信息（CDocFile）、类型别设置。

	排版（自动换行）在第 27 步加入（下面的“排版”）。光标、选择范围、绘制属于编辑画面，不在这里（第 28～30 步）。
	同一个 Document 只能在一个线程里使用。
*/
class Document {
public:
	//! 新文档（无题，空的一行）。核心库需要已经启动（Startup）
	static std::unique_ptr<Document> Create();
	~Document();
	Document(const Document&) = delete;
	Document& operator=(const Document&) = delete;

	// ----- 打开、保存 -----

	/*!
		打开文件。原来的内容和撤销记录都丢弃。
		与原版（CReadManager）相同：按文件名决定类型别设置，自动识别时用类型别设置的编码设置；
		BOM 的有无从文件得到。失败时文档变成空的。
	*/
	Result Open(const Text& path, const OpenOptions& options = {});

	/*!
		保存到 path（与原版 CWriteManager 相同：第一行前加 BOM，逐行转换编码）。
		成功后 path 成为这个文档的文件名，修改标记清除。
		options.eol 指定时先统一换行符（与原版相同，可以撤销）。
	*/
	Result SaveAs(const Text& path, const SaveOptions& options = {});

	//! 保存到打开时的文件（上書き保存）。新文件（没有路径）时返回 InvalidArgument
	Result Save();

	/*!
		閉じて(無題)（原版 CDocFileOperation::FileClose → CEditDoc::InitDoc，第 34 步）：
		内容、撤销记录、文件名都清除，变成新文档（与 Create 相同的状态）。保存的确认、历史的登记由界面层先做。
	*/
	void CloseToUntitled();

	//! 用 options 保存之前的检查（原版 CCodeChecker::OnCheckSave）。不改文档
	SaveCheck CheckSave(const SaveOptions& options = {}) const;

	/*!
		打开时从历史恢复的光标位置（第 31 步）。共通设置「カーソル位置を復元する」关掉时、历史里没有时是 nullopt。
		界面层打开后把光标放到这里。
	*/
	std::optional<RestoredView> GetRestoredView() const;

	/*!
		把现在的状态（光标位置、表示域、编码、类型）登记到「最近使ったファイル」，同时登记文件夹
		（原版 CMruListener：保存后、关闭前、打开后）。新文件（没有路径）时什么也不做。
	*/
	void AddToRecent(const Position& caret, std::int32_t viewTopLine);

	const FileInfo& GetFileInfo() const;
	bool IsModified() const;

	/*!
		文字コードセット指定（原版 Command_CHG_CHARSET → CDocFile::SetCodeSetChg，第 34 步）：
		下次保存时用的编码和 BOM。不能加 BOM 的编码时 BOM 是 false。内容不变。
	*/
	void SetEncoding(Encoding encoding, bool bom);

	//! 文字コードセット指定改过打开时的编码或 BOM（原版 CDocFile::IsChgCodeSet。新文件时 false）
	bool IsEncodingChanged() const;

	// ----- 内容 -----

	//! 行数。空文档是 0 行（与原版 CDocLineMgr 相同）
	std::int32_t LineCount() const;

	//! 一行的文字。withEol 为 true 时包括换行符。行号超出范围时是空
	Text GetLine(std::int32_t line, bool withEol = false) const;

	//! 一行的长度（不含换行符，UTF-16 单位）。不取出文字（第 36 步：超长行）。行号超出范围时是 0
	std::int32_t LineLength(std::int32_t line) const;

	//! 文字或排版变了的次数（编辑、撤销、重新排版、打开时增加）。界面层用来判断缓存是否还有效（第 36 步）
	std::uint64_t ChangeCount() const;

	//! 行的换行符（最后一行没有换行时是 Eol::None）
	Eol GetLineEol(std::int32_t line) const;

	//! 全文（包括换行符）
	Text GetText() const;

	//! 范围内的文字
	Text GetText(const Range& range) const;

	//! 文档末尾的位置（最后一行的末尾；最后一行以换行结束时是下一行的开头）
	Position EndPosition() const;

	/*!
		全文（包括换行符）的长度、全文的下标和位置的换算（第 36 步）。
		输入法（NSTextInputClient）用全文的下标说话。不做出全文，按行的长度加起来，大文件也快。
	*/
	std::int64_t TextLength() const;
	//! 位置 → 全文的下标（行、列超出范围时收到范围内）
	std::int64_t OffsetOf(const Position& position) const;
	//! 全文的下标 → 位置（落在换行符中间时取换行符之前，超出时是文档末尾）
	Position PositionAtOffset(std::int64_t offset) const;

	// ----- 编辑 -----

	/*!
		把 range 换成 text（插入时 range 为空，删除时 text 为空）。
		text 里的换行符原样插入。作为一次操作记入撤销缓冲。
		@param[out] pNewEnd 插入的文字之后的位置（原版的光标移动位置）
	*/
	Result Replace(const Range& range, const Text& text, Position* pNewEnd = nullptr);
	Result Insert(const Position& at, const Text& text, Position* pNewEnd = nullptr);
	Result Delete(const Range& range);

	/*!
		把多次编辑合成撤销的一步（原版的 COpeBlk）。
		BeginEdit 和 EndEdit 成对调用，可以嵌套。
	*/
	void BeginEdit();
	void EndEdit();

	bool CanUndo() const;
	bool CanRedo() const;
	//! 撤销。@param[out] pCaret 撤销后的光标位置（原版 Command_UNDO 的移动位置）
	Result Undo(Position* pCaret = nullptr);
	Result Redo(Position* pCaret = nullptr);

	//! 输入时用的换行符（原版的“入力改行コード”，状态栏显示的那个）
	Eol GetNewLineEol() const;
	void SetNewLineEol(Eol eol);

	// ----- 查找、替换 -----

	/*!
		从 from 开始查找（与原版 CSearchAgent::SearchWord 相同）。
		Forward 时找 from 之后的第一个，Backward 时找 from 之前的最后一个。
		找不到时是 std::nullopt。正则表达式有错误时也是 std::nullopt（GetLastSearchError 取得原因）。
	*/
	std::optional<Range> Find(const Text& pattern, const Position& from,
							  SearchDirection direction = SearchDirection::Forward,
							  const SearchOptions& options = {});

	//! 全文中的所有匹配
	std::vector<Range> FindAll(const Text& pattern, const SearchOptions& options = {});

	/*!
		全部替换（与原版“すべて置換”的一括置换相同。正则表达式时 replacement 可以用 $1、$& 等）。
		作为一次操作记入撤销缓冲。
		@return 替换的个数。正则表达式有错误时是 -1
	*/
	std::int32_t ReplaceAll(const Text& pattern, const Text& replacement, const SearchOptions& options = {});

	//! 最近一次查找、替换的正则表达式错误（没有错误时是空）
	Text GetLastSearchError() const;

	// ----- 查找、替换命令（第 32 步） -----
	//
	// 与原版 CViewCommander 的同名命令相同（cmd/CViewCommander_Search.cpp）。
	// 原版在排版位置上处理，这里在逻辑位置上处理（原版的 bFastMode 也是这样），结果相同。

	//! 次を検索（原版 Command_SEARCH_NEXT）：从选择的末尾（没有选择时从光标）往后找
	SearchResult SearchNext(const Text& key, const SearchOptions& options, const SearchView& view, bool searchAll);

	//! 前を検索（原版 Command_SEARCH_PREV）：从光标往前找
	SearchResult SearchPrev(const Text& key, const SearchOptions& options, const SearchView& view, bool searchAll);

	/*!
		置換（原版 Command_REPLACE）：从选择的开头找下一个，换掉，再找下一个。
		作为撤销的一步。
	*/
	ReplaceResult ReplaceNext(const Text& key, const Text& replacement, const ReplaceOptions& options, const SearchView& view);

	/*!
		すべて置換（原版 Command_REPLACE_ALL）。options.selectedArea 并且有选择时只换选择范围里的，
		之后的选择是换了以后的范围；否则换整个文件，光标在最后换的地方后面。作为撤销的一步。
	*/
	ReplaceResult ReplaceAll(const Text& key, const Text& replacement, const ReplaceOptions& options, const SearchView& view);

	/*!
		指定行へジャンプ（原版 Command_JUMP）：跳转后的光标（行首）。文档是空的时是 nullopt（原版 ErrorBeep）。
	*/
	std::optional<Position> JumpPosition(const JumpOptions& options) const;

	/*!
		这一逻辑行里要用「検索文字列」的颜色显示的部分（原版 CColor_Found + CEditView::IsSearchString）。
		类型别设置里「検索文字列」的颜色都不显示时、条件有错误时是空。长度 0 的匹配不返回。
	*/
	std::vector<SearchMark> SearchMarks(std::int32_t line, const Text& key, const SearchOptions& options);

	/*!
		这一逻辑行的语法颜色（第 33 步：原版 CEditView::DrawLogicLine / GetColorIndex 的色分け）。
		从排版时记下的行首状态（跨行的块注释、字符串、ヒアドキュメント）开始，按原版的顺序
		（正規表現キーワード、ヒアドキュメント、ブロックコメント1・2、行コメント、引用符、URL、半角数値、
		強調キーワード）判断每个文字的颜色。只返回不是「テキスト」的部分，按位置排列，不包括换行符。
		类型别设置里所有的语法颜色都不显示时是空（原版 IsSkipBeforeLayout）。
		颜色的显示与否在这里已经考虑，返回的颜色画面直接用 GetColor 的设置。
	*/
	std::vector<SyntaxColorRun> SyntaxColors(std::int32_t line);

	/*!
		光标所在的单词的范围（原版 CSearchAgent::WhereCurrentWord：查找对话框的初始文字、检索マークの切替え用）。
		没有单词时是 nullopt。
	*/
	std::optional<Range> WordRangeAt(const Position& position) const;

	// ----- 光标移动的目标（第 34 步） -----
	//
	// 光标、选择属于编辑画面，这里只算出原版的命令要移到的逻辑位置。

	/*!
		単語の左端／右端に移動（原版 Command_WORDLEFT / WORDRIGHT → CSearchAgent::PrevOrNextWord）。
		按共通設定「単語単位で移動するときに、単語の両端で止まる」。找不到时 nullopt（原版这时按一个字移动）。
	*/
	std::optional<Position> WordMoveTarget(const Position& position, bool left) const;

	/*!
		前／次の段落へ（原版 Command_GOPREVPARAGRAPH / GONEXTPARAGRAPH）的目标逻辑行。
		空行（只有空白、TAB、换行的行）和非空行的边界。按共通設定「段落単位で移動するときに、段落の両端で止まる」。
		不移动时 nullopt。
	*/
	std::optional<std::int32_t> ParagraphTarget(std::int32_t line, bool next) const;

	//! 次の変更行へ／前の変更行へ的结果
	struct ModifiedLineJump {
		Position position;
		bool wrapped = false;	//!< 绕到了文件的开头（末尾）（原版的「▼先頭から再検索しました」）
	};
	/*!
		次の変更行へ／前の変更行へ（原版 Command_MODIFYLINE_NEXT / PREV）：变更行的块的开头和末尾（下一行的开头）。
		按共通設定「先頭（末尾）から再検索する」绕回。找不到时 nullopt。
	*/
	std::optional<ModifiedLineJump> ModifiedLineTarget(const Position& position, bool next) const;

	/*!
		逻辑行 line 的 [from, to) 之间，缩进（空白、TAB，类型别设置「全角空白もインデント」时全角空白）之后第一个字的下标。
		只有缩进或换行时返回 from（原版 Command_GOLINETOP 的「行頭の空白を飛ばす」）。
	*/
	std::int32_t IndentEnd(std::int32_t line, std::int32_t from, std::int32_t to) const;

	// ----- 模式（第 34 步） -----

	//! 挿入モード（false 是上書きモード）。新文档按共通設定「挿入モード」（原版 CDocEditor 的 m_bInsMode）
	bool IsInsertMode() const;
	void SetInsertMode(bool insert);

	/*!
		上書きモードでの入力（原版的文字输入命令的上書き部分 → DelCharForOverwrite）：
		text 的每个字先删掉 at 处的一个字再插入。行末按共通設定「改行は上書きしない」，
		「文字幅に合わせてスペースを詰める」时用空白补齐宽度。作为撤销的一步。
		@param[out] pNewCaret 输入后的光标
	*/
	Result OverwriteText(const Position& at, const Text& text, Position* pNewCaret = nullptr);

	/*!
		現在のウィンドウ幅で折り返し（原版 Command_WRAPWINDOWWIDTH → CEditView::GetWrapMode）的新的折り返し桁数。
		width 是文字区域的宽度（点）。顺序是「ウィンドウ幅→最大値→設定値→ウィンドウ幅」。
		不能改变时 nullopt。界面层用 SetWrap(WrapMethod::SettingWidth, 桁数) 改变。
	*/
	std::optional<std::int32_t> WrapWindowWidthColumns(std::int32_t width) const;

	// ----- 命令 -----

	/*!
		执行命令。现在只能执行不需要编辑画面的命令（command 名字空间里的命令）：
		撤销、重做、上書き保存、输入换行符的切换。
		其他命令（光标移动、选择、剪贴板等）需要编辑画面，第 30 步起逐步加入，现在返回 NotSupported。
	*/
	Result ExecuteCommand(FunctionCode code);

	//! 现在能否执行（原版的 IsFuncEnable。例如没有可以撤销的操作时 Undo 是 false）
	bool IsCommandEnabled(FunctionCode code) const;

	//! 菜单是否打勾（原版的 IsFuncChecked：○○で開き直す（现在的编码）、入力改行コード、挿入モード）
	bool IsCommandChecked(FunctionCode code) const;

	//! 这个命令在 Mac 版是否已经移植
	static bool IsCommandSupported(FunctionCode code);

	// ----- 排版（第 27 步） -----

	/*!
		显示设置（类型别设置）。折り返し方法和桁数是现在用的值（SetWrap 改过时是改过的值）。
	*/
	ViewSettings GetViewSettings() const;

	/*!
		改变折り返し方法（原版的「折り返し方法」命令、窗口宽度变化时的「右端で折り返す」）并重新排版。
		columns 只在 SettingWidth、WindowWidth 时有用，小于 10 时按 10（与原版相同）。
		@return 排版有变化时 true
	*/
	bool SetWrap(WrapMethod method, std::int32_t columns);

	/*!
		「右端で折り返す」时，宽度 width（点）的文字区域可以放下的折り返し桁数
		（原版 CEditView::ViewColNumToWrapColNum：减去折り返し記号和ぶら下げ的宽度）。
	*/
	std::int32_t WrapColumnsForWidth(std::int32_t width) const;

	//! 按现在的字体和设置重新排版（字体、类型别设置改变后）
	void Relayout();

	/*!
		タイプ別設定 的第 typeIndex 个改了（第 40 步。原版 MYWM_CHANGESETTING の PM_CHANGESETTING_TYPE）：
		这个文档的类型是它，或者按文件名重新决定的类型是它时，按文件名重新决定类型、读新的设置、重新排版
		（原版 CEditDoc::OnChangeSetting）。折り返し方法的临时设置（F_TMPWRAP* 等）在类型没变、设置也没变时保留。
		重新读了时 true。
	*/
	bool ApplyTypeSettingChange(std::int32_t typeIndex);

	/*!
		タイプ別設定一覧で类型的顺序・个数变了（第 40 步。原版 PM_CHANGESETTING_TYPE2、PM_CHANGESETTING_ALL）：
		按 ID 找这个文档的类型的新编号。类型被删了时按文件名重新决定类型、重新排版，返回 true
	*/
	bool ApplyTypeListChange();

	/*!
		タイプ別設定一覧 的「一時適用」（原版 F_CHANGETYPE）：这个文档暂时用第 typeIndex 个类型，
		之后改了设置也不按文件名换回去（原版 LockDocumentType）。重新排版
	*/
	bool ChangeTypeTemporarily(std::int32_t typeIndex);

	//! 排版行数。空文档是 0 行（与原版 CLayoutMgr 相同）
	std::int32_t LayoutLineCount() const;

	//! 排版行。行号超出范围时是空的 LayoutLine
	LayoutLine GetLayoutLine(std::int32_t line) const;

	/*!
		排版行里每个字符的横向位置（点）：结果的第 i 个是排版行里第 i 个 UTF-16 字符的左端，
		最后多一个，是最后一个字符的右端。TAB 已经展开。与原版绘制时的位置相同（CMemoryIterator）。
		补充平面字符的后一半与前一半的位置相同。
	*/
	std::vector<std::int32_t> GetLayoutCharPositions(std::int32_t line) const;

	//! 逻辑位置 → 排版位置（原版 CLayoutMgr::LogicToLayout）
	LayoutPosition LogicToLayout(const Position& position) const;

	//! 排版位置 → 逻辑位置（原版 CLayoutMgr::LayoutToLogic）
	Position LayoutToLogic(const LayoutPosition& position) const;

	//! 半角一字的宽度（点，包括文字间隔）。TAB、行号、记号的宽度按它算
	std::int32_t CharWidth() const;

	/*!
		文字部分的宽度（点）：「折り返さない」时是最长的排版行的宽度，
		其他时候是折り返し桁数的宽度。横向滚动条用。
	*/
	std::int32_t LayoutWidth() const;

	// ----- 颜色（第 28 步） -----

	//! 类型别设置的颜色。种类超出范围时是全 0 的 ColorSetting
	ColorSetting GetColor(ColorIndex index) const;

	/*!
		这一逻辑行在上次保存（或打开）之后改过（原版 CModifyVisitor::IsLineModified，
		行号用「変更行」的颜色显示）。撤销回到保存时的内容后就不算改过。
	*/
	bool IsLineModified(std::int32_t line) const;

	// ----- 编辑命令（第 29 步） -----
	//
	// 选择范围和光标属于编辑画面（界面层），这里只提供需要排版、类型别设置的处理，
	// 与原版 CEditView、CViewCommander 的同名处理相同。编辑都记入撤销缓冲，
	// 一个函数的编辑是撤销的一步（外面有 BeginEdit 时合在外面的一步里）。

	//! 编辑用的设置
	EditSettings GetEditSettings() const;

	/*!
		复制普通选择范围的文字（原版 CEditView::GetSelectedData 的普通选择）。
		「折り返し行に改行を付けてコピー」时在折り返し的位置加入输入用的换行符。
	*/
	Text GetCopyText(const Range& range) const;

	//! 复制矩形范围的文字（GetSelectedData 的矩形选择）：每行后面加 CRLF
	Text GetBoxText(const BoxRange& box) const;

	/*!
		没有选择时复制的一行（原版 CEditView::CopyCurLine）：光标所在的排版行，带换行符。
		折り返した行在「折り返し行に改行を付けてコピー」时加 CRLF。
	*/
	Text GetLayoutLineCopyText(std::int32_t layoutLine) const;

	/*!
		在排版位置插入（原版 CEditView::InsertData_CEditView）：位置在行末的右边时，先用半角空白填到那里。
		@return 插入的文字之后的排版位置
	*/
	LayoutPosition InsertAtLayout(const LayoutPosition& at, const Text& text);

	/*!
		删除矩形范围的文字（原版 CEditView::DeleteData 的矩形选择）。范围里没有文字时什么也不改。
		@return 删除后的光标（矩形的左上，在文字的边界上）
	*/
	Position DeleteBox(const BoxRange& box);

	/*!
		矩形贴付（原版 Command_PASTEBOX）：text 的第 n 行插在 at 下面第 n 行的同一横向位置。
		文档的最后一行没有换行时先加入输入用的换行符。
	*/
	void PasteBox(const LayoutPosition& at, const Text& text);

	/*!
		矩形选择中的输入、缩进（原版 Command_INDENT ver0 的矩形选择）：在每行的选择范围之前插入 text。
		Tab、Space 时，空行和行末之后不插入；宽度 0 的矩形时把右端扩展到折り返し桁（原版 ver1），不插入。
		@param[out] pCaret 之后的光标
		@return 之后的矩形选择（插入的文字的宽度往右移）
	*/
	BoxRange IndentBox(const BoxRange& box, const Text& text, IndentKind kind, Position* pCaret = nullptr);

	/*!
		多行选择的缩进（原版 Command_INDENT 的「通常選択(複数行)」）：排版行 top～bottom（不包括 bottom）中
		逻辑行开头的行，在行首插入 text（空行不插入）。
		@return 之后的 bottom（折り返し变化时跟着变）
	*/
	std::int32_t IndentLines(std::int32_t top, std::int32_t bottom, const Text& text);

	/*!
		多行选择的逆缩进（原版 Command_UNINDENT）：行首是 ch 时删除一个。
		ch 是 TAB 时，行首是半角空白的话删除 TAB 幅以内的空白。
		@return 之后的 bottom
	*/
	std::int32_t UnindentLines(std::int32_t top, std::int32_t bottom, char16_t ch);

	/*!
		TAB 键输入的文字（原版 Command_INDENT）：「スペースの挿入」时是到下一个 TAB 位置的空白，否则是 TAB。
		@param x 插入位置的排版横向位置
	*/
	Text TabText(std::int32_t x) const;

	/*!
		改行时接在换行符后面的缩进（原版文字输入命令的オートインデント）：
		光标所在逻辑行开头的空白（TAB、半角空白、「日本語空白もインデント」时的全角空白、
		「その他のインデント対象文字」）到光标为止的部分。オートインデント关闭时是空。
	*/
	Text AutoIndentText(const Position& caret) const;

	/*!
		把文字里的换行符都换成输入用的换行符（原版 CViewCommander::ConvertEol，贴付时用）
	*/
	Text ConvertEolToNewLine(const Text& text) const;

	/*!
		删除一个排版行（原版 Command_DELETE_LINE，「切り取り」没有选择时用）。
		@param x 光标的横向位置（删除后光标尽量留在这个横向位置）
		@return 之后的光标
	*/
	Position DeleteLayoutLine(std::int32_t layoutLine, std::int32_t x);

	// ----- アウトライン解析（第 42 步） -----

	/*!
		アウトライン解析（原版 Command_FUNCLIST 的解析部分和 CDlgFuncList::SetData 的数据）。
		type 是 Default 时用类型别设置的解析方法。ツリー的顺序、リスト的排序按类型别设置。
		同时设置関数リストマーク（原版 SetDocLineFuncList：ブックマーク、ファイルツリー 以外）。
		ルールファイル 是类型别设置的文件（相对路径从 sakura.ini 的文件夹）。
	*/
	OutlineResult AnalyzeOutline(OutlineType type = OutlineType::Default);

	/*!
		解析方法（原版 Command_FUNCLIST 的开头）：Default 时是类型别设置的方法，C/C++ 时按扩展名是 C 或 Cpp
		（扩展名不是 .c、.cpp 等时 CCpp 不变）。已经打开的アウトライン解析 是不是同じ种类，按它判断
	*/
	OutlineType ResolveOutlineType(OutlineType type) const;

	/*!
		次の関数リストマークへ／前の関数リストマークへ（原版 Command_FUNCLIST_NEXT/PREV）的目标行。
		从 line 的下一行（前の 时上一行）找有関数リストマーク的逻辑行。
		searchAll（共通設定「先頭（末尾）から再検索する」）时到了末尾（开头）再从开头（末尾）找。
		找不到时 -1。@param[out] pWrapped 绕回去了（原版「▼末尾から先頭へ移動しました」等的消息）
	*/
	std::int32_t FindFuncListMark(std::int32_t line, bool forward, bool searchAll, bool* pWrapped = nullptr) const;

	//! この行に関数リストマークがあるか
	bool HasFuncListMark(std::int32_t line) const;

private:
	Document();
	struct Impl;
	std::unique_ptr<Impl> m_impl;
};

} // namespace sakura::core
