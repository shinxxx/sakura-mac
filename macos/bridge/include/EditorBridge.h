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

//! 颜色的种类（第 28 步。数值与原版的 EColorIndexType 相同）
typedef NS_ENUM(NSInteger, ECColorIndex) {
	ECColorIndexText NS_SWIFT_NAME(text) = 0,									//!< テキスト
	ECColorIndexRuler NS_SWIFT_NAME(ruler) = 1,									//!< ルーラー
	ECColorIndexCaret NS_SWIFT_NAME(caret) = 2,									//!< キャレット
	ECColorIndexCaretIme NS_SWIFT_NAME(caretIme) = 3,							//!< IMEキャレット
	ECColorIndexCaretLineBackground NS_SWIFT_NAME(caretLineBackground) = 4,		//!< カーソル行背景色
	ECColorIndexCaretLineUnderline NS_SWIFT_NAME(caretLineUnderline) = 5,		//!< カーソル行アンダーライン
	ECColorIndexCursorColumnLine NS_SWIFT_NAME(cursorColumnLine) = 6,			//!< カーソル位置縦線
	ECColorIndexNoteLine NS_SWIFT_NAME(noteLine) = 7,							//!< ノート線
	ECColorIndexLineNumber NS_SWIFT_NAME(lineNumber) = 8,						//!< 行番号
	ECColorIndexLineNumberModified NS_SWIFT_NAME(lineNumberModified) = 9,		//!< 行番号（変更行）
	ECColorIndexEvenLineBackground NS_SWIFT_NAME(evenLineBackground) = 10,		//!< 奇数行の背景色
	ECColorIndexTab NS_SWIFT_NAME(tab) = 11,									//!< TAB記号
	ECColorIndexSpace NS_SWIFT_NAME(space) = 12,								//!< 半角空白
	ECColorIndexFullWidthSpace NS_SWIFT_NAME(fullWidthSpace) = 13,				//!< 日本語空白
	ECColorIndexControlCode NS_SWIFT_NAME(controlCode) = 14,					//!< コントロールコード
	ECColorIndexEol NS_SWIFT_NAME(eol) = 15,									//!< 改行記号
	ECColorIndexWrapMark NS_SWIFT_NAME(wrapMark) = 16,							//!< 折り返し記号
	ECColorIndexVerticalLine NS_SWIFT_NAME(verticalLine) = 17,					//!< 指定桁縦線
	ECColorIndexEof NS_SWIFT_NAME(eof) = 18,									//!< EOF記号
	ECColorIndexDigit NS_SWIFT_NAME(digit) = 19,								//!< 半角数値
	ECColorIndexBracketPair NS_SWIFT_NAME(bracketPair) = 20,					//!< 対括弧
	ECColorIndexSelect NS_SWIFT_NAME(select) = 21,								//!< 選択範囲
	ECColorIndexSearch NS_SWIFT_NAME(search) = 22,								//!< 検索文字列（第 32 步）
	ECColorIndexSearch2 NS_SWIFT_NAME(search2) = 23,							//!< 検索文字列2
	ECColorIndexSearch3 NS_SWIFT_NAME(search3) = 24,							//!< 検索文字列3
	ECColorIndexSearch4 NS_SWIFT_NAME(search4) = 25,							//!< 検索文字列4
	ECColorIndexSearch5 NS_SWIFT_NAME(search5) = 26,							//!< 検索文字列5
	ECColorIndexComment NS_SWIFT_NAME(comment) = 27,							//!< コメント（第 33 步）
	ECColorIndexSingleQuote NS_SWIFT_NAME(singleQuote) = 28,					//!< シングルクォーテーション文字列
	ECColorIndexDoubleQuote NS_SWIFT_NAME(doubleQuote) = 29,					//!< ダブルクォーテーション文字列
	ECColorIndexHeredoc NS_SWIFT_NAME(heredoc) = 30,							//!< ヒアドキュメント
	ECColorIndexUrl NS_SWIFT_NAME(url) = 31,									//!< URL
	ECColorIndexKeyword1 NS_SWIFT_NAME(keyword1) = 32,						//!< 強調キーワード1
	ECColorIndexKeyword2 NS_SWIFT_NAME(keyword2) = 33,						//!< 強調キーワード2
	ECColorIndexKeyword3 NS_SWIFT_NAME(keyword3) = 34,						//!< 強調キーワード3
	ECColorIndexKeyword4 NS_SWIFT_NAME(keyword4) = 35,						//!< 強調キーワード4
	ECColorIndexKeyword5 NS_SWIFT_NAME(keyword5) = 36,						//!< 強調キーワード5
	ECColorIndexKeyword6 NS_SWIFT_NAME(keyword6) = 37,						//!< 強調キーワード6
	ECColorIndexKeyword7 NS_SWIFT_NAME(keyword7) = 38,						//!< 強調キーワード7
	ECColorIndexKeyword8 NS_SWIFT_NAME(keyword8) = 39,						//!< 強調キーワード8
	ECColorIndexKeyword9 NS_SWIFT_NAME(keyword9) = 40,						//!< 強調キーワード9
	ECColorIndexKeyword10 NS_SWIFT_NAME(keyword10) = 41,						//!< 強調キーワード10
	ECColorIndexRegex1 NS_SWIFT_NAME(regex1) = 42,							//!< 正規表現キーワード1
	ECColorIndexRegex2 NS_SWIFT_NAME(regex2) = 43,							//!< 正規表現キーワード2
	ECColorIndexRegex3 NS_SWIFT_NAME(regex3) = 44,							//!< 正規表現キーワード3
	ECColorIndexRegex4 NS_SWIFT_NAME(regex4) = 45,							//!< 正規表現キーワード4
	ECColorIndexRegex5 NS_SWIFT_NAME(regex5) = 46,							//!< 正規表現キーワード5
	ECColorIndexRegex6 NS_SWIFT_NAME(regex6) = 47,							//!< 正規表現キーワード6
	ECColorIndexRegex7 NS_SWIFT_NAME(regex7) = 48,							//!< 正規表現キーワード7
	ECColorIndexRegex8 NS_SWIFT_NAME(regex8) = 49,							//!< 正規表現キーワード8
	ECColorIndexRegex9 NS_SWIFT_NAME(regex9) = 50,							//!< 正規表現キーワード9
	ECColorIndexRegex10 NS_SWIFT_NAME(regex10) = 51,							//!< 正規表現キーワード10
	ECColorIndexDiffAppend NS_SWIFT_NAME(diffAppend) = 52,					//!< DIFF差分表示(追加)
	ECColorIndexDiffChange NS_SWIFT_NAME(diffChange) = 53,					//!< DIFF差分表示(変更)
	ECColorIndexDiffDelete NS_SWIFT_NAME(diffDelete) = 54,					//!< DIFF差分表示(削除)
	ECColorIndexMark NS_SWIFT_NAME(mark) = 55,								//!< ブックマーク
	ECColorIndexPageView NS_SWIFT_NAME(pageView) = 56,						//!< ミニマップの表示範囲
} NS_SWIFT_NAME(EditorColorIndex);

//! 一种颜色的设置（原版的 ColorInfo）。颜色是 0xRRGGBB
typedef struct ECColorSetting {
	bool display;		//!< 表示（C 的 bool，Swift 里是 Bool）
	bool bold;			//!< 太字
	bool underline;		//!< 下線
	uint32_t text;		//!< 文字色
	uint32_t back;		//!< 背景色
} NS_SWIFT_NAME(EditorColorSetting) ECColorSetting;

//! 矩形范围（第 29 步）：排版行 top～bottom（包括 bottom），横向 left～right（点）
typedef struct ECBoxRange {
	NSInteger top;
	NSInteger bottom;
	NSInteger left;
	NSInteger right;
} NS_SWIFT_NAME(EditorBoxRange) ECBoxRange;

//! 缩进的种类（第 29 步。原版的 EIndentType）
typedef NS_ENUM(NSInteger, ECIndentKind) {
	ECIndentKindNone NS_SWIFT_NAME(none) = 0,		//!< 普通的输入
	ECIndentKindTab NS_SWIFT_NAME(tab) = 1,			//!< TABインデント
	ECIndentKindSpace NS_SWIFT_NAME(space) = 2,		//!< SPACEインデント
} NS_SWIFT_NAME(EditorIndentKind);

//! 编辑用的设置（第 29 步。共通设置「編集」和类型别设置的一部分）
typedef struct ECEditSettings {
	bool copyWithoutSelection;		//!< 選択なしでコピーを可能にする
	bool lineModePaste;				//!< ラインモード貼り付けを可能にする
	bool clearSelectionAfterCopy;	//!< コピーしたら選択解除
	bool autoColumnPaste;			//!< 矩形コピーのテキストは常に矩形貼り付け
	bool convertEolOnPaste;			//!< 改行コードを変換して貼り付ける
	bool addEolAtWrapOnCopy;		//!< 折り返し行に改行を付けてコピー
	bool insertSpacesForTab;		//!< スペースの挿入（TAB 键输入空白）
	bool autoIndent;				//!< オートインデント
	bool boxSelectLock;				//!< 矩形選択移動で選択をロックする（第 34 步）
} NS_SWIFT_NAME(EditorEditSettings) ECEditSettings;

// ----- 查找、替换、跳转（第 32 步） -----

//! 查找的结果（sakura::core::SearchStatus）
typedef NS_ENUM(NSInteger, ECSearchStatus) {
	ECSearchStatusFound NS_SWIFT_NAME(found) = 0,						//!< 找到了
	ECSearchStatusWrapped NS_SWIFT_NAME(wrapped) = 1,					//!< 找到了，是从先頭（末尾）再查找的
	ECSearchStatusNotFound NS_SWIFT_NAME(notFound) = 2,					//!< 没有找到
	ECSearchStatusInvalidPattern NS_SWIFT_NAME(invalidPattern) = 3,		//!< 正则表达式有错误
} NS_SWIFT_NAME(EditorSearchStatus);

