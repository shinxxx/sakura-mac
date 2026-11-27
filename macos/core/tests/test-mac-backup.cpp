/*! @file
	@brief バックアップ（计划第 46 步：ファイルの安全機能）の测试

	- バックアップファイル名（原版 CBackupAgent::FormatBackUpPath）：.bak、拡張子を残す、日付・時刻（保存時・前回の更新時）、
	  連番、指定フォルダー（絶対・相対）、詳細設定（$0-$9、*、?、日付の書式）
	- バックアップの作成（MakeBackup）：内容と更新日時、連番の世代、作成前の確認（はい・いいえ・キャンセル、ごみ箱の文言）、
	  ごみ箱、書けないファイル、パスが作れないとき、コピーの失敗と保存前の確認（BackupBeforeSave）
	- Windows 官方版との対照：data/backup/cases.tsv の手順の結果が data/backup/expected.txt と同じ。
	  expected.txt は CI の backup-windows（macos/tools/backup/windows-backup.ps1）が Windows 官方版 sakura.exe で同じ手順をやって比べる。
	  环境变量 SAKURA_BACKUP_UPDATE=1 时不比较，写出 expected.txt。
*/
/*
	Copyright (C) 2026, Sakura Editor Organization

	SPDX-License-Identifier: Zlib
*/
#include "sakura_core/SakuraCore.h"

#include <gtest/gtest.h>

#include <algorithm>
#include <chrono>
#include <cstdlib>
#include <ctime>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

#include <sys/stat.h>
#include <utime.h>

using namespace sakura::core;

namespace {

namespace fs = std::filesystem;

Text T(const std::string& s)
{
	// テストの文字は ASCII と UTF-8 の日本語（u8 のバイト列をそのまま UTF-16 に）
	Text out;
	for (size_t i = 0; i < s.size();) {
		unsigned char c = static_cast<unsigned char>(s[i]);
		char32_t cp;
		int n;
		if (c < 0x80) { cp = c; n = 1; }
		else if ((c >> 5) == 6) { cp = c & 0x1F; n = 2; }
		else if ((c >> 4) == 14) { cp = c & 0x0F; n = 3; }
		else { cp = c & 0x07; n = 4; }
		for (int k = 1; k < n; ++k) cp = (cp << 6) | (static_cast<unsigned char>(s[i + k]) & 0x3F);
		i += n;
		if (cp >= 0x10000) {
			cp -= 0x10000;
			out += char16_t(0xD800 + (cp >> 10));
			out += char16_t(0xDC00 + (cp & 0x3FF));
		} else {
			out += char16_t(cp);
		}
	}
	return out;
}

std::string U8(const Text& s)
{
	return fs::path(s).string();
}

Text T(const fs::path& p) { return p.u16string(); }
Text T(const char* s) { return T(std::string(s)); }

//! 現地時刻でファイルの更新日時を決める
void SetLocalMtime(const fs::path& path, int year, int month, int day, int hour, int minute, int second)
{
	std::tm tm{};
	tm.tm_year = year - 1900;
	tm.tm_mon = month - 1;
	tm.tm_mday = day;
	tm.tm_hour = hour;
	tm.tm_min = minute;
	tm.tm_sec = second;
	tm.tm_isdst = -1;
	const std::time_t t = std::mktime(&tm);
	struct utimbuf times { t, t };
	ASSERT_EQ(0, ::utime(path.c_str(), &times));
}

std::string ReadAll(const fs::path& path)
{
	std::ifstream in(path, std::ios::binary);
	std::ostringstream ss;
	ss << in.rdbuf();
	return ss.str();
}

void WriteAll(const fs::path& path, const std::string& bytes)
{
	std::ofstream(path, std::ios::binary | std::ios::trunc) << bytes;
}

//! 呼ばれた確認・エラー・ごみ箱を記録して、決めた答えを返す
struct RecordingHandler : BackupHandler {
	std::vector<BackupAnswer> answers;		//!< 順に返す答え（足りなければ Yes）
	struct Call { std::string kind; Text title; Text message; bool withCancel = false; };
	std::vector<Call> calls;
	bool trashResult = true;

