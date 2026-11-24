/*! @file
	@brief アウトライン解析的结果的整理（计划第 42 步）

	原版 CDlgFuncList（outline/CDlgFuncList.cpp）把解析结果（CFuncInfoArr）放进 TreeView / ListView，
	同时做「コピー」的文字。这里不用窗口，按同样的步骤做出 OutlineResult：
	- SetTreeJava（C++、Java、COBOL、汎用クラスツリー）：「クラス名::」「\」分出的クラス的项目、グローバル 的项目
	- SetTree（テキスト、HTML、TeX、Python、ルールファイル 等）：按 m_nDepth 的层次
	- SetListVB（Visual Basic）、SetData 的リスト（C、PL/SQL、アセンブラ、Perl、Erlang、ブックマーク）
	- SortTree、SortListView、GetFuncInfoIndex
	ツリー的项目在原版是「デフォルト(降順)」时加在前面（TVI_FIRST），其他加在后面，这里也一样。
*/
/*
	Copyright (C) 2026, Sakura Editor Organization

	SPDX-License-Identifier: Zlib
*/
#include "StdAfx.h"
#include "OutlineView.h"

#include "outline/CFuncInfo.h"
#include "outline/CFuncInfoArr.h"
#include "mem/CNativeW.h"
#include "types/CType.h"
#include "util/string_ex.h"
#include "CSelectLang.h"
#include "sakura_rc.h"

#include <CoreFoundation/CoreFoundation.h>

#include <algorithm>
#include <climits>
#include <functional>
#include <string>

namespace sakura::core {

namespace {

Text Num(int value)
{
	const std::string s = std::to_string(value);
	return Text(s.begin(), s.end());
}

//! auto_sprintf( L"%s(%d,%d): ", path, line, col )
Text TagJumpHead(const Text& path, int line, int column)
{
	return path + u"(" + Num(line) + u"," + Num(column) + u"): ";
}

Text NativeText(const CNativeW& mem)
{
	const WCHAR* p = mem.GetStringPtr();
	return p ? Text(p, mem.GetStringLength()) : Text();
}

//! TreeView 的项目文字（以 NUL 结束）
Text LabelText(const WCHAR* p)
{
	return p ? Text(p) : Text();
}

/*!
	做ツリー用的临时的树。原版 TreeView 的操作（加在前面或后面、找第一个孩子、下一个兄弟）照样做。
*/
struct TreeBuilder {
	struct Node {
		Text label;
		int item = -1;
		int order = 0;
		bool expanded = false;
		std::vector<int> children;
	};
	std::vector<Node> nodes{ Node{} };	// 0 是根（TVI_ROOT）
	bool insertFirst = false;			// hInsertAfter == TVI_FIRST

	int Insert(int parent, Text label, int item, int order)
	{
		Node node;
		node.label = std::move(label);
		node.item = item;
		node.order = order;
		nodes.push_back(std::move(node));
		const int index = int(nodes.size()) - 1;
		auto& children = nodes[parent].children;
		if (insertFirst) {
			children.insert(children.begin(), index);
		} else {
			children.push_back(index);
		}
		return index;
	}

	//! TreeView_GetChild。没有时 -1
	int FirstChild(int node) const
	{
		const auto& children = nodes[node].children;
		return children.empty() ? -1 : children.front();
	}

	//! TreeView_GetNextSibling。parent 是 node 的父项目
	int NextSibling(int parent, int node) const
	{
		const auto& children = nodes[parent].children;
		auto it = std::find(children.begin(), children.end(), node);
		if (it == children.end() || ++it == children.end()) return -1;
		return *it;
	}

	OutlineNode Convert(int index) const
	{
		const Node& node = nodes[index];
		OutlineNode result;
		result.label = node.label;
		result.item = node.item;
		result.order = node.order;
		result.expanded = node.expanded;
		for (int child : node.children) result.children.push_back(Convert(child));
		return result;
	}

