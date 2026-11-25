/*! @file */
/*
	Copyright (C) 2026, Sakura Editor Organization

	SPDX-License-Identifier: Zlib
*/
#include "pch.h"
#include "grep/CGrepEnumKeys.h"
#include "grep/CGrepEnumFiles.h"
#include "grep/CGrepEnumFolders.h"
#include "grep/CGrepEnumFilterFiles.h"
#include "grep/CGrepEnumFilterFolders.h"

#include <filesystem>
#include <fstream>

namespace {

#if defined(_WIN32)
using TestPath = std::filesystem::path;	// Mac 版は tests/pch.h(c_str() などが WCHAR の文字列を返す)
#endif

/*!
	@brief テスト用の一時フォルダー

	%TEMP%\sakura_test_grepenum\<テスト名> に作り、デストラクターで消す。
	読み取り専用などの属性を付けたファイルも消せるよう、削除の前に属性を戻す。
*/
class TempFolder {
public:
	TempFolder()
		: m_path(std::filesystem::temp_directory_path() / LTEXT("sakura_test_grepenum") / ::testing::UnitTest::GetInstance()->current_test_info()->name())
	{
		Remove();
		std::filesystem::create_directories(m_path);
	}

	~TempFolder()
	{
		Remove();
	}

	TempFolder(const TempFolder&) = delete;
	TempFolder& operator=(const TempFolder&) = delete;

	//! ファイルを作る(途中のフォルダーも作る)
	void AddFile(const std::filesystem::path& relPath, DWORD attributes = FILE_ATTRIBUTE_NORMAL) const
	{
		const auto path = m_path / relPath;
		std::filesystem::create_directories(path.parent_path());
		std::ofstream(path) << "x";
		::SetFileAttributesW(path.c_str(), attributes);
	}

	//! フォルダーを作る
	void AddFolder(const std::filesystem::path& relPath) const
	{
		std::filesystem::create_directories(m_path / relPath);
	}

	const TestPath& Path() const noexcept { return m_path; }

private:
	void Remove() const
	{
		std::error_code ec;
		if (std::filesystem::exists(m_path, ec)) {
			for (const auto& entry : std::filesystem::recursive_directory_iterator(m_path, ec)) {
				::SetFileAttributesW(entry.path().c_str(), FILE_ATTRIBUTE_NORMAL);
			}
		}
		std::filesystem::remove_all(m_path, ec);
	}

	TestPath m_path;
};

//! 列挙結果の名前を昇順(符号単位)で返す
std::vector<sakura::wstring> Names(const CGrepEnumFileBase& items)
{
	std::vector<sakura::wstring> names;
	for (int i = 0; i < items.GetCount(); ++i) {
		names.emplace_back(items.GetFileName(i));
	}
	std::ranges::sort(names);
	return names;
}

//! キーの配列を作る
VGrepEnumKeys Keys(std::initializer_list<const WCHAR*> keys)
{
	return VGrepEnumKeys(keys.begin(), keys.end());
}

} // namespace

// ---------------------------------------------------------------------------
// CGrepEnumFiles
// ---------------------------------------------------------------------------

/*!
	@brief ワイルドカードは英大文字小文字を区別せずに一致すること
*/
TEST(CGrepEnumFiles, MatchesWildcardIgnoringCase)
{
	TempFolder folder;
	folder.AddFile(LTEXT("a.txt"));
	folder.AddFile(LTEXT("b.log"));
	folder.AddFile(LTEXT("C.TXT"));

	CGrepEnumFiles files;
	auto keys = Keys({ LTEXT("*.txt") });
	CGrepEnumOptions options;
	EXPECT_THAT(files.Enumerates(folder.Path().c_str(), keys, options), Eq(2));
	EXPECT_THAT(Names(files), Eq(std::vector<sakura::wstring>{ LTEXT("C.TXT"), LTEXT("a.txt") }));
}

/*!
	@brief フォルダーはファイルとして列挙されないこと
*/
TEST(CGrepEnumFiles, SkipsFolders)
{
	TempFolder folder;
	folder.AddFolder(LTEXT("dir.txt"));
	folder.AddFile(LTEXT("a.txt"));

	CGrepEnumFiles files;
	auto keys = Keys({ LTEXT("*.txt") });
	CGrepEnumOptions options;
	files.Enumerates(folder.Path().c_str(), keys, options);
	EXPECT_THAT(Names(files), Eq(std::vector<sakura::wstring>{ LTEXT("a.txt") }));
}

