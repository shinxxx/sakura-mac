/*! @file
	@brief ファイルツリーのテスト（计划第 43 步）

	原版 CDlgFuncList::LoadFileTreeSetting・SetTreeFile・SetTreeFileSub、CDlgFileTree::GetData、CImpExpFileTree の Mac 版
	（macos/core/api/FileTree.cpp）。原版にはテストが無い。
*/
/*
	Copyright (C) 2026, Sakura Editor Organization

	SPDX-License-Identifier: Zlib
*/

#include "pch.h"

#include "sakura_core/SakuraCore.h"
#include "mac-grep-temp-folder.hpp"

#include "env/CDocTypeManager.h"
#include "env/DLLSHAREDATA.h"

#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <string>

using namespace sakura::core;

namespace {

namespace fs = std::filesystem;

std::string U8(std::u16string_view text) { return sakura::u16::to_utf8(text); }

//! 设置文件（原版のエクスポート形式。BOM 付き UTF-8（BOM が無いと原版は Shift_JIS として読む）、[FileTree] セクション）
std::string IniText(const std::string& body)
{
	return "\xEF\xBB\xBF;SakuraEditorFileTree_Ver1\r\n\r\n[FileTree]\r\n" + body;
}

//! 書き込めないフォルダー（原版 CProfile::WriteProfile は無いフォルダーを作るので、書き込み禁止のフォルダーにする）
fs::path ReadOnlyFolder(const grep_test::TempFolder& temp)
{
	temp.AddFolder("readonly");
	const fs::path path = temp.Path().fs() / "readonly";
	::chmod(path.c_str(), 0555);
	return path;
}

class FileTreeTest : public ::testing::Test {
protected:
	void SetUp() override
	{
		ASSERT_TRUE(Startup());
		auto& outline = GetDllShareData().m_Common.m_sOutline;
		m_savedTree = outline.m_sFileTree;
		m_savedDockSet = outline.m_nOutlineDockSet;
		m_savedDefIni = outline.m_sFileTreeDefIniName;
		CDocTypeManager().GetTypeConfig(CTypeConfig(1), m_savedType);
	}
	void TearDown() override
	{
		auto& outline = GetDllShareData().m_Common.m_sOutline;
		outline.m_sFileTree = m_savedTree;
		outline.m_nOutlineDockSet = m_savedDockSet;
		outline.m_sFileTreeDefIniName = m_savedDefIni;
		CDocTypeManager().SetTypeConfig(CTypeConfig(1), m_savedType);
		Shutdown(false);
	}

	SFileTree m_savedTree{};
	int m_savedDockSet = 0;
	SFilePath m_savedDefIni;
	STypeConfig m_savedType;
};

} // namespace

// 初期値（原版 CShareData::InitFileTree）：共通設定、各フォルダーの設定を読み込む、Grep「.」「*.*」が 1 つ
TEST_F(FileTreeTest, DefaultSetting)
{
	grep_test::TempFolder temp;
	const auto setting = LoadFileTreeSetting(0, temp.PathText());
	EXPECT_EQ(FileTreeSettingFrom::Common, setting.origin);
	EXPECT_EQ(FileTreeSettingFrom::Common, setting.loadedFrom);
	EXPECT_TRUE(setting.project);
	EXPECT_TRUE(setting.loadedIni.empty());
	ASSERT_EQ(1u, setting.items.size());
	EXPECT_EQ(FileTreeItemType::Grep, setting.items[0].type);
	EXPECT_EQ(u".", setting.items[0].path);
	EXPECT_EQ(u"*.*", setting.items[0].file);
	EXPECT_TRUE(setting.items[0].ignoreHidden);
	EXPECT_FALSE(setting.items[0].ignoreReadOnly);
	EXPECT_FALSE(setting.items[0].ignoreSystem);

	const auto roots = FileTreeRoots(setting, temp.PathText());
	ASSERT_EQ(1u, roots.size());
	EXPECT_EQ(temp.PathText(), roots[0].path);	// 「.」は編集中のファイルのフォルダー
	EXPECT_EQ(temp.PathText(), roots[0].label);	// ラベルが空ならパス
}

