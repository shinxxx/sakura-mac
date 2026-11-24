/*! @file
	@brief 共通設定 > キー割り当て・メインメニュー・ツールバー・カスタムメニュー（计划第 41 步）的测试

	sakura::core::CommandSettingsEditor（原版 CPropCommon 的 m_Common 的复制 + CFuncLookup）。这里确认：
	- 「種別」「機能」与原版的 CFuncLookup 相同（分类的顺序、外部マクロ・カスタムメニュー・プラグイン）
	- キー割り当て：割当・解除只改复制，IniValues("KeyBind") 写回后按键马上用新的功能，保存后重新启动也是
	- 機能に割り当てられているキー（原版 GetKeyStrList）
	- インポート・エクスポート（*.key，原版的格式）
*/
/*
	Copyright (C) 2026, Sakura Editor Organization

	SPDX-License-Identifier: Zlib
*/
#include "pch.h"

#include "sakura_core/SakuraCore.h"

#include "env/DLLSHAREDATA.h"
#include "util/file.h"

#include <algorithm>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <string>

using namespace sakura::core;

namespace {

namespace fs = std::filesystem;

constexpr FunctionCode kCopy = 30602;			// F_COPY
constexpr FunctionCode kFileNew = 30101;		// F_FILENEW
constexpr FunctionCode kSelectAll = 30401;		// F_SELECTALL
constexpr FunctionCode kMenuRButton = 31580;	// F_MENU_RBUTTON
constexpr std::uint16_t kF8 = 0x77;
constexpr std::uint16_t kF12 = 0x7B;
constexpr std::uint8_t kAll = keymod::Shift | keymod::Ctrl | keymod::Alt;

class MacCommandSettingsTest : public ::testing::Test {
protected:
	void SetUp() override
	{
		RemoveIniFolder();
		ASSERT_TRUE(Startup());
	}
	void TearDown() override
	{
		Shutdown(false);
		RemoveIniFolder();
	}
	static void RemoveIniFolder()
	{
		std::error_code ec;
		fs::remove_all(GetIniFileName().parent_path(), ec);
	}
	static fs::path TempFile(const char* name)
	{
		return GetIniFileName().parent_path() / name;
	}
	//! 键的名字 → 编号
	static int KeyIndex(const CommandSettingsEditor& editor, const Text& name)
	{
		for (int i = 0; i < editor.KeyCount(); ++i) {
			if (editor.KeyName(i) == name) return i;
		}
		return -1;
	}
	//! 编辑的值写回核心库（窗口的 OK）
	static bool Apply(const CommandSettingsEditor& editor, const Text& section)
	{
		return SetCommonSettings(section, editor.IniValues(section));
	}
};

} // namespace

//! 「種別」：原版的分类、外部マクロ、カスタムメニュー、プラグイン（CFuncLookup::SetCategory2Combo）
TEST_F(MacCommandSettingsTest, FunctionCategories)
{
	auto editor = CommandSettingsEditor::Create();
	ASSERT_TRUE(editor);
	const auto categories = editor->FunctionCategories();
	ASSERT_GE(categories.size(), 4u);
	EXPECT_EQ(u"ファイル操作系", categories.front());
	EXPECT_EQ(u"外部マクロ", categories[categories.size() - 3]);
	EXPECT_EQ(u"カスタムメニュー", categories[categories.size() - 2]);
	EXPECT_EQ(u"プラグイン", categories.back());

	// ファイル操作系 的第一个是 新規作成
	const auto file = editor->Functions(0);
	ASSERT_FALSE(file.empty());
	EXPECT_EQ(kFileNew, file.front().code);
	EXPECT_EQ(editor->FunctionName(kFileNew), file.front().name);

	// 外部マクロ：没有登录的宏不在列表里（原版 Pos2FuncCode(…, bGetUnavailable=true) 也返回，SetListItem 不排除）
	const auto macros = editor->Functions(static_cast<std::int32_t>(categories.size() - 3));
	EXPECT_EQ(50u, macros.size());	// MAX_CUSTMACRO
	// カスタムメニュー：右クリックメニュー、カスタムメニュー1… 、タブメニュー
	const auto menus = editor->Functions(static_cast<std::int32_t>(categories.size() - 2));
	ASSERT_FALSE(menus.empty());
	EXPECT_EQ(kMenuRButton, menus.front().code);
	EXPECT_EQ(u"右クリックメニュー", menus.front().name);
	// Mac 版没有 DLL 的プラグイン
	EXPECT_TRUE(editor->Functions(static_cast<std::int32_t>(categories.size() - 1)).empty());
	// 没有的分类
	EXPECT_TRUE(editor->Functions(-1).empty());
	EXPECT_TRUE(editor->Functions(static_cast<std::int32_t>(categories.size())).empty());
}

