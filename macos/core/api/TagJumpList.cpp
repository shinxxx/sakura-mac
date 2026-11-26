/*! @file
	@brief タグジャンプ一覧の検索（计划第 44 步：ダイレクトタグジャンプ・キーワードを指定してタグジャンプ・タグジャンプ一覧）

	原版 dlg/CDlgTagJumpList.cpp の検索の部分（tags ファイルを開いて探す、上の階層の tags も探す、
	!_TAG_ の設定、二分探索・線形探索、ページめくり、最も近い候補の選択、ファイルのフルパス）の Mac 版。
	原版のダイアログ（CDialog）から切り離して、ダイアログは App（TagJumpList.swift）が作る。
	tags ファイルは原版と同じく ANSI（Mac 版は UTF-8，CP_ACP）で読む。パスの区切りは '/'。
*/
/*
	Copyright (C) 2003, MIK
	Copyright (C) 2005, MIK, genta
	Copyright (C) 2010, Moca
	Copyright (C) 2018-2022, Sakura Editor Organization
	Copyright (C) 2026, Sakura Editor Organization

	SPDX-License-Identifier: Zlib
*/
#include "StdAfx.h"
#include "sakura_core/SakuraCore.h"

#include "env/CSortedTagJumpList.h"
#include "env/DLLSHAREDATA.h"
#include "recent/CRecentTagjumpKeyword.h"
#include "mem/CNativeA.h"
#include "mem/CNativeW.h"
#include "util/container.h"
#include "util/file.h"
#include "util/string_ex.h"
#include "util/tchar_convert.h"

#include <cstdio>
#include <memory>

