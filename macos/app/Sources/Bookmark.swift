// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge

/// ブックマーク（第 44 步，原版 cmd/CViewCommander_Bookmark.cpp、docplus/CBookmarkManager.cpp）
extension EditorTextView {
    /// ブックマーク設定・解除（F_BOOKMARK_SET，原版 Command_BOOKMARK_SET）：
    /// 複数行の選択中は選択範囲の各行（選択の終わりの行も）、そうでなければカーソル行のブックマークを反転
    @objc func bookmarkSet(_ sender: Any?) {
        if let rows = selectedRowSpan(), rows.top < rows.bottom {
            document.toggleBookmarks(from: row(rows.top).start.line, to: row(rows.bottom).start.line)
        } else {
            document.toggleBookmarks(from: caret.line, to: caret.line)
        }
        needsDisplay = true
    }

    /// 選択範囲の最初と最後の画面上の行（原版 m_sSelect.GetFrom().y、GetTo().y）。選択していないときは nil
    private func selectedRowSpan() -> (top: Int, bottom: Int)? {
        if let box = boxSelection { return (box.top, box.bottom) }
        guard let selection else { return nil }
        return (rowAndIndex(of: selection.from).row, rowAndIndex(of: selection.to).row)
    }

    /// 次のブックマークへ（F_BOOKMARK_NEXT）
    @objc func bookmarkNext(_ sender: Any?) {
        moveToBookmark(next: true)
    }

    /// 前のブックマークへ（F_BOOKMARK_PREV）
    @objc func bookmarkPrev(_ sender: Any?) {
        moveToBookmark(next: false)
    }

    private func moveToBookmark(next: Bool) {
        var wrapped: ObjCBool = false
        let line = document.findBookmark(from: caret.line, forward: next, searchAll: EditorCore.searchSettings.searchAll,
                                         wrapped: &wrapped)
        if line >= 0 {
            moveCursorSelecting(EditorPosition(line: line, column: 0))
            sendSearchStatus(next: next, wrapped: wrapped.boolValue)
            return
        }
        sendSearchStatus(next: next, wrapped: nil)
        Self.alertNotFound(next
            ? L10n.tr("前方(↓) にブックマークが見つかりません。", comment: "STR_BOOKMARK_NEXT_NOT_FOUND")
            : L10n.tr("後方(↑) にブックマークが見つかりません。", comment: "STR_BOOKMARK_PREV_NOT_FOUND"))
    }

    /// ブックマークの全解除（F_BOOKMARK_RESET）
    @objc func bookmarkReset(_ sender: Any?) {
        document.resetBookmarks()
        needsDisplay = true
    }

    /// ブックマークの一覧（F_BOOKMARK_VIEW，原版 Command_FUNCLIST(OUTLINE_BOOKMARK)）：アウトライン解析の窓口に一覧
    @objc func bookmarkView(_ sender: Any?) {
        outlineCommand(action: .normal, type: .bookmark)
    }

    /// パターンに一致する行をマーク（F_BOOKMARK_PATTERN，原版 Command_BOOKMARK_PATTERN）：
    /// 現在の検索文字列・条件（検索ダイアログの「該当行マーク」から呼ばれる）に一致する行
    @objc func bookmarkPattern(_ sender: Any?) {
        guard changeCurrentRegexp(), !searchState.key.isEmpty else { return }
        if !document.markPattern(searchState.key, options: searchState.options) {
            Self.showRegexpError(document.lastSearchError)
        }
        needsDisplay = true
    }

    /// 行番号の色（原版 CTextDrawer::DispLineNumber）：DIFF の行は「DIFF差分表示」の色、ブックマークの行は「ブックマーク」の色。
    /// 変更行のときは、色・太字・下線が「行番号」と同じ部分を「行番号（変更行）」のものにする
    func lineNumberColor(line: Int) -> (info: EditorColorSetting, markBar: Bool) {
        let number = color(.lineNumber)
        let modifiedColor = color(.lineNumberModified)
        var info = number
        var gyouMod = false
        if modifiedColor.display && document.isLineModified(line) {
            info = modifiedColor
            gyouMod = true
        }
        var marked = false
        // DIFF色設定（原版 CDiffLineGetter::GetDiffColor）
        let diffColor: EditorColorIndex?
        switch document.diffMark(line) {
        case 1: diffColor = .diffAppend
        case 2: diffColor = .diffChange
        case 3, 4: diffColor = .diffDelete
        default: diffColor = nil
        }
        if let diffColor, color(diffColor).display {
            info = color(diffColor)
            marked = true
        }
        let bookmarked = document.isBookmarked(line)
        let mark = color(.mark)
        if bookmarked && mark.display {
            info = mark
            marked = true
        }
        if gyouMod && marked {
            // 2013.12.30 変更行の色・フォント属性をDIFFブックマーク行に継承する
            if number.text == info.text { info.text = modifiedColor.text }
            if number.back == info.back { info.back = modifiedColor.back }
            if number.bold == info.bold { info.bold = modifiedColor.bold }
            if number.underline == info.underline { info.underline = modifiedColor.underline }
        }
        // 「ブックマーク」を表示しないときは行番号の左に縦線（原版「とりあえずブックマークに縦線」）
        return (info, bookmarked && !mark.display)
    }

    /// DIFF の印（原版 CDiffLineGetter::DrawDiffMark）：行番号の左の小さな記号。color は行番号の文字色
    func drawDiffMark(line: Int, top: CGFloat, color: NSColor) {
        let mark = document.diffMark(line)
        guard mark != 0 else { return }
        var cy = (top + lineHeight / 2).rounded(.down)
        let path = NSBezierPath()
        path.lineWidth = 1
        path.lineCapStyle = .square	// 端の点も描く（原版の 1 ドットのペン）
        // 原版の MoveToEx・LineTo（終わりの点は描かない）を、点の中心を通る線で
        func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x + 0.5, y: y + 0.5) }
        switch mark {
        case 1:	// 追加：＋
            path.move(to: p(3, cy)); path.line(to: p(5, cy))
            path.move(to: p(4, cy - 2)); path.line(to: p(4, cy + 2))
        case 2:	// 変更：！
            path.move(to: p(3, cy - 4)); path.line(to: p(3, cy - 1))
        case 3:	// 削除：右下向きの矢印
            cy -= 3
            path.move(to: p(3, cy)); path.line(to: p(5, cy)); path.line(to: p(3, cy + 2)); path.line(to: p(3, cy)); path.line(to: p(6, cy + 3))
        case 4:	// 削除(EOF以降)：右上向きの矢印
            cy += 3
            path.move(to: p(3, cy)); path.line(to: p(5, cy)); path.line(to: p(3, cy - 2)); path.line(to: p(3, cy)); path.line(to: p(6, cy - 3))
        default:
            return
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.shouldAntialias = false	// 原版と同じくドットで
        color.setStroke()
        path.stroke()
        NSGraphicsContext.restoreGraphicsState()
        if mark == 2 {	// 1 点だけの線は stroke で描かれないので塗る
            color.setFill()
            NSRect(x: 3, y: cy + 2, width: 1, height: 1).fill()
        }
    }
}
