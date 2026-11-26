/*! @file
	@brief 行単位の差分（计划第 44 步：DIFF差分表示、原版は GNU diffutils の diff.exe を呼ぶ）

	原版の DIFF差分表示 は diff.exe（GNU diffutils、GPL）の通常形式の出力（「99,99c99,99」）を読んで行に印を付ける。
	Mac 版は GPL のプログラムを附带しないので、ここで差分を計算して同じ形式の結果を作る（zlib 许可证，独自の実装）。

	- 行の比較：-i（英大文字小文字を同一視、ASCII）、-w（空白を無視）、-b（空白の量の変化を無視、行末の空白も）。
	  -t（TAB を空白に）は出力だけの選択肢なので結果は変わらない。
	- 行の区切りは LF だけ（Windows 版の diff はテキストモードで読むので CR LF の CR は行に含まれない）。
	  最後の行に改行がないときは、改行がある同じ内容の行と違う行として扱う（diff と同じ）。
	- 最短の編集（Myers の O(ND) アルゴリズム、中央のスネークで分割）を求めたあと、変更の塊を上下にずらして
	  同じ内容の行の並びのどこに置くかを決める：一番下、ただし相手のファイルの変更と同じ所に置けるならそこ
	  （diff の出力と同じ位置になるように）。
	- -B（空行の変更を無視）：変更した行がすべて空の塊は出さない。
	- 差分が非常に大きいとき（編集の数が上限を超えたとき）は、最短でなくても途中で分割する（diff と同じ考え方）。
*/
/*
	Copyright (C) 2026, Sakura Editor Organization

	SPDX-License-Identifier: Zlib
*/
#include "sakura_core/SakuraCore.h"

#include <algorithm>
#include <cstdint>
#include <string>
#include <unordered_map>
#include <vector>

namespace sakura::core {

namespace {

bool IsAsciiSpace(char16_t c) { return c == u' ' || c == u'\t' || c == u'\v' || c == u'\f' || c == u'\r'; }

//! 比較用の行（選択肢で正規化）
Text Normalize(const Text& line, const DiffOptions& o)
{
	Text r;
	r.reserve(line.size());
	bool space = false;
	for (char16_t c : line) {
		if (o.ignoreCase && c >= u'A' && c <= u'Z') c = static_cast<char16_t>(c - u'A' + u'a');
		if ((o.ignoreAllSpace || o.ignoreSpaceChange) && IsAsciiSpace(c)) {
			space = true;
			continue;
		}
		if (space && o.ignoreSpaceChange && !o.ignoreAllSpace) r += u' ';
		space = false;
		r += c;
	}
	return r;	// 行末の空白は -b でも -w でも無視
}

struct DiffContext {
	std::vector<int> a, b;			// 行の番号（同じ内容は同じ番号）
	std::vector<char> changedA, changedB;
	std::vector<int> fd, bd;		// 前向き・後ろ向きの到達点（対角線 k → x）
	int offset = 0;
	int tooExpensive = 256;

	struct Split { int x, y; };

	//! 中央のスネークを探す（Myers 1986 の線形空間版）。[xoff, xlim) × [yoff, ylim) は前後の一致を除いたあと
	Split Middle(int xoff, int xlim, int yoff, int ylim)
	{
		const int dmin = xoff - ylim, dmax = xlim - yoff;
		const int fmid = xoff - yoff, bmid = xlim - ylim;
		const bool odd = ((fmid - bmid) & 1) != 0;
		int fmin = fmid, fmax = fmid, bmin = bmid, bmax = bmid;
		fd[offset + fmid] = xoff;
		bd[offset + bmid] = xlim;
		for (int c = 1;; ++c) {
			// 前向き
			if (fmin > dmin) fd[offset + --fmin - 1] = -1; else ++fmin;
			if (fmax < dmax) fd[offset + ++fmax + 1] = -1; else --fmax;
			for (int d = fmax; d >= fmin; d -= 2) {
				const int tlo = fd[offset + d - 1], thi = fd[offset + d + 1];
				int x = tlo >= thi ? tlo + 1 : thi;
				int y = x - d;
				while (x < xlim && y < ylim && a[x] == b[y]) { ++x; ++y; }
				fd[offset + d] = x;
				if (odd && bmin <= d && d <= bmax && bd[offset + d] <= x) return Split{ x, y };
			}
			// 後ろ向き
			if (bmin > dmin) bd[offset + --bmin - 1] = INT32_MAX; else ++bmin;
			if (bmax < dmax) bd[offset + ++bmax + 1] = INT32_MAX; else --bmax;
			for (int d = bmax; d >= bmin; d -= 2) {
				const int tlo = bd[offset + d - 1], thi = bd[offset + d + 1];
				int x = tlo < thi ? tlo : thi - 1;
				int y = x - d;
				while (x > xoff && y > yoff && a[x - 1] == b[y - 1]) { --x; --y; }
				bd[offset + d] = x;
				if (!odd && fmin <= d && d <= fmax && x <= fd[offset + d]) return Split{ x, y };
			}
			if (c >= tooExpensive) {
				// 高くつきすぎる：前向きか後ろ向きで一番進んだ対角線で分ける
				int best = -1;
				Split split{ xoff, yoff };
				for (int d = fmax; d >= fmin; d -= 2) {
					const int x = std::min(fd[offset + d], xlim);
					const int y = x - d;
					if (y < yoff || y > ylim) continue;
					if (x + y - xoff - yoff > best) { best = x + y - xoff - yoff; split = Split{ x, y }; }
				}
				for (int d = bmax; d >= bmin; d -= 2) {
					const int x = std::max(bd[offset + d], xoff);
					const int y = x - d;
					if (y < yoff || y > ylim) continue;
					if (xlim + ylim - x - y > best) { best = xlim + ylim - x - y; split = Split{ x, y }; }
				}
				if (split.x == xoff && split.y == yoff) split = Split{ xlim, ylim };
				return split;
			}
		}
	}

