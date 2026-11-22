/*! @file
	@brief 共通設定的读写（计划第 39 步：共通設定窗口）的测试

	共通設定窗口按 sakura.ini 的「节/项目」读写每一项（sakura::core::GetCommonSetting、SetCommonSetting）。这里确认：
	- 读出的值与 sakura.ini 的写法相同，改了以后 CommonSetting 的成员也变了
	- 值的范围限制与原版读入 sakura.ini 时相同（例：ファイルの履歴MAX 最大 36）
	- 改一项不影响同一节的其他项
	- 没有的项目、共通設定窗口不用的节不改
	- 一次改几项（SetCommonSettings）：ファイル名表示 的置換リスト的项数可以变；有一项不行时什么也不改
	- SaveSettings 以后 sakura.ini 里是新的值，重新启动后也是
*/
/*
	Copyright (C) 2026, Sakura Editor Organization

	SPDX-License-Identifier: Zlib
*/
#include "pch.h"

#include "sakura_core/SakuraCore.h"

#include "env/DLLSHAREDATA.h"
#include "util/file.h"

#include <filesystem>
#include <fstream>
#include <iterator>
#include <string>

using namespace sakura::core;

namespace {

namespace fs = std::filesystem;

class MacCommonSettingTest : public ::testing::Test {
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
	static CommonSetting& Common() { return GetDllShareData().m_Common; }
};

std::string ReadAll(const fs::path& path)
{
	std::ifstream in(path, std::ios::binary);
	return std::string(std::istreambuf_iterator<char>(in), std::istreambuf_iterator<char>());
}

} // namespace

//! 读：与 sakura.ini 的写法相同（bool 是 0/1，数值是十进制，字符串原样）
TEST_F(MacCommonSettingTest, GetReturnsIniValue)
{
	Common().m_sGeneral.m_bIsFreeCursorMode = true;
	Common().m_sGeneral.m_nRepeatedScrollLineNum = CLayoutInt(7);
	wcscpy(Common().m_sFormat.m_szMidashiKigou, LTEXT("■□"));
	EXPECT_EQ(u"1", GetCommonSetting(u"Common", u"bIsFreeCursorMode"));
	EXPECT_EQ(u"7", GetCommonSetting(u"Common", u"nRepeatedScrollLineNum"));
	EXPECT_EQ(u"■□", GetCommonSetting(u"Common", u"szMidashiKigou"));
	Common().m_sGeneral.m_bIsFreeCursorMode = false;
	EXPECT_EQ(u"0", GetCommonSetting(u"Common", u"bIsFreeCursorMode"));

	// ファイル名表示、ステータスバー的节
	Common().m_sFileName.m_nTransformShortMaxWidth = 50;
	EXPECT_EQ(u"50", GetCommonSetting(u"Nickname", u"nShortPathMaxWidth"));
	Common().m_sStatusbar.m_bDispColByChar = true;
	EXPECT_EQ(u"1", GetCommonSetting(u"Statusbar", u"DispColByChar"));

	// 没有的项目、不用的节
	EXPECT_FALSE(GetCommonSetting(u"Common", u"NoSuchKey").has_value());
	EXPECT_FALSE(GetCommonSetting(u"Types(0)", u"szTypeName").has_value());
	EXPECT_FALSE(GetCommonSetting(u"MRU", u"_MRU_Counts").has_value());
}

//! 写：CommonSetting 的成员变了，同一节的其他项不变
TEST_F(MacCommonSettingTest, SetChangesOnlyThatItem)
{
	Common().m_sGeneral.m_bIsFreeCursorMode = false;
	Common().m_sGeneral.m_bExitConfirm = true;
	Common().m_sEdit.m_bAddCRLFWhenCopy = false;
	EXPECT_TRUE(SetCommonSetting(u"Common", u"bIsFreeCursorMode", u"1"));
	EXPECT_TRUE(Common().m_sGeneral.m_bIsFreeCursorMode);
	EXPECT_TRUE(Common().m_sGeneral.m_bExitConfirm);
	EXPECT_FALSE(Common().m_sEdit.m_bAddCRLFWhenCopy);

	EXPECT_TRUE(SetCommonSetting(u"Common", u"szDateFormat", u"yyyy/MM/dd (ddd)"));
	EXPECT_STREQ(LTEXT("yyyy/MM/dd (ddd)"), Common().m_sFormat.m_szDateFormat);
	EXPECT_EQ(u"yyyy/MM/dd (ddd)", GetCommonSetting(u"Common", u"szDateFormat"));

	EXPECT_TRUE(SetCommonSetting(u"Statusbar", u"DispUnicodeInSjis", u"1"));
	EXPECT_TRUE(Common().m_sStatusbar.m_bDispUniInSjis);
	EXPECT_TRUE(SetCommonSetting(u"Nickname", u"bShortPath", u"0"));
	EXPECT_FALSE(Common().m_sFileName.m_bTransformShortPath);
}

//! 范围限制与原版读入 sakura.ini 时相同
TEST_F(MacCommonSettingTest, SetAppliesOriginalLimits)
{
	EXPECT_TRUE(SetCommonSetting(u"Common", u"nMRUArrNum_MAX", u"1000"));
	EXPECT_EQ(MAX_MRU, Common().m_sGeneral.m_nMRUArrNum_MAX);
	EXPECT_EQ(std::to_string(MAX_MRU), [] { auto v = GetCommonSetting(u"Common", u"nMRUArrNum_MAX"); return std::string(v->begin(), v->end()); }());
	EXPECT_TRUE(SetCommonSetting(u"Common", u"nMRUArrNum_MAX", u"5"));
	EXPECT_EQ(5, Common().m_sGeneral.m_nMRUArrNum_MAX);
}