	BackupAnswer Confirm(const Text& title, const Text& message, bool withCancel) override
	{
		calls.push_back({ "confirm", title, message, withCancel });
		if (answers.empty()) return BackupAnswer::Yes;
		const auto a = answers.front();
		answers.erase(answers.begin());
		return a;
	}
	void ShowError(const Text& title, const Text& message) override { calls.push_back({ "error", title, message }); }
	bool MoveToTrash(const Text& path) override
	{
		calls.push_back({ "trash", Text(), path });
		std::error_code ec;
		fs::remove(fs::path(path), ec);	// テストではごみ箱の代わりに消す
		return trashResult;
	}
};

class MacBackupTest : public ::testing::Test {
protected:
	void SetUp() override
	{
		ASSERT_TRUE(Startup());
		// ctest は並行して別のプロセスで実行するので、テストごとに別のフォルダー
		m_dir = fs::temp_directory_path() / (std::string("sakura-mac-backup-test-") + ::testing::UnitTest::GetInstance()->current_test_info()->name());
		fs::remove_all(m_dir);
		fs::create_directories(m_dir / "sub" / "proj");
		m_dir = fs::canonical(m_dir);
		// 既定：作成する、確認しない、ごみ箱に入れない
		Set({ { u"bBackUp", u"1" }, { u"bBackUpDialog", u"0" }, { u"bBackUpDustBox", u"0" }, { u"bBackUpFolder", u"0" },
			  { u"bBackUpFolderRM", u"0" }, { u"bBackUpPathAdvanced", u"0" }, { u"nBackUpType", u"1" } });
	}
	void TearDown() override
	{
		std::error_code ec;
		fs::permissions(m_dir, fs::perms::owner_all, fs::perm_options::add, ec);
		fs::remove_all(m_dir, ec);
		Shutdown(false);
	}
	void Set(const std::vector<std::pair<Text, Text>>& values) { ASSERT_TRUE(SetCommonSettings(u"Common", values)); }

	//! sub/proj/<name> を作る
	fs::path MakeFile(const std::string& name, const std::string& content = "old")
	{
		const auto path = m_dir / "sub" / "proj" / name;
		WriteAll(path, content);
		return path;
	}
	std::string Format(const fs::path& target, const BackupTime* now = nullptr)
	{
		const auto r = FormatBackupPath(T(target), now);
		if (!r) return "(none)";
		return U8(*r);
	}
	//! m_dir からの相対
	std::string Rel(const std::string& abs)
	{
		const std::string base = m_dir.string() + "/";
		return abs.rfind(base, 0) == 0 ? abs.substr(base.size()) : abs;
	}
	fs::path m_dir;
};

const BackupTime kNow{ 2026, 3, 4, 5, 6, 7 };

} // namespace

TEST_F(MacBackupTest, FormatTypes)
{
	const auto file = MakeFile("memo.txt");
	SetLocalMtime(file, 2025, 12, 31, 23, 59, 58);

	Set({ { u"nBackUpType", u"1" } });
	EXPECT_EQ("sub/proj/memo.bak", Rel(Format(file)));
	Set({ { u"nBackUpType", u"5" } });
	EXPECT_EQ("sub/proj/memo.txt.bak", Rel(Format(file)));

	// 保存時の日付・時刻（BKUP_YEAR 32 … BKUP_SEC 1）
	Set({ { u"nBackUpType", u"2" }, { u"bBackUpType2_Opt1", u"63" } });
	EXPECT_EQ("sub/proj/memo_20260304050607.txt", Rel(Format(file, &kNow)));
	Set({ { u"bBackUpType2_Opt1", u"56" } });	// 年月日
	EXPECT_EQ("sub/proj/memo_20260304.txt", Rel(Format(file, &kNow)));
	Set({ { u"bBackUpType2_Opt1", u"0" } });
	EXPECT_EQ("sub/proj/memo_.txt", Rel(Format(file, &kNow)));
	Set({ { u"bBackUpType2_Opt1", u"64" } });	// BKUP_AUTO（自動保存）は名前に関係ない
	EXPECT_EQ("sub/proj/memo_.txt", Rel(Format(file, &kNow)));

	// 前回の更新時の日付・時刻
	Set({ { u"nBackUpType", u"4" }, { u"bBackUpType2_Opt1", u"63" } });
	EXPECT_EQ("sub/proj/memo_20251231235958.txt", Rel(Format(file, &kNow)));
	Set({ { u"bBackUpType2_Opt1", u"6" } });	// 時分
	EXPECT_EQ("sub/proj/memo_2359.txt", Rel(Format(file, &kNow)));

	// 連番（拡張子の先頭の文字は bBackUpType2_Opt2 の 16 ビット目から）
	Set({ { u"nBackUpType", u"3" }, { u"bBackUpType2_Opt2", T(std::to_string(('b' << 16) | 5)) } });
	EXPECT_EQ("sub/proj/memo.b00", Rel(Format(file)));
	Set({ { u"nBackUpType", u"6" }, { u"bBackUpType2_Opt2", T(std::to_string(('q' << 16) | 5)) } });
	EXPECT_EQ("sub/proj/memo.txt.q00", Rel(Format(file)));
}

