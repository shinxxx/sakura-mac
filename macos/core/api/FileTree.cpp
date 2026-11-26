/*!	@file
	@brief ファイルツリー（第 43 步）

	原版 CDlgFuncList::LoadFileTreeSetting・SetTreeFile・SetTreeFileSub、CDlgFileTree::GetData 中不依赖窗口的部分。
	树的显示、设置对话框由界面层做。
*/
/*
	Copyright (C) 2026, Sakura Editor Organization

	SPDX-License-Identifier: Zlib
*/

#include "StdAfx.h"
#include "sakura_core/SakuraCore.h"

#include "env/CDataProfile.h"
#include "env/CDocTypeManager.h"
#include "env/CFileNameManager.h"
#include "env/DLLSHAREDATA.h"
#include "grep/CGrepEnumFilterFiles.h"
#include "grep/CGrepEnumFilterFolders.h"
#include "grep/CGrepEnumKeys.h"
#include "mem/CNativeW.h"
#include "typeprop/CImpExpManager.h"
#include "util/file.h"

#include <filesystem>

namespace sakura::core {

namespace {

FileTreeItem FromShare(const SFileTreeItem& s)
{
	FileTreeItem item;
	item.type = static_cast<FileTreeItemType>(s.m_eFileTreeItemType);
	item.path = s.m_szTargetPath.c_str();
	item.label = s.m_szLabelName.c_str();
	item.depth = s.m_nDepth;
	item.file = s.m_szTargetFile.c_str();
	item.ignoreHidden = s.m_bIgnoreHidden;
	item.ignoreReadOnly = s.m_bIgnoreReadOnly;
	item.ignoreSystem = s.m_bIgnoreSystem;
	return item;
}

SFileTreeItem ToShare(const FileTreeItem& item)
{
	SFileTreeItem s;
	s.m_eFileTreeItemType = static_cast<EFileTreeItemType>(item.type);
	s.m_szTargetPath = item.path.substr(0, s.m_szTargetPath.GetBufferCount() - 1).c_str();
	s.m_szLabelName = item.label.substr(0, s.m_szLabelName.GetBufferCount() - 1).c_str();
	s.m_nDepth = item.depth;
	s.m_szTargetFile = item.file.substr(0, s.m_szTargetFile.GetBufferCount() - 1).c_str();
	s.m_bIgnoreHidden = item.ignoreHidden;
	s.m_bIgnoreReadOnly = item.ignoreReadOnly;
	s.m_bIgnoreSystem = item.ignoreSystem;
	return s;
}

std::vector<FileTreeItem> FromShare(const std::vector<SFileTreeItem>& items)
{
	std::vector<FileTreeItem> result;
	result.reserve(items.size());
	for (const auto& s : items) result.push_back(FromShare(s));
	return result;
}

std::vector<SFileTreeItem> ToShare(const std::vector<FileTreeItem>& items)
{
	std::vector<SFileTreeItem> result;
	result.reserve(items.size());
	for (const auto& item : items) result.push_back(ToShare(item));
	return result;
}

//! 设置文件读到 items（原版 CDataProfile::ReadProfile + CImpExpFileTree::IO_FileTreeIni）
bool ReadFileTreeIni(const Text& path, std::vector<FileTreeItem>& items)
{
	CDataProfile cProfile;
	cProfile.SetReadingMode();
	if (!cProfile.ReadProfile(path.c_str())) return false;
	std::vector<SFileTreeItem> data;
	CImpExpFileTree::IO_FileTreeIni(cProfile, data);
	items = FromShare(data);
	return true;
}

//! デフォルト設定ファイル名 的绝对路径（原版：相对路径从 sakura.ini 的文件夹，GetInidirOrExedir）
Text DefaultIniPath(const Text& name)
{
	if (_IS_REL_PATH(name.c_str())) {
		WCHAR szDir[_MAX_PATH * 2];
		GetInidirOrExedir(szDir, name.c_str());
		return szDir;
	}
	return name;
}

//! 共通設定 或 タイプ別設定 的 SFileTree（原版 ProfDockSet() == 0 ? CommonSet() : TypeSet()）
bool UseTypeSetting()
{
	return GetDllShareData().m_Common.m_sOutline.m_nOutlineDockSet != 0;
}

//! 绝对路径（原版：当前文件夹 + GetLongFileName。"." ".." 去掉，最后的 / 去掉）
Text AbsolutePath(const Text& path, const Text& baseFolder)
{
	namespace fs = std::filesystem;
	fs::path p{ path };
	if (_IS_REL_PATH(path.c_str())) {
		p = fs::path{ baseFolder.empty() ? Text(LTEXT("/")) : baseFolder } / p;
	}
	Text result = sakura::path_to_wstring(p.lexically_normal());
	while (1 < result.size() && result.back() == LCHAR('/')) result.pop_back();
	return result;
}

} // namespace

FileTreeSetting LoadFileTreeSetting(std::int32_t typeIndex, const Text& folder)
{
	FileTreeSetting data;
	if (!IsStarted()) return data;
	const auto& common = GetDllShareData().m_Common.m_sOutline;
	STypeConfig type;
	const SFileTree* pFileTree = &common.m_sFileTree;
	if (UseTypeSetting() && CDocTypeManager().GetTypeConfig(CTypeConfig(typeIndex), type)) {
		pFileTree = &type.m_sFileTree;
		data.origin = FileTreeSettingFrom::Type;
	}
	data.loadedFrom = data.origin;
	data.project = pFileTree->m_bProject;
	data.defaultProjectIni = pFileTree->m_szProjectIni.c_str();
	if (data.project) {
		// 各フォルダーのプロジェクトファイル読み込み（原版：当前文件夹开始往上到根，CDlgTagJumpList::DirUp）
		namespace fs = std::filesystem;
		const Text name = common.m_sFileTreeDefIniName.c_str();
		fs::path dir{ AbsolutePath(folder.empty() ? Text(LTEXT(".")) : folder, folder) };
		while (!name.empty()) {
			const Text ini = sakura::path_to_wstring(dir / fs::path{ name });
			if (ReadFileTreeIni(ini, data.items)) {
				data.loadedFrom = FileTreeSettingFrom::File;
				data.iniFolder = sakura::path_to_wstring(dir);
				data.loadedIni = ini;
				break;
			}
			if (!dir.has_parent_path() || dir.parent_path() == dir) break;
			dir = dir.parent_path();
		}
	}
	if (data.loadedIni.empty()) {
		// デフォルトプロジェクトファイル読み込み
		bool bReadIni = false;
		if (!data.defaultProjectIni.empty()) {
			const Text ini = DefaultIniPath(data.defaultProjectIni);
			if (ReadFileTreeIni(ini, data.items)) {
				data.loadedIni = ini;
				bReadIni = true;
			}
		}
		if (!bReadIni) {
			// 共通設定orタイプ別設定から読み込み
			data.items.clear();
			for (int i = 0; i < pFileTree->m_nItemCount && i < kFileTreeMaxItems; ++i) {
				data.items.push_back(FromShare(pFileTree->m_aItems[i]));
			}
		}
	}
	return data;
}

bool LoadFileTreeDefaultIni(FileTreeSetting& setting, const Text& defaultProjectIni)
{
	// 原版 IDC_BUTTON_LOAD：読めたら项目と読み込んだファイル名を替える（デフォルト設定ファイル名 は入力のまま）
	setting.defaultProjectIni = defaultProjectIni;
	if (defaultProjectIni.empty()) return false;
	const Text ini = DefaultIniPath(defaultProjectIni);
	if (!ReadFileTreeIni(ini, setting.items)) return false;
	setting.loadedIni = ini;
	return true;
}

std::vector<FileTreeRoot> FileTreeRoots(const FileTreeSetting& setting, const Text& folder)
{
	std::vector<FileTreeRoot> roots;
	for (int i = 0; i < static_cast<int>(setting.items.size()); ++i) {
		const FileTreeItem& item = setting.items[i];
		FileTreeRoot root;
		root.itemIndex = i;
		root.type = item.type;
		root.depth = item.depth;
		// item.path => szPath メタ文字の展開
		WCHAR szPath[_MAX_PATH];
		Text path;
		if (CFileNameManager::ExpandMetaToFolder(item.path.c_str(), szPath, int(std::size(szPath)))) {
			path = szPath;
		} else {
			path = LTEXT("<Error:Long Path>");
		}
		// <iniroot>展開（設定ファイルを読んだとき）
		if (!setting.loadedIni.empty()) {
			CNativeW strTemp(path.c_str());
			strTemp.Replace(LTEXT("<iniroot>"), setting.iniFolder.c_str());
			path = _MAX_PATH <= strTemp.GetStringLength() ? Text(LTEXT("<Error:Long Path>")) : Text(strTemp.GetStringPtr());
		}
		// 「.」等の展開（原版 GetLongFileName。Mac 版の相対パスは folder から）
		if (path != LTEXT("<Error:Long Path>")) {
			path = AbsolutePath(path, folder);
		}
		root.path = path;
		if (item.type == FileTreeItemType::Folder) {
			root.label = item.label.empty() ? Text(LTEXT("Folder")) : item.label;
			root.path.clear();
		} else {
			root.label = item.label.empty() ? path : item.label;
		}
		roots.push_back(std::move(root));
	}
	return roots;
}

FileTreeListing ListFileTree(const FileTreeItem& item, const Text& folder)
{
	FileTreeListing listing;
	CGrepEnumKeys cGrepEnumKeys;
	if (cGrepEnumKeys.SetFileKeys(item.file.c_str()) != 0) {
		listing.wildcardError = true;
		return listing;
	}
	CGrepEnumOptions cGrepEnumOptions;
	cGrepEnumOptions.m_bIgnoreHidden = item.ignoreHidden;
	cGrepEnumOptions.m_bIgnoreReadOnly = item.ignoreReadOnly;
	cGrepEnumOptions.m_bIgnoreSystem = item.ignoreSystem;
	CGrepEnumFiles cGrepExceptAbsFiles;
	cGrepExceptAbsFiles.Enumerates(LTEXT(""), cGrepEnumKeys.m_vecExceptAbsFileKeys, cGrepEnumOptions);
	CGrepEnumFolders cGrepExceptAbsFolders;
	cGrepExceptAbsFolders.Enumerates(LTEXT(""), cGrepEnumKeys.m_vecExceptAbsFolderKeys, cGrepEnumOptions);

	// フォルダー一覧作成
	CGrepEnumFilterFolders cGrepEnumFilterFolders;
	cGrepEnumFilterFolders.Enumerates(folder.c_str(), cGrepEnumKeys, cGrepEnumOptions, cGrepExceptAbsFolders);
	for (int i = 0; i < cGrepEnumFilterFolders.GetCount(); ++i) {
		listing.folders.emplace_back(cGrepEnumFilterFolders.GetFileName(i));
	}
	// ファイル一覧作成
	CGrepEnumFilterFiles cGrepEnumFilterFiles;
	cGrepEnumFilterFiles.Enumerates(folder.c_str(), cGrepEnumKeys, cGrepEnumOptions, cGrepExceptAbsFiles);
	for (int i = 0; i < cGrepEnumFilterFiles.GetCount(); ++i) {
		listing.files.emplace_back(cGrepEnumFilterFiles.GetFileName(i));
	}
	return listing;
}

Text SaveFileTreeSetting(const FileTreeSetting& setting, std::int32_t typeIndex, bool& truncated)
{
	truncated = false;
	if (!IsStarted()) return {};
	SFileTree* pFileTree = nullptr;
	STypeConfig type;
	if (setting.origin == FileTreeSettingFrom::Common) {
		pFileTree = &GetDllShareData().m_Common.m_sOutline.m_sFileTree;
	} else if (CDocTypeManager().GetTypeConfig(CTypeConfig(typeIndex), type)) {
		pFileTree = &type.m_sFileTree;
	}
	const bool bSaveShareData = setting.loadedIni.empty();
	std::vector<FileTreeItem> items = setting.items;
	if (bSaveShareData && kFileTreeMaxItems < static_cast<int>(items.size())) {
		items.resize(kFileTreeMaxItems);
		truncated = true;
	}
	if (pFileTree) {
		pFileTree->m_bProject = setting.project;
		pFileTree->m_szProjectIni = setting.defaultProjectIni.substr(0, pFileTree->m_szProjectIni.GetBufferCount() - 1).c_str();
		if (bSaveShareData) {
			pFileTree->m_nItemCount = static_cast<int>(items.size());
			for (int i = 0; i < pFileTree->m_nItemCount; ++i) {
				pFileTree->m_aItems[i] = ToShare(items[i]);
			}
		}
		if (setting.origin == FileTreeSettingFrom::Type) {
			CDocTypeManager().SetTypeConfig(CTypeConfig(typeIndex), type);
		}
	}
	if (!bSaveShareData) {
		// 元のiniに保存
		return ExportFileTree(setting.loadedIni, items);
	}
	return {};
}

std::optional<std::vector<FileTreeItem>> ImportFileTree(const Text& path)
{
	std::vector<SFileTreeItem> data;
	CImpExpFileTree cImpExp(data);
	sakura::wstring strError;
	if (!cImpExp.Import(path, strError)) return std::nullopt;
	return FromShare(data);
}

Text ExportFileTree(const Text& path, const std::vector<FileTreeItem>& items)
{
	std::vector<SFileTreeItem> data = ToShare(items);
	CImpExpFileTree cImpExp(data);
	sakura::wstring strError;
	if (!cImpExp.Export(path, strError)) return strError.empty() ? Text(LTEXT("Export error")) : Text(strError);
	return {};
}

} // namespace sakura::core
