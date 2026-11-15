/*! @file
	@brief 最近使ったファイル、最近使ったフォルダー（计划第 31 步）的测试

	原版 CMRUFile、CMRUFolder、CMruListener 在核心库里的移植：
	- 打开、保存、关闭时登记到历史（sakura.ini 的 [MRU]），文件夹也登记
	- 历史里有的文件：自动识别的结果与上次不同时用上次的编码（或者问用户）
	- 打开时恢复上次的光标位置（「カーソル位置を復元する」）
	- 完成标志的核心部分：App 重启（Shutdown → Startup）后历史还在，能用上次的编码和位置打开
*/
/*
	Copyright (C) 2026, Sakura Editor Organization

	SPDX-License-Identifier: Zlib
*/
#include "pch.h"
#include "sakura_core/SakuraCore.h"

#include "env/DLLSHAREDATA.h"

#include <cstdlib>
#include <filesystem>
#include <fstream>

namespace fs = std::filesystem;
using namespace sakura::core;

namespace {

void WriteBytes(const fs::path& path, const std::string& bytes)
{
	std::ofstream out(path, std::ios::binary);
	out.write(bytes.data(), static_cast<std::streamsize>(bytes.size()));
}

Text ToText(const fs::path& path)
{
	return path.u16string();
}

class MacRecentTest : public ::testing::Test {
protected:
	void SetUp() override
	{
		ASSERT_TRUE(Startup());
		m_dir = fs::path(std::getenv("HOME")) / "recent-work";
		fs::remove_all(m_dir);
		fs::create_directories(m_dir);
		ClearHistory();
	}
	void TearDown() override
	{
		ClearHistory();
		Shutdown(false);
		std::error_code ec;
		fs::remove_all(m_dir, ec);
	}
	static void ClearHistory()
	{
		for (const auto& r : RecentFiles()) RemoveRecentFile(r.path);
	}
	fs::path File(const char* name, const std::string& bytes)
	{
		const auto path = m_dir / name;
		WriteBytes(path, bytes);
		return path;
	}
	static std::unique_ptr<Document> Open(const fs::path& path, const OpenOptions& options = {})
	{
		auto doc = Document::Create();
		EXPECT_NE(nullptr, doc);
		EXPECT_EQ(Result::Ok, doc->Open(ToText(path), options));
		return doc;
	}
	static OpenOptions WithEncoding(Encoding code)
	{
		OpenOptions options;
		options.encoding = code;
		return options;
	}

	fs::path m_dir;
};

} // namespace

TEST_F(MacRecentTest, OpenAddsFileAndFolderToHistory)
{
	const auto a = File("a.txt", "abc\n");
	const auto b = File("b.txt", "\xEF\xBB\xBF" "xyz\n");
	Open(a);
	Open(b);
	const auto files = RecentFiles();
	ASSERT_LE(2u, files.size());
	// 新的在前
	EXPECT_EQ(ToText(b), files[0].path);
	EXPECT_EQ(ToText(a), files[1].path);
	EXPECT_EQ(encoding::UTF8, files[0].encoding);
	// 菜单的文字：快捷键、路径、SJIS 以外的编码（原版 GetMenuFullLabel_MRU）
	EXPECT_NE(Text::npos, files[0].menuLabel.find(ToText(b))) ;
	EXPECT_EQ(u'&', files[0].menuLabel[0]);
	EXPECT_NE(Text::npos, files[0].menuLabel.find(u"[UTF-8]"));

	const auto folders = RecentFolders();
	ASSERT_LE(1u, folders.size());
	EXPECT_EQ(ToText(m_dir) + u"/", folders[0].path);
	EXPECT_NE(Text::npos, folders[0].menuLabel.find(ToText(m_dir)));

	// 同じファイルは 1 件
	Open(a);
	EXPECT_EQ(ToText(a), RecentFiles()[0].path);
	EXPECT_EQ(ToText(b), RecentFiles()[1].path);
}

TEST_F(MacRecentTest, NoHistoryOptionAndUntitledDocument)
{
	const auto a = File("a.txt", "abc\n");
	OpenOptions options;
	options.useHistory = false;
	auto doc = Open(a, options);
	EXPECT_FALSE(FindRecentFile(ToText(a)).has_value());
	EXPECT_FALSE(doc->GetRestoredView().has_value());
	doc->AddToRecent(Position{ 0, 1 }, 0);
	EXPECT_TRUE(FindRecentFile(ToText(a)).has_value());

	// 新文件不登记
	const auto before = RecentFiles().size();
	Document::Create()->AddToRecent(Position{}, 0);
	EXPECT_EQ(before, RecentFiles().size());
}

TEST_F(MacRecentTest, RestoresCaretPosition)
{
	const auto a = File("a.txt", "line1\nline2 long\nline3\n");
	{
		auto doc = Open(a);
		EXPECT_FALSE(doc->GetRestoredView().has_value()) << "第一次打开时没有历史";
		doc->AddToRecent(Position{ 1, 4 }, 1);	// 关闭前（CMruListener::OnBeforeClose）
	}
	const auto found = FindRecentFile(ToText(a));
	ASSERT_TRUE(found.has_value());
	EXPECT_EQ((Position{ 1, 4 }), found->caret);
	EXPECT_EQ(1, found->viewTopLine);

	auto doc = Open(a);
	const auto view = doc->GetRestoredView();
	ASSERT_TRUE(view.has_value());
	EXPECT_EQ((Position{ 1, 4 }), view->caret);
	EXPECT_EQ(1, view->viewTopLine);
	EXPECT_FALSE(view->toEnd);
}

