/*! @file
	@brief 核心库的 Objective-C 接口（计划第 24 步）的实现

	只是把 sakura::core（macos/core/include/sakura_core/SakuraCore.h）的调用换成 Objective-C：
	NSString 和 std::u16string 都是 UTF-16，逐个 UTF-16 单位复制，不做编码转换。
*/
/*
	Copyright (C) 2026, Sakura Editor Organization

	SPDX-License-Identifier: Zlib
*/
#import "EditorBridge.h"

#include "sakura_core/SakuraCore.h"

#include <memory>
#include <type_traits>

namespace core = sakura::core;

// 公开的数值与核心库相同
static_assert(static_cast<NSInteger>(ECResultSuccess) == static_cast<NSInteger>(core::Result::Ok));
static_assert(static_cast<NSInteger>(ECResultLostSome) == static_cast<NSInteger>(core::Result::LostSome));
static_assert(static_cast<NSInteger>(ECResultFailed) == static_cast<NSInteger>(core::Result::Failed));
static_assert(static_cast<NSInteger>(ECResultInvalidArgument) == static_cast<NSInteger>(core::Result::InvalidArgument));
static_assert(static_cast<NSInteger>(ECResultNotFound) == static_cast<NSInteger>(core::Result::NotFound));
static_assert(static_cast<NSInteger>(ECResultNotSupported) == static_cast<NSInteger>(core::Result::NotSupported));
static_assert(ECEolCRLF == static_cast<NSInteger>(core::Eol::CRLF) && ECEolLF == static_cast<NSInteger>(core::Eol::LF));
static_assert(ECEolCR == static_cast<NSInteger>(core::Eol::CR) && ECEolNEL == static_cast<NSInteger>(core::Eol::NEL));
static_assert(ECEolLineSeparator == static_cast<NSInteger>(core::Eol::LineSeparator));
static_assert(ECEolParagraphSeparator == static_cast<NSInteger>(core::Eol::ParagraphSeparator));
static_assert(ECEncodingSJIS == core::encoding::SJIS && ECEncodingUTF8 == core::encoding::UTF8);
static_assert(ECEncodingUTF16LE == core::encoding::UTF16LE && ECEncodingUTF16BE == core::encoding::UTF16BE);
static_assert(ECEncodingUTF32LE == core::encoding::UTF32LE && ECEncodingAutoDetect == core::encoding::AutoDetect);
static_assert(ECCommandFileSave == core::command::FileSave && ECCommandUndo == core::command::Undo);
static_assert(ECCommandRedo == core::command::Redo && ECCommandNewLineCRLF == core::command::NewLineCRLF);
static_assert(ECCommandNewLineLF == core::command::NewLineLF && ECCommandNewLineCR == core::command::NewLineCR);
static_assert(sizeof(unichar) == sizeof(char16_t), "NSString 和核心库都是 UTF-16");

namespace {

core::Text ToText(NSString *s)
{
	core::Text t;
	if (!s) return t;
	t.resize(s.length);
	[s getCharacters:reinterpret_cast<unichar *>(t.data()) range:NSMakeRange(0, s.length)];
	return t;
}

NSString *ToNSString(const core::Text& t)
{
	return [NSString stringWithCharacters:reinterpret_cast<const unichar *>(t.data()) length:t.size()];
}

core::Position ToCore(ECPosition p)
{
	return core::Position{ static_cast<std::int32_t>(p.line), static_cast<std::int32_t>(p.column) };
}

ECPosition FromCore(const core::Position& p)
{
	return ECPosition{ p.line, p.column };
}

core::Range ToCore(ECRange r)
{
	return core::Range{ ToCore(r.from), ToCore(r.to) };
}

ECRange FromCore(const core::Range& r)
{
	return ECRange{ FromCore(r.from), FromCore(r.to) };
}

ECResult FromCore(core::Result r)
{
	return static_cast<ECResult>(r);
}

core::SearchOptions ToCore(ECSearchOptions o)
{
	core::SearchOptions so;
	so.regularExpression = (o & ECSearchOptionsRegularExpression) != 0;
	so.matchCase = (o & ECSearchOptionsMatchCase) != 0;
	so.wholeWord = (o & ECSearchOptionsWholeWord) != 0;
	return so;
}

//! 超出 int32 的值（Swift 的 Int 是 64 位）当作无效的位置
bool FitsInt32(NSInteger v)
{
	return INT32_MIN <= v && v <= INT32_MAX;
}

bool FitsInt32(ECRange r)
{
	return FitsInt32(r.from.line) && FitsInt32(r.from.column) && FitsInt32(r.to.line) && FitsInt32(r.to.column);
}

} // namespace

