/*! @file
	@brief 文档模型和语法类型（计划第 20 步）

	原版测试没有覆盖、第 20 步编进核心库的部分：
	- 文件 API 的替代实现（macos/platform/src/file_api.cpp）和 io/CFile
	- io/CFileLoad 的特殊情况（空文件、日文路径、分段读入）
	- 撤销缓冲 cmd/COpeBuf、差异标记 docplus/CDiffManager、修改标记 docplus/CModifyManager
	- 17 种内置类型的默认设置 types/CType_*.cpp
	- BSTR、VARIANT（macos/platform/src/ole_types.cpp）
	读入各种编码的文件见 test-mac-roundtrip.cpp，查找和替换见原版的 test-csearchagent.cpp。
*/
/*
	Copyright (C) 2026, Sakura Editor Organization

	SPDX-License-Identifier: Zlib
*/
#include "pch.h"
#include "cmd/COpe.h"
#include "cmd/COpeBlk.h"
#include "cmd/COpeBuf.h"
#include "doc/logic/CDocLine.h"
#include "doc/logic/CDocLineMgr.h"
#include "docplus/CDiffManager.h"
#include "docplus/CModifyManager.h"
#include "io/CFile.h"
#include "io/CFileLoad.h"
#include "types/CType.h"
#include "env/ShareDataTestSuite.hpp"

#include <array>
#include <filesystem>
#include <fstream>
#include <memory>
#include <string>
#include <utility>

#include <sys/stat.h>

namespace {

namespace fs = std::filesystem;

//! 测试用的临时文件夹（名字含日文）
class MacDocTest : public ::testing::Test, public env::ShareDataTestSuite {
protected:
	fs::path m_dir;

	static void SetUpTestSuite() { SetUpShareData(); }
	static void TearDownTestSuite() { TearDownShareData(); }

	void SetUp() override {
		const auto* info = ::testing::UnitTest::GetInstance()->current_test_info();
		m_dir = fs::temp_directory_path() / (std::string("sakura-doc-") + info->name() + "-\xE6\x97\xA5\xE6\x9C\xAC\xE8\xAA\x9E");	// “日本語”
		std::error_code ec;
		fs::remove_all(m_dir, ec);
		fs::create_directories(m_dir);
	}
	void TearDown() override {
		std::error_code ec;
		fs::permissions(m_dir / "readonly.txt", fs::perms::owner_all, ec);
		fs::remove_all(m_dir, ec);
	}

	fs::path Write(const std::string& name, const std::string& bytes) const {
		const auto path = m_dir / name;
		std::ofstream(path, std::ios::binary) << bytes;
		return path;
	}
	static sakura::wstring W(const fs::path& path) { return sakura::path_to_wstring(path); }
};

// ---------------------------------------------------------------------------
// 文件 API（file_api.cpp）
// ---------------------------------------------------------------------------

TEST_F(MacDocTest, CreateFileReportsMissingFile)
{
	const auto path = W(m_dir / "missing.txt");
	HANDLE h = ::CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
	EXPECT_EQ(INVALID_HANDLE_VALUE, h);
	EXPECT_EQ(static_cast<DWORD>(ERROR_FILE_NOT_FOUND), ::GetLastError());
}

TEST_F(MacDocTest, CreateFileCannotOpenFolder)
{
	const auto path = W(m_dir);
	EXPECT_EQ(INVALID_HANDLE_VALUE, ::CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr));
	EXPECT_EQ(static_cast<DWORD>(ERROR_ACCESS_DENIED), ::GetLastError());
}