//! 置換対象（数值与原版的 m_nReplaceTarget 相同）
typedef NS_ENUM(NSInteger, ECReplaceTarget) {
	ECReplaceTargetSelection NS_SWIFT_NAME(selection) = 0,			//!< 選択文字
	ECReplaceTargetInsertBefore NS_SWIFT_NAME(insertBefore) = 1,	//!< 選択始点挿入
	ECReplaceTargetInsertAfter NS_SWIFT_NAME(insertAfter) = 2,		//!< 選択終点追加
	ECReplaceTargetDeleteLine NS_SWIFT_NAME(deleteLine) = 3,		//!< 行削除
} NS_SWIFT_NAME(EditorReplaceTarget);

//! 编辑画面的光标和选择（查找、替换命令的输入和结果。sakura::core::SearchView）
typedef struct ECSearchView {
	ECPosition caret;
	bool hasSelection;		//!< 有普通选择。selection 是 from == to 时表示上次长度 0 的匹配
	ECRange selection;
} NS_SWIFT_NAME(EditorSearchView) ECSearchView;

//! 置换的条件（sakura::core::ReplaceOptions）
typedef struct ECReplaceOptions {
	ECSearchOptions search;
	ECReplaceTarget target;
	bool paste;				//!< クリップボードから貼り付ける（置换后的文字是剪贴板的文字，原样插入）
	bool searchAll;			//!< 先頭（末尾）から再検索する
	bool consecutiveAll;	//!< 「すべて置換」は置換の繰返し
	bool selectedArea;		//!< すべて置換：選択範囲
} NS_SWIFT_NAME(EditorReplaceOptions) ECReplaceOptions;

//! 指定行へジャンプ的条件（sakura::core::JumpOptions）
typedef struct ECJumpOptions {
	NSInteger lineNumber;			//!< 行番号（从 1 开始）
	bool lineNumIsCRLF;				//!< 改行単位の行番号（false 是折り返し単位）
	bool plsql;						//!< PL/SQLコンパイルエラー行を処理する
	NSInteger plsqlBlockFirstLine;	//!< 「テキストの n 行目をブロックの1行目とする」
} NS_SWIFT_NAME(EditorJumpOptions) ECJumpOptions;

/*!
	查找、替换命令的结果（sakura::core::SearchResult、ReplaceResult）
*/
NS_SWIFT_NAME(EditorSearchResult)
@interface ECSearchResult : NSObject
//! 查找：结果。置換：第一次查找（找要换的地方）的结果。すべて置換：正则表达式有错误时是 invalidPattern
@property (readonly) ECSearchStatus status;
//! 置換：换了之后下一次查找的结果（notFound 时原版显示「最後まで置換しました。」）
@property (readonly) ECSearchStatus next;
//! 换了的个数
@property (readonly) NSInteger count;
//! 之后的光标和选择
@property (readonly) ECSearchView view;
//! 正则表达式的错误（原版在「正規表現の構文に誤りがあります。」后面显示的部分）
@property (readonly, copy) NSString *error;
- (instancetype)init NS_UNAVAILABLE;
@end

//! 查找文字的标记（逻辑行内 from..<to 用 color 的颜色显示）
NS_SWIFT_NAME(EditorSearchMark)
@interface ECSearchMark : NSObject
@property (readonly) NSInteger from;
@property (readonly) NSInteger to;
@property (readonly) ECColorIndex color;
- (instancetype)init NS_UNAVAILABLE;
@end

//! 语法颜色的一段（第 33 步：逻辑行内 from..<to 用 color 的颜色显示）
NS_SWIFT_NAME(EditorSyntaxColorRun)
@interface ECSyntaxColorRun : NSObject
@property (readonly) NSInteger from;
@property (readonly) NSInteger to;
@property (readonly) ECColorIndex color;
- (instancetype)init NS_UNAVAILABLE;
@end

/*!
	查找、替换、跳转的共通设置（sakura::core::SearchSettings，保存在 sakura.ini）。
	改了以后用 +[ECCore setSearchSettings:] 放回去。
*/
NS_SWIFT_NAME(EditorSearchSettings)
@interface ECSearchSettings : NSObject
@property ECSearchOptions options;			//!< 上次的查找条件
@property BOOL notifyNotFound;				//!< 見つからないときにメッセージを表示
@property BOOL autoCloseFind;				//!< 検索ダイアログを自動的に閉じる
@property BOOL autoCloseReplace;			//!< 置換ダイアログを自動的に閉じる
@property BOOL searchAll;					//!< 先頭（末尾）から再検索する
@property BOOL consecutiveAll;				//!< 「すべて置換」は置換の繰返し
@property BOOL selectedArea;				//!< 置換の範囲が「選択範囲」
@property BOOL caretTextForSearch;			//!< カーソル位置の文字列をデフォルトの検索文字列にする
@property BOOL inheritKeyOtherView;			//!< 次・前検索で他のビューの検索条件を引き継ぐ
@property BOOL jumpLineNumIsCRLF;			//!< 指定行へジャンプ：改行単位の行番号
@end

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
	文件对话框的编码列表里的一项（sakura::core::EncodingChoice，第 30 步）
*/
NS_SWIFT_NAME(EditorEncodingChoice)
@interface ECEncodingChoice : NSObject
@property (readonly) ECEncoding encoding;
@property (readonly, copy) NSString *name;		//!< 列表里显示的名字（"自動選択"、"EUC-JP" 等）
- (instancetype)init NS_UNAVAILABLE;
@end

/*!
	タイプ別設定的一个（sakura::core::TypeSettingInfo，第 40 步）
*/
NS_SWIFT_NAME(EditorTypeSetting)
@interface ECTypeSetting : NSObject
@property (readonly) NSInteger index;				//!< 编号（sakura.ini 的 Types(N) 的 N）。0 是「基本」
@property (readonly, copy) NSString *name;			//!< 設定の名前
@property (readonly, copy) NSString *extensions;	//!< ファイル拡張子
- (instancetype)init NS_UNAVAILABLE;
@end

/*!
	保存前的检查结果（sakura::core::SaveCheck，原版 CCodeChecker::OnCheckSave，第 30 步）
*/
NS_SWIFT_NAME(EditorSaveCheck)
@interface ECSaveCheck : NSObject
//! 换行符混在（类型别设置「保存時に改行コードの混在を警告する」打开、并且不转换换行符时）
@property (readonly) BOOL eolMixed;
//! 有不能用这个编码表示的字符
@property (readonly) BOOL lostSome;
//! 最初不能表示的位置。column 为 -1 表示行内的位置不明
@property (readonly) NSInteger lostLine;
@property (readonly) NSInteger lostColumn;
@property (readonly, copy) NSString *lostCharacter;	//!< 不能表示的那个字（不明时是空）
@property (readonly, copy) NSString *lostCharCode;	//!< 那个字的代码（"U+3042" 等）
- (instancetype)init NS_UNAVAILABLE;
@end

/*!
	「最近使ったファイル」的一项（sakura::core::RecentFile，原版 CMRUFile，第 31 步）
*/
NS_SWIFT_NAME(EditorRecentFile)
@interface ECRecentFile : NSObject
@property (readonly, copy) NSString *path;
@property (readonly) ECEncoding encoding;				//!< 上次的编码
@property (readonly) ECPosition caret;					//!< 上次的光标位置
@property (readonly) NSInteger viewTopLine;			//!< 上次表示域的第一行
@property (readonly) BOOL favorite;					//!< お気に入り
@property (readonly, copy) NSString *menuLabel;		//!< 菜单的文字（原版 GetMenuFullLabel_MRU："&1 路径  [UTF-8]"）
- (instancetype)init NS_UNAVAILABLE;
@end

/*!
	「最近使ったフォルダー」的一项（原版 CMRUFolder）
*/
NS_SWIFT_NAME(EditorRecentFolder)
@interface ECRecentFolder : NSObject
@property (readonly, copy) NSString *path;				//!< 末尾带 "/"
@property (readonly) BOOL favorite;
@property (readonly, copy) NSString *menuLabel;
- (instancetype)init NS_UNAVAILABLE;
@end

/*!
	主菜单的一项（原版 CMainMenu，来自 MainMenu.ini）（第 34 步）
*/
typedef NS_ENUM(NSInteger, ECMenuItemType) {
	ECMenuItemTypeSubmenu = 0,		//!< 子菜单（T_NODE）
	ECMenuItemTypeCommand = 1,		//!< 命令（T_LEAF）
	ECMenuItemTypeSeparator = 2,	//!< 分隔线（T_SEPARATOR）
	ECMenuItemTypeSpecial = 3,		//!< 特殊列表（T_SPECIAL，最近使ったファイル等）
} NS_SWIFT_NAME(EditorMenuItemType);

NS_SWIFT_NAME(EditorMenuItem)
@interface ECMenuItem : NSObject
@property (readonly) NSInteger level;			//!< 层次（0 是菜单栏）
@property (readonly) ECMenuItemType type;
@property (readonly) ECCommand command;			//!< 功能编号
@property (readonly, copy) NSString *name;		//!< 显示名（日文）
@property (readonly, copy) NSString *accessKey;	//!< 访问键（Mac 不显示）
- (instancetype)init NS_UNAVAILABLE;
@end

//! 按键分配的修饰键（原版 m_nFuncCodeArr 的序号）
typedef NS_OPTIONS(NSUInteger, ECKeyModifiers) {
	ECKeyModifierShift = 1,
	ECKeyModifierCtrl = 2,
	ECKeyModifierAlt = 4,
} NS_SWIFT_NAME(EditorKeyModifiers);

/*!
	按键分配的一项（原版 KEYDATA）（第 34 步）。keyCode 是 Windows 的虚拟键码
*/
NS_SWIFT_NAME(EditorKeyBinding)
@interface ECKeyBinding : NSObject
@property (readonly) NSInteger keyCode;
@property (readonly) ECKeyModifiers modifiers;
@property (readonly) ECCommand command;
@property (readonly, copy) NSString *keyName;
- (instancetype)init NS_UNAVAILABLE;
@end

