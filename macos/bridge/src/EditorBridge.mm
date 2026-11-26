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
static_assert(static_cast<NSInteger>(ECMigemoStatusReady) == static_cast<NSInteger>(core::MigemoStatus::Ready));
static_assert(static_cast<NSInteger>(ECDiffResultMarked) == static_cast<NSInteger>(core::Document::DiffResult::Marked));
static_assert(static_cast<NSInteger>(ECDiffResultNoDiff) == static_cast<NSInteger>(core::Document::DiffResult::NoDiff));
static_assert(static_cast<NSInteger>(ECDiffResultBinary) == static_cast<NSInteger>(core::Document::DiffResult::Binary));
static_assert(static_cast<NSInteger>(ECMigemoStatusNoLibrary) == static_cast<NSInteger>(core::MigemoStatus::NoLibrary));
static_assert(static_cast<NSInteger>(ECMigemoStatusNoDictionary) == static_cast<NSInteger>(core::MigemoStatus::NoDictionary));
static_assert(static_cast<NSInteger>(ECResultInvalidArgument) == static_cast<NSInteger>(core::Result::InvalidArgument));
static_assert(static_cast<NSInteger>(ECResultNotFound) == static_cast<NSInteger>(core::Result::NotFound));
static_assert(static_cast<NSInteger>(ECResultNotSupported) == static_cast<NSInteger>(core::Result::NotSupported));
static_assert(ECEolCRLF == static_cast<NSInteger>(core::Eol::CRLF) && ECEolLF == static_cast<NSInteger>(core::Eol::LF));
static_assert(ECEolCR == static_cast<NSInteger>(core::Eol::CR) && ECEolNEL == static_cast<NSInteger>(core::Eol::NEL));
static_assert(ECEolLineSeparator == static_cast<NSInteger>(core::Eol::LineSeparator));
static_assert(ECEolParagraphSeparator == static_cast<NSInteger>(core::Eol::ParagraphSeparator));
static_assert(ECColorIndexSearch5 == static_cast<NSInteger>(core::ColorIndex::Search5));
static_assert(ECColorIndexComment == static_cast<NSInteger>(core::ColorIndex::Comment));		// 第 33 步
static_assert(ECColorIndexKeyword1 == static_cast<NSInteger>(core::ColorIndex::Keyword1));
static_assert(ECColorIndexRegex1 == static_cast<NSInteger>(core::ColorIndex::Regex1));
static_assert(ECColorIndexPageView == static_cast<NSInteger>(core::ColorIndex::PageView));
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
static_assert(ECIndentKindNone == static_cast<NSInteger>(core::IndentKind::None));
static_assert(ECIndentKindTab == static_cast<NSInteger>(core::IndentKind::Tab));
static_assert(ECIndentKindSpace == static_cast<NSInteger>(core::IndentKind::Space));

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

ECSearchOptions FromCore(const core::SearchOptions& o)
{
	ECSearchOptions r = 0;
	if (o.regularExpression) r |= ECSearchOptionsRegularExpression;
	if (o.matchCase) r |= ECSearchOptionsMatchCase;
	if (o.wholeWord) r |= ECSearchOptionsWholeWord;
	return r;
}

//! 第 32 步：查找命令的光标和选择
core::SearchView ToCore(const ECSearchView& v)
{
	core::SearchView r;
	r.caret = ToCore(v.caret);
	if (v.hasSelection) r.selection = ToCore(v.selection);
	return r;
}

ECSearchView FromCore(const core::SearchView& v)
{
	ECSearchView r{};
	r.caret = FromCore(v.caret);
	r.hasSelection = v.selection.has_value();
	r.selection = v.selection ? FromCore(*v.selection) : ECRange{ r.caret, r.caret };
	return r;
}

