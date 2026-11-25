/*! @file
	@brief Grep・Grep置換（计划第 43 步）的测试

	原版的 src/test/cpp/tests1/test-grep-cmdline.cpp（-GREPMODE 的命令行 → CGrepAgent::DoGrep 的测试）移到 Mac 版。
	原版的测试用编辑窗口、标准输出（-GOPT=U）、消息框的替身（MockUser32）、剪贴板、Windows 的文件锁，
	Mac 版换成核心库的接口 GrepSession（App 用的同一个）：
	- 结果的文字：GrepSession::TakeOutput（原版是 Grep 窗口的文档或标准输出）
	- 消息框：GrepResult::errorMessage
	- 剪贴板：GrepOptions::pasteText
	- 「編集中のテキストから検索」(:HWND:)：GrepSourceText（原版是别的窗口）
	- 打不开的文件：chmod 000（原版是不共享地打开）；删不掉的文件：chflags uchg（原版是共享读取地打开）
	- 路径的分隔是 '/'
	测试的名字与原版相同，内容尽量照原版。中断和进度、结果的输出目标的测试与原版相同，直接给 DoGrep 替身。
	原版有、Mac 版没有的：-GOPT=U（标准输出）、不加 X 时改变当前文件夹、OnBeforeClose・OnAfterSave（界面层负责）、8.3 形式的短名字。
*/
/*
	Copyright (C) 2026, Sakura Editor Organization

	SPDX-License-Identifier: Zlib
*/
#include "pch.h"

#include "sakura_core/SakuraCore.h"
#include "mac-grep-temp-folder.hpp"

#include "agent/CGrepAgent.h"
#include "basis/GrepInfo.h"
#include "charset/CCodeBase.h"
#include "charset/CCodeFactory.h"
#include "env/CDocTypeManager.h"
#include "mem/CMemory.h"
#include "mem/CNativeW.h"
#include "types/CType.h"
#include "util/string_ex.h"
#include "view/colors/EColorIndexType.h"
#include "CSelectLang.h"
#include "sakura_rc.h"

#include <algorithm>
#include <chrono>
#include <cstdlib>
#include <filesystem>
#include <format>
#include <fstream>
#include <optional>
#include <sstream>
#include <string>
#include <thread>
#include <vector>

#include <sys/stat.h>
#include <unistd.h>

using namespace sakura::core;

namespace grep_test {

namespace fs = std::filesystem;
using sakura::core::Text;

//! UTF-16 → UTF-8（失敗したときの表示用）
inline std::string U8(std::u16string_view text)
{
	return sakura::u16::to_utf8(text);
}

//! 部分文字列を含むか
inline bool Contains(std::u16string_view text, std::u16string_view part)
{
	return text.find(part) != std::u16string_view::npos;
}

//! 文字列をこの文字コードのバイト列にする（原版は Windows の変換。Mac 版はエディタ自身の変換）
inline std::string Encode(std::u16string_view text, ECodeType code)
{
	std::unique_ptr<CCodeBase> pcCodeBase(CCodeFactory::CreateCodeBase(code, 0));
	CNativeW src(text.data(), text.size());
	CMemory dst;
	pcCodeBase->UnicodeToCode(src, &dst);
	return std::string(reinterpret_cast<const char*>(dst.GetRawPtr()), size_t(dst.GetRawLength()));
}

//! 文字列を UTF-16 のバイト列にする
inline std::string EncodeUtf16(std::u16string_view text, bool bigEndian, bool withBom)
{
	std::string bytes;
	if (withBom) {
		bytes += bigEndian ? "\xFE\xFF" : "\xFF\xFE";
	}
	for (const char16_t ch : text) {
		const auto lo = char(ch & 0xFF);
		const auto hi = char((ch >> 8) & 0xFF);
		bytes += bigEndian ? hi : lo;
		bytes += bigEndian ? lo : hi;
	}
	return bytes;
}

constexpr std::string_view Utf8Bom = "\xEF\xBB\xBF";

//! 文字コードの判別に使う日本語の文章（3 行。各行に「テスト」が 1 つ）
inline Text JapaneseLines()
{
	Text text;
	for (int i = 0; i < 3; ++i) {
		text += u"テストの文章です。日本語のファイルを検索します。\r\n";
	}
	return text;
}

//! text の中で part を含む最初の行（見つからなければ空）
inline Text LineContaining(const Text& text, std::u16string_view part)
{
	const auto pos = text.find(part);
	if (pos == Text::npos) {
		return {};
	}
	const auto lineHead = text.rfind(u'\n', pos);
	const auto begin = (lineHead == Text::npos) ? 0 : lineHead + 1;
	const auto end = text.find(u'\n', pos);
	return text.substr(begin, (end == Text::npos) ? Text::npos : end - begin);
}

inline Text CodeBracket(ECodeType code)
{
	return Text(CCodeTypeName(code).Bracket());
}

//! 文字列リソースの「%s」「%d」より前の部分
inline Text ResourcePrefix(UINT id)
{
	Text text = LS(id);
	if (const auto pos = text.find(u'%'); pos != Text::npos) {
		text.resize(pos);
	}
	return text;
}

//! 「%d 個が検索されました」の文言
inline Text MatchCountText(int count)
{
	Text text = LS(STR_GREP_MATCH_COUNT);
	if (const auto pos = text.find(u"%d"); pos != Text::npos) {
		text.replace(pos, 2, sakura::u16::from_utf8(std::to_string(count)));
	}
	return text;
}

//! 行に分ける（行末の CR は取る）
inline std::vector<Text> Lines(const Text& text)
{
	std::vector<Text> lines;
	size_t begin = 0;
	while (begin < text.size()) {
		size_t end = text.find(u'\n', begin);
		if (end == Text::npos) end = text.size();
		Text line = text.substr(begin, end - begin);
		if (!line.empty() && line.back() == u'\r') line.pop_back();
		lines.push_back(line);
		begin = end + 1;
	}
	return lines;
}

//! 原版の -GREPR・-GCODE・クリップボード
struct Extra {
	std::optional<Text> replace;		//!< -GREPR="..."
	std::optional<int> code;			//!< -GCODE=...
	std::optional<Text> clipboard;		//!< クリップボードの内容（-GOPT=C のとき）
};

/*!
	原版 CCommandLine::ParseCommandLine の -GOPT の解析と同じく、GrepOptions を作る
*/
inline GrepOptions MakeOptions(const Text& key, const Text& file, const Text& folders, std::u16string_view opt, const Extra& extra = {})
{
	GrepOptions o;
	o.key = key;
	o.files = file;
	o.folders = folders;
	for (const char16_t c : opt) {
		switch (c) {
		case u'H': o.header = false; break;
		case u'S': o.subFolder = true; break;
		case u'L': o.search.matchCase = true; break;
		case u'R': o.search.regularExpression = true; break;
		case u'K': o.charSet = encoding::AutoDetect; break;
		case u'P': o.outputLineType = 1; break;
		case u'N': o.outputLineType = 2; break;
		case u'W': o.search.wholeWord = true; break;
		case u'1': o.outputStyle = 1; break;
		case u'2': o.outputStyle = 2; break;
		case u'3': o.outputStyle = 3; break;
		case u'F': o.fileOnly = true; break;
		case u'B': o.baseFolder = true; break;
		case u'D': o.separateFolder = true; break;
		case u'C': o.paste = true; break;
		case u'O': o.backup = true; break;
		case u'E': o.exceptFileRegexp = true; break;
		default: break;	// X（カレントディレクトリを移動しない）：Mac 版はいつも移動しない
		}
	}
	if (extra.replace) {
		o.replace = true;
		o.replacement = *extra.replace;
	}
	if (extra.code) {
		o.charSet = *extra.code;
	}
	o.pasteText = extra.clipboard;
	return o;
}

//! GrepOptions → GrepInfo（GrepSession::Run と同じ。DoGrep に替身を直接渡すテスト用）
inline GrepInfo ToGrepInfo(const GrepOptions& o)
{
	GrepInfo gi;
	gi.cmGrepKey.SetString(o.key.c_str(), o.key.length());
	gi.cmGrepRep.SetString(o.replacement.c_str(), o.replacement.length());
	gi.cmGrepFile.SetString(o.files.c_str(), o.files.length());
	gi.cmGrepFolder.SetString(o.folders.c_str(), o.folders.length());
	gi.sGrepSearchOption.bRegularExp = o.search.regularExpression;
	gi.sGrepSearchOption.bLoHiCase = o.search.matchCase;
	gi.sGrepSearchOption.bWordOnly = o.search.wholeWord;
	gi.bGrepCurFolder = true;
	gi.bGrepHeader = o.header;
	gi.bGrepSubFolder = o.subFolder;
	gi.nGrepCharSet = ECodeType(o.charSet);
	gi.nGrepOutputStyle = o.outputStyle;
	gi.nGrepOutputLineType = o.outputLineType;
	gi.bGrepOutputFileOnly = o.fileOnly;
	gi.bGrepOutputBaseFolder = o.baseFolder;
	gi.bGrepSeparateFolder = o.separateFolder;
	gi.bGrepReplace = o.replace;
	gi.bGrepPaste = o.paste;
	gi.bGrepBackup = o.backup;
	gi.bGrepExceptFileRegexp = o.exceptFileRegexp;
	return gi;
}

/*!
	@brief 結果の文書の替身（DoGrep に直接渡すテスト用。GrepSession の中のものと同じ働き）
*/
class TestResultView : public IGrepResultView {
public:
	TestResultView()
	{
		(void)CDocTypeManager().GetTypeConfig(CTypeConfig(GrepOutputTypeIndex()), type);
	}
	const STypeConfig& GetDocumentAttribute() const override { return type; }
	bool GetPasteText(CNativeW& cmemText) override
	{
		if (!clipboard) return false;
		cmemText.SetString(clipboard->c_str(), clipboard->length());
		return true;
	}
	void ErrorMessage(const WCHAR* pszMessage) override { messages.emplace_back(pszMessage); }
	IGrepSourceDoc* FindSourceDoc(const WCHAR*) override { return nullptr; }

	STypeConfig type;
	std::optional<Text> clipboard;
	std::vector<Text> messages;
};

/*!
	@brief Grep のテストの共通基盤（原版 GrepTestSuite）

	原版は編集ウィンドウの文書に結果を出す。Mac 版は GrepSession の結果の文字をつないで「文書」にする。
*/
struct GrepTestSuite : public ::testing::Test {
	static void SetUpTestSuite() { ASSERT_TRUE(Startup()); }
	static void TearDownTestSuite() { Shutdown(false); }

	void TearDown() override
	{
		if (HasFailure()) {
			std::printf("----- document -----\n%s\n--------------------\n", U8(document).c_str());
		}
	}

	//! 文書を空に戻す
	void ResetDocument() { document.clear(); }
	const Text& GetDocumentText() const { return document; }

	//! GrepSession で実行し、結果を文書に足す
	DWORD RunGrep(const GrepOptions& options, std::vector<GrepSourceText> sources = {}, bool realTime = false)
	{
		GrepSession session(options, std::move(sources));
		session.SetRealTimeView(realTime);
		const GrepResult result = session.Run();
		document += session.TakeOutput();
		lastError = result.errorMessage;
		lastCancelled = result.cancelled;
		if (!result.errorMessage.empty()) {
			messages.push_back(result.errorMessage);
		}
		return DWORD(result.hitCount);
	}

	Text document;
	Text lastError;
	bool lastCancelled = false;
	std::vector<Text> messages;		//!< 出たメッセージボックス（原版 MockUser32 の MessageBoxExW）
};

/*!
	@brief コマンドライン(-GREPMODE)の経路のテスト（原版 GrepCommandLineTest）
*/
struct GrepCommandLineTest : public GrepTestSuite {
	TempFolder folder;

	/*!
		基本のテストデータ

		| ファイル | HIT の数 | HIT を含む行 | HIT を含まない行 |
		|---|---|---|---|
		| a.txt | 3 | 2 | 1 |
		| b.txt | 0 | 0 | 1 |
		| c.log | 1(対象外) | | |
		| sub/d.txt | 1 | 1 | 0 |
	*/
	void AddBasicFiles() const
	{
		folder.AddFile(u"a.txt", "HIT x HIT\r\nnone\r\nHIT\r\n");
		folder.AddFile(u"b.txt", "none\r\n");
		folder.AddFile(u"c.log", "HIT\r\n");
		folder.AddFile(u"sub/d.txt", "HIT\r\n");
	}

	GrepOptions Options(const Text& key, const Text& file, std::u16string_view opt, const Extra& extra = {}) const
	{
		return MakeOptions(key, file, folder.PathText(), opt, extra);
	}