// ---------------------------------------------------------------------------

@implementation ECCore

+ (BOOL)startup
{
	return core::Startup() ? YES : NO;
}

+ (void)shutdownSavingSettings:(BOOL)save
{
	core::Shutdown(save);
}

+ (BOOL)isStarted
{
	return core::IsStarted() ? YES : NO;
}

+ (NSString *)settingsFilePath
{
	return ToNSString(core::SettingsFilePath());
}

+ (NSString *)nameOfEncoding:(ECEncoding)encoding
{
	if (!FitsInt32(encoding)) return @"";
	return ToNSString(core::EncodingName(static_cast<core::Encoding>(encoding)));
}

+ (NSString *)nameOfCommand:(ECCommand)command
{
	if (!FitsInt32(command)) return @"";
	return ToNSString(core::CommandName(static_cast<core::FunctionCode>(command)));
}

+ (NSString *)textOfEol:(ECEol)eol
{
	if (eol < ECEolNone || ECEolParagraphSeparator < eol) return @"";
	return ToNSString(core::EolText(static_cast<core::Eol>(eol)));
}

@end

// ---------------------------------------------------------------------------

@implementation ECDocument {
	std::unique_ptr<core::Document> _doc;
}

- (nullable instancetype)init
{
	self = [super init];
	if (!self) return nil;
	_doc = core::Document::Create();
	if (!_doc) return nil;	// 核心库还没有启动
	return self;
}

// ----- 打开、保存 -----

- (ECResult)openFileAtPath:(NSString *)path encoding:(ECEncoding)encoding
{
	if (!FitsInt32(encoding)) return ECResultInvalidArgument;
	core::OpenOptions options;
	options.encoding = static_cast<core::Encoding>(encoding);
	return FromCore(_doc->Open(ToText(path), options));
}

- (ECResult)openFileAtPath:(NSString *)path
{
	return [self openFileAtPath:path encoding:ECEncodingAutoDetect];
}

- (ECResult)saveToPath:(NSString *)path encoding:(ECEncoding)encoding bom:(BOOL)bom eol:(ECEol)eol
{
	if (!FitsInt32(encoding) || eol < ECEolNone || ECEolParagraphSeparator < eol) return ECResultInvalidArgument;
	core::SaveOptions options;
	options.encoding = static_cast<core::Encoding>(encoding);
	options.bom = (bom == YES);
	options.eol = static_cast<core::Eol>(eol);
	return FromCore(_doc->SaveAs(ToText(path), options));
}

- (ECResult)saveToPath:(NSString *)path
{
	return FromCore(_doc->SaveAs(ToText(path)));
}

- (ECResult)save
{
	return FromCore(_doc->Save());
}

- (NSString *)path { return ToNSString(_doc->GetFileInfo().path); }
- (ECEncoding)encoding { return _doc->GetFileInfo().encoding; }
- (BOOL)hasBOM { return _doc->GetFileInfo().bom ? YES : NO; }
- (NSInteger)typeIndex { return _doc->GetFileInfo().typeIndex; }
- (NSString *)typeName { return ToNSString(_doc->GetFileInfo().typeName); }
- (BOOL)isModified { return _doc->IsModified() ? YES : NO; }

// ----- 内容 -----

- (NSInteger)lineCount { return _doc->LineCount(); }
- (NSString *)text { return ToNSString(_doc->GetText()); }

- (NSString *)lineAtIndex:(NSInteger)line
{
	return [self lineAtIndex:line withEol:NO];
}

