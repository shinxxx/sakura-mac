/*! @file
	@brief Win32 文件 API 的替代实现（非 Windows 平台，阶段 1 第 20 步）

	原版读文件（io/CFileLoad）、检查文件能否读写（io/CFile）用到的 Win32 文件函数，用 POSIX 实现。
	声明见 macos/platform/include/sakura_platform.h。

	与 Windows 不同的地方：
	- 共享模式（FILE_SHARE_*）不起作用。Windows 用它禁止其他程序同时写文件（原版的“排他控制”设置），
	  macOS 没有这种强制锁，改用文件协调（NSFileCoordinator）的做法在第 29 步“打开与保存”决定。
	- CreateFileMappingW 只支持映射文件；不支持不带文件的命名共享内存（原版多进程共享设置用，
	  Mac 版是单进程，第 21 步改成普通对象）。

	Copyright (C) 2026, Sakura Editor Organization
	SPDX-License-Identifier: Zlib
*/
#include "StdAfx.h"

#include <algorithm>
#include <cerrno>
#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

#include <dirent.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

namespace {

//! HANDLE 指向的对象。文件和文件映射共用 CloseHandle
struct PlatformHandle {
	enum class Kind { File, Mapping } kind;
	int fd = -1;            //!< 文件：打开的描述符；映射：复制的描述符
	bool writable = false;
	ULONGLONG size = 0;     //!< 映射：映射的大小
};

DWORD ErrnoToWin32(int e)
{
	switch (e) {
	case ENOENT:  return ERROR_FILE_NOT_FOUND;
	case ENOTDIR: return ERROR_PATH_NOT_FOUND;
	case EACCES:
	case EPERM:
	case EROFS:
	case EISDIR:  return ERROR_ACCESS_DENIED;
	case EEXIST:  return ERROR_FILE_EXISTS;
	case ENOMEM:  return ERROR_NOT_ENOUGH_MEMORY;
	case EBUSY:
	case ETXTBSY: return ERROR_SHARING_VIOLATION;
	case EINVAL:  return ERROR_INVALID_PARAMETER;
	default:      return ERROR_GEN_FAILURE;
	}
}

PlatformHandle* ToHandle(HANDLE h, PlatformHandle::Kind kind)
{
	if (!h || h == INVALID_HANDLE_VALUE) return nullptr;
	auto* p = static_cast<PlatformHandle*>(h);
	return p->kind == kind ? p : nullptr;
}

//! timespec → FILETIME
FILETIME ToFileTime(const timespec& ts)
{
	constexpr long long kEpochDiff100ns = 116444736000000000LL;
	const auto v = static_cast<unsigned long long>(ts.tv_sec * 10000000LL + ts.tv_nsec / 100 + kEpochDiff100ns);
	return FILETIME{ static_cast<DWORD>(v & 0xFFFFFFFFu), static_cast<DWORD>(v >> 32) };
}

// MapViewOfFile 返回的地址和大小（UnmapViewOfFile 时要用）
std::mutex g_viewMutex;
std::unordered_map<const void*, size_t>& Views()
{
	static std::unordered_map<const void*, size_t> views;
	return views;
}

} // namespace

HANDLE CreateFileW(const WCHAR* lpFileName, DWORD dwDesiredAccess, DWORD dwShareMode, LPSECURITY_ATTRIBUTES lpSecurityAttributes,
	DWORD dwCreationDisposition, DWORD dwFlagsAndAttributes, HANDLE hTemplateFile)
{
	(void)dwShareMode; (void)lpSecurityAttributes; (void)dwFlagsAndAttributes; (void)hTemplateFile;
	if (!lpFileName) { SetLastError(ERROR_INVALID_PARAMETER); return INVALID_HANDLE_VALUE; }
	const bool read = (dwDesiredAccess & (GENERIC_READ | GENERIC_ALL)) != 0;
	const bool write = (dwDesiredAccess & (GENERIC_WRITE | GENERIC_ALL)) != 0;
	int flags = O_CLOEXEC;
	flags |= (read && write) ? O_RDWR : write ? O_WRONLY : O_RDONLY;
	switch (dwCreationDisposition) {
	case CREATE_NEW:        flags |= O_CREAT | O_EXCL; break;
	case CREATE_ALWAYS:     flags |= O_CREAT | O_TRUNC; break;
	case OPEN_EXISTING:     break;
	case OPEN_ALWAYS:       flags |= O_CREAT; break;
	case TRUNCATE_EXISTING: flags |= O_TRUNC; break;
	default: SetLastError(ERROR_INVALID_PARAMETER); return INVALID_HANDLE_VALUE;
	}
	const std::string path = sakura::u16::to_utf8(lpFileName);
	const bool existed = ::access(path.c_str(), F_OK) == 0;
	const int fd = ::open(path.c_str(), flags, 0666);
	if (fd < 0) { SetLastError(ErrnoToWin32(errno)); return INVALID_HANDLE_VALUE; }
	struct stat st {};
	if (::fstat(fd, &st) == 0 && S_ISDIR(st.st_mode)) {
		// Windows 不加 FILE_FLAG_BACKUP_SEMANTICS 也打不开文件夹
		::close(fd);
		SetLastError(ERROR_ACCESS_DENIED);
		return INVALID_HANDLE_VALUE;
	}
	// 与 Windows 相同：用 CREATE_ALWAYS / OPEN_ALWAYS 打开已有文件时，最近错误码是 ERROR_ALREADY_EXISTS
	SetLastError((existed && (dwCreationDisposition == CREATE_ALWAYS || dwCreationDisposition == OPEN_ALWAYS)) ? ERROR_ALREADY_EXISTS : NO_ERROR);
	return new PlatformHandle{ PlatformHandle::Kind::File, fd, write, 0 };
}