	//! Grep を実行する（原版 -GREPMODE -GKEY -GFILE -GFOLDER=テストのフォルダー -GOPT）
	DWORD Grep(const Text& key, const Text& file, std::u16string_view opt, const Extra& extra = {})
	{
		return RunGrep(Options(key, file, opt, extra));
	}
};

// ---------------------------------------------------------------------------
// 検索条件
// ---------------------------------------------------------------------------

//! 既定(該当部分): 一致した箇所ごとに数える。サブフォルダーは探さない
TEST_F(GrepCommandLineTest, CountsEachMatch)
{
	AddBasicFiles();
	EXPECT_THAT(Grep(u"HIT", u"*.txt", u"X"), Eq(3u));
	const auto text = GetDocumentText();
	EXPECT_THAT(Contains(text, u"a.txt"), IsTrue());
	EXPECT_THAT(Contains(text, u"d.txt"), IsFalse());
	EXPECT_THAT(Contains(text, u"c.log"), IsFalse());
	EXPECT_THAT(Contains(text, MatchCountText(3)), IsTrue());
}

//! S: サブフォルダーも探す
TEST_F(GrepCommandLineTest, SubFolder)
{
	AddBasicFiles();
	EXPECT_THAT(Grep(u"HIT", u"*.txt", u"XS"), Eq(4u));
	EXPECT_THAT(Contains(GetDocumentText(), u"d.txt"), IsTrue());
}

//! P: 行単位で数える
TEST_F(GrepCommandLineTest, OutputLine)
{
	AddBasicFiles();
	EXPECT_THAT(Grep(u"HIT", u"*.txt", u"XSP"), Eq(3u));
}

//! N: 一致しなかった行を数える
TEST_F(GrepCommandLineTest, OutputNoHitLine)
{
	AddBasicFiles();
	EXPECT_THAT(Grep(u"HIT", u"*.txt", u"XSN"), Eq(2u));
	EXPECT_THAT(Contains(GetDocumentText(), u"none"), IsTrue());
}

//! F: ファイルごとに最初の 1 件だけ
TEST_F(GrepCommandLineTest, FileOnly)
{
	AddBasicFiles();
	EXPECT_THAT(Grep(u"HIT", u"*.txt", u"XSF"), Eq(2u));
}

//! L: 英大文字小文字を区別する
TEST_F(GrepCommandLineTest, CaseSensitive)
{
	AddBasicFiles();
	EXPECT_THAT(Grep(u"hit", u"*.txt", u"X"), Eq(3u));
	ResetDocument();
	EXPECT_THAT(Grep(u"hit", u"*.txt", u"XL"), Eq(0u));
}

//! W: 単語単位
TEST_F(GrepCommandLineTest, WordOnly)
{
	folder.AddFile(u"w.txt", "HIT HITS xHIT HIT.\r\n");
	EXPECT_THAT(Grep(u"HIT", u"*.txt", u"X"), Eq(4u));
	ResetDocument();
	EXPECT_THAT(Grep(u"HIT", u"*.txt", u"XW"), Eq(2u));
}

//! R: 正規表現(該当部分・行単位・否該当行)
TEST_F(GrepCommandLineTest, RegularExpression)
{
	AddBasicFiles();
	EXPECT_THAT(Grep(u"H.T", u"*.txt", u"XR"), Eq(3u));
	ResetDocument();
	EXPECT_THAT(Grep(u"H.T", u"*.txt", u"XRP"), Eq(2u));
	ResetDocument();
	EXPECT_THAT(Grep(u"H.T", u"*.txt", u"XRN"), Eq(2u));
}

//! R: 正しくない正規表現では何もしない(CSearchStringPattern::SetPattern() はメッセージを出さない)
TEST_F(GrepCommandLineTest, InvalidRegularExpression)
{
	AddBasicFiles();
	EXPECT_THAT(Grep(u"(", u"*.txt", u"XR"), Eq(0u));
	EXPECT_THAT(Contains(GetDocumentText(), u"a.txt"), IsFalse());
}

//! 空の検索キー: ファイル名の一覧になる
TEST_F(GrepCommandLineTest, EmptyKeyListsFiles)
{
	AddBasicFiles();
	Grep(u"", u"*.txt", u"XS");
	const auto text = GetDocumentText();
	EXPECT_THAT(Contains(text, u"a.txt"), IsTrue());
	EXPECT_THAT(Contains(text, u"b.txt"), IsTrue());
	EXPECT_THAT(Contains(text, u"d.txt"), IsTrue());
	EXPECT_THAT(Contains(text, u"c.log"), IsFalse());
}

// ---------------------------------------------------------------------------
// 出力形式
// ---------------------------------------------------------------------------

//! 1 / 2 / 3: 出力形式が変わってもヒット数は同じ
TEST_F(GrepCommandLineTest, OutputStyles)
{
	AddBasicFiles();
	for (const auto opt : { u"XS1", u"XS2", u"XS3", u"XS2B", u"XS2D", u"XS1BD", u"XS3BD" }) {
		ResetDocument();
		EXPECT_THAT(Grep(u"HIT", u"*.txt", opt), Eq(4u)) << U8(opt);
	}
}

//! 空の検索キー: ベースフォルダー名・フォルダー名の見出しは、出力形式3(結果のみ)でも出す
TEST_F(GrepCommandLineTest, EmptyKeyFolderHeadings)
{
	AddBasicFiles();
	const auto headings = [this](std::u16string_view opt) {
		ResetDocument();
		Grep(u"", u"*.txt", opt);
		std::vector<Text> result;
		for (const auto& line : Lines(GetDocumentText())) {
			if (!line.starts_with(u"◎") && !line.starts_with(u"■")) {
				continue;
			}
			Text kind = line.substr(0, 1);
			if (1 < line.size()) {
				kind += line.ends_with(u"sub\"") ? u"sub" : u"base";
			}
			result.push_back(kind);
		}
		return result;
	};
	EXPECT_THAT(headings(u"XS1B"), ::testing::ElementsAre(u"■base"));
	EXPECT_THAT(headings(u"XS3B"), ::testing::ElementsAre(u"■base"));
	EXPECT_THAT(headings(u"XS1BD"), ::testing::ElementsAre(u"◎base", u"■", u"■sub"));
	EXPECT_THAT(headings(u"XS3BD"), ::testing::ElementsAre(u"◎base", u"■", u"■sub"));
	EXPECT_THAT(headings(u"XS3D"), ::testing::ElementsAre(u"■base", u"■sub"));
}

//! 出力形式と行単位・ファイル名のみの組み合わせ
TEST_F(GrepCommandLineTest, OutputStylesWithEmptyKey)
{
	AddBasicFiles();
	for (const auto opt : { u"XS1", u"XS2", u"XS3", u"XS2B", u"XS2D", u"XS3BD" }) {
		ResetDocument();
		Grep(u"", u"*.txt", opt);
		EXPECT_THAT(Contains(GetDocumentText(), u"d.txt"), IsTrue()) << U8(opt);
	}
}

//! H: ヘッダー・フッターを出さない
TEST_F(GrepCommandLineTest, NoHeader)
{
	AddBasicFiles();
	Grep(u"HIT", u"*.txt", u"X");
	EXPECT_THAT(Contains(GetDocumentText(), LS(STR_GREP_EXCLUDE_FILE)), IsTrue());
	ResetDocument();
	Grep(u"HIT", u"*.txt", u"XH");
	const auto text = GetDocumentText();
	EXPECT_THAT(Contains(text, LS(STR_GREP_EXCLUDE_FILE)), IsFalse());
	EXPECT_THAT(Contains(text, MatchCountText(3)), IsFalse());
	EXPECT_THAT(Contains(text, u"a.txt"), IsTrue());
}

//! 10 件ごとにまとめて出力する経路(同じファイルで 12 件)
TEST_F(GrepCommandLineTest, ManyHits)
{
	std::string lines;
	for (int i = 0; i < 12; ++i) {
		lines += "HIT\r\n";
	}
	folder.AddFile(u"many.txt", lines);
	EXPECT_THAT(Grep(u"HIT", u"*.txt", u"XP"), Eq(12u));
}

//! リアルタイム表示: 結果を早めに出す経路を通っても、件数と結果は変わらない
TEST_F(GrepCommandLineTest, RealTimeView)
{
	AddBasicFiles();
	const auto hitCount = RunGrep(Options(u"HIT", u"*.txt", u"XS"), {}, true);
	EXPECT_THAT(hitCount, Eq(4u));
	EXPECT_THAT(Contains(GetDocumentText(), u"d.txt"), IsTrue());
}

// ---------------------------------------------------------------------------
// 対象ファイル・フォルダー
// ---------------------------------------------------------------------------

//! 除外ファイル・除外フォルダー
TEST_F(GrepCommandLineTest, ExcludeFileAndFolder)
{
	AddBasicFiles();
	EXPECT_THAT(Grep(u"HIT", u"*.txt;!a.txt", u"XS"), Eq(1u));
	ResetDocument();
	EXPECT_THAT(Grep(u"HIT", u"*.txt;#sub", u"XS"), Eq(3u));
}

//! 「,」を含む除外(ダイアログが組み立てる形 `#"obj,old";!"a,b.txt"`)
TEST_F(GrepCommandLineTest, ExcludePatternsWithComma)
{
	for (const auto name : { u"a,b.txt", u"b.txt", u"keep.txt", u"obj,old/x.txt", u"obj/x.txt", u"old/x.txt" }) {
		folder.AddFile(name, "HIT\r\n");
	}
	EXPECT_THAT(Grep(u"HIT", u"*.txt;#\"obj,old\";!\"a,b.txt\"", u"XS"), Eq(4u));
	const auto text = GetDocumentText();
	EXPECT_THAT(LineContaining(text, u"a,b.txt(").empty(), IsTrue());
	EXPECT_THAT(LineContaining(text, u"obj,old/x.txt(").empty(), IsTrue());
	EXPECT_THAT(LineContaining(text, u"/obj/x.txt(").empty(), IsFalse());
}

//! 複数のフォルダー(; 区切り)と、; を含むフォルダー名(引用符付き)
TEST_F(GrepCommandLineTest, MultipleFolders)
{
	folder.AddFile(u"p/x.txt", "HIT\r\n");
	folder.AddFile(u"q;r/y.txt", "HIT\r\n");
	const auto folders = folder.PathOf(u"p") + u";\"" + folder.PathOf(u"q;r") + u"\"";
	EXPECT_THAT(RunGrep(MakeOptions(u"HIT", u"*.txt", folders, u"X")), Eq(2u));
}

//! 存在しないフォルダーを指定すると、メッセージを出して検索しない(Issue #2707)
TEST_F(GrepCommandLineTest, NonexistentFolder)
{
	AddBasicFiles();
	const auto before = fs::current_path();
	EXPECT_THAT(RunGrep(MakeOptions(u"HIT", u"*.txt", folder.PathOf(u"none"), u"X")), Eq(0u));
	EXPECT_THAT(GetDocumentText().empty(), IsTrue());
	EXPECT_THAT(messages, ::testing::ElementsAre(Text(LS(STR_DLGGREP5))));
	EXPECT_THAT(fs::equivalent(fs::current_path(), before), IsTrue());
}

//! フォルダーの指定に 1 つでも存在しないもの(またはフォルダーでないもの)があれば、全体を検索しない
TEST_F(GrepCommandLineTest, InvalidFolderStopsBeforeSearch)
{
	AddBasicFiles();
	const auto base = folder.PathText();
	const auto none = folder.PathOf(u"none");
	const auto file = folder.PathOf(u"a.txt");
	const std::vector<Text> lists{ none + u";" + base, base + u";" + none, file };
	for (const auto& list : lists) {
		ResetDocument();
		EXPECT_THAT(RunGrep(MakeOptions(u"HIT", u"*.txt", list, u"X")), Eq(0u));
		EXPECT_THAT(GetDocumentText().empty(), IsTrue());
		EXPECT_THAT(lastError, Eq(Text(LS(STR_DLGGREP5))));
	}
}

//! Grep 置換: フォルダーに存在しないものがあれば、ファイルを書き換える前に止まる
TEST_F(GrepCommandLineTest, InvalidFolderDoesNotReplace)
{
	AddBasicFiles();
	const auto list = folder.PathText() + u";" + folder.PathOf(u"none");
	EXPECT_THAT(RunGrep(MakeOptions(u"HIT", u"a.txt", list, u"X", { .replace = u"REP" })), Eq(0u));
	EXPECT_THAT(lastError, Eq(Text(LS(STR_DLGGREP5))));
	EXPECT_THAT(folder.ReadFile(u"a.txt"), Eq(std::string("HIT x HIT\r\nnone\r\nHIT\r\n")));
	EXPECT_THAT(folder.Exists(u"a.txt.skrnew"), IsFalse());
}

//! 末尾に / が付いた実在するフォルダーは弾かない（原版は末尾の \）
TEST_F(GrepCommandLineTest, FolderWithTrailingBackslash)
{
	AddBasicFiles();
	EXPECT_THAT(RunGrep(MakeOptions(u"HIT", u"*.txt", folder.PathText() + u"/", u"X")), Eq(3u));
}

//! ファイル指定の誤り: フォルダー部分のワイルドカード、絶対パスの検索対象
TEST_F(GrepCommandLineTest, InvalidFileKeys)
{
	AddBasicFiles();
	EXPECT_THAT(Grep(u"HIT", u"sub*/a.txt", u"X"), Eq(0u));
	EXPECT_THAT(lastError, Eq(Text(LS(STR_GREP_ERR_ENUMKEYS1))));
	ResetDocument();
	EXPECT_THAT(Grep(u"HIT", u"/x/*.txt", u"X"), Eq(0u));
	EXPECT_THAT(lastError, Eq(Text(LS(STR_GREP_ERR_ENUMKEYS2))));
	EXPECT_THAT(messages.size(), Eq(2u));
}

//! 開けないファイルはメッセージを結果に出して続ける（原版は共有しないで開いたファイル。Mac 版は読む権限の無いファイル）
TEST_F(GrepCommandLineTest, FileOpenError)
{
	AddBasicFiles();
	ASSERT_THAT(::chmod((folder.Path().fs() / "a.txt").c_str(), 0), Eq(0));
	EXPECT_THAT(Grep(u"HIT", u"*.txt", u"XS"), Eq(1u));
	EXPECT_THAT(Contains(GetDocumentText(), ResourcePrefix(STR_GREP_ERR_FILEOPEN)), IsTrue());
}

// ---------------------------------------------------------------------------
// 文字コード
// ---------------------------------------------------------------------------

//! K(自動判別): SJIS と UTF-8 の両方で日本語が見つかる
TEST_F(GrepCommandLineTest, CharsetAutoDetect)
{
	folder.AddFile(u"sjis.txt", "\x83\x65\x83\x58\x83\x67\x82\xCC\x95\xB6\x8F\xCD\x82\xC5\x82\xB7\x81\x42\x93\xFA\x96\x7B\x8C\xEA\x82\xCC\x83\x74\x83\x40\x83\x43\x83\x8B\r\n");
	folder.AddFile(u"utf8.txt", "\xE3\x83\x86\xE3\x82\xB9\xE3\x83\x88\xE3\x81\xAE\xE6\x96\x87\xE7\xAB\xA0\xE3\x81\xA7\xE3\x81\x99\xE3\x80\x82\xE6\x97\xA5\xE6\x9C\xAC\xE8\xAA\x9E\xE3\x81\xAE\xE3\x83\x95\xE3\x82\xA1\xE3\x82\xA4\xE3\x83\xAB\r\n");
	EXPECT_THAT(Grep(u"テスト", u"*.txt", u"XK"), Eq(2u));
}

//! -GCODE で文字コードを固定する(UTF-8 固定なら SJIS のファイルは見つからない)
TEST_F(GrepCommandLineTest, CharsetFixed)
{
	folder.AddFile(u"utf8.txt", "\xE3\x83\x86\xE3\x82\xB9\xE3\x83\x88\r\n");
	folder.AddFile(u"sjis.txt", "\x83\x65\x83\x58\x83\x67\r\n");
	EXPECT_THAT(Grep(u"テスト", u"*.txt", u"X", { .code = int(CODE_UTF8) }), Eq(1u));
}

// ---------------------------------------------------------------------------
// Grep 置換
// ---------------------------------------------------------------------------

//! 置換: ファイルが書き換わる
TEST_F(GrepCommandLineTest, Replace)
{
	AddBasicFiles();
	Grep(u"HIT", u"a.txt", u"X", { .replace = u"REP" });
	EXPECT_THAT(folder.ReadFile(u"a.txt"), Eq("REP x REP\r\nnone\r\nREP\r\n"));
	EXPECT_THAT(folder.Exists(u"a.txt.skrold"), IsFalse());
	EXPECT_THAT(folder.Exists(u"a.txt.skrnew"), IsFalse());
}

//! 置換: 一致しないファイルは書き換えない
TEST_F(GrepCommandLineTest, ReplaceNoHitKeepsFile)
{
	AddBasicFiles();
	EXPECT_THAT(Grep(u"HIT", u"b.txt", u"X", { .replace = u"REP" }), Eq(0u));
	EXPECT_THAT(folder.ReadFile(u"b.txt"), Eq("none\r\n"));
}

//! 置換 + O(バックアップ): 元のファイルが .skrold に残る。既存の .skrold は置き換わる
TEST_F(GrepCommandLineTest, ReplaceWithBackup)
{
	AddBasicFiles();
	folder.AddFile(u"a.txt.skrold", "old backup\r\n");
	Grep(u"HIT", u"a.txt", u"XO", { .replace = u"REP" });
	EXPECT_THAT(folder.ReadFile(u"a.txt"), Eq("REP x REP\r\nnone\r\nREP\r\n"));
	EXPECT_THAT(folder.ReadFile(u"a.txt.skrold"), Eq("HIT x HIT\r\nnone\r\nHIT\r\n"));
}

//! 置換 + O: 既存の .skrold を消せないと、結果にメッセージを出す
TEST_F(GrepCommandLineTest, ReplaceBackupDeleteError)
{
	AddBasicFiles();
	folder.AddFile(u"a.txt.skrold", "old backup\r\n", FILE_ATTRIBUTE_READONLY);
	Grep(u"HIT", u"a.txt", u"XO", { .replace = u"REP" });
	EXPECT_THAT(Contains(GetDocumentText(), LS(STR_GREP_REP_ERR_DELETE)), IsTrue());
}

//! 置換: 読み取り専用のファイルは消せないので、結果にメッセージを出す
TEST_F(GrepCommandLineTest, ReplaceReadOnlyFile)
{
	folder.AddFile(u"ro.txt", "HIT\r\n", FILE_ATTRIBUTE_READONLY);
	Grep(u"HIT", u"ro.txt", u"X", { .replace = u"REP" });
	EXPECT_THAT(Contains(GetDocumentText(), LS(STR_GREP_REP_ERR_DELETE)), IsTrue());
	EXPECT_THAT(folder.ReadFile(u"ro.txt"), Eq("HIT\r\n"));
}

//! 置換 + 正規表現(後方参照)
TEST_F(GrepCommandLineTest, ReplaceRegularExpression)
{
	folder.AddFile(u"r.txt", "HIT HAT\r\n");
	Grep(u"H(.)T", u"r.txt", u"XR", { .replace = u"Z$1Z" });
	EXPECT_THAT(folder.ReadFile(u"r.txt"), Eq("ZIZ ZAZ\r\n"));
}

//! 置換 + 行単位・ファイルごと最初のみ
TEST_F(GrepCommandLineTest, ReplaceWithOutputOptions)
{
	AddBasicFiles();
	Grep(u"HIT", u"a.txt", u"XP", { .replace = u"REP" });
	EXPECT_THAT(folder.ReadFile(u"a.txt"), Eq("REP x REP\r\nnone\r\nREP\r\n"));
	ResetDocument();
	folder.AddFile(u"a.txt", "HIT x HIT\r\nnone\r\nHIT\r\n");
	Grep(u"HIT", u"a.txt", u"XF", { .replace = u"REP" });
	EXPECT_THAT(folder.ReadFile(u"a.txt"), Eq("REP x REP\r\nnone\r\nREP\r\n"));
}

//! 置換 + C(クリップボードから貼り付け)
TEST_F(GrepCommandLineTest, ReplaceWithClipboard)
{
	AddBasicFiles();
	Grep(u"HIT", u"a.txt", u"XC", { .replace = u"unused", .clipboard = u"CLIP" });
	EXPECT_THAT(folder.ReadFile(u"a.txt"), Eq("CLIP x CLIP\r\nnone\r\nCLIP\r\n"));
}

//! 置換 + C: クリップボードが空なら、メッセージを出して何もしない（原版 STR_DLGREPLC_CLIPBOARD）
TEST_F(GrepCommandLineTest, ReplaceWithEmptyClipboard)
{
	AddBasicFiles();
	EXPECT_THAT(Grep(u"HIT", u"a.txt", u"XC", { .replace = u"unused" }), Eq(0u));
	EXPECT_THAT(lastError, Eq(Text(LS(STR_DLGREPLC_CLIPBOARD))));
	EXPECT_THAT(GetDocumentText(), IsEmpty());
	EXPECT_THAT(folder.ReadFile(u"a.txt"), Eq("HIT x HIT\r\nnone\r\nHIT\r\n"));
}

// ---------------------------------------------------------------------------
// 状態
// ---------------------------------------------------------------------------

//! Grep 実行中は再入しない
TEST_F(GrepCommandLineTest, RejectsReentry)
{
	CGrepAgent agent;
	agent.m_bGrepRunning = true;
	TestResultView view;
	struct NullOutput : IGrepOutputTarget {
		void Append(const CNativeW&) override {}
		bool IsDrawing() const override { return false; }
	} output;
	struct NullProgress : IGrepProgress {
		bool IsCheckTime() override { return false; }
		bool IsFileNameTime() override { return false; }
		bool IsCancelRequested() override { return false; }
		void ApplyRealTimeView() override {}
		void SetHitCount(int) override {}
		void SetFileName(sakura::wstring_view) override {}
		void SetFolder(sakura::wstring_view) override {}
	} progress;
	EXPECT_THAT(([&] { agent.DoGrep(&view, ToGrepInfo(Options(u"HIT", u"*.txt", u"X")), &progress, &output); }),
		ThrowsMessage<std::domain_error>(Eq("The DoGrep method is not reentrant")));
}

//! 1 つの GrepSession は 1 回だけ実行する
TEST_F(GrepCommandLineTest, SessionRunsOnce)
{
	AddBasicFiles();
	GrepSession session(Options(u"HIT", u"*.txt", u"X"));
	EXPECT_THAT(session.Run().hitCount, Eq(3));
	EXPECT_THAT(session.IsRunning(), IsFalse());
	EXPECT_THAT(session.Run().hitCount, Eq(0));
}

// ---------------------------------------------------------------------------
// 文字コードの自動判別(イレギュラーケース)
// ---------------------------------------------------------------------------

//! 自動判別: 各文字コードのファイルを判別し、結果の行に文字コード名が付くこと
TEST_F(GrepCommandLineTest, CharsetAutoDetectEachEncoding)
{
	struct EncodedFile {
		const char16_t* name;
		std::string bytes;
		ECodeType expected;
	};
	const auto text = JapaneseLines();
	const std::vector<EncodedFile> files{
		{ u"sjis.txt", Encode(text, CODE_SJIS), CODE_SJIS },
		{ u"euc.txt", Encode(text, CODE_EUC), CODE_EUC },
		{ u"jis.txt", Encode(text, CODE_JIS), CODE_JIS },
		{ u"utf8.txt", Encode(text, CODE_UTF8), CODE_UTF8 },
		{ u"utf8bom.txt", std::string(Utf8Bom) + Encode(text, CODE_UTF8), CODE_UTF8 },
		{ u"utf16le.txt", EncodeUtf16(text, false, true), CODE_UNICODE },
		{ u"utf16be.txt", EncodeUtf16(text, true, true), CODE_UNICODEBE },
	};
	for (const auto& file : files) {
		folder.AddFile(file.name, file.bytes);
	}

	EXPECT_THAT(Grep(u"テスト", u"*.txt", u"XK"), Eq(DWORD(files.size() * 3)));
	const auto result = GetDocumentText();
	for (const auto& file : files) {
		SCOPED_TRACE(U8(file.name));
		const auto line = LineContaining(result, file.name);
		ASSERT_THAT(line.empty(), IsFalse());
		EXPECT_THAT(Contains(line, CodeBracket(file.expected)), IsTrue()) << U8(line);
	}
}

//! 自動判別: BOM の無い UTF-16
TEST_F(GrepCommandLineTest, CharsetAutoDetectUtf16WithoutBom)
{
	folder.AddFile(u"u16.txt", EncodeUtf16(JapaneseLines(), false, false));
	EXPECT_THAT(Grep(u"テスト", u"*.txt", u"XK"), Eq(3u));
}

//! 自動判別: ASCII だけ・空・NUL を含むファイルでも止まらずに続けること
TEST_F(GrepCommandLineTest, CharsetAutoDetectEdgeFiles)
{
	folder.AddFile(u"ascii.txt", "HIT\r\n");
	folder.AddFile(u"empty.txt", "");
	folder.AddFile(u"binary.txt", std::string("\x00\x01HIT\x00\xFF\xFE", 8));

	const auto hits = Grep(u"HIT", u"*.txt", u"XK");
	EXPECT_THAT(hits, Ge(1u));
	const auto result = GetDocumentText();
	EXPECT_THAT(Contains(LineContaining(result, u"ascii.txt"), u"HIT"), IsTrue());
	EXPECT_THAT(LineContaining(result, u"empty.txt").empty(), IsTrue());
	EXPECT_THAT(Contains(result, MatchCountText(int(hits))), IsTrue());
}

//! 自動判別 + 空の検索キー(ファイル名の一覧): 一覧にも文字コード名が付くこと
TEST_F(GrepCommandLineTest, FileListWithAutoDetect)
{
	const auto text = JapaneseLines();
	folder.AddFile(u"sjis.txt", Encode(text, CODE_SJIS));
	folder.AddFile(u"utf8.txt", Encode(text, CODE_UTF8));
	folder.AddFile(u"utf16le.txt", EncodeUtf16(text, false, true));
	Grep(u"", u"*.txt", u"XK");
	const auto result = GetDocumentText();
	EXPECT_THAT(Contains(LineContaining(result, u"sjis.txt"), CodeBracket(CODE_SJIS)), IsTrue());
	EXPECT_THAT(Contains(LineContaining(result, u"utf8.txt"), CodeBracket(CODE_UTF8)), IsTrue());
	EXPECT_THAT(Contains(LineContaining(result, u"utf16le.txt"), CodeBracket(CODE_UNICODE)), IsTrue());
}

//! 文字コードをコードページで指定する(-GCODE=932)
TEST_F(GrepCommandLineTest, CharsetCodePage)
{
	folder.AddFile(u"sjis.txt", Encode(JapaneseLines(), CODE_SJIS));
	folder.AddFile(u"utf8.txt", Encode(JapaneseLines(), CODE_UTF8));
	EXPECT_THAT(Grep(u"テスト", u"*.txt", u"X", { .code = 932 }), Eq(3u));
}

//! 自動判別で置換しても、文字コードと BOM が保たれること
TEST_F(GrepCommandLineTest, ReplacePreservesEncoding)
{
	const auto text = JapaneseLines();
	Text replaced = text;
	for (size_t pos; (pos = replaced.find(u"テスト")) != Text::npos; ) {
		replaced.replace(pos, 3, u"TEST");
	}
	folder.AddFile(u"sjis.txt", Encode(text, CODE_SJIS));
	folder.AddFile(u"utf8bom.txt", std::string(Utf8Bom) + Encode(text, CODE_UTF8));
	folder.AddFile(u"utf16le.txt", EncodeUtf16(text, false, true));
	folder.AddFile(u"utf16be.txt", EncodeUtf16(text, true, true));

	Grep(u"テスト", u"*.txt", u"XK", { .replace = u"TEST" });

	EXPECT_THAT(folder.ReadFile(u"sjis.txt"), Eq(Encode(replaced, CODE_SJIS)));
	EXPECT_THAT(folder.ReadFile(u"utf8bom.txt"), Eq(std::string(Utf8Bom) + Encode(replaced, CODE_UTF8)));
	EXPECT_THAT(folder.ReadFile(u"utf16le.txt"), Eq(EncodeUtf16(replaced, false, true)));
	EXPECT_THAT(folder.ReadFile(u"utf16be.txt"), Eq(EncodeUtf16(replaced, true, true)));
}

// ---------------------------------------------------------------------------
// そのほかのイレギュラーケース
// ---------------------------------------------------------------------------

//! 行末が LF だけ・CR だけ・最終行に行末が無い。置換しても行末は元のまま
TEST_F(GrepCommandLineTest, LineEndings)
{
	folder.AddFile(u"lf.txt", "HIT\nx\nHIT\n");
	folder.AddFile(u"cr.txt", "HIT\rx\rHIT\r");
	folder.AddFile(u"noeol.txt", "x\r\nHIT");
	EXPECT_THAT(Grep(u"HIT", u"*.txt", u"XP"), Eq(5u));

	ResetDocument();
	Grep(u"HIT", u"*.txt", u"X", { .replace = u"REP" });
	EXPECT_THAT(folder.ReadFile(u"lf.txt"), Eq("REP\nx\nREP\n"));
	EXPECT_THAT(folder.ReadFile(u"cr.txt"), Eq("REP\rx\rREP\r"));
	EXPECT_THAT(folder.ReadFile(u"noeol.txt"), Eq("x\r\nREP"));
}

//! サロゲートペアの文字を検索できる
TEST_F(GrepCommandLineTest, SurrogatePair)
{
	folder.AddFile(u"s.txt", Encode(u"\U00020BB7野家 \U00020BB7\r\n", CODE_UTF8));	// 𠮷野家 𠮷
	EXPECT_THAT(Grep(u"\U00020BB7", u"*.txt", u"X", { .code = int(CODE_UTF8) }), Eq(2u));
}

//! 全角英字の大文字小文字を区別しない
TEST_F(GrepCommandLineTest, FullWidthIgnoreCase)
{
	folder.AddFile(u"fw.txt", Encode(u"ＡＢＣ\r\n", CODE_UTF8));
	EXPECT_THAT(Grep(u"ａｂｃ", u"*.txt", u"X", { .code = int(CODE_UTF8) }), Eq(1u));
}

//! 長さ 0 に一致する正規表現でも無限ループにならない
TEST_F(GrepCommandLineTest, RegexZeroLengthMatchTerminates)
{
	AddBasicFiles();
	EXPECT_THAT(Grep(u"^", u"a.txt", u"XR"), Ge(1u));
	ResetDocument();
	EXPECT_THAT(Grep(u"x*", u"a.txt", u"XR"), Ge(1u));
}

//! 非常に長い行(10 万文字)
TEST_F(GrepCommandLineTest, VeryLongLine)
{
	folder.AddFile(u"long.txt", std::string(100000, 'x') + "HIT\r\n");
	EXPECT_THAT(Grep(u"HIT", u"*.txt", u"XP"), Eq(1u));
}

//! 検索キーに「"」を含む（原版のコマンドラインでは "" と書く）
TEST_F(GrepCommandLineTest, KeyWithQuote)
{
	folder.AddFile(u"q.txt", "say \"HIT\"\r\nHIT\r\n");
	EXPECT_THAT(Grep(u"\"HIT\"", u"*.txt", u"X"), Eq(1u));
}

//! 5MB を超えるファイル(進捗表示と UI 更新の間隔の分岐を通す)
TEST_F(GrepCommandLineTest, LargeFile)
{
	const std::string line = std::string(94, 'x') + " HIT\r\n";
	constexpr size_t lineCount = 60000;
	std::string data;
	data.reserve(line.size() * lineCount);
	for (size_t i = 0; i < lineCount; ++i) {
		data += line;
	}
	folder.AddFile(u"large.txt", data);
	EXPECT_THAT(Grep(u"HIT", u"large.txt", u"XN"), Eq(0u));
}

//! 無効な :HWND: は 0 件で、結果にエラーを出す
TEST_F(GrepCommandLineTest, InvalidHwndTarget)
{
	EXPECT_THAT(Grep(u"HIT", u":HWND:0", u"X"), Eq(0u));
	EXPECT_THAT(Contains(GetDocumentText(), u"HWND handle error."), IsTrue());
}

/*!
	見出しの検索キーは、出力先の文書のタイプ別設定に従ってエスケープされる(EscapeStringLiteral())

	C++ 風は \ と ' と " の前に \ を付け、PL/SQL 風は ' と " を重ねる。文字列の色分けが無効ならそのまま。
	（原版は結果の文書のタイプ別設定を変える。Mac 版は結果の文書の替身のタイプ別設定を変える）
*/
TEST_F(GrepCommandLineTest, HeaderEscapesKeyByStringType)
{
	struct Case {
		bool bDisp;
		EStringLiteralType stringType;
		std::u16string_view expected;
	};
	const Case cases[] = {
		{ true,  STRING_LITERAL_CPP,   uR"(x\\y\'z)" },
		{ true,  STRING_LITERAL_PLSQL, uR"(x\y''z)" },
		{ false, STRING_LITERAL_CPP,   uR"(x\y'z)" },
	};
	struct TextOutput : IGrepOutputTarget {
		void Append(const CNativeW& cmem) override { text.append(cmem.GetStringPtr(), size_t(cmem.GetStringLength())); }
		bool IsDrawing() const override { return false; }
		Text text;
	};
	struct NullProgress : IGrepProgress {
		bool IsCheckTime() override { return false; }
		bool IsFileNameTime() override { return false; }
		bool IsCancelRequested() override { return false; }
		void ApplyRealTimeView() override {}
		void SetHitCount(int) override {}
		void SetFileName(sakura::wstring_view) override {}
		void SetFolder(sakura::wstring_view) override {}
	};
	for (const auto& c : cases) {
		TestResultView view;
		view.type.m_ColorInfoArr[COLORIDX_WSTRING].m_bDisp = c.bDisp;
		view.type.m_nStringType = decltype(view.type.m_nStringType)(c.stringType);
		TextOutput output;
		NullProgress progress;
		CGrepAgent agent;
		agent.DoGrep(&view, ToGrepInfo(Options(uR"(x\y'z)", u"*.txt", u"X")), &progress, &output);
		const Text quoted = u"\"" + Text(c.expected) + u"\"";
		EXPECT_THAT(Contains(output.text, quoted), IsTrue()) << U8(quoted);
	}
}

//! 複数のフォルダー + ベースフォルダー表示(B): フォルダーごとに見出しが 1 回ずつ出る
TEST_F(GrepCommandLineTest, MultipleFoldersBaseFolderHeader)
{
	folder.AddFile(u"p/x.txt", "HIT\r\n");
	folder.AddFile(u"q/y.txt", "HIT\r\n");
	const auto folders = folder.PathOf(u"p") + u";" + folder.PathOf(u"q");
	EXPECT_THAT(RunGrep(MakeOptions(u"HIT", u"*.txt", folders, u"XB")), Eq(2u));

	std::vector<Text> headers;
	for (const auto& line : Lines(GetDocumentText())) {
		if (line.starts_with(u"■\"")) {
			headers.push_back(line);
		}
	}
	ASSERT_THAT(headers.size(), Eq(2u));
	EXPECT_THAT(headers[0].ends_with(u"/p\""), IsTrue()) << U8(headers[0]);
	EXPECT_THAT(headers[1].ends_with(u"/q\""), IsTrue()) << U8(headers[1]);
}

//! 置換: 書き込み用の .skrnew を作れないと、結果にメッセージを出し、元のファイルは変わらない
TEST_F(GrepCommandLineTest, ReplaceWriteOpenError)
{
	AddBasicFiles();
	folder.AddFolder(u"a.txt.skrnew");	// 同じ名前のフォルダーがあるとファイルを作れない
	Grep(u"HIT", u"a.txt", u"X", { .replace = u"REP" });
	ASSERT_THAT(ResourcePrefix(STR_GREP_ERR_FILEWRITE).empty(), IsFalse());
	EXPECT_THAT(Contains(GetDocumentText(), ResourcePrefix(STR_GREP_ERR_FILEWRITE)), IsTrue());
	EXPECT_THAT(folder.ReadFile(u"a.txt"), Eq("HIT x HIT\r\nnone\r\nHIT\r\n"));
}

/*!
	置換: 元のファイルを消せないと、結果にメッセージを出し、元のファイルは変わらない
	（原版は共有読み取りで開いたファイル。Mac 版は変更不可(chflags uchg)のファイル）

	【現状の制限】書き出した .skrnew は消されずに残る。
*/
TEST_F(GrepCommandLineTest, ReplaceLockedFile)
{
	AddBasicFiles();
	ASSERT_THAT(::chflags((folder.Path().fs() / "a.txt").c_str(), UF_IMMUTABLE), Eq(0));
	Grep(u"HIT", u"a.txt", u"X", { .replace = u"REP" });

	EXPECT_THAT(Contains(GetDocumentText(), ResourcePrefix(STR_GREP_REP_ERR_DELETE)), IsTrue());
	EXPECT_THAT(folder.ReadFile(u"a.txt"), Eq("HIT x HIT\r\nnone\r\nHIT\r\n"));
	EXPECT_THAT(folder.ReadFile(u"a.txt.skrnew"), Eq("REP x REP\r\nnone\r\nREP\r\n"));	// 【現状の制限】
}

/*!
	置換 + O(バックアップ): 元のファイルを .skrold に移せないと、結果にメッセージを出し、元のファイルは変わらない

	【現状の制限】書き出した .skrnew は消されずに残る。
*/
TEST_F(GrepCommandLineTest, ReplaceLockedFileWithBackup)
{
	AddBasicFiles();
	ASSERT_THAT(::chflags((folder.Path().fs() / "a.txt").c_str(), UF_IMMUTABLE), Eq(0));
	Grep(u"HIT", u"a.txt", u"XO", { .replace = u"REP" });

	ASSERT_THAT(ResourcePrefix(STR_GREP_REP_ERR_REPLACE).empty(), IsFalse());
	EXPECT_THAT(Contains(GetDocumentText(), ResourcePrefix(STR_GREP_REP_ERR_REPLACE)), IsTrue());
	EXPECT_THAT(folder.ReadFile(u"a.txt"), Eq("HIT x HIT\r\nnone\r\nHIT\r\n"));
	EXPECT_THAT(folder.Exists(u"a.txt.skrold"), IsFalse());
	EXPECT_THAT(folder.Exists(u"a.txt.skrnew"), IsTrue());	// 【現状の制限】
}

//! Grep は隠し・読み取り専用のファイルも検索する（Mac 版にシステム属性は無い）
TEST_F(GrepCommandLineTest, SearchesHiddenReadOnlySystemFiles)
{
	folder.AddFile(u"n.txt", "HIT\r\n");
	folder.AddFile(u"h.txt", "HIT\r\n", FILE_ATTRIBUTE_HIDDEN);
	folder.AddFile(u".dot.txt", "HIT\r\n");
	folder.AddFile(u"r.txt", "HIT\r\n", FILE_ATTRIBUTE_READONLY);
	EXPECT_THAT(Grep(u"HIT", u"*.txt", u"X"), Eq(4u));
}

//! 文字コード固定(UTF-8): BOM だけのファイルは 0 件。不正なバイト列を含むファイルも、正しい部分は検索できる
TEST_F(GrepCommandLineTest, FixedUtf8BomOnlyAndInvalidBytes)
{
	folder.AddFile(u"bomonly.txt", Utf8Bom);
	folder.AddFile(u"invalid.txt", std::string("abc\xFF\xFE" "def\r\n"));
	EXPECT_THAT(Grep(u"def", u"*.txt", u"X", { .code = int(CODE_UTF8) }), Eq(1u));
	EXPECT_THAT(LineContaining(GetDocumentText(), u"bomonly.txt").empty(), IsTrue());
}

//! -GCODE に範囲外の値: Grep は止まらずに終わる
TEST_F(GrepCommandLineTest, CharsetOutOfRange)
{
	AddBasicFiles();
	EXPECT_THAT(Grep(u"HIT", u"a.txt", u"X", { .code = 99999 }), Eq(3u));
}

// ---------------------------------------------------------------------------
// フォルダーの一覧(CGrepAgent の static 関数)
// ---------------------------------------------------------------------------

//! ChopYen: 末尾の / を 1 つだけ取り除く。Mac 版はルートの / を残す（空にすると相対パスになる）
TEST(GrepFolderList, ChopYen)
{
	EXPECT_THAT(CGrepAgent::ChopYen(u"/"), Eq(u"/"));
	EXPECT_THAT(CGrepAgent::ChopYen(u"/work/"), Eq(u"/work"));
	EXPECT_THAT(CGrepAgent::ChopYen(u"/work//"), Eq(u"/work/"));
	EXPECT_THAT(CGrepAgent::ChopYen(u"/work"), Eq(u"/work"));
	EXPECT_THAT(CGrepAgent::ChopYen(u""), Eq(u""));
}

//! CreateFolders: ; で分け、引用符を取り除く
TEST(GrepFolderList, CreateFoldersSplitsAndUnquotes)
{
	TempFolder folder;
	const auto a = folder.PathOf(u"none_a");
	const auto b = folder.PathOf(u"none;b");
	const Text list = a + u";\"" + b + u"\"";
	std::vector<sakura::wstring> paths;
	CGrepAgent::CreateFolders(list.c_str(), paths);
	EXPECT_THAT(paths, Eq(std::vector<sakura::wstring>{ a, b }));
}

//! CreateFolders: . と .. を取り除き、相対パスは絶対パスにする（原版の 8.3 形式の短い名前は Mac に無い）
TEST(GrepFolderList, CreateFoldersResolvesShortName)
{
	TempFolder folder;
	const Text longName = u"long_folder_name_for_grep";
	folder.AddFolder(longName);
	std::vector<sakura::wstring> paths;
	CGrepAgent::CreateFolders((folder.PathOf(longName) + u"/./x/..").c_str(), paths);
	ASSERT_THAT(paths.size(), Eq(1u));
	EXPECT_THAT(CGrepAgent::ChopYen(paths[0]), Eq(folder.PathOf(longName)));
}

// ---------------------------------------------------------------------------
// 出力のスナップショット
// ---------------------------------------------------------------------------

/*!
	@brief Grep の出力をそのまま比べるテスト（原版は -GOPT=U の標準出力。Mac 版は GrepSession の結果の文字）

	H でヘッダー・フッターを出さないので、出力は結果の行だけになる。
*/
struct GrepOutputSnapshotTest : public GrepCommandLineTest {
	static constexpr std::string_view SNAPSHOT_TEXT = "alpha needle one\r\nbravo two\r\n";