namespace sakura::core {

namespace {

// タグファイルのフォーマット（原版と同じ）
#define TAG_FORMAT_2_A       "%[^\t\r\n]\t%[^\t\r\n]\t%d;\"\t%s\t%s"
#define TAG_FORMAT_1_A       "%[^\t\r\n]\t%[^\t\r\n]\t%d"
#define TAG_FILE_INFO_A      "%[^\t\r\n]\t%[^\t\r\n]\t%[^\t\r\n]"
constexpr const WCHAR* TAG_FILENAME_T = LTEXT("tags");

//! ctags が出力する、拡張子と対応する種類（原版 p_extentions）
const WCHAR* const p_extentions[] = {
	/*asm*/			LTEXT("asm,s"),								LTEXT("d=define,l=label,m=macro,t=type"),
	/*asp*/			LTEXT("asp,asa"),								LTEXT("f=function,s=sub"),
	/*awk*/			LTEXT("awk,gawk,mawk"),						LTEXT("f=function"),
	/*beta*/		LTEXT("bet"),									LTEXT("f=fragment,p=pattern,s=slot,v=virtual"),
	/*c*/			LTEXT("c,h"),									LTEXT("c=class,d=macro,e=enumerator,f=function,g=enum,m=member,n=namespace,p=prototype,s=struct,t=typedef,u=union,v=variable,x=externvar"),
	/*c++*/			LTEXT("c++,cc,cp,cpp,cxx,h++,hh,hp,hpp,hxx"),	LTEXT("c=class,d=macro,e=enumerator,f=function,g=enum,m=member,n=namespace,p=prototype,s=struct,t=typedef,u=union,v=variable,x=externvar"),
	/*java*/		LTEXT("java"),									LTEXT("c=class,d=macro,e=enumerator,f=function,g=enum,m=member,n=namespace,p=prototype,s=struct,t=typedef,u=union,v=variable,x=externvar"),
	/*vera*/		LTEXT("vr,vri,vrh"),							LTEXT("c=class,d=macro,e=enumerator,f=function,g=enum,m=member,n=namespace,p=prototype,s=struct,t=typedef,u=union,v=variable,x=externvar"),
	/*cobol*/		LTEXT("cbl,cob"),								LTEXT("d=data,f=file,g=group,p=paragraph,P=program,s=section"),
	/*eiffel*/		LTEXT("e"),									LTEXT("c=class,f=feature,l=local"),
	/*fortran*/		LTEXT("f,for,ftn,f77,f90,f95"),				LTEXT("b=block data,c=common,e=entry,f=function,i=interface,k=component,l=label,L=local,m=module,n=namelist,p=program,s=subroutine,t=type,v=variable"),
	/*lisp*/		LTEXT("cl,clisp,el,l,lisp,lsp,ml"),			LTEXT("f=function"),
	/*lua*/			LTEXT("lua"),									LTEXT("f=function"),
	/*makefile*/	LTEXT("mak"),									LTEXT("m=macro"),
	/*pascal*/		LTEXT("p,pas"),								LTEXT("f=function,p=procedure"),
	/*perl*/		LTEXT("pl,pm,perl"),							LTEXT("s=subroutine,p=package"),
	/*php*/			LTEXT("php,php3,phtml"),						LTEXT("c=class,f=function"),
	/*python*/		LTEXT("py,python"),							LTEXT("c=class,f=function,m=member"),
	/*rexx*/		LTEXT("cmd,rexx,rx"),							LTEXT("s=subroutine"),
	/*ruby*/		LTEXT("rb"),									LTEXT("c=class,f=method,F=singleton method,m=mixin"),
	/*scheme*/		LTEXT("sch,scheme,scm,sm"),					LTEXT("f=function,s=set"),
	/*sh*/			LTEXT("sh,bsh,bash,ksh,zsh"),					LTEXT("f=function"),
	/*slang*/		LTEXT("sl"),									LTEXT("f=function,n=namespace"),
	/*sql*/			LTEXT("sql"),									LTEXT("c=cursor,d=prototype,f=function,F=field,l=local,P=package,p=procedure,r=record,s=subtype,t=table,T=trigger,v=variable"),
	/*tcl*/			LTEXT("tcl,tk,wish,itcl"),						LTEXT("p=procedure,c=class,f=method"),
	/*verilog*/		LTEXT("v"),									LTEXT("f=function,m=module,P=parameter,p=port,r=reg,t=task,v=variable,w=wire"),
	/*vim*/			LTEXT("vim"),									LTEXT("f=function,v=variable"),
	/*yacc*/		LTEXT("y"),									LTEXT("l=label"),
					nullptr,									nullptr
};

//! 「.ext」形式のタイプ情報（原版 GetNameByType）
Text GetNameByType(const WCHAR type, const WCHAR* name)
{
	const WCHAR* p = wcsrchr(name, LCHAR('.'));
	if (!p) p = LTEXT(".c");	//見つからないときは ".c" と想定する。
	p++;
	for (int i = 0; p_extentions[i]; i += 2) {
		sakura::wstring exts(p_extentions[i]);
		size_t pos = 0;
		while (pos <= exts.size()) {
			const size_t comma = exts.find(LCHAR(','), pos);
			const auto token = exts.substr(pos, comma == sakura::wstring::npos ? sakura::wstring::npos : comma - pos);
			if (_wcsicmp(p, token.c_str()) == 0) {
				sakura::wstring kinds(p_extentions[i + 1]);
				size_t k = 0;
				while (k <= kinds.size()) {
					const size_t c = kinds.find(LCHAR(','), k);
					const auto kind = kinds.substr(k, c == sakura::wstring::npos ? sakura::wstring::npos : c - k);
					if (!kind.empty() && kind[0] == type) return Text(kind.substr(2));
					if (c == sakura::wstring::npos) break;
					k = c + 1;
				}
				return Text();
			}
			if (comma == sakura::wstring::npos) break;
			pos = comma + 1;
		}
	}
	return Text();
}

//! 改行コードまでを捨てる
inline void SkipLine(FILE* fp)
{
	int ch = fgetc(fp);
	while (ch != '\n' && ch != EOF) ch = fgetc(fp);
}

//! ディレクトリとディレクトリを連結する（原版 CopyDirDir）
void CopyDirDir(WCHAR* dest, size_t destLen, const WCHAR* target, const WCHAR* base)
{
	if (_IS_REL_PATH(target)) {
		::wcscpy_s(dest, destLen, base);
		cxx::AddLastYenFromDirectoryPath(std::span<WCHAR>(dest, destLen));
		if (dest[0]) ::wcscat_s(dest, destLen, target);
	} else {
		::wcscpy_s(dest, destLen, target);
	}
	cxx::AddLastYenFromDirectoryPath(std::span<WCHAR>(dest, destLen));
}

//! フォルダーを 1 階層上へ（原版 DirUp。/a/b/ → /a/）
WCHAR* DirUp(WCHAR* dir)
{
	CutLastYenFromDirectoryPath(dir);
	const WCHAR* p = GetFileTitlePointer(dir);
	if (0 < p - dir) dir[p - dir] = '\0';
	return dir;
}

int CalcMaxUpDirectory(const WCHAR* p)
{
	int loop = CalcDirectoryDepth(p);
	if (loop < 0) loop = 0;
	if (loop > (_MAX_PATH / 2)) loop = (_MAX_PATH / 2);
	return loop;
}

//! ファイル名の部分（原版 GetFileTitlePointer の位置）
const WCHAR* FileNamePart(const WCHAR* path) { return GetFileTitlePointer(path); }

struct PathParts {
	sakura::wstring dir;	// 最後の '/' まで
	sakura::wstring file;	// 拡張子を除く
	sakura::wstring ext;	// 「.」から
};
//! 原版 _wsplitpath_s の代わり（Mac 版はドライブがない）
PathParts SplitPath(const WCHAR* path)
{
	PathParts r;
	sakura::wstring s(path);
	const size_t slash = s.rfind(PATH_DELIMITER);
	r.dir = slash == sakura::wstring::npos ? sakura::wstring() : s.substr(0, slash + 1);
	sakura::wstring name = slash == sakura::wstring::npos ? s : s.substr(slash + 1);
	const size_t dot = name.rfind(LCHAR('.'));
	if (dot == sakura::wstring::npos) {
		r.file = name;
	} else {
		r.file = name.substr(0, dot);
		r.ext = name.substr(dot);
	}
	return r;
}

} // namespace

// ---------------------------------------------------------------------------

struct TagJumpList::Impl {
	struct STagFindState {
		int   m_nDepth = 0;
		int   m_nMatchAll = 0;
		int   m_nNextMode = 0;
		int   m_nLoop = -1;
		bool  m_bJumpPath = false;
		WCHAR m_szCurPath[1024] = {};
	};
	struct STagSearchRule {
		bool bTagJumpExactMatch;
		bool bTagJumpPartialMatch;
		bool bTagJumpICase;
		int  baseDirId;
		int  nTop;
	};

