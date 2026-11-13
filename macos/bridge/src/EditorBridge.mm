/*! @file
	@brief 核心库的 Objective-C 接口（计划第 24 步）的实现

	只是把 sakura::core（macos/core/include/sakura_core/SakuraCore.h）的调用换成 Objective-C：
	NSString 和 std::u16string 都是 UTF-16，逐个 UTF-16 单位复制，不做编码转换。

	另外，排版用的文字宽度在这里用 Core Text 测量（第 27 步，原版用 GDI 的 GetTextExtentPoint32）。
*/
/*
	Copyright (C) 2026, Sakura Editor Organization

	SPDX-License-Identifier: Zlib
*/
#import "EditorBridge.h"
#import <CoreText/CoreText.h>

#include "sakura_core/SakuraCore.h"

#include <algorithm>
#include <cmath>
#include <memory>
#include <mutex>
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
static_assert(ECWrapMethodNone == static_cast<NSInteger>(core::WrapMethod::None));
static_assert(ECWrapMethodSettingWidth == static_cast<NSInteger>(core::WrapMethod::SettingWidth));
static_assert(ECWrapMethodWindowWidth == static_cast<NSInteger>(core::WrapMethod::WindowWidth));
static_assert(ECTabMarkString == static_cast<NSInteger>(core::TabMark::String));
static_assert(ECTabMarkShortArrow == static_cast<NSInteger>(core::TabMark::ShortArrow));
static_assert(ECTabMarkLongArrow == static_cast<NSInteger>(core::TabMark::LongArrow));
static_assert(ECColorIndexText == static_cast<NSInteger>(core::ColorIndex::Text));
static_assert(ECColorIndexLineNumber == static_cast<NSInteger>(core::ColorIndex::LineNumber));
static_assert(ECColorIndexEof == static_cast<NSInteger>(core::ColorIndex::Eof));
static_assert(ECColorIndexSelect == static_cast<NSInteger>(core::ColorIndex::Select));

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

// ----- Core Text 的文字宽度（第 27 步） -----

//! 最近用的字体。排版可能在多个线程里进行（大文件），用锁保护
std::mutex g_fontMutex;
CTFontRef g_font = nullptr;
std::u16string g_fontFace;
std::int32_t g_fontSize = 0;

//! 字体名和大小对应的 CTFont（调用方 CFRelease）
CTFontRef CopyFont(const char16_t* faceName, std::int32_t size)
{
	std::lock_guard lock(g_fontMutex);
	if (!g_font || g_fontFace != faceName || g_fontSize != size) {
		if (g_font) CFRelease(g_font);
		g_fontFace = faceName;
		g_fontSize = size;
		CFStringRef name = CFStringCreateWithCharacters(nullptr, reinterpret_cast<const UniChar *>(g_fontFace.data()), static_cast<CFIndex>(g_fontFace.size()));
		g_font = CTFontCreateWithName(name, size, nullptr);
		CFRelease(name);
	}
	return static_cast<CTFontRef>(CFRetain(g_font));
}

/*!
	文字宽度（点）。与 GetTextExtentPoint32 相同，返回整数（四舍五入）。
	这个字体里没有的字符（例如 Menlo 的汉字）由 Core Text 换成其他字体（Hiragino 等）来测，
	与绘制时相同。
*/
std::int32_t MeasureWithCoreText(const char16_t* faceName, std::int32_t size, const char16_t* text, std::size_t length)
{
	if (length == 0) return 0;
	CTFontRef font = CopyFont(faceName, size);
	CFStringRef string = CFStringCreateWithCharactersNoCopy(nullptr, reinterpret_cast<const UniChar *>(text), static_cast<CFIndex>(length), kCFAllocatorNull);
	const void* keys[] = { kCTFontAttributeName };
	const void* values[] = { font };
	CFDictionaryRef attributes = CFDictionaryCreate(nullptr, keys, values, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
	CFAttributedStringRef attributed = CFAttributedStringCreate(nullptr, string, attributes);
	CTLineRef line = CTLineCreateWithAttributedString(attributed);
	const double width = CTLineGetTypographicBounds(line, nullptr, nullptr, nullptr);
	CFRelease(line);
	CFRelease(attributed);
	CFRelease(attributes);
	CFRelease(string);
	CFRelease(font);
	return static_cast<std::int32_t>(std::lround(width));
}

} // namespace

// ---------------------------------------------------------------------------

@interface ECViewSettings ()
- (instancetype)initWithSettings:(const core::ViewSettings&)v;
@end

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

+ (void)useCoreTextMeasurement
{
	core::SetTextMeasureFunction(&MeasureWithCoreText);
}

+ (void)setLayoutFontName:(NSString *)name size:(NSInteger)size
{
	if (!FitsInt32(size)) return;
	core::SetLayoutFont(ToText(name), static_cast<std::int32_t>(size));
}

@end

// ---------------------------------------------------------------------------

@implementation ECViewSettings {
	core::ViewSettings _v;
}