	//! 出力のパス（原版は長い名前。Mac 版はそのまま）
	Text LongPath(const Text& relPath) const { return relPath.empty() ? folder.PathText() : folder.PathOf(relPath); }

	//! -GOPT に XH を足して Grep し、結果の文字を返す
	Text GrepStdout(const Text& key, const Text& file, std::u16string_view opt, DWORD* pHitCount = nullptr, const Extra& extra = {})
	{
		ResetDocument();
		const auto hitCount = Grep(key, file, Text(u"XH") + Text(opt), extra);
		if (pHitCount) {
			*pHitCount = hitCount;
		}
		return GetDocumentText();
	}
};

//! 形式 1(ノーマル): 該当部分・該当行・否該当行
TEST_F(GrepOutputSnapshotTest, Style1LineTypes)
{
	folder.AddFile(u"snap.txt", SNAPSHOT_TEXT);
	const auto path = LongPath(u"snap.txt");

	EXPECT_THAT(GrepStdout(u"needle", u"snap.txt", u"1"), Eq(path + u"(1,7): needle\r\n"));
	EXPECT_THAT(GrepStdout(u"needle", u"snap.txt", u"1P"), Eq(path + u"(1,7): alpha needle one\r\n"));
	EXPECT_THAT(GrepStdout(u"needle", u"snap.txt", u"1N"), Eq(path + u"(2,1): bravo two\r\n"));
}

//! 形式 1: 1 行に 2 つ。該当部分なら 2 行、該当行なら 1 行
TEST_F(GrepOutputSnapshotTest, Style1MultipleHitsInLine)
{
	folder.AddFile(u"snap.txt", "needle x needle\r\n");
	const auto path = LongPath(u"snap.txt");

	DWORD hitCount = 0;
	EXPECT_THAT(GrepStdout(u"needle", u"snap.txt", u"1", &hitCount), Eq(path + u"(1,1): needle\r\n" + path + u"(1,10): needle\r\n"));
	EXPECT_THAT(hitCount, Eq(2u));
	EXPECT_THAT(GrepStdout(u"needle", u"snap.txt", u"1P", &hitCount), Eq(path + u"(1,1): needle x needle\r\n"));
	EXPECT_THAT(hitCount, Eq(1u));
}

//! 形式 2(WZ 風): ファイルの見出しは 1 回、位置は (%6d,%-5d)
TEST_F(GrepOutputSnapshotTest, Style2HeaderOncePerFile)
{
	folder.AddFile(u"snap.txt", "needle\r\nx\r\nneedle\r\n");
	const auto path = LongPath(u"snap.txt");

	const Text expected = u"■\"" + path + u"\"\r\n"
		+ u"・(     1,1    ): needle\r\n"
		+ u"・(     3,1    ): needle\r\n";
	EXPECT_THAT(GrepStdout(u"needle", u"snap.txt", u"2P"), Eq(expected));
}

//! 形式 3(結果のみ): パスも位置も出さない
TEST_F(GrepOutputSnapshotTest, Style3LineTypes)
{
	folder.AddFile(u"snap.txt", SNAPSHOT_TEXT);
	EXPECT_THAT(GrepStdout(u"needle", u"snap.txt", u"3"), Eq(u"needle\r\n"));
	EXPECT_THAT(GrepStdout(u"needle", u"snap.txt", u"3P"), Eq(u"alpha needle one\r\n"));
}

//! B(ベースフォルダー表示): 見出しは 1 回、結果は「・」＋ベースからの相対パス。ファイルが先、サブフォルダーが後
TEST_F(GrepOutputSnapshotTest, BaseFolderRelativePath)
{
	folder.AddFile(u"snap.txt", SNAPSHOT_TEXT);
	folder.AddFile(u"sub/snap.txt", SNAPSHOT_TEXT);
	const auto base = LongPath(u"");

	const Text expected = u"■\"" + base + u"\"\r\n"
		+ u"・snap.txt(1,7): alpha needle one\r\n"
		+ u"・sub/snap.txt(1,7): alpha needle one\r\n";
	EXPECT_THAT(GrepStdout(u"needle", u"*.txt", u"1PSB"), Eq(expected));
}

//! B+D(フォルダー毎に表示): ベースは ◎、フォルダーは ■、結果はファイル名
TEST_F(GrepOutputSnapshotTest, BaseAndSeparateFolderHeaders)
{
	folder.AddFile(u"snap.txt", SNAPSHOT_TEXT);
	folder.AddFile(u"sub/snap.txt", SNAPSHOT_TEXT);
	const auto base = LongPath(u"");

	DWORD hitCount = 0;
	const auto output = GrepStdout(u"needle", u"*.txt", u"2PSBD", &hitCount);
	EXPECT_THAT(hitCount, Eq(2u));

	const Text baseHeader = u"◎\"" + base + u"\"\r\n";
	const Text subHeader = u"■\"sub\"\r\n";
	const Text hitLine = u"・(     1,7    ): alpha needle one\r\n";
	EXPECT_THAT(output.starts_with(baseHeader), IsTrue());
	EXPECT_THAT(Contains(output, subHeader), IsTrue());
	EXPECT_THAT(output.find(hitLine), Lt(output.rfind(hitLine)));
	EXPECT_THAT(output.find(subHeader), Lt(output.rfind(hitLine)));
}

//! 入れ子のフォルダー: フォルダーごとにファイルが先、サブフォルダーが後(深さ優先)
TEST_F(GrepOutputSnapshotTest, NestedFoldersOrder)
{
	for (const auto name : { u"a.txt", u"b.txt", u"sub1/x.txt", u"sub1/deep/y.txt", u"sub2/z.txt" }) {
		folder.AddFile(name, SNAPSHOT_TEXT);
	}
	const auto base = LongPath(u"");

	const Text expected = u"■\"" + base + u"\"\r\n"
		+ u"・a.txt(1,7): alpha needle one\r\n"
		+ u"・b.txt(1,7): alpha needle one\r\n"
		+ u"・sub1/x.txt(1,7): alpha needle one\r\n"
		+ u"・sub1/deep/y.txt(1,7): alpha needle one\r\n"
		+ u"・sub2/z.txt(1,7): alpha needle one\r\n";
	EXPECT_THAT(GrepStdout(u"needle", u"*.txt", u"1PSB"), Eq(expected));
}

//! ファイル名の順序は Windows(NTFS)と同じ: 大文字小文字を区別せず、記号・数字・英字・日本語の順（Mac 版で追加）
TEST_F(GrepOutputSnapshotTest, FileOrderSameAsWindows)
{
	for (const auto name : { u"b.txt", u"B2.txt", u"a.txt", u"_x.txt", u"1.txt", u"あ.txt", u"A1.txt", u"[z].txt" }) {
		folder.AddFile(name, "needle\r\n");
	}
	const auto base = LongPath(u"");
	const Text expected = u"■\"" + base + u"\"\r\n"
		+ u"・1.txt(1,1): needle\r\n"
		+ u"・a.txt(1,1): needle\r\n"
		+ u"・A1.txt(1,1): needle\r\n"
		+ u"・b.txt(1,1): needle\r\n"
		+ u"・B2.txt(1,1): needle\r\n"
		+ u"・[z].txt(1,1): needle\r\n"
		+ u"・_x.txt(1,1): needle\r\n"
		+ u"・あ.txt(1,1): needle\r\n";
	EXPECT_THAT(GrepStdout(u"needle", u"*.txt", u"1PB"), Eq(expected));
}

//! D(フォルダー毎に表示): 見出しはフォルダーごとに 1 回。ヒットの無いフォルダーには出ない
TEST_F(GrepOutputSnapshotTest, SeparateFolderHeaderOncePerFolder)
{
	folder.AddFile(u"sub1/a.txt", SNAPSHOT_TEXT);
	folder.AddFile(u"sub1/b.txt", SNAPSHOT_TEXT);
	folder.AddFile(u"nohit/c.txt", "bravo two\r\n");
	folder.AddFile(u"sub2/d.txt", SNAPSHOT_TEXT);

	DWORD hitCount = 0;
	const auto output = GrepStdout(u"needle", u"*.txt", u"2PSBD", &hitCount);

	const Text sub1Header = u"■\"sub1\"\r\n";
	const Text sub2Header = u"■\"sub2\"\r\n";
	const auto first = output.find(sub1Header);
	EXPECT_THAT(hitCount, Eq(3u));
	ASSERT_THAT(first, Ne(Text::npos));
	EXPECT_THAT(output.find(sub1Header, first + 1), Eq(Text::npos));
	EXPECT_THAT(Contains(output, u"■\"nohit\""), IsFalse());
	EXPECT_THAT(first, Lt(output.find(sub2Header)));
}

//! 検索キーにフォルダーを含む(sub/*.txt): 結果の相対パスにフォルダーが付く
TEST_F(GrepOutputSnapshotTest, KeyWithSubFolderPath)
{
	folder.AddFile(u"snap.txt", SNAPSHOT_TEXT);
	folder.AddFile(u"sub/snap.txt", SNAPSHOT_TEXT);
	const auto base = LongPath(u"");

	const Text expected = u"■\"" + base + u"\"\r\n" + u"・sub/snap.txt(1,7): alpha needle one\r\n";
	EXPECT_THAT(GrepStdout(u"needle", u"sub/*.txt", u"1PB"), Eq(expected));
}

//! 改行が混ざっても行番号がずれない(CRLF・LF・CR・改行なしの最終行)
TEST_F(GrepOutputSnapshotTest, MixedLineEndings)
{
	folder.AddFile(u"mixed.txt", "HIT\r\nx\nHIT\rHIT");
	const auto path = LongPath(u"mixed.txt");

	const Text expected = path + u"(1,1): HIT\r\n" + path + u"(3,1): HIT\r\n" + path + u"(4,1): HIT\r\n";
	DWORD hitCount = 0;
	EXPECT_THAT(GrepStdout(u"HIT", u"mixed.txt", u"1P", &hitCount), Eq(expected));
	EXPECT_THAT(hitCount, Eq(3u));
}

// ---------------------------------------------------------------------------
// Grep 置換の細部
// ---------------------------------------------------------------------------

struct GrepReplaceDetailTest : public GrepOutputSnapshotTest {
	//! -GOPT に XH を足し、置換し、結果の文字を返す
	Text ReplaceStdout(const Text& key, const Text& file, std::u16string_view opt, const Text& replace, DWORD* pHitCount = nullptr)
	{
		return GrepStdout(key, file, opt, pHitCount, { .replace = replace });
	}
};

//! 単語単位: 1 行に複数の単語を置換し、単語の一部(HITS・xHIT・HIT_X)は置換しない。結果は一致ごとに出す
TEST_F(GrepReplaceDetailTest, WordOnly)
{
	folder.AddFile(u"w.txt", "HIT HITS xHIT HIT.\r\nHIT_X HIT\r\n");
	const auto path = LongPath(u"w.txt");

	const Text expected = path + u"(1,1): HIT\r\n" + path + u"(1,15): HIT\r\n" + path + u"(2,7): HIT\r\n";
	DWORD hitCount = 0;
	EXPECT_THAT(ReplaceStdout(u"HIT", u"w.txt", u"1W", u"REP", &hitCount), Eq(expected));
	EXPECT_THAT(hitCount, Eq(3u));
	EXPECT_THAT(folder.ReadFile(u"w.txt"), Eq("REP HITS xHIT REP.\r\nHIT_X REP\r\n"));
}

//! 文字列: 1 行に複数・行末の直前・最終行(行末なし)を置換し、置換した数を返す
TEST_F(GrepReplaceDetailTest, StringMultipleInLine)
{
	folder.AddFile(u"s.txt", "aaaa HIT\r\nHITHIT\r\nxHIT");
	EXPECT_THAT(Grep(u"HIT", u"s.txt", u"X", { .replace = u"REP" }), Eq(4u));
	EXPECT_THAT(folder.ReadFile(u"s.txt"), Eq("aaaa REP\r\nREPREP\r\nxREP"));
}

//! 文字列: 一致の後ろから次を探すので、重なる一致は置換しない
TEST_F(GrepReplaceDetailTest, StringDoesNotOverlap)
{
	folder.AddFile(u"s.txt", "aaaaa\r\n");
	EXPECT_THAT(Grep(u"aa", u"s.txt", u"X", { .replace = u"b" }), Eq(2u));
	EXPECT_THAT(folder.ReadFile(u"s.txt"), Eq("bba\r\n"));
}

//! 文字列: L が無ければ大文字小文字を区別せずに置換し、L があれば区別する
TEST_F(GrepReplaceDetailTest, StringCase)
{
	folder.AddFile(u"s.txt", "hit Hit HIT\r\n");
	EXPECT_THAT(Grep(u"HIT", u"s.txt", u"X", { .replace = u"REP" }), Eq(3u));
	EXPECT_THAT(folder.ReadFile(u"s.txt"), Eq("REP REP REP\r\n"));

	ResetDocument();
	folder.AddFile(u"s.txt", "hit Hit HIT\r\n");
	EXPECT_THAT(Grep(u"HIT", u"s.txt", u"XL", { .replace = u"REP" }), Eq(1u));
	EXPECT_THAT(folder.ReadFile(u"s.txt"), Eq("hit Hit REP\r\n"));
}

//! 正規表現(普通): 1 行の一致をまとめて置換し、置換した数を足す
TEST_F(GrepReplaceDetailTest, RegexCountsEachMatch)
{
	folder.AddFile(u"r.txt", "HIT HAT\r\nHUT\r\n");
	EXPECT_THAT(Grep(u"H(.)T", u"r.txt", u"XR", { .replace = u"Z$1Z" }), Eq(3u));
	EXPECT_THAT(folder.ReadFile(u"r.txt"), Eq("ZIZ ZAZ\r\nZUZ\r\n"));
}

//! 正規表現 + C(クリップボードから貼り付け): 一致を探して、前の部分と貼り付ける文字列をつなぐ
TEST_F(GrepReplaceDetailTest, PasteRegexMultipleInLine)
{
	folder.AddFile(u"p.txt", "aXbXc\r\n");
	EXPECT_THAT(Grep(u"X", u"p.txt", u"XRC", { .replace = u"unused", .clipboard = u"Z" }), Eq(2u));
	EXPECT_THAT(folder.ReadFile(u"p.txt"), Eq("aZbZc\r\n"));
}

//! F(ファイル毎最初のみ): 結果に出すのは最初の 1 件だけで、置換はすべて行い、置換した数を返す
TEST_F(GrepReplaceDetailTest, FileOnlyReplacesAll)
{
	folder.AddFile(u"a.txt", "HIT x HIT\r\nnone\r\nHIT\r\n");
	const auto path = LongPath(u"a.txt");

	DWORD hitCount = 0;
	EXPECT_THAT(ReplaceStdout(u"HIT", u"a.txt", u"1F", u"REP", &hitCount), Eq(path + u"(1,1): HIT\r\n"));
	EXPECT_THAT(hitCount, Eq(3u));
	EXPECT_THAT(folder.ReadFile(u"a.txt"), Eq("REP x REP\r\nnone\r\nREP\r\n"));
}

//! P(該当行): 1 行に複数の一致があっても結果は 1 行で、置換はすべて行う
TEST_F(GrepReplaceDetailTest, OutputLineOncePerLine)
{
	folder.AddFile(u"a.txt", "HIT x HIT\r\n");
	const auto path = LongPath(u"a.txt");

	DWORD hitCount = 0;
	EXPECT_THAT(ReplaceStdout(u"HIT", u"a.txt", u"1P", u"REP", &hitCount), Eq(path + u"(1,1): HIT x HIT\r\n"));
	EXPECT_THAT(hitCount, Eq(2u));
	EXPECT_THAT(folder.ReadFile(u"a.txt"), Eq("REP x REP\r\n"));
}

//! 置換後の文字列が空: 一致を消す。ファイルが空になれば 0 バイトのファイルになる
TEST_F(GrepReplaceDetailTest, EmptyReplacement)
{
	folder.AddFile(u"s.txt", "aHITb HIT\r\n");
	EXPECT_THAT(Grep(u"HIT", u"s.txt", u"X", { .replace = u"" }), Eq(2u));
	EXPECT_THAT(folder.ReadFile(u"s.txt"), Eq("ab \r\n"));

	ResetDocument();
	folder.AddFile(u"w.txt", "HIT x HIT\r\n");
	EXPECT_THAT(Grep(u"HIT", u"w.txt", u"XW", { .replace = u"" }), Eq(2u));
	EXPECT_THAT(folder.ReadFile(u"w.txt"), Eq(" x \r\n"));

	ResetDocument();
	folder.AddFile(u"e.txt", "HIT");
	EXPECT_THAT(Grep(u"HIT", u"e.txt", u"X", { .replace = u"" }), Eq(1u));
	EXPECT_THAT(folder.ReadFile(u"e.txt"), IsEmpty());
	EXPECT_THAT(folder.Exists(u"e.txt.skrnew"), IsFalse());
}

//! 文字列・単語単位: 置換後の文字列の $ や \ や & は、そのままの文字として入る
TEST_F(GrepReplaceDetailTest, ReplacementTakenLiterally)
{
	folder.AddFile(u"s.txt", "HIT\r\n");
	EXPECT_THAT(Grep(u"HIT", u"s.txt", u"X", { .replace = uR"(a$1\n&b)" }), Eq(1u));
	EXPECT_THAT(folder.ReadFile(u"s.txt"), Eq("a$1\\n&b\r\n"));
}

//! 置換後の文字列が検索語を含んでも、置換した後ろから次を探すので、もう一度は置換しない
TEST_F(GrepReplaceDetailTest, ReplacementContainsKey)
{
	folder.AddFile(u"s.txt", "HIT HIT\r\n");
	EXPECT_THAT(Grep(u"HIT", u"s.txt", u"X", { .replace = u"HIT!" }), Eq(2u));
	EXPECT_THAT(folder.ReadFile(u"s.txt"), Eq("HIT! HIT!\r\n"));

	ResetDocument();
	folder.AddFile(u"w.txt", "HIT HIT\r\n");
	EXPECT_THAT(Grep(u"HIT", u"w.txt", u"XW", { .replace = u"HIT!" }), Eq(2u));
	EXPECT_THAT(folder.ReadFile(u"w.txt"), Eq("HIT! HIT!\r\n"));
}

//! 置換後も内容が同じ: ファイルを書き直し、O ならバックアップも作る
TEST_F(GrepReplaceDetailTest, SameContentStillRewrites)
{
	folder.AddFile(u"s.txt", "HIT\r\n");
	EXPECT_THAT(Grep(u"HIT", u"s.txt", u"XO", { .replace = u"HIT" }), Eq(1u));
	EXPECT_THAT(folder.ReadFile(u"s.txt"), Eq("HIT\r\n"));
	EXPECT_THAT(folder.ReadFile(u"s.txt.skrold"), Eq("HIT\r\n"));
}

//! 一致しようがない検索語(空・単語単位で空白だけ)は 0 件で、ファイルを書き換えない
TEST_F(GrepReplaceDetailTest, KeyThatCannotMatch)
{
	folder.AddFile(u"s.txt", "HIT x\r\n");
	EXPECT_THAT(Grep(u"", u"s.txt", u"X", { .replace = u"REP" }), Eq(0u));
	ResetDocument();
	EXPECT_THAT(Grep(u" ", u"s.txt", u"XW", { .replace = u"REP" }), Eq(0u));
	EXPECT_THAT(folder.ReadFile(u"s.txt"), Eq("HIT x\r\n"));
	EXPECT_THAT(folder.Exists(u"s.txt.skrnew"), IsFalse());
}

//! 正規表現(普通): 行末つきの検索語(HIT$)は、CRLF・LF・CR・行末なしのどれでも、行末を残して置換する
TEST_F(GrepReplaceDetailTest, RegexLineEndKeepsEol)
{
	folder.AddFile(u"crlf.txt", "HIT\r\nx HIT\r\n");
	folder.AddFile(u"lf.txt", "HIT\nx HIT\n");
	folder.AddFile(u"cr.txt", "HIT\rx HIT\r");
	folder.AddFile(u"noeol.txt", "HIT\r\nx HIT");
	EXPECT_THAT(Grep(u"HIT$", u"*.txt", u"XR", { .replace = u"REP" }), Eq(8u));
	EXPECT_THAT(folder.ReadFile(u"crlf.txt"), Eq("REP\r\nx REP\r\n"));
	EXPECT_THAT(folder.ReadFile(u"lf.txt"), Eq("REP\nx REP\n"));
	EXPECT_THAT(folder.ReadFile(u"cr.txt"), Eq("REP\rx REP\r"));
	EXPECT_THAT(folder.ReadFile(u"noeol.txt"), Eq("REP\r\nx REP"));
}

//! N(否該当行)を指定しても、置換では P(該当行)として扱う(GrepInfo::Normalized())
TEST_F(GrepReplaceDetailTest, NoHitLineActsAsOutputLine)
{
	folder.AddFile(u"a.txt", "HIT x HIT\r\nnone\r\n");
	const auto path = LongPath(u"a.txt");

	DWORD hitCount = 0;
	EXPECT_THAT(ReplaceStdout(u"HIT", u"a.txt", u"1N", u"REP", &hitCount), Eq(path + u"(1,1): HIT x HIT\r\n"));
	EXPECT_THAT(hitCount, Eq(2u));
	EXPECT_THAT(folder.ReadFile(u"a.txt"), Eq("REP x REP\r\nnone\r\n"));
}

//! O(バックアップ): 一致しないファイルは、既にある .skrold を消さず、上書きもしない
TEST_F(GrepReplaceDetailTest, BackupNoHitKeepsOldBackup)
{
	folder.AddFile(u"a.txt", "HIT\r\n");
	folder.AddFile(u"b.txt", "none\r\n");
	folder.AddFile(u"b.txt.skrold", "keep\r\n");
	EXPECT_THAT(Grep(u"HIT", u"*.txt", u"XO", { .replace = u"REP" }), Eq(1u));
	EXPECT_THAT(folder.ReadFile(u"a.txt"), Eq("REP\r\n"));
	EXPECT_THAT(folder.ReadFile(u"a.txt.skrold"), Eq("HIT\r\n"));
	EXPECT_THAT(folder.ReadFile(u"b.txt"), Eq("none\r\n"));
	EXPECT_THAT(folder.ReadFile(u"b.txt.skrold"), Eq("keep\r\n"));
}

//! 単語単位: 検索語が 2 つの単語なら、どちらの単語も置換する
TEST_F(GrepReplaceDetailTest, WordOnlyMultipleWordsKey)
{
	folder.AddFile(u"w.txt", "foo bar baz foobar\r\n");
	EXPECT_THAT(Grep(u"foo bar", u"w.txt", u"XW", { .replace = u"X" }), Eq(2u));
	EXPECT_THAT(folder.ReadFile(u"w.txt"), Eq("X X baz foobar\r\n"));
}

//! S(サブフォルダー) + O: サブフォルダーのファイルも置換してバックアップを作る。一致しないファイルには何も作らない
TEST_F(GrepReplaceDetailTest, SubFoldersWithBackup)
{
	folder.AddFile(u"a.txt", "HIT\r\n");
	folder.AddFile(u"sub/b.txt", "HIT\r\n");
	folder.AddFile(u"sub/deep/c.txt", "none\r\n");
	EXPECT_THAT(Grep(u"HIT", u"*.txt", u"XSO", { .replace = u"REP" }), Eq(2u));
	EXPECT_THAT(folder.ReadFile(u"a.txt"), Eq("REP\r\n"));
	EXPECT_THAT(folder.ReadFile(u"sub/b.txt"), Eq("REP\r\n"));
	EXPECT_THAT(folder.ReadFile(u"sub/b.txt.skrold"), Eq("HIT\r\n"));
	EXPECT_THAT(folder.Exists(u"sub/deep/c.txt.skrold"), IsFalse());
}

//! 文字コード固定の UTF-16LE(BOM なし): BOM を付けずに書き戻す
TEST_F(GrepReplaceDetailTest, Utf16WithoutBom)
{
	folder.AddFile(u"u.txt", std::string("H\0I\0T\0\r\0\n\0", 10));
	EXPECT_THAT(Grep(u"HIT", u"u.txt", u"X", { .replace = u"REP", .code = int(CODE_UNICODE) }), Eq(1u));
	EXPECT_THAT(folder.ReadFile(u"u.txt"), Eq(std::string("R\0E\0P\0\r\0\n\0", 10)));
}

//! ファイルの文字コード(SJIS)に無い文字で置換すると、「?」になる（【現状の制限】変換できなかったことは結果に出ない）
TEST_F(GrepReplaceDetailTest, ReplacementNotInCharset)
{
	folder.AddFile(u"s.txt", "HIT\r\n");
	EXPECT_THAT(Grep(u"HIT", u"s.txt", u"X", { .replace = u"\U0001F600", .code = int(CODE_SJIS) }), Eq(1u));
	EXPECT_THAT(folder.ReadFile(u"s.txt"), Eq("?\r\n"));
}

//! 10MB を超えるファイル: 最初の一致より前の行が 10MB を超えると、一致の前に書き出し始める
TEST_F(GrepReplaceDetailTest, LargeFileFlushesBuffer)
{
	const std::string line = std::string(98, 'x') + "\r\n";
	constexpr size_t lineCount = 105000;
	std::string data;
	data.reserve(line.size() * lineCount + 5);
	for (size_t i = 0; i < lineCount; ++i) {
		data += line;
	}
	folder.AddFile(u"large.txt", data + "HIT\r\n");

	EXPECT_THAT(Grep(u"HIT", u"large.txt", u"X", { .replace = u"REP" }), Eq(1u));
	const auto result = folder.ReadFile(u"large.txt");
	EXPECT_THAT(result.size(), Eq(data.size() + 5));
	EXPECT_THAT(result.ends_with(line + "REP\r\n"), IsTrue());
	EXPECT_THAT(result.compare(0, data.size(), data), Eq(0));
}

//! O(バックアップ): 読み取り専用のファイルも、元のファイルを .skrold に移せるので置換できる
TEST_F(GrepReplaceDetailTest, ReadOnlyFileWithBackup)
{
	folder.AddFile(u"ro.txt", "HIT\r\n", FILE_ATTRIBUTE_READONLY);
	EXPECT_THAT(Grep(u"HIT", u"ro.txt", u"XO", { .replace = u"REP" }), Eq(1u));
	EXPECT_THAT(folder.ReadFile(u"ro.txt"), Eq("REP\r\n"));
	EXPECT_THAT(folder.ReadFile(u"ro.txt.skrold"), Eq("HIT\r\n"));
}

// ---------------------------------------------------------------------------
// 除外ファイルの正規表現(-GOPT=E)
// ---------------------------------------------------------------------------

//! E: フルパスで照合し、サブフォルダーにも効き、大文字小文字を区別しない。結果の条件表示に出る（区切りは /）
TEST_F(GrepCommandLineTest, ExceptFileRegexp)
{
	folder.AddFile(u"a.txt", "HIT\r\n");
	folder.AddFile(u"README", "HIT\r\n");
	folder.AddFile(u"app.log", "HIT\r\n");
	folder.AddFile(u"app.20260801.log", "HIT\r\n");
	folder.AddFile(u"sub/readme", "HIT\r\n");
	const Text files = uR"(*;!/[^./]+$;!/APP\.\d{8}\.log$)";
	EXPECT_THAT(Grep(u"HIT", files, u"XSE"), Eq(2u));
	const auto text = GetDocumentText();
	EXPECT_THAT(LineContaining(text, u"a.txt("), ::testing::Not(IsEmpty()));
	EXPECT_THAT(LineContaining(text, u"app.log("), ::testing::Not(IsEmpty()));
	EXPECT_THAT(LineContaining(text, u"app.20260801.log("), IsEmpty());
	EXPECT_THAT(Contains(text, LS(STR_GREP_EXCLUDE_FILE_REGEXP)), IsTrue());

	// E が無ければワイルドカードとして扱われ、何も除外されない
	ResetDocument();
	EXPECT_THAT(Grep(u"HIT", uR"(*;!/[^./]+$)", u"XS"), Eq(5u));
}

//! E: 区切り文字を含む正規表現は引用符で囲む
TEST_F(GrepCommandLineTest, ExceptFileRegexpQuoted)
{
	folder.AddFile(u"a1.txt", "HIT\r\n");
	folder.AddFile(u"a12.txt", "HIT\r\n");
	folder.AddFile(u"a123.txt", "HIT\r\n");
	EXPECT_THAT(Grep(u"HIT", uR"(*;!"/a\d{2,3}\.txt$")", u"XE"), Eq(1u));
}

//! E: 正しくない正規表現はエラーメッセージを出して何もしない
TEST_F(GrepCommandLineTest, ExceptFileRegexpInvalid)
{
	folder.AddFile(u"a.txt", "HIT\r\n");
	EXPECT_THAT(Grep(u"HIT", u"*;!^[a$", u"XE"), Eq(0u));
	EXPECT_THAT(lastError, StartsWith(LS(STR_GREP_ERR_EXCLUDE_REGEXP)));
	EXPECT_THAT(LineContaining(GetDocumentText(), u"a.txt("), IsEmpty());
}

// ---------------------------------------------------------------------------
// 編集中のテキストから検索(:HWND:)
// ---------------------------------------------------------------------------

/*!
	@brief 編集中のテキストから検索のテスト（原版は別のウィンドウ。Mac 版は GrepSourceText）

	文書のファイル名はテストのフォルダーの doc.txt にする(ファイルは作らない。作るテストは明記する)。
*/
struct GrepHwndTargetTest : public GrepOutputSnapshotTest {
	Text DocPath() const { return folder.PathOf(u"doc.txt"); }