TEST_F(MacBackupTest, FormatNameEdgeCases)
{
	// 拡張子なし・先頭の「.」（原版 _wsplitpath と同じく「.」からが拡張子）・拡張子が二つ・日本語
	const auto noext = MakeFile("Makefile");
	const auto dot = MakeFile(".zshrc");
	const auto two = MakeFile("a.tar.gz");
	const auto jp = MakeFile("\xE3\x83\xA1\xE3\x83\xA2 1.txt");
	Set({ { u"nBackUpType", u"1" } });
	EXPECT_EQ("sub/proj/Makefile.bak", Rel(Format(noext)));
	EXPECT_EQ("sub/proj/.bak", Rel(Format(dot)));
	EXPECT_EQ("sub/proj/a.tar.bak", Rel(Format(two)));
	EXPECT_EQ("sub/proj/\xE3\x83\xA1\xE3\x83\xA2 1.bak", Rel(Format(jp)));
	Set({ { u"nBackUpType", u"5" } });
	EXPECT_EQ("sub/proj/.zshrc.bak", Rel(Format(dot)));
	EXPECT_EQ("sub/proj/a.tar.gz.bak", Rel(Format(two)));
	Set({ { u"nBackUpType", u"3" } });
	EXPECT_EQ("sub/proj/Makefile.b00", Rel(Format(noext)));
}

TEST_F(MacBackupTest, FormatFolder)
{
	const auto file = MakeFile("memo.txt");
	// 絶対パス（最後の「/」はあってもなくても）
	Set({ { u"bBackUpFolder", u"1" }, { u"szBackUpFolder", T(m_dir / "bk") } });
	EXPECT_EQ("bk/memo.bak", Rel(Format(file)));
	Set({ { u"szBackUpFolder", T((m_dir / "bk").string() + "/") } });
	EXPECT_EQ("bk/memo.bak", Rel(Format(file)));
	// 相対パス：対象ファイルのフォルダーから（Mac 版）
	Set({ { u"szBackUpFolder", u"backup" } });
	EXPECT_EQ("sub/proj/backup/memo.bak", Rel(Format(file)));
	Set({ { u"szBackUpFolder", u"../old/" } });
	EXPECT_EQ("sub/old/memo.bak", Rel(Format(file)));
	// 「指定フォルダーに作成する」が off なら使わない
	Set({ { u"bBackUpFolder", u"0" } });
	EXPECT_EQ("sub/proj/memo.bak", Rel(Format(file)));
	// リムーバブルメディアのみ：ローカルのディスクでは使わない
	Set({ { u"bBackUpFolder", u"1" }, { u"bBackUpFolderRM", u"1" }, { u"szBackUpFolder", T(m_dir / "bk") } });
	EXPECT_EQ("sub/proj/memo.bak", Rel(Format(file)));
}