	void Compare(int xoff, int xlim, int yoff, int ylim)
	{
		while (xoff < xlim && yoff < ylim && a[xoff] == b[yoff]) { ++xoff; ++yoff; }
		while (xlim > xoff && ylim > yoff && a[xlim - 1] == b[ylim - 1]) { --xlim; --ylim; }
		if (xoff == xlim) {
			for (int y = yoff; y < ylim; ++y) changedB[y] = 1;
			return;
		}
		if (yoff == ylim) {
			for (int x = xoff; x < xlim; ++x) changedA[x] = 1;
			return;
		}
		const Split s = Middle(xoff, xlim, yoff, ylim);
		if ((s.x == xoff && s.y == yoff) || (s.x == xlim && s.y == ylim)) {
			// 分けられない（途中で打ち切ったとき）：全部変更
			for (int x = xoff; x < xlim; ++x) changedA[x] = 1;
			for (int y = yoff; y < ylim; ++y) changedB[y] = 1;
			return;
		}
		Compare(xoff, s.x, yoff, s.y);
		Compare(s.x, xlim, s.y, ylim);
	}
};

/*!
	変更の塊を同じ内容の行の範囲でずらす。line：このファイルの行番号、changed：このファイルの変更、
	otherGap：相手のファイルで k 番目と k+1 番目の一致行の間に変更があるか
*/
void ShiftRuns(const std::vector<int>& line, std::vector<char>& changed, const std::vector<char>& otherGap)
{
	const int n = static_cast<int>(line.size());
	auto gapIndex = [&](int start) {	// start より前の一致行の数
		int k = 0;
		for (int i = 0; i < start; ++i) if (!changed[i]) ++k;
		return k;
	};
	int i = 0;
	while (i < n) {
		if (!changed[i]) { ++i; continue; }
		int start = i;
		int end = i;
		while (end < n && changed[end]) ++end;
		int runLength;
		int corresponding;
		do {
			runLength = end - start;
			// 上へずらせるだけずらす（前の塊とくっついたら一つに）
			while (start > 0 && line[start - 1] == line[end - 1]) {
				changed[--start] = 1;
				changed[--end] = 0;
				while (start > 0 && changed[start - 1]) --start;
			}
			int k = gapIndex(start);
			corresponding = (k < static_cast<int>(otherGap.size()) && otherGap[k]) ? end : -1;
			// 下へずらせるだけずらす（後ろの塊とくっついたら一つに）
			while (end < n && line[start] == line[end]) {
				changed[start++] = 0;
				changed[end++] = 1;
				while (end < n && changed[end]) ++end;
				++k;
				if (k < static_cast<int>(otherGap.size()) && otherGap[k]) corresponding = end;
			}
		} while (runLength != end - start);
		// 相手のファイルの変更と同じ所に置けるなら、そこまで上へ戻す
		if (corresponding >= 0) {
			while (end > corresponding) {
				changed[--start] = 1;
				changed[--end] = 0;
			}
		}
		i = end;
	}
}

//! 一致行の間に変更があるか（k 番目と k+1 番目の一致行の間。k = 0 は最初の一致行の前）
std::vector<char> Gaps(const std::vector<char>& changed)
{
	std::vector<char> gaps(1, 0);
	for (char c : changed) {
		if (c) gaps.back() = 1;
		else gaps.push_back(0);
	}
	return gaps;
}

} // namespace

std::vector<DiffHunk> ComputeDiff(const std::vector<Text>& oldLines, const std::vector<Text>& newLines, const DiffOptions& options)
{
	DiffContext ctx;
	std::unordered_map<Text, int> ids;
	auto id = [&](const Text& line) {
		const auto [it, inserted] = ids.emplace(Normalize(line, options), static_cast<int>(ids.size()));
		return it->second;
	};
	for (const auto& l : oldLines) ctx.a.push_back(id(l));
	for (const auto& l : newLines) ctx.b.push_back(id(l));
	const int na = static_cast<int>(ctx.a.size()), nb = static_cast<int>(ctx.b.size());
	ctx.changedA.assign(na + 1, 0);
	ctx.changedB.assign(nb + 1, 0);
	ctx.offset = nb + 1;
	ctx.fd.assign(na + nb + 3, 0);
	ctx.bd.assign(na + nb + 3, 0);
	// 編集の数の上限：対角線の数の平方根程度（最低 256）
	int diags = na + nb + 3;
	int tooExpensive = 1;
	for (; diags != 0; diags >>= 2) tooExpensive <<= 1;
	ctx.tooExpensive = std::max(256, tooExpensive);
	ctx.Compare(0, na, 0, nb);
	ctx.changedA.resize(na);
	ctx.changedB.resize(nb);

	// 塊の位置を決める（両方のファイルで。相手のファイルの変更の位置は先に決めた結果を使う）
	ShiftRuns(ctx.b, ctx.changedB, Gaps(ctx.changedA));
	ShiftRuns(ctx.a, ctx.changedA, Gaps(ctx.changedB));

	// 通常形式の塊（変更された行が続く所）。一致行で対応を取りながら進む
	std::vector<DiffHunk> hunks;
	int x = 0, y = 0;
	while (x < na || y < nb) {
		if (x < na && y < nb && !ctx.changedA[x] && !ctx.changedB[y]) { ++x; ++y; continue; }
		const int x0 = x, y0 = y;
		while (x < na && ctx.changedA[x]) ++x;
		while (y < nb && ctx.changedB[y]) ++y;
		if (x == x0 && y == y0) break;	// 念のため
		// -B：変更した行がすべて空の塊は出さない
		if (options.ignoreBlankLines) {
			bool blank = true;
			for (int i = x0; i < x && blank; ++i) blank = oldLines[i].empty();
			for (int i = y0; i < y && blank; ++i) blank = newLines[i].empty();
			if (blank) continue;
		}
		DiffHunk h;
		if (x == x0) {
			h.mode = 'a';
			h.oldFrom = h.oldTo = x0;			// 旧の x0 行目の次に追加
			h.newFrom = y0 + 1; h.newTo = y;
		} else if (y == y0) {
			h.mode = 'd';
			h.oldFrom = x0 + 1; h.oldTo = x;
			h.newFrom = h.newTo = y0;			// 新の y0 行目の次から削除
		} else {
			h.mode = 'c';
			h.oldFrom = x0 + 1; h.oldTo = x;
			h.newFrom = y0 + 1; h.newTo = y;
		}
		hunks.push_back(h);
	}
	return hunks;
}

Text FormatDiffHunk(const DiffHunk& h)
{
	// diff の通常形式の見出し（「99a99,99」「99,99c99」「99d99」）
	auto range = [](int from, int to) {
		std::string s = std::to_string(from);
		if (to != from) s += "," + std::to_string(to);
		return s;
	};
	std::string s;
	if (h.mode == 'a') s = std::to_string(h.oldFrom) + "a" + range(h.newFrom, h.newTo);
	else if (h.mode == 'd') s = range(h.oldFrom, h.oldTo) + "d" + std::to_string(h.newFrom);
	else s = range(h.oldFrom, h.oldTo) + "c" + range(h.newFrom, h.newTo);
	return Text(s.begin(), s.end());
}

std::vector<Text> SplitDiffLines(const Text& text)
{
	// diff の行：LF で区切る（Windows 版はテキストモードなので CR LF の CR は除く）。最後の行に改行がないときは印を付ける
	std::vector<Text> lines;
	size_t pos = 0;
	while (pos < text.size()) {
		const size_t lf = text.find(u'\n', pos);
		if (lf == Text::npos) {
			lines.push_back(text.substr(pos) + u'\0');	// 改行のない最後の行（\0 は区別のため）
			break;
		}
		size_t end = lf;
		if (end > pos && text[end - 1] == u'\r') --end;
		lines.push_back(text.substr(pos, end - pos));
		pos = lf + 1;
	}
	return lines;
}

} // namespace sakura::core