/*!
	@brief 複数のキーに一致しても 1 回だけ列挙されること(大文字小文字違いのキーを含む)
*/
TEST(CGrepEnumFiles, NoDuplicatesAcrossKeys)
{
	TempFolder folder;
	folder.AddFile(LTEXT("a.txt"));

	CGrepEnumFiles files;
	auto keys = Keys({ LTEXT("*.txt"), LTEXT("a.*"), LTEXT("A.TXT") });
	CGrepEnumOptions options;
	EXPECT_THAT(files.Enumerates(folder.Path().c_str(), keys, options), Eq(1));
	EXPECT_THAT(Names(files), Eq(std::vector<sakura::wstring>{ LTEXT("a.txt") }));
}

/*!
	@brief フォルダー部分を含むキーでは、名前にフォルダー部分が付くこと
*/
TEST(CGrepEnumFiles, KeyWithSubFolder)
{
	TempFolder folder;
	folder.AddFile(LTEXT("x.txt"));
#if defined(_WIN32)
	folder.AddFile(LTEXT(R"(sub\x.txt)"));

	CGrepEnumFiles files;
	auto keys = Keys({ LTEXT(R"(sub\*.txt)") });
	CGrepEnumOptions options;
	files.Enumerates(folder.Path().c_str(), keys, options);
	EXPECT_THAT(Names(files), Eq(std::vector<sakura::wstring>{ LTEXT(R"(sub\x.txt)") }));
#else
	// Mac 版: パスの区切りは '/'
	folder.AddFile(LTEXT("sub/x.txt"));

	CGrepEnumFiles files;
	auto keys = Keys({ LTEXT("sub/*.txt") });
	CGrepEnumOptions options;
	files.Enumerates(folder.Path().c_str(), keys, options);
	EXPECT_THAT(Names(files), Eq(std::vector<sakura::wstring>{ LTEXT("sub/x.txt") }));
#endif
}

/*!
	@brief 存在しないフォルダーでは何も列挙されず、エラーにもならないこと
*/
TEST(CGrepEnumFiles, NonexistentFolder)
{
	TempFolder folder;

	CGrepEnumFiles files;
	auto keys = Keys({ LTEXT("*") });
	CGrepEnumOptions options;
	EXPECT_THAT(files.Enumerates((folder.Path() / LTEXT("none")).c_str(), keys, options), Eq(0));
	EXPECT_THAT(files.GetCount(), Eq(0));
}

/*!
	@brief 区切り文字や接頭辞と同じ文字、日本語を含むファイル名も列挙されること
*/
TEST(CGrepEnumFiles, SpecialCharactersInFileName)
{
	TempFolder folder;
	for (const auto name : { LTEXT("a b.txt"), LTEXT("a,b.txt"), LTEXT("a;b.txt"), LTEXT("#x.txt"), LTEXT("!y.txt"), LTEXT("テスト.txt"), LTEXT("x.txt.bak") }) {
		folder.AddFile(name);
	}

	CGrepEnumFiles files;
	auto keys = Keys({ LTEXT("*.txt") });
	CGrepEnumOptions options;
	files.Enumerates(folder.Path().c_str(), keys, options);
	EXPECT_THAT(Names(files), Eq(std::vector<sakura::wstring>{ LTEXT("!y.txt"), LTEXT("#x.txt"), LTEXT("a b.txt"), LTEXT("a,b.txt"), LTEXT("a;b.txt"), LTEXT("テスト.txt") }));
}

/*!
	@brief 短いファイル名(8.3形式)で一致しても、長いファイル名で一致しなければ列挙されないこと

	FindFirstFile は短いファイル名にも一致するが、PathMatchSpec で長いファイル名を確かめ直している。
*/
TEST(CGrepEnumFiles, ShortNameDoesNotMatch)
{
	TempFolder folder;
	folder.AddFile(LTEXT("a.html"));

	CGrepEnumFiles files;
	auto keys = Keys({ LTEXT("*.htm") });
	CGrepEnumOptions options;
	files.Enumerates(folder.Path().c_str(), keys, options);
	EXPECT_THAT(files.GetCount(), Eq(0));
}

