// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge

/// 対括弧の検索（F_BRACKETPAIR）和対括弧の強調表示（第 44 步，原版 view/CEditView_Paint_Bracket.cpp、Command_BRACKETPAIR）
extension EditorTextView {
    /// 対括弧の検索（原版 Command_BRACKETPAIR：mode 3 = 表示領域外も調べる、前方文字も調べる）。
    /// 找到时移动光标（選択ロック中は選択を広げる，原版 MoveCursorSelecting），找不到时什么也不做
    @objc func bracketPair(_ sender: Any?) {
        guard !hasMarkedText() else { return }
        var pair = EditorPosition(), bracket = EditorPosition()
        guard document.findBracketPair(at: caret, checkPrev: true, areaTop: 1, areaBottom: 0,
                                       pair: &pair, bracket: &bracket) else { return }
        moveCursorSelecting(pair)
    }

    /// 表示領域の排版行（原版 GetViewTopLine ～ GetBottomLine）
    var visibleRowRange: (top: Int, bottom: Int) {
        let top = topVisibleRow
        let rows = lineHeight > 0 ? Int(((enclosingScrollView?.contentSize.height ?? visibleRect.height) / lineHeight).rounded(.down)) : 0
        return (top, top + rows)
    }

    /// 強調表示する対括弧の位置を決める（原版 SetBracketPairPos(true)：カーソル移動のたびに）。
    /// 「対括弧」の色を表示しない、選択中、表示領域に対括弧がない（左右も）ときは強調表示しない
    func updateBracketHighlight() {
        bracketHighlight = nil
        guard color(.bracketPair).display, !hasSelection else { return }
        let area = visibleRowRange
        var pair = EditorPosition(), bracket = EditorPosition()
        // mode 2：表示領域外は調べない、前方文字も調べる
        guard document.findBracketPair(at: caret, checkPrev: true, areaTop: area.top, areaBottom: area.bottom,
                                       pair: &pair, bracket: &bracket) else { return }
        let p = rowAndIndex(of: pair)
        guard p.row >= area.top && p.row <= area.bottom else { return }
        let x = displayX(row: p.row, index: p.index)
        guard x >= visibleRect.minX && x <= visibleRect.maxX else { return }
        bracketHighlight = (pair, bracket)
    }

    /// この行で対括弧の色で描く文字の下標（原版 DrawBracketPair(true)：選択中、フォーカスがないときは描かない）
    func bracketHighlightIndices(row r: Int) -> [Int] {
        guard let highlight = bracketHighlight, !hasSelection, window?.firstResponder === self else { return [] }
        let current = row(r)
        guard current.isLayoutLine else { return [] }
        var result: [Int] = []
        for position in [highlight.pair, highlight.bracket] where position.line == current.start.line {
            let i = position.column - current.start.column
            if i >= 0 && i < current.text.length && EditorDocument.isBracket(current.text.character(at: i)) {
                result.append(i)
            }
        }
        return result
    }
}