BOOL CloseHandle(HANDLE hObject)
{
	if (!hObject || hObject == INVALID_HANDLE_VALUE) { SetLastError(ERROR_INVALID_HANDLE); return FALSE; }
	auto* p = static_cast<PlatformHandle*>(hObject);
	if (p->fd >= 0) ::close(p->fd);
	delete p;
	return TRUE;
}

DWORD GetFileSize(HANDLE hFile, LPDWORD lpFileSizeHigh)
{
	auto* p = ToHandle(hFile, PlatformHandle::Kind::File);
	struct stat st {};
	if (!p || ::fstat(p->fd, &st) != 0) {
		SetLastError(p ? ErrnoToWin32(errno) : ERROR_INVALID_HANDLE);
		return INVALID_FILE_SIZE;
	}
	const auto size = static_cast<ULONGLONG>(st.st_size);
	if (lpFileSizeHigh) *lpFileSizeHigh = static_cast<DWORD>(size >> 32);
	// 与 Windows 相同：低 32 位是 0xFFFFFFFF 时，调用方用 GetLastError 区分成功和失败
	SetLastError(NO_ERROR);
	return static_cast<DWORD>(size & 0xFFFFFFFFu);
}

BOOL GetFileTime(HANDLE hFile, LPFILETIME lpCreationTime, LPFILETIME lpLastAccessTime, LPFILETIME lpLastWriteTime)
{
	auto* p = ToHandle(hFile, PlatformHandle::Kind::File);
	struct stat st {};
	if (!p || ::fstat(p->fd, &st) != 0) {
		SetLastError(p ? ErrnoToWin32(errno) : ERROR_INVALID_HANDLE);
		return FALSE;
	}
#if defined(__APPLE__)
	if (lpCreationTime)   *lpCreationTime = ToFileTime(st.st_birthtimespec);
	if (lpLastAccessTime) *lpLastAccessTime = ToFileTime(st.st_atimespec);
	if (lpLastWriteTime)  *lpLastWriteTime = ToFileTime(st.st_mtimespec);
#else
	// Linux（只用于开发时检查）没有创建时间，用状态改变时间代替
	if (lpCreationTime)   *lpCreationTime = ToFileTime(st.st_ctim);
	if (lpLastAccessTime) *lpLastAccessTime = ToFileTime(st.st_atim);
	if (lpLastWriteTime)  *lpLastWriteTime = ToFileTime(st.st_mtim);
#endif
	return TRUE;
}