	bool m_bDirectTagJump = false;
	sakura::wstring m_strFileName;
	int  m_nLoop = -1;
	CSortedTagJumpList m_cList{ 50 };	// 原版 2010.07.22 ページング採用で 50
	int  m_nTop = 0;
	bool m_bNextItem = false;
	STagFindState m_sFindPrev;
	STagFindState m_sFind0Match;
	sakura::wstring m_strOldKeyword;
	bool m_bOldTagJumpICase = false;
	bool m_bOldTagJumpPartialMatch = false;
	std::vector<TagJumpListItem> m_items;

	void ClearPrevFindInfo()
	{
		m_sFindPrev.m_nMatchAll = -1;
		m_sFind0Match.m_nDepth = -1;
		m_sFind0Match.m_nMatchAll = 0;
	}

	const WCHAR* GetFilePath() const { return m_strFileName.c_str(); }

	bool ReadTagsParameter(FILE* fp, bool bTagJumpICaseByTags, STagFindState* state, int* nTagFormat, bool* bSorted,
						   bool* bFoldcase, bool* bTagJumpICase, WCHAR* szNextPath, int* baseDirId)
	{
		ACHAR szLineData[1024];
		ACHAR s[4][1024];
		int nLines = 0;
		int n2;
		fpos_t old_offset = 0;
		constexpr auto nLINEDATA_LAST_CHAR = int(std::size(szLineData)) - 2;
		szLineData[nLINEDATA_LAST_CHAR] = '\0';
		while (fgets(szLineData, int(std::size(szLineData)), fp)) {
			nLines++;
			if ('\0' != szLineData[nLINEDATA_LAST_CHAR] && '\n' != szLineData[nLINEDATA_LAST_CHAR]) SkipLine(fp);
			if (1 == nLines && szLineData[0] == '\x0c') return false;	// etagsなので次のファイル
			if ('!' == szLineData[0]) {
				if (0 == strncmp(szLineData + 1, "_TAG_", 5)) {
					s[0][0] = s[1][0] = s[2][0] = 0;
					const int nRet = sscanf(szLineData, TAG_FILE_INFO_A, s[0], s[1], s[2]);
					if (nRet < 2) {
						szLineData[nLINEDATA_LAST_CHAR] = '\0';
						continue;
					}
					const ACHAR* pTag = s[0] + 6;
					if (0 == strncmp(pTag, "FILE_FORMAT", 11)) {
						n2 = atoi(s[1]);
						if (1 <= n2 && n2 <= 2) *nTagFormat = n2;
					} else if (0 == strncmp(pTag, "FILE_SORTED", 11)) {
						n2 = atoi(s[1]);
						*bSorted = (1 == n2);
						*bFoldcase = (2 == n2);
						if (bTagJumpICaseByTags) *bTagJumpICase = *bFoldcase;
					} else if (0 == strncmp(pTag, "S_SEARCH_NEXT", 13)) {
						// 独自拡張:次に検索するtagファイルの指定
						if ('0' <= s[1][0] && s[1][0] <= '3') {
							n2 = atoi(s[1]);
							if (0 <= n2 && n2 <= 3) state->m_nNextMode = n2;
							if (1 <= n2 && s[2][0]) {
								WCHAR baseWork[1024];
								CopyDirDir(baseWork, std::size(baseWork), to_wchar(s[2]), state->m_szCurPath);
								szNextPath[0] = 0;
								if (!GetLongFileName(baseWork, szNextPath)) wcscpy(szNextPath, baseWork);
							}
						}
					} else if (0 == strncmp(pTag, "S_FILE_BASEDIR", 14)) {
						// 独自拡張:ファイル名の基準ディレクトリ
						WCHAR baseWork[1024];
						if (state->m_bJumpPath) {
							CopyDirDir(baseWork, std::size(baseWork), to_wchar(s[1]), state->m_szCurPath);
						} else {
							wcscpy(baseWork, to_wchar(s[1]));
							cxx::AddLastYenFromDirectoryPath(std::span<WCHAR>(baseWork, std::size(baseWork)));
						}
						*baseDirId = m_cList.AddBaseDir(baseWork);
					}
				}
				szLineData[nLINEDATA_LAST_CHAR] = '\0';
				old_offset = ftell(fp);
				if (old_offset == -1) return false;
				continue;
			} else {
				fsetpos(fp, &old_offset);
				break;
			}
		}
		return true;
	}