/*!
	打开时从历史恢复的位置（sakura::core::RestoredView，原版 CMruListener::OnAfterLoad）
*/
NS_SWIFT_NAME(EditorRestoredView)
@interface ECRestoredView : NSObject
@property (readonly) ECPosition caret;
@property (readonly) NSInteger viewTopLine;			//!< 表示域的第一行（排版行）
@property (readonly) BOOL toEnd;						//!< 上次的位置超过了文件末尾：移到文件末尾
- (instancetype)init NS_UNAVAILABLE;
@end

//! 导入设置的结果（第 35 步，core::ImportResult）
typedef NS_ENUM(NSInteger, ECImportResult) {
	ECImportResultImported = 0,			//!< 成功（检查时：是设置文件）
	ECImportResultNotSettingsFile,		//!< 不是サクラエディタ的设置文件
	ECImportResultReadFailed,			//!< 读不了
	ECImportResultWriteFailed,			//!< 写不了 sakura.ini
} NS_SWIFT_NAME(EditorImportResult);

/*!
	タイプ別設定「カラー」页的一行（core::ColorItemInfo，第 40 步）
*/
NS_SWIFT_NAME(EditorColorItem)
@interface ECColorItem : NSObject
@property (readonly) NSInteger index;			//!< 颜色的编号
@property (readonly, copy) NSString *name;		//!< 显示的名字
@property (readonly, copy) NSString *key;		//!< sakura.ini 的项目（「C[TXT]」等）
@property (readonly) BOOL forceDisplay;			//!< 「色分け/表示」不能关
@property (readonly) BOOL noText;				//!< 没有文字色
@property (readonly) BOOL noBack;				//!< 没有背景色
@property (readonly) BOOL noBold;				//!< 不能是太字
@property (readonly) BOOL noUnderline;			//!< 不能加下線
- (instancetype)init NS_UNAVAILABLE;
@end

//! タイプ別設定的导入・导出的文件（core::TypeSettingFile，第 40 步）
typedef NS_ENUM(NSInteger, ECTypeSettingFile) {
	ECTypeSettingFileColors = 0,		//!< 色設定（*.col）
	ECTypeSettingFileRegexKeywords,		//!< 正規表現キーワード（*.rkw）
	ECTypeSettingFileKeywordHelp,		//!< キーワード辞書の一覧（*.txt）
} NS_SWIFT_NAME(EditorTypeSettingFile);

//! 导入・导出的结果（core::TypeSettingFileResult）
NS_SWIFT_NAME(EditorTypeSettingFileResult)
@interface ECTypeSettingFileResult : NSObject
@property (readonly) BOOL succeeded;
@property (readonly, copy) NSString *message;		//!< 原版的消息。没有时是空字符串
//! 导入后的值（项目 → 值）。没有的项是空字符串
@property (readonly, copy) NSDictionary<NSString *, NSString *> *values;
- (instancetype)init NS_UNAVAILABLE;
@end

//! タイプ別設定的文件（*.ini）的内容（core::TypeSettingFileInfo，第 40 步）
NS_SWIFT_NAME(EditorTypeSettingFileInfo)
@interface ECTypeSettingFileInfo : NSObject
@property (readonly) BOOL succeeded;
@property (readonly, copy) NSString *message;
@property (readonly, copy) NSString *typeName;
@property (readonly, copy) NSString *version;
@property (readonly) NSInteger structureVersion;
@property (readonly) BOOL versionDiffers;
@property (readonly, copy) NSArray<NSString *> *colorFiles;
- (instancetype)init NS_UNAVAILABLE;
@end

//! タイプ別設定的インポート的结果（core::TypeSettingImportResult）
NS_SWIFT_NAME(EditorTypeSettingImportResult)
@interface ECTypeSettingImportResult : NSObject
@property (readonly) BOOL succeeded;
@property (readonly, copy) NSString *message;
@property (readonly) NSInteger index;
@property (readonly) BOOL added;
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
//! path 是不是サクラエディタ的设置文件（sakura.ini）（第 35 步）
+ (ECImportResult)checkSettingsFile:(NSString *)path NS_SWIFT_NAME(checkSettingsFile(_:));
//! 导入 Windows 版的 sakura.ini（历史保留 Mac 的）。重新启动以后生效，在那之前结束时不写出设置
+ (ECImportResult)importSettings:(NSString *)path NS_SWIFT_NAME(importSettings(_:));
//! 导入以后、重新启动之前是 YES
@property (class, readonly) BOOL isSettingsImportPending;
//! 导入前的设置的备份（sakura.ini.before-import）
@property (class, readonly, copy) NSString *settingsBackupPath;

//! 共通設定的一项（第 39 步）。节和项目与 sakura.ini 相同（Common、Nickname、Statusbar、タイプ別設定的 Types(N)），值是 ini 里的写法。没有这一项时 nil
+ (nullable NSString *)commonSettingInSection:(NSString *)section key:(NSString *)key NS_SWIFT_NAME(commonSetting(section:key:));
//! 改共通設定的一项（与改 sakura.ini 后读入相同，范围限制照原版）。没有这一项时 NO
+ (BOOL)setCommonSetting:(NSString *)value section:(NSString *)section key:(NSString *)key NS_SWIFT_NAME(setCommonSetting(_:section:key:));
//! 一次改同一节的几项（项目 → 值）。ファイル名表示 的置換リスト（ArrNum、From%02d、To%02d）用。有一项不在这一节里时 NO，什么也不改
+ (BOOL)setCommonSettings:(NSDictionary<NSString *, NSString *> *)values section:(NSString *)section NS_SWIFT_NAME(setCommonSettings(_:section:));
//! 现在的设置写进 sakura.ini。导入设置以后、重新启动之前不写，返回 NO
+ (BOOL)saveSettings;
//! タイプ別設定的一览（第 40 步。顺序与 Types(0)、Types(1)… 相同）
@property (class, readonly, copy) NSArray<ECTypeSetting *> *typeSettings;
//! タイプ別設定一覧（第 40 步，原版 CDlgTypeList）：最大个数、追加、複製、削除、↑↓、初期化
@property (class, readonly) NSInteger maxTypeSettings;
+ (NSInteger)addTypeSetting;
+ (NSInteger)copyTypeSetting:(NSInteger)index NS_SWIFT_NAME(copyTypeSetting(_:));
+ (BOOL)deleteTypeSetting:(NSInteger)index NS_SWIFT_NAME(deleteTypeSetting(_:));
+ (NSInteger)moveTypeSetting:(NSInteger)index up:(BOOL)up NS_SWIFT_NAME(moveTypeSetting(_:up:));
+ (NSString *)initializeTypeSetting:(NSInteger)index NS_SWIFT_NAME(initializeTypeSetting(_:));
+ (ECTypeSettingFileInfo *)checkTypeSettingFile:(NSString *)path NS_SWIFT_NAME(checkTypeSettingFile(_:));
//! colorType：-1 文件里的色、0 以上是那个类型的色。colorFile 不是空时用同一个文件夹的色設定文件
+ (ECTypeSettingImportResult *)importTypeSetting:(NSString *)path index:(NSInteger)index addNew:(BOOL)addNew
	colorType:(NSInteger)colorType colorFile:(NSString *)colorFile NS_SWIFT_NAME(importTypeSetting(_:index:addNew:colorType:colorFile:));
+ (ECTypeSettingFileResult *)exportTypeSetting:(NSInteger)index path:(NSString *)path NS_SWIFT_NAME(exportTypeSetting(_:path:));
//! 「カラー」页的全部的行（第 40 步）
@property (class, readonly, copy) NSArray<ECColorItem *> *colorItems;
//! 強調キーワード的セット名（顺序就是编号）
@property (class, readonly, copy) NSArray<NSString *> *keywordSetNames;
//! 从文件读入色設定等（原版的格式）。pending 是窗口里还没 OK 的值。不改核心库的设置
+ (ECTypeSettingFileResult *)importTypeSettingFile:(ECTypeSettingFile)kind typeIndex:(NSInteger)typeIndex
	pending:(NSDictionary<NSString *, NSString *> *)pending path:(NSString *)path NS_SWIFT_NAME(importTypeSettingFile(_:typeIndex:pending:path:));
//! 正規表現キーワード：用「/…/k」等围起来了吗（原版 RegexKeyCheckSyntax）
+ (BOOL)regexKeywordHasDelimiters:(NSString *)keyword NS_SWIFT_NAME(regexKeywordHasDelimiters(_:));
//! 正規表現キーワード：正则表达式的语法正确吗（原版 CheckRegexpSyntax(…, bKakomi)）
+ (BOOL)regexKeywordSyntaxOK:(NSString *)keyword NS_SWIFT_NAME(regexKeywordSyntaxOK(_:));
//! キーワード辞書的「辞書の説明」（辞書文件的第 1 行）。打不开时 nil
+ (nullable NSString *)keywordHelpDictionaryAbout:(NSString *)path NS_SWIFT_NAME(keywordHelpDictionaryAbout(_:));
//! 写出到文件（原版的エクスポート的格式）
+ (ECTypeSettingFileResult *)exportTypeSettingFile:(ECTypeSettingFile)kind typeIndex:(NSInteger)typeIndex
	pending:(NSDictionary<NSString *, NSString *> *)pending path:(NSString *)path NS_SWIFT_NAME(exportTypeSettingFile(_:typeIndex:pending:path:));

