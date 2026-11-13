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
#include <memory>
#include <optional>
#include <string>
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
};

struct SaveOptions {
	std::optional<Encoding> encoding;	//!< 不指定时用打开时的编码
	std::optional<bool> bom;			//!< 不指定时与打开时相同
	Eol eol = Eol::None;				//!< 统一换行符。None 是不转换（原版“名前を付けて保存”的改行コード）
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
}

/*!
	功能的名字（与原版的菜单、按键分配对话框里的名字相同，日文）。
	编号不存在时是空。界面的多语言化在第 48 步。
*/
Text CommandName(FunctionCode code);

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

	const FileInfo& GetFileInfo() const;
	bool IsModified() const;

	// ----- 内容 -----

	//! 行数。空文档是 0 行（与原版 CDocLineMgr 相同）
	std::int32_t LineCount() const;

	//! 一行的文字。withEol 为 true 时包括换行符。行号超出范围时是空
	Text GetLine(std::int32_t line, bool withEol = false) const;

	//! 行的换行符（最后一行没有换行时是 Eol::None）
	Eol GetLineEol(std::int32_t line) const;

	//! 全文（包括换行符）
	Text GetText() const;

	//! 范围内的文字
	Text GetText(const Range& range) const;

	//! 文档末尾的位置（最后一行的末尾；最后一行以换行结束时是下一行的开头）
	Position EndPosition() const;

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

	// ----- 命令 -----

	/*!
		执行命令。现在只能执行不需要编辑画面的命令（command 名字空间里的命令）：
		撤销、重做、上書き保存、输入换行符的切换。
		其他命令（光标移动、选择、剪贴板等）需要编辑画面，第 30 步起逐步加入，现在返回 NotSupported。
	*/
	Result ExecuteCommand(FunctionCode code);

	//! 现在能否执行（原版的 IsFuncEnable。例如没有可以撤销的操作时 Undo 是 false）
	bool IsCommandEnabled(FunctionCode code) const;

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

private:
	Document();
	struct Impl;
	std::unique_ptr<Impl> m_impl;
};

} // namespace sakura::core