	static bool parseTagsLine(ACHAR s[][1024], ACHAR* szLineData, int* n2, int nTagFormat)
	{
		bool bRet = true;
		s[0][0] = s[1][0] = s[2][0] = s[3][0] = '\0';
		*n2 = 0;
		int nRet;
		if (2 == nTagFormat) {
			nRet = sscanf(szLineData, TAG_FORMAT_2_A, s[0], s[1], n2, s[2], s[3]);
			if (nRet < 3) bRet = false;
			if (*n2 <= 0) bRet = false;	//行番号不正(-excmd=nが指定されてないかも)
		} else {
			nRet = sscanf(szLineData, TAG_FORMAT_1_A, s[0], s[1], n2);
			if (nRet < 2) bRet = false;
			if (*n2 <= 0) bRet = false;
		}
		return bRet;
	}

	void find_key_for_BinarySearch(FILE* fp, const ACHAR* paszKeyword, int nTagFormat, STagFindState* state, const STagSearchRule* rule)
	{
		ACHAR szLineData[1024];
		ACHAR s[4][1024];
		const int nCap = m_cList.GetCapacity();
		int n2;
		enum SearchState { STATE_BINARY, STATE_SKIP_BACK, STATE_STEP_FORWARD } eSearchState = STATE_BINARY;
		constexpr auto nLINEDATA_LAST_CHAR = int(std::size(szLineData)) - 2;
		szLineData[nLINEDATA_LAST_CHAR] = '\0';
		fpos_t low_offset = 0, high_offset, curr_offset;
		fseek(fp, 0, SEEK_END);
		fgetpos(fp, &high_offset);
		curr_offset = low_offset + ((high_offset - low_offset) / 2);
		fsetpos(fp, &curr_offset);
		fgets(szLineData, int(std::size(szLineData)), fp);	// 改行コードまでを捨てる
		while (fgets(szLineData, int(std::size(szLineData)), fp)) {
			if ('\0' != szLineData[nLINEDATA_LAST_CHAR] && '\n' != szLineData[nLINEDATA_LAST_CHAR]) SkipLine(fp);
			if (parseTagsLine(s, szLineData, &n2, nTagFormat)) {
				const int cmp = strcmp(s[0], paszKeyword);
				if (0 == cmp) {
					if (eSearchState == STATE_BINARY) {
						eSearchState = STATE_SKIP_BACK;
					} else if (eSearchState == STATE_STEP_FORWARD) {
						state->m_nMatchAll++;
						if (rule->nTop < state->m_nMatchAll) {
							if (m_cList.GetCount() < nCap) {
								m_cList.AddParamA(s[0], s[1], n2, s[2][0], s[3], state->m_nDepth, rule->baseDirId);
							} else {
								m_bNextItem = true;	// 探索打ち切り(次ページでやり直し)
								break;
							}
						}
					}
				} else if (0 > cmp) {
					if (eSearchState == STATE_BINARY) low_offset = curr_offset;
					else if (eSearchState == STATE_SKIP_BACK) eSearchState = STATE_STEP_FORWARD;
				} else {
					if (eSearchState == STATE_BINARY) high_offset = curr_offset;
					else if (eSearchState == STATE_STEP_FORWARD) break;	//探索終了
				}
				// 次に探索するoffset位置算出
				if (eSearchState == STATE_BINARY) {
					const fpos_t temp = low_offset + ((high_offset - low_offset) / 2);
					if (temp == curr_offset) break;	// 一致無しのため探索終了
					curr_offset = temp;
					fsetpos(fp, &curr_offset);
					fgets(szLineData, int(std::size(szLineData)), fp);
				} else if (eSearchState == STATE_SKIP_BACK) {
					curr_offset -= 1024 * 2;
					if (curr_offset < 0) {
						curr_offset = 0;
						eSearchState = STATE_STEP_FORWARD;
					}
					fsetpos(fp, &curr_offset);
					fgets(szLineData, int(std::size(szLineData)), fp);
				}
			}
			szLineData[nLINEDATA_LAST_CHAR] = '\0';
		}
	}