//! 编码的显示名（"SJIS"、"UTF-8" 等）。不能用的编码是空字符串
+ (NSString *)nameOfEncoding:(ECEncoding)encoding NS_SWIFT_NAME(name(ofEncoding:));
//! 功能的名字（与原版菜单相同，日文）。不存在时是空字符串
+ (NSString *)nameOfCommand:(ECCommand)command NS_SWIFT_NAME(name(ofCommand:));
//! 主菜单的构成（原版 MainMenu.ini，按顺序，用 level 表示层次）（第 34 步）
@property (class, readonly, copy) NSArray<ECMenuItem *> *mainMenu;
//! 按键分配（原版 m_sKeyBind 里分配了功能的组合）
@property (class, readonly, copy) NSArray<ECKeyBinding *> *keyBindings;
//! 这个按键（Windows 虚拟键码）和修饰键分配的功能。没有分配时是 0
+ (ECCommand)commandForKeyCode:(NSInteger)keyCode modifiers:(ECKeyModifiers)modifiers NS_SWIFT_NAME(command(forKeyCode:modifiers:));
//! 换行符的文字（"\r\n" 等）
+ (NSString *)textOfEol:(ECEol)eol NS_SWIFT_NAME(text(ofEol:));

//! 打开、保存对话框的「文字コードセット」列表（原版 CCodeTypesForCombobox）。第一项是「自動選択」
@property (class, readonly, copy) NSArray<ECEncodingChoice *> *encodingChoices;
//! 勾选「CP」后追加的代码页（CP_ACP、CP_OEM、系统的代码页、UTF-32）
@property (class, readonly, copy) NSArray<ECEncodingChoice *> *codePageChoices;
//! 这个编码能否加 BOM（原版 CCodeTypeName::UseBom）
+ (BOOL)encodingCanHaveBOM:(ECEncoding)encoding NS_SWIFT_NAME(canHaveBOM(_:));
//! 换成这个编码时 BOM 是否默认勾选（原版 CCodeTypeName::IsBomDefOn）
+ (BOOL)encodingBOMDefault:(ECEncoding)encoding NS_SWIFT_NAME(bomDefault(_:));
//! 能否作为タイプ別設定的デフォルトの文字コード（原版 CCodeTypeName::CanDefault，第 40 步）
+ (BOOL)encodingCanBeDefault:(ECEncoding)encoding NS_SWIFT_NAME(canBeDefault(_:));

//! 「最近使ったファイル」菜单里显示的历史（新的在前，「ファイルの履歴MAX」个）（第 31 步）
@property (class, readonly, copy) NSArray<ECRecentFile *> *recentFiles;
//! 「最近使ったフォルダー」菜单里显示的历史
@property (class, readonly, copy) NSArray<ECRecentFolder *> *recentFolders;
//! 历史里这个文件的记录（菜单里不显示的也算）
+ (nullable ECRecentFile *)recentFileForPath:(NSString *)path NS_SWIFT_NAME(recentFile(path:));
//! 从历史里删除这个文件
+ (void)removeRecentFileAtPath:(NSString *)path NS_SWIFT_NAME(removeRecentFile(path:));
//! 删除全部「最近使ったファイル」（共通設定 > 全般「履歴をクリア」，第 39 步）
+ (void)clearRecentFiles;
//! 删除全部「最近使ったフォルダー」（第 39 步）
+ (void)clearRecentFolders;

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
/*!
	フォントサイズ拡大／縮小（原版 Command_SETFONTSIZE 的倍率表，第 34 步）：从基准的大小 base（点）和现在的倍率 zoom
	移动 steps 级，按 unit 点取整。不能再变时返回 NO
*/
+ (BOOL)zoomFontSize:(double)base zoom:(double)zoom steps:(NSInteger)steps unit:(double)unit
	size:(double *)outSize newZoom:(double *)outZoom NS_SWIFT_NAME(zoomFontSize(_:zoom:steps:unit:size:newZoom:));

// ----- 查找、替换（第 32 步） -----

//! 查找、替换、跳转的共通设置
@property (class, strong) ECSearchSettings *searchSettings;
//! 查找的文字的历史（新的在前）
@property (class, readonly, copy) NSArray<NSString *> *searchKeyHistory;
//! 置换后的文字的历史（新的在前）
@property (class, readonly, copy) NSArray<NSString *> *replaceKeyHistory;
//! 登记到历史（_MAX_PATH 以上长度的不登记）。登记后序号加 1
+ (void)addSearchKey:(NSString *)key NS_SWIFT_NAME(addSearchKey(_:));
+ (void)addReplaceKey:(NSString *)key NS_SWIFT_NAME(addReplaceKey(_:));
//! 历史的序号（每次登记加 1）
@property (class, readonly) NSInteger searchKeySequence;
@property (class, readonly) NSInteger replaceKeySequence;
//! 正则表达式库的版本（查找对话框里显示）
@property (class, readonly, copy) NSString *regexpVersion;
//! 正则表达式的语法错误（没有错误时是 nil）
+ (nullable NSString *)regexpSyntaxErrorForPattern:(NSString *)pattern matchCase:(BOOL)matchCase NS_SWIFT_NAME(regexpSyntaxError(_:matchCase:));

- (instancetype)init NS_UNAVAILABLE;
@end

/*!
	一个文档（一个文件）。sakura::core::Document 的包装。
	排版（自动换行）也在这里（第 27 步）。光标、选择、绘制属于编辑画面，不在这里。
	只能在一个线程（通常是主线程）里使用。
*/
/*!
	共通設定 > 強調キーワード 的编辑（core::KeywordSetEditor，第 40 步）。复制核心库现在的强调关键字来编辑，
	OK 时把 iniValues 写进 [KeyWords] 节
*/
NS_SWIFT_NAME(EditorKeywordSetEditor)
@interface ECKeywordSetEditor : NSObject
- (nullable instancetype)init NS_DESIGNATED_INITIALIZER;
@property (readonly) NSInteger setCount;
- (NSString *)nameOfSet:(NSInteger)set NS_SWIFT_NAME(name(ofSet:));
- (BOOL)isCaseSensitive:(NSInteger)set NS_SWIFT_NAME(isCaseSensitive(_:));
@property NSInteger currentSet;
//! 关键字的文字（排好的顺序）和编号
- (NSArray<NSString *> *)keywordsOfSet:(NSInteger)set NS_SWIFT_NAME(keywords(ofSet:));
- (NSArray<NSNumber *> *)keywordIndicesOfSet:(NSInteger)set NS_SWIFT_NAME(keywordIndices(ofSet:));
- (NSInteger)freeCountOfSet:(NSInteger)set NS_SWIFT_NAME(freeCount(ofSet:));
- (BOOL)canAddKeywordToSet:(NSInteger)set NS_SWIFT_NAME(canAddKeyword(toSet:));
- (BOOL)addSet:(NSString *)name NS_SWIFT_NAME(addSet(_:));
- (BOOL)deleteSet:(NSInteger)set NS_SWIFT_NAME(deleteSet(_:));
- (void)renameSet:(NSInteger)set to:(NSString *)name NS_SWIFT_NAME(renameSet(_:to:));
- (void)setCaseSensitive:(BOOL)on ofSet:(NSInteger)set NS_SWIFT_NAME(setCaseSensitive(_:ofSet:));
//! 0 成功、1 セット番号エラー、2 已满、3 空、4 重复
- (NSInteger)addKeyword:(NSString *)keyword toSet:(NSInteger)set NS_SWIFT_NAME(addKeyword(_:toSet:));
- (BOOL)updateKeyword:(NSInteger)index ofSet:(NSInteger)set to:(NSString *)keyword NS_SWIFT_NAME(updateKeyword(_:ofSet:to:));
- (void)deleteKeyword:(NSInteger)index ofSet:(NSInteger)set NS_SWIFT_NAME(deleteKeyword(_:ofSet:));
- (NSInteger)cleanSet:(NSInteger)set NS_SWIFT_NAME(clean(set:));
//! 读入・写出 *.kwd。message 是原版的消息
- (BOOL)importToSet:(NSInteger)set path:(NSString *)path message:(NSString *_Nullable *_Nullable)message NS_SWIFT_NAME(importFile(toSet:path:message:));
- (BOOL)exportSet:(NSInteger)set path:(NSString *)path message:(NSString *_Nullable *_Nullable)message NS_SWIFT_NAME(exportFile(set:path:message:));
//! [KeyWords] 节的值（项目 → 值）
@property (readonly, copy) NSDictionary<NSString *, NSString *> *iniValues;
@end

/*!
	共通設定 > キー割り当て・メインメニュー・ツールバー・カスタムメニュー 的编辑（core::CommandSettingsEditor，第 41 步）。
	复制核心库现在的共通設定（原版 CPropCommon::m_Common），这几页共用一个；OK 时把 iniValues(section:) 写进那一节
*/
//! メインメニュー的一项（core::CommandSettingsEditor::MainMenuEntry，第 41 步）
NS_SWIFT_NAME(EditorMainMenuEntry)
@interface ECMainMenuEntry : NSObject
@property NSInteger level;
@property BOOL isNode;
@property NSInteger code;
@property (copy) NSString *name;
@property (copy) NSString *accessKey;
- (instancetype)initWithLevel:(NSInteger)level isNode:(BOOL)isNode code:(NSInteger)code name:(NSString *)name accessKey:(NSString *)accessKey;
@end

