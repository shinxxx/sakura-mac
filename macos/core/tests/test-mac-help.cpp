/*! @file
	@brief 帮助（计划第 49 步）的测试

	sakura::core::HelpContextID（原版 FuncID_To_HelpContextID：菜单的 F1、对话框的「ヘルプ」按钮打开的话题）。这里确认：
	- 编号与原版相同（HLP000025 新規作成 等），没有的功能是 0
	- 「種別」「機能」里的全部功能的话题，在原版的帮助（help/sakura/sakura.hhp 的 [ALIAS]）里有页，页的文件也在
*/
/*
	Copyright (C) 2026, Sakura Editor Organization

	SPDX-License-Identifier: Zlib
*/
#include "pch.h"

#include "sakura_core/SakuraCore.h"
#include "util/file.h"

#include <filesystem>
#include <fstream>
#include <regex>
#include <set>
#include <sstream>
#include <string>

using namespace sakura::core;

namespace {

namespace fs = std::filesystem;

class MacHelpTest : public ::testing::Test {
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
};

fs::path HelpDir()
{
	return fs::path(SAKURA_ROOT_DIR) / "help" / "sakura";
}

//! sakura.hhp の [ALIAS]：HLP000025=res\HLP000025.html の 25
std::set<int> AliasTopics()
{
	std::ifstream in(HelpDir() / "sakura.hhp");
	std::stringstream ss;
	ss << in.rdbuf();
	const std::string text = ss.str();
	std::set<int> result;
	const auto begin = text.find("[ALIAS]");
	const auto end = text.find("[MAP]");
	if (begin == std::string::npos || end == std::string::npos) return result;
	const std::string alias = text.substr(begin, end - begin);
	static const std::regex re(R"(HLP(\d{6})=res\\HLP\d{6}\.html)");
	for (std::sregex_iterator it(alias.begin(), alias.end(), re), last; it != last; ++it) {
		result.insert(std::stoi((*it)[1].str()));
	}
	return result;
}

} // namespace

TEST_F(MacHelpTest, ContextIDsAreOriginal)
{
	EXPECT_EQ(25, HelpContextID(30101));	// F_FILENEW 新規作成 → HLP000025
	EXPECT_EQ(15, HelpContextID(30102));	// F_FILEOPEN 開く
	EXPECT_EQ(59, HelpContextID(30901));	// F_SEARCH_DIALOG 検索
	EXPECT_EQ(67, HelpContextID(30910));	// F_GREP_DIALOG Grep
	EXPECT_EQ(81, HelpContextID(32000));	// F_OPTION_GENERAL 共通設定『全般』
	EXPECT_EQ(75, HelpContextID(31116));	// F_TYPE_COLOR タイプ別設定『カラー』
	EXPECT_EQ(100, HelpContextID(31440));	// F_HELP_CONTENTS ヘルプ目次
	EXPECT_EQ(189, HelpContextID(31445));	// F_MENU_ALLFUNC コマンド一覧
	EXPECT_EQ(0, HelpContextID(0));			// F_0
	EXPECT_EQ(0, HelpContextID(99999));
}

TEST_F(MacHelpTest, EveryFunctionTopicHasPage)
{
	const auto topics = AliasTopics();
	ASSERT_GT(topics.size(), 300u);
	auto editor = CommandSettingsEditor::Create();
	ASSERT_TRUE(editor);
	const auto categories = editor->FunctionCategories();
	int checked = 0;
	for (std::int32_t category = 0; category < static_cast<std::int32_t>(categories.size()); ++category) {
		for (const auto& f : editor->Functions(category)) {
			const int id = HelpContextID(f.code);
			if (id == 0) continue;	// 外部マクロ・カスタムメニュー等：原版も話題なし
			++checked;
			EXPECT_TRUE(topics.count(id)) << "function " << f.code << " topic " << id;
			char name[32];
			std::snprintf(name, sizeof(name), "HLP%06d.html", id);
			EXPECT_TRUE(fs::exists(HelpDir() / "res" / name)) << name;
		}
	}
	EXPECT_GT(checked, 300);
}