	static GrepSourceText Source(Text path, std::vector<Text> lines, ECodeType charCode = CODE_UTF8)
	{
		GrepSourceText source;
		source.id = 0x1234abcd;
		source.filePath = std::move(path);
		source.windowLabel = u"(無題)1";
		source.encoding = charCode;
		source.lines = std::move(lines);
		return source;
	}

	//! 文書を検索して結果の文字を返す（-GOPT に XH を足す）
	Text GrepSource(const GrepSourceText& source, const Text& key, std::u16string_view opt, DWORD* pHitCount = nullptr, const Extra& extra = {})
	{
		ResetDocument();
		const auto hitCount = RunGrep(MakeOptions(key, GrepSourceToken(source.id), u"", Text(u"XH") + Text(opt), extra), { source });
		if (pHitCount) {
			*pHitCount = hitCount;
		}
		return GetDocumentText();
	}
};

//! 文書の各行を検索する。結果のパスは文書のファイル名
TEST_F(GrepHwndTargetTest, SearchesWindowText)
{
	const auto source = Source(DocPath(), { u"alpha HIT one\r\n", u"bravo two\r\n", u"HIT x HIT\r\n" });
	const auto path = DocPath();
	DWORD hitCount = 0;
	EXPECT_THAT(GrepSource(source, u"HIT", u"1", &hitCount), Eq(path + u"(1,7): HIT\r\n" + path + u"(3,1): HIT\r\n" + path + u"(3,7): HIT\r\n"));
	EXPECT_THAT(hitCount, Eq(3u));
}

//! 同じ名前のファイルがあっても、ファイルではなく文書の内容を検索する
TEST_F(GrepHwndTargetTest, ReadsWindowNotFile)
{
	folder.AddFile(u"doc.txt", "none\r\n");
	const auto source = Source(DocPath(), { u"alpha HIT one\r\n" });
	EXPECT_THAT(GrepSource(source, u"HIT", u"1"), Eq(DocPath() + u"(1,7): HIT\r\n"));
}

//! 該当行(P): CRLF・LF・CR・改行なし(最後の行)のどれでも、改行コードを除いて出力する
TEST_F(GrepHwndTargetTest, LineEndings)
{
	const auto source = Source(DocPath(), { u"a HIT\r\n", u"b HIT\n", u"c HIT\r", u"d HIT" });
	const auto path = DocPath();
	EXPECT_THAT(GrepSource(source, u"HIT", u"1P"), Eq(path + u"(1,3): a HIT\r\n" + path + u"(2,3): b HIT\r\n" + path + u"(3,3): c HIT\r\n" + path + u"(4,3): d HIT\r\n"));
}

//! ベースフォルダー(B)・フォルダー毎(D)の見出しは、文書のフォルダーで出す
TEST_F(GrepHwndTargetTest, FolderHeaders)
{
	const auto source = Source(DocPath(), { u"alpha HIT one\r\n" });
	const auto dir = folder.PathText();
	const Text line = u"・doc.txt(1,7): alpha HIT one\r\n";
	EXPECT_THAT(GrepSource(source, u"HIT", u"1PB"), Eq(u"■\"" + dir + u"\"\r\n" + line));
	EXPECT_THAT(GrepSource(source, u"HIT", u"1PD"), Eq(u"■\"" + dir + u"\"\r\n" + line));
	EXPECT_THAT(GrepSource(source, u"HIT", u"1PBD"), Eq(u"◎\"" + dir + u"\"\r\n■\r\n" + line));
}

//! 自動判別(K)のときは、文書の文字コードを結果に付ける
TEST_F(GrepHwndTargetTest, CodeNameFromWindow)
{
	const auto source = Source(DocPath(), { u"alpha HIT one\r\n" }, CODE_EUC);
	EXPECT_THAT(GrepSource(source, u"HIT", u"1K"), Eq(DocPath() + u"(1,7)" + CodeBracket(CODE_EUC) + u": HIT\r\n"));
}

//! 検索キーが空なら、文書を読まずにファイル名だけを出して 1 件と数える
TEST_F(GrepHwndTargetTest, EmptyKeyListsDocumentName)
{
	const auto source = Source(DocPath(), { u"alpha HIT one\r\n" });
	DWORD hitCount = 0;
	EXPECT_THAT(GrepSource(source, u"", u"1", &hitCount), Eq(DocPath() + u"\r\n"));
	EXPECT_THAT(hitCount, Eq(1u));
}

//! 空の文書(0 行)は 0 件で、何も出さない
TEST_F(GrepHwndTargetTest, EmptyDocument)
{
	const auto source = Source(DocPath(), {});
	DWORD hitCount = 1;
	EXPECT_THAT(GrepSource(source, u"HIT", u"1", &hitCount), IsEmpty());
	EXPECT_THAT(hitCount, Eq(0u));
}

//! 一致しない文書は 0 件で、何も出さない
TEST_F(GrepHwndTargetTest, NoHit)
{
	const auto source = Source(DocPath(), { u"alpha one\r\n", u"bravo two\r\n" });
	DWORD hitCount = 1;
	EXPECT_THAT(GrepSource(source, u"HIT", u"1", &hitCount), IsEmpty());
	EXPECT_THAT(hitCount, Eq(0u));
}

//! 長い行も 1 行として検索する（原版は共有のワークバッファーごとに分けて読んでつなぐ）
TEST_F(GrepHwndTargetTest, KeyAcrossWorkBuffer)
{
	const size_t work = 0x10000;
	const Text longLine = Text(work - 1, u'x') + u"HIT" + Text(work, u'y') + u"HIT\r\n";
	const auto source = Source(DocPath(), { longLine });
	const auto path = DocPath();
	const Text expected = path + sakura::u16::from_utf8(std::format("({},{}): HIT\r\n", 1, work)) + path + sakura::u16::from_utf8(std::format("({},{}): HIT\r\n", 1, work * 2 + 3));
	DWORD hitCount = 0;
	EXPECT_THAT(GrepSource(source, u"HIT", u"1", &hitCount), Eq(expected));
	EXPECT_THAT(hitCount, Eq(2u));
}

//! 置換を指定しても、文書では検索だけを行い、文書と同じ名前のファイルを書き換えない
TEST_F(GrepHwndTargetTest, ReplaceOnlySearches)
{
	folder.AddFile(u"doc.txt", "HIT\r\n");
	const auto source = Source(DocPath(), { u"HIT a\r\n", u"HIT b\r\n" });
	DWORD hitCount = 0;
	GrepSource(source, u"HIT", u"", &hitCount, { .replace = u"REP" });
	EXPECT_THAT(hitCount, Eq(2u));
	EXPECT_THAT(folder.ReadFile(u"doc.txt"), Eq("HIT\r\n"));
	EXPECT_THAT(folder.Exists(u"doc.txt.skrold"), IsFalse());
}

//! 無題の文書: 結果のパスは「:HWND:[番号]ウィンドウ一覧の名前」（タグジャンプで文書のウィンドウに戻る）
TEST_F(GrepHwndTargetTest, UntitledDocument)
{
	const auto source = Source(u"", { u"alpha HIT one\r\n" });
	EXPECT_THAT(GrepSource(source, u"HIT", u"1"), Eq(Text(u":HWND:[000000001234abcd](無題)1(1,7): HIT\r\n")));
	// Grep の結果の文書は (Grep) と表示する
	auto grep = source;
	grep.isGrep = true;
	EXPECT_THAT(GrepSource(grep, u"HIT", u"1"), Eq(Text(u":HWND:[000000001234abcd](Grep)(1,7): HIT\r\n")));
	// 見出し(H なし)の「検索対象」は Window:[名前]
	ResetDocument();
	RunGrep(MakeOptions(u"HIT", GrepSourceToken(source.id), u"", u"X"), { source });
	EXPECT_THAT(Contains(GetDocumentText(), Text(LS(STR_GREP_SEARCH_TARGET)) + u"Window:[(無題)1]"), IsTrue());
}

//! :HWND: の後ろが 16 進でなければ、0 件で結果にエラーを出す
TEST_F(GrepHwndTargetTest, NonHexHandle)
{
	EXPECT_THAT(Grep(u"HIT", u":HWND:zz", u"X"), Eq(0u));
	EXPECT_THAT(Contains(GetDocumentText(), u"HWND handle error."), IsTrue());
}

//! 閉じた文書（渡されていない番号）は受け付けない
TEST_F(GrepHwndTargetTest, ClosedWindow)
{
	const auto source = Source(DocPath(), { u"HIT\r\n" });
	EXPECT_THAT(RunGrep(MakeOptions(u"HIT", GrepSourceToken(source.id + 1), u"", u"X"), { source }), Eq(0u));
	EXPECT_THAT(Contains(GetDocumentText(), u"HWND handle error."), IsTrue());
}

// ---------------------------------------------------------------------------
// 中断と進み具合の表示
// ---------------------------------------------------------------------------

/*!
	@brief テスト用の中断の確認と進み具合の表示（原版と同じ）
*/
class FakeGrepProgress : public IGrepProgress {
public:
	explicit FakeGrepProgress(int cancelAt = 0, bool checkTime = true) : m_cancelAt(cancelAt), m_checkTime(checkTime) {}
	bool IsCheckTime() override { return m_checkTime; }
	bool IsFileNameTime() override { return true; }
	bool IsCancelRequested() override
	{
		++checkCount;
		return 0 < m_cancelAt && m_cancelAt <= checkCount;
	}
	void ApplyRealTimeView() override { ++applyCount; }
	void SetHitCount(int nHitCount) override { hitCounts.push_back(nHitCount); }
	void SetFileName(sakura::wstring_view fileName) override { fileNames.emplace_back(fileName); }
	void SetFolder(sakura::wstring_view folder) override { folders.emplace_back(folder); }

