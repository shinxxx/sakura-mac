/*! @file
	@brief 外部模块（计划第 19 步）：正则（bregonig）、C/Migemo、uchardet 的 Mac 版测试

	原版 src/test/cpp/tests1/test-extmodules.cpp 依赖共通设置（DLLSHAREDATA）、exe 所在目录和
	资源里的 zip，Mac 版还不能直接编译。这里把其中不依赖这些的部分改写过来：
	  - CBregexpTest.test001、MatchConcurrentlyWithSeparateObjects（几乎原样）
	  - LoadTest.FailedToLoadLibrary / FailedToGetProcAddress（Mac 没有 MSHTML.DLL，换成名字不对的模块）
	  - CMigemoTest.test002 的查询结果（这里直接调用 migemo.dll 的函数；经由 CMigemo 类的测试在 test-mac-env.cpp，第 21 步）
	另外加了 Mac 版“静态链接的 DLL”本身（macos/platform/src/static_modules.cpp）和几个正则用例的测试。
*/
/*
	Copyright (C) 2026, Sakura Editor Organization

	SPDX-License-Identifier: Zlib
*/
#include "pch.h"
#include "extmodule/CBregexp.h"
#include "extmodule/CBregexpDll2.h"
#include "extmodule/CUchardet.h"

#include "migemo.h"

#include <array>
#include <filesystem>
#include <string>
#include <thread>
#include <vector>

#ifndef SAKURA_MIGEMO_DICT_DIR
#error "SAKURA_MIGEMO_DICT_DIR is not defined (macos/core/CMakeLists.txt)"
#endif