// 各フォルダーの設定ファイル（_sakurafiletree.ini）：フォルダーから上へ探す。<iniroot> はそのフォルダー
TEST_F(FileTreeTest, ProjectIniInParentFolder)
{
	grep_test::TempFolder temp;
	temp.AddFile("proj/_sakurafiletree.ini", IniText(
		"nFileTreeItemCount=3\r\n"
		"FileTree(0).eItemType=0\r\nFileTree(0).szTargetPath=<iniroot>/src\r\nFileTree(0).nDepth=0\r\n"
		"FileTree(0).szTargetFile=*.cpp\r\nFileTree(0).bIgnoreHidden=1\r\nFileTree(0).bIgnoreReadOny=0\r\nFileTree(0).bIgnoreSystem=0\r\n"
		"FileTree(1).eItemType=2\r\nFileTree(1).szLabelName=Docs\r\nFileTree(1).nDepth=0\r\n"
		"FileTree(2).eItemType=1\r\nFileTree(2).szTargetPath=<iniroot>/README.md\r\nFileTree(2).szLabelName=読んでね\r\nFileTree(2).nDepth=1\r\n"));
	temp.AddFolder("proj/src/sub");
	const Text proj = temp.PathOf("proj");

	const auto setting = LoadFileTreeSetting(0, temp.PathOf("proj/src/sub"));
	EXPECT_EQ(FileTreeSettingFrom::Common, setting.origin);
	EXPECT_EQ(FileTreeSettingFrom::File, setting.loadedFrom);
	EXPECT_EQ(proj + u"/_sakurafiletree.ini", setting.loadedIni);
	EXPECT_EQ(proj, setting.iniFolder);
	ASSERT_EQ(3u, setting.items.size());
	EXPECT_EQ(u"*.cpp", setting.items[0].file);
	EXPECT_EQ(FileTreeItemType::Folder, setting.items[1].type);
	EXPECT_EQ(1, setting.items[2].depth);

	const auto roots = FileTreeRoots(setting, temp.PathOf("proj/src/sub"));
	ASSERT_EQ(3u, roots.size());
	EXPECT_EQ(proj + u"/src", roots[0].path);
	EXPECT_EQ(proj + u"/src", roots[0].label);
	EXPECT_EQ(u"Docs", roots[1].label);
	EXPECT_TRUE(roots[1].path.empty());
	EXPECT_EQ(proj + u"/README.md", roots[2].path);
	EXPECT_EQ(u"読んでね", roots[2].label);
	EXPECT_EQ(1, roots[2].depth);
	EXPECT_EQ(2, roots[2].itemIndex);
}

// 各フォルダーの設定を読み込む が切ってあれば探さない。設定ファイル名は共通設定（szFileTreeDefIniName）
TEST_F(FileTreeTest, ProjectIniOffAndName)
{
	grep_test::TempFolder temp;
	temp.AddFile("_sakurafiletree.ini", IniText("nFileTreeItemCount=0\r\n"));
	temp.AddFile("my.ini", IniText("nFileTreeItemCount=1\r\nFileTree(0).eItemType=1\r\nFileTree(0).szTargetPath=a.txt\r\n"));

	auto& outline = GetDllShareData().m_Common.m_sOutline;
	outline.m_sFileTree.m_bProject = false;
	auto setting = LoadFileTreeSetting(0, temp.PathText());
	EXPECT_EQ(FileTreeSettingFrom::Common, setting.loadedFrom);
	EXPECT_EQ(1u, setting.items.size());

	outline.m_sFileTree.m_bProject = true;
	outline.m_sFileTreeDefIniName = LTEXT("my.ini");
	setting = LoadFileTreeSetting(0, temp.PathText());
	EXPECT_EQ(FileTreeSettingFrom::File, setting.loadedFrom);
	ASSERT_EQ(1u, setting.items.size());
	EXPECT_EQ(FileTreeItemType::File, setting.items[0].type);
	// 相対パスは編集中のファイルのフォルダーから
	const auto roots = FileTreeRoots(setting, temp.PathText());
	EXPECT_EQ(temp.PathOf("a.txt"), roots[0].path);
}