//! 没有的项目、不用的节：false，什么也不改
TEST_F(MacCommonSettingTest, SetRejectsUnknownItems)
{
	Common().m_sGeneral.m_bIsFreeCursorMode = false;
	EXPECT_FALSE(SetCommonSetting(u"Common", u"NoSuchKey", u"1"));
	EXPECT_FALSE(SetCommonSetting(u"Types(0)", u"szTypeName", u"x"));
	EXPECT_FALSE(SetCommonSetting(u"MRU", u"_MRU_Counts", u"0"));
	EXPECT_FALSE(Common().m_sGeneral.m_bIsFreeCursorMode);
}

//! 一次改几项：置換リスト的项数变多、变少（原版 CPropFileName::GetData 写 ArrNum 和 From%02d、To%02d）
TEST_F(MacCommonSettingTest, SetSeveralChangesFileNameList)
{
	auto& fileName = Common().m_sFileName;
	ASSERT_TRUE(SetCommonSettings(u"Nickname", { { u"ArrNum", u"0" } }));
	EXPECT_EQ(0, fileName.m_nTransformFileNameArrNum);
	EXPECT_FALSE(GetCommonSetting(u"Nickname", u"From00").has_value());

	// 一项一项地改不行（ArrNum 以外的项目还没有），一起改可以
	EXPECT_FALSE(SetCommonSetting(u"Nickname", u"From00", u"%HOME%\\"));
	EXPECT_TRUE(SetCommonSettings(u"Nickname", {
		{ u"ArrNum", u"2" }, { u"From00", u"%HOME%\\" }, { u"To00", u"~\\" }, { u"From01", u"C:\\Work\\" }, { u"To01", u"W:" },
	}));
	EXPECT_EQ(2, fileName.m_nTransformFileNameArrNum);
	EXPECT_STREQ(LTEXT("%HOME%\\"), fileName.m_szTransformFileNameFrom[0]);
	EXPECT_STREQ(LTEXT("~\\"), fileName.m_szTransformFileNameTo[0]);
	EXPECT_STREQ(LTEXT("C:\\Work\\"), fileName.m_szTransformFileNameFrom[1]);
	EXPECT_EQ(u"W:", GetCommonSetting(u"Nickname", u"To01"));

	// 变少：后面的项清空（原版读入时）
	EXPECT_TRUE(SetCommonSettings(u"Nickname", { { u"ArrNum", u"1" } }));
	EXPECT_EQ(1, fileName.m_nTransformFileNameArrNum);
	EXPECT_STREQ(LTEXT(""), fileName.m_szTransformFileNameFrom[1]);
	EXPECT_FALSE(GetCommonSetting(u"Nickname", u"From01").has_value());

	// 范围限制：最多 MAX_TRANSFORM_FILENAME 项
	EXPECT_TRUE(SetCommonSettings(u"Nickname", { { u"ArrNum", u"100" } }));
	EXPECT_EQ(MAX_TRANSFORM_FILENAME, fileName.m_nTransformFileNameArrNum);
}

//! 一次改几项：有一项不在这一节里时 false，别的项也不改
TEST_F(MacCommonSettingTest, SetSeveralRejectsAllWhenOneIsUnknown)
{
	Common().m_sFileName.m_nTransformFileNameArrNum = 1;
	wcscpy(Common().m_sFileName.m_szTransformFileNameFrom[0], LTEXT("A"));
	Common().m_sFileName.m_bTransformShortPath = true;
	EXPECT_FALSE(SetCommonSettings(u"Nickname", { { u"bShortPath", u"0" }, { u"From05", u"X" } }));
	EXPECT_TRUE(Common().m_sFileName.m_bTransformShortPath);
	EXPECT_FALSE(SetCommonSettings(u"Nickname", { { u"ArrNum", u"0" }, { u"NoSuchKey", u"1" } }));
	EXPECT_EQ(1, Common().m_sFileName.m_nTransformFileNameArrNum);
	EXPECT_STREQ(LTEXT("A"), Common().m_sFileName.m_szTransformFileNameFrom[0]);
	EXPECT_FALSE(SetCommonSettings(u"MRU", { { u"_MRU_Counts", u"0" } }));
}

//! 保存：sakura.ini 里是新的值，重新启动后也是
TEST_F(MacCommonSettingTest, SaveSettingsWritesIni)
{
	ASSERT_TRUE(SetCommonSetting(u"Common", u"bIsFreeCursorMode", u"1"));
	ASSERT_TRUE(SetCommonSetting(u"Common", u"szInyouKigou", u"> "));
	ASSERT_TRUE(SaveSettings());
	const auto ini = ReadAll(GetIniFileName());
	EXPECT_NE(std::string::npos, ini.find("bIsFreeCursorMode=1\r\n"));
	EXPECT_NE(std::string::npos, ini.find("szInyouKigou=> \r\n"));

	Shutdown(false);
	ASSERT_TRUE(Startup());
	EXPECT_TRUE(Common().m_sGeneral.m_bIsFreeCursorMode);
	EXPECT_STREQ(LTEXT("> "), Common().m_sFormat.m_szInyouKigou);
}