/*!
	@brief 隠し・読み取り専用・システムの各属性を、オプションに従って除外すること
*/
TEST(CGrepEnumFiles, AttributeOptions)
{
	TempFolder folder;
	folder.AddFile(LTEXT("n.txt"));
	folder.AddFile(LTEXT("h.txt"), FILE_ATTRIBUTE_HIDDEN);
	folder.AddFile(LTEXT("r.txt"), FILE_ATTRIBUTE_READONLY);
	folder.AddFile(LTEXT("s.txt"), FILE_ATTRIBUTE_SYSTEM);
	auto keys = Keys({ LTEXT("*.txt") });

	{
		CGrepEnumFiles files;
		CGrepEnumOptions options;
		files.Enumerates(folder.Path().c_str(), keys, options);
		EXPECT_THAT(Names(files), Eq(std::vector<sakura::wstring>{ LTEXT("h.txt"), LTEXT("n.txt"), LTEXT("r.txt"), LTEXT("s.txt") }));
	}
	{
		CGrepEnumFiles files;
		CGrepEnumOptions options;
		options.m_bIgnoreHidden = true;
		options.m_bIgnoreReadOnly = true;
		options.m_bIgnoreSystem = true;
		files.Enumerates(folder.Path().c_str(), keys, options);
#if defined(_WIN32)
		EXPECT_THAT(Names(files), Eq(std::vector<sakura::wstring>{ LTEXT("n.txt") }));
#else
		// Mac 版: システム属性は無い(s.txt は普通のファイル)
		EXPECT_THAT(Names(files), Eq(std::vector<sakura::wstring>{ LTEXT("n.txt"), LTEXT("s.txt") }));
#endif
	}
}

// ---------------------------------------------------------------------------
// CGrepEnumFolders
// ---------------------------------------------------------------------------

/*!
	@brief ファイルと「.」「..」はフォルダーとして列挙されないこと
*/
TEST(CGrepEnumFolders, SkipsFilesAndDots)
{
	TempFolder folder;
	folder.AddFolder(LTEXT("a"));
	folder.AddFolder(LTEXT("b"));
	folder.AddFile(LTEXT("c"));

	CGrepEnumFolders folders;
	auto keys = Keys({ LTEXT("*") });
	CGrepEnumOptions options;
	folders.Enumerates(folder.Path().c_str(), keys, options);
	EXPECT_THAT(Names(folders), Eq(std::vector<sakura::wstring>{ LTEXT("a"), LTEXT("b") }));
}

/*!
	@brief 既定のキー「*.*」は「.」を含まない名前のフォルダーにも一致すること

	SetFileKeys() はフォルダーのキーが無いとき「*.*」を入れる。サブフォルダー検索はこれに依存する。
*/
TEST(CGrepEnumFolders, DefaultKeyMatchesNamesWithoutDot)
{
	TempFolder folder;
	folder.AddFolder(LTEXT("src"));
	folder.AddFolder(LTEXT("a.b"));

	CGrepEnumFolders folders;
	auto keys = Keys({ LTEXT("*.*") });
	CGrepEnumOptions options;
	folders.Enumerates(folder.Path().c_str(), keys, options);
	EXPECT_THAT(Names(folders), Eq(std::vector<sakura::wstring>{ LTEXT("a.b"), LTEXT("src") }));
}

// ---------------------------------------------------------------------------
// CGrepEnumFilterFiles / CGrepEnumFilterFolders(除外の組み合わせ)
// ---------------------------------------------------------------------------

/*!
	@brief 除外ファイルのワイルドカードは英大文字小文字を区別しないこと
*/
TEST(CGrepEnumFilterFiles, ExceptWildcardIgnoringCase)
{
	TempFolder folder;
	folder.AddFile(LTEXT("a.txt"));
	folder.AddFile(LTEXT("a.bak"));
	folder.AddFile(LTEXT("b.BAK"));

	CGrepEnumKeys keys;
	ASSERT_THAT(keys.SetFileKeys(LTEXT("*;!*.bak")), Eq(0));
	CGrepEnumFilterFiles files;
	CGrepEnumFiles absExcept;
	files.Enumerates(folder.Path().c_str(), keys, CGrepEnumOptions(), absExcept);
	EXPECT_THAT(Names(files), Eq(std::vector<sakura::wstring>{ LTEXT("a.txt") }));
}