- (NSString *)lineAtIndex:(NSInteger)line withEol:(BOOL)withEol
{
	if (!FitsInt32(line)) return @"";
	return ToNSString(_doc->GetLine(static_cast<std::int32_t>(line), withEol == YES));
}

- (ECEol)eolOfLineAtIndex:(NSInteger)line
{
	if (!FitsInt32(line)) return ECEolNone;
	return static_cast<ECEol>(_doc->GetLineEol(static_cast<std::int32_t>(line)));
}

- (NSString *)textInRange:(ECRange)range
{
	if (!FitsInt32(range)) return @"";
	return ToNSString(_doc->GetText(ToCore(range)));
}

- (ECPosition)endPosition { return FromCore(_doc->EndPosition()); }

// ----- 编辑 -----

- (ECResult)replaceRange:(ECRange)range withText:(NSString *)text newEnd:(nullable ECPosition *)newEnd
{
	if (!FitsInt32(range)) return ECResultInvalidArgument;
	core::Position end;
	const core::Result r = _doc->Replace(ToCore(range), ToText(text), &end);
	if (newEnd && r == core::Result::Ok) *newEnd = FromCore(end);
	return FromCore(r);
}

- (ECResult)replaceRange:(ECRange)range withText:(NSString *)text
{
	return [self replaceRange:range withText:text newEnd:NULL];
}

- (ECResult)insertText:(NSString *)text at:(ECPosition)position
{
	return [self replaceRange:ECRange{ position, position } withText:text newEnd:NULL];
}

- (ECResult)deleteRange:(ECRange)range
{
	return [self replaceRange:range withText:@"" newEnd:NULL];
}

- (void)beginEdit { _doc->BeginEdit(); }
- (void)endEdit { _doc->EndEdit(); }
- (BOOL)canUndo { return _doc->CanUndo() ? YES : NO; }
- (BOOL)canRedo { return _doc->CanRedo() ? YES : NO; }
- (ECResult)undo { return FromCore(_doc->Undo()); }
- (ECResult)redo { return FromCore(_doc->Redo()); }

- (ECEol)newLineEol { return static_cast<ECEol>(_doc->GetNewLineEol()); }

- (void)setNewLineEol:(ECEol)eol
{
	if (eol < ECEolNone || ECEolParagraphSeparator < eol) return;
	_doc->SetNewLineEol(static_cast<core::Eol>(eol));
}

// ----- 查找、替换 -----

- (BOOL)findPattern:(NSString *)pattern from:(ECPosition)from backward:(BOOL)backward options:(ECSearchOptions)options range:(ECRange *)outRange
{
	if (!FitsInt32(from.line) || !FitsInt32(from.column)) return NO;
	const auto found = _doc->Find(ToText(pattern), ToCore(from),
								  backward ? core::SearchDirection::Backward : core::SearchDirection::Forward,
								  ToCore(options));
	if (!found) return NO;
	if (outRange) *outRange = FromCore(*found);
	return YES;
}

- (NSInteger)replaceAllPattern:(NSString *)pattern with:(NSString *)replacement options:(ECSearchOptions)options
{
	return _doc->ReplaceAll(ToText(pattern), ToText(replacement), ToCore(options));
}

- (NSString *)lastSearchError { return ToNSString(_doc->GetLastSearchError()); }

// ----- 命令 -----

- (ECResult)executeCommand:(ECCommand)command
{
	if (!FitsInt32(command)) return ECResultNotSupported;
	return FromCore(_doc->ExecuteCommand(static_cast<core::FunctionCode>(command)));
}

- (BOOL)isCommandEnabled:(ECCommand)command
{
	if (!FitsInt32(command)) return NO;
	return _doc->IsCommandEnabled(static_cast<core::FunctionCode>(command)) ? YES : NO;
}

+ (BOOL)isCommandSupported:(ECCommand)command
{
	if (!FitsInt32(command)) return NO;
	return core::Document::IsCommandSupported(static_cast<core::FunctionCode>(command)) ? YES : NO;
}

@end