	int checkCount = 0;
	int applyCount = 0;
	std::vector<int> hitCounts;
	std::vector<Text> fileNames;
	std::vector<Text> folders;

private:
	const int m_cancelAt;
	const bool m_checkTime;
};

/*!
	@brief テスト用の結果の出力先（原版と同じ）
*/
class FakeGrepOutput : public IGrepOutputTarget {
public:
	void Append(const CNativeW& cmem) override
	{
		chunks.emplace_back(cmem.GetStringPtr(), size_t(cmem.GetStringLength()));
		std::this_thread::sleep_for(appendDelay);
	}
	bool IsDrawing() const override { return drawing; }
	Text Text_() const
	{
		Text text;
		for (const auto& chunk : chunks) text += chunk;
		return text;
	}
	size_t ChunkOf(std::u16string_view text) const
	{
		const auto it = std::ranges::find_if(chunks, [text](const Text& chunk) { return chunk.find(text) != Text::npos; });
		return size_t(it - chunks.cbegin());
	}

	std::vector<Text> chunks;
	bool drawing = false;
	std::chrono::milliseconds appendDelay{ 0 };
};

struct GrepProgressTest : public GrepCommandLineTest {
	//! progress を渡して Grep を実行する（結果は文書に足す）
	DWORD GrepWith(FakeGrepProgress& progress, const Text& key, const Text& file, std::u16string_view opt, const Extra& extra = {})
	{
		FakeGrepOutput output;
		TestResultView view;
		CGrepAgent agent;
		const DWORD hits = agent.DoGrep(&view, ToGrepInfo(Options(key, file, opt, extra)), &progress, &output);
		document += output.Text_();
		return hits;
	}

