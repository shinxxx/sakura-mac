/*! @file
	@brief バックアップ（计划第 46 步：ファイルの安全機能）

	原版 CBackupAgent（sakura_core/agent/CBackupAgent.cpp）の OnPreBeforeSave・MakeBackUp・FormatBackUpPath の移植。
	原版は CEditDoc のリスナーで、メッセージボックスとごみ箱を自分で出す。Mac 版は文書の保存の流れ（SakuraDocument）から呼ばれ、
	メッセージボックスとごみ箱は界面層（BackupHandler）が行う。手順・書式・メッセージは原版と同じ。

	原版と違うところ：
	- パスの区切りは '/'（_wsplitpath の代わりに自分で分ける。拡張子は最後の '.' から、先頭の '.' も拡張子なのは原版と同じ）。
	- 「指定フォルダー」の相対パスは対象ファイルのフォルダーから（原版 GetFullPathName はカレントフォルダーから。
	  エクスプローラーから開くとファイルのフォルダーになることが多い）。
	- コピーは std::filesystem（原版 CopyFile と同じく更新日時も残す）。
*/
/*
	Copyright (C) 2008, kobake
	Copyright (C) 2018-2022, Sakura Editor Organization
	Copyright (C) 2026, Sakura Editor Organization

	SPDX-License-Identifier: Zlib
*/
#include "StdAfx.h"
#include "sakura_core/SakuraCore.h"

#include <cstdio>
#include <filesystem>
#include <system_error>

#include <unistd.h>

#include "env/DLLSHAREDATA.h"
#include "env/CFileNameManager.h"
#include "util/file.h"
#include "util/format.h"
#include "CSelectLang.h"
#include "sakura_rc.h"