TEST_F(MacDocTest, FileSizeTimeAndMapping)
{
	const auto path = W(Write("data.bin", "Hello, Sakura!"));
	HANDLE h = ::CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_EXISTING, FILE_FLAG_SEQUENTIAL_SCAN, nullptr);
	ASSERT_NE(INVALID_HANDLE_VALUE, h);

	DWORD high = 1;
	EXPECT_EQ(14u, ::GetFileSize(h, &high));
	EXPECT_EQ(0u, high);

	// 修改时间是现在（几分钟以内）
	FILETIME ftWrite{};
	ASSERT_TRUE(::GetFileTime(h, nullptr, nullptr, &ftWrite));
	SYSTEMTIME now{};
	::GetSystemTime(&now);
	FILETIME ftNow{};
	::SystemTimeToFileTime(&now, &ftNow);
	const auto toU64 = [](const FILETIME& ft) { return (static_cast<ULONGLONG>(ft.dwHighDateTime) << 32) | ft.dwLowDateTime; };
	// SYSTEMTIME 只到毫秒，文件时间更精确，所以文件可能比“现在”晚不到 1 毫秒，比较差的绝对值
	const auto tNow = toU64(ftNow);
	const auto tWrite = toU64(ftWrite);
	EXPECT_LT(tNow > tWrite ? tNow - tWrite : tWrite - tNow, 10ULL * 60 * 10000000);

	HANDLE m = ::CreateFileMappingW(h, nullptr, PAGE_READONLY, 0, 0, nullptr);
	ASSERT_NE(nullptr, m);
	const auto* p = static_cast<const char*>(::MapViewOfFile(m, FILE_MAP_READ, 0, 0, 0));
	ASSERT_NE(nullptr, p);
	EXPECT_EQ(std::string("Hello, Sakura!"), std::string(p, 14));
	EXPECT_TRUE(::UnmapViewOfFile(p));
	EXPECT_FALSE(::UnmapViewOfFile(p));	// 第二次失败
	EXPECT_TRUE(::CloseHandle(m));
	EXPECT_TRUE(::CloseHandle(h));
}

TEST_F(MacDocTest, EmptyFileCannotBeMapped)
{
	const auto path = W(Write("empty.txt", ""));
	HANDLE h = ::CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
	ASSERT_NE(INVALID_HANDLE_VALUE, h);
	EXPECT_EQ(0u, ::GetFileSize(h, nullptr));
	EXPECT_EQ(static_cast<DWORD>(NO_ERROR), ::GetLastError());
	EXPECT_EQ(nullptr, ::CreateFileMappingW(h, nullptr, PAGE_READONLY, 0, 0, nullptr));	// 与 Windows 相同
	EXPECT_EQ(static_cast<DWORD>(ERROR_FILE_INVALID), ::GetLastError());
	::CloseHandle(h);
}

