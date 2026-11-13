/*! @file
	@brief 核心库的 Objective-C 接口（计划第 24 步）

	Swift 通过框架 EditorBridge 使用核心库（import EditorBridge）。
	这个头文件只引用 Foundation，Swift 能直接导入；实现（EditorBridge.mm）是 Objective-C++，
	内部调用核心库的 C++ 接口 sakura_core/SakuraCore.h（第 22 步）。

	- 文字是 NSString（UTF-16），与核心库相同，不做转换。
	- 位置是逻辑位置：行号和行内的 UTF-16 下标，都从 0 开始。
	  自动换行后的排版位置是 ECLayoutPosition（第 27 步）：排版行号和横向位置（点）。
	- 编码、换行符、功能编号的数值与原版相同（ECodeType、EEolType、EFunctionCode）。
*/
/*
	Copyright (C) 2026, Sakura Editor Organization

	SPDX-License-Identifier: Zlib
*/
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

//! 结果（sakura::core::Result）
typedef NS_ENUM(NSInteger, ECResult) {
	ECResultSuccess NS_SWIFT_NAME(success) = 0,
	ECResultLostSome NS_SWIFT_NAME(lostSome),					//!< 完成，但有的字符不能用这个编码表示
	ECResultFailed NS_SWIFT_NAME(failed),						//!< 文件打不开、读写失败等
	ECResultInvalidArgument NS_SWIFT_NAME(invalidArgument),		//!< 位置超出范围、编码不对等
	ECResultNotFound NS_SWIFT_NAME(notFound),
	ECResultNotSupported NS_SWIFT_NAME(notSupported),			//!< 这个功能在 Mac 版还没有移植
} NS_SWIFT_NAME(EditorResult);

//! 换行符（数值与原版的 EEolType 相同）
typedef NS_ENUM(NSInteger, ECEol) {
	ECEolNone NS_SWIFT_NAME(none) = 0,
	ECEolCRLF NS_SWIFT_NAME(crlf) = 1,
	ECEolLF NS_SWIFT_NAME(lf) = 2,
	ECEolCR NS_SWIFT_NAME(cr) = 3,
	ECEolNEL NS_SWIFT_NAME(nel) = 4,
	ECEolLineSeparator NS_SWIFT_NAME(lineSeparator) = 5,
	ECEolParagraphSeparator NS_SWIFT_NAME(paragraphSeparator) = 6,
} NS_SWIFT_NAME(EditorEol);

//! 编码（数值与原版的 ECodeType 相同。下面以外的值是代码页编号，例如 1252）
typedef NSInteger ECEncoding NS_SWIFT_NAME(EditorEncoding);
enum : NSInteger {
	ECEncodingSJIS = 0,
	ECEncodingJIS = 1,
	ECEncodingEUC = 2,
	ECEncodingUTF16LE = 3,
	ECEncodingUTF8 = 4,
	ECEncodingUTF7 = 5,
	ECEncodingUTF16BE = 6,
	ECEncodingCESU8 = 7,
	ECEncodingLatin1 = 8,
	ECEncodingUTF32LE = 12000,
	ECEncodingUTF32BE = 12001,
	ECEncodingAutoDetect = 99,	//!< 打开时自动识别
};

//! 功能编号（数值与原版的 EFunctionCode 相同）
typedef NSInteger ECCommand NS_SWIFT_NAME(EditorCommand);
enum : NSInteger {
	ECCommandFileSave = 30103,		//!< F_FILESAVE（上書き保存）
	ECCommandUndo = 30210,			//!< F_UNDO
	ECCommandRedo = 30211,			//!< F_REDO
	ECCommandNewLineCRLF = 31081,	//!< F_CHGMOD_EOL_CRLF
	ECCommandNewLineLF = 31082,		//!< F_CHGMOD_EOL_LF
	ECCommandNewLineCR = 31083,		//!< F_CHGMOD_EOL_CR
};

//! 逻辑位置
typedef struct ECPosition {
	NSInteger line;
	NSInteger column;
} NS_SWIFT_NAME(EditorPosition) ECPosition;

//! 范围 [from, to)
typedef struct ECRange {
	ECPosition from;
	ECPosition to;
} NS_SWIFT_NAME(EditorRange) ECRange;