TEST_F(MacBackupTest, FormatAdvanced)
{
	const auto file = MakeFile("memo.txt");
	SetLocalMtime(file, 2024, 2, 29, 1, 2, 3);
	Set({ { u"bBackUpPathAdvanced", u"1" }, { u"bBackUpType2_Opt4", u"2" } });
	// $0 ファイル名、$1 一つ上のフォルダー名、$2 二つ上、* 拡張子、? → _、%Y 等は時刻
	Set({ { u"szBackUpPathAdvanced", u"$0_%Y%m%d_%H%M%S.*" } });
	EXPECT_EQ("sub/proj/memo_20260304_050607.txt", Rel(Format(file, &kNow)));
	Set({ { u"szBackUpPathAdvanced", u"$2-$1-$0.*?%y%%" } });
	EXPECT_EQ("sub/proj/sub-proj-memo.txt_26%", Rel(Format(file, &kNow)));
	// サブフォルダー（Mac 版の区切りは「/」）
	Set({ { u"szBackUpPathAdvanced", u"old/$0.*" } });
	EXPECT_EQ("sub/proj/old/memo.txt", Rel(Format(file, &kNow)));
	// $ の後が数字でないときはそのまま（原版と同じ）
	Set({ { u"szBackUpPathAdvanced", u"$a$0$" } });
	EXPECT_EQ("sub/proj/$amemo$", Rel(Format(file, &kNow)));
	// ないフォルダー（$9）は空
	Set({ { u"szBackUpPathAdvanced", u"x$9y" } });
	EXPECT_EQ("sub/proj/xy", Rel(Format(file, &kNow)));
	// ファイルの日付・時刻
	Set({ { u"bBackUpType2_Opt4", u"4" }, { u"szBackUpPathAdvanced", u"$0.%Y-%m-%d.%H%M%S.*" } });
	EXPECT_EQ("sub/proj/memo.2024-02-29.010203.txt", Rel(Format(file, &kNow)));
	// 指定フォルダーの後ろに付く
	Set({ { u"bBackUpFolder", u"1" }, { u"szBackUpFolder", T(m_dir / "bk") }, { u"szBackUpPathAdvanced", u"$1/$0.*" } });
	EXPECT_EQ("bk/proj/memo.txt", Rel(Format(file, &kNow)));
}

TEST_F(MacBackupTest, FormatTooLong)
{
	const auto file = MakeFile("memo.txt");
	Set({ { u"bBackUpPathAdvanced", u"1" }, { u"szBackUpPathAdvanced", T(std::string(100, 'a') + "$0$0$0$0$0$0$0$0$0$0$0$0$0$0$0$0$0$0$0$0$0$0$0$0$0$0$0$0$0$0$0$0$0$0$0$0$0$0$0$0") } });
	EXPECT_EQ("(none)", Format(file));
}

TEST_F(MacBackupTest, MakeBackupCopiesContentAndTime)
{
	const auto file = MakeFile("memo.txt", "hello\r\n");
	SetLocalMtime(file, 2025, 5, 6, 7, 8, 9);
	const auto before = fs::last_write_time(file);
	RecordingHandler h;
	EXPECT_EQ(BackupResult::Created, MakeBackup(T(file), h));
	EXPECT_TRUE(h.calls.empty());
	const auto bak = m_dir / "sub" / "proj" / "memo.bak";
	EXPECT_EQ("hello\r\n", ReadAll(bak));
	EXPECT_EQ(before, fs::last_write_time(bak));
	// もう一度：上書き
	WriteAll(file, "second");
	EXPECT_EQ(BackupResult::Created, MakeBackup(T(file), h));
	EXPECT_EQ("second", ReadAll(bak));
}

TEST_F(MacBackupTest, MakeBackupSerialGenerations)
{
	// 連番：世代数 3。保存のたびに .b00 が最新、古いものは番号が増え、3 つを超えると消える
	Set({ { u"nBackUpType", u"3" }, { u"bBackUpType2_Opt2", T(std::to_string(('b' << 16) | 3)) } });
	const auto file = MakeFile("memo.txt", "0");
	RecordingHandler h;
	for (int k = 1; k <= 5; ++k) {
		ASSERT_EQ(BackupResult::Created, MakeBackup(T(file), h)) << k;
		WriteAll(file, std::to_string(k));
	}
	const auto dir = m_dir / "sub" / "proj";
	EXPECT_EQ("4", ReadAll(dir / "memo.b00"));
	EXPECT_EQ("3", ReadAll(dir / "memo.b01"));
	EXPECT_EQ("2", ReadAll(dir / "memo.b02"));
	EXPECT_FALSE(fs::exists(dir / "memo.b03"));
	EXPECT_TRUE(h.calls.empty());

	// 世代数を 1 に減らすと、次の保存で .b00 だけになる
	Set({ { u"bBackUpType2_Opt2", T(std::to_string(('b' << 16) | 1)) } });
	ASSERT_EQ(BackupResult::Created, MakeBackup(T(file), h));
	EXPECT_EQ("5", ReadAll(dir / "memo.b00"));
	EXPECT_FALSE(fs::exists(dir / "memo.b01"));
	EXPECT_FALSE(fs::exists(dir / "memo.b02"));
}