HANDLE CreateFileMappingW(HANDLE hFile, LPSECURITY_ATTRIBUTES lpFileMappingAttributes, DWORD flProtect,
	DWORD dwMaximumSizeHigh, DWORD dwMaximumSizeLow, const WCHAR* lpName)
{
	(void)lpFileMappingAttributes;
	auto* file = ToHandle(hFile, PlatformHandle::Kind::File);
	if (!file || lpName) {
		SetLastError(ERROR_INVALID_HANDLE);
		return nullptr;
	}
	const bool writable = flProtect == PAGE_READWRITE;
	if (!writable && flProtect != PAGE_READONLY) { SetLastError(ERROR_INVALID_PARAMETER); return nullptr; }
	if (writable && !file->writable) { SetLastError(ERROR_ACCESS_DENIED); return nullptr; }
	struct stat st {};
	if (::fstat(file->fd, &st) != 0) { SetLastError(ErrnoToWin32(errno)); return nullptr; }
	ULONGLONG size = (static_cast<ULONGLONG>(dwMaximumSizeHigh) << 32) | dwMaximumSizeLow;
	if (size == 0) size = static_cast<ULONGLONG>(st.st_size);
	if (size == 0) { SetLastError(ERROR_FILE_INVALID); return nullptr; }	// Windows 也不能映射空文件
	if (size > static_cast<ULONGLONG>(st.st_size)) {
		if (!writable) { SetLastError(ERROR_NOT_ENOUGH_MEMORY); return nullptr; }
		if (::ftruncate(file->fd, static_cast<off_t>(size)) != 0) { SetLastError(ErrnoToWin32(errno)); return nullptr; }
	}
	const int fd = ::dup(file->fd);
	if (fd < 0) { SetLastError(ErrnoToWin32(errno)); return nullptr; }
	SetLastError(NO_ERROR);
	return new PlatformHandle{ PlatformHandle::Kind::Mapping, fd, writable, size };
}

LPVOID MapViewOfFile(HANDLE hFileMappingObject, DWORD dwDesiredAccess, DWORD dwFileOffsetHigh, DWORD dwFileOffsetLow, SIZE_T dwNumberOfBytesToMap)
{
	auto* m = ToHandle(hFileMappingObject, PlatformHandle::Kind::Mapping);
	if (!m) { SetLastError(ERROR_INVALID_HANDLE); return nullptr; }
	const bool write = (dwDesiredAccess & FILE_MAP_WRITE) != 0;
	if (write && !m->writable) { SetLastError(ERROR_ACCESS_DENIED); return nullptr; }
	const ULONGLONG offset = (static_cast<ULONGLONG>(dwFileOffsetHigh) << 32) | dwFileOffsetLow;
	if (offset > m->size) { SetLastError(ERROR_ACCESS_DENIED); return nullptr; }
	size_t length = dwNumberOfBytesToMap ? dwNumberOfBytesToMap : static_cast<size_t>(m->size - offset);
	if (length == 0 || offset + length > m->size) { SetLastError(ERROR_ACCESS_DENIED); return nullptr; }
	void* p = ::mmap(nullptr, length, PROT_READ | (write ? PROT_WRITE : 0), MAP_SHARED, m->fd, static_cast<off_t>(offset));
	if (p == MAP_FAILED) { SetLastError(ErrnoToWin32(errno)); return nullptr; }
	std::lock_guard lock(g_viewMutex);
	Views()[p] = length;
	return p;
}

BOOL UnmapViewOfFile(LPCVOID lpBaseAddress)
{
	size_t length = 0;
	{
		std::lock_guard lock(g_viewMutex);
		auto it = Views().find(lpBaseAddress);
		if (it == Views().end()) { SetLastError(ERROR_INVALID_ADDRESS); return FALSE; }
		length = it->second;
		Views().erase(it);
	}
	return ::munmap(const_cast<void*>(lpBaseAddress), length) == 0 ? TRUE : FALSE;
}