//! キー一覧、キーに割り当てられている機能、機能に割り当てられているキー
TEST_F(MacCommandSettingsTest, KeyListAndAssignedKeys)
{
	auto editor = CommandSettingsEditor::Create();
	ASSERT_TRUE(editor);
	ASSERT_GT(editor->KeyCount(), 0);
	EXPECT_EQ(u"ダブルクリック", editor->KeyName(0));	// 鼠标在最前面
	const int f8 = KeyIndex(*editor, u"F8");
	ASSERT_GE(f8, 0);
	EXPECT_EQ(kCopy, editor->KeyFunction(f8, 0));
	EXPECT_EQ(0, editor->KeyFunction(f8, keymod::Shift | keymod::Ctrl | kAll));
	EXPECT_EQ(0, editor->KeyFunction(-1, 0));
	EXPECT_EQ(0, editor->KeyFunction(f8, 8));

	const auto keys = editor->AssignedKeys(kCopy);
	EXPECT_NE(keys.end(), std::find(keys.begin(), keys.end(), u"F8"));
	EXPECT_NE(keys.end(), std::find(keys.begin(), keys.end(), u"Ctrl+C"));
}

//! 割当・解除：只改复制；写回后按键用新的功能，保存后重新启动也是
TEST_F(MacCommandSettingsTest, AssignAndRelease)
{
	auto editor = CommandSettingsEditor::Create();
	ASSERT_TRUE(editor);
	const int f12 = KeyIndex(*editor, u"F12");
	const int f8 = KeyIndex(*editor, u"F8");
	ASSERT_GE(f12, 0);
	editor->SetKeyFunction(f12, keymod::Shift | keymod::Ctrl, kSelectAll);
	editor->SetKeyFunction(f8, 0, 0);	// 解除
	EXPECT_EQ(kSelectAll, editor->KeyFunction(f12, keymod::Shift | keymod::Ctrl));
	const auto keys = editor->AssignedKeys(kSelectAll);
	EXPECT_NE(keys.end(), std::find(keys.begin(), keys.end(), u"Shift+Ctrl+F12"));
	// 核心库还没变（キャンセル 时什么也不改）
	EXPECT_NE(kSelectAll, FunctionForKey(kF12, keymod::Shift | keymod::Ctrl));
	EXPECT_EQ(kCopy, FunctionForKey(kF8, 0));

	// IniValues：原版 sakura.ini 的写法（键码,8 个功能,键名）
	const auto values = editor->IniValues(u"KeyBind");
	ASSERT_EQ(static_cast<size_t>(editor->KeyCount()), values.size());
	EXPECT_EQ(u"KeyBind[000]", values.front().first);
	const auto& f12Value = values[f12].second;
	EXPECT_EQ(u"007b,", f12Value.substr(0, 5));
	EXPECT_NE(Text::npos, f12Value.find(u",30401,"));
	EXPECT_EQ(u",F12", f12Value.substr(f12Value.size() - 4));
	EXPECT_TRUE(editor->IniValues(u"Common").empty());

	ASSERT_TRUE(Apply(*editor, u"KeyBind"));
	EXPECT_EQ(kSelectAll, FunctionForKey(kF12, keymod::Shift | keymod::Ctrl));
	EXPECT_EQ(0, FunctionForKey(kF8, 0));
	EXPECT_EQ(f12Value, GetCommonSetting(u"KeyBind", values[f12].first));

	// 保存、重新启动
	ASSERT_TRUE(SaveSettings());
	Shutdown(false);
	ASSERT_TRUE(Startup());
	EXPECT_EQ(kSelectAll, FunctionForKey(kF12, keymod::Shift | keymod::Ctrl));
	EXPECT_EQ(0, FunctionForKey(kF8, 0));
}