/*!
	@brief 空白を含む除外ファイルは引用符で囲めば除外されること
*/
TEST(CGrepEnumFilterFiles, ExceptQuotedNameWithSpace)
{
	TempFolder folder;
	folder.AddFile(LTEXT("a b.txt"));
	folder.AddFile(LTEXT("c.txt"));

	CGrepEnumKeys keys;
	ASSERT_THAT(keys.SetFileKeys(LTEXT(R"(*;!"a b.txt")")), Eq(0));
	CGrepEnumFilterFiles files;
	CGrepEnumFiles absExcept;
	files.Enumerates(folder.Path().c_str(), keys, CGrepEnumOptions(), absExcept);
	EXPECT_THAT(Names(files), Eq(std::vector<sakura::wstring>{ LTEXT("c.txt") }));
}

/*!
	@brief 引用符で囲んだ「,」を含む除外ファイル・除外フォルダー(ダイアログが組み立てる形)

	Issue #2677 の修正後に Grep ダイアログが渡す「#"obj,old";!"a,b.txt"」を、列挙が正しく扱うこと。
*/
TEST(CGrepEnumFilterFiles, ExceptQuotedNamesWithComma)
{
	TempFolder folder;
	folder.AddFile(LTEXT("a,b.txt"));
	folder.AddFile(LTEXT("b.txt"));
	folder.AddFolder(LTEXT("obj,old"));
	folder.AddFolder(LTEXT("obj"));

	CGrepEnumKeys keys;
	ASSERT_THAT(keys.SetFileKeys(LTEXT(R"(*.txt;#"obj,old";!"a,b.txt")")), Eq(0));
	{
		CGrepEnumFilterFiles files;
		CGrepEnumFiles absExcept;
		files.Enumerates(folder.Path().c_str(), keys, CGrepEnumOptions(), absExcept);
		EXPECT_THAT(Names(files), Eq(std::vector<sakura::wstring>{ LTEXT("b.txt") }));
	}
	{
		CGrepEnumFilterFolders folders;
		CGrepEnumFolders absExcept;
		folders.Enumerates(folder.Path().c_str(), keys, CGrepEnumOptions(), absExcept);
		EXPECT_THAT(Names(folders), Eq(std::vector<sakura::wstring>{ LTEXT("obj") }));
	}
}

/*!
	@brief 【現状の制限】除外ファイルは基準フォルダー直下で列挙されるので、フォルダー部分を含む検索キーで見つかったファイルには効かない
*/
TEST(CGrepEnumFilterFiles, ExceptDoesNotApplyToKeyWithSubFolder)
{
	TempFolder folder;
#if defined(_WIN32)
	folder.AddFile(LTEXT(R"(sub\x.bak)"));

	CGrepEnumKeys keys;
	ASSERT_THAT(keys.SetFileKeys(LTEXT(R"(sub\*;!*.bak)")), Eq(0));
	CGrepEnumFilterFiles files;
	CGrepEnumFiles absExcept;
	files.Enumerates(folder.Path().c_str(), keys, CGrepEnumOptions(), absExcept);
	EXPECT_THAT(Names(files), Eq(std::vector<sakura::wstring>{ LTEXT(R"(sub\x.bak)") }));
#else
	// Mac 版: パスの区切りは '/'
	folder.AddFile(LTEXT("sub/x.bak"));

	CGrepEnumKeys keys;
	ASSERT_THAT(keys.SetFileKeys(LTEXT("sub/*;!*.bak")), Eq(0));
	CGrepEnumFilterFiles files;
	CGrepEnumFiles absExcept;
	files.Enumerates(folder.Path().c_str(), keys, CGrepEnumOptions(), absExcept);
	EXPECT_THAT(Names(files), Eq(std::vector<sakura::wstring>{ LTEXT("sub/x.bak") }));
#endif
}

/*!
	@brief 絶対パスの除外ファイルが除外されること

	CGrepAgent::DoGrep() と同じく、絶対パスの除外は基準フォルダー無し(L"")で列挙してから渡す。
	パスに空白が含まれうるので引用符で囲む。
*/
TEST(CGrepEnumFilterFiles, ExceptAbsolutePath)
{
	TempFolder folder;
	folder.AddFile(LTEXT("a.txt"));
	folder.AddFile(LTEXT("b.txt"));

	CGrepEnumKeys keys;
	const auto excludePath = (folder.Path() / LTEXT("a.txt")).wstring();
	const sakura::wstring fileKeys = LTEXT("*;!\"") + excludePath + LTEXT("\"");
	ASSERT_THAT(keys.SetFileKeys(fileKeys.c_str()), Eq(0));
	ASSERT_THAT(std::vector<sakura::wstring>(keys.m_vecExceptAbsFileKeys.cbegin(), keys.m_vecExceptAbsFileKeys.cend()), Eq(std::vector<sakura::wstring>{ excludePath }));

	CGrepEnumOptions options;
	CGrepEnumFiles absExcept;
	absExcept.Enumerates(LTEXT(""), keys.m_vecExceptAbsFileKeys, options);
	EXPECT_THAT(absExcept.GetCount(), Eq(1));

	CGrepEnumFilterFiles files;
	files.Enumerates(folder.Path().c_str(), keys, options, absExcept);
	EXPECT_THAT(Names(files), Eq(std::vector<sakura::wstring>{ LTEXT("b.txt") }));
}