	std::vector<OutlineNode> Result() const
	{
		std::vector<OutlineNode> result;
		for (int child : nodes[0].children) result.push_back(Convert(child));
		return result;
	}
};

/* Java/C++メソッドツリーの最大ネスト深さ */
constexpr int MAX_JAVA_TREE_NEST = 32;

//! 原版 SetTreeJava
void SetTreeJava(CFuncInfoArr& arr, TreeBuilder& tree, bool bAddClass, Text& clip)
{
	// 追加文字列の初期化（プラグインで指定済みの場合は上書きしない）
	arr.SetAppendText( FL_OBJ_DECLARE,		LS(STR_DLGFNCLST_APND_DECLARE),	false );
	arr.SetAppendText( FL_OBJ_CLASS,		LS(STR_DLGFNCLST_APND_CLASS),		false );
	arr.SetAppendText( FL_OBJ_STRUCT,		LS(STR_DLGFNCLST_APND_STRUCT),		false );
	arr.SetAppendText( FL_OBJ_ENUM,			LS(STR_DLGFNCLST_APND_ENUM),		false );
	arr.SetAppendText( FL_OBJ_UNION,		LS(STR_DLGFNCLST_APND_UNION),		false );
	arr.SetAppendText( FL_OBJ_NAMESPACE,	LS(STR_DLGFNCLST_APND_NAMESPACE),	false );
	arr.SetAppendText( FL_OBJ_INTERFACE,	LS(STR_DLGFNCLST_APND_INTERFACE),	false );
	arr.SetAppendText( FL_OBJ_GLOBAL,		LS(STR_DLGFNCLST_APND_GLOBAL),		false );

	const Text path = LabelText(arr.m_szFilePath.c_str());
	int htiGlobal = -1;
	int nlParamCount = 0;
	for (int i = 0; i < arr.GetNum(); ++i) {
		const CFuncInfo* pcFuncInfo = arr.GetAt(i);
		const WCHAR* pWork = pcFuncInfo->m_cmemFuncName.GetStringPtr();
		int m = 0;
		std::vector<sakura::wstring> vStrClasses;
		int nClassNest = 0;
		/* クラス名::メソッドの場合 */
		if (nullptr != wcsstr(pWork, LTEXT("::")) && wcsncmp_literal(pWork, LTEXT("operator ")) != 0) {
			/* インナークラスのネストレベルを調べる */
			int nNestTemplate = 0;
			const int nWorkLen = (int)wcslen(pWork);
			for (int k = 0; k < nWorkLen; ++k) {
				if (nClassNest == MAX_JAVA_TREE_NEST) {
					k = nWorkLen;
					break;
				}
				const int nCharChars = int(CNativeW::GetSizeOfChar(pWork, nWorkLen, k));
				if (1 == nCharChars && 0 == nNestTemplate && LCHAR(':') == pWork[k]) {
					if (k < nWorkLen - 1 && LCHAR(':') == pWork[k + 1]) {
						vStrClasses.emplace_back(&pWork[m], k - m);
						++nClassNest;
						m = k + 2;
						++k;
						// Klass::operator std::string
						if (wcsncmp_literal(pWork + m, LTEXT("operator ")) == 0) {
							break;
						}
					} else {
						break;
					}
				} else if (1 == nCharChars && LCHAR('\\') == pWork[k]) {
					vStrClasses.emplace_back(&pWork[m], k - m);
					++nClassNest;
					m = k + 1;
				} else if (1 == nCharChars && LCHAR('<') == pWork[k]) {
					nNestTemplate++;
				} else if (1 == nCharChars && LCHAR('>') == pWork[k]) {
					if (0 < nNestTemplate) {
						nNestTemplate--;
					}
				}
				if (2 == nCharChars) {
					++k;
				}
			}
		}
		int htiClass;
		if (0 < nClassNest) {
			pWork = pWork + m;
			/* クラス名のアイテムが登録されているか */
			int htiParent = 0;
			htiClass = tree.FirstChild(0);	// TreeView_GetFirstVisible
			for (int k = 0; k < nClassNest; ++k) {
				// 既存の項目は「(クラス名)(半角スペース一個)(追加文字列)」となっているとみなし、
				// クラス名が一致すれば親ノードにする（複数あれば最初の項目）
				const size_t nClassNameLen = vStrClasses[k].size();
				for (; htiClass != -1; htiClass = tree.NextSibling(htiParent, htiClass)) {
					const Text& label = tree.nodes[htiClass].label;
					if (0 == wcsncmp(vStrClasses[k].c_str(), label.c_str(), nClassNameLen)) {
						const WCHAR next = nClassNameLen < label.size() ? label[nClassNameLen] : LCHAR('\0');
						if (bAddClass) {
							if (next == LCHAR(' ')) break;
						} else {
							if (next == LCHAR('\0')) break;
						}
					}
				}
				/* クラス名のアイテムが登録されていないので登録 */
				if (htiClass == -1) {
					sakura::wstring strClassName = vStrClasses[k];
					if (bAddClass) {
						if (pcFuncInfo->m_nInfo == FL_OBJ_NAMESPACE) {
							strClassName += arr.GetAppendText(FL_OBJ_NAMESPACE);
						} else {
							strClassName += arr.GetAppendText(FL_OBJ_CLASS);
						}
					}
					htiClass = tree.Insert(htiParent, LabelText(strClassName.c_str()), -1, nlParamCount);
					nlParamCount++;
				}
				htiParent = htiClass;
				htiClass = tree.FirstChild(htiClass);
			}
			htiClass = htiParent;
		} else {
			// Global空間の場合。クラスに類する要素（プラグインで追加された要素も）はルートに置く
			if (FL_OBJ_CLASS <= pcFuncInfo->m_nInfo && pcFuncInfo->m_nInfo <= FL_OBJ_ELEMENT_MAX) {
				htiClass = 0;
			} else {
				if (htiGlobal == -1) {
					htiGlobal = tree.Insert(0, LabelText(arr.GetAppendText(FL_OBJ_GLOBAL).c_str()), -1, nlParamCount);
					nlParamCount++;
				}
				htiClass = htiGlobal;
			}
		}
		sakura::wstring strFuncName = pWork;
		switch (pcFuncInfo->m_nInfo) {
		case FL_OBJ_DEFINITION:		//「定義位置」に追加文字列は不要なため除外
		case FL_OBJ_NAMESPACE:		//「名前空間」は別の場所で処理してるので除外
		case FL_OBJ_GLOBAL:			//「グローバル」は別の場所で処理してるので除外
			break;
		default:
			strFuncName += arr.GetAppendText(pcFuncInfo->m_nInfo);
		}
		/* 該当クラス名のアイテムの子として、メソッドのアイテムを登録 */
		tree.Insert(htiClass, LabelText(strFuncName.c_str()), i, nlParamCount);
		nlParamCount++;

		/* クリップボードにコピーするテキストを編集 */
		clip += TagJumpHead(path, pcFuncInfo->m_nFuncLineCRLF, pcFuncInfo->m_nFuncColCRLF);
		clip += NativeText(pcFuncInfo->m_cmemFuncName);
		if (FL_OBJ_DECLARE == pcFuncInfo->m_nInfo) clip += arr.GetAppendText(FL_OBJ_DECLARE);
		clip += u"\r\n";
	}
	/* ノードの展開をする（第一層） */
	for (int child : tree.nodes[0].children) {
		tree.nodes[child].expanded = true;
	}
}

//! 原版 SetTree：CFuncInfo::m_nDepth で親子を設定
void SetTree(const CFuncInfoArr& arr, TreeBuilder& tree, bool tagjump, Text& clip)
{
	const Text path = LabelText(arr.m_szFilePath.c_str());
	std::vector<int> parentStack(32, 0);	// phParentStack（最初は TVI_ROOT）
	int nStackPointer = 0;
	for (int i = 0; i < arr.GetNum(); i++) {
		const CFuncInfo* pcFuncInfo = arr.GetAt(i);
		/*	親子関係をチェック
			※2段階深くなることは考慮していない（原版）。まだ設定していない段はルートにする
		*/
		if (nStackPointer != pcFuncInfo->m_nDepth) {
			if (int(parentStack.size()) <= pcFuncInfo->m_nDepth + 1) {
				parentStack.resize(pcFuncInfo->m_nDepth + 4, 0);
			}
			nStackPointer = pcFuncInfo->m_nDepth;
		}
		const int hItem = tree.Insert(parentStack[nStackPointer],
			LabelText(pcFuncInfo->m_cmemFuncName.GetStringPtr()), i, i);
		parentStack[nStackPointer + 1] = hItem;

		/* クリップボードコピー用テキストを作成する（dummy要素はツリーに入れるがクリップには加えない） */
		if (pcFuncInfo->IsAddClipText()) {
			Text text;
			if (tagjump) {
				const WCHAR* pszFileName = pcFuncInfo->m_cmemFileName.GetStringPtr();
				text += pszFileName ? Text(pszFileName) : path;
				if (0 < pcFuncInfo->m_nFuncLineCRLF) {
					text += u"(" + Num(pcFuncInfo->m_nFuncLineCRLF) + u"," + Num(pcFuncInfo->m_nFuncColCRLF) + u"): ";
				}
			}
			for (int cnt = 0; cnt < nStackPointer; cnt++) {
				text += u"  ";
			}
			text += u" ";
			text += NativeText(pcFuncInfo->m_cmemFuncName);
			text += u"\r\n";
			clip += text;
		}
	}
}

//! 原版 SetListVB の「備考」
Text RemarkVB(int nInfo0)
{
	Text szOption;
	Text szType;
	if ((nInfo0 >> 8) & 0x01) {
		// スタティック宣言(Static)
		szOption = LS(STR_DLGFNCLST_VB_STATIC);
	}
	// VBアクセス識別子（見つからなかった場合はパブリック）
	switch ((nInfo0 >> 4) & 0x0f) {
	case 2:		szOption += LS(STR_DLGFNCLST_VB_PRIVATE);	break;
	case 3:		szOption += LS(STR_DLGFNCLST_VB_FRIEND);	break;
	default:	szOption += LS(STR_DLGFNCLST_VB_PUBLIC);	break;
	}
	int nInfo = nInfo0;
	switch (nInfo & 0x0f) {
	case 1: szType = LS(STR_DLGFNCLST_VB_FUNCTION);	break;
	case 2: szType = LS(STR_DLGFNCLST_VB_PROC);		break;
	case 3: szType = LS(STR_DLGFNCLST_VB_PROPGET);	break;
	case 4: szType = LS(STR_DLGFNCLST_VB_PROPLET);	break;
	case 5: szType = LS(STR_DLGFNCLST_VB_PROPSET);	break;
	case 6: szType = LS(STR_DLGFNCLST_VB_CONST);	break;
	case 7: szType = LS(STR_DLGFNCLST_VB_ENUM);		break;
	case 8: szType = LS(STR_DLGFNCLST_VB_TYPE);		break;
	case 9: szType = LS(STR_DLGFNCLST_VB_EVENT);	break;
	default:
		// 未定義なのでクリア
		nInfo = 0;
		break;
	}
	if ((nInfo >> 8) & 0x02) {
		// 宣言(Declareなど)
		szType += LS(STR_DLGFNCLST_VB_DECL);
	}
	if (0 == nInfo) {
		return {};
	}
	Text szTypeOption = szType;
	if (!szOption.empty()) {
		szTypeOption += u"（" + szOption + u"）";
	}
	return szTypeOption;
}

//! 原版 SetData のリストの「備考」
Text RemarkList(int nInfo)
{
	switch (nInfo) {
	case 1:		return LS(STR_DLGFNCLST_REMARK01);
	case 10:	return LS(STR_DLGFNCLST_REMARK02);
	case 20:	return LS(STR_DLGFNCLST_REMARK03);
	case 11:	return LS(STR_DLGFNCLST_REMARK04);
	case 21:	return LS(STR_DLGFNCLST_REMARK05);
	case 31:	return LS(STR_DLGFNCLST_REMARK06);
	case 41:	return LS(STR_DLGFNCLST_REMARK07);
	case 50:	return LS(STR_DLGFNCLST_REMARK08);
	case 51:	return LS(STR_DLGFNCLST_REMARK09);
	case 52:	return LS(STR_DLGFNCLST_REMARK10);
	default:	return {};
	}
}

//! 原版 SetListVB / SetData のリスト
void SetList(const CFuncInfoArr& arr, bool vb, bool lineNumIsCRLF, OutlineResult& result)
{
	const Text path = LabelText(arr.m_szFilePath.c_str());
	for (int i = 0; i < arr.GetNum(); ++i) {
		const CFuncInfo* pcFuncInfo = arr.GetAt(i);
		OutlineRow row;
		row.item = i;
		row.line = pcFuncInfo->GetLineNumber(lineNumIsCRLF);
		row.column = pcFuncInfo->GetColumnPosition(lineNumIsCRLF);
		row.name = LabelText(pcFuncInfo->m_cmemFuncName.GetStringPtr());
		row.remark = vb ? RemarkVB(pcFuncInfo->m_nInfo) : RemarkList(pcFuncInfo->m_nInfo);

		/* クリップボードにコピーするテキストを編集 */
		result.clipText += TagJumpHead(path, pcFuncInfo->m_nFuncLineCRLF, pcFuncInfo->m_nFuncColCRLF);
		result.clipText += NativeText(pcFuncInfo->m_cmemFuncName);
		if (!row.remark.empty()) {
			result.clipText += u"(" + row.remark + u")";
		}
		result.clipText += u"\r\n";
		result.rows.push_back(std::move(row));
	}
}

/*!
	lstrcmpi の代わり（Windows の単語の並べ替え：大文字小文字を区別しない言語的な比較。
	ハイフンとアポストロフィは他が同じときだけ比べる）。CoreFoundation の照合（英語）で近似する
*/
int CompareTextIgnoreCase(const Text& a, const Text& b)
{
	auto compare = [](const Text& x, const Text& y) {
		CFStringRef sx = CFStringCreateWithCharacters(nullptr, reinterpret_cast<const UniChar*>(x.data()), CFIndex(x.size()));
		CFStringRef sy = CFStringCreateWithCharacters(nullptr, reinterpret_cast<const UniChar*>(y.data()), CFIndex(y.size()));
		// ユーザーの言語によらない照合（英語：Windows と同じく、ラテン文字・かな・漢字の順）
		CFLocaleRef locale = CFLocaleCreate(nullptr, CFSTR("en"));
		const CFComparisonResult r = CFStringCompareWithOptionsAndLocale(sx, sy, CFRangeMake(0, CFStringGetLength(sx)),
			kCFCompareCaseInsensitive | kCFCompareLocalized, locale);
		CFRelease(locale);
		CFRelease(sy);
		CFRelease(sx);
		return int(r);
	};
	auto strip = [](const Text& s) {
		Text r;
		for (char16_t c : s) {
			if (c != u'-' && c != u'\'') r += c;
		}
		return r;
	};
	const int r = compare(strip(a), strip(b));
	if (r != 0) return r;
	return compare(a, b);
}

void SortChildren(std::vector<OutlineNode>& nodes, OutlineSort sort)
{
	std::function<bool(const OutlineNode&, const OutlineNode&)> less;
	switch (sort) {
	case OutlineSort::Default:
		less = [](const OutlineNode& x, const OutlineNode& y) { return x.order < y.order; };
		break;
	case OutlineSort::DefaultDesc:
		less = [](const OutlineNode& x, const OutlineNode& y) { return y.order < x.order; };
		break;
	case OutlineSort::AtoZ:
		less = [](const OutlineNode& x, const OutlineNode& y) {
			const int r = CompareTextIgnoreCase(x.label, y.label);
			return r != 0 ? r < 0 : x.order < y.order;	// 同じ名前は登録順
		};
		break;
	case OutlineSort::ZtoA:
		less = [](const OutlineNode& x, const OutlineNode& y) {
			const int r = CompareTextIgnoreCase(y.label, x.label);
			return r != 0 ? r < 0 : y.order < x.order;
		};
		break;
	}
	std::stable_sort(nodes.begin(), nodes.end(), less);
	for (auto& node : nodes) SortChildren(node.children, sort);
}

//! 原版 CompareFunc_Asc
int CompareRow(const OutlineResult& result, const OutlineRow& r1, const OutlineRow& r2, int sortCol)
{
	const OutlineItem& f1 = result.items[r1.item];
	const OutlineItem& f2 = result.items[r2.item];
	if (2 == sortCol) {	/* 名前でソート */
		return wmemicmp(f1.name.c_str(), f2.name.c_str());
	}
	if (0 == sortCol) {	/* 行（＋桁）でソート */
		if (f1.line != f2.line) return f1.line < f2.line ? -1 : 1;
		if (f1.column != f2.column) return f1.column < f2.column ? -1 : 1;
		return 0;
	}
	if (1 == sortCol) {	/* 桁でソート */
		if (f1.column != f2.column) return f1.column < f2.column ? -1 : 1;
		return 0;
	}
	if (3 == sortCol) {	/* 備考でソート */
		if (f1.info != f2.info) return f1.info < f2.info ? -1 : 1;
		return 0;
	}
	return -1;
}

bool FindPath(const std::vector<OutlineNode>& nodes, std::int32_t item, std::vector<std::int32_t>& path)
{
	for (size_t i = 0; i < nodes.size(); ++i) {
		path.push_back(std::int32_t(i));
		if (nodes[i].item == item || FindPath(nodes[i].children, item, path)) return true;
		path.pop_back();
	}
	return false;
}

} // namespace

OutlineResult BuildOutlineView(CFuncInfoArr& arr, int nOutlineType, int nListType, const Text& titleOverride,
							   bool lineNumIsCRLF, int sortType, int sortCol, bool sortDesc)
{
	OutlineResult result;
	result.type = OutlineType(nOutlineType);
	result.listType = OutlineType(nListType);
	result.lineNumIsCRLF = lineNumIsCRLF;
	result.filePath = LabelText(arr.m_szFilePath.c_str());
	// SORTTYPE_DEFAULT～SORTTYPE_ZTOA（outline/CDlgFuncList.h）
	result.sort = (0 <= sortType && sortType <= 3) ? OutlineSort(sortType) : OutlineSort::Default;
	result.sortColumn = sortCol;
	result.sortDescending = sortDesc;
	for (int i = 0; i < arr.GetNum(); ++i) {
		const CFuncInfo* p = arr.GetAt(i);
		OutlineItem item;
		item.line = p->m_nFuncLineCRLF;
		item.column = p->m_nFuncColCRLF;
		item.layoutLine = p->m_nFuncLineLAYOUT;
		item.layoutColumn = p->m_nFuncColLAYOUT;
		item.name = NativeText(p->m_cmemFuncName);
		item.fileName = LabelText(p->m_cmemFileName.GetStringPtr());
		item.info = p->m_nInfo;
		item.depth = p->m_nDepth;
		result.items.push_back(std::move(item));
	}

	TreeBuilder tree;
	tree.insertFirst = (result.sort == OutlineSort::DefaultDesc);
	switch (nListType) {
	case OUTLINE_C_CPP:
	case OUTLINE_CPP:
		SetTreeJava(arr, tree, true, result.clipText);
		result.title = LS(STR_DLGFNCLST_TITLE_CPP);
		break;
	case OUTLINE_FILE:
		SetTree(arr, tree, false, result.clipText);
		result.title = LS(STR_DLGFNCLST_TITLE_RULE);
		break;
	case OUTLINE_WZTXT:
		SetTree(arr, tree, false, result.clipText);
		result.title = LS(STR_DLGFNCLST_TITLE_WZ);
		break;
	case OUTLINE_HTML:
		SetTree(arr, tree, false, result.clipText);
		result.title = u"HTML";
		break;
	case OUTLINE_TEX:
		SetTree(arr, tree, false, result.clipText);
		result.title = u"TeX";
		break;
	case OUTLINE_TEXT:
		SetTree(arr, tree, false, result.clipText);
		result.title = LS(STR_DLGFNCLST_TITLE_TEXT);
		break;
	case OUTLINE_JAVA:
		SetTreeJava(arr, tree, true, result.clipText);
		result.title = LS(STR_DLGFNCLST_TITLE_JAVA);
		break;
	case OUTLINE_PYTHON:
		SetTree(arr, tree, true, result.clipText);
		result.title = LS(STR_DLGFNCLST_TITLE_PYTHON);
		break;
	case OUTLINE_COBOL:
		SetTreeJava(arr, tree, false, result.clipText);
		result.title = LS(STR_DLGFNCLST_TITLE_COBOL);
		break;
	case OUTLINE_VB:
		result.isTree = false;
		SetList(arr, true, lineNumIsCRLF, result);
		result.title = LS(STR_DLGFNCLST_TITLE_VB);
		break;
	case OUTLINE_XML:
		SetTree(arr, tree, false, result.clipText);
		result.title = u"XML";
		break;
	case OUTLINE_TREE:
		SetTree(arr, tree, false, result.clipText);
		break;
	case OUTLINE_TREE_TAGJUMP:
		SetTree(arr, tree, true, result.clipText);
		break;
	case OUTLINE_CLSTREE:
		SetTreeJava(arr, tree, true, result.clipText);
		break;
	default:
		result.isTree = false;
		switch (nListType) {
		case OUTLINE_C:			result.title = LS(STR_DLGFNCLST_TITLE_C);		break;
		case OUTLINE_PLSQL:		result.title = LS(STR_DLGFNCLST_TITLE_PLSQL);	break;
		case OUTLINE_ASM:		result.title = LS(STR_DLGFNCLST_TITLE_ASM);		break;
		case OUTLINE_PERL:		result.title = LS(STR_DLGFNCLST_TITLE_PERL);	break;
		case OUTLINE_ERLANG:	result.title = LS(STR_DLGFNCLST_TITLE_ERLANG);	break;
		case OUTLINE_BOOKMARK:	result.title = LS(STR_DLGFNCLST_TITLE_BOOK);	break;
		default:				break;
		}
		SetList(arr, false, lineNumIsCRLF, result);
		break;
	}
	if (!titleOverride.empty()) {
		result.title = titleOverride;
	}

	if (result.isTree) {
		result.tree = tree.Result();
		if (result.sort == OutlineSort::AtoZ || result.sort == OutlineSort::ZtoA) {
			SortOutlineTree(result, result.sort);
		}
	} else {
		SortOutlineRows(result, sortCol, sortDesc);
	}
	return result;
}

void SortOutlineTree(OutlineResult& result, OutlineSort sort)
{
	result.sort = sort;
	SortChildren(result.tree, sort);
}

void SortOutlineRows(OutlineResult& result, std::int32_t column, bool descending)
{
	result.sortColumn = column;
	result.sortDescending = descending;
	const bool bookmark = result.listType == OutlineType::Bookmark;
	result.columnTitles[0] = column == 0 ? LS(STR_DLGFNCLST_LIST_LINE_M) : LS(STR_DLGFNCLST_LIST_LINE);
	result.columnTitles[1] = column == 1 ? LS(STR_DLGFNCLST_LIST_COL_M) : LS(STR_DLGFNCLST_LIST_COL);
	if (bookmark) {
		result.columnTitles[2] = column == 2 ? LS(STR_DLGFNCLST_LIST_TEXT_M) : LS(STR_DLGFNCLST_LIST_TEXT);
	} else {
		result.columnTitles[2] = column == 2 ? LS(STR_DLGFNCLST_LIST_FUNC_M) : LS(STR_DLGFNCLST_LIST_FUNC);
	}
	result.columnTitles[3] = column == 3 ? Text(LS(STR_DLGFNCLST_LIST_M)) : Text();
	// ListView_SortItems（安定なマージソート）
	std::stable_sort(result.rows.begin(), result.rows.end(), [&](const OutlineRow& a, const OutlineRow& b) {
		const int r = CompareRow(result, a, b, column);
		return (descending ? -r : r) < 0;
	});
}

std::int32_t OutlineItemAt(const OutlineResult& result, std::int32_t nCurLine, std::int32_t nCurCol)
{
	// 原版 GetFuncInfoIndex
	int nFuncLineOld = -1;
	int nFuncColOld = -1;
	int nFuncLineTop = INT_MAX;
	int nFuncColTop = INT_MAX;
	int nFoundIndex = -1;
	for (int i = 0; i < int(result.items.size()); ++i) {
		const OutlineItem& f = result.items[i];
		if (!f.fileName.empty() && !result.filePath.empty()) {
			if (0 != wmemicmp(f.fileName.c_str(), result.filePath.c_str())) {
				continue;
			}
		}
		if (nFoundIndex == -1) {
			if (f.layoutLine < nFuncLineTop || (f.layoutLine == nFuncLineTop && f.layoutColumn <= nFuncColTop)) {
				nFuncLineTop = f.layoutLine;
				nFuncColTop = f.layoutColumn;
				nFoundIndex = i;
			}
		} else {
			if ((nFuncLineOld < f.layoutLine || (nFuncLineOld == f.layoutLine && nFuncColOld <= f.layoutColumn))
				&& (f.layoutLine < nCurLine || (f.layoutLine == nCurLine && f.layoutColumn <= nCurCol))) {
				nFuncLineOld = f.layoutLine;
				nFuncColOld = f.layoutColumn;
				nFoundIndex = i;
			}
		}
	}
	return nFoundIndex;
}

std::vector<std::int32_t> OutlineNodePath(const OutlineResult& result, std::int32_t item)
{
	std::vector<std::int32_t> path;
	if (item < 0 || !FindPath(result.tree, item, path)) path.clear();
	return path;
}

} // namespace sakura::core