//! インポート・エクスポート（*.key）：原版のファイル形式。読み込んだ値は複製に入り、写回时才生效
TEST_F(MacCommandSettingsTest, ImportExportKeyBind)
{
	auto editor = CommandSettingsEditor::Create();
	ASSERT_TRUE(editor);
	const int f12 = KeyIndex(*editor, u"F12");
	editor->SetKeyFunction(f12, kAll, kSelectAll);
	const auto path = TempFile("test.key");
	Text message;
	ASSERT_TRUE(editor->ExportKeyBind(Text(path.u16string()), message)) << std::string(message.begin(), message.end());
	const auto text = [&] {
		std::ifstream in(path, std::ios::binary);
		return std::string(std::istreambuf_iterator<char>(in), std::istreambuf_iterator<char>());
	}();
	EXPECT_NE(std::string::npos, text.find("KEYBIND_VERSION")) << text.substr(0, 200);
	EXPECT_NE(std::string::npos, text.find("SelectAll"));	// 原版のエクスポートはマクロ名で書く

	auto other = CommandSettingsEditor::Create();
	EXPECT_EQ(0, other->KeyFunction(f12, kAll));
	ASSERT_TRUE(other->ImportKeyBind(Text(path.u16string()), message));
	EXPECT_EQ(kSelectAll, other->KeyFunction(f12, kAll));
	EXPECT_NE(kSelectAll, FunctionForKey(kF12, kAll));	// 还没写回

	// 打不开的文件：原版的消息
	EXPECT_FALSE(other->ImportKeyBind(Text(TempFile("none.key").u16string()), message));
	EXPECT_NE(Text::npos, message.find(u"ファイルを開けませんでした"));
	// 格式不对的文件
	{
		std::ofstream out(TempFile("bad.key"));
		out << "hello\n";
	}
	EXPECT_FALSE(other->ImportKeyBind(Text(TempFile("bad.key").u16string()), message));
	EXPECT_FALSE(message.empty());
	EXPECT_EQ(kSelectAll, other->KeyFunction(f12, kAll));	// 失败时不变
}

//! 复制是 Create 时的：之后核心库变了也不影响（原版 m_Common）
TEST_F(MacCommandSettingsTest, EditorIsACopy)
{
	auto editor = CommandSettingsEditor::Create();
	ASSERT_TRUE(editor);
	auto second = CommandSettingsEditor::Create();
	const int f12 = KeyIndex(*second, u"F12");
	second->SetKeyFunction(f12, 0, kSelectAll);
	ASSERT_TRUE(Apply(*second, u"KeyBind"));
	EXPECT_EQ(kSelectAll, FunctionForKey(kF12, 0));
	EXPECT_NE(kSelectAll, editor->KeyFunction(f12, 0));
}

// ----- メインメニュー（第 2 个 PR）-----

namespace {
constexpr FunctionCode kOption = 31112;			// F_OPTION
constexpr FunctionCode kFileTopMenu = 34052;	// F_FILE_TOPMENU
constexpr FunctionCode kSeparator = 1;			// F_SEPARATOR
constexpr FunctionCode kRecentFiles = 29002;	// F_FILE_USED_RECENTLY（特別機能）
}

//! 原版 SetData：命令は機能名、区切線、特別機能、子菜单（リソースの名前）
TEST_F(MacCommandSettingsTest, MainMenuEntries)
{
	auto editor = CommandSettingsEditor::Create();
	ASSERT_TRUE(editor);
	const auto entries = editor->MainMenuEntries();
	ASSERT_FALSE(entries.empty());
	EXPECT_EQ(0, entries.front().level);
	EXPECT_TRUE(entries.front().isNode);
	EXPECT_EQ(kFileTopMenu, entries.front().code);
	EXPECT_EQ(u"ファイル", entries.front().name);
	EXPECT_EQ(u"F", entries.front().accessKey);
	EXPECT_EQ(1, entries[1].level);
	EXPECT_EQ(u"新規作成", entries[1].name);
	EXPECT_NE(entries.end(), std::find_if(entries.begin(), entries.end(), [](const auto& e) { return e.code == kSeparator && e.name == u"――――――――――"; }));
	EXPECT_NE(entries.end(), std::find_if(entries.begin(), entries.end(), [](const auto& e) { return e.code == kRecentFiles && !e.isNode; }));

	EXPECT_EQ(u"特別機能", editor->SpecialFunctionCategory());
	const auto special = editor->SpecialFunctions();
	EXPECT_NE(special.end(), std::find_if(special.begin(), special.end(), [](const auto& f) { return f.code == kRecentFiles; }));
}