NS_SWIFT_NAME(EditorCommandSettingsEditor)
@interface ECCommandSettingsEditor : NSObject
- (nullable instancetype)init NS_DESIGNATED_INITIALIZER;
// ----- 機能の検索（原版 CFuncLookup）-----
//! 「種別」
@property (readonly, copy) NSArray<NSString *> *functionCategories;
//! 这个分类的功能的编号和名字
- (NSArray<NSNumber *> *)functionCodesInCategory:(NSInteger)category NS_SWIFT_NAME(functionCodes(inCategory:));
- (NSArray<NSString *> *)functionNamesInCategory:(NSInteger)category NS_SWIFT_NAME(functionNames(inCategory:));
- (NSString *)nameOfFunction:(NSInteger)code NS_SWIFT_NAME(name(ofFunction:));
// ----- キー割り当て -----
@property (readonly) NSInteger keyCount;
- (NSString *)nameOfKey:(NSInteger)key NS_SWIFT_NAME(name(ofKey:));
//! modifiers 是 Shift 1、Ctrl 2、Alt 4 的组合。0 是未割当
- (NSInteger)functionOfKey:(NSInteger)key modifiers:(NSInteger)modifiers NS_SWIFT_NAME(function(ofKey:modifiers:));
- (void)setFunction:(NSInteger)code ofKey:(NSInteger)key modifiers:(NSInteger)modifiers NS_SWIFT_NAME(setFunction(_:ofKey:modifiers:));
//! 機能に割り当てられているキー（「Shift+Ctrl+F3」等）
- (NSArray<NSString *> *)keysAssignedToFunction:(NSInteger)code NS_SWIFT_NAME(keysAssigned(toFunction:));
//! 读入・写出 *.key。message 是原版的消息
- (BOOL)importKeyBindFromPath:(NSString *)path message:(NSString *_Nullable *_Nullable)message NS_SWIFT_NAME(importKeyBind(path:message:));
- (BOOL)exportKeyBindToPath:(NSString *)path message:(NSString *_Nullable *_Nullable)message NS_SWIFT_NAME(exportKeyBind(path:message:));
// ----- メインメニュー -----
@property (readonly, copy) NSArray<ECMainMenuEntry *> *mainMenuEntries;
@property (readonly) BOOL mainMenuKeyParentheses;
//! 页的内容写进复制（原版 GetData：没有「共通設定」时加在最后）
- (BOOL)setMainMenu:(NSArray<ECMainMenuEntry *> *)entries keyParentheses:(BOOL)keyParentheses NS_SWIFT_NAME(setMainMenu(_:keyParentheses:));
//! 初期設定（内置的 MainMenu.ini）
- (void)initializeMainMenu;
//! 「特別機能」
@property (readonly, copy) NSString *specialFunctionCategory;
@property (readonly, copy) NSArray<NSNumber *> *specialFunctionCodes;
@property (readonly, copy) NSArray<NSString *> *specialFunctionNames;
- (BOOL)importMainMenuFromPath:(NSString *)path message:(NSString *_Nullable *_Nullable)message NS_SWIFT_NAME(importMainMenu(path:message:));
- (BOOL)exportMainMenuToPath:(NSString *)path message:(NSString *_Nullable *_Nullable)message NS_SWIFT_NAME(exportMainMenu(path:message:));
// ----- カスタムメニュー -----
@property (readonly) NSInteger customMenuCount;
@property (readonly) NSInteger maxCustomMenuItems;
- (NSString *)displayNameOfCustomMenu:(NSInteger)menu NS_SWIFT_NAME(displayName(ofCustomMenu:));
- (NSString *)nameOfCustomMenu:(NSInteger)menu NS_SWIFT_NAME(name(ofCustomMenu:));
- (void)setName:(NSString *)name ofCustomMenu:(NSInteger)menu NS_SWIFT_NAME(setName(_:ofCustomMenu:));
- (BOOL)customMenuIsSubmenu:(NSInteger)menu NS_SWIFT_NAME(customMenuIsSubmenu(_:));
- (void)setCustomMenu:(NSInteger)menu isSubmenu:(BOOL)on NS_SWIFT_NAME(setCustomMenu(_:isSubmenu:));
//! 项目的功能（0 是区切線）和アクセスキー（没有时是空字符串）
- (NSArray<NSNumber *> *)codesOfCustomMenu:(NSInteger)menu NS_SWIFT_NAME(codes(ofCustomMenu:));
- (NSArray<NSString *> *)accessKeysOfCustomMenu:(NSInteger)menu NS_SWIFT_NAME(accessKeys(ofCustomMenu:));
- (void)setCustomMenu:(NSInteger)menu codes:(NSArray<NSNumber *> *)codes accessKeys:(NSArray<NSString *> *)keys NS_SWIFT_NAME(setCustomMenu(_:codes:accessKeys:));
- (BOOL)importCustomMenuFromPath:(NSString *)path message:(NSString *_Nullable *_Nullable)message NS_SWIFT_NAME(importCustomMenu(path:message:));
- (BOOL)exportCustomMenuToPath:(NSString *)path message:(NSString *_Nullable *_Nullable)message NS_SWIFT_NAME(exportCustomMenu(path:message:));
// ----- ツールバー -----
//! ボタン番号
@property (readonly, copy) NSArray<NSNumber *> *toolbarButtons;
@property (readonly) BOOL toolbarIsFlat;
- (void)setToolbarButtons:(NSArray<NSNumber *> *)buttons flat:(BOOL)flat NS_SWIFT_NAME(setToolbar(_:flat:));
//! ボタンの種類：0 ボタン、1 区切、2 折返、3 不明
- (NSInteger)kindOfToolbarButton:(NSInteger)number NS_SWIFT_NAME(kind(ofToolbarButton:));
- (NSInteger)functionOfToolbarButton:(NSInteger)number NS_SWIFT_NAME(function(ofToolbarButton:));
//! mytool.bmp のアイコン番号（無いとき -1）
- (NSInteger)iconOfToolbarButton:(NSInteger)number NS_SWIFT_NAME(icon(ofToolbarButton:));
//! この機能のボタン番号。ボタンが無いとき -1
- (NSInteger)toolbarButtonForFunction:(NSInteger)code NS_SWIFT_NAME(toolbarButton(forFunction:));
@property (readonly) NSInteger toolbarSeparatorButton;
@property (readonly) NSInteger toolbarWrapButton;
//! 这一节的值（项目 → 值）。节：KeyBind、MainMenu、CustMenu、Toolbar
- (NSDictionary<NSString *, NSString *> *)iniValuesOfSection:(NSString *)section NS_SWIFT_NAME(iniValues(section:));
@end

// ---------------------------------------------------------------------------
// アウトライン解析（第 42 步。sakura::core::OutlineResult 等）
// ---------------------------------------------------------------------------

//! アウトライン解析方法（数值与原版的 EOutlineType 相同）
typedef NS_ENUM(NSInteger, ECOutlineType) {
	ECOutlineTypeDefault NS_SWIFT_NAME(default) = -1,	//!< 类型别设置的方法
	ECOutlineTypeC NS_SWIFT_NAME(c) = 0,
	ECOutlineTypeCCpp NS_SWIFT_NAME(cCpp) = 1,
	ECOutlineTypePlSql NS_SWIFT_NAME(plSql) = 2,
	ECOutlineTypeText NS_SWIFT_NAME(text) = 3,
	ECOutlineTypeJava NS_SWIFT_NAME(java) = 4,
	ECOutlineTypeCobol NS_SWIFT_NAME(cobol) = 5,
	ECOutlineTypeAsm NS_SWIFT_NAME(asm) = 6,
	ECOutlineTypePerl NS_SWIFT_NAME(perl) = 7,
	ECOutlineTypeVisualBasic NS_SWIFT_NAME(visualBasic) = 8,
	ECOutlineTypeWzText NS_SWIFT_NAME(wzText) = 9,
	ECOutlineTypeHtml NS_SWIFT_NAME(html) = 10,
	ECOutlineTypeTex NS_SWIFT_NAME(tex) = 11,
	ECOutlineTypeRuleFile NS_SWIFT_NAME(ruleFile) = 12,
	ECOutlineTypePython NS_SWIFT_NAME(python) = 13,
	ECOutlineTypeErlang NS_SWIFT_NAME(erlang) = 14,
	ECOutlineTypeXml NS_SWIFT_NAME(xml) = 15,
	ECOutlineTypeCpp NS_SWIFT_NAME(cpp) = 16,
	ECOutlineTypeBookmark NS_SWIFT_NAME(bookmark) = 18,
	ECOutlineTypeFileTree NS_SWIFT_NAME(fileTree) = 20,
	ECOutlineTypeTree NS_SWIFT_NAME(tree) = 100,
	ECOutlineTypeTreeTagJump NS_SWIFT_NAME(treeTagJump) = 101,
	ECOutlineTypeClassTree NS_SWIFT_NAME(classTree) = 200,
	ECOutlineTypeList NS_SWIFT_NAME(list) = 300,
} NS_SWIFT_NAME(OutlineType);

//! ツリーの「順序」（数值与原版的 SORTTYPE_DEFAULT 等相同）
typedef NS_ENUM(NSInteger, ECOutlineSort) {
	ECOutlineSortDefault NS_SWIFT_NAME(default) = 0,
	ECOutlineSortDefaultDesc NS_SWIFT_NAME(defaultDesc) = 1,
	ECOutlineSortAtoZ NS_SWIFT_NAME(aToZ) = 2,
	ECOutlineSortZtoA NS_SWIFT_NAME(zToA) = 3,
} NS_SWIFT_NAME(OutlineSort);

//! 解析结果的一项（原版 CFuncInfo）。行・桁从 1 开始
NS_SWIFT_NAME(OutlineItem)
@interface ECOutlineItem : NSObject
@property (readonly) NSInteger line;			//!< 逻辑行（1 开始）
@property (readonly) NSInteger column;			//!< 逻辑桁（1 开始）
@property (readonly) NSInteger layoutLine;		//!< 排版行（1 开始）
@property (readonly) NSInteger layoutColumn;	//!< 排版横向位置 + 1
@property (readonly, copy) NSString *name;
@property (readonly, copy) NSString *fileName;	//!< 别的文件的项目（没有时空）
@property (readonly) NSInteger info;
@property (readonly) NSInteger depth;
- (instancetype)init NS_UNAVAILABLE;
@end

//! ツリーの一つの項目
NS_SWIFT_NAME(OutlineNode)
@interface ECOutlineNode : NSObject
@property (readonly, copy) NSString *label;
@property (readonly) NSInteger item;			//!< items 的下标。クラス名等的项目是 -1
@property (readonly) NSInteger order;			//!< 加入的顺序（「デフォルト」的顺序）
@property (readonly) BOOL expanded;				//!< 打开窗口时展开着
@property (readonly, copy) NSArray<ECOutlineNode *> *children;
- (instancetype)init NS_UNAVAILABLE;
@end

