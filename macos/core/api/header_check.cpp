/*! @file
	@brief 确认核心库的接口头文件不依赖平台头文件（计划第 22 步的完成标志）

	这个文件在只有 macos/core/include 的包含路径下编译（CMake 的 sakura_core_api_header_check 目标），
	找不到 macos/platform、sakura_core 和 Windows SDK 替身的头文件。
	接口头文件如果引用了它们，或者用到了 Win32 的类型和宏，这里就会编译失败。
*/
/*
	Copyright (C) 2026, Sakura Editor Organization

	SPDX-License-Identifier: Zlib
*/
#include "sakura_core/SakuraCore.h"

#if defined(WCHAR) || defined(TRUE) || defined(FALSE) || defined(LTEXT) || defined(_T) || defined(MAX_PATH)
#error "SakuraCore.h must not pull in Win32 or platform-layer macros"
#endif

#include <type_traits>

namespace {

// 接口里的类型都是标准 C++ 的类型
static_assert(std::is_same_v<sakura::core::Text, std::u16string>);
static_assert(std::is_same_v<sakura::core::Encoding, std::int32_t>);
static_assert(std::is_same_v<sakura::core::FunctionCode, std::int32_t>);
static_assert(sizeof(sakura::core::Position) == 2 * sizeof(std::int32_t));

// 只用接口头文件就能写出界面层要做的事（打开、编辑、查找、保存、执行命令）
[[maybe_unused]] bool UseInterface()
{
	using namespace sakura::core;
	if (!Startup()) return false;
	auto doc = Document::Create();
	bool ok = doc != nullptr;
	if (doc) {
		ok = ok && doc->Open(u"/tmp/a.txt", OpenOptions{ encoding::AutoDetect }) == Result::Ok;
		Position end;
		ok = ok && doc->Insert(Position{ 0, 0 }, u"abc\r\n", &end) == Result::Ok;
		const std::optional<Range> found = doc->Find(u"b", Position{}, SearchDirection::Forward, SearchOptions{ false, true, false });
		ok = ok && found.has_value();
		ok = ok && doc->ExecuteCommand(command::Undo) == Result::Ok;
		ok = ok && doc->SaveAs(u"/tmp/b.txt", SaveOptions{ encoding::UTF8, false, Eol::LF }) == Result::Ok;
		ok = ok && !CommandName(command::Redo).empty() && !EncodingName(encoding::SJIS).empty();
	}
	Shutdown();
	return ok;
}

} // namespace
