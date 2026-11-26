/*! @file
	@brief マクロ（计划第 45 步）

	- 関数表：原版 CSMacroMgr の m_MacroFuncInfoCommandArr・m_MacroFuncInfoArr（sakura_core/macro/CSMacroMgr.cpp をそのまま使う）。
	- キーマクロ（.mac）の読み書き：原版 CKeyMacroMgr::LoadKeyMacro・SaveKeyMacro、CMacro::Save の移植。
	- マクロのファイルの読み込み：原版 CTextInputStream（BOM 付き UTF-8 か Shift_JIS）。
	  Mac 版は BOM がなくても全体が UTF-8 として正しければ UTF-8 として読む。
	- JScript の前処理：原版の Editor オブジェクトは括弧なしの参照でも実行される（IDispatch の PROPERTYGET）。
	  JavaScriptCore ではそうならないので、命令・関数の名前の後ろに「()」を足す。

	マクロの命令・関数の処理（原版 CMacro::HandleCommand・HandleFunction）は界面層（Swift）が行う。
*/
/*
	Copyright (C) 2026, Sakura Editor Organization

	SPDX-License-Identifier: Zlib
*/
#include "StdAfx.h"
#include "sakura_core/SakuraCore.h"

#include <algorithm>
#include <cstdio>
#include <set>
#include <string>
#include <string_view>
#include <vector>

#include "Funccode_enum.h"
#include "macro/CSMacroMgr.h"
#include "io/CTextStream.h"
#include "mem/CNativeW.h"
#include "util/format.h"
#include "util/tchar_convert.h"
#include "CSelectLang.h"
#include "util/string_ex.h"
#include "charset/charcode.h"
#include "sakura_rc.h"