- (instancetype)initWithSettings:(const core::ViewSettings&)v
{
	self = [super init];
	if (self) _v = v;
	return self;
}

- (ECWrapMethod)wrapMethod { return static_cast<ECWrapMethod>(_v.wrapMethod); }
- (NSInteger)wrapColumns { return _v.wrapColumns; }
- (NSInteger)typeWrapColumns { return _v.typeWrapColumns; }
- (NSInteger)tabColumns { return _v.tabColumns; }
- (NSInteger)columnSpacing { return _v.columnSpacing; }
- (NSInteger)lineSpacing { return _v.lineSpacing; }
- (BOOL)showLineNumbers { return _v.showLineNumbers ? YES : NO; }
- (BOOL)lineNumberPerLogicalLine { return _v.lineNumberPerLogicalLine ? YES : NO; }
- (NSInteger)lineNumberMinDigits { return _v.lineNumberMinDigits; }
- (BOOL)showTab { return _v.showTab ? YES : NO; }
- (ECTabMark)tabMark { return static_cast<ECTabMark>(_v.tabMark); }
- (NSString *)tabString { return ToNSString(_v.tabString); }
- (BOOL)showSpace { return _v.showSpace ? YES : NO; }
- (BOOL)showFullWidthSpace { return _v.showFullWidthSpace ? YES : NO; }
- (BOOL)showEol { return _v.showEol ? YES : NO; }
- (BOOL)showWrapMark { return _v.showWrapMark ? YES : NO; }
- (BOOL)showEof { return _v.showEof ? YES : NO; }
- (BOOL)hideHanging { return _v.hideHanging ? YES : NO; }
- (BOOL)hangEol { return _v.hangEol ? YES : NO; }
- (BOOL)hangPunctuation { return _v.hangPunctuation ? YES : NO; }

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

// ----- 排版（第 27 步） -----

- (ECViewSettings *)viewSettings
{
	return [[ECViewSettings alloc] initWithSettings:_doc->GetViewSettings()];
}

- (BOOL)setWrapMethod:(ECWrapMethod)method columns:(NSInteger)columns
{
	if (method < ECWrapMethodNone || ECWrapMethodWindowWidth < method) return NO;
	const auto nColumns = static_cast<std::int32_t>(std::clamp<NSInteger>(columns, 0, INT32_MAX));
	return _doc->SetWrap(static_cast<core::WrapMethod>(method), nColumns) ? YES : NO;
}

- (NSInteger)wrapColumnsForWidth:(NSInteger)width
{
	return _doc->WrapColumnsForWidth(static_cast<std::int32_t>(std::clamp<NSInteger>(width, 0, INT32_MAX)));
}

- (void)relayout { _doc->Relayout(); }

- (NSInteger)layoutLineCount { return _doc->LayoutLineCount(); }

- (ECLayoutLine)layoutLineAtIndex:(NSInteger)line
{
	if (!FitsInt32(line)) return ECLayoutLine{};
	const core::LayoutLine l = _doc->GetLayoutLine(static_cast<std::int32_t>(line));
	return ECLayoutLine{ FromCore(l.start), l.length, static_cast<ECEol>(l.eol), l.indent };
}

- (NSArray<NSNumber *> *)charPositionsOfLayoutLine:(NSInteger)line
{
	if (!FitsInt32(line)) return @[ @0 ];
	const auto positions = _doc->GetLayoutCharPositions(static_cast<std::int32_t>(line));
	NSMutableArray<NSNumber *> *result = [NSMutableArray arrayWithCapacity:positions.size()];
	for (const auto x : positions) [result addObject:@(x)];
	return result;
}

- (ECLayoutPosition)layoutPositionOf:(ECPosition)position
{
	if (!FitsInt32(position.line) || !FitsInt32(position.column)) return ECLayoutPosition{};
	const core::LayoutPosition p = _doc->LogicToLayout(ToCore(position));
	return ECLayoutPosition{ p.line, p.x };
}

- (ECPosition)logicPositionOf:(ECLayoutPosition)position
{
	if (!FitsInt32(position.line) || !FitsInt32(position.x)) return ECPosition{};
	const core::Position p = _doc->LayoutToLogic(core::LayoutPosition{ static_cast<std::int32_t>(position.line), static_cast<std::int32_t>(position.x) });
	return FromCore(p);
}

- (NSInteger)charWidth { return _doc->CharWidth(); }
- (NSInteger)layoutWidth { return _doc->LayoutWidth(); }

- (ECColorSetting)colorFor:(ECColorIndex)index
{
	if (index < 0 || index > 255) return ECColorSetting{};
	const core::ColorSetting c = _doc->GetColor(static_cast<core::ColorIndex>(index));
	return ECColorSetting{ c.display, c.bold, c.underline, c.text, c.back };
}

- (BOOL)isLineModified:(NSInteger)line
{
	if (!FitsInt32(line)) return NO;
	return _doc->IsLineModified(static_cast<std::int32_t>(line)) ? YES : NO;
}

@end