//! 查找条件（原版的 SSearchOption）
typedef NS_OPTIONS(NSUInteger, ECSearchOptions) {
	ECSearchOptionsRegularExpression NS_SWIFT_NAME(regularExpression) = 1 << 0,
	ECSearchOptionsMatchCase NS_SWIFT_NAME(matchCase) = 1 << 1,		//!< 区分大小写
	ECSearchOptionsWholeWord NS_SWIFT_NAME(wholeWord) = 1 << 2,		//!< 单词单位
} NS_SWIFT_NAME(EditorSearchOptions);

//! 折り返し方法（数值与原版的 WRAP_NO_TEXT_WRAP 等相同）
typedef NS_ENUM(NSInteger, ECWrapMethod) {
	ECWrapMethodNone NS_SWIFT_NAME(none) = 0,						//!< 折り返さない
	ECWrapMethodSettingWidth NS_SWIFT_NAME(settingWidth) = 1,		//!< 指定桁で折り返す
	ECWrapMethodWindowWidth NS_SWIFT_NAME(windowWidth) = 2,			//!< 右端で折り返す
} NS_SWIFT_NAME(EditorWrapMethod);

//! TAB 记号的样式（数值与原版的 ETabArrow 相同）
typedef NS_ENUM(NSInteger, ECTabMark) {
	ECTabMarkString NS_SWIFT_NAME(string) = 0,				//!< 文字指定
	ECTabMarkShortArrow NS_SWIFT_NAME(shortArrow) = 1,		//!< 短い矢印
	ECTabMarkLongArrow NS_SWIFT_NAME(longArrow) = 2,		//!< 長い矢印
} NS_SWIFT_NAME(EditorTabMark);

//! 排版位置：排版行号（从 0 开始）和横向位置（点，从排版行的左端量起，包括缩进）
typedef struct ECLayoutPosition {
	NSInteger line;
	NSInteger x;
} NS_SWIFT_NAME(EditorLayoutPosition) ECLayoutPosition;

//! 一个排版行（原版的 CLayout）
typedef struct ECLayoutLine {
	ECPosition start;		//!< 在逻辑行里的开始位置
	NSInteger length;		//!< 长度（UTF-16，不含换行符）
	ECEol eol;				//!< 逻辑行的最后一段带换行符，其他段是 none
	NSInteger indent;		//!< 行首的缩进（点）
} NS_SWIFT_NAME(EditorLayoutLine) ECLayoutLine;

/*!
	编辑画面的显示设置：类型别设置里与排版、记号有关的部分（sakura::core::ViewSettings）
*/
NS_SWIFT_NAME(EditorViewSettings)
@interface ECViewSettings : NSObject
@property (readonly) ECWrapMethod wrapMethod;			//!< 现在的折り返し方法
@property (readonly) NSInteger wrapColumns;				//!< 现在的折り返し桁数
@property (readonly) NSInteger typeWrapColumns;			//!< 类型别设置的折り返し桁数
@property (readonly) NSInteger tabColumns;				//!< TAB 幅（桁）
@property (readonly) NSInteger columnSpacing;			//!< 文字と文字の隙間（点）
@property (readonly) NSInteger lineSpacing;				//!< 行間のすきま（点）
@property (readonly) BOOL showLineNumbers;
@property (readonly) BOOL lineNumberPerLogicalLine;		//!< 行番号を改行単位で数える
@property (readonly) NSInteger lineNumberMinDigits;		//!< 行番号の最小桁数
@property (readonly) BOOL showTab;
@property (readonly) ECTabMark tabMark;
@property (readonly, copy) NSString *tabString;			//!< 文字指定のときの TAB 表示文字
@property (readonly) BOOL showSpace;					//!< 半角空白
@property (readonly) BOOL showFullWidthSpace;			//!< 日本語空白
@property (readonly) BOOL showEol;						//!< 改行記号
@property (readonly) BOOL showWrapMark;					//!< 折り返し記号
@property (readonly) BOOL showEof;						//!< EOF 記号
@property (readonly) BOOL hideHanging;					//!< ぶら下げを隠す
@property (readonly) BOOL hangEol;						//!< 改行文字をぶら下げる
@property (readonly) BOOL hangPunctuation;				//!< 句読点ぶら下げ
- (instancetype)init NS_UNAVAILABLE;
@end

