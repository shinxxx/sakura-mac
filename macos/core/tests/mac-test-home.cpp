/*! @file
	@brief 测试用的 HOME（计划第 21 步）

	Mac 版的设置文件在 $HOME/Library/Application Support/sakura/sakura.ini（util/file.cpp 的 GetIniFileName）。
	原版的测试会写设置文件和 Migemo 词典，为了不碰到运行测试的人自己的设置，
	测试程序一启动就把 HOME 换成临时文件夹里的专用文件夹（每个测试进程一个），结束时删除。
*/
/*
	Copyright (C) 2026, Sakura Editor Organization

	SPDX-License-Identifier: Zlib
*/
#include "pch.h"

#include <cstdlib>
#include <filesystem>
#include <string>

#include <unistd.h>

namespace {

class MacTestHome {
public:
	MacTestHome()
	{
		m_dir = std::filesystem::temp_directory_path() / ("sakura-test-home-" + std::to_string(::getpid()));
		std::error_code ec;
		std::filesystem::remove_all(m_dir, ec);
		std::filesystem::create_directories(m_dir, ec);
		::setenv("HOME", m_dir.c_str(), 1);
	}
	~MacTestHome()
	{
		std::error_code ec;
		std::filesystem::remove_all(m_dir, ec);
	}

private:
	std::filesystem::path m_dir;
};

//! 静态对象：在 main（GoogleTest 开始之前）建立，进程结束时删除
const MacTestHome g_macTestHome;

} // namespace