namespace sakura::core {

namespace {

MacroValueType ToValueType(VARTYPE vt)
{
	switch (vt) {
	case VT_I4: return MacroValueType::Int;
	case VT_BSTR: return MacroValueType::String;
	default: return MacroValueType::None;
	}
}

MacroFunctionInfo ToInfo(const MacroFuncInfo& f, bool isFunction)
{
	MacroFunctionInfo info;
	info.code = f.m_nFuncID;
	info.name = Text(f.m_pszFuncName);
	for (VARTYPE vt : f.m_varArguments) {
		if (vt == VT_EMPTY) break;
		info.args.push_back(ToValueType(vt));
	}
	info.result = ToValueType(f.m_varResult);
	info.isFunction = isFunction;
	return info;
}

//! 大文字小文字を区別しない比較（ASCII。原版 _wcsicmp）
bool EqualsIgnoreCase(const Text& a, const Text& b)
{
	if (a.size() != b.size()) return false;
	for (size_t i = 0; i < a.size(); ++i) {
		char16_t x = a[i], y = b[i];
		if (u'A' <= x && x <= u'Z') x = char16_t(x - u'A' + u'a');
		if (u'A' <= y && y <= u'Z') y = char16_t(y - u'A' + u'a');
		if (x != y) return false;
	}
	return true;
}

Text Format(const WCHAR* format, auto... args)
{
	WCHAR buf[2048] = {};
	auto_sprintf_s(buf, std::size(buf), format, args...);
	return Text(buf);
}

//! メッセージボックスに出す文字（rc の文字列は改行が CR LF のことがある）
Text ToMessage(Text s)
{
	for (size_t i = 0; (i = s.find(u"\r\n", i)) != Text::npos;) s.erase(i, 1);
	return s;
}

//! 全体が UTF-8 として正しいか（BOM なしのマクロのファイル。Mac 版の追加）
bool IsValidUtf8(std::string_view bytes)
{
	size_t i = 0;
	while (i < bytes.size()) {
		const auto c = static_cast<unsigned char>(bytes[i]);
		int n;
		char32_t cp;
		if (c < 0x80) { ++i; continue; }
		else if ((c & 0xE0) == 0xC0) { n = 1; cp = c & 0x1F; if (c < 0xC2) return false; }
		else if ((c & 0xF0) == 0xE0) { n = 2; cp = c & 0x0F; }
		else if ((c & 0xF8) == 0xF0) { n = 3; cp = c & 0x07; if (c > 0xF4) return false; }
		else return false;
		if (i + n >= bytes.size()) return false;
		for (int k = 1; k <= n; ++k) {
			const auto cc = static_cast<unsigned char>(bytes[i + k]);
			if ((cc & 0xC0) != 0x80) return false;
			cp = (cp << 6) | (cc & 0x3F);
		}
		if ((n == 2 && cp < 0x800) || (n == 3 && (cp < 0x10000 || cp > 0x10FFFF)) || (0xD800 <= cp && cp <= 0xDFFF)) return false;
		i += n + 1;
	}
	return true;
}

/*!
	マクロのファイルを行に分けて読む（原版 CTextInputStream::ReadLineW と同じ：CR LF、LF、CR で区切り、改行は削る）。
	@retval Failure 開けない。EncodingError 文字コードの変換に失敗（原版 CError_TextEncoding）
*/
MacroLoadResult ReadMacroLines(const Text& path, std::vector<Text>& lines)
{
	lines.clear();
	FILE* fp = _wfopen(path.c_str(), LTEXT("rb"));
	if (!fp) return MacroLoadResult::Failure;
	std::string bytes;
	char buf[8192];
	for (size_t n; (n = fread(buf, 1, sizeof(buf), fp)) > 0;) bytes.append(buf, n);
	fclose(fp);

	bool utf8 = false;
	std::string_view body = bytes;
	if (body.size() >= 3 && static_cast<unsigned char>(body[0]) == 0xEF && static_cast<unsigned char>(body[1]) == 0xBB
		&& static_cast<unsigned char>(body[2]) == 0xBF) {
		utf8 = true;
		body.remove_prefix(3);
	}
	else {
		// Mac 版：BOM がなくても UTF-8 として正しければ UTF-8（ASCII だけのときはどちらでも同じ）
		utf8 = IsValidUtf8(body);
	}
	const auto codePage = utf8 ? CP_UTF8 : CP_SJIS;

	size_t start = 0;
	auto flush = [&](size_t end) -> bool {
		sakura::wstring line;
		try {
			cxx::MultiByteToWideChar(codePage, body.substr(start, end - start), line);
		}
		catch (const std::invalid_argument&) {
			return false;
		}
		lines.emplace_back(line.c_str(), line.size());
		return true;
	};
	for (size_t i = 0; i < body.size(); ++i) {
		const char c = body[i];
		if (c != '\r' && c != '\n') continue;
		if (!flush(i)) return MacroLoadResult::EncodingError;
		if (c == '\r' && i + 1 < body.size() && body[i + 1] == '\n') ++i;
		start = i + 1;
	}
	// 最後の行（原版は EOF の行も一行として読む。空なら空行）
	if (!flush(body.size())) return MacroLoadResult::EncodingError;
	return MacroLoadResult::Success;
}

} // namespace

// ----- 関数表 -----

const std::vector<MacroFunctionInfo>& MacroFunctions()
{
	static const std::vector<MacroFunctionInfo> table = [] {
		std::vector<MacroFunctionInfo> v;
		for (const auto& f : CSMacroMgr::GetCommandInfo()) v.push_back(ToInfo(f, false));
		for (const auto& f : CSMacroMgr::GetFuncInfo()) v.push_back(ToInfo(f, true));
		return v;
	}();
	return table;
}

const MacroFunctionInfo* FindMacroFunction(const Text& name)
{
	// CSMacroMgr::GetFuncInfoByName：S_ を取る。関数（値を返す）を先に、命令を後に。完全一致
	Text n = name;
	if (n.size() >= 2 && n[0] == u'S' && n[1] == u'_') n.erase(0, 2);
	const auto& table = MacroFunctions();
	for (const auto& f : table) {
		if (f.isFunction && f.name == n) return &f;
	}
	for (const auto& f : table) {
		if (!f.isFunction && f.name == n) return &f;
	}
	return nullptr;
}

const MacroFunctionInfo* FindMacroFunctionIgnoreCase(const Text& name)
{
	// CIfObj::GetIDsOfNames：登録順（命令、関数）に _wcsicmp。S_ は付けない
	for (const auto& f : MacroFunctions()) {
		if (EqualsIgnoreCase(f.name, name)) return &f;
	}
	return nullptr;
}

const MacroFunctionInfo* MacroFunctionByCode(std::int32_t code)
{
	if (code <= 0) return nullptr;
	const auto& table = MacroFunctions();
	for (const auto& f : table) {
		if (!f.isFunction && f.code == code) return &f;
	}
	for (const auto& f : table) {
		if (f.isFunction && f.code == code) return &f;
	}
	return nullptr;
}

Text MacroFunctionDisplayName(std::int32_t code)
{
	return Text(LS(code));
}

bool CanRecordInKeyMacro(std::int32_t code)
{
	return CSMacroMgr::CanFuncIsKeyMacro(code) != FALSE;
}

MacroArg MacroArg::Int(std::int32_t n)
{
	// CMacroParam::SetIntParam（_itow）
	WCHAR buf[16] = {};
	_itow(n, buf, 10);
	return MacroArg{ false, Text(buf) };
}

std::int32_t MacroArg::IntValue() const
{
	return _wtoi(text.c_str());
}

// ----- キーマクロの読み込み（原版 CKeyMacroMgr::LoadKeyMacro） -----

namespace {

//! LoadKeyMacro の一行の文字列の引数の展開（エスケープ）
Text UnescapeKeyMacroString(const Text& raw)
{
	CNativeW cmemWork;
	cmemWork.SetString(raw.c_str(), raw.size());
	// 2014.01.28 「"\\'"」のような場合の不具合を修正
	cmemWork.Replace(LTEXT("\\\\"), LTEXT("\\\1"));	// 一時置換(最初に必要)
	cmemWork.Replace(LTEXT("\\\'"), LTEXT("\'"));
	cmemWork.Replace(LTEXT("\\\""), LTEXT("\""));
	cmemWork.Replace(LTEXT("\\r"), LTEXT("\r"));
	cmemWork.Replace(LTEXT("\\n"), LTEXT("\n"));
	cmemWork.Replace(LTEXT("\\t"), LTEXT("\t"));
	{
		// \uXXXX 置換
		size_t nLen = cmemWork.GetStringLength();
		size_t nBegin = 0;
		const WCHAR* p = cmemWork.GetStringPtr();
		CNativeW cmemTemp;
		for (size_t n = 0; n < nLen; n++) {
			if (n + 1 < nLen && p[n] == LCHAR('\\') && p[n + 1] == LCHAR('u')) {
				size_t k;
				for (k = n + 2; k < nLen && k < n + 2 + 4
					&& (WCODE::Is09(p[k])
						|| (LCHAR('a') <= p[k] && p[k] <= LCHAR('f'))
						|| (LCHAR('A') <= p[k] && p[k] <= LCHAR('F'))); k++) {
				}
				cmemTemp.AppendString(p + nBegin, n - nBegin);
				nBegin = k;
				if (0 < k - n - 2) {
					WCHAR hex[5];
					wcsncpy(hex, &p[n + 2], k - n - 2);
					hex[k - n - 2] = LCHAR('\0');
					WCHAR* pEnd = nullptr;
					WCHAR c = static_cast<WCHAR>(wcstol(hex, &pEnd, 16));
					cmemTemp.AppendString(&c, 1);
				}
				n = k - 1;
			}
		}
		if (nBegin != 0) {
			if (0 < nLen - nBegin) {
				cmemTemp.AppendString(p + nBegin, nLen - nBegin);
			}
			cmemWork.swap(cmemTemp);
		}
	}
	cmemWork.Replace(LTEXT("\\\1"), LTEXT("\\"));	// 一時置換を\に戻す(最後でないといけない)
	return Text(cmemWork.GetStringPtr(), cmemWork.GetStringLength());
}

KeyMacroParseResult ParseKeyMacroLines(const std::vector<Text>& lines)
{
	KeyMacroParseResult r;
	r.errorTitle = Text(LS(STR_ERR_DLGKEYMACMGR2));
	auto fail = [&](Text message) {
		if (r.result == MacroLoadResult::Success) r.errorMessage = ToMessage(std::move(message));
		r.result = MacroLoadResult::Failure;
	};

	int line = 0;	//	エラー時に行番号を通知するため．1始まり．
	for (const Text& strLine : lines) {
		++line;
		const auto nLineLen = int(strLine.length());
		// szLine[i]：行末より後ろは '\0'（原版は c_str() の終端を読む）
		auto at = [&](int i) -> WCHAR { return (0 <= i && i < nLineLen) ? strLine[i] : LCHAR('\0'); };
		int i;
		// 先行する空白をスキップ
		for (i = 0; i < nLineLen; ++i) {
			if (strLine[i] != WCODE::SPACE && strLine[i] != WCODE::TAB) break;
		}
		int nBgn = i;
		//	Jun. 16, 2002 genta 空行を無視する
		if (nBgn == nLineLen || at(nBgn) == LCHAR('\0')) continue;
		// コメント行の検出
		if (at(nBgn) == LCHAR('/') && nBgn + 1 < nLineLen && at(nBgn + 1) == LCHAR('/')) continue;

		// 関数名の取得
		Text szFuncName;
		for (; i < nLineLen; ++i) {
			if (at(i) == LCHAR('(') && (i - nBgn) < 100) {
				szFuncName = strLine.substr(nBgn, i - nBgn);
				++i;
				nBgn = i;
				break;
			}
		}
		const MacroFunctionInfo* mInfo = FindMacroFunction(szFuncName);
		if (!mInfo) {
			fail(Format(LS(STR_ERR_DLGKEYMACMGR8), line, szFuncName.c_str()));
			break;
		}
		MacroCall macro;
		macro.code = mInfo->code;
		// プロトタイプチェックは原版 GetFuncInfoByID（命令を先に）の表で
		const MacroFunctionInfo* proto = MacroFunctionByCode(mInfo->code);
		const auto nArgSizeMax = 8;	// MacroFuncInfo::MaxArgs
		bool ok = true;
		for (int nArgs = 0; at(i); ++nArgs) {
			if (nArgs >= nArgSizeMax) {
				fail(Format(LS(STR_ERR_DLGKEYMACMGR3), line, i + 1));
				ok = false;
				break;
			}
			const MacroValueType type = (proto && nArgs < int(proto->args.size())) ? proto->args[nArgs] : MacroValueType::None;

			//	Skip Space
			while (at(i) == LCHAR(' ') || at(i) == LCHAR('\t')) i++;

			if (LCHAR('\'') == at(i) || LCHAR('\"') == at(i)) {	//	'で始まったら文字列だよきっと。
				if (type != MacroValueType::String && type != MacroValueType::None) {
					fail(Format(LS(STR_ERR_DLGKEYMACMGR4), line, i + 1, szFuncName.c_str(), nArgs + 1));
					ok = false;
					break;
				}
				const WCHAR cQuote = at(i);
				++i;
				int nEnd = i;
				nBgn = i;	//	nBgnは引数の先頭の文字
				for (; i <= nLineLen; ++i) {		//	最後の文字+1までスキャン
					if (at(i) == LCHAR('\\')) {	// エスケープのスキップ
						++i;
						continue;
					}
					if (at(i) == cQuote) {	//	始まりと同じquotationで終了。
						nEnd = i;
						break;
					}
					if (i == nLineLen) {	//	行末に来てしまった
						fail(Format(LS(STR_ERR_DLGKEYMACMGR5), line, szFuncName.c_str(), nArgs + 1, cQuote));
						ok = false;
						nEnd = i - 1;
						break;
					}
				}
				if (!ok) break;
				macro.args.push_back(MacroArg::String(UnescapeKeyMacroString(strLine.substr(nBgn, std::max(0, nEnd - nBgn)))));
			}
			else if (WCODE::Is09(at(i)) || at(i) == LCHAR('-')) {	//	数字で始まったら数字列だ(-記号も含む)。
				if (type != MacroValueType::Int && type != MacroValueType::None) {
					fail(Format(LS(STR_ERR_DLGKEYMACMGR6), line, i + 1, szFuncName.c_str(), nArgs + 1));
					ok = false;
					break;
				}
				nBgn = i;
				int nEnd = i;
				for (i = nBgn + 1; i <= nLineLen; ++i) {		//	最後の文字+1までスキャン
					if (WCODE::Is09(at(i))) continue;
					nEnd = i;	//	数字の最後の文字
					i--;
					break;
				}
				macro.args.push_back(MacroArg::Int(_wtoi(strLine.substr(nBgn, nEnd - nBgn).c_str())));
			}
			else if (at(i) == LCHAR(')')) {
				//	引数無し
				break;
			}
			else {
				//	Parse Error:文法エラーっぽい。
				fail(Format(LS(STR_ERR_DLGKEYMACMGR7), line, i + 1));
				ok = false;
				break;
			}

			for (; i < nLineLen; ++i) {		//	最後の文字までスキャン
				if (at(i) == LCHAR(')') || at(i) == LCHAR(',')) {	//	,もしくは)を読み飛ばす
					i++;
					break;
				}
			}
			if (at(i - 1) == LCHAR(')')) break;
		}
		if (!ok) break;
		r.calls.push_back(std::move(macro));
	}
	return r;
}

} // namespace

KeyMacroParseResult ParseKeyMacro(const Text& source)
{
	// CTextInputStream と同じに行に分ける
	std::vector<Text> lines;
	size_t start = 0;
	for (size_t i = 0; i < source.size(); ++i) {
		const char16_t c = source[i];
		if (c != u'\r' && c != u'\n') continue;
		lines.push_back(source.substr(start, i - start));
		if (c == u'\r' && i + 1 < source.size() && source[i + 1] == u'\n') ++i;
		start = i + 1;
	}
	lines.push_back(source.substr(start));
	return ParseKeyMacroLines(lines);
}

KeyMacroParseResult LoadKeyMacroFile(const Text& path)
{
	std::vector<Text> lines;
	const auto read = ReadMacroLines(path, lines);
	if (read != MacroLoadResult::Success) {
		KeyMacroParseResult r;
		r.result = read;
		return r;
	}
	return ParseKeyMacroLines(lines);
}

// ----- キーマクロの保存（原版 CKeyMacroMgr::SaveKeyMacro、CMacro::Save） -----

Text FormatKeyMacro(const std::vector<MacroCall>& calls)
{
	Text out(LS(STR_ERR_DLGKEYMACMGR1));
	for (const auto& call : calls) {
		const MacroFunctionInfo* info = MacroFunctionByCode(call.code);
		if (!info) {
			out += LS(STR_ERR_DLGMACRO01);
			continue;
		}
		out += info->name;
		out += u"(";
		bool first = true;
		for (const auto& arg : call.args) {
			if (!first) out += u", ";
			first = false;
			if (!arg.isString) {
				out += arg.text;
				continue;
			}
			CNativeW cmemWork;
			cmemWork.SetString(arg.text.c_str(), arg.text.size());
			cmemWork.Replace(LTEXT("\\"), LTEXT("\\\\"));
			cmemWork.Replace(LTEXT("\'"), LTEXT("\\\'"));
			cmemWork.Replace(LTEXT("\r"), LTEXT("\\r"));
			cmemWork.Replace(LTEXT("\n"), LTEXT("\\n"));
			cmemWork.Replace(LTEXT("\t"), LTEXT("\\t"));
			cmemWork.Replace(LTEXT("\0"), 1, LTEXT("\\u0000"), 6);
			cmemWork.Replace(LTEXT("\u0085"), LTEXT("\\u0085"));
			cmemWork.Replace(LTEXT(" "), LTEXT("\\u2028"));
			cmemWork.Replace(LTEXT(" "), LTEXT("\\u2029"));
			for (int c = 1; c < 0x20; c++) {
				int nLen = cmemWork.GetStringLength();
				const WCHAR* p = cmemWork.GetStringPtr();
				for (int i = 0; i < nLen; i++) {
					if (p[i] == c) {
						WCHAR from[2];
						WCHAR to[7];
						from[0] = WCHAR(c);
						from[1] = LCHAR('\0');
						auto_sprintf(to, LTEXT("\\u%04x"), c);
						cmemWork.Replace(from, to);
						break;
					}
				}
			}
			cmemWork.Replace(LTEXT("\u007f"), LTEXT("\\u007f"));
			out += u"'";
			out.append(cmemWork.GetStringPtr(), cmemWork.GetStringLength());
			out += u"'";
		}
		out += u");\t// ";
		out += MacroFunctionDisplayName(call.code);
		out += u"\r\n";
	}
	return out;
}

bool SaveKeyMacroFile(const Text& path, const std::vector<MacroCall>& calls)
{
	CTextOutputStream out(path.c_str());
	if (!out) return false;
	const Text text = FormatKeyMacro(calls);
	out.WriteString(text.c_str(), int(text.size()));
	out.Close();
	return true;
}

MacroSourceResult LoadMacroSourceFile(const Text& path)
{
	MacroSourceResult r;
	std::vector<Text> lines;
	r.result = ReadMacroLines(path, lines);
	if (r.result != MacroLoadResult::Success) return r;
	// CWSHMacroManager::LoadKeyMacro：while(in){ m_Source += ReadLineW() + "\r\n"; }
	for (const auto& line : lines) {
		r.source += line;
		r.source += u"\r\n";
	}
	return r;
}

// ----- マクロの種類 -----

MacroKind MacroKindOfExtension(const Text& ext)
{
	Text e;
	for (char16_t c : ext) e.push_back((u'A' <= c && c <= u'Z') ? char16_t(c - u'A' + u'a') : c);
	if (e == u"mac") return MacroKind::Key;
	if (e == u"js") return MacroKind::JScript;
	// 原版：PPA.DLL（.ppa）、Windows Script Host に登録されたエンジン（.vbs .vbe .jse .wsf、PerlScript .pls など）、Python（.py）
	static const Text unsupported[] = { u"ppa", u"vbs", u"vbe", u"jse", u"wsf", u"wsc", u"pls", u"py" };
	for (const auto& u : unsupported) {
		if (e == u) return MacroKind::Unsupported;
	}
	return MacroKind::Unknown;
}

MacroKind MacroKindOfPath(const Text& path)
{
	// CSMacroMgr::Load：最後の「.」の後ろ。そのあとにパスの区切りがあれば拡張子なし
	const auto dot = path.rfind(u'.');
	if (dot == Text::npos) return MacroKind::Unknown;
	const Text ext = path.substr(dot + 1);
	if (ext.find(u'/') != Text::npos || ext.find(u'\\') != Text::npos) return MacroKind::Unknown;
	return MacroKindOfExtension(ext);
}

std::int32_t CompareVersionString(const Text& verA, const Text& verB)
{
	return CompareVersion(verA.c_str(), verB.c_str());
}

// ----- JScript の前処理 -----

namespace {

bool IsIdentStart(char16_t c)
{
	return (u'a' <= c && c <= u'z') || (u'A' <= c && c <= u'Z') || c == u'_' || c == u'$' || c >= 0x80;
}
bool IsIdentPart(char16_t c)
{
	return IsIdentStart(c) || (u'0' <= c && c <= u'9');
}

//! 字句（前処理に要るだけ）
struct Token {
	enum Kind { Ident, Number, String, Regex, Punct, Template } kind;
	size_t begin, end;
	bool newlineBefore = false;
};

//! この字句の後ろの「/」は正規表現の始まりか（割り算でなく）
bool RegexAllowedAfter(const Text& src, const std::vector<Token>& toks)
{
	if (toks.empty()) return true;
	const Token& t = toks.back();
	const Text s = src.substr(t.begin, t.end - t.begin);
	switch (t.kind) {
	case Token::Number: case Token::String: case Token::Regex: case Token::Template:
		return false;
	case Token::Ident: {
		static const Text keywords[] = { u"return", u"typeof", u"instanceof", u"in", u"of", u"new", u"delete",
			u"void", u"throw", u"case", u"do", u"else", u"yield", u"await" };
		for (const auto& k : keywords) {
			if (s == k) return true;
		}
		return false;
	}
	case Token::Punct:
		return !(s == u")" || s == u"]" || s == u"}" || s == u"++" || s == u"--");
	}
	return true;
}

std::vector<Token> Tokenize(const Text& src)
{
	std::vector<Token> toks;
	const size_t n = src.size();
	size_t i = 0;
	bool newline = false;
	while (i < n) {
		const char16_t c = src[i];
		if (c == u'\n' || c == u'\r' || c == 0x2028 || c == 0x2029) { newline = true; ++i; continue; }
		if (c == u' ' || c == u'\t' || c == u'\v' || c == u'\f' || c == 0xA0 || c == 0xFEFF || c == 0x3000) { ++i; continue; }
		// コメント
		if (c == u'/' && i + 1 < n && src[i + 1] == u'/') {
			while (i < n && src[i] != u'\n' && src[i] != u'\r') ++i;
			continue;
		}
		if (c == u'/' && i + 1 < n && src[i + 1] == u'*') {
			const auto e = src.find(u"*/", i + 2);
			const size_t end = (e == Text::npos) ? n : e + 2;
			if (src.find_first_of(u"\r\n", i) < end) newline = true;
			i = end;
			continue;
		}
		Token t{ Token::Punct, i, i, newline };
		newline = false;
		if (IsIdentStart(c)) {
			size_t j = i + 1;
			while (j < n && IsIdentPart(src[j])) ++j;
			t.kind = Token::Ident;
			t.end = j;
		}
		else if ((u'0' <= c && c <= u'9') || (c == u'.' && i + 1 < n && u'0' <= src[i + 1] && src[i + 1] <= u'9')) {
			size_t j = i + 1;
			while (j < n && (IsIdentPart(src[j]) || src[j] == u'.'
				|| ((src[j] == u'+' || src[j] == u'-') && (src[j - 1] == u'e' || src[j - 1] == u'E')))) ++j;
			t.kind = Token::Number;
			t.end = j;
		}
		else if (c == u'\'' || c == u'"') {
			size_t j = i + 1;
			while (j < n && src[j] != c && src[j] != u'\n' && src[j] != u'\r') {
				if (src[j] == u'\\') ++j;
				++j;
			}
			t.kind = Token::String;
			t.end = std::min(n, j + 1);
		}
		else if (c == u'`') {
			// テンプレート文字列（${} の中は簡単に括弧の数で飛ばす）
			size_t j = i + 1;
			int depth = 0;
			while (j < n) {
				if (src[j] == u'\\') { j += 2; continue; }
				if (depth == 0 && src[j] == u'`') break;
				if (src[j] == u'$' && j + 1 < n && src[j + 1] == u'{') { ++depth; j += 2; continue; }
				if (depth > 0 && src[j] == u'}') --depth;
				++j;
			}
			t.kind = Token::Template;
			t.end = std::min(n, j + 1);
		}
		else if (c == u'/' && RegexAllowedAfter(src, toks)) {
			size_t j = i + 1;
			bool inClass = false;
			while (j < n && src[j] != u'\n' && src[j] != u'\r') {
				if (src[j] == u'\\') { j += 2; continue; }
				if (src[j] == u'[') inClass = true;
				else if (src[j] == u']') inClass = false;
				else if (src[j] == u'/' && !inClass) break;
				++j;
			}
			++j;	// 閉じの /
			while (j < n && IsIdentPart(src[j])) ++j;	// フラグ
			t.kind = Token::Regex;
			t.end = std::min(n, j);
		}
		else {
			// 記号：ここで要るのは一文字か「++」「--」かの区別だけ
			size_t j = i + 1;
			if ((c == u'+' || c == u'-') && j < n && src[j] == c) ++j;
			t.kind = Token::Punct;
			t.end = j;
		}
		toks.push_back(t);
		i = t.end;
	}
	return toks;
}

} // namespace

Text PrepareJScriptMacro(const Text& src)
{
	const std::vector<Token> toks = Tokenize(src);
	auto text = [&](const Token& t) { return src.substr(t.begin, t.end - t.begin); };
	auto isPunct = [&](size_t k, const char16_t* p) { return k < toks.size() && toks[k].kind == Token::Punct && text(toks[k]) == p; };
	auto isIdent = [&](size_t k, const char16_t* p) { return k < toks.size() && toks[k].kind == Token::Ident && text(toks[k]) == p; };

	// スクリプトで宣言した名前（var・let・const の後ろと「,」の後ろ、function の名前と引数、catch の引数）
	std::set<Text> declared;
	for (size_t k = 0; k < toks.size(); ++k) {
		if (toks[k].kind != Token::Ident) continue;
		const Text s = text(toks[k]);
		if (s == u"var" || s == u"let" || s == u"const") {
			int depth = 0;
			bool expectName = true;
			for (size_t m = k + 1; m < toks.size(); ++m) {
				const Token& t = toks[m];
				if (t.kind == Token::Punct) {
					const Text p = text(t);
					if (p == u"(" || p == u"[" || p == u"{") ++depth;
					else if (p == u")" || p == u"]" || p == u"}") { if (--depth < 0) break; }
					else if (depth == 0 && p == u";") break;
					else if (depth == 0 && p == u",") { expectName = true; continue; }
				}
				else if (t.kind == Token::Ident && depth == 0 && expectName) {
					declared.insert(text(t));
				}
				expectName = false;
			}
		}
		else if (s == u"function") {
			size_t m = k + 1;
			if (m < toks.size() && toks[m].kind == Token::Ident) declared.insert(text(toks[m++]));
			if (isPunct(m, u"(")) {
				for (++m; m < toks.size() && !isPunct(m, u")"); ++m) {
					if (toks[m].kind == Token::Ident) declared.insert(text(toks[m]));
				}
			}
		}
		else if (s == u"catch" && isPunct(k + 1, u"(") && k + 2 < toks.size() && toks[k + 2].kind == Token::Ident) {
			declared.insert(text(toks[k + 2]));
		}
	}

	std::set<Text> names;
	for (const auto& f : MacroFunctions()) names.insert(f.name);

	Text out;
	out.reserve(src.size() + 64);
	size_t copied = 0;
	for (size_t k = 0; k < toks.size(); ++k) {
		const Token& t = toks[k];
		if (t.kind != Token::Ident) continue;
		const Text s = text(t);
		if (!names.count(s) || declared.count(s)) continue;
		// 「.」の後ろはほかのオブジェクトのメンバー（Editor. は原版の Editor オブジェクト）
		if (k >= 1 && isPunct(k - 1, u".")) {
			if (!(k >= 2 && isIdent(k - 2, u"Editor"))) continue;
		}
		// すでに呼び出し
		if (isPunct(k + 1, u"(")) continue;
		// 代入・オブジェクトのキーなどは変えない（「GetFilename = 1」「{ GetFilename: 1 }」）
		if (isPunct(k + 1, u"=") && !(k + 2 < toks.size() && isPunct(k + 2, u"="))) continue;
		out.append(src, copied, t.end - copied);
		out += u"()";
		copied = t.end;
	}
	out.append(src, copied, Text::npos);
	return out;
}

} // namespace sakura::core