/*!
	核心库的启动和结束、名字的查询。
	App 启动时调用一次 +startup，结束时调用 +shutdownSavingSettings:。
*/
NS_SWIFT_NAME(EditorCore)
@interface ECCore : NSObject

//! 启动核心库：建立共通设置，读入 sakura.ini（没有时写出默认设置）
+ (BOOL)startup;
//! 结束核心库。save 为 YES 时写出 sakura.ini
+ (void)shutdownSavingSettings:(BOOL)save NS_SWIFT_NAME(shutdown(savingSettings:));
@property (class, readonly) BOOL isStarted;
//! sakura.ini 的路径（沙盒里在 App 的容器中）
@property (class, readonly, copy) NSString *settingsFilePath;

//! 编码的显示名（"SJIS"、"UTF-8" 等）。不能用的编码是空字符串
+ (NSString *)nameOfEncoding:(ECEncoding)encoding NS_SWIFT_NAME(name(ofEncoding:));
//! 功能的名字（与原版菜单相同，日文）。不存在时是空字符串
+ (NSString *)nameOfCommand:(ECCommand)command NS_SWIFT_NAME(name(ofCommand:));
//! 换行符的文字（"\r\n" 等）
+ (NSString *)textOfEol:(ECEol)eol NS_SWIFT_NAME(text(ofEol:));

/*!
	文字宽度用 Core Text 测量（第 27 步，原版用 GDI）。App 启动时调用一次。
	不调用时用简单的估算（单元测试用）。
*/
+ (void)useCoreTextMeasurement NS_SWIFT_NAME(useCoreTextMeasurement());
/*!
	排版用的字体：字体名和大小（点）。已经打开的文档要调用 -relayout。
	字体名是 Core Text 能找到的名字（例如 "Menlo"）。
*/
+ (void)setLayoutFontName:(NSString *)name size:(NSInteger)size NS_SWIFT_NAME(setLayoutFont(name:size:));

- (instancetype)init NS_UNAVAILABLE;
@end

/*!
	一个文档（一个文件）。sakura::core::Document 的包装。
	排版（自动换行）也在这里（第 27 步）。光标、选择、绘制属于编辑画面，不在这里。
	只能在一个线程（通常是主线程）里使用。
*/
NS_SWIFT_NAME(EditorDocument)
@interface ECDocument : NSObject

//! 新文档（无题、空）。核心库没有启动时返回 nil
- (nullable instancetype)init NS_DESIGNATED_INITIALIZER;

// ----- 打开、保存 -----

//! 打开文件。encoding 用 ECEncodingAutoDetect 时自动识别
- (ECResult)openFileAtPath:(NSString *)path encoding:(ECEncoding)encoding NS_SWIFT_NAME(open(path:encoding:));
- (ECResult)openFileAtPath:(NSString *)path NS_SWIFT_NAME(open(path:));
//! 另存为。eol 为 ECEolNone 时不转换换行符
- (ECResult)saveToPath:(NSString *)path encoding:(ECEncoding)encoding bom:(BOOL)bom eol:(ECEol)eol NS_SWIFT_NAME(save(to:encoding:bom:eol:));
//! 用打开时的编码、BOM 另存为
- (ECResult)saveToPath:(NSString *)path NS_SWIFT_NAME(save(to:));
//! 覆盖保存（无题文档返回 ECResultInvalidArgument）
- (ECResult)save;

@property (readonly, copy) NSString *path;				//!< 无题时是空字符串
@property (readonly) ECEncoding encoding;
@property (readonly) BOOL hasBOM;
@property (readonly) NSInteger typeIndex;				//!< 类型别设置的编号
@property (readonly, copy) NSString *typeName;			//!< 类型别设置的名字（“テキスト”“C/C++” 等）
@property (readonly, getter=isModified) BOOL modified;

// ----- 内容 -----

@property (readonly) NSInteger lineCount;
@property (readonly, copy) NSString *text;				//!< 全文（包括换行符）
- (NSString *)lineAtIndex:(NSInteger)line NS_SWIFT_NAME(line(at:));
- (NSString *)lineAtIndex:(NSInteger)line withEol:(BOOL)withEol NS_SWIFT_NAME(line(at:withEol:));
- (ECEol)eolOfLineAtIndex:(NSInteger)line NS_SWIFT_NAME(eol(ofLine:));
- (NSString *)textInRange:(ECRange)range NS_SWIFT_NAME(text(in:));
@property (readonly) ECPosition endPosition;