//! 原版 GetData：種類は機能番号で決まる。「共通設定」が無いと最後に追加。写回后 MainMenu() も変わる
TEST_F(MacCommandSettingsTest, SetMainMenuAndApply)
{
	auto editor = CommandSettingsEditor::Create();
	ASSERT_TRUE(editor);
	const auto before = MainMenu().size();
	using E = CommandSettingsEditor::MainMenuEntry;
	std::vector<E> entries = {
		{ 0, true, 0, u"A&B", u"A" },			// F_NODE：名前を書く（& は && に）
		{ 1, false, kFileNew, u"", u"N" },
		{ 1, false, kSeparator, u"", u"" },
		{ 1, false, kRecentFiles, u"", u"R" },
		{ 0, true, kFileTopMenu, u"", u"F" },	// リソースの名前の子菜单
	};
	ASSERT_TRUE(editor->SetMainMenu(entries, true));
	const auto result = editor->MainMenuEntries();
	ASSERT_EQ(7u, result.size());	// auto_add と 共通設定
	EXPECT_EQ(u"A&B", result[0].name);
	EXPECT_EQ(u"新規作成", result[1].name);
	EXPECT_EQ(kSeparator, result[2].code);
	EXPECT_EQ(u"ファイル", result[4].name);
	EXPECT_EQ(u"auto_add", result[5].name);
	EXPECT_EQ(0, result[5].level);
	EXPECT_EQ(kOption, result[6].code);
	EXPECT_EQ(1, result[6].level);
	EXPECT_TRUE(editor->MainMenuKeyParentheses());

	const auto values = editor->IniValues(u"MainMenu");
	auto value = [&](const Text& key) {
		auto it = std::find_if(values.begin(), values.end(), [&](const auto& v) { return v.first == key; });
		return it == values.end() ? Text(u"<none>") : it->second;
	};
	EXPECT_EQ(u"7", value(u"nMainMenuNum"));
	EXPECT_EQ(u"1", value(u"bKeyParentheses"));
	EXPECT_EQ(u"0,0,0,A,A&&B", value(u"MM[000]"));
	EXPECT_EQ(u"1,1,30101,N,", value(u"MM[001]"));
	EXPECT_EQ(u"", value(u"MM[007]"));	// 減った項目
	EXPECT_EQ(MainMenu().size(), before);	// まだ変わらない

	ASSERT_TRUE(SetCommonSettings(u"MainMenu", values));
	const auto menu = MainMenu();
	ASSERT_EQ(7u, menu.size());
	EXPECT_EQ(u"A&&B", menu[0].name);
	EXPECT_EQ(kFileNew, menu[1].code);
	EXPECT_EQ(MenuItemType::Special, menu[3].type);
	EXPECT_EQ(kOption, menu[6].code);

	// 保存、重新启动
	ASSERT_TRUE(SaveSettings());
	Shutdown(false);
	ASSERT_TRUE(Startup());
	EXPECT_EQ(7u, MainMenu().size());
}

//! 菜单栏の項目は MAX_MAINMENU_TOP（20）まで：あふれた項目は下位項目ごと入れない
TEST_F(MacCommandSettingsTest, SetMainMenuTopLimit)
{
	auto editor = CommandSettingsEditor::Create();
	std::vector<CommandSettingsEditor::MainMenuEntry> entries;
	for (int i = 0; i < 22; ++i) {
		entries.push_back({ 0, true, 0, u"M", u"" });
		entries.push_back({ 1, false, kOption, u"", u"" });
	}
	ASSERT_TRUE(editor->SetMainMenu(entries, false));
	EXPECT_EQ(40u, editor->MainMenuEntries().size());
}