//! リストの一行
NS_SWIFT_NAME(OutlineRow)
@interface ECOutlineRow : NSObject
@property (readonly) NSInteger item;			//!< items 的下标
@property (readonly) NSInteger line;			//!< 「行」
@property (readonly) NSInteger column;			//!< 「桁」
@property (readonly, copy) NSString *name;		//!< 「関数名」
@property (readonly, copy) NSString *remark;	//!< 第 4 列
- (instancetype)init NS_UNAVAILABLE;
@end

/*!
	アウトライン解析的结果（sakura::core::OutlineResult：原版 Command_FUNCLIST + CDlgFuncList::SetData）。
	並べ替えるとツリー・リストが変わる
*/
NS_SWIFT_NAME(OutlineResult)
@interface ECOutlineResult : NSObject
@property (readonly) ECOutlineType type;		//!< 实际用的解析方法
@property (readonly) ECOutlineType listType;	//!< 一覧的形式
@property (readonly, copy) NSString *title;		//!< 窗口标题
@property (readonly, copy) NSString *filePath;	//!< 解析的文件（新文件时空）
@property (readonly) BOOL isTree;
@property (readonly, copy) NSArray<ECOutlineItem *> *items;
@property (readonly, copy) NSArray<ECOutlineNode *> *tree;
@property (readonly, copy) NSArray<ECOutlineRow *> *rows;
@property (readonly, copy) NSArray<NSString *> *columnTitles;	//!< リスト的列名 4 个（排序的列后面有「 *」）
@property (readonly, copy) NSString *clipText;	//!< 「コピー」的文字
@property (readonly) ECOutlineSort sort;
@property (readonly) NSInteger sortColumn;
@property (readonly) BOOL sortDescending;
@property (readonly) BOOL lineNumIsCRLF;		//!< 行番号は改行単位
- (instancetype)init NS_UNAVAILABLE;
//! ツリーの順序を変える（原版 SortTree）
- (void)sortTree:(ECOutlineSort)sort NS_SWIFT_NAME(sortTree(_:));
//! リストを並べ替える（原版 SortListView：0 行、1 桁、2 関数名、3 第 4 列）
- (void)sortRowsByColumn:(NSInteger)column descending:(BOOL)descending NS_SWIFT_NAME(sortRows(column:descending:));
//! 光标所在的项目（原版 GetFuncInfoIndex）。layoutLine・layoutColumn 是光标的排版位置 + 1。没有时 -1
- (NSInteger)itemAtLayoutLine:(NSInteger)layoutLine column:(NSInteger)layoutColumn NS_SWIFT_NAME(item(atLayoutLine:column:));
//! ツリー里这个项目的位置（从根开始的下标）。没有时空
- (NSArray<NSNumber *> *)nodePathForItem:(NSInteger)item NS_SWIFT_NAME(nodePath(forItem:));
@end

// ---------------------------------------------------------------------------
// Grep・Grep置換（第 43 步。sakura::core::GrepSession 等）
// ---------------------------------------------------------------------------

//! Grep 的条件（sakura::core::GrepOptions：原版 GrepInfo）
NS_SWIFT_NAME(GrepOptions)
@interface ECGrepOptions : NSObject
@property (copy) NSString *key;
@property (copy) NSString *replacement;
@property (copy) NSString *files;				//!< 対象ファイル（除外は PackGrepFiles で加えたもの）
@property (copy) NSString *folders;
@property BOOL regularExpression;
@property BOOL matchCase;
@property BOOL wholeWord;
@property BOOL subFolder;
@property ECEncoding charSet;
@property NSInteger outputStyle;				//!< 1 ノーマル、2 ファイル毎、3 結果のみ
@property NSInteger outputLineType;			//!< 0 該当部分、1 該当行、2 否該当行
@property BOOL fileOnly;
@property BOOL baseFolder;
@property BOOL separateFolder;
@property BOOL exceptFileRegexp;
@property BOOL header;
@property BOOL replace;
@property BOOL paste;
@property BOOL backup;
@property (copy, nullable) NSString *pasteText;	//!< 貼り付ける文字（剪贴板是空的时候 nil）
@end

//! 「編集中のテキストから検索」的文档（sakura::core::GrepSourceText）
NS_SWIFT_NAME(GrepSourceText)
@interface ECGrepSourceText : NSObject
@property uint64_t sourceID;
@property (copy) NSString *filePath;
@property (copy) NSString *windowLabel;
@property BOOL isGrep;
@property ECEncoding encoding;
@property (copy) NSArray<NSString *> *lines;		//!< 各行（包括换行符）
@end

NS_SWIFT_NAME(GrepResult)
@interface ECGrepResult : NSObject
@property (readonly) NSInteger hitCount;
@property (readonly) BOOL cancelled;
@property (readonly, copy) NSString *errorMessage;	//!< 空：没有错误
- (instancetype)init NS_UNAVAILABLE;
@end

/*!
	一次 Grep（sakura::core::GrepSession）。run 在别的线程调用；cancel、takeOutput、进度可以在任何线程调用
*/
NS_SWIFT_NAME(GrepSession)
@interface ECGrepSession : NSObject
- (instancetype)initWithOptions:(ECGrepOptions *)options sources:(NSArray<ECGrepSourceText *> *)sources NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
- (ECGrepResult *)run;
- (void)cancel;
@property BOOL realTimeView;
@property (readonly, getter=isRunning) BOOL running;
- (NSString *)takeOutput;
@property (readonly) NSInteger progressHitCount;
@property (readonly, copy) NSString *progressFile;
@property (readonly, copy) NSString *progressFolder;
@end

//! Grep 对话框的历史的种类（sakura::core::GrepHistory）
typedef NS_ENUM(NSInteger, ECGrepHistory) {
	ECGrepHistoryFile NS_SWIFT_NAME(file) = 0,
	ECGrepHistoryFolder NS_SWIFT_NAME(folder),
	ECGrepHistoryExcludeFile NS_SWIFT_NAME(excludeFile),
	ECGrepHistoryExcludeFolder NS_SWIFT_NAME(excludeFolder),
} NS_SWIFT_NAME(GrepHistory);

//! Grep 对话框的「OK」的检查（sakura::core::GrepDialogCheck）
NS_SWIFT_NAME(GrepDialogCheck)
@interface ECGrepDialogCheck : NSObject
@property (readonly, copy) NSString *error;
@property (readonly, copy) NSString *file;
@property (readonly, copy) NSString *folders;
- (instancetype)init NS_UNAVAILABLE;
@end

//! タグジャンプ 的目标（sakura::core::TagJumpTarget）
NS_SWIFT_NAME(TagJumpTarget)
@interface ECTagJumpTarget : NSObject
@property (readonly, copy) NSString *path;		//!< 「編集中のテキストから検索」的结果时是空
@property (readonly) BOOL hasSourceID;
@property (readonly) uint64_t sourceID;
@property (readonly) NSInteger line;				//!< 1 开始。0：没有指定
@property (readonly) NSInteger column;
- (instancetype)init NS_UNAVAILABLE;
@end

NS_SWIFT_NAME(GrepCore)
@interface ECGrep : NSObject
+ (NSArray<NSString *> *)historyOf:(ECGrepHistory)kind NS_SWIFT_NAME(history(_:));
+ (void)addHistory:(NSString *)text kind:(ECGrepHistory)kind NS_SWIFT_NAME(addHistory(_:kind:));
//! 打开对话框时的初始值：file、folder、excludeFile、excludeFolder（原版 CDlgGrep::DoModal）
+ (NSDictionary<NSString *, NSString *> *)dialogDefaults;
+ (NSString *)packFiles:(NSString *)file excludeFile:(NSString *)excludeFile excludeFolder:(NSString *)excludeFolder NS_SWIFT_NAME(packFiles(_:excludeFile:excludeFolder:));
+ (NSArray<NSString *> *)splitFolders:(NSString *)folders base:(NSString *)base NS_SWIFT_NAME(splitFolders(_:base:));
+ (NSString *)joinFolders:(NSArray<NSString *> *)folders NS_SWIFT_NAME(joinFolders(_:));
+ (nullable NSString *)foldersUp:(NSString *)folders base:(NSString *)base NS_SWIFT_NAME(foldersUp(_:base:));
+ (ECGrepDialogCheck *)checkDialogFile:(NSString *)file excludeFile:(NSString *)excludeFile excludeFolder:(NSString *)excludeFolder
	folders:(NSString *)folders base:(NSString *)base fromThisText:(BOOL)fromThisText
	NS_SWIFT_NAME(checkDialog(file:excludeFile:excludeFolder:folders:base:fromThisText:));
+ (NSString *)sourceToken:(uint64_t)sourceID NS_SWIFT_NAME(sourceToken(_:));
//! Grep 的结果的文档的タイプ別設定的番号（扩展名 grepout 的类型）
@property (class, readonly) NSInteger outputTypeIndex;
- (instancetype)init NS_UNAVAILABLE;
@end

// ----- ファイルツリー（第 43 步。sakura::core::FileTreeSetting 等）-----

typedef NS_ENUM(NSInteger, ECFileTreeItemType) {
	ECFileTreeItemTypeGrep NS_SWIFT_NAME(grep) = 0,
	ECFileTreeItemTypeFile NS_SWIFT_NAME(file) = 1,
	ECFileTreeItemTypeFolder NS_SWIFT_NAME(folder) = 2,
} NS_SWIFT_NAME(FileTreeItemType);

typedef NS_ENUM(NSInteger, ECFileTreeSettingFrom) {
	ECFileTreeSettingFromCommon NS_SWIFT_NAME(common) = 0,
	ECFileTreeSettingFromType NS_SWIFT_NAME(type) = 1,
	ECFileTreeSettingFromFile NS_SWIFT_NAME(file) = 2,
} NS_SWIFT_NAME(FileTreeSettingFrom);