/*!
	@brief 絶対パスの除外ファイルにワイルドカードを使えること
*/
TEST(CGrepEnumFilterFiles, ExceptAbsolutePathWithWildcard)
{
	TempFolder folder;
	folder.AddFile(LTEXT("a.bak"));
	folder.AddFile(LTEXT("b.bak"));
	folder.AddFile(LTEXT("c.txt"));

	CGrepEnumKeys keys;
	const auto excludePath = (folder.Path() / LTEXT("*.bak")).wstring();
	const sakura::wstring fileKeys = LTEXT("*;!\"") + excludePath + LTEXT("\"");
	ASSERT_THAT(keys.SetFileKeys(fileKeys.c_str()), Eq(0));

	CGrepEnumOptions options;
	CGrepEnumFiles absExcept;
	absExcept.Enumerates(LTEXT(""), keys.m_vecExceptAbsFileKeys, options);
	EXPECT_THAT(absExcept.GetCount(), Eq(2));

	CGrepEnumFilterFiles files;
	files.Enumerates(folder.Path().c_str(), keys, options, absExcept);
	EXPECT_THAT(Names(files), Eq(std::vector<sakura::wstring>{ LTEXT("c.txt") }));
}

/*!
	@brief 除外フォルダーは名前が一致したものだけ除外され、英大文字小文字を区別しないこと
*/
TEST(CGrepEnumFilterFolders, ExceptFolder)
{
	TempFolder folder;
	for (const auto name : { LTEXT("Obj"), LTEXT("obj2"), LTEXT("obj,old"), LTEXT("src") }) {
		folder.AddFolder(name);
	}

	CGrepEnumKeys keys;
	ASSERT_THAT(keys.SetFileKeys(LTEXT("*;#OBJ")), Eq(0));
	CGrepEnumFilterFolders folders;
	CGrepEnumFolders absExcept;
	folders.Enumerates(folder.Path().c_str(), keys, CGrepEnumOptions(), absExcept);
	EXPECT_THAT(Names(folders), Eq(std::vector<sakura::wstring>{ LTEXT("obj,old"), LTEXT("obj2"), LTEXT("src") }));
}

/*!
	@brief 絶対パスの除外フォルダーが除外されること

	CGrepAgent::DoGrep() と同じく、絶対パスの除外は基準フォルダー無し(L"")で列挙してから渡す。
*/
TEST(CGrepEnumFilterFolders, ExceptAbsolutePath)
{
	TempFolder folder;
	folder.AddFolder(LTEXT("obj"));
	folder.AddFolder(LTEXT("src"));

	CGrepEnumKeys keys;
	const auto excludePath = (folder.Path() / LTEXT("obj")).wstring();
	const sakura::wstring fileKeys = LTEXT("*;#\"") + excludePath + LTEXT("\"");
	ASSERT_THAT(keys.SetFileKeys(fileKeys.c_str()), Eq(0));
	ASSERT_THAT(std::vector<sakura::wstring>(keys.m_vecExceptAbsFolderKeys.cbegin(), keys.m_vecExceptAbsFolderKeys.cend()), Eq(std::vector<sakura::wstring>{ excludePath }));

	CGrepEnumOptions options;
	CGrepEnumFolders absExcept;
	absExcept.Enumerates(LTEXT(""), keys.m_vecExceptAbsFolderKeys, options);
	EXPECT_THAT(absExcept.GetCount(), Eq(1));

	CGrepEnumFilterFolders folders;
	folders.Enumerates(folder.Path().c_str(), keys, options, absExcept);
	EXPECT_THAT(Names(folders), Eq(std::vector<sakura::wstring>{ LTEXT("src") }));
}
