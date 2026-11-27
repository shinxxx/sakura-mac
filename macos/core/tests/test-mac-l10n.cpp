/*! @file
	@brief 界面本地化（计划第 48 步）的测试

	界面字符串（原版的 LS()）：日文是 Windows 版 sakura.exe 内置的（sakura_core/sakura_rc.rc），
	英文、中文是原版的语言包（sakura_lang/sakura_rc_en-US.rc、sakura_rc_zh-CN.rc）。这里确认：
	- 没有遗漏：日文有的编号英文、中文都有（语言包缺的由 macos/tools/l10n/rc_supplement.json 补上）
	- 英文里没有日文的文字，中文里没有假名（设置的数据「禁則」的文字等例外）
	- 选了语言以后，功能名、菜单、类型名等是那个语言
	- 换了语言时，设置里的默认文字（タイプ名「基本」、日付書式、印刷設定名）像原版一样换成新的语言，
	  sakura.ini 的 Common/szLanguageDll 写原版的语言 DLL 名
*/
/*
	Copyright (C) 2026, Sakura Editor Organization

	SPDX-License-Identifier: Zlib
*/
#include "pch.h"
#include "sakura_core/SakuraCore.h"
#include "sakura_platform_hooks.h"
#include "sakura_rc.h"
#include "Funccode_enum.h"

#include <gtest/gtest.h>

#include <filesystem>
#include <optional>
#include <set>
#include <string>
#include <vector>

using namespace sakura::core;