//! 一个项目（sakura::core::FileTreeItem）
NS_SWIFT_NAME(FileTreeItem)
@interface ECFileTreeItem : NSObject <NSCopying>
@property ECFileTreeItemType type;
@property (copy) NSString *path;
@property (copy) NSString *label;
@property NSInteger depth;
@property (copy) NSString *file;			//!< 初始值 *.*
@property BOOL ignoreHidden;				//!< 初始值 YES
@property BOOL ignoreReadOnly;
@property BOOL ignoreSystem;
@end

//! 现在的设置（sakura::core::FileTreeSetting）
NS_SWIFT_NAME(FileTreeSetting)
@interface ECFileTreeSetting : NSObject
@property ECFileTreeSettingFrom origin;
@property ECFileTreeSettingFrom loadedFrom;
@property BOOL project;
@property (copy) NSString *defaultProjectIni;
@property (copy) NSString *loadedIni;
@property (copy) NSString *iniFolder;
@property (copy) NSArray<ECFileTreeItem *> *items;
@end

//! 树的一个根（sakura::core::FileTreeRoot）
NS_SWIFT_NAME(FileTreeRoot)
@interface ECFileTreeRoot : NSObject
@property (readonly) NSInteger itemIndex;
@property (readonly) ECFileTreeItemType type;
@property (readonly, copy) NSString *label;
@property (readonly, copy) NSString *path;
@property (readonly) NSInteger depth;
- (instancetype)init NS_UNAVAILABLE;
@end

//! 一个文件夹的内容（sakura::core::FileTreeListing）
NS_SWIFT_NAME(FileTreeListing)
@interface ECFileTreeListing : NSObject
@property (readonly) BOOL wildcardError;
@property (readonly, copy) NSArray<NSString *> *folders;
@property (readonly, copy) NSArray<NSString *> *files;
- (instancetype)init NS_UNAVAILABLE;
@end

NS_SWIFT_NAME(FileTreeCore)
@interface ECFileTree : NSObject
@property (class, readonly) NSInteger maxItems;
+ (ECFileTreeSetting *)loadSettingForType:(NSInteger)typeIndex folder:(NSString *)folder NS_SWIFT_NAME(load(typeIndex:folder:));
+ (BOOL)loadDefaultIni:(NSString *)path into:(ECFileTreeSetting *)setting NS_SWIFT_NAME(loadDefaultIni(_:into:));
+ (NSArray<ECFileTreeRoot *> *)rootsOf:(ECFileTreeSetting *)setting folder:(NSString *)folder NS_SWIFT_NAME(roots(_:folder:));
+ (ECFileTreeListing *)listItem:(ECFileTreeItem *)item folder:(NSString *)folder NS_SWIFT_NAME(list(_:folder:));
//! 返回错误的消息（空：成功）
+ (NSString *)saveSetting:(ECFileTreeSetting *)setting typeIndex:(NSInteger)typeIndex truncated:(BOOL *)truncated NS_SWIFT_NAME(save(_:typeIndex:truncated:));
+ (nullable NSArray<ECFileTreeItem *> *)importFromPath:(NSString *)path NS_SWIFT_NAME(importItems(path:));
+ (NSString *)exportItems:(NSArray<ECFileTreeItem *> *)items toPath:(NSString *)path NS_SWIFT_NAME(exportItems(_:path:));
- (instancetype)init NS_UNAVAILABLE;
@end

NS_SWIFT_NAME(EditorDocument)
@interface ECDocument : NSObject

//! 新文档（无题、空）。核心库没有启动时返回 nil
- (nullable instancetype)init NS_DESIGNATED_INITIALIZER;

// ----- 打开、保存 -----

//! 打开文件。encoding 用 ECEncodingAutoDetect 时自动识别
- (ECResult)openFileAtPath:(NSString *)path encoding:(ECEncoding)encoding NS_SWIFT_NAME(open(path:encoding:));
- (ECResult)openFileAtPath:(NSString *)path NS_SWIFT_NAME(open(path:));
/*!
	打开文件，用「最近使ったファイル」的历史（第 31 步）。打开时的编码与上次不同、并且共通设置
	「前回と異なる文字コードの時に問い合わせを行う」打开时调用 ask，返回 YES 用上次的编码。
	ask 为 nil 时与不问时相同（自动识别用上次的编码，指定时用指定的编码）。
	上面两个 open 也用历史（ask 为 nil）。
*/
- (ECResult)openFileAtPath:(NSString *)path encoding:(ECEncoding)encoding
	askUsePreviousEncoding:(nullable BOOL (NS_NOESCAPE ^)(ECEncoding current, ECEncoding previous))ask
	NS_SWIFT_NAME(open(path:encoding:askUsePreviousEncoding:));
//! 另存为。eol 为 ECEolNone 时不转换换行符
- (ECResult)saveToPath:(NSString *)path encoding:(ECEncoding)encoding bom:(BOOL)bom eol:(ECEol)eol NS_SWIFT_NAME(save(to:encoding:bom:eol:));
//! 用打开时的编码、BOM 另存为
- (ECResult)saveToPath:(NSString *)path NS_SWIFT_NAME(save(to:));
//! 覆盖保存（无题文档返回 ECResultInvalidArgument）
- (ECResult)save;
//! 閉じて(無題)（第 34 步）：内容、撤销、文件名都清除，变成新文档
- (void)closeToUntitled;
//! 打开时从历史恢复的位置（共通设置「カーソル位置を復元する」关掉时、历史里没有时是 nil）（第 31 步）
@property (readonly, nullable) ECRestoredView *restoredView;
//! 把现在的状态登记到「最近使ったファイル」（原版 CMruListener：保存后、关闭前）。新文件时什么也不做
- (void)addToRecentWithCaret:(ECPosition)caret viewTopLine:(NSInteger)viewTopLine NS_SWIFT_NAME(addToRecent(caret:viewTopLine:));
//! 用这些设置保存之前的检查（原版 CCodeChecker::OnCheckSave）。不改文档。eol 为 ECEolNone 时不转换换行符
- (ECSaveCheck *)checkSaveWithEncoding:(ECEncoding)encoding eol:(ECEol)eol NS_SWIFT_NAME(checkSave(encoding:eol:));

@property (readonly, copy) NSString *path;				//!< 无题时是空字符串
@property (readonly) ECEncoding encoding;
@property (readonly) BOOL hasBOM;
@property (readonly) NSInteger typeIndex;				//!< 类型别设置的编号
@property (readonly, copy) NSString *typeName;			//!< 类型别设置的名字（“テキスト”“C/C++” 等）
@property (readonly, getter=isModified) BOOL modified;
//! 文字コードセット指定（第 34 步）：下次保存用的编码和 BOM（不能加 BOM 的编码时 BOM 是 NO）
- (void)setEncoding:(ECEncoding)encoding bom:(BOOL)bom NS_SWIFT_NAME(setEncoding(_:bom:));
//! 文字コードセット指定改过打开（保存）时的编码或 BOM（新文件时 NO）
@property (readonly, getter=isEncodingChanged) BOOL encodingChanged;

// ----- 内容 -----

@property (readonly) NSInteger lineCount;
@property (readonly, copy) NSString *text;				//!< 全文（包括换行符）
- (NSString *)lineAtIndex:(NSInteger)line NS_SWIFT_NAME(line(at:));
- (NSString *)lineAtIndex:(NSInteger)line withEol:(BOOL)withEol NS_SWIFT_NAME(line(at:withEol:));
//! 一行的长度（不含换行符）。不取出文字（第 36 步：超长行）
- (NSInteger)lengthOfLineAtIndex:(NSInteger)line NS_SWIFT_NAME(lineLength(at:));
//! 文字或排版变了的次数（编辑、撤销、重新排版、打开时增加）。视图的缓存是否还有效（第 36 步）
@property (readonly) NSUInteger changeCount;
- (ECEol)eolOfLineAtIndex:(NSInteger)line NS_SWIFT_NAME(eol(ofLine:));
- (NSString *)textInRange:(ECRange)range NS_SWIFT_NAME(text(in:));
@property (readonly) ECPosition endPosition;
//! 全文（包括换行符）的长度（第 36 步。不做出全文）
@property (readonly) NSInteger textLength;
//! 位置 → 全文的下标
- (NSInteger)offsetOfPosition:(ECPosition)position NS_SWIFT_NAME(offset(of:));
//! 全文的下标 → 位置（落在换行符中间时取换行符之前）
- (ECPosition)positionAtOffset:(NSInteger)offset NS_SWIFT_NAME(position(atOffset:));

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

//! 次を検索（原版 Command_SEARCH_NEXT）：从选择的末尾（没有选择时从光标）往后找
- (ECSearchResult *)searchNext:(NSString *)key options:(ECSearchOptions)options view:(ECSearchView)view searchAll:(BOOL)searchAll NS_SWIFT_NAME(searchNext(_:options:view:searchAll:));
//! 前を検索（原版 Command_SEARCH_PREV）：从光标往前找
- (ECSearchResult *)searchPrev:(NSString *)key options:(ECSearchOptions)options view:(ECSearchView)view searchAll:(BOOL)searchAll NS_SWIFT_NAME(searchPrev(_:options:view:searchAll:));
//! 置換（原版 Command_REPLACE）：从选择的开头找下一个，换掉，再找下一个
- (ECSearchResult *)replaceNext:(NSString *)key with:(NSString *)replacement options:(ECReplaceOptions)options view:(ECSearchView)view NS_SWIFT_NAME(replaceNext(_:with:options:view:));
//! すべて置換（原版 Command_REPLACE_ALL）
- (ECSearchResult *)replaceAll:(NSString *)key with:(NSString *)replacement options:(ECReplaceOptions)options view:(ECSearchView)view NS_SWIFT_NAME(replaceAll(_:with:options:view:));
//! 指定行へジャンプ（原版 Command_JUMP）：跳转后的光标。文档是空的时返回 NO
- (BOOL)jumpPosition:(ECJumpOptions)options position:(ECPosition *)outPosition NS_SWIFT_NAME(jumpPosition(_:position:));
//! 这个位置的单词的范围（原版 WhereCurrentWord）。没有单词时返回 NO
- (BOOL)wordRangeAt:(ECPosition)position range:(ECRange *)outRange NS_SWIFT_NAME(wordRange(at:range:));