// デフォルト設定ファイル名：各フォルダーに無いときに読む。<iniroot> は展開しない（原版 IniDirPath が空）
TEST_F(FileTreeTest, DefaultProjectIni)
{
	grep_test::TempFolder temp;
	temp.AddFile("def/tree.ini", IniText("nFileTreeItemCount=1\r\nFileTree(0).eItemType=0\r\nFileTree(0).szTargetPath=/usr\r\nFileTree(0).szTargetFile=*.h\r\n"));
	auto& tree = GetDllShareData().m_Common.m_sOutline.m_sFileTree;
	tree.m_szProjectIni = temp.PathOf("def/tree.ini").c_str();
	auto setting = LoadFileTreeSetting(0, temp.PathOf("def"));
	EXPECT_EQ(FileTreeSettingFrom::Common, setting.loadedFrom);	// 原版：デフォルト設定ファイルは「共通設定+ファイル」
	EXPECT_EQ(temp.PathOf("def/tree.ini"), setting.loadedIni);
	ASSERT_EQ(1u, setting.items.size());
	EXPECT_EQ(u"*.h", setting.items[0].file);

	// 無いファイルなら共通設定の項目
	tree.m_szProjectIni = temp.PathOf("def/none.ini").c_str();
	setting = LoadFileTreeSetting(0, temp.PathOf("def"));
	EXPECT_TRUE(setting.loadedIni.empty());
	EXPECT_EQ(u".", setting.items[0].path);

	// 「読み込み」ボタン
	EXPECT_FALSE(LoadFileTreeDefaultIni(setting, temp.PathOf("def/none.ini")));
	EXPECT_EQ(u".", setting.items[0].path);
	EXPECT_TRUE(LoadFileTreeDefaultIni(setting, temp.PathOf("def/tree.ini")));
	EXPECT_EQ(u"/usr", setting.items[0].path);
	EXPECT_EQ(temp.PathOf("def/tree.ini"), setting.loadedIni);
}

// ドッキング配置が「タイプ別」ならタイプ別設定の項目
TEST_F(FileTreeTest, TypeSetting)
{
	grep_test::TempFolder temp;
	STypeConfig type;
	ASSERT_TRUE(CDocTypeManager().GetTypeConfig(CTypeConfig(1), type));
	type.m_sFileTree.m_bProject = false;
	type.m_sFileTree.m_nItemCount = 1;
	type.m_sFileTree.m_aItems[0] = SFileTreeItem();
	type.m_sFileTree.m_aItems[0].m_eFileTreeItemType = EFileTreeItemType_File;
	type.m_sFileTree.m_aItems[0].m_szTargetPath = LTEXT("type.txt");
	CDocTypeManager().SetTypeConfig(CTypeConfig(1), type);
	GetDllShareData().m_Common.m_sOutline.m_nOutlineDockSet = 1;

	auto setting = LoadFileTreeSetting(1, temp.PathText());
	EXPECT_EQ(FileTreeSettingFrom::Type, setting.origin);
	EXPECT_FALSE(setting.project);
	ASSERT_EQ(1u, setting.items.size());
	EXPECT_EQ(u"type.txt", setting.items[0].path);

	// 保存はタイプ別設定へ
	setting.items[0].path = u"type2.txt";
	setting.project = true;
	bool truncated = true;
	EXPECT_TRUE(SaveFileTreeSetting(setting, 1, truncated).empty());
	EXPECT_FALSE(truncated);
	ASSERT_TRUE(CDocTypeManager().GetTypeConfig(CTypeConfig(1), type));
	EXPECT_EQ(sakura::wstring(LTEXT("type2.txt")), type.m_sFileTree.m_aItems[0].m_szTargetPath.c_str());
	EXPECT_TRUE(type.m_sFileTree.m_bProject);
	// 共通設定は変わらない
	EXPECT_EQ(sakura::wstring(LTEXT(".")), GetDllShareData().m_Common.m_sOutline.m_sFileTree.m_aItems[0].m_szTargetPath.c_str());
}

// パスの展開：%…%（環境変数、%SAKURADATA%）、%%、長すぎるパス
TEST_F(FileTreeTest, ExpandPath)
{
	grep_test::TempFolder temp;
	::setenv("SAKURA_FILETREE_TEST", U8(temp.PathText()).c_str(), 1);
	FileTreeSetting setting;
	FileTreeItem a; a.path = u"%SAKURA_FILETREE_TEST%/x";
	FileTreeItem b; b.path = u"100%%/y";
	FileTreeItem c; c.path = Text(400, u'a');
	FileTreeItem d; d.type = FileTreeItemType::File; d.path = u"../z.txt"; d.label = u"Z";
	FileTreeItem e; e.type = FileTreeItemType::Folder;
	setting.items = { a, b, c, d, e };
	const auto roots = FileTreeRoots(setting, temp.PathOf("sub"));
	ASSERT_EQ(5u, roots.size());
	EXPECT_EQ(temp.PathOf("x"), roots[0].path);
	EXPECT_EQ(temp.PathOf("sub/100%/y"), roots[1].path);
	EXPECT_EQ(u"<Error:Long Path>", roots[2].path);
	EXPECT_EQ(temp.PathOf("z.txt"), roots[3].path);
	EXPECT_EQ(u"Z", roots[3].label);
	EXPECT_EQ(u"Folder", roots[4].label);
	::unsetenv("SAKURA_FILETREE_TEST");
}