//! 初期設定（内置的 MainMenu.ini）、インポート・エクスポート（*.ini）
TEST_F(MacCommandSettingsTest, MainMenuInitializeImportExport)
{
	auto editor = CommandSettingsEditor::Create();
	const auto original = editor->MainMenuEntries();
	ASSERT_TRUE(editor->SetMainMenu({ { 0, true, 0, u"X", u"X" }, { 1, false, kOption, u"", u"O" } }, false));
	EXPECT_EQ(2u, editor->MainMenuEntries().size());
	const auto path = TempFile("menu.ini");
	Text message;
	ASSERT_TRUE(editor->ExportMainMenu(Text(path.u16string()), message));
	editor->InitializeMainMenu();
	ASSERT_EQ(original.size(), editor->MainMenuEntries().size());
	EXPECT_EQ(original.front().name, editor->MainMenuEntries().front().name);
	ASSERT_TRUE(editor->ImportMainMenu(Text(path.u16string()), message));
	ASSERT_EQ(2u, editor->MainMenuEntries().size());
	EXPECT_EQ(u"X", editor->MainMenuEntries().front().name);
	// 原版のヘッダーが無いファイル
	{
		std::ofstream out(TempFile("bad.ini"));
		out << "[MainMenu]\nnMainMenuNum=1\n";
	}
	EXPECT_FALSE(editor->ImportMainMenu(Text(TempFile("bad.ini").u16string()), message));
	EXPECT_FALSE(message.empty());
	EXPECT_EQ(2u, editor->MainMenuEntries().size());
}

// ----- カスタムメニュー・ツールバー（第 3 个 PR）-----

//! カスタムメニュー：名前（未設定は「右クリックメニュー」「カスタムメニュー1」…）、項目、サブメニュー。写回、保存、再起動
TEST_F(MacCommandSettingsTest, CustomMenu)
{
	auto editor = CommandSettingsEditor::Create();
	ASSERT_TRUE(editor);
	EXPECT_EQ(25, editor->CustomMenuCount());
	EXPECT_EQ(48, editor->MaxCustomMenuItems());
	EXPECT_EQ(u"右クリックメニュー", editor->CustomMenuDisplayName(0));
	EXPECT_EQ(u"メニュー1", editor->CustomMenuDisplayName(1));
	EXPECT_EQ(u"タブメニュー", editor->CustomMenuDisplayName(24));
	EXPECT_EQ(u"", editor->CustomMenuName(1));
	EXPECT_FALSE(editor->CustomMenuItems(0).empty());	// 右クリックメニューの初期値

	editor->SetCustomMenuName(1, u"マイメニュー");
	editor->SetCustomMenuIsSubmenu(1, true);
	editor->SetCustomMenuItems(1, { { kFileNew, u'N' }, { 0, 0 }, { kCopy, u'C' } });
	EXPECT_EQ(u"マイメニュー", editor->CustomMenuDisplayName(1));
	// 名前の変更はキー割り当ての「機能」にも出る（同じ複製）
	EXPECT_EQ(u"マイメニュー", editor->FunctionName(31501));	// F_CUSTMENU_1
	const auto items = editor->CustomMenuItems(1);
	ASSERT_EQ(3u, items.size());
	EXPECT_EQ(u'N', items[0].accessKey);
	EXPECT_EQ(0, items[1].code);
	// 長い名前は MAX_CUSTOM_MENU_NAME_LEN - 1 文字まで（原版 DlgItem_GetText）
	editor->SetCustomMenuName(2, Text(40, u'あ'));
	EXPECT_EQ(31u, editor->CustomMenuName(2).size());
	editor->SetCustomMenuName(2, u"");

	ASSERT_TRUE(SetCommonSettings(u"CustMenu", editor->IniValues(u"CustMenu")));
	ASSERT_TRUE(SaveSettings());
	Shutdown(false);
	ASSERT_TRUE(Startup());
	auto reloaded = CommandSettingsEditor::Create();
	EXPECT_EQ(u"マイメニュー", reloaded->CustomMenuName(1));
	EXPECT_TRUE(reloaded->CustomMenuIsSubmenu(1));
	const auto again = reloaded->CustomMenuItems(1);
	ASSERT_EQ(3u, again.size());
	EXPECT_EQ(kFileNew, again[0].code);
	EXPECT_EQ(u'N', again[0].accessKey);
	EXPECT_EQ(kCopy, again[2].code);
	EXPECT_EQ(u'C', again[2].accessKey);

	// 項目を減らす：減った項目は空の値
	reloaded->SetCustomMenuItems(1, { { kCopy, 0 } });
	const auto values = reloaded->IniValues(u"CustMenu");
	auto it = std::find_if(values.begin(), values.end(), [](const auto& v) { return v.first == u"nCMIF[01][02]"; });
	ASSERT_NE(values.end(), it);
	EXPECT_EQ(u"", it->second);
	ASSERT_TRUE(SetCommonSettings(u"CustMenu", values));
	EXPECT_EQ(1u, CommandSettingsEditor::Create()->CustomMenuItems(1).size());
}