TEST_F(MacBackupTest, MakeBackupCreatesOneFolderLevel)
{
	const auto file = MakeFile("memo.txt", "x");
	RecordingHandler h;
	// 一段だけ作る（原版 CreateDirectory）
	Set({ { u"bBackUpFolder", u"1" }, { u"szBackUpFolder", T(m_dir / "bk") } });
	EXPECT_EQ(BackupResult::Created, MakeBackup(T(file), h));
	EXPECT_EQ("x", ReadAll(m_dir / "bk" / "memo.bak"));
	// 二段は作れない → コピーの失敗
	Set({ { u"szBackUpFolder", T(m_dir / "a" / "b") } });
	EXPECT_EQ(BackupResult::FileError, MakeBackup(T(file), h));
	EXPECT_FALSE(fs::exists(m_dir / "a"));
}

TEST_F(MacBackupTest, MakeBackupConfirm)
{
	const auto file = MakeFile("memo.txt", "x");
	const auto bak = m_dir / "sub" / "proj" / "memo.bak";
	Set({ { u"bBackUpDialog", u"1" } });
	{
		// はい／いいえ／キャンセル（原版 STR_BACKUP_CONFORM_TITLE2・MSG2）
		RecordingHandler h;
		h.answers = { BackupAnswer::Yes };
		EXPECT_EQ(BackupResult::Created, MakeBackup(T(file), h));
		ASSERT_EQ(1u, h.calls.size());
		EXPECT_EQ("confirm", h.calls[0].kind);
		EXPECT_TRUE(h.calls[0].withCancel);
		EXPECT_EQ(T("バックアップ作成の確認"), h.calls[0].title);
		const std::string expected = "変更される前に、バックアップファイルを作成します。\nよろしいですか？  [いいえ(N)] を選ぶと作成せずに上書き（または名前を付けて）保存になります。\n\n"
			+ file.string() + "\n    ↓\n" + bak.string() + "\n\n";
		EXPECT_EQ(T(expected), h.calls[0].message);
		EXPECT_TRUE(fs::exists(bak));
	}
	fs::remove(bak);
	{
		RecordingHandler h;
		h.answers = { BackupAnswer::No };
		EXPECT_EQ(BackupResult::NotCreated, MakeBackup(T(file), h));
		EXPECT_FALSE(fs::exists(bak));
	}
	{
		RecordingHandler h;
		h.answers = { BackupAnswer::Cancel };
		EXPECT_EQ(BackupResult::Interrupt, MakeBackup(T(file), h));
		EXPECT_FALSE(fs::exists(bak));
		// 保存の前：中断
		RecordingHandler h2;
		h2.answers = { BackupAnswer::Cancel };
		EXPECT_FALSE(BackupBeforeSave(T(file), h2));
	}
	{
		// ごみ箱に放り込む：はい／いいえだけ（原版 STR_BACKUP_CONFORM_TITLE1・MSG1）、作ったらごみ箱へ
		Set({ { u"bBackUpDustBox", u"1" } });
		RecordingHandler h;
		h.answers = { BackupAnswer::Yes };
		EXPECT_EQ(BackupResult::Created, MakeBackup(T(file), h));
		ASSERT_EQ(2u, h.calls.size());
		EXPECT_FALSE(h.calls[0].withCancel);
		EXPECT_NE(Text::npos, h.calls[0].message.find(T("作成したバックアップファイルをごみ箱に放り込みます。\n")));
		EXPECT_EQ("trash", h.calls[1].kind);
		EXPECT_EQ(T(bak), h.calls[1].message);
	}
}