// ---------------------------------------------------------------------------
// 文件的查找（第 43 步：Grep、ファイルツリー 的文件枚举）
// ---------------------------------------------------------------------------
namespace {

//! 查找的结果（FindFirstFileW 返回的句柄指向它）。一开始就读完文件夹，按 NTFS 的顺序排好
struct FindHandle {
	std::vector<WIN32_FIND_DATAW> items;
	size_t next = 0;
};

/*!
	NTFS 比较名字时用的大写（$UpCase 表）。只做常用的部分：ASCII、Latin-1、希腊文、西里尔文、全角英文字母。
	日文没有大小写，不受影响。
*/
WCHAR NtfsUpper(WCHAR c) noexcept
{
	if (u'a' <= c && c <= u'z') return WCHAR(c - 0x20);
	if (c < 0x80) return c;
	if ((0xE0 <= c && c <= 0xFE && c != 0xF7)) return WCHAR(c - 0x20);
	if (c == 0xFF) return 0x178;
	if (0x3B1 <= c && c <= 0x3C9 && c != 0x3C2) return WCHAR(c - 0x20);
	if (0x430 <= c && c <= 0x44F) return WCHAR(c - 0x20);
	if (0x450 <= c && c <= 0x45F) return WCHAR(c - 0x50);
	if (0xFF41 <= c && c <= 0xFF5A) return WCHAR(c - 0x20);
	return c;
}

//! NTFS 的目录的顺序：大写以后按 UTF-16 的值比较
bool NtfsLess(const WCHAR* a, const WCHAR* b) noexcept
{
	for (;; ++a, ++b) {
		const WCHAR ua = NtfsUpper(*a);
		const WCHAR ub = NtfsUpper(*b);
		if (ua != ub) return ua < ub;
		if (*a == 0) return false;
	}
}

//! FindFirstFile 的模式（'*'、'?'，不区分大小写）。与 Windows 相同，"*.*" 是全部，"xxx.*" 也匹配没有扩展名的 "xxx"
bool FindPatternMatch(std::u16string_view name, std::u16string_view spec) noexcept
{
	if (spec == u"*" || spec == u"*.*") return true;
	auto match = [](std::u16string_view f, std::u16string_view p) {
		size_t fi = 0, pi = 0, starP = std::u16string_view::npos, starF = 0;
		while (fi < f.size()) {
			if (pi < p.size() && p[pi] == u'*') {
				starP = ++pi;
				starF = fi;
			} else if (pi < p.size() && (p[pi] == u'?' || NtfsUpper(p[pi]) == NtfsUpper(f[fi]))) {
				++pi;
				++fi;
			} else if (starP != std::u16string_view::npos) {
				pi = starP;
				fi = ++starF;
			} else {
				return false;
			}
		}
		while (pi < p.size() && p[pi] == u'*') ++pi;
		return pi == p.size();
	};
	if (match(name, spec)) return true;
	return spec.size() >= 2 && spec.substr(spec.size() - 2) == u".*"
		&& name.find(u'.') == std::u16string_view::npos && match(name, spec.substr(0, spec.size() - 2));
}

//! stat 的结果 → WIN32_FIND_DATAW
WIN32_FIND_DATAW MakeFindData(const std::u16string& name, const struct stat& st)
{
	WIN32_FIND_DATAW fd {};
	DWORD attr = 0;
	if (S_ISDIR(st.st_mode)) attr |= FILE_ATTRIBUTE_DIRECTORY;
	if ((st.st_mode & (S_IWUSR | S_IWGRP | S_IWOTH)) == 0) attr |= FILE_ATTRIBUTE_READONLY;
	bool hidden = name.size() > 1 && name[0] == u'.' && name != u"..";
#if defined(__APPLE__)
	hidden = hidden || (st.st_flags & UF_HIDDEN) != 0;
	fd.ftCreationTime = ToFileTime(st.st_birthtimespec);
	fd.ftLastAccessTime = ToFileTime(st.st_atimespec);
	fd.ftLastWriteTime = ToFileTime(st.st_mtimespec);
#else
	fd.ftCreationTime = ToFileTime(st.st_ctim);
	fd.ftLastAccessTime = ToFileTime(st.st_atim);
	fd.ftLastWriteTime = ToFileTime(st.st_mtim);
#endif
	if (hidden) attr |= FILE_ATTRIBUTE_HIDDEN;
	if (!S_ISDIR(st.st_mode)) attr |= FILE_ATTRIBUTE_ARCHIVE;	// Windows 的普通文件一般有存档属性
	fd.dwFileAttributes = attr;
	if (!S_ISDIR(st.st_mode)) {
		const auto size = static_cast<ULONGLONG>(st.st_size);
		fd.nFileSizeHigh = static_cast<DWORD>(size >> 32);
		fd.nFileSizeLow = static_cast<DWORD>(size & 0xFFFFFFFFu);
	}
	const size_t n = std::min(name.size(), size_t(MAX_PATH - 1));
	std::copy_n(name.data(), n, fd.cFileName);
	fd.cFileName[n] = 0;
	return fd;
}

} // namespace