	void find_key_for_LinearSearch(FILE* fp, const ACHAR* paszKeyword, int nTagFormat, STagFindState* state,
								   const STagSearchRule* rule, bool bSorted, bool bFoldcase, int length)
	{
		ACHAR szLineData[1024];
		ACHAR s[4][1024];
		const int nCap = m_cList.GetCapacity();
		int n2;
		constexpr auto nLINEDATA_LAST_CHAR = int(std::size(szLineData)) - 2;
		szLineData[nLINEDATA_LAST_CHAR] = '\0';
		while (fgets(szLineData, int(std::size(szLineData)), fp)) {
			if ('\0' != szLineData[nLINEDATA_LAST_CHAR] && '\n' != szLineData[nLINEDATA_LAST_CHAR]) SkipLine(fp);
			if (szLineData[0] >= '!' && parseTagsLine(s, szLineData, &n2, nTagFormat)) {
				int cmp;
				if (rule->bTagJumpPartialMatch) {
					if (rule->bTagJumpICase) cmp = stristr_j(s[0], paszKeyword) != nullptr ? 0 : -1;
					else cmp = strstr_j(s[0], paszKeyword) != nullptr ? 0 : -1;
				} else if (rule->bTagJumpExactMatch) {
					cmp = rule->bTagJumpICase ? my_stricmp(s[0], paszKeyword) : strcmp(s[0], paszKeyword);	// 完全一致
				} else {
					cmp = rule->bTagJumpICase ? my_strnicmp(s[0], paszKeyword, length) : strncmp(s[0], paszKeyword, length);	// 前方一致
				}
				if (0 == cmp) {
					state->m_nMatchAll++;
					if (rule->nTop < state->m_nMatchAll) {
						if (m_cList.GetCount() < nCap) {
							m_cList.AddParamA(s[0], s[1], n2, s[2][0], s[3], state->m_nDepth, rule->baseDirId);
						} else {
							m_bNextItem = true;
							break;
						}
					}
				} else if (0 < cmp) {
					// tagsはソートされているので，先頭からのcase sensitiveな比較結果によって検索の時は処理の打ち切りが可能
					if ((!rule->bTagJumpICase) && bSorted && (!rule->bTagJumpPartialMatch)) break;
					// Foldcase時も打ち切る
					if (rule->bTagJumpICase && bFoldcase && (!rule->bTagJumpPartialMatch)) break;
				}
			}
			szLineData[nLINEDATA_LAST_CHAR] = '\0';
		}
	}

