/*! @file
	@brief 主菜单、按键分配（计划第 34 步）的测试

	核心库按原版的 MainMenu.ini（共通設定の m_sMainMenu）和按键分配表（m_sKeyBind、CKeyBind.cpp の KeyDataInit）
	提供菜单栏的构成和按键对应的功能。这里确认：
	- 顶层菜单的名字和顺序、子菜单的层次、分隔线、特殊列表（最近使ったファイル等）与原版相同
	- 菜单项的名字：MainMenu.ini 里没有名字时用功能名（原版 CMainMenu の LS(funccode)）
	- 默认的按键分配（Ctrl+C 是コピー、F3 是次を検索等）和没有分配的组合
*/
/*
	Copyright (C) 2026, Sakura Editor Organization

	SPDX-License-Identifier: Zlib
*/
#include "sakura_core/SakuraCore.h"

#include <gtest/gtest.h>

#include <algorithm>
#include <string>
#include <vector>

using namespace sakura::core;

namespace {

Text T(const char16_t* s) { return Text(s); }

class MacMenuTest : public ::testing::Test {
protected:
	void SetUp() override { ASSERT_TRUE(Startup()); }
	void TearDown() override { Shutdown(false); }

	//! 顶层菜单（level 0）
	static std::vector<MenuItem> TopMenus(const std::vector<MenuItem>& menu)
	{
		std::vector<MenuItem> r;
		std::copy_if(menu.begin(), menu.end(), std::back_inserter(r), [](const MenuItem& m) { return m.level == 0; });
		return r;
	}

	//! 这个顶层菜单下面的全部项目（下一个顶层菜单之前）
	static std::vector<MenuItem> Children(const std::vector<MenuItem>& menu, FunctionCode top)
	{
		std::vector<MenuItem> r;
		bool in = false;
		for (const auto& m : menu) {
			if (m.level == 0) in = (m.code == top);
			else if (in) r.push_back(m);
		}
		return r;
	}

	static const MenuItem* Find(const std::vector<MenuItem>& items, FunctionCode code)
	{
		auto it = std::find_if(items.begin(), items.end(), [code](const MenuItem& m) { return m.code == code; });
		return it == items.end() ? nullptr : &*it;
	}
};

} // namespace

// 顶层菜单：原版 MainMenu.ini 的 8 个（ファイル～ヘルプ），顺序相同
TEST_F(MacMenuTest, TopMenusAreSameAsOriginal)
{
	auto top = TopMenus(MainMenu());
	ASSERT_EQ(top.size(), 8u);
	const FunctionCode codes[] = { 34052, 34053, 34054, 34055, 34056, 34057, 34058, 34059 };
	const char16_t* names[] = { u"ファイル", u"編集", u"変換", u"検索", u"ツール", u"設定", u"ウィンドウ", u"ヘルプ" };
	for (size_t i = 0; i < top.size(); ++i) {
		EXPECT_EQ(top[i].type, MenuItemType::Submenu);
		EXPECT_EQ(top[i].code, codes[i]);
		EXPECT_EQ(top[i].name, T(names[i]));
	}
	EXPECT_EQ(top[0].accessKey, T(u"F"));
}

// ファイル菜单的开头部分：顺序、分隔线、子菜单「開き直す」的层次
TEST_F(MacMenuTest, FileMenuOrderAndLevels)
{
	auto file = Children(MainMenu(), 34052);
	ASSERT_GE(file.size(), 14u);
	EXPECT_EQ(file[0].code, 30101);		// 新規作成
	EXPECT_EQ(file[0].name, T(u"新規作成"));
	EXPECT_EQ(file[2].code, 30102);		// 開く...
	EXPECT_EQ(file[2].name, T(u"開く..."));
	EXPECT_EQ(file[3].code, 30103);		// 上書き保存
	EXPECT_EQ(file[6].type, MenuItemType::Separator);
	EXPECT_EQ(file[6].level, 1);

	// 開き直す（子菜单，level 1）下面是 level 2 的各编码
	auto* reopen = Find(file, 34005);
	ASSERT_NE(reopen, nullptr);
	EXPECT_EQ(reopen->type, MenuItemType::Submenu);
	EXPECT_EQ(reopen->level, 1);
	auto* sjis = Find(file, 30111);
	ASSERT_NE(sjis, nullptr);
	EXPECT_EQ(sjis->level, 2);
	EXPECT_EQ(sjis->name, T(u"SJISで開き直す"));
}

// 特殊列表：最近使ったファイル（29002）、最近使ったフォルダー（29003）、ウィンドウリスト（29001）
TEST_F(MacMenuTest, SpecialLists)
{
	auto menu = MainMenu();
	auto* recent = Find(menu, 34006);
	ASSERT_NE(recent, nullptr);
	EXPECT_EQ(recent->name, T(u"最近使ったファイル"));
	for (FunctionCode code : { 29001, 29002, 29003, 29004, 29005, 29006 }) {
		auto* special = Find(menu, code);
		ASSERT_NE(special, nullptr) << code;
		EXPECT_EQ(special->type, MenuItemType::Special) << code;
	}
	// 29002 紧跟在 34006 的下一层
	auto it = std::find_if(menu.begin(), menu.end(), [](const MenuItem& m) { return m.code == 34006; });
	ASSERT_NE(it + 1, menu.end());
	EXPECT_EQ((it + 1)->code, 29002);
	EXPECT_EQ((it + 1)->level, it->level + 1);
}