core::ReplaceOptions ToCore(const ECReplaceOptions& o)
{
	core::ReplaceOptions r;
	r.search = ToCore(o.search);
	if (ECReplaceTargetSelection <= o.target && o.target <= ECReplaceTargetDeleteLine) {
		r.target = static_cast<core::ReplaceTarget>(o.target);
	}
	r.paste = o.paste;
	r.searchAll = o.searchAll;
	r.consecutiveAll = o.consecutiveAll;
	r.selectedArea = o.selectedArea;
	return r;
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

// ----- 查找、替换（第 32 步） -----

@interface ECSearchResult ()
- (instancetype)initWithStatus:(core::SearchStatus)status next:(core::SearchStatus)next count:(std::int32_t)count
						  view:(const core::SearchView&)view error:(const core::Text&)error;
@end

@implementation ECSearchResult

- (instancetype)initWithStatus:(core::SearchStatus)status next:(core::SearchStatus)next count:(std::int32_t)count
						  view:(const core::SearchView&)view error:(const core::Text&)error
{
	self = [super init];
	if (self) {
		_status = static_cast<ECSearchStatus>(status);
		_next = static_cast<ECSearchStatus>(next);
		_count = count;
		_view = FromCore(view);
		_error = ToNSString(error);
	}
	return self;
}

@end

@interface ECSearchMark ()
- (instancetype)initWithMark:(const core::SearchMark&)m;
@end

@implementation ECSearchMark

- (instancetype)initWithMark:(const core::SearchMark&)m
{
	self = [super init];
	if (self) {
		_from = m.from;
		_to = m.to;
		_color = static_cast<ECColorIndex>(m.color);
	}
	return self;
}

@end

@interface ECSyntaxColorRun ()
- (instancetype)initWithRun:(const core::SyntaxColorRun&)run;
@end

@implementation ECSyntaxColorRun

- (instancetype)initWithRun:(const core::SyntaxColorRun&)run
{
	self = [super init];
	if (self) {
		_from = run.from;
		_to = run.to;
		_color = static_cast<ECColorIndex>(run.color);
	}
	return self;
}

@end

@implementation ECSearchSettings
@end

@implementation ECTypeSetting

- (instancetype)initWithInfo:(const core::TypeSettingInfo&)info
{
	self = [super init];
	if (self) {
		_index = info.index;
		_name = ToNSString(info.name);
		_extensions = ToNSString(info.extensions);
	}
	return self;
}

@end

@implementation ECTypeSettingFileInfo

- (instancetype)initWithInfo:(const core::TypeSettingFileInfo&)info
{
	self = [super init];
	if (self) {
		_succeeded = info.succeeded;
		_message = ToNSString(info.message);
		_typeName = ToNSString(info.typeName);
		_version = ToNSString(info.version);
		_structureVersion = info.structureVersion;
		_versionDiffers = info.versionDiffers;
		NSMutableArray<NSString *> *files = [NSMutableArray array];
		for (const auto& f : info.colorFiles) [files addObject:ToNSString(f)];
		_colorFiles = files;
	}
	return self;
}

@end

@implementation ECTypeSettingImportResult

- (instancetype)initWithResult:(const core::TypeSettingImportResult&)r
{
	self = [super init];
	if (self) {
		_succeeded = r.succeeded;
		_message = ToNSString(r.message);
		_index = r.index;
		_added = r.added;
	}
	return self;
}

@end

@implementation ECColorItem

- (instancetype)initWithInfo:(const core::ColorItemInfo&)info
{
	self = [super init];
	if (self) {
		_index = info.index;
		_name = ToNSString(info.name);
		_key = ToNSString(info.key);
		_forceDisplay = info.forceDisplay;
		_noText = info.noText;
		_noBack = info.noBack;
		_noBold = info.noBold;
		_noUnderline = info.noUnderline;
	}
	return self;
}

@end

@implementation ECTypeSettingFileResult

- (instancetype)initWithResult:(const core::TypeSettingFileResult&)r
{
	self = [super init];
	if (self) {
		_succeeded = r.succeeded;
		_message = ToNSString(r.message);
		NSMutableDictionary<NSString *, NSString *> *values = [NSMutableDictionary dictionary];
		for (const auto& [key, value] : r.values) values[ToNSString(key)] = ToNSString(value);
		_values = values;
	}
	return self;
}

@end

@implementation ECEncodingChoice

- (instancetype)initWithChoice:(const core::EncodingChoice&)c
{
	self = [super init];
	if (self) {
		_encoding = c.code;
		_name = ToNSString(c.name);
	}
	return self;
}

@end

@implementation ECSaveCheck

- (instancetype)initWithCheck:(const core::SaveCheck&)c
{
	self = [super init];
	if (self) {
		_eolMixed = c.eolMixed ? YES : NO;
		_lostSome = c.lostSome ? YES : NO;
		_lostLine = c.lostAt.line;
		_lostColumn = c.lostAt.column;
		_lostCharacter = ToNSString(c.lostChar);
		_lostCharCode = ToNSString(c.lostCharCode);
	}
	return self;
}

@end

@implementation ECRecentFile

- (instancetype)initWithRecent:(const core::RecentFile&)r
{
	self = [super init];
	if (self) {
		_path = ToNSString(r.path);
		_encoding = r.encoding;
		_caret = FromCore(r.caret);
		_viewTopLine = r.viewTopLine;
		_favorite = r.favorite ? YES : NO;
		_menuLabel = ToNSString(r.menuLabel);
	}
	return self;
}

@end

@implementation ECMenuItem

- (instancetype)initWithItem:(const core::MenuItem&)m
{
	self = [super init];
	if (self) {
		_level = m.level;
		_type = static_cast<ECMenuItemType>(m.type);
		_command = m.code;
		_name = ToNSString(m.name);
		_accessKey = ToNSString(m.accessKey);
	}
	return self;
}

@end

@implementation ECKeyBinding

- (instancetype)initWithBinding:(const core::KeyBinding&)k
{
	self = [super init];
	if (self) {
		_keyCode = k.keyCode;
		_modifiers = k.modifiers;
		_command = k.code;
		_keyName = ToNSString(k.keyName);
	}
	return self;
}

@end

@implementation ECRecentFolder

- (instancetype)initWithRecent:(const core::RecentFolder&)r
{
	self = [super init];
	if (self) {
		_path = ToNSString(r.path);
		_favorite = r.favorite ? YES : NO;
		_menuLabel = ToNSString(r.menuLabel);
	}
	return self;
}

@end

@implementation ECRestoredView

- (instancetype)initWithView:(const core::RestoredView&)v
{
	self = [super init];
	if (self) {
		_caret = FromCore(v.caret);
		_viewTopLine = v.viewTopLine;
		_toEnd = v.toEnd ? YES : NO;
	}
	return self;
}

@end

namespace {

NSArray<ECEncodingChoice *> *ToChoices(const std::vector<core::EncodingChoice>& list)
{
	NSMutableArray<ECEncodingChoice *> *result = [NSMutableArray arrayWithCapacity:list.size()];
	for (const auto& c : list) {
		[result addObject:[[ECEncodingChoice alloc] initWithChoice:c]];
	}
	return result;
}

} // namespace

// タイプ別設定的导入・导出的文件（第 40 步）
static_assert(static_cast<NSInteger>(core::TypeSettingFile::Colors) == ECTypeSettingFileColors);
static_assert(static_cast<NSInteger>(core::TypeSettingFile::RegexKeywords) == ECTypeSettingFileRegexKeywords);
static_assert(static_cast<NSInteger>(core::TypeSettingFile::KeywordHelp) == ECTypeSettingFileKeywordHelp);

// 导入设置的结果（第 35 步）
static_assert(static_cast<NSInteger>(core::ImportResult::Imported) == ECImportResultImported);
static_assert(static_cast<NSInteger>(core::ImportResult::NotSettingsFile) == ECImportResultNotSettingsFile);
static_assert(static_cast<NSInteger>(core::ImportResult::ReadFailed) == ECImportResultReadFailed);
static_assert(static_cast<NSInteger>(core::ImportResult::WriteFailed) == ECImportResultWriteFailed);

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

+ (ECImportResult)checkSettingsFile:(NSString *)path
{
	return static_cast<ECImportResult>(core::CheckSettingsFile(ToText(path)));
}

+ (ECImportResult)importSettings:(NSString *)path
{
	return static_cast<ECImportResult>(core::ImportSettings(ToText(path)));
}

+ (BOOL)isSettingsImportPending
{
	return core::IsSettingsImportPending() ? YES : NO;
}

+ (NSString *)settingsBackupPath
{
	return ToNSString(core::SettingsBackupPath());
}

+ (NSString *)commonSettingInSection:(NSString *)section key:(NSString *)key
{
	const auto value = core::GetCommonSetting(ToText(section), ToText(key));
	return value ? ToNSString(*value) : nil;
}

+ (BOOL)setCommonSetting:(NSString *)value section:(NSString *)section key:(NSString *)key
{
	return core::SetCommonSetting(ToText(section), ToText(key), ToText(value)) ? YES : NO;
}

+ (BOOL)setCommonSettings:(NSDictionary<NSString *, NSString *> *)values section:(NSString *)section
{
	std::vector<std::pair<core::Text, core::Text>> items;
	items.reserve(values.count);
	for (NSString *key in values) {
		items.emplace_back(ToText(key), ToText(values[key]));
	}
	return core::SetCommonSettings(ToText(section), items) ? YES : NO;
}

+ (BOOL)saveSettings
{
	return core::SaveSettings() ? YES : NO;
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

+ (NSArray<ECTypeSetting *> *)typeSettings
{
	const auto list = core::TypeSettings();
	NSMutableArray<ECTypeSetting *> *result = [NSMutableArray arrayWithCapacity:list.size()];
	for (const auto& info : list) {
		[result addObject:[[ECTypeSetting alloc] initWithInfo:info]];
	}
	return result;
}

+ (NSInteger)maxTypeSettings { return core::MaxTypeSettings(); }
+ (NSInteger)addTypeSetting { return core::AddTypeSetting(); }
+ (NSInteger)copyTypeSetting:(NSInteger)index { return core::CopyTypeSetting(static_cast<std::int32_t>(index)); }
+ (BOOL)deleteTypeSetting:(NSInteger)index { return core::DeleteTypeSetting(static_cast<std::int32_t>(index)) ? YES : NO; }
+ (NSInteger)moveTypeSetting:(NSInteger)index up:(BOOL)up { return core::MoveTypeSetting(static_cast<std::int32_t>(index), up); }
+ (NSString *)initializeTypeSetting:(NSInteger)index { return ToNSString(core::InitializeTypeSetting(static_cast<std::int32_t>(index))); }

+ (ECTypeSettingFileInfo *)checkTypeSettingFile:(NSString *)path
{
	return [[ECTypeSettingFileInfo alloc] initWithInfo:core::CheckTypeSettingFile(ToText(path))];
}

+ (ECTypeSettingImportResult *)importTypeSetting:(NSString *)path index:(NSInteger)index addNew:(BOOL)addNew
	colorType:(NSInteger)colorType colorFile:(NSString *)colorFile
{
	core::TypeSettingImportChoice choice;
	choice.addNew = addNew;
	choice.colorType = static_cast<std::int32_t>(colorType);
	choice.colorFile = ToText(colorFile);
	return [[ECTypeSettingImportResult alloc] initWithResult:core::ImportTypeSetting(ToText(path), static_cast<std::int32_t>(index), choice)];
}

+ (ECTypeSettingFileResult *)exportTypeSetting:(NSInteger)index path:(NSString *)path
{
	return [[ECTypeSettingFileResult alloc] initWithResult:core::ExportTypeSetting(static_cast<std::int32_t>(index), ToText(path))];
}

+ (NSArray<ECColorItem *> *)colorItems
{
	NSMutableArray<ECColorItem *> *result = [NSMutableArray array];
	for (const auto& item : core::ColorItems()) [result addObject:[[ECColorItem alloc] initWithInfo:item]];
	return result;
}

+ (NSArray<NSString *> *)keywordSetNames
{
	NSMutableArray<NSString *> *result = [NSMutableArray array];
	for (const auto& name : core::KeywordSetNames()) [result addObject:ToNSString(name)];
	return result;
}

static std::vector<std::pair<core::Text, core::Text>> ToPairs(NSDictionary<NSString *, NSString *> *values)
{
	std::vector<std::pair<core::Text, core::Text>> items;
	for (NSString *key in [values.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
		items.emplace_back(ToText(key), ToText(values[key]));
	}
	return items;
}

+ (ECTypeSettingFileResult *)importTypeSettingFile:(ECTypeSettingFile)kind typeIndex:(NSInteger)typeIndex
	pending:(NSDictionary<NSString *, NSString *> *)pending path:(NSString *)path
{
	return [[ECTypeSettingFileResult alloc] initWithResult:core::ImportTypeSettingFile(
		static_cast<core::TypeSettingFile>(kind), static_cast<std::int32_t>(typeIndex), ToPairs(pending), ToText(path))];
}

+ (ECTypeSettingFileResult *)exportTypeSettingFile:(ECTypeSettingFile)kind typeIndex:(NSInteger)typeIndex
	pending:(NSDictionary<NSString *, NSString *> *)pending path:(NSString *)path
{
	return [[ECTypeSettingFileResult alloc] initWithResult:core::ExportTypeSettingFile(
		static_cast<core::TypeSettingFile>(kind), static_cast<std::int32_t>(typeIndex), ToPairs(pending), ToText(path))];
}

+ (BOOL)regexKeywordHasDelimiters:(NSString *)keyword
{
	return core::CheckRegexKeyword(ToText(keyword)).hasDelimiters ? YES : NO;
}

+ (BOOL)regexKeywordSyntaxOK:(NSString *)keyword
{
	return core::CheckRegexKeyword(ToText(keyword)).syntaxOK ? YES : NO;
}

+ (NSString *)keywordHelpDictionaryAbout:(NSString *)path
{
	const auto about = core::KeywordHelpDictionaryAbout(ToText(path));
	return about ? ToNSString(*about) : nil;
}

+ (BOOL)encodingCanBeDefault:(ECEncoding)encoding
{
	return core::EncodingCanBeDefault(static_cast<core::Encoding>(encoding)) ? YES : NO;
}

+ (NSArray<ECEncodingChoice *> *)encodingChoices
{
	return ToChoices(core::EncodingChoices());
}

+ (NSArray<ECEncodingChoice *> *)codePageChoices
{
	return ToChoices(core::CodePageChoices());
}

+ (BOOL)encodingCanHaveBOM:(ECEncoding)encoding
{
	if (!FitsInt32(encoding)) return NO;
	return core::EncodingCanHaveBom(static_cast<core::Encoding>(encoding)) ? YES : NO;
}

+ (BOOL)encodingBOMDefault:(ECEncoding)encoding
{
	if (!FitsInt32(encoding)) return NO;
	return core::EncodingBomDefault(static_cast<core::Encoding>(encoding)) ? YES : NO;
}

+ (NSArray<ECRecentFile *> *)recentFiles
{
	NSMutableArray<ECRecentFile *> *result = [NSMutableArray array];
	for (const auto& r : core::RecentFiles()) {
		[result addObject:[[ECRecentFile alloc] initWithRecent:r]];
	}
	return result;
}

+ (NSArray<ECMenuItem *> *)mainMenu
{
	NSMutableArray<ECMenuItem *> *result = [NSMutableArray array];
	for (const auto& m : core::MainMenu()) {
		[result addObject:[[ECMenuItem alloc] initWithItem:m]];
	}
	return result;
}

+ (NSArray<ECKeyBinding *> *)keyBindings
{
	NSMutableArray<ECKeyBinding *> *result = [NSMutableArray array];
	for (const auto& k : core::KeyBindings()) {
		[result addObject:[[ECKeyBinding alloc] initWithBinding:k]];
	}
	return result;
}

+ (ECCommand)commandForKeyCode:(NSInteger)keyCode modifiers:(ECKeyModifiers)modifiers
{
	if (keyCode < 0 || keyCode > 0xFFFF) return 0;
	return core::FunctionForKey(static_cast<std::uint16_t>(keyCode), static_cast<std::uint8_t>(modifiers & 7));
}

+ (NSArray<ECRecentFolder *> *)recentFolders
{
	NSMutableArray<ECRecentFolder *> *result = [NSMutableArray array];
	for (const auto& r : core::RecentFolders()) {
		[result addObject:[[ECRecentFolder alloc] initWithRecent:r]];
	}
	return result;
}

+ (nullable ECRecentFile *)recentFileForPath:(NSString *)path
{
	const auto r = core::FindRecentFile(ToText(path));
	return r ? [[ECRecentFile alloc] initWithRecent:*r] : nil;
}

+ (void)removeRecentFileAtPath:(NSString *)path
{
	core::RemoveRecentFile(ToText(path));
}

+ (void)clearRecentFiles
{
	core::ClearRecentFiles();
}

+ (void)clearRecentFolders
{
	core::ClearRecentFolders();
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

+ (BOOL)zoomFontSize:(double)base zoom:(double)zoom steps:(NSInteger)steps unit:(double)unit
	size:(double *)outSize newZoom:(double *)outZoom
{
	if (!FitsInt32(steps)) return NO;
	const auto r = core::ZoomFontSize(base, zoom, static_cast<std::int32_t>(steps), unit);
	if (!r) return NO;
	if (outSize) *outSize = r->pointSize;
	if (outZoom) *outZoom = r->zoom;
	return YES;
}

// ----- 查找、替换（第 32 步） -----

+ (ECSearchSettings *)searchSettings
{
	const core::SearchSettings v = core::GetSearchSettings();
	ECSearchSettings *r = [[ECSearchSettings alloc] init];
	r.options = FromCore(v.options);
	r.notifyNotFound = v.notifyNotFound;
	r.autoCloseFind = v.autoCloseFind;
	r.autoCloseReplace = v.autoCloseReplace;
	r.searchAll = v.searchAll;
	r.consecutiveAll = v.consecutiveAll;
	r.selectedArea = v.selectedArea;
	r.caretTextForSearch = v.caretTextForSearch;
	r.inheritKeyOtherView = v.inheritKeyOtherView;
	r.jumpLineNumIsCRLF = v.jumpLineNumIsCRLF;
	return r;
}

+ (void)setSearchSettings:(ECSearchSettings *)s
{
	core::SearchSettings v;
	v.options = ToCore(s.options);
	v.notifyNotFound = s.notifyNotFound;
	v.autoCloseFind = s.autoCloseFind;
	v.autoCloseReplace = s.autoCloseReplace;
	v.searchAll = s.searchAll;
	v.consecutiveAll = s.consecutiveAll;
	v.selectedArea = s.selectedArea;
	v.caretTextForSearch = s.caretTextForSearch;
	v.inheritKeyOtherView = s.inheritKeyOtherView;
	v.jumpLineNumIsCRLF = s.jumpLineNumIsCRLF;
	core::SetSearchSettings(v);
}

+ (NSArray<NSString *> *)searchKeyHistory
{
	NSMutableArray<NSString *> *r = [NSMutableArray array];
	for (const auto& t : core::SearchKeyHistory()) [r addObject:ToNSString(t)];
	return r;
}

+ (NSArray<NSString *> *)replaceKeyHistory
{
	NSMutableArray<NSString *> *r = [NSMutableArray array];
	for (const auto& t : core::ReplaceKeyHistory()) [r addObject:ToNSString(t)];
	return r;
}

+ (void)addSearchKey:(NSString *)key { core::AddSearchKey(ToText(key)); }
+ (ECMigemoStatus)prepareMigemo { return static_cast<ECMigemoStatus>(core::PrepareMigemo()); }

+ (NSArray<NSString *> *)tagJumpKeywordHistory
{
	NSMutableArray<NSString *> *result = [NSMutableArray array];
	for (const auto& k : core::TagJumpKeywordHistory()) [result addObject:ToNSString(k)];
	return result;
}
+ (void)addTagJumpKeyword:(NSString *)keyword { core::AddTagJumpKeyword(ToText(keyword)); }

+ (NSString *)windowListLabelForPath:(NSString *)path untitledId:(NSInteger)untitledId modified:(BOOL)modified
	encoding:(ECEncoding)encoding grepKey:(nullable NSString *)grepKey index:(NSInteger)index
{
	core::WindowListEntry e;
	e.path = ToText(path);
	e.untitledId = static_cast<std::int32_t>(std::clamp<NSInteger>(untitledId, -1, INT32_MAX));
	e.modified = modified == YES;
	e.encoding = static_cast<core::Encoding>(encoding);
	e.grep = grepKey != nil;
	if (grepKey) e.grepKey = ToText(grepKey);
	return ToNSString(core::WindowListLabel(e, static_cast<std::int32_t>(std::clamp<NSInteger>(index, -1, INT32_MAX))));
}

+ (NSInteger)fileMatchScore:(NSString *)file1 with:(NSString *)file2 { return core::FileMatchScore(ToText(file1), ToText(file2)); }
+ (void)resetMigemo { core::ResetMigemo(); }
+ (void)addReplaceKey:(NSString *)key { core::AddReplaceKey(ToText(key)); }
+ (NSInteger)searchKeySequence { return core::SearchKeySequence(); }
+ (NSInteger)replaceKeySequence { return core::ReplaceKeySequence(); }

+ (NSString *)regexpVersion { return ToNSString(core::RegexpVersion()); }

+ (NSString *)regexpSyntaxErrorForPattern:(NSString *)pattern matchCase:(BOOL)matchCase
{
	const auto error = core::RegexpSyntaxError(ToText(pattern), matchCase == YES);
	return error ? ToNSString(*error) : nil;
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

// 第 29 步的编辑命令用
namespace {

std::int32_t ClampInt32(NSInteger v)
{
	return static_cast<std::int32_t>(std::clamp<NSInteger>(v, INT32_MIN / 2, INT32_MAX / 2));
}

core::BoxRange ToCore(ECBoxRange b)
{
	return core::BoxRange{ ClampInt32(b.top), ClampInt32(b.bottom), ClampInt32(b.left), ClampInt32(b.right) };
}

core::LayoutPosition ToCore(ECLayoutPosition p)
{
	return core::LayoutPosition{ ClampInt32(p.line), ClampInt32(p.x) };
}

} // namespace

@implementation ECKeywordSetEditor {
	std::unique_ptr<core::KeywordSetEditor> _editor;
}

- (instancetype)init
{
	self = [super init];
	if (self) {
		_editor = core::KeywordSetEditor::Create();
		if (!_editor) return nil;
	}
	return self;
}

- (NSInteger)setCount { return _editor->SetCount(); }
- (NSString *)nameOfSet:(NSInteger)set { return ToNSString(_editor->SetName(static_cast<std::int32_t>(set))); }
- (BOOL)isCaseSensitive:(NSInteger)set { return _editor->IsCaseSensitive(static_cast<std::int32_t>(set)) ? YES : NO; }
- (NSInteger)currentSet { return _editor->CurrentSet(); }
- (void)setCurrentSet:(NSInteger)set { _editor->SetCurrentSet(static_cast<std::int32_t>(set)); }

- (NSArray<NSString *> *)keywordsOfSet:(NSInteger)set
{
	NSMutableArray<NSString *> *result = [NSMutableArray array];
	for (const auto& k : _editor->Keywords(static_cast<std::int32_t>(set))) [result addObject:ToNSString(k.text)];
	return result;
}

- (NSArray<NSNumber *> *)keywordIndicesOfSet:(NSInteger)set
{
	NSMutableArray<NSNumber *> *result = [NSMutableArray array];
	for (const auto& k : _editor->Keywords(static_cast<std::int32_t>(set))) [result addObject:@(k.index)];
	return result;
}

- (NSInteger)freeCountOfSet:(NSInteger)set { return _editor->FreeCount(static_cast<std::int32_t>(set)); }
- (BOOL)canAddKeywordToSet:(NSInteger)set { return _editor->CanAddKeyword(static_cast<std::int32_t>(set)) ? YES : NO; }
- (BOOL)addSet:(NSString *)name { return _editor->AddSet(ToText(name)) ? YES : NO; }
- (BOOL)deleteSet:(NSInteger)set { return _editor->DeleteSet(static_cast<std::int32_t>(set)) ? YES : NO; }
- (void)renameSet:(NSInteger)set to:(NSString *)name { _editor->RenameSet(static_cast<std::int32_t>(set), ToText(name)); }
- (void)setCaseSensitive:(BOOL)on ofSet:(NSInteger)set { _editor->SetCaseSensitive(static_cast<std::int32_t>(set), on); }
- (NSInteger)addKeyword:(NSString *)keyword toSet:(NSInteger)set { return _editor->AddKeyword(static_cast<std::int32_t>(set), ToText(keyword)); }
- (BOOL)updateKeyword:(NSInteger)index ofSet:(NSInteger)set to:(NSString *)keyword
{
	return _editor->UpdateKeyword(static_cast<std::int32_t>(set), static_cast<std::int32_t>(index), ToText(keyword)) ? YES : NO;
}
- (void)deleteKeyword:(NSInteger)index ofSet:(NSInteger)set { _editor->DeleteKeyword(static_cast<std::int32_t>(set), static_cast<std::int32_t>(index)); }
- (NSInteger)cleanSet:(NSInteger)set { return _editor->Clean(static_cast<std::int32_t>(set)); }

- (BOOL)importToSet:(NSInteger)set path:(NSString *)path message:(NSString **)message
{
	core::Text text;
	const bool ok = _editor->Import(static_cast<std::int32_t>(set), ToText(path), text);
	if (message) *message = ToNSString(text);
	return ok ? YES : NO;
}

- (BOOL)exportSet:(NSInteger)set path:(NSString *)path message:(NSString **)message
{
	core::Text text;
	const bool ok = _editor->Export(static_cast<std::int32_t>(set), ToText(path), text);
	if (message) *message = ToNSString(text);
	return ok ? YES : NO;
}

- (NSDictionary<NSString *, NSString *> *)iniValues
{
	NSMutableDictionary<NSString *, NSString *> *result = [NSMutableDictionary dictionary];
	for (const auto& [key, value] : _editor->IniValues()) result[ToNSString(key)] = ToNSString(value);
	return result;
}

@end

@implementation ECMainMenuEntry
- (instancetype)initWithLevel:(NSInteger)level isNode:(BOOL)isNode code:(NSInteger)code name:(NSString *)name accessKey:(NSString *)accessKey
{
	self = [super init];
	if (self) {
		_level = level;
		_isNode = isNode;
		_code = code;
		_name = [name copy];
		_accessKey = [accessKey copy];
	}
	return self;
}
@end

@implementation ECCommandSettingsEditor {
	std::unique_ptr<core::CommandSettingsEditor> _editor;
}

- (instancetype)init
{
	self = [super init];
	if (self) {
		_editor = core::CommandSettingsEditor::Create();
		if (!_editor) return nil;
	}
	return self;
}

- (NSArray<NSString *> *)functionCategories
{
	NSMutableArray<NSString *> *result = [NSMutableArray array];
	for (const auto& name : _editor->FunctionCategories()) [result addObject:ToNSString(name)];
	return result;
}

- (NSArray<NSNumber *> *)functionCodesInCategory:(NSInteger)category
{
	NSMutableArray<NSNumber *> *result = [NSMutableArray array];
	for (const auto& f : _editor->Functions(ClampInt32(category))) [result addObject:@(f.code)];
	return result;
}

- (NSArray<NSString *> *)functionNamesInCategory:(NSInteger)category
{
	NSMutableArray<NSString *> *result = [NSMutableArray array];
	for (const auto& f : _editor->Functions(ClampInt32(category))) [result addObject:ToNSString(f.name)];
	return result;
}

- (NSString *)nameOfFunction:(NSInteger)code { return ToNSString(_editor->FunctionName(ClampInt32(code))); }
- (NSInteger)keyCount { return _editor->KeyCount(); }
- (NSString *)nameOfKey:(NSInteger)key { return ToNSString(_editor->KeyName(ClampInt32(key))); }

- (NSInteger)functionOfKey:(NSInteger)key modifiers:(NSInteger)modifiers
{
	if (modifiers < 0 || 8 <= modifiers) return 0;
	return _editor->KeyFunction(ClampInt32(key), static_cast<std::uint8_t>(modifiers));
}

- (void)setFunction:(NSInteger)code ofKey:(NSInteger)key modifiers:(NSInteger)modifiers
{
	if (modifiers < 0 || 8 <= modifiers) return;
	_editor->SetKeyFunction(ClampInt32(key), static_cast<std::uint8_t>(modifiers), ClampInt32(code));
}

- (NSArray<NSString *> *)keysAssignedToFunction:(NSInteger)code
{
	NSMutableArray<NSString *> *result = [NSMutableArray array];
	for (const auto& name : _editor->AssignedKeys(ClampInt32(code))) [result addObject:ToNSString(name)];
	return result;
}

- (BOOL)importKeyBindFromPath:(NSString *)path message:(NSString **)message
{
	core::Text text;
	const bool ok = _editor->ImportKeyBind(ToText(path), text);
	if (message) *message = ToNSString(text);
	return ok ? YES : NO;
}

- (BOOL)exportKeyBindToPath:(NSString *)path message:(NSString **)message
{
	core::Text text;
	const bool ok = _editor->ExportKeyBind(ToText(path), text);
	if (message) *message = ToNSString(text);
	return ok ? YES : NO;
}

- (NSArray<ECMainMenuEntry *> *)mainMenuEntries
{
	NSMutableArray<ECMainMenuEntry *> *result = [NSMutableArray array];
	for (const auto& e : _editor->MainMenuEntries()) {
		[result addObject:[[ECMainMenuEntry alloc] initWithLevel:e.level isNode:e.isNode code:e.code
			name:ToNSString(e.name) accessKey:ToNSString(e.accessKey)]];
	}
	return result;
}

- (BOOL)mainMenuKeyParentheses { return _editor->MainMenuKeyParentheses() ? YES : NO; }

- (BOOL)setMainMenu:(NSArray<ECMainMenuEntry *> *)entries keyParentheses:(BOOL)keyParentheses
{
	std::vector<core::CommandSettingsEditor::MainMenuEntry> list;
	for (ECMainMenuEntry *e in entries) {
		list.push_back({ ClampInt32(e.level), e.isNode ? true : false, ClampInt32(e.code), ToText(e.name), ToText(e.accessKey) });
	}
	return _editor->SetMainMenu(list, keyParentheses) ? YES : NO;
}

- (void)initializeMainMenu { _editor->InitializeMainMenu(); }
- (NSString *)specialFunctionCategory { return ToNSString(_editor->SpecialFunctionCategory()); }

- (NSArray<NSNumber *> *)specialFunctionCodes
{
	NSMutableArray<NSNumber *> *result = [NSMutableArray array];
	for (const auto& f : _editor->SpecialFunctions()) [result addObject:@(f.code)];
	return result;
}

- (NSArray<NSString *> *)specialFunctionNames
{
	NSMutableArray<NSString *> *result = [NSMutableArray array];
	for (const auto& f : _editor->SpecialFunctions()) [result addObject:ToNSString(f.name)];
	return result;
}

- (BOOL)importMainMenuFromPath:(NSString *)path message:(NSString **)message
{
	core::Text text;
	const bool ok = _editor->ImportMainMenu(ToText(path), text);
	if (message) *message = ToNSString(text);
	return ok ? YES : NO;
}

- (BOOL)exportMainMenuToPath:(NSString *)path message:(NSString **)message
{
	core::Text text;
	const bool ok = _editor->ExportMainMenu(ToText(path), text);
	if (message) *message = ToNSString(text);
	return ok ? YES : NO;
}

- (NSInteger)customMenuCount { return _editor->CustomMenuCount(); }
- (NSInteger)maxCustomMenuItems { return _editor->MaxCustomMenuItems(); }
- (NSString *)displayNameOfCustomMenu:(NSInteger)menu { return ToNSString(_editor->CustomMenuDisplayName(ClampInt32(menu))); }
- (NSString *)nameOfCustomMenu:(NSInteger)menu { return ToNSString(_editor->CustomMenuName(ClampInt32(menu))); }
- (void)setName:(NSString *)name ofCustomMenu:(NSInteger)menu { _editor->SetCustomMenuName(ClampInt32(menu), ToText(name)); }
- (BOOL)customMenuIsSubmenu:(NSInteger)menu { return _editor->CustomMenuIsSubmenu(ClampInt32(menu)) ? YES : NO; }
- (void)setCustomMenu:(NSInteger)menu isSubmenu:(BOOL)on { _editor->SetCustomMenuIsSubmenu(ClampInt32(menu), on); }

- (NSArray<NSNumber *> *)codesOfCustomMenu:(NSInteger)menu
{
	NSMutableArray<NSNumber *> *result = [NSMutableArray array];
	for (const auto& item : _editor->CustomMenuItems(ClampInt32(menu))) [result addObject:@(item.code)];
	return result;
}

- (NSArray<NSString *> *)accessKeysOfCustomMenu:(NSInteger)menu
{
	NSMutableArray<NSString *> *result = [NSMutableArray array];
	for (const auto& item : _editor->CustomMenuItems(ClampInt32(menu))) {
		[result addObject:item.accessKey ? ToNSString(core::Text(1, item.accessKey)) : @""];
	}
	return result;
}

- (void)setCustomMenu:(NSInteger)menu codes:(NSArray<NSNumber *> *)codes accessKeys:(NSArray<NSString *> *)keys
{
	std::vector<core::CommandSettingsEditor::CustomMenuItem> items;
	for (NSUInteger i = 0; i < codes.count; ++i) {
		const core::Text key = i < keys.count ? ToText(keys[i]) : core::Text();
		items.push_back({ ClampInt32(codes[i].integerValue), key.empty() ? char16_t(0) : key[0] });
	}
	_editor->SetCustomMenuItems(ClampInt32(menu), items);
}

- (BOOL)importCustomMenuFromPath:(NSString *)path message:(NSString **)message
{
	core::Text text;
	const bool ok = _editor->ImportCustomMenu(ToText(path), text);
	if (message) *message = ToNSString(text);
	return ok ? YES : NO;
}

- (BOOL)exportCustomMenuToPath:(NSString *)path message:(NSString **)message
{
	core::Text text;
	const bool ok = _editor->ExportCustomMenu(ToText(path), text);
	if (message) *message = ToNSString(text);
	return ok ? YES : NO;
}

- (NSArray<NSNumber *> *)toolbarButtons
{
	NSMutableArray<NSNumber *> *result = [NSMutableArray array];
	for (const auto n : _editor->ToolbarButtons()) [result addObject:@(n)];
	return result;
}

- (BOOL)toolbarIsFlat { return _editor->ToolbarIsFlat() ? YES : NO; }

- (void)setToolbarButtons:(NSArray<NSNumber *> *)buttons flat:(BOOL)flat
{
	std::vector<std::int32_t> list;
	for (NSNumber *n in buttons) list.push_back(ClampInt32(n.integerValue));
	_editor->SetToolbar(list, flat);
}

- (NSInteger)kindOfToolbarButton:(NSInteger)number { return static_cast<NSInteger>(_editor->ToolbarButton(ClampInt32(number)).kind); }
- (NSInteger)functionOfToolbarButton:(NSInteger)number { return _editor->ToolbarButton(ClampInt32(number)).code; }
- (NSInteger)iconOfToolbarButton:(NSInteger)number { return _editor->ToolbarButton(ClampInt32(number)).icon; }
- (NSInteger)toolbarButtonForFunction:(NSInteger)code { return _editor->ToolbarButtonNumber(ClampInt32(code)); }
- (NSInteger)toolbarSeparatorButton { return _editor->ToolbarSeparatorNumber(); }
- (NSInteger)toolbarWrapButton { return _editor->ToolbarWrapNumber(); }

- (NSDictionary<NSString *, NSString *> *)iniValuesOfSection:(NSString *)section
{
	NSMutableDictionary<NSString *, NSString *> *result = [NSMutableDictionary dictionary];
	for (const auto& [key, value] : _editor->IniValues(ToText(section))) result[ToNSString(key)] = ToNSString(value);
	return result;
}

@end

// ---------------------------------------------------------------------------
// アウトライン解析（第 42 步）
// ---------------------------------------------------------------------------

static_assert(ECOutlineTypeDefault == static_cast<NSInteger>(core::OutlineType::Default));
static_assert(ECOutlineTypeCpp == static_cast<NSInteger>(core::OutlineType::Cpp));
static_assert(ECOutlineTypeBookmark == static_cast<NSInteger>(core::OutlineType::Bookmark));
static_assert(ECOutlineTypeList == static_cast<NSInteger>(core::OutlineType::List));
static_assert(ECOutlineSortZtoA == static_cast<NSInteger>(core::OutlineSort::ZtoA));

@implementation ECOutlineItem

- (instancetype)initWithItem:(const core::OutlineItem&)item
{
	self = [super init];
	if (self) {
		_line = item.line;
		_column = item.column;
		_layoutLine = item.layoutLine;
		_layoutColumn = item.layoutColumn;
		_name = ToNSString(item.name);
		_fileName = ToNSString(item.fileName);
		_info = item.info;
		_depth = item.depth;
	}
	return self;
}

@end

@implementation ECOutlineNode

- (instancetype)initWithNode:(const core::OutlineNode&)node
{
	self = [super init];
	if (self) {
		_label = ToNSString(node.label);
		_item = node.item;
		_order = node.order;
		_expanded = node.expanded ? YES : NO;
		NSMutableArray<ECOutlineNode *> *children = [NSMutableArray arrayWithCapacity:node.children.size()];
		for (const auto& child : node.children) [children addObject:[[ECOutlineNode alloc] initWithNode:child]];
		_children = children;
	}
	return self;
}

@end

@implementation ECOutlineRow

- (instancetype)initWithRow:(const core::OutlineRow&)row
{
	self = [super init];
	if (self) {
		_item = row.item;
		_line = row.line;
		_column = row.column;
		_name = ToNSString(row.name);
		_remark = ToNSString(row.remark);
	}
	return self;
}

@end

@implementation ECOutlineResult {
	core::OutlineResult _result;
}

- (instancetype)initWithResult:(core::OutlineResult)result
{
	self = [super init];
	if (self) {
		_result = std::move(result);
		NSMutableArray<ECOutlineItem *> *items = [NSMutableArray arrayWithCapacity:_result.items.size()];
		for (const auto& item : _result.items) [items addObject:[[ECOutlineItem alloc] initWithItem:item]];
		_items = items;
		[self update];
	}
	return self;
}

//! 并べ替えた後のツリー・リスト
- (void)update
{
	NSMutableArray<ECOutlineNode *> *tree = [NSMutableArray arrayWithCapacity:_result.tree.size()];
	for (const auto& node : _result.tree) [tree addObject:[[ECOutlineNode alloc] initWithNode:node]];
	_tree = tree;
	NSMutableArray<ECOutlineRow *> *rows = [NSMutableArray arrayWithCapacity:_result.rows.size()];
	for (const auto& row : _result.rows) [rows addObject:[[ECOutlineRow alloc] initWithRow:row]];
	_rows = rows;
	_columnTitles = @[ ToNSString(_result.columnTitles[0]), ToNSString(_result.columnTitles[1]),
					   ToNSString(_result.columnTitles[2]), ToNSString(_result.columnTitles[3]) ];
}

- (ECOutlineType)type { return static_cast<ECOutlineType>(_result.type); }
- (ECOutlineType)listType { return static_cast<ECOutlineType>(_result.listType); }
- (NSString *)title { return ToNSString(_result.title); }
- (NSString *)filePath { return ToNSString(_result.filePath); }
- (BOOL)isTree { return _result.isTree ? YES : NO; }
- (NSString *)clipText { return ToNSString(_result.clipText); }
- (ECOutlineSort)sort { return static_cast<ECOutlineSort>(_result.sort); }
- (NSInteger)sortColumn { return _result.sortColumn; }
- (BOOL)sortDescending { return _result.sortDescending ? YES : NO; }
- (BOOL)lineNumIsCRLF { return _result.lineNumIsCRLF ? YES : NO; }

- (void)sortTree:(ECOutlineSort)sort
{
	if (sort < ECOutlineSortDefault || ECOutlineSortZtoA < sort) return;
	core::SortOutlineTree(_result, static_cast<core::OutlineSort>(sort));
	[self update];
}

- (void)sortRowsByColumn:(NSInteger)column descending:(BOOL)descending
{
	core::SortOutlineRows(_result, ClampInt32(column), descending == YES);
	[self update];
}

- (NSInteger)itemAtLayoutLine:(NSInteger)layoutLine column:(NSInteger)layoutColumn
{
	return core::OutlineItemAt(_result, ClampInt32(layoutLine), ClampInt32(layoutColumn));
}

- (NSArray<NSNumber *> *)nodePathForItem:(NSInteger)item
{
	NSMutableArray<NSNumber *> *path = [NSMutableArray array];
	for (std::int32_t i : core::OutlineNodePath(_result, ClampInt32(item))) [path addObject:@(i)];
	return path;
}

@end

// ---------------------------------------------------------------------------
// Grep・Grep置換（第 43 步）
// ---------------------------------------------------------------------------

static_assert(ECGrepHistoryFile == static_cast<NSInteger>(core::GrepHistory::File));
static_assert(ECGrepHistoryExcludeFolder == static_cast<NSInteger>(core::GrepHistory::ExcludeFolder));

@interface ECGrepOptions ()
- (core::GrepOptions)coreOptions;
@end

@interface ECGrepSourceText ()
- (core::GrepSourceText)coreSource;
@end

@interface ECGrepResult ()
- (instancetype)initWithResult:(const core::GrepResult&)result;
@end

@interface ECGrepDialogCheck ()
- (instancetype)initWithCheck:(const core::GrepDialogCheck&)check;
@end

@interface ECTagJumpTarget ()
- (instancetype)initWithTarget:(const core::TagJumpTarget&)target;
@end

@interface ECExpandParameterView ()
- (core::ExpandParameterView)coreView;
@end

@interface ECFileTreeRoot ()
- (instancetype)initWithRoot:(const core::FileTreeRoot&)root;
@end

@interface ECFileTreeListing ()
- (instancetype)initWithListing:(const core::FileTreeListing&)listing;
@end

@implementation ECGrepOptions

- (instancetype)init
{
	self = [super init];
	if (self) {
		const core::GrepOptions defaults;
		_key = @"";
		_replacement = @"";
		_files = @"";
		_folders = @"";
		_charSet = defaults.charSet;
		_outputStyle = defaults.outputStyle;
		_outputLineType = defaults.outputLineType;
		_header = YES;
	}
	return self;
}

- (core::GrepOptions)coreOptions
{
	core::GrepOptions o;
	o.key = ToText(_key);
	o.replacement = ToText(_replacement);
	o.files = ToText(_files);
	o.folders = ToText(_folders);
	o.search.regularExpression = _regularExpression == YES;
	o.search.matchCase = _matchCase == YES;
	o.search.wholeWord = _wholeWord == YES;
	o.subFolder = _subFolder == YES;
	o.charSet = static_cast<core::Encoding>(_charSet);
	o.outputStyle = ClampInt32(_outputStyle);
	o.outputLineType = ClampInt32(_outputLineType);
	o.fileOnly = _fileOnly == YES;
	o.baseFolder = _baseFolder == YES;
	o.separateFolder = _separateFolder == YES;
	o.exceptFileRegexp = _exceptFileRegexp == YES;
	o.header = _header == YES;
	o.replace = _replace == YES;
	o.paste = _paste == YES;
	o.backup = _backup == YES;
	if (_pasteText) o.pasteText = ToText(_pasteText);
	return o;
}

@end

@implementation ECGrepSourceText

- (instancetype)init
{
	self = [super init];
	if (self) {
		_filePath = @"";
		_windowLabel = @"";
		_encoding = ECEncodingUTF8;
		_lines = @[];
	}
	return self;
}

- (core::GrepSourceText)coreSource
{
	core::GrepSourceText source;
	source.id = _sourceID;
	source.filePath = ToText(_filePath);
	source.windowLabel = ToText(_windowLabel);
	source.isGrep = _isGrep == YES;
	source.encoding = static_cast<core::Encoding>(_encoding);
	source.lines.reserve(_lines.count);
	for (NSString *line in _lines) source.lines.push_back(ToText(line));
	return source;
}

@end

@implementation ECGrepResult

- (instancetype)initWithResult:(const core::GrepResult&)result
{
	self = [super init];
	if (self) {
		_hitCount = result.hitCount;
		_cancelled = result.cancelled ? YES : NO;
		_errorMessage = ToNSString(result.errorMessage);
	}
	return self;
}

@end

@implementation ECGrepSession {
	std::unique_ptr<core::GrepSession> _session;
}

- (instancetype)initWithOptions:(ECGrepOptions *)options sources:(NSArray<ECGrepSourceText *> *)sources
{
	self = [super init];
	if (self) {
		std::vector<core::GrepSourceText> coreSources;
		for (ECGrepSourceText *source in sources) coreSources.push_back([source coreSource]);
		_session = std::make_unique<core::GrepSession>([options coreOptions], std::move(coreSources));
	}
	return self;
}

- (ECGrepResult *)run { return [[ECGrepResult alloc] initWithResult:_session->Run()]; }
- (void)cancel { _session->Cancel(); }
- (BOOL)realTimeView { return _session->IsRealTimeView() ? YES : NO; }
- (void)setRealTimeView:(BOOL)realTimeView { _session->SetRealTimeView(realTimeView == YES); }
- (BOOL)isRunning { return _session->IsRunning() ? YES : NO; }
- (NSString *)takeOutput { return ToNSString(_session->TakeOutput()); }
- (NSInteger)progressHitCount { return _session->Progress().hitCount; }
- (NSString *)progressFile { return ToNSString(_session->Progress().file); }
- (NSString *)progressFolder { return ToNSString(_session->Progress().folder); }

@end

@implementation ECGrepDialogCheck

- (instancetype)initWithCheck:(const core::GrepDialogCheck&)check
{
	self = [super init];
	if (self) {
		_error = ToNSString(check.error);
		_file = ToNSString(check.file);
		_folders = ToNSString(check.folders);
	}
	return self;
}

@end

@implementation ECTagJumpTarget

- (instancetype)initWithTarget:(const core::TagJumpTarget&)target
{
	self = [super init];
	if (self) {
		_path = ToNSString(target.path);
		_hasSourceID = target.sourceId ? YES : NO;
		_sourceID = target.sourceId.value_or(0);
		_line = target.line;
		_column = target.column;
	}
	return self;
}

@end

// ----- ファイルツリー -----

@implementation ECFileTreeItem

- (instancetype)init
{
	self = [super init];
	if (self) {
		_type = ECFileTreeItemTypeGrep;
		_path = @"";
		_label = @"";
		_file = @"*.*";
		_ignoreHidden = YES;
	}
	return self;
}

- (id)copyWithZone:(NSZone *)zone
{
	ECFileTreeItem *item = [[ECFileTreeItem allocWithZone:zone] init];
	item.type = _type;
	item.path = _path;
	item.label = _label;
	item.depth = _depth;
	item.file = _file;
	item.ignoreHidden = _ignoreHidden;
	item.ignoreReadOnly = _ignoreReadOnly;
	item.ignoreSystem = _ignoreSystem;
	return item;
}

@end

namespace {

ECFileTreeItem *ToFileTreeItem(const core::FileTreeItem& item)
{
	ECFileTreeItem *result = [[ECFileTreeItem alloc] init];
	result.type = static_cast<ECFileTreeItemType>(item.type);
	result.path = ToNSString(item.path);
	result.label = ToNSString(item.label);
	result.depth = item.depth;
	result.file = ToNSString(item.file);
	result.ignoreHidden = item.ignoreHidden;
	result.ignoreReadOnly = item.ignoreReadOnly;
	result.ignoreSystem = item.ignoreSystem;
	return result;
}

core::FileTreeItem FromFileTreeItem(ECFileTreeItem *item)
{
	core::FileTreeItem result;
	result.type = static_cast<core::FileTreeItemType>(item.type);
	result.path = ToText(item.path);
	result.label = ToText(item.label);
	result.depth = static_cast<std::int32_t>(item.depth);
	result.file = ToText(item.file);
	result.ignoreHidden = item.ignoreHidden;
	result.ignoreReadOnly = item.ignoreReadOnly;
	result.ignoreSystem = item.ignoreSystem;
	return result;
}

NSArray<ECFileTreeItem *> *ToFileTreeItems(const std::vector<core::FileTreeItem>& items)
{
	NSMutableArray<ECFileTreeItem *> *result = [NSMutableArray array];
	for (const auto& item : items) [result addObject:ToFileTreeItem(item)];
	return result;
}

std::vector<core::FileTreeItem> FromFileTreeItems(NSArray<ECFileTreeItem *> *items)
{
	std::vector<core::FileTreeItem> result;
	for (ECFileTreeItem *item in items) result.push_back(FromFileTreeItem(item));
	return result;
}

} // namespace

@interface ECFileTreeSetting ()
- (instancetype)initWithSetting:(const core::FileTreeSetting&)setting;
- (void)assign:(const core::FileTreeSetting&)setting;
- (core::FileTreeSetting)coreSetting;
@end

@implementation ECFileTreeSetting

- (instancetype)init
{
	self = [super init];
	if (self) {
		_project = YES;
		_defaultProjectIni = @"";
		_loadedIni = @"";
		_iniFolder = @"";
		_items = @[];
	}
	return self;
}

- (instancetype)initWithSetting:(const core::FileTreeSetting&)setting
{
	self = [super init];
	if (self) {
		[self assign:setting];
	}
	return self;
}

- (void)assign:(const core::FileTreeSetting&)setting
{
	_origin = static_cast<ECFileTreeSettingFrom>(setting.origin);
	_loadedFrom = static_cast<ECFileTreeSettingFrom>(setting.loadedFrom);
	_project = setting.project;
	_defaultProjectIni = ToNSString(setting.defaultProjectIni);
	_loadedIni = ToNSString(setting.loadedIni);
	_iniFolder = ToNSString(setting.iniFolder);
	_items = ToFileTreeItems(setting.items);
}

- (core::FileTreeSetting)coreSetting
{
	core::FileTreeSetting setting;
	setting.origin = static_cast<core::FileTreeSettingFrom>(_origin);
	setting.loadedFrom = static_cast<core::FileTreeSettingFrom>(_loadedFrom);
	setting.project = _project;
	setting.defaultProjectIni = ToText(_defaultProjectIni);
	setting.loadedIni = ToText(_loadedIni);
	setting.iniFolder = ToText(_iniFolder);
	setting.items = FromFileTreeItems(_items);
	return setting;
}

@end

@implementation ECFileTreeRoot

- (instancetype)initWithRoot:(const core::FileTreeRoot&)root
{
	self = [super init];
	if (self) {
		_itemIndex = root.itemIndex;
		_type = static_cast<ECFileTreeItemType>(root.type);
		_label = ToNSString(root.label);
		_path = ToNSString(root.path);
		_depth = root.depth;
	}
	return self;
}

@end

@implementation ECFileTreeListing

- (instancetype)initWithListing:(const core::FileTreeListing&)listing
{
	self = [super init];
	if (self) {
		_wildcardError = listing.wildcardError;
		NSMutableArray<NSString *> *folders = [NSMutableArray array];
		for (const auto& name : listing.folders) [folders addObject:ToNSString(name)];
		NSMutableArray<NSString *> *files = [NSMutableArray array];
		for (const auto& name : listing.files) [files addObject:ToNSString(name)];
		_folders = folders;
		_files = files;
	}
	return self;
}

@end

@implementation ECFileTree

+ (NSInteger)maxItems
{
	return core::kFileTreeMaxItems;
}

+ (ECFileTreeSetting *)loadSettingForType:(NSInteger)typeIndex folder:(NSString *)folder
{
	return [[ECFileTreeSetting alloc] initWithSetting:core::LoadFileTreeSetting(static_cast<std::int32_t>(typeIndex), ToText(folder))];
}

+ (BOOL)loadDefaultIni:(NSString *)path into:(ECFileTreeSetting *)setting
{
	core::FileTreeSetting s = [setting coreSetting];
	const bool ok = core::LoadFileTreeDefaultIni(s, ToText(path));
	[setting assign:s];
	return ok;
}

+ (NSArray<ECFileTreeRoot *> *)rootsOf:(ECFileTreeSetting *)setting folder:(NSString *)folder
{
	NSMutableArray<ECFileTreeRoot *> *roots = [NSMutableArray array];
	for (const auto& root : core::FileTreeRoots([setting coreSetting], ToText(folder))) {
		[roots addObject:[[ECFileTreeRoot alloc] initWithRoot:root]];
	}
	return roots;
}

+ (ECFileTreeListing *)listItem:(ECFileTreeItem *)item folder:(NSString *)folder
{
	return [[ECFileTreeListing alloc] initWithListing:core::ListFileTree(FromFileTreeItem(item), ToText(folder))];
}

+ (NSString *)saveSetting:(ECFileTreeSetting *)setting typeIndex:(NSInteger)typeIndex truncated:(BOOL *)truncated
{
	bool t = false;
	const auto error = core::SaveFileTreeSetting([setting coreSetting], static_cast<std::int32_t>(typeIndex), t);
	if (truncated) *truncated = t;
	return ToNSString(error);
}

+ (NSArray<ECFileTreeItem *> *)importFromPath:(NSString *)path
{
	const auto items = core::ImportFileTree(ToText(path));
	return items ? ToFileTreeItems(*items) : nil;
}

+ (NSString *)exportItems:(NSArray<ECFileTreeItem *> *)items toPath:(NSString *)path
{
	return ToNSString(core::ExportFileTree(ToText(path), FromFileTreeItems(items)));
}

@end

@implementation ECGrep

+ (NSArray<NSString *> *)historyOf:(ECGrepHistory)kind
{
	NSMutableArray<NSString *> *items = [NSMutableArray array];
	for (const auto& item : core::GrepHistoryItems(static_cast<core::GrepHistory>(kind))) [items addObject:ToNSString(item)];
	return items;
}

+ (void)addHistory:(NSString *)text kind:(ECGrepHistory)kind
{
	core::AddGrepHistory(static_cast<core::GrepHistory>(kind), ToText(text));
}

+ (NSDictionary<NSString *, NSString *> *)dialogDefaults
{
	const auto d = core::GetGrepDialogDefaults();
	return @{ @"file": ToNSString(d.file), @"folder": ToNSString(d.folder),
			  @"excludeFile": ToNSString(d.excludeFile), @"excludeFolder": ToNSString(d.excludeFolder) };
}

+ (NSString *)packFiles:(NSString *)file excludeFile:(NSString *)excludeFile excludeFolder:(NSString *)excludeFolder
{
	return ToNSString(core::PackGrepFiles(ToText(file), ToText(excludeFile), ToText(excludeFolder)));
}

+ (NSArray<NSString *> *)splitFolders:(NSString *)folders base:(NSString *)base
{
	NSMutableArray<NSString *> *items = [NSMutableArray array];
	for (const auto& item : core::SplitGrepFolders(ToText(folders), ToText(base))) [items addObject:ToNSString(item)];
	return items;
}

+ (NSString *)joinFolders:(NSArray<NSString *> *)folders
{
	std::vector<core::Text> items;
	for (NSString *folder in folders) items.push_back(ToText(folder));
	return ToNSString(core::JoinGrepFolders(items));
}

+ (nullable NSString *)foldersUp:(NSString *)folders base:(NSString *)base
{
	const auto up = core::GrepFoldersUp(ToText(folders), ToText(base));
	return up ? ToNSString(*up) : nil;
}

+ (ECGrepDialogCheck *)checkDialogFile:(NSString *)file excludeFile:(NSString *)excludeFile excludeFolder:(NSString *)excludeFolder
	folders:(NSString *)folders base:(NSString *)base fromThisText:(BOOL)fromThisText
{
	return [[ECGrepDialogCheck alloc] initWithCheck:core::CheckGrepDialog(ToText(file), ToText(excludeFile), ToText(excludeFolder),
		ToText(folders), ToText(base), fromThisText == YES)];
}

+ (NSString *)sourceToken:(uint64_t)sourceID { return ToNSString(core::GrepSourceToken(sourceID)); }
+ (NSInteger)outputTypeIndex { return core::GrepOutputTypeIndex(); }

@end

@implementation ECTagJumpListItem
- (instancetype)initWithItem:(const core::TagJumpListItem&)i
{
	if ((self = [super init])) {
		_keyword = ToNSString(i.keyword);
		_file = ToNSString(i.file);
		_line = i.line;
		_kind = ToNSString(i.kind);
		_note = ToNSString(i.note);
		_depth = i.depth;
		_hasBaseDir = i.hasBaseDir ? YES : NO;
	}
	return self;
}
@end

@implementation ECTagJumpList {
	std::unique_ptr<core::TagJumpList> _list;
}
- (instancetype)initWithBaseFilePath:(NSString *)path direct:(BOOL)direct
{
	if ((self = [super init])) {
		_list = std::make_unique<core::TagJumpList>(ToText(path), direct == YES);
	}
	return self;
}
- (NSInteger)findDirect:(NSString *)keyword { return _list->FindDirect(ToText(keyword)); }
- (void)find:(NSString *)keyword ignoreCase:(BOOL)icase partialMatch:(BOOL)partial newFind:(BOOL)newFind
{
	_list->Find(ToText(keyword), icase == YES, partial == YES, newFind == YES);
}
- (void)nextPage:(NSString *)keyword ignoreCase:(BOOL)icase partialMatch:(BOOL)partial { _list->NextPage(ToText(keyword), icase == YES, partial == YES); }
- (void)prevPage:(NSString *)keyword ignoreCase:(BOOL)icase partialMatch:(BOOL)partial { _list->PrevPage(ToText(keyword), icase == YES, partial == YES); }
- (NSArray<ECTagJumpListItem *> *)items
{
	NSMutableArray<ECTagJumpListItem *> *result = [NSMutableArray array];
	for (const auto& i : _list->Items()) [result addObject:[[ECTagJumpListItem alloc] initWithItem:i]];
	return result;
}
- (NSInteger)bestIndex { return _list->BestIndex(); }
- (BOOL)hasNextPage { return _list->HasNextPage() ? YES : NO; }
- (BOOL)hasPrevPage { return _list->HasPrevPage() ? YES : NO; }
- (NSString *)baseDirectory { return ToNSString(_list->BaseDirectory()); }
- (nullable NSString *)fullPathAtIndex:(NSInteger)index line:(NSInteger *)line
{
	if (!FitsInt32(index)) return nil;
	const auto t = _list->FullPathAndLine(static_cast<std::int32_t>(index));
	if (!t) return nil;
	if (line) *line = t->line;
	return ToNSString(t->path);
}
@end

@implementation ECKeywordHelp
- (instancetype)initWithHelp:(const core::Document::KeywordHelp&)h
{
	if ((self = [super init])) {
		_info = ToNSString(h.info);
		_dictionary = h.dictionary;
		_dictionaryPath = ToNSString(h.dictionaryPath);
		_line = h.line;
	}
	return self;
}
@end

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
	return [self openFileAtPath:path encoding:encoding askUsePreviousEncoding:nil];
}

- (ECResult)openFileAtPath:(NSString *)path encoding:(ECEncoding)encoding
	askUsePreviousEncoding:(nullable BOOL (NS_NOESCAPE ^)(ECEncoding current, ECEncoding previous))ask
{
	if (!FitsInt32(encoding)) return ECResultInvalidArgument;
	core::OpenOptions options;
	options.encoding = static_cast<core::Encoding>(encoding);
	if (ask) {
		options.askUsePreviousEncoding = [ask](core::Encoding current, core::Encoding previous) {
			return ask(current, previous) == YES;
		};
	}
	return FromCore(_doc->Open(ToText(path), options));
}

- (nullable ECRestoredView *)restoredView
{
	const auto v = _doc->GetRestoredView();
	return v ? [[ECRestoredView alloc] initWithView:*v] : nil;
}

- (void)addToRecentWithCaret:(ECPosition)caret viewTopLine:(NSInteger)viewTopLine
{
	if (!FitsInt32(viewTopLine)) return;
	_doc->AddToRecent(ToCore(caret), static_cast<std::int32_t>(viewTopLine));
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

- (ECSaveCheck *)checkSaveWithEncoding:(ECEncoding)encoding eol:(ECEol)eol
{
	core::SaveOptions options;
	if (FitsInt32(encoding)) options.encoding = static_cast<core::Encoding>(encoding);
	if (ECEolNone <= eol && eol <= ECEolParagraphSeparator) options.eol = static_cast<core::Eol>(eol);
	return [[ECSaveCheck alloc] initWithCheck:_doc->CheckSave(options)];
}

- (NSString *)path { return ToNSString(_doc->GetFileInfo().path); }
- (ECEncoding)encoding { return _doc->GetFileInfo().encoding; }
- (BOOL)hasBOM { return _doc->GetFileInfo().bom ? YES : NO; }
- (NSInteger)typeIndex { return _doc->GetFileInfo().typeIndex; }
- (NSString *)typeName { return ToNSString(_doc->GetFileInfo().typeName); }
- (BOOL)isModified { return _doc->IsModified() ? YES : NO; }
- (void)closeToUntitled { _doc->CloseToUntitled(); }
- (void)setEncoding:(ECEncoding)encoding bom:(BOOL)bom { _doc->SetEncoding(encoding, bom == YES); }
- (BOOL)isEncodingChanged { return _doc->IsEncodingChanged() ? YES : NO; }

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

- (NSUInteger)changeCount
{
	return static_cast<NSUInteger>(_doc->ChangeCount());
}

- (NSInteger)lengthOfLineAtIndex:(NSInteger)line
{
	if (!FitsInt32(line)) return 0;
	return _doc->LineLength(static_cast<std::int32_t>(line));
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
- (NSInteger)textLength { return static_cast<NSInteger>(_doc->TextLength()); }
- (NSInteger)offsetOfPosition:(ECPosition)position
{
	// 超出 int32 的行：文档末尾；超出的列：行末（核心库收到范围内）
	if (!FitsInt32(position.line)) return position.line < 0 ? 0 : static_cast<NSInteger>(_doc->TextLength());
	const core::Position p{ static_cast<std::int32_t>(position.line),
		static_cast<std::int32_t>(std::clamp<NSInteger>(position.column, 0, INT32_MAX)) };
	return static_cast<NSInteger>(_doc->OffsetOf(p));
}
- (ECPosition)positionAtOffset:(NSInteger)offset { return FromCore(_doc->PositionAtOffset(offset)); }

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

static ECSearchResult *MakeResult(const core::SearchResult& r)
{
	return [[ECSearchResult alloc] initWithStatus:r.status next:core::SearchStatus::NotFound count:0 view:r.view error:r.error];
}

static ECSearchResult *MakeResult(const core::ReplaceResult& r)
{
	return [[ECSearchResult alloc] initWithStatus:r.status next:r.next count:r.count view:r.view error:r.error];
}

static bool FitsInt32(const ECSearchView& v)
{
	return FitsInt32(v.caret.line) && FitsInt32(v.caret.column) && (!v.hasSelection || FitsInt32(v.selection));
}

static ECSearchResult *InvalidViewResult()
{
	return [[ECSearchResult alloc] initWithStatus:core::SearchStatus::NotFound next:core::SearchStatus::NotFound count:0
											 view:core::SearchView{} error:core::Text()];
}

- (ECSearchResult *)searchNext:(NSString *)key options:(ECSearchOptions)options view:(ECSearchView)view searchAll:(BOOL)searchAll
{
	if (!FitsInt32(view)) return InvalidViewResult();
	return MakeResult(_doc->SearchNext(ToText(key), ToCore(options), ToCore(view), searchAll == YES));
}

- (ECSearchResult *)searchPrev:(NSString *)key options:(ECSearchOptions)options view:(ECSearchView)view searchAll:(BOOL)searchAll
{
	if (!FitsInt32(view)) return InvalidViewResult();
	return MakeResult(_doc->SearchPrev(ToText(key), ToCore(options), ToCore(view), searchAll == YES));
}

- (ECSearchResult *)replaceNext:(NSString *)key with:(NSString *)replacement options:(ECReplaceOptions)options view:(ECSearchView)view
{
	if (!FitsInt32(view)) return InvalidViewResult();
	return MakeResult(_doc->ReplaceNext(ToText(key), ToText(replacement), ToCore(options), ToCore(view)));
}

- (ECSearchResult *)replaceAll:(NSString *)key with:(NSString *)replacement options:(ECReplaceOptions)options view:(ECSearchView)view
{
	if (!FitsInt32(view)) return InvalidViewResult();
	return MakeResult(_doc->ReplaceAll(ToText(key), ToText(replacement), ToCore(options), ToCore(view)));
}

- (BOOL)jumpPosition:(ECJumpOptions)options position:(ECPosition *)outPosition
{
	core::JumpOptions o;
	o.lineNumber = static_cast<std::int32_t>(std::clamp<NSInteger>(options.lineNumber, INT32_MIN, INT32_MAX));
	o.lineNumIsCRLF = options.lineNumIsCRLF;
	o.plsql = options.plsql;
	o.plsqlBlockFirstLine = static_cast<std::int32_t>(std::clamp<NSInteger>(options.plsqlBlockFirstLine, INT32_MIN, INT32_MAX));
	const auto p = _doc->JumpPosition(o);
	if (!p) return NO;
	if (outPosition) *outPosition = FromCore(*p);
	return YES;
}

- (BOOL)wordRangeAt:(ECPosition)position range:(ECRange *)outRange
{
	if (!FitsInt32(position.line) || !FitsInt32(position.column)) return NO;
	const auto r = _doc->WordRangeAt(ToCore(position));
	if (!r) return NO;
	if (outRange) *outRange = FromCore(*r);
	return YES;
}

- (BOOL)wordMoveTargetFrom:(ECPosition)position left:(BOOL)left position:(ECPosition *)outPosition
{
	if (!FitsInt32(position.line) || !FitsInt32(position.column)) return NO;
	const auto p = _doc->WordMoveTarget(ToCore(position), left == YES);
	if (!p) return NO;
	if (outPosition) *outPosition = FromCore(*p);
	return YES;
}

- (NSInteger)paragraphTargetFromLine:(NSInteger)line next:(BOOL)next
{
	if (!FitsInt32(line)) return -1;
	const auto y = _doc->ParagraphTarget(static_cast<std::int32_t>(line), next == YES);
	return y ? *y : -1;
}

- (BOOL)modifiedLineTargetFrom:(ECPosition)position next:(BOOL)next position:(ECPosition *)outPosition wrapped:(BOOL *)outWrapped
{
	if (!FitsInt32(position.line) || !FitsInt32(position.column)) return NO;
	const auto j = _doc->ModifiedLineTarget(ToCore(position), next == YES);
	if (!j) return NO;
	if (outPosition) *outPosition = FromCore(j->position);
	if (outWrapped) *outWrapped = j->wrapped ? YES : NO;
	return YES;
}

- (NSInteger)indentEndInLine:(NSInteger)line from:(NSInteger)from to:(NSInteger)to
{
	if (!FitsInt32(line) || !FitsInt32(from) || !FitsInt32(to)) return from;
	return _doc->IndentEnd(static_cast<std::int32_t>(line), static_cast<std::int32_t>(from), static_cast<std::int32_t>(to));
}

// ----- 模式（第 34 步） -----

- (BOOL)insertMode { return _doc->IsInsertMode() ? YES : NO; }
- (void)setInsertMode:(BOOL)insertMode { _doc->SetInsertMode(insertMode == YES); }

- (ECResult)overwriteText:(NSString *)text at:(ECPosition)position newCaret:(ECPosition *)newCaret
{
	if (!FitsInt32(position.line) || !FitsInt32(position.column)) return ECResultInvalidArgument;
	core::Position caret{};
	const core::Result r = _doc->OverwriteText(ToCore(position), ToText(text), &caret);
	if (newCaret) *newCaret = FromCore(caret);
	return FromCore(r);
}

- (NSInteger)wrapWindowWidthColumnsForWidth:(NSInteger)width
{
	const auto columns = _doc->WrapWindowWidthColumns(static_cast<std::int32_t>(std::clamp<NSInteger>(width, 0, INT32_MAX)));
	return columns ? *columns : -1;
}

- (NSArray<ECSearchMark *> *)searchMarksInLine:(NSInteger)line key:(NSString *)key options:(ECSearchOptions)options
{
	if (!FitsInt32(line)) return @[];
	const auto marks = _doc->SearchMarks(static_cast<std::int32_t>(line), ToText(key), ToCore(options));
	NSMutableArray<ECSearchMark *> *r = [NSMutableArray arrayWithCapacity:marks.size()];
	for (const auto& m : marks) [r addObject:[[ECSearchMark alloc] initWithMark:m]];
	return r;
}

- (NSArray<ECSyntaxColorRun *> *)syntaxColorsInLine:(NSInteger)line
{
	if (!FitsInt32(line)) return @[];
	const auto runs = _doc->SyntaxColors(static_cast<std::int32_t>(line));
	NSMutableArray<ECSyntaxColorRun *> *r = [NSMutableArray arrayWithCapacity:runs.size()];
	for (const auto& run : runs) [r addObject:[[ECSyntaxColorRun alloc] initWithRun:run]];
	return r;
}

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

- (BOOL)isCommandChecked:(ECCommand)command
{
	if (!FitsInt32(command)) return NO;
	return _doc->IsCommandChecked(static_cast<core::FunctionCode>(command)) ? YES : NO;
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
- (BOOL)applyTypeSettingChange:(NSInteger)typeIndex { return _doc->ApplyTypeSettingChange(static_cast<std::int32_t>(typeIndex)) ? YES : NO; }
- (BOOL)applyTypeListChange { return _doc->ApplyTypeListChange() ? YES : NO; }
- (BOOL)changeTypeTemporarily:(NSInteger)typeIndex { return _doc->ChangeTypeTemporarily(static_cast<std::int32_t>(typeIndex)) ? YES : NO; }

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

// ----- 编辑命令（第 29 步） -----


- (ECEditSettings)editSettings
{
	const core::EditSettings e = _doc->GetEditSettings();
	return ECEditSettings{ e.copyWithoutSelection, e.lineModePaste, e.clearSelectionAfterCopy, e.autoColumnPaste,
						   e.convertEolOnPaste, e.addEolAtWrapOnCopy, e.insertSpacesForTab, e.autoIndent, e.boxSelectLock };
}

- (NSString *)copyTextInRange:(ECRange)range { return ToNSString(_doc->GetCopyText(ToCore(range))); }
- (NSString *)boxText:(ECBoxRange)box { return ToNSString(_doc->GetBoxText(ToCore(box))); }
- (NSString *)copyTextOfLayoutLine:(NSInteger)line { return ToNSString(_doc->GetLayoutLineCopyText(ClampInt32(line))); }

- (ECLayoutPosition)insertText:(NSString *)text atLayout:(ECLayoutPosition)position
{
	const core::LayoutPosition p = _doc->InsertAtLayout(ToCore(position), ToText(text));
	return ECLayoutPosition{ p.line, p.x };
}

- (ECPosition)deleteBox:(ECBoxRange)box { return FromCore(_doc->DeleteBox(ToCore(box))); }

- (void)pasteBox:(NSString *)text at:(ECLayoutPosition)position { _doc->PasteBox(ToCore(position), ToText(text)); }

- (ECBoxRange)indentBox:(ECBoxRange)box text:(NSString *)text kind:(ECIndentKind)kind caret:(nullable ECPosition *)caret
{
	// 宽度 0 的 TAB、SPACE 缩进不移动光标，caret 保持原样
	core::Position c = caret ? ToCore(*caret) : core::Position{};
	const core::BoxRange b = _doc->IndentBox(ToCore(box), ToText(text), static_cast<core::IndentKind>(kind), caret ? &c : nullptr);
	if (caret) *caret = FromCore(c);
	return ECBoxRange{ b.top, b.bottom, b.left, b.right };
}

- (NSInteger)indentLinesFrom:(NSInteger)top to:(NSInteger)bottom text:(NSString *)text
{
	return _doc->IndentLines(ClampInt32(top), ClampInt32(bottom), ToText(text));
}

- (NSInteger)unindentLinesFrom:(NSInteger)top to:(NSInteger)bottom character:(unichar)character
{
	return _doc->UnindentLines(ClampInt32(top), ClampInt32(bottom), static_cast<char16_t>(character));
}

- (NSString *)tabTextAt:(NSInteger)x { return ToNSString(_doc->TabText(ClampInt32(x))); }
- (NSString *)autoIndentTextAt:(ECPosition)caret { return ToNSString(_doc->AutoIndentText(ToCore(caret))); }
- (NSString *)convertEolToNewLine:(NSString *)text { return ToNSString(_doc->ConvertEolToNewLine(ToText(text))); }
- (ECPosition)deleteLayoutLine:(NSInteger)line x:(NSInteger)x { return FromCore(_doc->DeleteLayoutLine(ClampInt32(line), ClampInt32(x))); }

// ----- アウトライン解析（第 42 步） -----

- (ECOutlineResult *)analyzeOutline:(ECOutlineType)type
{
	return [[ECOutlineResult alloc] initWithResult:_doc->AnalyzeOutline(static_cast<core::OutlineType>(ClampInt32(type)))];
}

- (ECOutlineType)resolveOutlineType:(ECOutlineType)type
{
	return static_cast<ECOutlineType>(_doc->ResolveOutlineType(static_cast<core::OutlineType>(ClampInt32(type))));
}

- (NSInteger)findFuncListMarkFromLine:(NSInteger)line forward:(BOOL)forward searchAll:(BOOL)searchAll wrapped:(nullable BOOL *)wrapped
{
	bool w = false;
	const std::int32_t found = _doc->FindFuncListMark(ClampInt32(line), forward == YES, searchAll == YES, &w);
	if (wrapped) *wrapped = w ? YES : NO;
	return found;
}

- (BOOL)hasFuncListMark:(NSInteger)line { return _doc->HasFuncListMark(ClampInt32(line)) ? YES : NO; }

- (ECPosition)appendWithoutUndo:(NSString *)text
{
	const auto p = _doc->AppendWithoutUndo(ToText(text));
	return ECPosition{ p.line, p.column };
}

- (void)setUnmodified { _doc->SetUnmodified(); }

// ----- 編集支援（第 44 步） -----

- (BOOL)findBracketPairAt:(ECPosition)caret checkPrev:(BOOL)checkPrev areaTop:(NSInteger)areaTop areaBottom:(NSInteger)areaBottom
	pair:(ECPosition *)outPair bracket:(ECPosition *)outBracket
{
	if (!FitsInt32(caret.line) || !FitsInt32(caret.column)) return NO;
	std::optional<core::Document::BracketSearchArea> area;
	if (areaTop <= areaBottom) area = core::Document::BracketSearchArea{ ClampInt32(areaTop), ClampInt32(areaBottom) };
	const auto r = _doc->FindBracketPair(ToCore(caret), checkPrev == YES, area);
	if (!r) return NO;
	if (outPair) *outPair = FromCore(r->pair);
	if (outBracket) *outBracket = FromCore(r->bracket);
	return YES;
}

+ (BOOL)isBracketCharacter:(unichar)ch { return core::IsBracketChar(static_cast<char16_t>(ch)) ? YES : NO; }

- (BOOL)isBookmarked:(NSInteger)line { return FitsInt32(line) && _doc->IsBookmarked(static_cast<std::int32_t>(line)) ? YES : NO; }

- (void)setBookmark:(BOOL)on line:(NSInteger)line
{
	if (FitsInt32(line)) _doc->SetBookmark(static_cast<std::int32_t>(line), on == YES);
}

- (void)toggleBookmarksFrom:(NSInteger)fromLine to:(NSInteger)toLine
{
	_doc->ToggleBookmarks(ClampInt32(fromLine), ClampInt32(toLine));
}

- (NSInteger)findBookmarkFromLine:(NSInteger)line forward:(BOOL)forward searchAll:(BOOL)searchAll wrapped:(nullable BOOL *)wrapped
{
	bool w = false;
	const std::int32_t found = _doc->FindBookmark(ClampInt32(line), forward == YES, searchAll == YES, &w);
	if (wrapped) *wrapped = w ? YES : NO;
	return found;
}

- (void)resetBookmarks { _doc->ResetBookmarks(); }

- (BOOL)markPattern:(NSString *)key options:(ECSearchOptions)options
{
	return _doc->MarkPattern(ToText(key), ToCore(options)) ? YES : NO;
}

- (NSString *)bookmarkList { return ToNSString(_doc->GetBookmarkList()); }
- (void)setBookmarkList:(NSString *)bookmarkList { _doc->SetBookmarkList(ToText(bookmarkList)); }

- (BOOL)isearchFind:(NSString *)key from:(ECPosition)from forward:(BOOL)forward options:(ECSearchOptions)options
	migemo:(BOOL)migemo range:(ECRange *)outRange
{
	if (!FitsInt32(from.line) || !FitsInt32(from.column)) return NO;
	const auto r = _doc->ISearchFind(ToText(key), ToCore(from),
									 forward ? core::SearchDirection::Forward : core::SearchDirection::Backward,
									 ToCore(options), migemo == YES);
	if (!r) return NO;
	if (outRange) *outRange = FromCore(*r);
	return YES;
}

- (ECPosition)isearchWrapBackwardStart { return FromCore(_doc->ISearchWrapBackwardStart()); }

- (ECDiffResult)applyDiff:(NSString *)otherText flags:(NSInteger)flags
{
	core::DiffOptions o;
	o.ignoreCase = (flags & 0x01) != 0;
	o.ignoreAllSpace = (flags & 0x02) != 0;
	o.ignoreSpaceChange = (flags & 0x04) != 0;
	o.ignoreBlankLines = (flags & 0x08) != 0;
	o.expandTabs = (flags & 0x10) != 0;
	return static_cast<ECDiffResult>(_doc->ApplyDiff(ToText(otherText), o, (flags & 0x20) != 0));
}

- (NSInteger)diffMark:(NSInteger)line { return FitsInt32(line) ? static_cast<NSInteger>(_doc->GetDiffMark(static_cast<std::int32_t>(line))) : 0; }
+ (nullable NSString *)textOfFileAtPath:(NSString *)path
{
	auto doc = core::Document::Create();
	if (!doc) return nil;
	core::OpenOptions options;
	options.useHistory = false;
	const auto r = doc->Open(ToText(path), options);
	if (r != core::Result::Ok && r != core::Result::LostSome) return nil;
	return ToNSString(doc->GetText());
}

- (BOOL)compareWith:(ECDocument *)other from:(ECPosition)from otherFrom:(ECPosition)otherFrom
	mine:(ECPosition *)mine theirs:(ECPosition *)theirs
{
	const auto r = _doc->CompareWith(*other->_doc, ToCore(from), ToCore(otherFrom));
	if (mine) *mine = FromCore(r.mine);
	if (theirs) *theirs = FromCore(r.theirs);
	return r.different ? YES : NO;
}

- (void)resetDiffMarks { _doc->ResetDiffMarks(); }

- (NSString *)leftWordAt:(ECPosition)caret
{
	if (!FitsInt32(caret.line) || !FitsInt32(caret.column)) return @"";
	return ToNSString(_doc->LeftWord(ToCore(caret)));
}

- (NSArray<NSString *> *)hokanCandidatesForKey:(NSString *)key caret:(ECPosition)caret
{
	NSMutableArray<NSString *> *result = [NSMutableArray array];
	if (!FitsInt32(caret.line) || !FitsInt32(caret.column)) return result;
	for (const auto& w : _doc->HokanCandidates(ToText(key), ToCore(caret))) [result addObject:ToNSString(w)];
	return result;
}

- (NSArray<NSString *> *)supportFilePaths
{
	NSMutableArray<NSString *> *result = [NSMutableArray array];
	for (const auto& p : _doc->SupportFilePaths()) [result addObject:ToNSString(p)];
	return result;
}

- (BOOL)usesKeywordHelp { return _doc->UsesKeywordHelp() ? YES : NO; }

- (nullable ECKeywordHelp *)lookupKeywordHelp:(NSString *)key
{
	const auto h = _doc->LookupKeywordHelp(ToText(key));
	return h.hit ? [[ECKeywordHelp alloc] initWithHelp:h] : nil;
}
- (BOOL)isDiffUsed { return _doc->IsDiffUsed() ? YES : NO; }

- (NSInteger)findDiffMarkFromLine:(NSInteger)line forward:(BOOL)forward searchAll:(BOOL)searchAll wrapped:(nullable BOOL *)wrapped
{
	bool w = false;
	const std::int32_t found = _doc->FindDiffMark(ClampInt32(line), forward == YES, searchAll == YES, &w);
	if (wrapped) *wrapped = w ? YES : NO;
	return found;
}

- (nullable ECTagJumpTarget *)tagJumpAtLine:(NSInteger)line
{
	const auto target = core::FindTagJump(*_doc, ClampInt32(line));
	return target ? [[ECTagJumpTarget alloc] initWithTarget:*target] : nil;
}

// ----- マクロ（第 45 步） -----

- (NSString *)expandParameter:(NSString *)source view:(ECExpandParameterView *)view
{
	return ToNSString(_doc->ExpandParameter(ToText(source), [view coreView]));
}
- (NSString *)cookie:(NSString *)scope name:(NSString *)name { return ToNSString(_doc->GetCookie(ToText(scope), ToText(name))); }
- (NSString *)cookie:(NSString *)scope name:(NSString *)name defaultValue:(NSString *)defaultValue
{
	return ToNSString(_doc->GetCookieDefault(ToText(scope), ToText(name), ToText(defaultValue)));
}
- (NSInteger)setCookie:(NSString *)scope name:(NSString *)name value:(NSString *)value
{
	return _doc->SetCookie(ToText(scope), ToText(name), ToText(value));
}
- (NSInteger)deleteCookie:(NSString *)scope name:(NSString *)name { return _doc->DeleteCookie(ToText(scope), ToText(name)); }
- (NSString *)cookieNames:(NSString *)scope { return ToNSString(_doc->GetCookieNames(ToText(scope))); }

@end

// ----- マクロ（第 45 步） -----

static_assert(ECMacroValueTypeNone == static_cast<NSInteger>(core::MacroValueType::None));
static_assert(ECMacroValueTypeInt == static_cast<NSInteger>(core::MacroValueType::Int));
static_assert(ECMacroValueTypeString == static_cast<NSInteger>(core::MacroValueType::String));
static_assert(ECMacroLoadResultSuccess == static_cast<NSInteger>(core::MacroLoadResult::Success));
static_assert(ECMacroLoadResultFailure == static_cast<NSInteger>(core::MacroLoadResult::Failure));
static_assert(ECMacroLoadResultEncodingError == static_cast<NSInteger>(core::MacroLoadResult::EncodingError));
static_assert(ECMacroKindKey == static_cast<NSInteger>(core::MacroKind::Key));
static_assert(ECMacroKindJScript == static_cast<NSInteger>(core::MacroKind::JScript));
static_assert(ECMacroKindUnsupported == static_cast<NSInteger>(core::MacroKind::Unsupported));
static_assert(ECMacroKindUnknown == static_cast<NSInteger>(core::MacroKind::Unknown));

@implementation ECMacroFunctionInfo
- (instancetype)initWithInfo:(const core::MacroFunctionInfo&)f
{
	if ((self = [super init])) {
		_code = f.code;
		_name = ToNSString(f.name);
		NSMutableArray<NSNumber *> *args = [NSMutableArray array];
		for (auto a : f.args) [args addObject:@(static_cast<NSInteger>(a))];
		_argTypes = args;
		_resultType = static_cast<ECMacroValueType>(f.result);
		_isFunction = f.isFunction ? YES : NO;
	}
	return self;
}
@end

@implementation ECMacroArg
- (instancetype)initWithArg:(const core::MacroArg&)a
{
	if ((self = [super init])) {
		_isString = a.isString ? YES : NO;
		_text = ToNSString(a.text);
	}
	return self;
}
+ (instancetype)string:(NSString *)text { return [[ECMacroArg alloc] initWithArg:core::MacroArg::String(ToText(text))]; }
+ (instancetype)int:(NSInteger)value { return [[ECMacroArg alloc] initWithArg:core::MacroArg::Int(ClampInt32(value))]; }
- (NSInteger)intValue { return [self coreArg].IntValue(); }
- (core::MacroArg)coreArg { return core::MacroArg{ _isString == YES, ToText(_text) }; }
@end

@implementation ECMacroCall
- (instancetype)initWithCode:(NSInteger)code args:(NSArray<ECMacroArg *> *)args
{
	if ((self = [super init])) {
		_code = code;
		_args = [args copy];
	}
	return self;
}
- (instancetype)initWithCall:(const core::MacroCall&)c
{
	NSMutableArray<ECMacroArg *> *args = [NSMutableArray array];
	for (const auto& a : c.args) [args addObject:[[ECMacroArg alloc] initWithArg:a]];
	return [self initWithCode:c.code args:args];
}
- (core::MacroCall)coreCall
{
	core::MacroCall c;
	c.code = ClampInt32(_code);
	for (ECMacroArg *a in _args) c.args.push_back([a coreArg]);
	return c;
}
@end

@implementation ECKeyMacroParseResult
- (instancetype)initWithResult:(const core::KeyMacroParseResult&)r
{
	if ((self = [super init])) {
		_result = static_cast<ECMacroLoadResult>(r.result);
		NSMutableArray<ECMacroCall *> *calls = [NSMutableArray array];
		for (const auto& c : r.calls) [calls addObject:[[ECMacroCall alloc] initWithCall:c]];
		_calls = calls;
		_errorTitle = ToNSString(r.errorTitle);
		_errorMessage = ToNSString(r.errorMessage);
	}
	return self;
}
@end

@implementation ECExpandParameterView
- (instancetype)init
{
	if ((self = [super init])) {
		_selectedText = @""; _grepKey = @""; _macroPath = @""; _date = @""; _time = @"";
		_fileDate = @""; _fileTime = @""; _appName = @""; _appPath = @""; _version = @"";
	}
	return self;
}
- (core::ExpandParameterView)coreView
{
	core::ExpandParameterView v;
	v.selectedText = ToText(_selectedText);
	v.caret = ToCore(_caret);
	v.untitledNumber = ClampInt32(_untitledNumber);
	v.grepMode = _grepMode == YES;
	v.outputMode = _outputMode == YES;
	v.grepKey = ToText(_grepKey);
	v.macroPath = ToText(_macroPath);
	v.recordingKeyMacro = _recordingKeyMacro == YES;
	v.viewMode = _viewMode == YES;
	v.readOnly = _readOnly == YES;
	v.minimized = _minimized == YES;
	v.date = ToText(_date);
	v.time = ToText(_time);
	v.fileDate = ToText(_fileDate);
	v.fileTime = ToText(_fileTime);
	v.appName = ToText(_appName);
	v.appPath = ToText(_appPath);
	v.version = ToText(_version);
	return v;
}
@end

namespace {
NSArray<ECMacroFunctionInfo *> *MacroFunctionList()
{
	static NSArray<ECMacroFunctionInfo *> *list = [] {
		NSMutableArray<ECMacroFunctionInfo *> *a = [NSMutableArray array];
		for (const auto& f : core::MacroFunctions()) [a addObject:[[ECMacroFunctionInfo alloc] initWithInfo:f]];
		return [a copy];
	}();
	return list;
}
//! 表の中の同じ項目（ECMacroFunctionInfo は表の順に一つずつ）
ECMacroFunctionInfo *_Nullable MacroInfoFor(const core::MacroFunctionInfo* f)
{
	if (!f) return nil;
	const auto& table = core::MacroFunctions();
	const auto index = static_cast<NSUInteger>(f - table.data());
	return index < MacroFunctionList().count ? MacroFunctionList()[index] : nil;
}
std::vector<core::MacroCall> ToCoreCalls(NSArray<ECMacroCall *> *calls)
{
	std::vector<core::MacroCall> v;
	for (ECMacroCall *c in calls) v.push_back([c coreCall]);
	return v;
}
} // namespace

@implementation ECMacro
+ (NSArray<ECMacroFunctionInfo *> *)functions { return MacroFunctionList(); }
+ (nullable ECMacroFunctionInfo *)findFunction:(NSString *)name { return MacroInfoFor(core::FindMacroFunction(ToText(name))); }
+ (nullable ECMacroFunctionInfo *)findFunctionIgnoreCase:(NSString *)name { return MacroInfoFor(core::FindMacroFunctionIgnoreCase(ToText(name))); }
+ (nullable ECMacroFunctionInfo *)functionByCode:(NSInteger)code
{
	return FitsInt32(code) ? MacroInfoFor(core::MacroFunctionByCode(static_cast<std::int32_t>(code))) : nil;
}
+ (NSString *)displayName:(NSInteger)code { return FitsInt32(code) ? ToNSString(core::MacroFunctionDisplayName(static_cast<std::int32_t>(code))) : @""; }
+ (BOOL)canRecord:(NSInteger)code { return FitsInt32(code) && core::CanRecordInKeyMacro(static_cast<std::int32_t>(code)) ? YES : NO; }
+ (ECKeyMacroParseResult *)parseKeyMacro:(NSString *)source { return [[ECKeyMacroParseResult alloc] initWithResult:core::ParseKeyMacro(ToText(source))]; }
+ (NSString *)formatKeyMacro:(NSArray<ECMacroCall *> *)calls { return ToNSString(core::FormatKeyMacro(ToCoreCalls(calls))); }
+ (ECKeyMacroParseResult *)loadKeyMacroFile:(NSString *)path { return [[ECKeyMacroParseResult alloc] initWithResult:core::LoadKeyMacroFile(ToText(path))]; }
+ (BOOL)saveKeyMacroFile:(NSString *)path calls:(NSArray<ECMacroCall *> *)calls { return core::SaveKeyMacroFile(ToText(path), ToCoreCalls(calls)) ? YES : NO; }
+ (nullable NSString *)loadSourceFile:(NSString *)path result:(ECMacroLoadResult *)result
{
	const auto r = core::LoadMacroSourceFile(ToText(path));
	if (result) *result = static_cast<ECMacroLoadResult>(r.result);
	return r.result == core::MacroLoadResult::Success ? ToNSString(r.source) : nil;
}
+ (ECMacroKind)kindOfPath:(NSString *)path { return static_cast<ECMacroKind>(core::MacroKindOfPath(ToText(path))); }
+ (NSString *)prepareJScript:(NSString *)source { return ToNSString(core::PrepareJScriptMacro(ToText(source))); }
+ (NSInteger)compareVersion:(NSString *)a with:(NSString *)b { return core::CompareVersionString(ToText(a), ToText(b)); }
@end
