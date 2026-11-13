/*! @file
	@brief 只链接核心库（不链接测试代码）时能否正常工作（计划第 24 步）

	App 和桥接层只链接 sakura_core_api 和它依赖的静态库。
	单元测试程序里有测试专用的代码，可能把核心库缺少的函数补上，发现不了链接错误；
	这个小程序不用 GoogleTest，与 App 一样只链接核心库，确认能启动、编辑、查找。
*/
/*
	Copyright (C) 2026, Sakura Editor Organization

	SPDX-License-Identifier: Zlib
*/
#include "sakura_core/SakuraCore.h"

#include <cstdio>
#include <cstdlib>
#include <filesystem>

int main()
{
	using namespace sakura::core;
	// 不碰运行者自己的 sakura.ini
	const auto home = std::filesystem::temp_directory_path() / "sakura-core-api-link-check";
	std::filesystem::create_directories(home);
	::setenv("HOME", home.c_str(), 1);

	if (!Startup()) {
		std::puts("Startup failed");
		return 1;
	}
	int rc = 0;
	{
		auto doc = Document::Create();
		if (!doc || doc->Insert(Position{ 0, 0 }, u"int main() {}\n") != Result::Ok) rc = 2;
		const auto found = doc ? doc->Find(u"main", Position{}) : std::nullopt;
		if (!found || found->from.column != 4) rc = 3;
	}
	Shutdown(false);
	std::filesystem::remove_all(home);
	std::puts(rc == 0 ? "OK" : "NG");
	return rc;
}