TEST_F(MacBackupTest, MakeBackupTrashWithoutDialog)
{
	Set({ { u"bBackUpDustBox", u"1" } });
	const auto file = MakeFile("memo.txt", "x");
	RecordingHandler h;
	EXPECT_EQ(BackupResult::Created, MakeBackup(T(file), h));
	ASSERT_EQ(1u, h.calls.size());
	EXPECT_EQ("trash", h.calls[0].kind);
}

TEST_F(MacBackupTest, MakeBackupNotWritableOrTooLong)
{
	// 書き込めないファイルは作らない（原版 _waccess(target, 2)）
	const auto file = MakeFile("memo.txt", "x");
	fs::permissions(file, fs::perms::owner_write | fs::perms::group_write | fs::perms::others_write, fs::perm_options::remove);
	RecordingHandler h;
	if (::access(file.c_str(), W_OK) != 0) {	// root で動かすと書けてしまう
		EXPECT_EQ(BackupResult::NotCreated, MakeBackup(T(file), h));
		EXPECT_FALSE(fs::exists(m_dir / "sub" / "proj" / "memo.bak"));
		EXPECT_TRUE(h.calls.empty());
	}
	fs::permissions(file, fs::perms::owner_write, fs::perm_options::add);

	// パスが作れない：「バックアップ先のパス作成中にエラーになりました。…」はい：保存を続ける、いいえ：中断
	Set({ { u"bBackUpPathAdvanced", u"1" }, { u"szBackUpPathAdvanced", T(std::string(250, 'a')) } });
	RecordingHandler yes;
	EXPECT_EQ(BackupResult::NotCreated, MakeBackup(T(file), yes));
	ASSERT_EQ(1u, yes.calls.size());
	EXPECT_EQ(Text(), yes.calls[0].title);
	EXPECT_FALSE(yes.calls[0].withCancel);
	EXPECT_EQ(T("バックアップ先のパス作成中にエラーになりました。\nパスが長すぎるか不正な書式です。\nバックアップを作成せずに上書き保存してよろしいですか？"), yes.calls[0].message);
	RecordingHandler no;
	no.answers = { BackupAnswer::No };
	EXPECT_EQ(BackupResult::Interrupt, MakeBackup(T(file), no));
}

TEST_F(MacBackupTest, BackupBeforeSave)
{
	const auto file = m_dir / "sub" / "proj" / "memo.txt";
	{
		// ファイルがまだない（新しいファイル）：何もしない
		RecordingHandler h;
		EXPECT_FALSE(IsBackupNeeded(T(file)));
		EXPECT_TRUE(BackupBeforeSave(T(file), h));
		EXPECT_TRUE(h.calls.empty());
	}
	WriteAll(file, "x");
	EXPECT_TRUE(IsBackupNeeded(T(file)));
	{
		// 「保存時にバックアップを作成する」が off：作らない
		Set({ { u"bBackUp", u"0" } });
		EXPECT_FALSE(IsBackupNeeded(T(file)));
		RecordingHandler h;
		EXPECT_TRUE(BackupBeforeSave(T(file), h));
		EXPECT_FALSE(fs::exists(m_dir / "sub" / "proj" / "memo.bak"));
		Set({ { u"bBackUp", u"1" } });
	}
	{
		RecordingHandler h;
		EXPECT_TRUE(BackupBeforeSave(T(file), h));
		EXPECT_TRUE(fs::exists(m_dir / "sub" / "proj" / "memo.bak"));
	}
	{
		// コピーの失敗：「バックアップの作成に失敗しました．元ファイルへの上書きを継続して行いますか．」
		Set({ { u"bBackUpFolder", u"1" }, { u"szBackUpFolder", T(m_dir / "a" / "b") } });
		RecordingHandler yes;
		EXPECT_TRUE(BackupBeforeSave(T(file), yes));
		ASSERT_EQ(1u, yes.calls.size());
		EXPECT_EQ(T("ファイル保存"), yes.calls[0].title);
		EXPECT_EQ(T("バックアップの作成に失敗しました．元ファイルへの上書きを継続して行いますか．"), yes.calls[0].message);
		EXPECT_FALSE(yes.calls[0].withCancel);
		RecordingHandler no;
		no.answers = { BackupAnswer::No };
		EXPECT_FALSE(BackupBeforeSave(T(file), no));
	}
}