namespace {

std::size_t LanguageIndex(const char* name)
{
	for (std::size_t i = 0; i < sakura::platform::ResourceLanguageCount(); ++i) {
		if (std::string(sakura::platform::ResourceLanguageName(i)) == name) return i;
	}
	return SIZE_MAX;
}

std::vector<UINT> Ids(std::size_t language)
{
	const std::size_t n = sakura::platform::ResourceStringIds(language, nullptr, 0);
	std::vector<UINT> ids(n);
	sakura::platform::ResourceStringIds(language, ids.data(), ids.size());
	return ids;
}

bool IsKana(char16_t c) { return (c >= 0x3040 && c <= 0x30FF) || (c >= 0xFF66 && c <= 0xFF9F); }
bool IsKanji(char16_t c) { return (c >= 0x3400 && c <= 0x9FFF); }

//! 不是界面的文字（设置的数据）：英文、中文里也是日文
const std::set<UINT> kNotUiText = {
	STR_ERR_CSHAREDATA14,	// 禁則の文字（共通設定の既定値。原版の語言包でも同じ）
	STR_ERR_DLGEDITVW2,		// 「大」（原版のどこからも使われていない）
};

std::u16string Load(std::size_t language, UINT id)
{
	sakura::wstring s;
	sakura::platform::LoadResourceStringIn(language, id, s);
	return std::u16string(s);
}

class MacL10nTest : public ::testing::Test {
protected:
	void TearDown() override
	{
		Shutdown(false);
		SetUILanguage(UILanguage::Japanese);
		// 保存した sakura.ini を消す（ほかのテストは既定の日本語の設定から始める）
		std::error_code ec;
		std::filesystem::remove(std::filesystem::path(std::u16string(SettingsFilePath())), ec);
	}
};

TEST_F(MacL10nTest, LanguagesAreJapaneseEnglishChinese)
{
	ASSERT_EQ(3u, sakura::platform::ResourceLanguageCount());
	EXPECT_STREQ("ja", sakura::platform::ResourceLanguageName(0));
	EXPECT_NE(SIZE_MAX, LanguageIndex("en"));
	EXPECT_NE(SIZE_MAX, LanguageIndex("zh"));
}

//! 没有遗漏：日文的全部编号英文、中文都有
TEST_F(MacL10nTest, EveryStringIsTranslated)
{
	const auto ja = Ids(0);
	ASSERT_GT(ja.size(), 1300u);
	for (const char* lang : { "en", "zh" }) {
		const auto index = LanguageIndex(lang);
		const auto ids = Ids(index);
		const std::set<UINT> have(ids.begin(), ids.end());
		for (const UINT id : ja) {
			EXPECT_TRUE(have.count(id)) << lang << " にない: " << id;
		}
	}
}

TEST_F(MacL10nTest, EnglishHasNoJapanese)
{
	const auto en = LanguageIndex("en");
	for (const UINT id : Ids(en)) {
		if (kNotUiText.count(id)) continue;
		const auto s = Load(en, id);
		for (const char16_t c : s) {
			if (IsKana(c) || IsKanji(c)) {
				ADD_FAILURE() << "英語に日本語: " << id;
				break;
			}
		}
	}
}

TEST_F(MacL10nTest, ChineseHasNoKana)
{
	const auto zh = LanguageIndex("zh");
	for (const UINT id : Ids(zh)) {
		if (kNotUiText.count(id)) continue;
		const auto s = Load(zh, id);
		for (const char16_t c : s) {
			if (IsKana(c)) {
				ADD_FAILURE() << "中国語に仮名: " << id;
				break;
			}
		}
	}
}

//! 语言包缺的编号由 rc_supplement.json 补上（原版的语言 DLL 里没有，Windows 版会显示日文）
TEST_F(MacL10nTest, SupplementFillsMissingStrings)
{
	EXPECT_EQ(u"Maximize", Load(LanguageIndex("en"), F_WINMAXIMIZE));
	EXPECT_EQ(u"最大化", Load(LanguageIndex("zh"), F_WINMAXIMIZE));
	EXPECT_EQ(u"Truncated because the maximum number (%d) was exceeded", Load(LanguageIndex("en"), STR_FILETREE_MAXCOUNT));
}

TEST_F(MacL10nTest, CommandNamesFollowLanguage)
{
	SetUILanguage(UILanguage::English);
	ASSERT_TRUE(Startup());
	EXPECT_EQ(UILanguage::English, GetUILanguage());
	EXPECT_EQ(u"New", CommandName(F_FILENEW));
	EXPECT_EQ(u"File", ResourceString(F_FILE_TOPMENU));
	Shutdown(false);

	SetUILanguage(UILanguage::Chinese);
	ASSERT_TRUE(Startup());
	EXPECT_EQ(u"新建", CommandName(F_FILENEW));
	EXPECT_EQ(u"文件", ResourceString(F_FILE_TOPMENU));
	Shutdown(false);

	SetUILanguage(UILanguage::Japanese);
	ASSERT_TRUE(Startup());
	EXPECT_EQ(u"新規作成", CommandName(F_FILENEW));
	EXPECT_EQ(u"ファイル", ResourceString(F_FILE_TOPMENU));
}

//! 主菜单：MainMenu.ini 没有名字的项目是功能名（原版 LayoutMainMenu）→ 选的语言
TEST_F(MacL10nTest, MainMenuFollowsLanguage)
{
	SetUILanguage(UILanguage::English);
	ASSERT_TRUE(Startup());
	const auto menu = MainMenu();
	ASSERT_FALSE(menu.empty());
	bool foundFile = false;
	for (const auto& m : menu) {
		if (m.level == 0 && m.code == F_FILE_TOPMENU) {
			foundFile = true;
			EXPECT_EQ(u"File", m.name);
		}
		for (const char16_t c : m.name) {
			if (IsKana(c) || IsKanji(c)) {
				ADD_FAILURE() << "英語のメニューに日本語: " << m.code;
				break;
			}
		}
	}
	EXPECT_TRUE(foundFile);
}

//! 起動時の言語が sakura.ini と違うとき、原版で言語を変えたときと同じく設定の既定の文字列を新しい言語にする
TEST_F(MacL10nTest, SwitchingLanguageConvertsDefaultValues)
{
	SetUILanguage(UILanguage::Japanese);
	ASSERT_TRUE(Startup());
	EXPECT_EQ(u"基本", TypeSettings().at(0).name);
	EXPECT_EQ(u"", GetCommonSetting(u"Common", u"szLanguageDll").value_or(u"?"));
	Shutdown(true);

	// 同じ sakura.ini を英語で開く
	SetUILanguage(UILanguage::English);
	ASSERT_TRUE(Startup());
	EXPECT_EQ(u"Default", TypeSettings().at(0).name);
	EXPECT_EQ(u"sakura_lang_en_US.dll", GetCommonSetting(u"Common", u"szLanguageDll").value_or(u"?"));
	EXPECT_EQ(u"M'/'d'/'yyyy dddd", GetCommonSetting(u"Common", u"szDateFormat").value_or(u"?"));
	Shutdown(true);

	// 英語で保存した sakura.ini をそのまま英語で開く：変わらない
	ASSERT_TRUE(Startup());
	EXPECT_EQ(u"Default", TypeSettings().at(0).name);
	Shutdown(true);

	// 中国語
	SetUILanguage(UILanguage::Chinese);
	ASSERT_TRUE(Startup());
	EXPECT_EQ(u"默认", TypeSettings().at(0).name);
	EXPECT_EQ(u"sakura_lang_zh_CN.dll", GetCommonSetting(u"Common", u"szLanguageDll").value_or(u"?"));
	Shutdown(true);

	// 日本語に戻す
	SetUILanguage(UILanguage::Japanese);
	ASSERT_TRUE(Startup());
	EXPECT_EQ(u"基本", TypeSettings().at(0).name);
	EXPECT_EQ(u"yyyy'年'M'月'd'日('dddd')'", GetCommonSetting(u"Common", u"szDateFormat").value_or(u"?"));
	EXPECT_EQ(u"", GetCommonSetting(u"Common", u"szLanguageDll").value_or(u"?"));
}

//! 起動したあとに言語を変える（テスト用。原版の共通設定で言語を変えたとき）
TEST_F(MacL10nTest, SetUILanguageAfterStartup)
{
	SetUILanguage(UILanguage::Japanese);
	ASSERT_TRUE(Startup());
	SetUILanguage(UILanguage::English);
	EXPECT_EQ(u"Default", TypeSettings().at(0).name);
	EXPECT_EQ(u"New", CommandName(F_FILENEW));
	SetUILanguage(UILanguage::Japanese);
	EXPECT_EQ(u"基本", TypeSettings().at(0).name);
	EXPECT_EQ(u"新規作成", CommandName(F_FILENEW));
}

} // namespace