// ----- 编辑 -----

//! 把 range 换成 text。newEnd 是插入的文字之后的位置（可以是 NULL）
- (ECResult)replaceRange:(ECRange)range withText:(NSString *)text newEnd:(nullable ECPosition *)newEnd NS_SWIFT_NAME(replace(_:with:newEnd:));
- (ECResult)replaceRange:(ECRange)range withText:(NSString *)text NS_SWIFT_NAME(replace(_:with:));
- (ECResult)insertText:(NSString *)text at:(ECPosition)position NS_SWIFT_NAME(insert(_:at:));
- (ECResult)deleteRange:(ECRange)range NS_SWIFT_NAME(delete(_:));
//! 把多次编辑合成撤销的一步（成对调用，可以嵌套）
- (void)beginEdit;
- (void)endEdit;

@property (readonly) BOOL canUndo;
@property (readonly) BOOL canRedo;
- (ECResult)undo;
- (ECResult)redo;

@property (nonatomic) ECEol newLineEol;					//!< 输入时用的换行符

// ----- 查找、替换 -----

/*!
	从 from 开始查找。找到时返回 YES，范围放进 outRange。
	正则表达式有错误时返回 NO，lastSearchError 是原因。
*/
- (BOOL)findPattern:(NSString *)pattern from:(ECPosition)from backward:(BOOL)backward options:(ECSearchOptions)options range:(nullable ECRange *)outRange NS_SWIFT_NAME(find(_:from:backward:options:range:));
//! 全部替换。返回替换的个数，正则表达式有错误时是 -1
- (NSInteger)replaceAllPattern:(NSString *)pattern with:(NSString *)replacement options:(ECSearchOptions)options NS_SWIFT_NAME(replaceAll(_:with:options:));
@property (readonly, copy) NSString *lastSearchError;

// ----- 命令 -----

- (ECResult)executeCommand:(ECCommand)command NS_SWIFT_NAME(execute(_:));
- (BOOL)isCommandEnabled:(ECCommand)command NS_SWIFT_NAME(isEnabled(_:));
+ (BOOL)isCommandSupported:(ECCommand)command NS_SWIFT_NAME(isSupported(_:));

// ----- 排版（第 27 步） -----

//! 显示设置（类型别设置；折り返し方法和桁数是现在的值）
@property (readonly) ECViewSettings *viewSettings;
/*!
	改变折り返し方法并重新排版（原版的「折り返し方法」、窗口宽度变化时的「右端で折り返す」）。
	columns 小于 10 时按 10。排版有变化时返回 YES。
*/
- (BOOL)setWrapMethod:(ECWrapMethod)method columns:(NSInteger)columns NS_SWIFT_NAME(setWrap(_:columns:));
//! 「右端で折り返す」时，宽度 width（点）可以放下的折り返し桁数
- (NSInteger)wrapColumnsForWidth:(NSInteger)width NS_SWIFT_NAME(wrapColumns(forWidth:));
//! 按现在的字体和设置重新排版
- (void)relayout;

//! 排版行数（空文档是 0）
@property (readonly) NSInteger layoutLineCount;
//! 排版行。超出范围时全是 0
- (ECLayoutLine)layoutLineAtIndex:(NSInteger)line NS_SWIFT_NAME(layoutLine(at:));
/*!
	排版行里每个 UTF-16 字符左端的横向位置（点），最后多一个（行末）。TAB 已经展开。
	补充平面字符的后一半与前一半相同。
*/
- (NSArray<NSNumber *> *)charPositionsOfLayoutLine:(NSInteger)line NS_SWIFT_NAME(charPositions(ofLayoutLine:));
//! 逻辑位置 → 排版位置
- (ECLayoutPosition)layoutPositionOf:(ECPosition)position NS_SWIFT_NAME(layoutPosition(of:));
//! 排版位置 → 逻辑位置
- (ECPosition)logicPositionOf:(ECLayoutPosition)position NS_SWIFT_NAME(logicPosition(of:));
//! 半角一字的宽度（点，包括文字间隔）
@property (readonly) NSInteger charWidth;
//! 文字部分的宽度（点）：折り返さない时是最长的行，其他时候是折り返し桁数的宽度
@property (readonly) NSInteger layoutWidth;

@end

NS_ASSUME_NONNULL_END