//! data/backup/cases.tsv の手順（CI の backup-windows と同じ）の結果
TEST_F(MacBackupTest, BackupWindowsComparison)
{
	const fs::path data = fs::path(SAKURA_ROOT_DIR) / "macos" / "core" / "tests" / "data" / "backup";
	std::ifstream cases(data / "cases.tsv", std::ios::binary);
	ASSERT_TRUE(cases.good());
	std::string out;
	std::string line;
	while (std::getline(cases, line)) {
		if (!line.empty() && line.back() == '\r') line.pop_back();
		if (line.empty() || line[0] == '#') continue;
		std::vector<std::string> cols;
		for (size_t p = 0;;) {
			const auto q = line.find('\t', p);
			cols.push_back(line.substr(p, q == std::string::npos ? std::string::npos : q - p));
			if (q == std::string::npos) break;
			p = q + 1;
		}
		ASSERT_EQ(3u, cols.size()) << line;
		const std::string name = cols[0];
		const int saves = std::stoi(cols[1]);
		const fs::path dir = m_dir / "cases" / name;
		fs::create_directories(dir);

		std::vector<std::pair<Text, Text>> values = { { u"bBackUp", u"1" }, { u"bBackUpDialog", u"0" }, { u"bBackUpDustBox", u"0" },
			{ u"bBackUpFolder", u"0" }, { u"bBackUpFolderRM", u"0" }, { u"bBackUpPathAdvanced", u"0" }, { u"nBackUpType", u"1" },
			{ u"bBackUpType2_Opt1", u"0" }, { u"bBackUpType2_Opt2", T(std::to_string(('b' << 16) | 10)) }, { u"bBackUpType2_Opt4", u"0" },
			{ u"szBackUpFolder", u"" }, { u"szBackUpPathAdvanced", u"" } };
		for (size_t p = 0; p <= cols[2].size();) {
			auto q = cols[2].find(';', p);
			if (q == std::string::npos) q = cols[2].size();
			const std::string kv = cols[2].substr(p, q - p);
			p = q + 1;
			if (kv.empty()) continue;
			const auto eq = kv.find('=');
			std::string value = kv.substr(eq + 1);
			if (const auto at = value.find("@DIR@"); at != std::string::npos) value.replace(at, 5, dir.string());
			const Text key = T(kv.substr(0, eq));
			auto it = std::find_if(values.begin(), values.end(), [&](const auto& v) { return v.first == key; });
			if (it != values.end()) it->second = T(value); else values.emplace_back(key, T(value));
		}
		Set(values);

		const fs::path file = dir / "test.txt";
		WriteAll(file, "0");
		for (int k = 1; k <= saves; ++k) {
			SetLocalMtime(file, 2026, 1, k, 10, 20, 30 + k);
			RecordingHandler h;
			ASSERT_TRUE(BackupBeforeSave(T(file), h)) << name << " " << k;
			EXPECT_TRUE(h.calls.empty()) << name;
			WriteAll(file, std::to_string(k));
		}

		// フォルダーの中のファイル（相対パス、'/' 区切り、名前の順）と内容
		std::vector<std::string> files;
		for (const auto& e : fs::recursive_directory_iterator(dir)) {
			if (!e.is_regular_file()) continue;
			files.push_back(fs::relative(e.path(), dir).generic_string());
		}
		std::sort(files.begin(), files.end());
		out += "== " + name + " ==\n";
		for (const auto& f : files) out += f + ": " + ReadAll(dir / f) + "\n";
	}

	const fs::path expected = data / "expected.txt";
	if (const char* u = std::getenv("SAKURA_BACKUP_UPDATE"); u && std::string(u) == "1") {
		std::ofstream(expected, std::ios::binary) << out;
		return;
	}
	EXPECT_EQ(ReadAll(expected), out);
}
