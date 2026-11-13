/*! @file
	@brief 核心库的 Objective-C 接口（计划第 24 步）

	Swift 通过框架 EditorBridge 使用核心库（import EditorBridge）。
	这个头文件只引用 Foundation，Swift 能直接导入；实现（EditorBridge.mm）是 Objective-C++，
	内部调用核心库的 C++ 接口 sakura_core/SakuraCore.h（第 22 步）。

	- 文字是 NSString（UTF-16），与核心库相同，不做转换。
	- 位置是逻辑位置：行号和行内的 UTF-16 下标，都从 0 开始。
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

- (instancetype)init NS_UNAVAILABLE;
@end

/*!
	一个文档（一个文件）。sakura::core::Document 的包装。
	光标、选择、排版、绘制属于编辑画面，不在这里。只能在一个线程（通常是主线程）里使用。
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

@end

NS_ASSUME_NONNULL_END
