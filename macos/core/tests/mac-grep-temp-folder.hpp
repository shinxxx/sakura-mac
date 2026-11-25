/*! @file
	@brief Grep のテスト用の一時フォルダー（计划第 43 步。原版 src/test/cpp/tests1/grep/GrepTestSuite.hpp 的 TempFolder 的 Mac 版）

	原版的 GrepTestSuite.hpp 还用编辑窗口和 Windows 的文件属性，Mac 版只取出一时フォルダー。
	test-mac-grep.cpp、原版的 test-grep-exclude-regex.cpp（Mac 版）用。
*/
/*
	Copyright (C) 2026, Sakura Editor Organization

	SPDX-License-Identifier: Zlib
*/
#pragma once

#include <filesystem>
#include <format>
#include <fstream>
#include <string>
#include <string_view>

#include <sys/stat.h>
#include <unistd.h>

namespace grep_test {

namespace fs = std::filesystem;

/*!
	@brief テスト用の一時フォルダー（原版 GrepTestSuite.hpp の TempFolder）

	$TMPDIR/sakura_test_grep/<テストスイート名>.<テスト名> に作り、デストラクターで消す。
	読み取り専用・変更不可のファイルも消せるよう、削除の前に戻す。
*/
class TempFolder {
public:
	TempFolder()
	{
		const auto info = ::testing::UnitTest::GetInstance()->current_test_info();
		m_path = fs::temp_directory_path() / "sakura_test_grep" / std::format("{}.{}", info->test_suite_name(), info->name());
		Remove();
		fs::create_directories(m_path);
	}
	~TempFolder() { Remove(); }
	TempFolder(const TempFolder&) = delete;
	TempFolder& operator=(const TempFolder&) = delete;

	//! ファイルをバイト列のまま書き出す（途中のフォルダーも作る）。属性は読み取り専用・隠しだけ（Mac にシステム属性は無い）
	void AddFile(const std::filesystem::path& relPath, std::string_view bytes, DWORD attributes = FILE_ATTRIBUTE_NORMAL) const
	{
		const fs::path path = m_path.fs() / relPath;
		fs::create_directories(path.parent_path());
		if (fs::exists(path)) {
			::chmod(path.c_str(), 0644);
		}
		{
			std::ofstream ofs(path, std::ios::binary | std::ios::trunc);
			ofs.write(bytes.data(), std::streamsize(bytes.size()));
		}
		::SetFileAttributesW(sakura::path_to_wstring(path).c_str(), attributes);
	}

	void AddFolder(const std::filesystem::path& relPath) const { fs::create_directories(m_path.fs() / relPath); }

	std::string ReadFile(const std::filesystem::path& relPath) const
	{
		std::ifstream ifs(m_path.fs() / relPath, std::ios::binary);
		return std::string(std::istreambuf_iterator<char>(ifs), std::istreambuf_iterator<char>());
	}

	bool Exists(const std::filesystem::path& relPath) const { return fs::exists(m_path.fs() / relPath); }

	const TestPath& Path() const noexcept { return m_path; }
	sakura::wstring PathText() const { return sakura::path_to_wstring(m_path); }
	sakura::wstring PathOf(const std::filesystem::path& relPath) const { return sakura::path_to_wstring(m_path.fs() / relPath); }

private:
	void Remove() const
	{
		std::error_code ec;
		if (fs::exists(m_path, ec)) {
			for (const auto& entry : fs::recursive_directory_iterator(m_path, ec)) {
				::chflags(entry.path().c_str(), 0);
				::chmod(entry.path().c_str(), entry.is_directory() ? 0755 : 0644);
			}
		}
		fs::remove_all(m_path, ec);
	}

	TestPath m_path;
};

} // namespace grep_test
