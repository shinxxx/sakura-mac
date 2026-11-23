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