TEST_F(MacDocTest, CreateAlwaysTruncatesAndReportsExisting)
{
	const auto path = W(Write("exists.txt", "old contents"));
	HANDLE h = ::CreateFileW(path.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
	ASSERT_NE(INVALID_HANDLE_VALUE, h);
	EXPECT_EQ(static_cast<DWORD>(ERROR_ALREADY_EXISTS), ::GetLastError());
	EXPECT_EQ(0u, ::GetFileSize(h, nullptr));
	::CloseHandle(h);
	EXPECT_EQ(INVALID_HANDLE_VALUE, ::CreateFileW(path.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr));
	EXPECT_EQ(static_cast<DWORD>(ERROR_FILE_EXISTS), ::GetLastError());
}

// ---------------------------------------------------------------------------
// io/CFile
// ---------------------------------------------------------------------------

TEST_F(MacDocTest, CFileChecksExistenceAndPermissions)
{
	CFile missing(W(m_dir / "missing.txt").c_str());
	EXPECT_FALSE(missing.IsFileExist());
	EXPECT_FALSE(missing.IsFileReadable());
	EXPECT_FALSE(missing.FileLock(SHAREMODE_DENY_WRITE, false));

	CFile file(W(Write("normal.txt", "abc")).c_str());
	EXPECT_TRUE(file.IsFileExist());
	EXPECT_TRUE(file.IsFileReadable());
	EXPECT_TRUE(file.IsFileWritable());
	EXPECT_TRUE(file.HasWritablePermission());

	// 排他控制：Mac 版共享模式不起作用，但为了锁定而一直打开文件的行为相同
	EXPECT_TRUE(file.FileLock(SHAREMODE_DENY_WRITE, false));
	EXPECT_TRUE(file.IsFileLocking());
	file.FileUnlock();
	EXPECT_FALSE(file.IsFileLocking());
	EXPECT_TRUE(file.FileLock(SHAREMODE_NOT_EXCLUSIVE, false));
	EXPECT_FALSE(file.IsFileLocking());
}

TEST_F(MacDocTest, CFileReadOnlyFileIsNotWritable)
{
	if (::geteuid() == 0) GTEST_SKIP() << "root can write to read-only files";
	const auto path = Write("readonly.txt", "abc");
	fs::permissions(path, fs::perms::owner_read);
	CFile file(W(path).c_str());
	EXPECT_TRUE(file.IsFileExist());
	EXPECT_TRUE(file.IsFileReadable());
	EXPECT_FALSE(file.IsFileWritable());
	EXPECT_FALSE(file.HasWritablePermission());
}

// ---------------------------------------------------------------------------
// io/CFileLoad
// ---------------------------------------------------------------------------

TEST_F(MacDocTest, CFileLoadEmptyFile)
{
	const auto path = Write("empty.txt", "");
	CFileLoad cfl;
	bool bBom = true;
	EXPECT_EQ(CODE_UTF8, cfl.FileOpen(W(path).c_str(), true, CODE_UTF8, 0, &bBom));
	EXPECT_FALSE(bBom);
	EXPECT_EQ(0, cfl.GetFileSize());
	CNativeW line;
	CEol eol;
	// 空文件一行也不返回（CReadManager 读成没有行的文档）
	EXPECT_EQ(RESULT_FAILURE, cfl.ReadLine(&line, &eol));
	EXPECT_EQ(0, line.GetStringLength());
}

TEST_F(MacDocTest, CFileLoadMissingFileThrows)
{
	CFileLoad cfl;
	EXPECT_THROW(cfl.FileOpen(W(m_dir / "missing.txt").c_str(), true, CODE_UTF8, 0), CError_FileOpen);
}

TEST_F(MacDocTest, CFileLoadReadsLinesWithEol)
{
	// 日文路径、UTF-8（带 BOM）、三种换行符
	const auto path = Write("\xE3\x81\x95\xE3\x81\x8F\xE3\x82\x89.txt", "\xEF\xBB\xBF" "a\r\n\xE3\x81\x82\nb\rc");
	CFileLoad cfl;
	bool bBom = false;
	EXPECT_EQ(CODE_UTF8, cfl.FileOpen(W(path).c_str(), true, CODE_AUTODETECT, 0, &bBom));
	EXPECT_TRUE(bBom);
	FILETIME ft{};
	EXPECT_TRUE(cfl.GetFileTime(nullptr, nullptr, &ft));

	const std::array<std::pair<sakura::wstring, EEolType>, 4> expected{ {
		{ LTEXT("a\r\n"), EEolType::cr_and_lf },
		{ LTEXT("\x3042\n"), EEolType::line_feed },
		{ LTEXT("b\r"), EEolType::carriage_return },
		{ LTEXT("c"), EEolType::none },
	} };
	CNativeW line;
	CEol eol;
	for (const auto& [text, type] : expected) {
		ASSERT_EQ(RESULT_COMPLETE, cfl.ReadLine(&line, &eol));
		EXPECT_EQ(text, sakura::wstring(line.GetStringPtr(), line.GetStringLength()));
		EXPECT_EQ(type, eol.GetType());
	}
	EXPECT_EQ(RESULT_FAILURE, cfl.ReadLine(&line, &eol));
}

// ---------------------------------------------------------------------------
// 撤销缓冲（cmd/COpeBuf）
// ---------------------------------------------------------------------------

COpeBlk* MakeBlock()
{
	auto* blk = new COpeBlk;
	blk->AppendOpe(new CMoveCaretOpe(CLogicPoint(0, 0), CLogicPoint(1, 0)));
	return blk;
}

TEST(MacCOpeBuf, UndoRedoAndModifiedState)
{
	COpeBuf buf;
	EXPECT_FALSE(buf.IsEnableUndo());
	EXPECT_FALSE(buf.IsEnableRedo());

	COpeBlk* b1 = MakeBlock();
	COpeBlk* b2 = MakeBlock();
	buf.AppendOpeBlk(b1);
	buf.SetNoModified();	// 已保存
	buf.AppendOpeBlk(b2);
	EXPECT_EQ(2, buf.GetCurrentPointer());
	EXPECT_TRUE(buf.IsEnableUndo());
	EXPECT_FALSE(buf.IsEnableRedo());

	bool modified = false;
	EXPECT_EQ(b2, buf.DoUndo(&modified));
	EXPECT_FALSE(modified);			// 回到了保存时的状态
	EXPECT_EQ(b1, buf.DoUndo(&modified));
	EXPECT_TRUE(modified);
	EXPECT_EQ(nullptr, buf.DoUndo(&modified));
	EXPECT_TRUE(buf.IsEnableRedo());

	EXPECT_EQ(b1, buf.DoRedo(&modified));
	EXPECT_FALSE(modified);
	// 撤销后再加新操作，可重做的部分（b2）被丢弃
	buf.AppendOpeBlk(MakeBlock());
	EXPECT_FALSE(buf.IsEnableRedo());
	EXPECT_EQ(2, buf.GetCurrentPointer());
}

// ---------------------------------------------------------------------------
// 差异标记、修改标记（docplus）
// ---------------------------------------------------------------------------

void SetLines(CDocLineMgr& mgr, std::initializer_list<const WCHAR*> lines)
{
	for (const WCHAR* s : lines) {
		mgr.AddNewLine()->SetDocLineString(s, int(sakura::u16::strlen(s)), false);
	}
}

TEST(MacCDiffLineMgr, MarkSearchAndReset)
{
	CDocLineMgr mgr;
	SetLines(mgr, { LTEXT("0\n"), LTEXT("1\n"), LTEXT("2\n"), LTEXT("3\n"), LTEXT("4") });
	CDiffLineMgr diff(&mgr);
	diff.SetDiffMarkRange(MARK_DIFF_CHANGE, CLogicInt(1), CLogicInt(2));
	diff.SetDiffMarkRange(MARK_DIFF_DELETE, CLogicInt(4), CLogicInt(10));	// 最后一行之后的删除，在最后一行标 MARK_DIFF_DEL_EX
	EXPECT_TRUE(CDiffManager::getInstance()->IsDiffUse());

	EXPECT_EQ(MARK_DIFF_NONE, CDiffLineGetter(mgr.GetLine(CLogicInt(0))).GetLineDiffMark());
	EXPECT_EQ(MARK_DIFF_CHANGE, CDiffLineGetter(mgr.GetLine(CLogicInt(1))).GetLineDiffMark());
	EXPECT_EQ(MARK_DIFF_CHANGE, CDiffLineGetter(mgr.GetLine(CLogicInt(2))).GetLineDiffMark());
	EXPECT_EQ(MARK_DIFF_NONE, CDiffLineGetter(mgr.GetLine(CLogicInt(3))).GetLineDiffMark());
	EXPECT_EQ(MARK_DIFF_DELETE, CDiffLineGetter(mgr.GetLine(CLogicInt(4))).GetLineDiffMark());

	CLogicInt found(-1);
	EXPECT_TRUE(diff.SearchDiffMark(CLogicInt(0), SEARCH_FORWARD, &found));
	EXPECT_EQ(1, found);
	EXPECT_TRUE(diff.SearchDiffMark(CLogicInt(2), SEARCH_FORWARD, &found));
	EXPECT_EQ(4, found);
	EXPECT_TRUE(diff.SearchDiffMark(CLogicInt(4), SEARCH_BACKWARD, &found));
	EXPECT_EQ(2, found);
	EXPECT_FALSE(diff.SearchDiffMark(CLogicInt(1), SEARCH_BACKWARD, &found));

	diff.ResetAllDiffMark();
	EXPECT_FALSE(diff.SearchDiffMark(CLogicInt(0), SEARCH_FORWARD, &found));
	EXPECT_FALSE(CDiffManager::getInstance()->IsDiffUse());
}

TEST(MacCModifyVisitor, ResetAllModifyFlag)
{
	CDocLineMgr mgr;
	SetLines(mgr, { LTEXT("a\n"), LTEXT("b") });
	CModifyVisitor visitor;
	visitor.SetLineModified(mgr.GetLine(CLogicInt(1)), 5);
	EXPECT_EQ(5, visitor.GetLineModifiedSeq(mgr.GetLine(CLogicInt(1))));
	EXPECT_TRUE(visitor.IsLineModified(mgr.GetLine(CLogicInt(1)), 3));
	visitor.ResetAllModifyFlag(&mgr, 3);
	EXPECT_FALSE(visitor.IsLineModified(mgr.GetLine(CLogicInt(0)), 3));
	EXPECT_FALSE(visitor.IsLineModified(mgr.GetLine(CLogicInt(1)), 3));
}

// ---------------------------------------------------------------------------
// 内置类型的默认设置（types）
// ---------------------------------------------------------------------------

TEST(MacTypeConfig, BuiltinTypesHaveWindowsDefaults)
{
	env::ShareDataTestSuite::SetUpShareData();
	struct Expected { std::unique_ptr<CType> type; const WCHAR* name; const WCHAR* exts; };
	std::vector<Expected> table;
	table.push_back({ std::make_unique<CType_Basis>(),  LTEXT("基本"), LTEXT("") });
	table.push_back({ std::make_unique<CType_Text>(),   LTEXT("テキスト"), LTEXT("txt,log,1st,err,ps") });
	table.push_back({ std::make_unique<CType_Cpp>(),    LTEXT("C/C++"), LTEXT("c,cpp,cxx,cc,cp,c++,h,hpp,hxx,hh,hp,h++,rc,hm") });
	table.push_back({ std::make_unique<CType_Html>(),   LTEXT("HTML"), LTEXT("html,htm,shtml,plg") });
	table.push_back({ std::make_unique<CType_Sql>(),    LTEXT("PL/SQL"), LTEXT("sql,plsql") });
	table.push_back({ std::make_unique<CType_Cobol>(),  LTEXT("COBOL"), LTEXT("cbl,cpy,pco,cob") });
	table.push_back({ std::make_unique<CType_Java>(),   LTEXT("Java"), LTEXT("java,jav") });
	table.push_back({ std::make_unique<CType_Asm>(),    LTEXT("アセンブラ"), LTEXT("asm") });
	table.push_back({ std::make_unique<CType_Awk>(),    LTEXT("AWK"), LTEXT("awk") });
	table.push_back({ std::make_unique<CType_Dos>(),    LTEXT("MS-DOSバッチファイル"), LTEXT("bat") });
	table.push_back({ std::make_unique<CType_Pascal>(), LTEXT("Pascal"), LTEXT("dpr,pas") });
	table.push_back({ std::make_unique<CType_Tex>(),    LTEXT("TeX"), LTEXT("tex,ltx,sty,bib,log,blg,aux,bbl,toc,lof,lot,idx,ind,glo") });
	table.push_back({ std::make_unique<CType_Perl>(),   LTEXT("Perl"), LTEXT("cgi,pl,pm") });
	table.push_back({ std::make_unique<CType_Python>(), LTEXT("Python"), LTEXT("py") });
	table.push_back({ std::make_unique<CType_Vb>(),     LTEXT("Visual Basic"), LTEXT("bas,frm,cls,ctl,pag,dob,dsr,vb") });
	table.push_back({ std::make_unique<CType_Rich>(),   LTEXT("リッチテキスト"), LTEXT("rtf") });
	table.push_back({ std::make_unique<CType_Ini>(),    LTEXT("設定ファイル"), LTEXT("ini,inf,cnf,kwd,col") });

	for (int i = 0; i < int(table.size()); ++i) {
		auto config = std::make_unique<STypeConfig>();
		table[i].type->InitTypeConfig(i, *config);
		EXPECT_EQ(i, config->m_nIdx) << i;
		EXPECT_STREQ(table[i].name, config->m_szTypeName) << i;
		EXPECT_STREQ(table[i].exts, config->m_szTypeExts) << i;
		EXPECT_EQ(IME_CMODE_NOCONVERSION, config->m_nImeState) << i;
	}
	// 各类型设置的例子
	auto cpp = std::make_unique<STypeConfig>();
	CType_Cpp().InitTypeConfig(2, *cpp);
	EXPECT_EQ(OUTLINE_C_CPP, cpp->m_eDefaultOutline);
	EXPECT_EQ(SMARTINDENT_CPP, cpp->m_eSmartIndent);
	EXPECT_STREQ(LTEXT("//"), cpp->m_cLineComment.getLineComment(0));
	EXPECT_STREQ(LTEXT("/*"), cpp->m_cBlockComments[0].getBlockCommentFrom());
	EXPECT_STREQ(LTEXT("*/"), cpp->m_cBlockComments[0].getBlockCommentTo());
	auto python = std::make_unique<STypeConfig>();
	CType_Python().InitTypeConfig(13, *python);
	EXPECT_EQ(OUTLINE_PYTHON, python->m_eDefaultOutline);
	EXPECT_STREQ(LTEXT("#"), python->m_cLineComment.getLineComment(0));
}

// ---------------------------------------------------------------------------
// BSTR、VARIANT（ole_types.cpp）
// ---------------------------------------------------------------------------

TEST(MacOleTypes, BstrLayoutMatchesWindows)
{
	BSTR s = ::SysAllocStringLen(LTEXT("ab\0c"), 4);	// 中间的 NUL 也算在长度里
	ASSERT_NE(nullptr, s);
	EXPECT_EQ(4u, ::SysStringLen(s));
	EXPECT_EQ(8u, *reinterpret_cast<const std::uint32_t*>(reinterpret_cast<const char*>(s) - 4));	// 前 4 字节是字节数
	EXPECT_EQ(0, s[4]);
	EXPECT_TRUE(::SysReAllocString(&s, LTEXT("xyz")));
	EXPECT_EQ(3u, ::SysStringLen(s));
	::SysFreeString(s);
	EXPECT_EQ(0u, ::SysStringLen(nullptr));
}

TEST(MacOleTypes, VariantCopyDuplicatesString)
{
	VARIANT src;
	::VariantInit(&src);
	src.vt = VT_BSTR;
	src.bstrVal = ::SysAllocString(LTEXT("sakura"));
	VARIANT dst;
	::VariantInit(&dst);
	EXPECT_EQ(S_OK, ::VariantCopy(&dst, &src));
	EXPECT_EQ(VT_BSTR, dst.vt);
	EXPECT_NE(src.bstrVal, dst.bstrVal);
	EXPECT_STREQ(LTEXT("sakura"), dst.bstrVal);

	VARIANT ref;
	::VariantInit(&ref);
	ref.vt = VT_BYREF | VT_VARIANT;
	ref.pvarVal = &src;
	VARIANT ind;
	EXPECT_EQ(S_OK, ::VariantCopyInd(&ind, &ref));
	EXPECT_STREQ(LTEXT("sakura"), ind.bstrVal);

	::VariantClear(&src);
	::VariantClear(&dst);
	::VariantClear(&ind);
	EXPECT_EQ(VT_EMPTY, src.vt);
}

} // namespace