	void AddLinesFile(const Text& relPath, int lineCount) const
	{
		std::string data;
		for (int i = 0; i < lineCount; ++i) {
			data += "HIT\r\n";
		}
		folder.AddFile(relPath, data);
	}
};

//! 最初のファイルの前に中断すると、どのファイルも探さず「中断しました」を出す
TEST_F(GrepProgressTest, CancelBeforeFirstFile)
{
	AddBasicFiles();
	FakeGrepProgress progress(1);
	EXPECT_THAT(GrepWith(progress, u"HIT", u"*.txt", u"X"), Eq(0u));
	const auto text = GetDocumentText();
	EXPECT_THAT(Contains(text, LS(STR_GREP_SUSPENDED)), IsTrue());
	EXPECT_THAT(Contains(text, u"a.txt"), IsFalse());
}

//! 2 つ目のファイルの前に中断すると、1 つ目のファイルの結果だけが残る
TEST_F(GrepProgressTest, CancelBetweenFiles)
{
	folder.AddFile(u"a.txt", "HIT\r\n");
	folder.AddFile(u"b.txt", "HIT\r\n");
	FakeGrepProgress progress(3);
	EXPECT_THAT(GrepWith(progress, u"HIT", u"*.txt", u"X"), Eq(1u));
	const auto text = GetDocumentText();
	EXPECT_THAT(Contains(text, LS(STR_GREP_SUSPENDED)), IsTrue());
	EXPECT_THAT(Contains(text, u"a.txt"), IsTrue());
	EXPECT_THAT(Contains(text, u"b.txt"), IsFalse());
	EXPECT_THAT(progress.checkCount, Eq(3));
}

//! ファイルの途中(32 行目)で中断すると、その前の 31 行の結果が残る
TEST_F(GrepProgressTest, CancelInsideFile)
{
	AddLinesFile(u"many.txt", 64);
	FakeGrepProgress progress(3);
	EXPECT_THAT(GrepWith(progress, u"HIT", u"many.txt", u"X"), Eq(31u));
	EXPECT_THAT(Contains(GetDocumentText(), LS(STR_GREP_SUSPENDED)), IsTrue());
}

//! サブフォルダーに入る前に中断すると、サブフォルダーは探さない
TEST_F(GrepProgressTest, CancelBeforeSubFolder)
{
	AddBasicFiles();
	FakeGrepProgress progress(5);
	EXPECT_THAT(GrepWith(progress, u"HIT", u"*.txt", u"XS"), Eq(3u));
	const auto text = GetDocumentText();
	EXPECT_THAT(Contains(text, LS(STR_GREP_SUSPENDED)), IsTrue());
	EXPECT_THAT(Contains(text, u"d.txt"), IsFalse());
}

//! Grep 置換をファイルの途中(2 行目)で中断すると、1 行目は数えるが、ファイルは書き換えず、一時ファイルも残さない
TEST_F(GrepProgressTest, CancelReplaceKeepsFile)
{
	folder.AddFile(u"r.txt", "HIT\r\nHIT\r\n");
	FakeGrepProgress progress(4);
	EXPECT_THAT(GrepWith(progress, u"HIT", u"r.txt", u"X", { .replace = u"REP" }), Eq(1u));
	EXPECT_THAT(folder.ReadFile(u"r.txt"), Eq("HIT\r\nHIT\r\n"));
	EXPECT_THAT(folder.Exists(u"r.txt.skrnew"), IsFalse());
	EXPECT_THAT(Contains(GetDocumentText(), LS(STR_GREP_SUSPENDED)), IsTrue());
}

//! ファイル名だけを返す(検索キーが空)ときは、ファイルごとにヒット数を表示する。最後はファイル名を消す
TEST_F(GrepProgressTest, ShowsHitCountOfFileList)
{
	AddBasicFiles();
	FakeGrepProgress progress;
	EXPECT_THAT(GrepWith(progress, u"", u"*.txt", u"X"), Eq(2u));
	EXPECT_THAT(progress.hitCounts, ::testing::ElementsAre(1, 2));
	ASSERT_THAT(progress.fileNames, ::testing::SizeIs(3));
	EXPECT_THAT(progress.fileNames.back(), Eq(u" "));
}

//! ファイルの途中では、32 行ごとにリアルタイム表示を反映し、ファイル名・ヒット数・フォルダーを表示する
TEST_F(GrepProgressTest, ShowsProgressInsideFile)
{
	AddLinesFile(u"many.txt", 64);
	FakeGrepProgress progress;
	EXPECT_THAT(GrepWith(progress, u"HIT", u"many.txt", u"X"), Eq(64u));
	EXPECT_THAT(progress.checkCount, Eq(4));
	EXPECT_THAT(progress.applyCount, Eq(3));
	EXPECT_THAT(progress.hitCounts, ::testing::ElementsAre(31, 63));
	EXPECT_THAT(progress.fileNames, ::testing::ElementsAre(u"many.txt", u"many.txt", u"many.txt", u" "));
	EXPECT_THAT(progress.folders, ::testing::SizeIs(2));
}

//! 5MB を超えるファイルでは、読んだ割合をファイル名に付けて表示する(Grep・Grep 置換とも)
TEST_F(GrepProgressTest, ShowsReadPercentOfLargeFile)
{
	const std::string line = std::string(94, 'x') + " HIT\r\n";
	constexpr size_t lineCount = 60000;
	std::string data;
	data.reserve(line.size() * lineCount);
	for (size_t i = 0; i < lineCount; ++i) {
		data += line;
	}
	folder.AddFile(u"large.txt", data);

	const auto startsWithLarge = [](const std::vector<Text>& names) {
		return std::ranges::any_of(names, [](const Text& n) { return n.starts_with(u"large.txt ("); });
	};
	FakeGrepProgress grep;
	EXPECT_THAT(GrepWith(grep, u"HIT", u"large.txt", u"XN"), Eq(0u));
	EXPECT_THAT(startsWithLarge(grep.fileNames), IsTrue());

	FakeGrepProgress replace;
	EXPECT_THAT(GrepWith(replace, u"NOHIT", u"large.txt", u"X", { .replace = u"REP" }), Eq(0u));
	EXPECT_THAT(startsWithLarge(replace.fileNames), IsTrue());
}

//! 確かめる時機でなければ、中断の確認もリアルタイム表示の反映も進み具合の表示もしない(Grep 置換のファイルを開いた後だけは時機を見ずに確かめる)
TEST_F(GrepProgressTest, SkipsCheckUntilCheckTime)
{
	AddLinesFile(u"many.txt", 64);

	FakeGrepProgress grep(1, false);
	EXPECT_THAT(GrepWith(grep, u"HIT", u"many.txt", u"X"), Eq(64u));
	EXPECT_THAT(grep.checkCount, Eq(0));
	EXPECT_THAT(grep.applyCount, Eq(0));
	EXPECT_THAT(grep.hitCounts, IsEmpty());

	FakeGrepProgress replace(1, false);
	EXPECT_THAT(GrepWith(replace, u"HIT", u"many.txt", u"X", { .replace = u"REP" }), Eq(0u));
	EXPECT_THAT(replace.checkCount, Eq(1));
	EXPECT_THAT(Contains(GetDocumentText(), LS(STR_GREP_SUSPENDED)), IsTrue());
}

//! サブフォルダーから戻ると、元のフォルダーを表示する
TEST_F(GrepProgressTest, ShowsFolderAfterSubFolder)
{
	AddBasicFiles();
	FakeGrepProgress progress;
	EXPECT_THAT(GrepWith(progress, u"HIT", u"*.txt", u"XS"), Eq(4u));
	ASSERT_THAT(progress.folders, ::testing::SizeIs(1));
	EXPECT_THAT(progress.folders[0].ends_with(u"GrepProgressTest.ShowsFolderAfterSubFolder"), IsTrue());
}

//! GrepSession: 中断すると「中断しました」を出し、cancelled になる（原版の「キャンセル」ボタン）
TEST_F(GrepProgressTest, SessionCancel)
{
	AddLinesFile(u"many.txt", 64);
	GrepSession session(Options(u"HIT", u"many.txt", u"X"));
	session.Cancel();
	const auto result = session.Run();
	EXPECT_THAT(result.cancelled, IsTrue());
	EXPECT_THAT(result.hitCount, Eq(0));
	EXPECT_THAT(Contains(session.TakeOutput(), LS(STR_GREP_SUSPENDED)), IsTrue());
}

//! GrepSession: 別のスレッドで実行し、進み具合と結果をこのスレッドから取り出せる
TEST_F(GrepProgressTest, SessionOnAnotherThread)
{
	for (int i = 0; i < 20; ++i) {
		AddLinesFile(sakura::u16::from_utf8(std::format("f{:02}.txt", i)), 2000);
	}
	GrepSession session(Options(u"HIT", u"*.txt", u"XP"));
	GrepResult result;
	std::thread thread([&] { result = session.Run(); });
	Text text;
	while (!thread.joinable() || session.IsRunning() || text.empty()) {
		text += session.TakeOutput();
		(void)session.Progress();
		if (!session.IsRunning() && !text.empty()) break;
		std::this_thread::sleep_for(std::chrono::milliseconds(1));
	}
	thread.join();
	text += session.TakeOutput();
	EXPECT_THAT(result.hitCount, Eq(40000));
	EXPECT_THAT(result.cancelled, IsFalse());
	EXPECT_THAT(Contains(text, MatchCountText(40000)), IsTrue());
	EXPECT_THAT(session.Progress().hitCount, Ge(0));
}

// ---------------------------------------------------------------------------
// 結果の出力先
// ---------------------------------------------------------------------------

struct GrepOutputTargetTest : public GrepCommandLineTest {
	DWORD GrepTo(FakeGrepOutput& output, const GrepOptions& options, IGrepProgress* progress = nullptr)
	{
		FakeGrepProgress defaultProgress;
		TestResultView view;
		CGrepAgent agent;
		return agent.DoGrep(&view, ToGrepInfo(options), progress ? progress : &defaultProgress, &output);
	}
};

//! 見出し・結果・件数は、すべて出力先に足され、結果の文書には足されない
TEST_F(GrepOutputTargetTest, AppendsAllToTarget)
{
	AddBasicFiles();
	FakeGrepOutput output;
	EXPECT_THAT(GrepTo(output, Options(u"HIT", u"*.txt", u"XS")), Eq(4u));
	EXPECT_THAT(GetDocumentText(), IsEmpty());
	const auto text = output.Text_();
	EXPECT_THAT(Contains(text, LS(STR_GREP_SEARCH_CONDITION)), IsTrue());
	EXPECT_THAT(Contains(text, u"d.txt"), IsTrue());
	EXPECT_THAT(Contains(text, MatchCountText(4)), IsTrue());
}

//! 出力先に足される文字列は、結果の文書（GrepSession）に足される文字列と同じ
TEST_F(GrepOutputTargetTest, SameTextAsDocument)
{
	AddBasicFiles();
	FakeGrepOutput output;
	EXPECT_THAT(GrepTo(output, Options(u"HIT", u"*.txt", u"XSP")), Eq(3u));
	EXPECT_THAT(Grep(u"HIT", u"*.txt", u"XSP"), Eq(3u));
	EXPECT_THAT(output.Text_(), Eq(GetDocumentText()));
}

/*!
	リアルタイム表示で、検索したファイルの合計が 10000KB を超えたら、ヒット数によらず早めに出力する。
	（原版は b2 を共有しないで開いて開けなくする。Mac 版は読む権限を外す）
*/
TEST_F(GrepOutputTargetTest, FlushesEarlyAfterLargeFile)
{
	folder.AddFile(u"a1.txt", "HIT\r\n");
	folder.AddFile(u"b2.txt", "HIT\r\n");
	folder.AddFile(u"c3.txt", "HIT\r\n");
	folder.AddFile(u"d4.txt", "HIT\r\n");
	const auto path = folder.Path().fs() / "b2.txt";
	fs::resize_file(path, 10001 * 1024);
	ASSERT_THAT(::chmod(path.c_str(), 0), Eq(0));

	const auto options = Options(u"HIT", u"*.txt", u"X");
	FakeGrepOutput notDrawing;
	notDrawing.appendDelay = std::chrono::milliseconds(100);
	EXPECT_THAT(GrepTo(notDrawing, options), Eq(3u));
	FakeGrepOutput drawing;
	drawing.drawing = true;
	drawing.appendDelay = std::chrono::milliseconds(100);
	EXPECT_THAT(GrepTo(drawing, options), Eq(3u));

	const auto openError = ResourcePrefix(STR_GREP_ERR_FILEOPEN);
	ASSERT_THAT(drawing.ChunkOf(openError), Lt(drawing.chunks.size()));
	EXPECT_THAT(notDrawing.ChunkOf(openError), Eq(notDrawing.ChunkOf(u"c3.txt")));
	EXPECT_THAT(drawing.ChunkOf(openError), Lt(drawing.ChunkOf(u"c3.txt")));
	EXPECT_THAT(drawing.ChunkOf(u"c3.txt"), Eq(drawing.ChunkOf(u"d4.txt")));
	EXPECT_THAT(drawing.Text_(), Eq(notDrawing.Text_()));
}

//! 中断したときの「中断しました」も出力先に足される
TEST_F(GrepOutputTargetTest, SuspendedMessageToTarget)
{
	AddBasicFiles();
	FakeGrepOutput output;
	FakeGrepProgress progress(1);
	EXPECT_THAT(GrepTo(output, Options(u"HIT", u"*.txt", u"X"), &progress), Eq(0u));
	EXPECT_THAT(Contains(output.Text_(), LS(STR_GREP_SUSPENDED)), IsTrue());
	EXPECT_THAT(GetDocumentText(), IsEmpty());
}

//! 無効な :HWND: のエラーも出力先に足される
TEST_F(GrepOutputTargetTest, HwndErrorToTarget)
{
	FakeGrepOutput output;
	EXPECT_THAT(GrepTo(output, Options(u"HIT", u":HWND:0", u"X")), Eq(0u));
	EXPECT_THAT(Contains(output.Text_(), u"HWND handle error."), IsTrue());
	EXPECT_THAT(GetDocumentText(), IsEmpty());
}

/*!
	大文字小文字を区別しない比較の変換（skr_towlower・skr_towupper）は Windows 版と同じ（Mac 版で追加）

	Mac の towlower は C ロケールでは ASCII しか変換しないので、全角英字などが一致しなかった（FullWidthIgnoreCase で分かった）。
	c < 256 は Windows 版の変換テーブル（0x80-0x9F は無変換、µ は無変換、ÿ の大文字は Ÿ）と同じ。
*/
TEST(GrepCaseFolding, SameAsWindows)
{
	EXPECT_THAT(skr_towlower(u'Ａ'), Eq(int(u'ａ')));
	EXPECT_THAT(skr_towupper(u'ｚ'), Eq(int(u'Ｚ')));
	EXPECT_THAT(skr_towlower(u'Ω'), Eq(int(u'ω')));
	EXPECT_THAT(skr_towlower(u'Ж'), Eq(int(u'ж')));
	EXPECT_THAT(skr_towupper(0xE0), Eq(0xC0));		// à → À
	EXPECT_THAT(skr_towlower(0xC0), Eq(0xE0));
	EXPECT_THAT(skr_towupper(0xF7), Eq(0xF7));		// ÷
	EXPECT_THAT(skr_towupper(0xB5), Eq(0xB5));		// µ（Windows-1252 に大文字が無い）
	EXPECT_THAT(skr_towupper(0xFF), Eq(0x178));		// ÿ → Ÿ
	EXPECT_THAT(skr_towupper(0x85), Eq(0x85));		// 制御コード
	EXPECT_THAT(skr_towupper(u'a'), Eq(int(u'A')));
	EXPECT_THAT(skr_towlower(u'あ'), Eq(int(u'あ')));
	EXPECT_THAT(skr_towlower(0xD842), Eq(0xD842));	// サロゲート
}

//! 結果の文書のタイプは「grepout」の拡張子のタイプ（無ければ基本）
TEST(GrepOutputType, IndexOfGrepout)
{
	ASSERT_TRUE(Startup());
	const auto index = GrepOutputTypeIndex();
	EXPECT_THAT(index, Eq(CDocTypeManager().GetDocumentTypeOfExt(u"grepout").GetIndex()));
	EXPECT_THAT(GrepSourceToken(0x1234abcd), Eq(u":HWND:000000001234abcd"));
	Shutdown(false);
}

} // namespace grep_test