// ----- 光标移动的目标（第 34 步） -----

//! 単語の左端／右端に移動（原版 PrevOrNextWord）的目标。行内找不到时返回 NO
- (BOOL)wordMoveTargetFrom:(ECPosition)position left:(BOOL)left position:(ECPosition *)outPosition NS_SWIFT_NAME(wordMoveTarget(from:left:position:));
//! 前／次の段落へ 的目标逻辑行。不移动时 -1
- (NSInteger)paragraphTargetFromLine:(NSInteger)line next:(BOOL)next NS_SWIFT_NAME(paragraphTarget(fromLine:next:));
//! 前／次の変更行へ 的目标。找不到时返回 NO。wrapped：绕到了开头（末尾）
- (BOOL)modifiedLineTargetFrom:(ECPosition)position next:(BOOL)next position:(ECPosition *)outPosition wrapped:(BOOL *)outWrapped NS_SWIFT_NAME(modifiedLineTarget(from:next:position:wrapped:));
//! 逻辑行 line 的 [from, to) 里缩进之后第一个字的下标（行頭に移動 用）。只有缩进时是 from
- (NSInteger)indentEndInLine:(NSInteger)line from:(NSInteger)from to:(NSInteger)to NS_SWIFT_NAME(indentEnd(line:from:to:));

// ----- 模式（第 34 步） -----

//! 挿入モード（NO 是上書きモード）。新文档按共通設定
@property (nonatomic) BOOL insertMode;
//! 上書きモードでの入力：每个字先删掉光标处的一个字再插入（原版 DelCharForOverwrite）。作为撤销的一步
- (ECResult)overwriteText:(NSString *)text at:(ECPosition)position newCaret:(nullable ECPosition *)newCaret NS_SWIFT_NAME(overwrite(_:at:newCaret:));
//! 現在のウィンドウ幅で折り返し 的新的折り返し桁数（width 是文字区域的宽度）。不能改变时 -1
- (NSInteger)wrapWindowWidthColumnsForWidth:(NSInteger)width NS_SWIFT_NAME(wrapWindowWidthColumns(forWidth:));
//! 这一逻辑行里用「検索文字列」的颜色显示的部分
- (NSArray<ECSearchMark *> *)searchMarksInLine:(NSInteger)line key:(NSString *)key options:(ECSearchOptions)options NS_SWIFT_NAME(searchMarks(line:key:options:));
/*!
	这一逻辑行的语法颜色（第 33 步：原版的色分け。注释、字符串、关键字、数字、URL 等）。
	只有不是「テキスト」的部分，按位置排列，不包括换行符。颜色的设置用 color(for:)
*/
- (NSArray<ECSyntaxColorRun *> *)syntaxColorsInLine:(NSInteger)line NS_SWIFT_NAME(syntaxColors(line:));

// ----- 命令 -----

- (ECResult)executeCommand:(ECCommand)command NS_SWIFT_NAME(execute(_:));
- (BOOL)isCommandEnabled:(ECCommand)command NS_SWIFT_NAME(isEnabled(_:));
//! 菜单是否打勾（原版 IsFuncChecked：○○で開き直す、入力改行コード、挿入モード）
- (BOOL)isCommandChecked:(ECCommand)command NS_SWIFT_NAME(isChecked(_:));
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
/*!
	タイプ別設定的第 typeIndex 个改了（第 40 步，原版 PM_CHANGESETTING_TYPE）：这个文档的类型（或按文件名决定的类型）是它时
	按文件名重新决定类型、读新的设置、重新排版，返回 YES
*/
- (BOOL)applyTypeSettingChange:(NSInteger)typeIndex NS_SWIFT_NAME(applyTypeSettingChange(_:));
//! タイプ別設定一覧で顺序・个数变了：按 ID 找新的编号（类型被删了时按文件名重新决定、重新排版，返回 YES）
- (BOOL)applyTypeListChange;
//! タイプ別設定一覧 的「一時適用」（原版 F_CHANGETYPE）
- (BOOL)changeTypeTemporarily:(NSInteger)typeIndex NS_SWIFT_NAME(changeTypeTemporarily(_:));

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

// ----- 颜色（第 28 步） -----

//! 类型别设置的颜色
- (ECColorSetting)colorFor:(ECColorIndex)index NS_SWIFT_NAME(color(for:));
//! 这一逻辑行在上次保存（或打开）之后改过（行号用「変更行」的颜色）
- (BOOL)isLineModified:(NSInteger)line NS_SWIFT_NAME(isLineModified(_:));

// ----- 编辑命令（第 29 步。sakura::core::Document 的同名函数，与原版 CEditView、CViewCommander 相同） -----

@property (readonly) ECEditSettings editSettings;
//! 复制普通选择范围的文字（GetSelectedData）
- (NSString *)copyTextInRange:(ECRange)range NS_SWIFT_NAME(copyText(in:));
//! 复制矩形范围的文字：每行后面加 CRLF
- (NSString *)boxText:(ECBoxRange)box NS_SWIFT_NAME(boxText(_:));
//! 没有选择时复制的排版行（CopyCurLine）
- (NSString *)copyTextOfLayoutLine:(NSInteger)line NS_SWIFT_NAME(copyText(ofLayoutLine:));
//! 在排版位置插入（行末之后先填空白）。返回插入的文字之后的排版位置
- (ECLayoutPosition)insertText:(NSString *)text atLayout:(ECLayoutPosition)position NS_SWIFT_NAME(insert(_:atLayout:));
//! 删除矩形范围的文字。返回之后的光标
- (ECPosition)deleteBox:(ECBoxRange)box NS_SWIFT_NAME(deleteBox(_:));
//! 矩形贴付（Command_PASTEBOX）
- (void)pasteBox:(NSString *)text at:(ECLayoutPosition)position NS_SWIFT_NAME(pasteBox(_:at:));
//! 矩形选择中的输入、缩进（Command_INDENT）。返回之后的矩形，caret 是之后的光标
- (ECBoxRange)indentBox:(ECBoxRange)box text:(NSString *)text kind:(ECIndentKind)kind caret:(nullable ECPosition *)caret NS_SWIFT_NAME(indentBox(_:text:kind:caret:));
//! 多行选择的缩进：排版行 top～bottom（不包括 bottom）。返回之后的 bottom
- (NSInteger)indentLinesFrom:(NSInteger)top to:(NSInteger)bottom text:(NSString *)text NS_SWIFT_NAME(indentLines(from:to:text:));
//! 多行选择的逆缩进。返回之后的 bottom
- (NSInteger)unindentLinesFrom:(NSInteger)top to:(NSInteger)bottom character:(unichar)character NS_SWIFT_NAME(unindentLines(from:to:character:));
//! TAB 键输入的文字（「スペースの挿入」时是空白）
- (NSString *)tabTextAt:(NSInteger)x NS_SWIFT_NAME(tabText(at:));
//! 改行时的オートインデント
- (NSString *)autoIndentTextAt:(ECPosition)caret NS_SWIFT_NAME(autoIndentText(at:));
//! 把换行符都换成输入用的换行符
- (NSString *)convertEolToNewLine:(NSString *)text NS_SWIFT_NAME(convertEolToNewLine(_:));
//! 删除一个排版行。返回之后的光标
- (ECPosition)deleteLayoutLine:(NSInteger)line x:(NSInteger)x NS_SWIFT_NAME(deleteLayoutLine(_:x:));

// ----- アウトライン解析（第 42 步） -----

//! アウトライン解析（ECOutlineTypeDefault 时用类型别设置的方法）。同时设置関数リストマーク
- (ECOutlineResult *)analyzeOutline:(ECOutlineType)type NS_SWIFT_NAME(analyzeOutline(_:));
//! 解析方法（Default 时是类型别设置的方法，C/C++ 时按扩展名）
- (ECOutlineType)resolveOutlineType:(ECOutlineType)type NS_SWIFT_NAME(resolveOutlineType(_:));
/*!
	次の関数リストマークへ／前の関数リストマークへ 的目标行（逻辑行）。找不到时 -1。
	searchAll 是共通設定「先頭（末尾）から再検索する」。wrapped：绕回去了
*/
- (NSInteger)findFuncListMarkFromLine:(NSInteger)line forward:(BOOL)forward searchAll:(BOOL)searchAll
	wrapped:(nullable BOOL *)wrapped NS_SWIFT_NAME(findFuncListMark(from:forward:searchAll:wrapped:));
//! この行に関数リストマークがあるか
- (BOOL)hasFuncListMark:(NSInteger)line NS_SWIFT_NAME(hasFuncListMark(_:));

// ----- Grep・タグジャンプ（第 43 步） -----

//! 逻辑行 line 的タグジャンプ 的目标（Grep 的结果、「ファイル名(行,桁)」的消息）。没有时 nil
- (nullable ECTagJumpTarget *)tagJumpAtLine:(NSInteger)line NS_SWIFT_NAME(tagJump(at:));
//! 加到最后，不记入撤销（Grep 的结果，原版 Command_ADDTAIL）。返回加入之后的位置
- (ECPosition)appendWithoutUndo:(NSString *)text NS_SWIFT_NAME(appendWithoutUndo(_:));
//! 当作没有修改（Grep 结束时，原版 SetModified(false,false)）
- (void)setUnmodified;

@end

NS_ASSUME_NONNULL_END