// フォルダーの中（原版 SetTreeFileSub）：フォルダーが先、Windows と同じ順、対象ファイル・除外、隠しファイル
TEST_F(FileTreeTest, ListFolder)
{
	grep_test::TempFolder temp;
	temp.AddFile("b.txt", "b");
	temp.AddFile("A.txt", "a");
	temp.AddFile("c.cpp", "c");
	temp.AddFile(".hidden.txt", "h");
	temp.AddFile("ro.txt", "r", FILE_ATTRIBUTE_READONLY);
	temp.AddFolder("Sub");
	temp.AddFolder("obj");
	temp.AddFolder(".git");

	FileTreeItem item;
	auto listing = ListFileTree(item, temp.PathText());
	EXPECT_FALSE(listing.wildcardError);
	EXPECT_EQ((std::vector<Text>{ u"obj", u"Sub" }), listing.folders);
	EXPECT_EQ((std::vector<Text>{ u"A.txt", u"b.txt", u"c.cpp", u"ro.txt" }), listing.files);

	item.file = u"*.txt;#obj;!b.txt";
	item.ignoreHidden = false;
	item.ignoreReadOnly = true;
	listing = ListFileTree(item, temp.PathText());
	EXPECT_EQ((std::vector<Text>{ u".git", u"Sub" }), listing.folders);
	EXPECT_EQ((std::vector<Text>{ u".hidden.txt", u"A.txt" }), listing.files);

	// サブフォルダー（パスの最後の / はあってもなくても同じ）
	temp.AddFile("Sub/s.txt", "s");
	item = FileTreeItem();
	listing = ListFileTree(item, temp.PathOf("Sub") + u"/");
	EXPECT_EQ((std::vector<Text>{ u"s.txt" }), listing.files);

	// ワイルドカードの後ろのフォルダー区切り（原版「<Wild Card Error>」）
	item.file = u"*/x.txt";
	listing = ListFileTree(item, temp.PathText());
	EXPECT_TRUE(listing.wildcardError);
	EXPECT_TRUE(listing.files.empty());
}

// 保存（原版 CDlgFileTree::GetData）：共通設定へ。20 個まで
TEST_F(FileTreeTest, SaveCommon)
{
	grep_test::TempFolder temp;
	auto setting = LoadFileTreeSetting(0, temp.PathText());
	setting.project = false;
	setting.defaultProjectIni = u"def.ini";
	setting.items.clear();
	for (int i = 0; i < 22; ++i) {
		FileTreeItem item;
		item.type = FileTreeItemType::File;
		item.path = u"f" + sakura::u16::from_utf8<char16_t>(std::to_string(i));
		setting.items.push_back(item);
	}
	bool truncated = false;
	EXPECT_TRUE(SaveFileTreeSetting(setting, 0, truncated).empty());
	EXPECT_TRUE(truncated);
	const auto& tree = GetDllShareData().m_Common.m_sOutline.m_sFileTree;
	EXPECT_FALSE(tree.m_bProject);
	EXPECT_EQ(sakura::wstring(LTEXT("def.ini")), tree.m_szProjectIni.c_str());
	EXPECT_EQ(kFileTreeMaxItems, tree.m_nItemCount);
	EXPECT_EQ(sakura::wstring(LTEXT("f19")), tree.m_aItems[19].m_szTargetPath.c_str());
	EXPECT_EQ(EFileTreeItemType_File, tree.m_aItems[0].m_eFileTreeItemType);

	const auto loaded = LoadFileTreeSetting(0, temp.PathText());
	EXPECT_EQ(20u, loaded.items.size());
}

// 保存：設定ファイルを読んでいたらそのファイルへ（20 個を超えてもよい）。共通設定の項目は変わらない
TEST_F(FileTreeTest, SaveToIni)
{
	grep_test::TempFolder temp;
	temp.AddFile("_sakurafiletree.ini", IniText("nFileTreeItemCount=1\r\nFileTree(0).eItemType=1\r\nFileTree(0).szTargetPath=a.txt\r\n"));
	auto setting = LoadFileTreeSetting(0, temp.PathText());
	ASSERT_EQ(FileTreeSettingFrom::File, setting.loadedFrom);
	setting.items.clear();
	for (int i = 0; i < 25; ++i) {
		FileTreeItem item;
		item.type = (i == 0) ? FileTreeItemType::Folder : FileTreeItemType::Grep;
		item.label = (i == 0) ? u"G" : u"";
		item.depth = (i == 0) ? 0 : 1;
		item.path = u"<iniroot>/d";
		setting.items.push_back(item);
	}
	bool truncated = true;
	EXPECT_TRUE(SaveFileTreeSetting(setting, 0, truncated).empty());
	EXPECT_FALSE(truncated);
	EXPECT_EQ(1, GetDllShareData().m_Common.m_sOutline.m_sFileTree.m_nItemCount);

	const auto loaded = LoadFileTreeSetting(0, temp.PathText());
	ASSERT_EQ(25u, loaded.items.size());
	EXPECT_EQ(FileTreeItemType::Folder, loaded.items[0].type);
	EXPECT_EQ(u"G", loaded.items[0].label);
	EXPECT_EQ(1, loaded.items[24].depth);
	EXPECT_EQ(temp.PathOf("d"), FileTreeRoots(loaded, temp.PathText())[1].path);

	// 書けないファイルはエラーのメッセージ
	setting.loadedIni = sakura::path_to_wstring(ReadOnlyFolder(temp) / "x.ini");
	EXPECT_FALSE(SaveFileTreeSetting(setting, 0, truncated).empty());
}