// ---------------------------------------------------------------------------
// Windows 版との対照（计划第 43 步）
// ---------------------------------------------------------------------------
namespace grep_test {

/*!
	data/grep/cases.txt の条件で data/grep/tree/ を Grep し、結果を data/grep/expected/<名前>.txt と比べる。
	CI の grep-windows は Windows 官方版 sakura.exe で同じ条件の -GREPMODE を実行し（-GOPT=U の標準出力）、同じ expected と比べる
	（macos/tools/grep/windows-grep.ps1）。両方とも同じなら、Mac 版の Grep の結果は Windows 版と同じ。

	比べる前にそろえるもの（両方とも同じ処理）：
	- 検索したフォルダーの絶対パス → {DIR}（Windows 版はさらにパスの区切りの \ を /）
	- 見出しの正規表現ライブラリの版（「    (正規表現:」から行末まで）→ {VERSION})（Mac 版は bregonig を組み込み、Windows 版は bregonig.dll）
	Grep置換の条件は、置換した後の tree/ の全ファイル（名前の順）の中身を 16 進で後ろに付ける。

	環境変数 SAKURA_GREP_UPDATE=1 のときは比べずに expected を書き出す（更新用）。
*/
class GrepWindowsComparison : public ::testing::TestWithParam<std::vector<Text>> {
public:
	static void SetUpTestSuite() { ASSERT_TRUE(Startup()); }
	static void TearDownTestSuite() { Shutdown(false); }