TEST_F(MacRecentTest, RestoredCaretIsClampedToLineAndFile)
{
	const auto a = File("a.txt", "abc\nde\n");
	Open(a)->AddToRecent(Position{ 1, 10 }, 0);
	auto view = Open(a)->GetRestoredView();
	ASSERT_TRUE(view.has_value());
	EXPECT_EQ((Position{ 1, 2 }), view->caret) << "不放在换行符的中间";

	Open(a)->AddToRecent(Position{ 9, 0 }, 0);
	view = Open(a)->GetRestoredView();
	ASSERT_TRUE(view.has_value());
	EXPECT_TRUE(view->toEnd) << "超过文件末尾时移到文件末尾（原版 F_GOFILEEND）";
	EXPECT_EQ((Position{ 2, 0 }), view->caret);
}

TEST_F(MacRecentTest, RestoreCaretDisabled)
{
	const auto a = File("a.txt", "abc\nde\n");
	Open(a)->AddToRecent(Position{ 1, 1 }, 0);
	GetDllShareData().m_Common.m_sFile.m_bRestoreCurPosition = false;
	EXPECT_FALSE(Open(a)->GetRestoredView().has_value());
	GetDllShareData().m_Common.m_sFile.m_bRestoreCurPosition = true;
}

TEST_F(MacRecentTest, AutoDetectUsesPreviousEncoding)
{
	// SJIS の「あ」：自動判別では SJIS。前回 Latin1 で開いていたら Latin1（CMruListener::OnBeforeLoad）
	const auto a = File("a.txt", "\x82\xA0\r\n");
	EXPECT_EQ(encoding::SJIS, Open(a)->GetFileInfo().encoding);
	EXPECT_EQ(encoding::Latin1, Open(a, WithEncoding(encoding::Latin1))->GetFileInfo().encoding) << "指定した编码优先";
	EXPECT_EQ(encoding::Latin1, FindRecentFile(ToText(a))->encoding);
	EXPECT_EQ(encoding::Latin1, Open(a)->GetFileInfo().encoding) << "不问时自动识别用上次的编码";
}

TEST_F(MacRecentTest, AsksWhenEncodingDiffersFromPrevious)
{
	const auto a = File("a.txt", "\x82\xA0\r\n");
	Open(a, WithEncoding(encoding::Latin1));
	ASSERT_TRUE(GetDllShareData().m_Common.m_sFile.GetQueryIfCodeChange()) << "默认是问";

	int asked = 0;
	OpenOptions options;
	options.askUsePreviousEncoding = [&](Encoding current, Encoding previous) {
		++asked;
		EXPECT_EQ(encoding::SJIS, current);
		EXPECT_EQ(encoding::Latin1, previous);
		return false;	// いいえ：这次的编码
	};
	EXPECT_EQ(encoding::SJIS, Open(a, options)->GetFileInfo().encoding);
	EXPECT_EQ(1, asked);
	// 上次已经是 SJIS：一样就不问
	EXPECT_EQ(encoding::SJIS, Open(a, options)->GetFileInfo().encoding);
	EXPECT_EQ(1, asked);

	// はい：上次的编码
	Open(a, WithEncoding(encoding::Latin1));
	options.askUsePreviousEncoding = [&](Encoding, Encoding) { ++asked; return true; };
	EXPECT_EQ(encoding::Latin1, Open(a, options)->GetFileInfo().encoding);
	EXPECT_EQ(2, asked);

	// 共通设置关掉时不问
	GetDllShareData().m_Common.m_sFile.SetQueryIfCodeChange(false);
	options.askUsePreviousEncoding = [&](Encoding, Encoding) { ++asked; return false; };
	options.encoding = encoding::SJIS;
	EXPECT_EQ(encoding::SJIS, Open(a, options)->GetFileInfo().encoding) << "指定时用指定的编码";
	EXPECT_EQ(2, asked);
	GetDllShareData().m_Common.m_sFile.SetQueryIfCodeChange(true);
}

TEST_F(MacRecentTest, RemoveAndMaxCount)
{
	const auto a = File("a.txt", "a");
	Open(a);
	RemoveRecentFile(ToText(a));
	EXPECT_FALSE(FindRecentFile(ToText(a)).has_value());

	// 菜单里显示「ファイルの履歴MAX」（默认 15）个
	for (int i = 0; i < 20; ++i) {
		Open(File(("f" + std::to_string(i) + ".txt").c_str(), "x"));
	}
	EXPECT_EQ(15u, RecentFiles().size());
	EXPECT_EQ(ToText(m_dir / "f19.txt"), RecentFiles()[0].path);
	EXPECT_TRUE(FindRecentFile(ToText(m_dir / "f0.txt")).has_value()) << "菜单里不显示的也留在历史里";
}

//! 完成标志的核心部分：重启后历史还在（写进 sakura.ini，下次启动读回来）
TEST_F(MacRecentTest, HistorySurvivesRestart)
{
	const auto a = File("a.txt", "\x82\xA0\r\nxyz\r\n");
	Open(a, WithEncoding(encoding::Latin1))->AddToRecent(Position{ 1, 2 }, 0);
	Shutdown(true);
	ASSERT_TRUE(Startup());

	const auto files = RecentFiles();
	ASSERT_FALSE(files.empty());
	EXPECT_EQ(ToText(a), files[0].path);
	EXPECT_EQ(encoding::Latin1, files[0].encoding);
	auto doc = Open(a);
	EXPECT_EQ(encoding::Latin1, doc->GetFileInfo().encoding);
	ASSERT_TRUE(doc->GetRestoredView().has_value());
	EXPECT_EQ((Position{ 1, 2 }), doc->GetRestoredView()->caret);

	// 后面的测试不受影响
	ClearHistory();
	Shutdown(true);
	ASSERT_TRUE(Startup());
}