namespace {

using ::testing::Eq;
using ::testing::IsFalse;
using ::testing::IsTrue;

sakura::wstring W(const WCHAR* s) { return s ? sakura::wstring(s) : sakura::wstring(); }

// ---------------------------------------------------------------------------
// 静态链接的 DLL（LoadLibraryW / GetProcAddress / FreeLibrary）
// ---------------------------------------------------------------------------

TEST(StaticModules, LoadsRegisteredNamesIgnoringCaseAndDirectory)
{
	const HMODULE h1 = ::LoadLibraryW(LTEXT("bregonig.dll"));
	ASSERT_NE(nullptr, h1);
	EXPECT_EQ(h1, ::LoadLibraryW(LTEXT("BREGONIG.DLL")));
	EXPECT_EQ(h1, ::LoadLibraryW(LTEXT("/Applications/Sakura Editor.app/Contents/bregonig.dll")));
	EXPECT_EQ(h1, ::LoadLibraryW(LTEXT("C:\\Program Files\\sakura\\bregonig.dll")));
	EXPECT_NE(nullptr, ::GetProcAddress(h1, "BMatchW"));
	EXPECT_EQ(nullptr, ::GetProcAddress(h1, "BMatch"));        // 多字节版不导出（原版 Sakura 只用 W 版）
	EXPECT_TRUE(::FreeLibrary(h1));

	const HMODULE h2 = ::LoadLibraryW(LTEXT("migemo.dll"));
	ASSERT_NE(nullptr, h2);
	EXPECT_NE(h1, h2);
	EXPECT_NE(nullptr, ::GetProcAddress(h2, "migemo_open"));
	EXPECT_EQ(nullptr, ::GetProcAddress(h2, "BMatchW"));
	EXPECT_EQ(DWORD(ERROR_PROC_NOT_FOUND), ::GetLastError());
}

TEST(StaticModules, UnknownNamesFailLikeAMissingDll)
{
	EXPECT_EQ(nullptr, ::LoadLibraryW(LTEXT("uchardet.dll")));   // Windows 官方版也不附带
	EXPECT_EQ(DWORD(ERROR_MOD_NOT_FOUND), ::GetLastError());
	EXPECT_EQ(nullptr, ::LoadLibraryW(LTEXT("bregexp.dll")));
	EXPECT_EQ(nullptr, ::LoadLibraryW(LTEXT("")));
	EXPECT_EQ(nullptr, ::LoadLibraryW(nullptr));
	EXPECT_FALSE(::FreeLibrary(nullptr));
}

// ---------------------------------------------------------------------------
// CDllImp 的加载失败（相当于原版 LoadTest）
// ---------------------------------------------------------------------------

//! 相当于原版 TExtModule.hpp：替换 DLL 名，在构造函数里加载
template<class T>
class TExtModule : public T {
public:
	explicit TExtModule(const WCHAR* name) : m_name(name) { this->InitDll(nullptr); }
protected:
	LPCWSTR GetDllNameImp(int) override { return m_name; }
private:
	const WCHAR* m_name;
};

TEST(LoadTest, FailedToLoadLibrary)
{
	TExtModule<CBregexpDll2> bregexp(LTEXT(">\\(^o^)\\<"));
	EXPECT_FALSE(bregexp.IsAvailable());
	TExtModule<CUchardet> uchardet(LTEXT(">\\(^o^)\\<"));
	EXPECT_FALSE(uchardet.IsAvailable());
}

TEST(LoadTest, FailedToGetProcAddress)
{
	// 原版用 MSHTML.DLL（Sakura 不用的 Windows DLL）。Mac 版用函数对不上的另一个模块
	TExtModule<CBregexpDll2> bregexp(LTEXT("migemo.dll"));
	EXPECT_FALSE(bregexp.IsAvailable());
	// 指定的名字失败时，原版 InitDll 接着尝试类自己的 DLL 名（bregonig.dll）
	CBregexpDll2 other;
	EXPECT_EQ(DLL_SUCCESS, other.InitDll(LTEXT("migemo.dll")));
	EXPECT_EQ(LTEXT("bregonig.dll"), W(other.GetLoadedDllName()));
}

// ---------------------------------------------------------------------------
// CBregexp（原版 CBregexpTest）
// ---------------------------------------------------------------------------

TEST(CBregexpTest, test001)
{
	CBregexp regexp;
	CBregexp* pcBregexp = &regexp;

	// 初始状态不可用
	EXPECT_THAT(pcBregexp->IsAvailable(), IsFalse());
	EXPECT_EQ(LTEXT(""), W(pcBregexp->GetVersionW()));
	EXPECT_THAT(pcBregexp->Compile(LTEXT("[0-9]+"), LTEXT("$1d")), IsFalse());

	// 不指定名字加载（原版先把共通设置的 m_szRegexpLib 设为空字符串）
	EXPECT_EQ(DLL_SUCCESS, pcBregexp->InitDll());
	EXPECT_THAT(pcBregexp->IsAvailable(), IsTrue());
	EXPECT_EQ(LTEXT("bregonig.dll"), W(pcBregexp->GetLoadedDllName()));
	EXPECT_NE(LTEXT(""), W(pcBregexp->GetVersionW()));
	EXPECT_EQ(LTEXT(""), W(pcBregexp->GetLastMessage()));

	EXPECT_THAT(pcBregexp->Compile(LTEXT(".+")), IsTrue());
	EXPECT_THAT(pcBregexp->Compile(LTEXT("^$")), IsTrue());
	EXPECT_THAT(pcBregexp->Compile(LTEXT("[0-9]+"), int(-1)), IsTrue());

	EXPECT_THAT(pcBregexp->Compile(LTEXT("[0-9")), IsFalse());
	EXPECT_NE(LTEXT(""), W(pcBregexp->GetLastMessage()));

	EXPECT_THAT(pcBregexp->Compile(LTEXT("[0-9]+")), IsTrue());
	EXPECT_EQ(LTEXT(""), W(pcBregexp->GetLastMessage()));

	constexpr auto& target = LTEXT("test123あいう");
	EXPECT_THAT(pcBregexp->Match(target, std::size(target) - 1, 0), IsTrue());
	EXPECT_EQ(LTEXT(""), W(pcBregexp->GetLastMessage()));
	EXPECT_EQ(CLogicInt(4), pcBregexp->GetIndex());
	EXPECT_EQ(CLogicInt(7), pcBregexp->GetLastIndex());
	EXPECT_EQ(CLogicInt(3), pcBregexp->GetMatchLen());
	EXPECT_THAT(pcBregexp->Match(LTEXT("a"), 1, 1), IsFalse());

	EXPECT_THAT(pcBregexp->Compile(LTEXT("([0-9]+)"), LTEXT("{$1d}")), IsTrue());
	EXPECT_THAT(pcBregexp->Replace(target, std::size(target) - 1, 0), IsTrue());
	EXPECT_EQ(LTEXT(""), W(pcBregexp->GetLastMessage()));
	constexpr auto& expected = LTEXT("test{123d}あいう");
	EXPECT_EQ(expected, sakura::wstring(pcBregexp->GetString(), pcBregexp->GetStringLen()));
	EXPECT_EQ(CLogicInt(std::size(expected) - 1), pcBregexp->GetStringLen());
	EXPECT_THAT(pcBregexp->Replace(LTEXT("a"), 1, 1), IsFalse());
}

//! 原版：不同的 CBregexp 对象可以在不同线程同时 Match()（Grep 并行检索）
TEST(CBregexpTest, MatchConcurrentlyWithSeparateObjects)
{
	constexpr size_t threadCount = 4;
	constexpr int loopCount = 2000;
	std::array<CBregexp, threadCount> regexps;
	for (auto& regexp : regexps) {
		ASSERT_EQ(DLL_SUCCESS, regexp.InitDll(LTEXT("bregonig.dll")));
		ASSERT_TRUE(regexp.Compile(LTEXT("H.T"), CBregexp::optCaseSensitive));
	}
	std::array<int, threadCount> hitCounts{};
	{
		std::vector<std::thread> threads;
		for (size_t i = 0; i < threadCount; ++i) {
			threads.emplace_back([&regexp = regexps[i], &hitCount = hitCounts[i]] {
				constexpr sakura::wstring_view line = LTEXT("xx HIT yy hat");
				for (int n = 0; n < loopCount; ++n) {
					if (regexp.Match(line.data(), int(line.size())) && regexp.GetIndex() == CLogicInt(3)) {
						++hitCount;
					}
				}
			});
		}
		for (auto& t : threads) t.join();
	}
	EXPECT_THAT(hitCounts, ::testing::Each(Eq(loopCount)));
}

//! 有代表性的查找和替换（与 Windows 版是同一份 bregonig 4.20 和 Onigmo 源码）
struct RegexCase {
	const WCHAR* pattern;
	const WCHAR* replacement;   //!< nullptr 表示只查找
	int          option;
	const WCHAR* target;
	int          index;         //!< 匹配位置，-1 表示不匹配
	int          length;
	const WCHAR* replaced;      //!< 替换结果
};

TEST(CBregexpTest, RepresentativePatterns)
{
	constexpr int cs = CBregexp::optCaseSensitive;
	constexpr int ci = CBregexp::optNothing;
	constexpr int g = CBregexp::optGlobal;
	const RegexCase cases[] = {
		{ LTEXT("abc"),                 nullptr, ci, LTEXT("xxABCxx"),        2, 3, nullptr },
		{ LTEXT("abc"),                 nullptr, cs, LTEXT("xxABCxx"),       -1, 0, nullptr },
		{ LTEXT("ｶﾀｶﾅ|カタカナ"),       nullptr, cs, LTEXT("半角ｶﾀｶﾅ"),       2, 4, nullptr },
		{ LTEXT("[ぁ-ん]+"),            nullptr, cs, LTEXT("漢字ひらがな"),   2, 4, nullptr },
		{ LTEXT("\\p{Han}+"),           nullptr, cs, LTEXT("abc漢字def"),     3, 2, nullptr },
		{ LTEXT("(?<=\\$)\\d+"),        nullptr, cs, LTEXT("cost $120"),      6, 3, nullptr },
		{ LTEXT("(?<w>\\w)\\k<w>"),     nullptr, cs, LTEXT("abccd"),          2, 2, nullptr },
		{ LTEXT("^\\s*$"),              nullptr, cs, LTEXT("   "),            0, 3, nullptr },
		{ LTEXT("\\x{1F600}"),          nullptr, cs, LTEXT("a😀b"),           1, 2, nullptr },
		{ LTEXT("Ａ"),                  nullptr, ci, LTEXT("ａ"),             0, 1, nullptr },
		{ LTEXT("(\\d+)-(\\d+)"), LTEXT("$2-$1"), cs, LTEXT("10-20"),         0, 5, LTEXT("20-10") },
		{ LTEXT("a"),             LTEXT("b"),   cs | g, LTEXT("banana"),      1, 1, LTEXT("bbnbnb") },
		{ LTEXT("(\\w+)"),        LTEXT("[\\U$1]"), cs, LTEXT("sakura"),      0, 6, LTEXT("[SAKURA]") },
		{ LTEXT("。"),            LTEXT("\\r\\n"), cs, LTEXT("文。"),          1, 1, LTEXT("文\r\n") },
	};
	for (const auto& c : cases) {
		CBregexp regexp;
		ASSERT_EQ(DLL_SUCCESS, regexp.InitDll());
		const auto t = sakura::wstring(c.target);
		ASSERT_TRUE(regexp.Compile(c.pattern, c.replacement, c.option)) << sakura::u16::to_utf8(c.pattern);
		if (!c.replacement) {
			const bool matched = regexp.Match(t.c_str(), int(t.size()), 0);
			EXPECT_EQ(c.index >= 0, matched) << sakura::u16::to_utf8(c.pattern);
			if (matched) {
				EXPECT_EQ(CLogicInt(c.index), regexp.GetIndex()) << sakura::u16::to_utf8(c.pattern);
				EXPECT_EQ(CLogicInt(c.length), regexp.GetMatchLen()) << sakura::u16::to_utf8(c.pattern);
			}
		} else {
			ASSERT_TRUE(regexp.Replace(t.c_str(), int(t.size()), 0)) << sakura::u16::to_utf8(c.pattern);
			EXPECT_EQ(W(c.replaced), sakura::wstring(regexp.GetString(), regexp.GetStringLen())) << sakura::u16::to_utf8(c.pattern);
		}
	}
}

// ---------------------------------------------------------------------------
// C/Migemo（原版 CMigemoTest.test002 的查询结果）
// ---------------------------------------------------------------------------

//! 直接取得与 CMigemo 相同的函数表（CMigemo 类本身的测试在 test-mac-env.cpp）
class MigemoFunctions : public CDllImp {
public:
	decltype(&::migemo_open) open = nullptr;
	decltype(&::migemo_close) close = nullptr;
	decltype(&::migemo_query) query = nullptr;
	decltype(&::migemo_release) release = nullptr;
	decltype(&::migemo_load) load = nullptr;
	decltype(&::migemo_is_enable) is_enable = nullptr;
protected:
	LPCWSTR GetDllNameImp(int) override { return LTEXT("migemo.dll"); }
	bool InitDllImp() override {
		const ImportTable table[] = {
			{ &open, "migemo_open" }, { &close, "migemo_close" }, { &query, "migemo_query" },
			{ &release, "migemo_release" }, { &load, "migemo_load" }, { &is_enable, "migemo_is_enable" },
			{ nullptr, nullptr }
		};
		return RegisterEntries(table);
	}
};

TEST(CMigemoTest, QueryWithUtf8Dictionary)
{
	MigemoFunctions f;
	ASSERT_EQ(DLL_SUCCESS, f.InitDll());
	migemo* m = f.open(nullptr);
	ASSERT_NE(nullptr, m);
	EXPECT_EQ(0, f.is_enable(m));   // 没有词典时不可用（原版 test001）

	// 按原版 CMigemo::migemo_load_all 的顺序读词典
	const std::filesystem::path dir = std::filesystem::path(SAKURA_MIGEMO_DICT_DIR) / "utf-8";
	f.load(m, MIGEMO_DICTID_MIGEMO, (dir / "migemo-dict").string().c_str());
	f.load(m, MIGEMO_DICTID_HAN2ZEN, (dir / "han2zen.dat").string().c_str());
	f.load(m, MIGEMO_DICTID_HIRA2KATA, (dir / "hira2kata.dat").string().c_str());
	f.load(m, MIGEMO_DICTID_ROMA2HIRA, (dir / "roma2hira.dat").string().c_str());
	f.load(m, MIGEMO_DICTID_ZEN2HAN, (dir / "zen2han.dat").string().c_str());
	ASSERT_NE(0, f.is_enable(m));

	unsigned char* found = f.query(m, reinterpret_cast<const unsigned char*>(u8"さくらえでぃt"));
	ASSERT_NE(nullptr, found);
	// 原版 CMigemoTest.test002 的期望值
	EXPECT_EQ(std::string(reinterpret_cast<const char*>(u8"(ｻｸﾗｴﾃﾞｨ[ﾄﾃﾂﾁﾀ]|サクラエディ[トテツチタ]|さくらえでぃ[とてつちたｔt])")),
	          std::string(reinterpret_cast<const char*>(found)));
	f.release(m, found);

	found = f.query(m, reinterpret_cast<const unsigned char*>("sakura"));
	ASSERT_NE(nullptr, found);
	EXPECT_NE(std::string::npos, std::string(reinterpret_cast<const char*>(found)).find(reinterpret_cast<const char*>(u8"桜")));
	f.release(m, found);
	f.close(m);
}

// ---------------------------------------------------------------------------
// uchardet：与 Windows 官方版一样不附带
// ---------------------------------------------------------------------------

TEST(CUchardetTest, NotBundled)
{
	CUchardet uchardet;
	EXPECT_EQ(DLL_LOADFAILURE, uchardet.InitDll());
	EXPECT_FALSE(uchardet.IsAvailable());
}

} // namespace