//! カスタムメニューのインポート・エクスポート（*.mnu）
TEST_F(MacCommandSettingsTest, CustomMenuImportExport)
{
	auto editor = CommandSettingsEditor::Create();
	editor->SetCustomMenuName(3, u"Export");
	editor->SetCustomMenuItems(3, { { kSelectAll, u'A' } });
	const auto path = TempFile("menu.mnu");
	Text message;
	ASSERT_TRUE(editor->ExportCustomMenu(Text(path.u16string()), message));
	auto other = CommandSettingsEditor::Create();
	ASSERT_TRUE(other->ImportCustomMenu(Text(path.u16string()), message));
	EXPECT_EQ(u"Export", other->CustomMenuName(3));
	ASSERT_EQ(1u, other->CustomMenuItems(3).size());
	EXPECT_EQ(kSelectAll, other->CustomMenuItems(3)[0].code);
	{
		std::ofstream out(TempFile("bad.mnu"));
		out << "[CustMenu]\n";
	}
	EXPECT_FALSE(other->ImportCustomMenu(Text(TempFile("bad.mnu").u16string()), message));
	EXPECT_FALSE(message.empty());
}

//! ツールバー：ボタン番号、ボタンの機能とアイコン、区切・折返、写回
TEST_F(MacCommandSettingsTest, Toolbar)
{
	auto editor = CommandSettingsEditor::Create();
	ASSERT_TRUE(editor);
	const auto buttons = editor->ToolbarButtons();
	ASSERT_FALSE(buttons.empty());
	const auto first = editor->ToolbarButton(buttons.front());
	EXPECT_EQ(CommandSettingsEditor::ToolbarButtonKind::Button, first.kind);
	EXPECT_EQ(kFileNew, first.code);	// 原版の初期値の先頭は 新規作成
	EXPECT_GE(first.icon, 0);
	EXPECT_EQ(CommandSettingsEditor::ToolbarButtonKind::Separator, editor->ToolbarButton(editor->ToolbarSeparatorNumber()).kind);
	EXPECT_EQ(CommandSettingsEditor::ToolbarButtonKind::Wrap, editor->ToolbarButton(editor->ToolbarWrapNumber()).kind);
	EXPECT_EQ(CommandSettingsEditor::ToolbarButtonKind::Unknown, editor->ToolbarButton(100000).kind);
	const int copyButton = editor->ToolbarButtonNumber(kCopy);
	ASSERT_GE(copyButton, 0);
	EXPECT_EQ(kCopy, editor->ToolbarButton(copyButton).code);
	EXPECT_EQ(-1, editor->ToolbarButtonNumber(99999));	// ボタンが無い機能

	editor->SetToolbar({ copyButton, editor->ToolbarSeparatorNumber(), editor->ToolbarWrapNumber() }, true);
	const auto values = editor->IniValues(u"Toolbar");
	auto value = [&](const Text& key) {
		auto it = std::find_if(values.begin(), values.end(), [&](const auto& v) { return v.first == key; });
		return it == values.end() ? Text(u"<none>") : it->second;
	};
	EXPECT_EQ(u"3", value(u"nToolBarButtonNum"));
	EXPECT_EQ(u"1", value(u"bToolBarIsFlat"));
	EXPECT_EQ(u"", value(u"nTBB[003]"));	// 減った項目
	ASSERT_TRUE(SetCommonSettings(u"Toolbar", values));
	auto reloaded = CommandSettingsEditor::Create();
	EXPECT_EQ((std::vector<std::int32_t>{ copyButton, 0, 384 }), reloaded->ToolbarButtons());
	EXPECT_TRUE(reloaded->ToolbarIsFlat());
}