namespace sakura::core {

namespace {

namespace fs = std::filesystem;

//! 原版 MAX_PATH 相当の長さの上限（SFilePath）。これを超えるとパスが作れない（原版 auto_sprintf_s の -1）
constexpr size_t kMaxPath = MAX_PATH;

//! rc の文字列（改行が CR LF のことがある）をメッセージボックスの文字に
Text ToMessage(Text s)
{
	for (size_t i = 0; (i = s.find(u"\r\n", i)) != Text::npos;) s.erase(i, 1);
	return s;
}

//! 原版の %s 一つ・二つのメッセージ
Text FormatMessage(const WCHAR* format, const Text& a, const Text& b)
{
	Text out;
	const Text args[] = { a, b };
	size_t n = 0;
	for (const WCHAR* p = format; *p; ++p) {
		if (p[0] == u'%' && p[1] == u's') {
			if (n < 2) out += args[n++];
			++p;
		} else if (p[0] == u'%' && p[1] == u'%') {
			out += u'%';
			++p;
		} else {
			out += *p;
		}
	}
	return ToMessage(out);
}

//! パスの分解（原版 _wsplitpath_s。Mac 版はドライブがない）：dir は最後の '/' まで（'/' を含む）、ext は '.' から
struct SplitPath {
	Text dir;
	Text fname;
	Text ext;
};
SplitPath Split(const Text& path)
{
	SplitPath r;
	const auto slash = path.rfind(u'/');
	const size_t nameStart = slash == Text::npos ? 0 : slash + 1;
	r.dir = path.substr(0, nameStart);
	const Text name = path.substr(nameStart);
	const auto dot = name.rfind(u'.');
	if (dot == Text::npos) {
		r.fname = name;
	} else {
		r.fname = name.substr(0, dot);
		r.ext = name.substr(dot);
	}
	return r;
}

fs::path ToPath(const Text& s) { return fs::path(s); }

bool Exists(const Text& path)
{
	std::error_code ec;
	return fs::exists(ToPath(path), ec);
}

//! ファイルの更新日時（現地時刻。原版 GetLastWriteTimestamp → CFileTime の SYSTEMTIME）
SYSTEMTIME LastWriteLocalTime(const Text& path)
{
	SYSTEMTIME st{};
	CFileTime ftime;
	if (GetLastWriteTimestamp(path.c_str(), &ftime)) {
		st = ftime.GetSYSTEMTIME();
	}
	return st;
}

SYSTEMTIME ToSystemTime(const BackupTime& t)
{
	SYSTEMTIME st{};
	st.wYear = static_cast<WORD>(t.year);
	st.wMonth = static_cast<WORD>(t.month);
	st.wDay = static_cast<WORD>(t.day);
	st.wHour = static_cast<WORD>(t.hour);
	st.wMinute = static_cast<WORD>(t.minute);
	st.wSecond = static_cast<WORD>(t.second);
	return st;
}

SYSTEMTIME Now(const BackupTime* now)
{
	if (now) return ToSystemTime(*now);
	SYSTEMTIME st{};
	::GetLocalTime(&st);
	return st;
}

Text TwoDigits(int n)
{
	char buf[16];
	std::snprintf(buf, sizeof(buf), "%02d", n);
	return Text(buf, buf + std::char_traits<char>::length(buf));
}

Text Decimal(int n)
{
	char buf[16];
	std::snprintf(buf, sizeof(buf), "%d", n);
	return Text(buf, buf + std::char_traits<char>::length(buf));
}

//! 「指定フォルダー」（原版 ExpandMetaToFolder → GetFullPathName → AddLastYenFromDirectoryPath）
Text BackupFolder(const CommonSetting_Backup& setting, const Text& targetDir)
{
	WCHAR selDir[_MAX_PATH] = {};
	CFileNameManager::ExpandMetaToFolder(setting.m_szBackUpFolder.c_str(), selDir, int(std::size(selDir)));
	Text folder(selDir);
	// sakura.ini の szBackUpFolder は最後に「\」が付く（原版 ShareData_IO_BackUpFolder。Mac 版の区切りは「/」なので取る）
	while (!folder.empty() && folder.back() == u'\\') folder.pop_back();
	if (!folder.empty() && folder[0] != u'/') {
		// Mac 版：相対パスは対象ファイルのフォルダーから
		folder = targetDir + folder;
	}
	if (!folder.empty()) {
		folder = ToPath(folder).lexically_normal().u16string();
	}
	if (folder.empty() || folder.back() != u'/') folder += u'/';
	return folder;
}

} // namespace

std::optional<Text> FormatBackupPath(const Text& target, const BackupTime* now)
{
	const CommonSetting_Backup& bup_setting = GetDllShareData().m_Common.m_sBackup;

	/* パスの分解 */
	const SplitPath sp = Split(target);
	Text szNewPath;
	Text szExt = sp.ext;

	if (bup_setting.m_bBackUpFolder
	  && (!bup_setting.m_bBackUpFolderRM || !IsLocalDrive(target.c_str()))) {	/* 指定フォルダーにバックアップを作成する */
		szNewPath = BackupFolder(bup_setting, sp.dir);
	} else {
		szNewPath = sp.dir;
	}

	/* 相対フォルダーを挿入 */
	if (!bup_setting.m_bBackUpPathAdvanced) {
		Text name;
		/* バックアップファイル名のタイプ 1=(.bak) 2=*_日付.* */
		switch (bup_setting.GetBackupType()) {
		case 1:
			name = sp.fname + u".bak";
			break;
		case 5: //	1の拡張子を残す版
			name = sp.fname + sp.ext + u".bak";
			break;
		case 2:	//	日付，時刻（保存時）
			{
				const SYSTEMTIME t = Now(now);
				Text szTime;
				if (bup_setting.GetBackupOpt(BKUP_YEAR)) szTime += Decimal(t.wYear);	// wcsftime の %Y
				if (bup_setting.GetBackupOpt(BKUP_MONTH)) szTime += TwoDigits(t.wMonth);
				if (bup_setting.GetBackupOpt(BKUP_DAY)) szTime += TwoDigits(t.wDay);
				if (bup_setting.GetBackupOpt(BKUP_HOUR)) szTime += TwoDigits(t.wHour);
				if (bup_setting.GetBackupOpt(BKUP_MIN)) szTime += TwoDigits(t.wMinute);
				if (bup_setting.GetBackupOpt(BKUP_SEC)) szTime += TwoDigits(t.wSecond);
				name = sp.fname + u"_" + szTime + sp.ext;
			}
			break;
		case 4:	//	日付，時刻（前回のファイル更新時）
			{
				const SYSTEMTIME t = LastWriteLocalTime(target);
				Text szTime;
				if (bup_setting.GetBackupOpt(BKUP_YEAR)) szTime += Decimal(t.wYear);	// 原版 "%d"
				if (bup_setting.GetBackupOpt(BKUP_MONTH)) szTime += TwoDigits(t.wMonth);
				if (bup_setting.GetBackupOpt(BKUP_DAY)) szTime += TwoDigits(t.wDay);
				if (bup_setting.GetBackupOpt(BKUP_HOUR)) szTime += TwoDigits(t.wHour);
				if (bup_setting.GetBackupOpt(BKUP_MIN)) szTime += TwoDigits(t.wMinute);
				if (bup_setting.GetBackupOpt(BKUP_SEC)) szTime += TwoDigits(t.wSecond);
				name = sp.fname + u"_" + szTime + sp.ext;
			}
			break;
		case 3: //	?xx : xx = 00~99, ?は任意の文字
		case 6: //	3の拡張子を残す版
			{
				if (bup_setting.GetBackupType() == 3) {
					szExt.clear();
				}
				const WCHAR szBackupExt[] = { u'.', bup_setting.GetBackupExtChar(), u'0', u'0', 0 };
				szExt += szBackupExt;
			}
			name = sp.fname + szExt;
			break;
		default:
			break;
		}
		szNewPath += name;
		if (szNewPath.size() >= kMaxPath) return std::nullopt;
	} else { // 詳細設定使用する
		SYSTEMTIME time = {};
		switch (bup_setting.GetBackupTypeAdv()) {
		case 4:	//	ファイルの日付，時刻
			time = LastWriteLocalTime(target);
			break;
		case 2:	//	現在の日付，時刻
		default:
			time = Now(now);
			break;
		}

		const sakura::wstring formatString = GetDateTimeFormat(bup_setting.m_szBackUpPathAdvanced.c_str(), time);

		// $0-$9に対応するフォルダー名を切り出し（$0 はファイル名、$1 から上のフォルダー名）
		Text folders[10];
		bool hasFolder[10] = {};
		folders[0] = sp.fname;
		hasFolder[0] = true;
		{
			Text keybuff = sp.dir;
			if (keybuff.size() > 1 && keybuff.back() == u'/') keybuff.pop_back();	// CutLastYenFromDirectoryPath
			for (int idx = 1; idx < 10; ++idx) {
				const auto cp = keybuff.rfind(u'/');
				if (cp == Text::npos) break;
				folders[idx] = keybuff.substr(cp + 1);
				hasFolder[idx] = true;
				keybuff.erase(cp);
			}
		}
		{
			// $0-$9を置換
			const Text q(formatString.c_str());
			size_t q2 = 0;
			for (size_t q1 = 0; q1 < q.size(); ++q1) {
				if (q[q1] == u'$') {
					++q1;
					if (q1 >= q.size()) break;
					if (u'0' <= q[q1] && q[q1] <= u'9') {
						szNewPath += q.substr(q2, q1 - 1 - q2);
						const int n = q[q1] - u'0';
						if (hasFolder[n]) szNewPath += folders[n];
						q2 = q1 + 1;
					}
				}
			}
			szNewPath += q.substr(std::min(q2, q.size()));
			if (szNewPath.size() >= kMaxPath) return std::nullopt;
		}
		{
			// * → 拡張子（'.' なし）、? → '_'
			const Text ep = szExt.empty() ? Text() : szExt.substr(1);
			for (size_t cp; (cp = szNewPath.find(u'*')) != Text::npos;) {
				szNewPath = szNewPath.substr(0, cp) + ep + szNewPath.substr(cp + 1);
				if (szNewPath.size() >= kMaxPath) return std::nullopt;
			}
			for (auto& c : szNewPath) {
				if (c == u'?') c = u'_';
			}
		}
	}
	return szNewPath;
}

BackupResult MakeBackup(const Text& target, BackupHandler& handler, const BackupTime* now)
{
	/* バックアップソースの存在チェック */
	if (::access(ToPath(target).c_str(), W_OK) != 0) {
		return BackupResult::NotCreated;
	}

	const CommonSetting_Backup& bup_setting = GetDllShareData().m_Common.m_sBackup;

	const auto formatted = FormatBackupPath(target, now);
	if (!formatted) {
		//	原版 TopConfirmMessage（題はアプリ名。空の題は界面層がアプリ名にする）
		const auto r = handler.Confirm(Text(), ToMessage(Text(LS(STR_BACKUP_ERR_PATH_CRETE))), false);
		if (r == BackupAnswer::Yes) {
			return BackupResult::NotCreated;	//	保存継続
		}
		return BackupResult::Interrupt;	// 保存中断
	}
	Text szPath = *formatted;

	bool dustflag = false;
	if (bup_setting.m_bBackUpDustBox) {
		dustflag = !IsLocalDrive(szPath.c_str());
	}

	if (bup_setting.m_bBackUpDialog) {	/* バックアップの作成前に確認 */
		BackupAnswer nRet;
		if (bup_setting.m_bBackUpDustBox && !dustflag) {	//共通設定：バックアップファイルをごみ箱に放り込む
			nRet = handler.Confirm(ToMessage(Text(LS(STR_BACKUP_CONFORM_TITLE1))),
								   FormatMessage(LS(STR_BACKUP_CONFORM_MSG1), target, szPath), false);
		} else {
			nRet = handler.Confirm(ToMessage(Text(LS(STR_BACKUP_CONFORM_TITLE2))),
								   FormatMessage(LS(STR_BACKUP_CONFORM_MSG2), target, szPath), true);
		}
		if (nRet == BackupAnswer::No) {
			return BackupResult::NotCreated;	//	保存継続
		} else if (nRet == BackupAnswer::Cancel) {
			return BackupResult::Interrupt;	// 保存中断
		}
	}

	//	ファイル名の最後の2桁を連番にする（原版：既存のバックアップファイルを1つずつずらす）
	if (bup_setting.GetBackupType() == 3 ||
		bup_setting.GetBackupType() == 6) {
		if (szPath.size() < 2) return BackupResult::NotCreated;
		const size_t base = szPath.size() - 2;	//	2: 拡張子の最後の2桁の意味
		auto withNumber = [&](int n) { return szPath.substr(0, base) + TwoDigits(n); };

		//	既存のバックアップファイルの最大の番号
		int i;
		for (i = 0; i <= 99; i++) {	//	最大値に関わらず，99（2桁の最大値）まで探す
			if (!Exists(withNumber(i))) {
				break;
			}
		}
		--i;

		//	世代数を超えるものを削除
		int boundary = bup_setting.GetBackupCount();
		boundary = boundary > 0 ? boundary - 1 : 0;	//	最小値は0
		for (; i >= boundary; --i) {
			const Text path = withNumber(i);
			std::error_code ec;
			if (!fs::remove(ToPath(path), ec)) {
				handler.ShowError(ToMessage(Text(LS(STR_BACKUP_ERR_DELETE))), path);
				return BackupResult::NotCreated;
			}
		}

		//	番号を1つずつずらす
		for (; i >= 0; --i) {
			const Text from = withNumber(i);
			const Text to = withNumber(i + 1);
			std::error_code ec;
			fs::rename(ToPath(from), ToPath(to), ec);
			if (ec) {
				handler.ShowError(ToMessage(Text(LS(STR_BACKUP_ERR_MOVE))), from);
				return BackupResult::NotCreated;
			}
		}
		szPath = withNumber(0);
	}

	/* バックアップの作成 */
	//	フォルダーがなければ作る（原版 CreateDirectory：一段だけ）
	{
		const SplitPath sp = Split(szPath);
		Text dir = sp.dir;
		if (dir.size() > 1 && dir.back() == u'/') dir.pop_back();
		std::error_code ec;
		if (!dir.empty() && !fs::exists(ToPath(dir), ec)) {
			fs::create_directory(ToPath(dir), ec);
		}
	}

	std::error_code ec;
	fs::copy_file(ToPath(target), ToPath(szPath), fs::copy_options::overwrite_existing, ec);
	if (!ec) {
		//	CopyFile と同じく更新日時を残す
		std::error_code ec2;
		const auto mtime = fs::last_write_time(ToPath(target), ec2);
		if (!ec2) fs::last_write_time(ToPath(szPath), mtime, ec2);
		/* 正常終了 */
		if (bup_setting.m_bBackUpDustBox && !dustflag) {	//	ネットワーク・リムーバブルドライブでない
			handler.MoveToTrash(szPath);
		}
	} else {
		/* エラー終了 */
		return BackupResult::FileError;
	}
	return BackupResult::Created;
}

bool IsBackupNeeded(const Text& target)
{
	return Exists(target) && GetDllShareData().m_Common.m_sBackup.m_bBackUp;
}

bool BackupBeforeSave(const Text& target, BackupHandler& handler, const BackupTime* now)
{
	if (!Exists(target)) return true;

	if (GetDllShareData().m_Common.m_sBackup.m_bBackUp) {
		//	原版はバックアップの作成の前後でファイルのロックを外す・戻す（Mac 版はファイルをロックしない）
		const BackupResult nBackupResult = MakeBackup(target, handler, now);
		switch (nBackupResult) {
		case BackupResult::Interrupt:	//	中断指示
			return false;
		case BackupResult::FileError: //	ファイルエラー
			if (BackupAnswer::Yes != handler.Confirm(ToMessage(Text(LS(STR_BACKUP_ERR_TITLE))),
													  ToMessage(Text(LS(STR_BACKUP_ERR_MSG))), false)) {
				return false;
			}
			break;
		default:
			break;
		}
	}
	return true;
}

} // namespace sakura::core