	//! タグファイルからキーワードにマッチするデータを抽出する（原版 find_key_core）
	int find_key_core(int nTop, const WCHAR* keyword, bool bTagJumpPartialMatch, bool bTagJumpExactMatch, bool bTagJumpICase,
					  bool bTagJumpICaseByTags, int nDefaultNextMode)
	{
		CNativeA cmemKeyA = CNativeA(to_achar(keyword));
		const ACHAR* paszKeyword = cmemKeyA.GetStringPtr();
		const int length = cmemKeyA.GetStringLength();
		m_cList.Empty();
		m_strOldKeyword = keyword;
		m_bOldTagJumpPartialMatch = bTagJumpPartialMatch;
		m_bOldTagJumpICase = bTagJumpICase;
		m_bNextItem = false;
		if (length == 0) {
			ClearPrevFindInfo();
			return -1;
		}
		// 往復変換してみて一致しなかったら、検索キーには一致しないということにする
		if (0 != wcscmp(to_wchar(paszKeyword), keyword)) {
			ClearPrevFindInfo();
			return -1;
		}
		STagFindState state;
		state.m_nDepth = 0;
		state.m_nMatchAll = 0;
		state.m_nNextMode = nDefaultNextMode;
		state.m_nLoop = -1;
		state.m_bJumpPath = false;	// 親以外のパスの移動先指定
		state.m_szCurPath[0] = 0;
		// 前回の結果から検索対象tagsを絞る
		if (m_sFindPrev.m_nMatchAll <= nTop && -1 < m_sFindPrev.m_nMatchAll) {
			state = m_sFindPrev;	// 指定ページの検索をスキップ
		} else if (0 <= m_sFind0Match.m_nDepth) {
			state = m_sFind0Match;	// depthが浅い順にヒットしなかった分をスキップ
		} else {
			ClearPrevFindInfo();
			// ファイル名をコピーしたあと、ディレクトリ(最後/)のみにする
			wcscpy(state.m_szCurPath, GetFilePath());
			state.m_szCurPath[FileNamePart(GetFilePath()) - GetFilePath()] = LCHAR('\0');
			state.m_nLoop = m_nLoop;
		}
		WCHAR szTagFile[1024];
		WCHAR szNextPath[1024];
		szNextPath[0] = LCHAR('\0');
		vector_ex<sakura::wstring> seachDirs;
		// パスのJumpで循環している場合に最大値を規制する
		for (; state.m_nDepth <= state.m_nLoop && state.m_nDepth < (_MAX_PATH / 2); state.m_nDepth++) {
			// 0 次のファイルは検索しない / 1 1つでもヒットしたら次は検索しない / 2 完全一致のときは1に同じ。それ以外は3に同じ / 3 必ず次も検索
			if (0 == state.m_nNextMode) break;
			if (1 == state.m_nNextMode && 0 < state.m_nMatchAll) break;
			if (2 == state.m_nNextMode && bTagJumpExactMatch && 0 < state.m_nMatchAll) break;
			{
				sakura::wstring curPath = state.m_szCurPath;
				if (seachDirs.exist(curPath)) break;	// 検索済み =>終了
				seachDirs.push_back(curPath);
			}
			auto_sprintf(szTagFile, LTEXT("%s%s"), state.m_szCurPath, TAG_FILENAME_T);
			FILE* fp = _wfopen(szTagFile, LTEXT("rb"));
			if (fp) {
				bool bSorted = true;
				bool bFoldcase = false;
				int nTagFormat = 2;	// 2は1も読めるのでデフォルトは2
				int baseDirId = 0;
				bool bICase = bTagJumpICase;
				if (state.m_bJumpPath) baseDirId = m_cList.AddBaseDir(state.m_szCurPath);
				state.m_nNextMode = nDefaultNextMode;
				if (ReadTagsParameter(fp, bTagJumpICaseByTags, &state, &nTagFormat, &bSorted, &bFoldcase, &bICase, szNextPath, &baseDirId)) {
					STagSearchRule rule{ bTagJumpExactMatch, bTagJumpPartialMatch, bICase, baseDirId, nTop };
					if (bSorted && !bFoldcase && !bICase && (bTagJumpExactMatch && !bTagJumpPartialMatch)) {
						find_key_for_BinarySearch(fp, paszKeyword, nTagFormat, &state, &rule);	//二分探索
					} else {
						find_key_for_LinearSearch(fp, paszKeyword, nTagFormat, &state, &rule, bSorted, bFoldcase, length);
					}
				}
				fclose(fp);
			}
			if (szNextPath[0]) {
				state.m_bJumpPath = true;
				wcscpy(state.m_szCurPath, szNextPath);
				sakura::wstring path = state.m_szCurPath;
				path += LTEXT("/dummy");
				state.m_nLoop = CalcMaxUpDirectory(path.c_str());
				state.m_nDepth = 0;
				szNextPath[0] = 0;
			} else {
				DirUp(state.m_szCurPath);	//カレントパスを1階層上へ。
			}
			if (0 != state.m_nMatchAll && false == m_bNextItem) {
				// ページめくり用: 打ち切られていないので次のページでは、このtagsの次から検索できる
				m_sFindPrev = state;
				++(m_sFindPrev.m_nDepth);
			}
			if (0 == state.m_nMatchAll) {
				// キーワード絞込み用: 次の絞り込み検索では、このtagsの次から検索できる
				m_sFind0Match = state;
				++(m_sFind0Match.m_nDepth);
			}
			if (m_bNextItem) break;
		}
		return state.m_nMatchAll;
	}

	//! 一覧の項目（原版 UpdateData の各列）
	void Collect()
	{
		m_items.clear();
		for (int i = 0; i < m_cList.GetCount(); ++i) {
			const auto* item = m_cList.GetPtr(i);
			if (!item) break;
			TagJumpListItem r;
			r.keyword = Text(item->keyword);
			r.file = Text(item->filename);
			r.line = item->no;
			r.kind = GetNameByType(item->type, item->filename);
			r.note = Text(item->note);
			r.depth = item->depth;
			r.hasBaseDir = item->baseDirId != 0;
			m_items.push_back(std::move(r));
		}
	}