// 名字：MainMenu.ini 里没有写名字的项目用功能名（CommandName）
TEST_F(MacMenuTest, NamesComeFromCommandNames)
{
	auto menu = MainMenu();
	for (const auto& m : menu) {
		if (m.type == MenuItemType::Command) {
			EXPECT_FALSE(m.name.empty()) << m.code;
		}
		if (m.type == MenuItemType::Separator) {
			EXPECT_TRUE(m.name.empty());
		}
	}
	auto edit = Children(menu, 34053);
	ASSERT_NE(Find(edit, 30602), nullptr);
	EXPECT_EQ(Find(edit, 30602)->name, CommandName(30602));		// コピー
	EXPECT_EQ(Find(edit, 30602)->name, T(u"コピー"));
	auto search = Children(menu, 34055);
	ASSERT_NE(Find(search, 30904), nullptr);
	EXPECT_EQ(Find(search, 30904)->name, T(u"置換..."));
}

// 层次只会一层一层地变深（Mac 的菜单按 level 组装时不会断开）
TEST_F(MacMenuTest, LevelsAreNested)
{
	auto menu = MainMenu();
	ASSERT_FALSE(menu.empty());
	EXPECT_EQ(menu.front().level, 0);
	for (size_t i = 1; i < menu.size(); ++i) {
		EXPECT_LE(menu[i].level, menu[i - 1].level + 1) << i;
		if (menu[i].level > menu[i - 1].level) {
			EXPECT_EQ(menu[i - 1].type, MenuItemType::Submenu) << i;
		}
	}
}

// 默认的按键分配（原版 KeyDataInit）
TEST_F(MacMenuTest, DefaultKeyBindings)
{
	EXPECT_EQ(FunctionForKey('C', keymod::Ctrl), 30602);		// Ctrl+C コピー
	EXPECT_EQ(FunctionForKey('V', keymod::Ctrl), 30604);		// Ctrl+V 貼り付け
	EXPECT_EQ(FunctionForKey('X', keymod::Ctrl), 30601);		// Ctrl+X 切り取り
	EXPECT_EQ(FunctionForKey('Z', keymod::Ctrl), 30210);		// Ctrl+Z 元に戻す
	EXPECT_EQ(FunctionForKey('Y', keymod::Ctrl), 30211);		// Ctrl+Y やり直し
	EXPECT_EQ(FunctionForKey('F', keymod::Ctrl), 30901);		// Ctrl+F 検索
	EXPECT_EQ(FunctionForKey('R', keymod::Ctrl), 30904);		// Ctrl+R 置換
	EXPECT_EQ(FunctionForKey('J', keymod::Ctrl), 30920);		// Ctrl+J 指定行へジャンプ
	EXPECT_EQ(FunctionForKey(114, 0), 30902);					// F3 次を検索
	EXPECT_EQ(FunctionForKey(114, keymod::Shift), 30903);		// Shift+F3 前を検索
	EXPECT_EQ(FunctionForKey(36, 0), 30332);					// Home 行頭に移動(折り返し単位)
	EXPECT_EQ(FunctionForKey(36, keymod::Ctrl), 30350);			// Ctrl+Home ファイルの先頭に移動
	EXPECT_EQ(FunctionForKey(37, keymod::Alt), 30513);			// Alt+← (矩形選択)カーソル左移動
	EXPECT_EQ(FunctionForKey(27, 0), 31099);					// Esc 各種モードの取り消し
	EXPECT_EQ(FunctionForKey(9, 0), 30260);						// Tab TABインデント
	EXPECT_EQ(FunctionForKey(9, keymod::Shift), 30261);			// Shift+Tab 逆TABインデント
	EXPECT_EQ(FunctionForKey(45, keymod::Ctrl), 30602);			// Ctrl+Ins コピー
	EXPECT_EQ(FunctionForKey(46, keymod::Shift), 30601);		// Shift+Del 切り取り
	EXPECT_EQ(FunctionForKey(219, keymod::Ctrl), 30960);		// Ctrl+[ 対括弧の検索
}

// 没有分配的组合、不在表里的键是 0
TEST_F(MacMenuTest, UnassignedKeysAreZero)
{
	EXPECT_EQ(FunctionForKey('A', 0), 0);						// 字母键本身不分配（输入文字）
	EXPECT_EQ(FunctionForKey('A', keymod::Shift), 0);
	EXPECT_EQ(FunctionForKey(13, 0), 0);						// Enter 本身不分配（换行）
	EXPECT_EQ(FunctionForKey(0xFF, keymod::Ctrl), 0);			// 表里没有的键
	EXPECT_EQ(FunctionForKey(0x1234, 0), 0);					// 范围外
}

// KeyBindings 列出的都和 FunctionForKey 一致，并且不含鼠标（0x100 以上）
TEST_F(MacMenuTest, KeyBindingsListMatchesLookup)
{
	auto list = KeyBindings();
	EXPECT_GT(list.size(), 200u);
	for (const auto& k : list) {
		EXPECT_LT(k.keyCode, 0x100);
		EXPECT_NE(k.code, 0);
		EXPECT_LT(k.modifiers, 8);
		EXPECT_EQ(FunctionForKey(k.keyCode, k.modifiers), k.code) << k.keyCode << "/" << int(k.modifiers);
	}
	auto f1 = std::find_if(list.begin(), list.end(), [](const KeyBinding& k) { return k.keyCode == 112 && k.modifiers == 0; });
	ASSERT_NE(f1, list.end());
	EXPECT_EQ(f1->keyName, T(u"F1"));
}