	static fs::path DataDir() { return fs::path(SAKURA_ROOT_DIR) / "macos" / "core" / "tests" / "data" / "grep"; }

	//! cases.txt の各行（TAB で分けた列）
	static std::vector<std::vector<Text>> Cases()
	{
		std::vector<std::vector<Text>> cases;
		std::ifstream ifs(DataDir() / "cases.txt", std::ios::binary);
		for (std::string line; std::getline(ifs, line); ) {
			if (!line.empty() && line.back() == '\r') line.pop_back();
			if (line.empty() || line[0] == '#') continue;
			std::vector<Text> cols;
			size_t begin = 0;
			for (;;) {
				const size_t tab = line.find('\t', begin);
				cols.push_back(sakura::u16::from_utf8(line.substr(begin, tab == std::string::npos ? std::string::npos : tab - begin)));
				if (tab == std::string::npos) break;
				begin = tab + 1;
			}
			cases.push_back(cols);
		}
		return cases;
	}

	//! 置換した後の全ファイル（相対パスの順。区切りは /）の中身を 16 進で
	static std::string DumpTree(const fs::path& root)
	{
		std::vector<std::pair<std::string, fs::path>> files;
		for (const auto& entry : fs::recursive_directory_iterator(root)) {
			if (entry.is_regular_file()) files.emplace_back(fs::relative(entry.path(), root).generic_string(), entry.path());
		}
		std::ranges::sort(files, [](const auto& a, const auto& b) {
			return sakura::u16::from_utf8(a.first) < sakura::u16::from_utf8(b.first);	// UTF-16 の順（Windows のスクリプトと同じ）
		});
		std::string dump = "----- files -----\n";
		for (const auto& [name, path] : files) {
			std::ifstream ifs(path, std::ios::binary);
			const std::string bytes((std::istreambuf_iterator<char>(ifs)), std::istreambuf_iterator<char>());
			dump += name + ":";
			for (const unsigned char c : bytes) dump += std::format(" {:02X}", c);
			dump += "\n";
		}
		return dump;
	}
};

TEST_P(GrepWindowsComparison, SameAsWindows)
{
	const auto& c = GetParam();
	ASSERT_THAT(c.size(), Ge(5u));
	const std::string name = sakura::u16::to_utf8(std::u16string_view(c[0]));
	const fs::path work = fs::temp_directory_path() / "sakura_grep_cmp" / name;
	std::error_code ec;
	fs::remove_all(work, ec);
	fs::create_directories(work);
	const fs::path tree = work / "tree";
	fs::copy(DataDir() / "tree", tree, fs::copy_options::recursive);
	const Text dir = sakura::path_to_wstring(tree);

	Extra extra;
	if (!c[4].empty()) extra.code = std::stoi(sakura::u16::to_utf8(std::u16string_view(c[4])));
	if (c.size() >= 6) extra.replace = c[5];
	GrepSession session(MakeOptions(c[1], c[2], dir, Text(c[3]), extra));
	const GrepResult result = session.Run();
	EXPECT_THAT(result.errorMessage, IsEmpty());
	Text output = session.TakeOutput();

	// そろえる：フォルダーの絶対パス、正規表現ライブラリの版
	for (size_t pos; (pos = output.find(dir)) != Text::npos; ) {
		output.replace(pos, dir.size(), u"{DIR}");
	}
	const Text regexHead = LS(STR_GREP_REGEX_DLL);
	if (const auto pos = output.find(regexHead); pos != Text::npos) {
		const auto end = output.find_first_of(u"\r\n", pos + regexHead.size());
		output.replace(pos + regexHead.size(), end - pos - regexHead.size(), u"{VERSION})");
	}
	std::string actual = sakura::u16::to_utf8(std::u16string_view(output));
	if (c.size() >= 6) actual += DumpTree(tree);
	fs::remove_all(work, ec);

	const fs::path expectedPath = DataDir() / "expected" / (name + ".txt");
	if (const char* update = std::getenv("SAKURA_GREP_UPDATE"); update && std::string(update) == "1") {
		fs::create_directories(expectedPath.parent_path());
		std::ofstream(expectedPath, std::ios::binary) << actual;
		return;
	}
	std::ifstream ifs(expectedPath, std::ios::binary);
	ASSERT_TRUE(ifs) << "no expected file: " << expectedPath;
	const std::string expected((std::istreambuf_iterator<char>(ifs)), std::istreambuf_iterator<char>());
	EXPECT_THAT(actual, Eq(expected)) << name;
}

INSTANTIATE_TEST_SUITE_P(Cases, GrepWindowsComparison, ::testing::ValuesIn(GrepWindowsComparison::Cases()),
	[](const ::testing::TestParamInfo<std::vector<Text>>& info) { return sakura::u16::to_utf8(std::u16string_view(info.param[0])); });

} // namespace grep_test