	//! 原版 GetFullPathAndLine
	bool GetFullPathAndLine(int index, sakura::wstring& fullPath, int* lineNum, int* depth)
	{
		WCHAR path[1024];
		WCHAR fileName[1024];
		WCHAR dirFileName[1024];
		int tempDepth = 0;
		int line = 0;
		wcscpy(path, GetFilePath());
		path[FileNamePart(GetFilePath()) - GetFilePath()] = LCHAR('\0');
		cxx::AddLastYenFromDirectoryPath(std::span<WCHAR>(path, std::size(path)));
		if (!m_cList.GetParam(index, nullptr, fileName, &line, nullptr, nullptr, &tempDepth, dirFileName)) return false;
		if (lineNum) *lineNum = line;
		if (depth) *depth = tempDepth;
		const WCHAR* fileNamePath;
		// ファイル名、ディレクトリ指定、基準ファイルパス、の順に適用。途中でフルパスならそのまま。
		if (dirFileName[0]) {
			cxx::AddLastYenFromDirectoryPath(std::span<WCHAR>(dirFileName, std::size(dirFileName)));
			if (fileName[0] == PATH_DELIMITER) wcscpy(dirFileName, fileName);
			else wcscat(dirFileName, fileName);	// 相対パス：連結する
			fileNamePath = dirFileName;
		} else {
			fileNamePath = fileName;
		}
		// 原版 GetFullPathFromDepth
		if (fileNamePath[0] == PATH_DELIMITER) {
			fullPath = fileNamePath;
		} else {
			for (int i = 0; i < tempDepth; i++) DirUp(path);
			fullPath = sakura::wstring(path) + fileNamePath;
		}
		return true;
	}