// インポート・エクスポート（原版 CImpExpFileTree）：ファイルの形式は原版と同じ
TEST_F(FileTreeTest, ImportExport)
{
	grep_test::TempFolder temp;
	FileTreeItem g; g.path = u"<iniroot>"; g.file = u"*.c;*.h"; g.ignoreReadOnly = true;
	FileTreeItem f; f.type = FileTreeItemType::Folder; f.label = u"フォルダー";
	FileTreeItem file; file.type = FileTreeItemType::File; file.path = u"%MYDOC%/a.txt"; file.depth = 1;
	const std::vector<FileTreeItem> items{ g, f, file };
	EXPECT_TRUE(ExportFileTree(temp.PathOf("out.ini"), items).empty());

	// 原版 IOProfileData<SFileTreeItem>：種類に関係ないキーは書かない。CProfile はキーの名前の順に書く
	EXPECT_EQ(
		"\xEF\xBB\xBF;SakuraEditorFileTree_Ver1\r\n"
		"\r\n"
		"[FileTree]\r\n"
		"FileTree(0).bIgnoreHidden=1\r\n"
		"FileTree(0).bIgnoreReadOny=1\r\n"
		"FileTree(0).bIgnoreSystem=0\r\n"
		"FileTree(0).eItemType=0\r\n"
		"FileTree(0).nDepth=0\r\n"
		"FileTree(0).szTargetFile=*.c;*.h\r\n"
		"FileTree(0).szTargetPath=<iniroot>\r\n"
		"FileTree(1).eItemType=2\r\n"
		"FileTree(1).nDepth=0\r\n"
		"FileTree(1).szLabelName=フォルダー\r\n"
		"FileTree(2).eItemType=1\r\n"
		"FileTree(2).nDepth=1\r\n"
		"FileTree(2).szTargetPath=%MYDOC%/a.txt\r\n"
		"nFileTreeItemCount=3\r\n"
		"\r\n", temp.ReadFile("out.ini"));

	const auto imported = ImportFileTree(temp.PathOf("out.ini"));
	ASSERT_TRUE(imported.has_value());
	ASSERT_EQ(3u, imported->size());
	EXPECT_EQ(u"*.c;*.h", (*imported)[0].file);
	EXPECT_TRUE((*imported)[0].ignoreReadOnly);
	EXPECT_EQ(u"フォルダー", (*imported)[1].label);
	EXPECT_EQ(u"%MYDOC%/a.txt", (*imported)[2].path);
	EXPECT_EQ(1, (*imported)[2].depth);

	// 無いフォルダーは作る（原版 CProfile::WriteProfile）。書けない場所はエラーのメッセージ
	EXPECT_TRUE(ExportFileTree(temp.PathOf("new/out.ini"), items).empty());
	EXPECT_TRUE(temp.Exists("new/out.ini"));
	EXPECT_FALSE(ExportFileTree(sakura::path_to_wstring(ReadOnlyFolder(temp) / "out.ini"), items).empty());
}

// アウトライン解析の F_FILETREE（原版 SetData の OUTLINE_FILETREE）：ツリー表示、題名「ファイルツリー」
TEST_F(FileTreeTest, OutlineResult)
{
	auto doc = Document::Create();
	ASSERT_TRUE(doc);
	const auto result = doc->AnalyzeOutline(OutlineType::FileTree);
	EXPECT_EQ(OutlineType::FileTree, result.listType);
	EXPECT_TRUE(result.isTree);
	EXPECT_EQ(u"ファイルツリー", result.title);
	EXPECT_TRUE(result.items.empty());
	EXPECT_TRUE(result.tree.empty());
}