HANDLE FindFirstFileW(const WCHAR* lpFileName, LPWIN32_FIND_DATAW lpFindFileData)
{
	if (!lpFileName || !lpFindFileData) { SetLastError(ERROR_INVALID_PARAMETER); return INVALID_HANDLE_VALUE; }
	const std::u16string_view full(lpFileName);
	const auto slash = full.find_last_of(u'/');
	const std::u16string_view spec = slash == std::u16string_view::npos ? full : full.substr(slash + 1);
	std::u16string folder = slash == std::u16string_view::npos ? std::u16string(u".")
		: slash == 0 ? std::u16string(u"/") : std::u16string(full.substr(0, slash));
	if (spec.empty()) { SetLastError(ERROR_FILE_NOT_FOUND); return INVALID_HANDLE_VALUE; }
	const std::string folderUtf8 = sakura::u16::to_utf8(folder.c_str());
	DIR* dir = ::opendir(folderUtf8.c_str());
	if (!dir) { SetLastError(errno == ENOENT || errno == ENOTDIR ? ERROR_PATH_NOT_FOUND : ErrnoToWin32(errno)); return INVALID_HANDLE_VALUE; }
	auto handle = std::make_unique<FindHandle>();
	std::vector<WIN32_FIND_DATAW> dots;
	while (const dirent* e = ::readdir(dir)) {
		const std::u16string name = sakura::u16::from_utf8(e->d_name);
		if (!FindPatternMatch(name, spec)) continue;
		std::string path = folderUtf8;
		if (path.back() != '/') path += '/';
		path += e->d_name;
		struct stat st {};
		if (::stat(path.c_str(), &st) != 0 && ::lstat(path.c_str(), &st) != 0) continue;	// 链接到的东西不在时用链接本身
		auto& list = (name == u"." || name == u"..") ? dots : handle->items;
		list.push_back(MakeFindData(name, st));
	}
	::closedir(dir);
	std::sort(handle->items.begin(), handle->items.end(), [](const WIN32_FIND_DATAW& a, const WIN32_FIND_DATAW& b) {
		if (NtfsLess(a.cFileName, b.cFileName)) return true;
		if (NtfsLess(b.cFileName, a.cFileName)) return false;
		return std::u16string_view(a.cFileName) < std::u16string_view(b.cFileName);	// 区分大小写的文件系统上大写相同的名字
	});
	std::sort(dots.begin(), dots.end(), [](const WIN32_FIND_DATAW& a, const WIN32_FIND_DATAW& b) {
		return std::u16string_view(a.cFileName).size() < std::u16string_view(b.cFileName).size();
	});
	handle->items.insert(handle->items.begin(), dots.begin(), dots.end());
	if (handle->items.empty()) { SetLastError(ERROR_FILE_NOT_FOUND); return INVALID_HANDLE_VALUE; }
	*lpFindFileData = handle->items[0];
	handle->next = 1;
	SetLastError(NO_ERROR);
	return handle.release();
}

BOOL FindNextFileW(HANDLE hFindFile, LPWIN32_FIND_DATAW lpFindFileData)
{
	if (!hFindFile || hFindFile == INVALID_HANDLE_VALUE || !lpFindFileData) { SetLastError(ERROR_INVALID_HANDLE); return FALSE; }
	auto* h = static_cast<FindHandle*>(hFindFile);
	if (h->next >= h->items.size()) { SetLastError(ERROR_NO_MORE_FILES); return FALSE; }
	*lpFindFileData = h->items[h->next++];
	return TRUE;
}

BOOL FindClose(HANDLE hFindFile)
{
	if (!hFindFile || hFindFile == INVALID_HANDLE_VALUE) { SetLastError(ERROR_INVALID_HANDLE); return FALSE; }
	delete static_cast<FindHandle*>(hFindFile);
	return TRUE;
}

// ---------------------------------------------------------------------------
// 删除文件、改名（第 43 步：Grep置換）
// ---------------------------------------------------------------------------
BOOL DeleteFileW(const WCHAR* lpFileName)
{
	if (!lpFileName) { SetLastError(ERROR_INVALID_PARAMETER); return FALSE; }
	const std::string path = sakura::u16::to_utf8(lpFileName);
	struct stat st {};
	if (::lstat(path.c_str(), &st) != 0) { SetLastError(ErrnoToWin32(errno)); return FALSE; }
	if (S_ISDIR(st.st_mode)) { SetLastError(ERROR_ACCESS_DENIED); return FALSE; }
	// Windows 不能删除只读文件
	if (!S_ISLNK(st.st_mode) && (st.st_mode & (S_IWUSR | S_IWGRP | S_IWOTH)) == 0) { SetLastError(ERROR_ACCESS_DENIED); return FALSE; }
	if (::unlink(path.c_str()) != 0) { SetLastError(ErrnoToWin32(errno)); return FALSE; }
	return TRUE;
}

BOOL MoveFileW(const WCHAR* lpExistingFileName, const WCHAR* lpNewFileName)
{
	if (!lpExistingFileName || !lpNewFileName) { SetLastError(ERROR_INVALID_PARAMETER); return FALSE; }
	const std::string from = sakura::u16::to_utf8(lpExistingFileName);
	const std::string to = sakura::u16::to_utf8(lpNewFileName);
	struct stat st {};
	if (::lstat(to.c_str(), &st) == 0) { SetLastError(ERROR_ALREADY_EXISTS); return FALSE; }
	if (::rename(from.c_str(), to.c_str()) != 0) { SetLastError(ErrnoToWin32(errno)); return FALSE; }
	return TRUE;
}