	//! 得られた候補から最も期待に近いと思われるものを選び出す（原版 SearchBestTag）
	int SearchBestTag()
	{
		if (m_cList.GetCount() <= 0) return -1;
		if (m_strFileName.empty()) return 0;
		int nMatch1 = -1, nMatch2 = -1, nMatch3 = -1, nMatch4 = -1, nMatch5 = -1, nMatch6 = -1, nMatch7 = -1;
		const PathParts src = SplitPath(m_strFileName.c_str());
		auto ieq = [](const sakura::wstring& a, const WCHAR* b) { return _wcsicmp(a.c_str(), b) == 0; };
		for (int i = 0; i < m_cList.GetCount(); i++) {
			sakura::wstring path;
			GetFullPathAndLine(i, path, nullptr, nullptr);
			WCHAR szFileNameDst[_MAX_PATH * 4];
			if (FALSE == GetLongFileName(path.c_str(), szFileNameDst)) wcscpy(szFileNameDst, path.c_str());
			const PathParts dst = SplitPath(szFileNameDst);
			if (_wcsicmp(m_strFileName.c_str(), szFileNameDst) == 0) return i;	//同一ファイルを見つけた
			if (nMatch1 == -1 && ieq(src.dir, dst.dir.c_str()) && ieq(src.file, dst.file.c_str())) nMatch1 = i;	//ファイル名まで一致
			if (nMatch2 == -1 && ieq(src.dir, dst.dir.c_str())) nMatch2 = i;	//パス名まで一致
			if (nMatch5 == -1 && ieq(src.dir, dst.dir.c_str()) && ieq(src.file, dst.file.c_str()) && ieq(src.ext, dst.ext.c_str())) nMatch5 = i;
			const bool tailPath = src.dir.size() >= dst.dir.size() && _wcsicmp(src.dir.c_str() + (src.dir.size() - dst.dir.size()), dst.dir.c_str()) == 0;
			if (nMatch6 == -1 && ieq(src.file, dst.file.c_str()) && ieq(src.ext, dst.ext.c_str()) && tailPath) nMatch6 = i;
			if (nMatch7 == -1 && ieq(src.file, dst.file.c_str()) && tailPath) nMatch7 = i;
			if (nMatch3 == -1 && ieq(src.file, dst.file.c_str()) && ieq(src.ext, dst.ext.c_str())) nMatch3 = i;	//ファイル名・拡張子が一致
			if (nMatch4 == -1 && ieq(src.file, dst.file.c_str())) nMatch4 = i;	//ファイル名が一致
		}
		if (nMatch1 != -1) return nMatch1;
		if (nMatch5 != -1) return nMatch5;
		if (nMatch6 != -1) return nMatch6;
		if (nMatch7 != -1) return nMatch7;
		if (nMatch3 != -1) return nMatch3;
		if (nMatch4 != -1) return nMatch4;
		if (nMatch2 != -1) return nMatch2;
		return 0;
	}
};

TagJumpList::TagJumpList(const Text& baseFilePath, bool direct) : m_impl(std::make_unique<Impl>())
{
	m_impl->m_bDirectTagJump = direct;
	m_impl->m_strFileName = sakura::wstring(baseFilePath);
	m_impl->m_nLoop = CalcMaxUpDirectory(m_impl->m_strFileName.c_str());	// 原版 SetFileName
	m_impl->ClearPrevFindInfo();
}

TagJumpList::~TagJumpList() = default;

std::int32_t TagJumpList::FindDirect(const Text& keyword)
{
	// 原版 FindDirectTagJump：完全一致、大小を区別、tags のソートに従う、共通設定のタグジャンプモード
	auto& d = *m_impl;
	d.m_nTop = 0;
	const int n = d.find_key_core(0, keyword.c_str(), false, true, false, true, GetDllShareData().m_Common.m_sSearch.m_nTagJumpMode);
	d.Collect();
	return n;
}

void TagJumpList::Find(const Text& keyword, bool icase, bool partialMatch, bool newFind)
{
	// 原版 FindNext（キーワード指定。完全一致ではなく前方一致）・find_key
	auto& d = *m_impl;
	if (newFind) {
		// 前回のキーワードからの絞込検索のときで、tagsをスキップできるときはスキップ
		if (-1 < d.m_sFind0Match.m_nDepth
			&& (partialMatch == d.m_bOldTagJumpPartialMatch || !partialMatch)
			&& (icase == d.m_bOldTagJumpICase || !icase)
			&& 0 == keyword.compare(0, d.m_strOldKeyword.size(), d.m_strOldKeyword.c_str())) {
			// 元のキーワードで１件もヒットしないtagsがあるので飛ばす
		} else {
			d.ClearPrevFindInfo();
		}
		d.m_nTop = 0;
	}
	const bool direct = d.m_bDirectTagJump;
	d.find_key_core(d.m_nTop, keyword.c_str(), partialMatch, direct, icase, direct,
					direct ? GetDllShareData().m_Common.m_sSearch.m_nTagJumpMode : GetDllShareData().m_Common.m_sSearch.m_nTagJumpModeKeyword);
	d.Collect();
}

void TagJumpList::NextPage(const Text& keyword, bool icase, bool partialMatch)
{
	m_impl->m_nTop += m_impl->m_cList.GetCapacity();
	Find(keyword, icase, partialMatch, false);
}

void TagJumpList::PrevPage(const Text& keyword, bool icase, bool partialMatch)
{
	m_impl->m_nTop = std::max(0, m_impl->m_nTop - m_impl->m_cList.GetCapacity());
	Find(keyword, icase, partialMatch, false);
}

const std::vector<TagJumpListItem>& TagJumpList::Items() const { return m_impl->m_items; }
std::int32_t TagJumpList::BestIndex() const { return m_impl->SearchBestTag(); }
bool TagJumpList::HasNextPage() const { return m_impl->m_bNextItem; }
bool TagJumpList::HasPrevPage() const { return 0 < m_impl->m_nTop; }
std::int32_t TagJumpList::Capacity() const { return m_impl->m_cList.GetCapacity(); }

std::optional<TagJumpList::Target> TagJumpList::FullPathAndLine(std::int32_t index) const
{
	if (index < 0 || index >= m_impl->m_cList.GetCount()) return std::nullopt;
	sakura::wstring path;
	int line = 0;
	if (!m_impl->GetFullPathAndLine(index, path, &line, nullptr)) return std::nullopt;
	return Target{ Text(path), line };
}

Text TagJumpList::BaseDirectory() const
{
	// 原版 SetTextDir
	const WCHAR* p = m_impl->GetFilePath();
	return Text(p, FileNamePart(p) - p);
}

std::vector<Text> TagJumpKeywordHistory()
{
	std::vector<Text> r;
	CRecentTagjumpKeyword cRecent;
	for (int i = 0; i < cRecent.GetItemCount(); i++) r.emplace_back(cRecent.GetItemText(i));
	cRecent.Terminate();
	return r;
}

void AddTagJumpKeyword(const Text& keyword)
{
	if (keyword.empty()) return;
	CRecentTagjumpKeyword cRecent;
	cRecent.AppendItem(keyword.c_str());
	cRecent.Terminate();
}

} // namespace sakura::core
