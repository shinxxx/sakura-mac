// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge

/// 移動履歴（第 34 步。原版 CAutoMarkMgr：最多 30 个，新的在后面）
struct JumpHistory {
    private(set) var marks: [EditorPosition] = []
    /// 现在的位置（原版 m_nCurpos）。marks.count 是「最后的后面」
    private(set) var current = 0
    var maxCount = 30

    /// 原版 CAutoMarkMgr::Add：现在位置以后的全部删除，加在最后
    mutating func add(_ position: EditorPosition) {
        if current < marks.count { marks.removeSubrange(current...) }
        marks.append(position)
        current += 1
        if marks.count > maxCount {
            let over = marks.count - maxCount
            marks.removeFirst(over)
            current = max(0, current - over)
        }
    }

    var canPrev: Bool { current > 0 && !marks.isEmpty }
    var canNext: Bool { current + 1 < marks.count }

    mutating func prev() -> EditorPosition? {
        guard canPrev else { return nil }
        current -= 1
        return marks[current]
    }

    mutating func next() -> EditorPosition? {
        guard canNext else { return nil }
        current += 1
        return marks[current]
    }
}

/// 光标移动、选择的命令（第 34 步。原版 cmd/CViewCommander_Cursor.cpp、CViewCommander_Select.cpp）。
///
/// 原版的每个移动命令有三种：普通（F_UP）、(範囲選択)（F_UP_SEL）、(矩形選択)（F_UP_BOX）。
/// 这里用 CursorMove（移到哪里）× MoveMode（怎么选择）表示，菜单和按键都经过 cursorCommandAction(_:)。
/// 移到哪里需要原版算法的（単語、段落、変更行、行頭の空白）由核心库算（Document::WordMoveTarget 等）。
extension EditorTextView {
    enum CursorMove {
        case up, down, up2, down2, left, right, wordLeft, wordRight
        case lineTop, lineEnd, logicalLineTop, logicalLineEnd
        case halfPageUp, halfPageDown, pageUp, pageDown, fileTop, fileEnd
        case nextParagraph, prevParagraph, nextModified, prevModified

        /// 上下移动（矩形选择时横向位置不变）
        var isVertical: Bool {
            switch self {
            case .up, .down, .up2, .down2, .halfPageUp, .halfPageDown, .pageUp, .pageDown,
                 .nextParagraph, .prevParagraph, .fileTop, .fileEnd: return true
            default: return false
            }
        }
    }

    enum MoveMode {
        case normal		//!< 不选择（選択状態のロック中是选择）
        case select		//!< (範囲選択)
        case box		//!< (矩形選択)
    }

    /// 功能编号 → 移动和选择方式（原版 CViewCommander::HandleCommand 的カーソル移動系、選択系、矩形選択系）
    static let cursorCommands: [Int: (CursorMove, MoveMode)] = [
        30311: (.up, .normal), 30312: (.down, .normal), 30313: (.left, .normal), 30314: (.right, .normal),
        30315: (.up2, .normal), 30316: (.down2, .normal), 30320: (.wordLeft, .normal), 30321: (.wordRight, .normal),
        30332: (.lineTop, .normal), 30333: (.lineEnd, .normal),
        30340: (.halfPageUp, .normal), 30341: (.halfPageDown, .normal), 30342: (.pageUp, .normal), 30343: (.pageDown, .normal),
        30350: (.fileTop, .normal), 30351: (.fileEnd, .normal),
        30382: (.nextParagraph, .normal), 30383: (.prevParagraph, .normal),
        30393: (.nextModified, .normal), 30394: (.prevModified, .normal),

        30411: (.up, .select), 30412: (.down, .select), 30413: (.left, .select), 30414: (.right, .select),
        30415: (.up2, .select), 30416: (.down2, .select), 30420: (.wordLeft, .select), 30421: (.wordRight, .select),
        30432: (.lineTop, .select), 30433: (.lineEnd, .select),
        30440: (.halfPageUp, .select), 30441: (.halfPageDown, .select), 30442: (.pageUp, .select), 30443: (.pageDown, .select),
        30450: (.fileTop, .select), 30451: (.fileEnd, .select),
        30482: (.nextParagraph, .select), 30483: (.prevParagraph, .select),
        30484: (.nextModified, .select), 30485: (.prevModified, .select),

        30511: (.up, .box), 30512: (.down, .box), 30513: (.left, .box), 30514: (.right, .box),
        30515: (.up2, .box), 30516: (.down2, .box), 30520: (.wordLeft, .box), 30521: (.wordRight, .box),
        30530: (.logicalLineTop, .box), 30532: (.lineTop, .box), 30533: (.lineEnd, .box),
        30540: (.halfPageUp, .box), 30541: (.halfPageDown, .box), 30542: (.pageUp, .box), 30543: (.pageDown, .box),
        30550: (.fileTop, .box), 30551: (.fileEnd, .box),
    ]

    /// 菜单、按键的功能编号（NSMenuItem.tag 或 CommandSender.code）
    static func commandCode(of sender: Any?) -> Int? {
        if let item = sender as? NSMenuItem { return item.tag }
        if let command = sender as? CommandSender { return command.code }
        return nil
    }

    /// 移动系的命令（菜单、按键）
    @objc func cursorCommandAction(_ sender: Any?) {
        guard let code = Self.commandCode(of: sender), let entry = Self.cursorCommands[code] else { return }
        cursorCommand(entry.0, entry.1)
    }

    /// 移动光标。mode 是 .normal 时，選択状態のロック中按 (範囲選択)／(矩形選択) 处理（原版 m_bSelectingLock）
    func cursorCommand(_ move: CursorMove, _ mode: MoveMode) {
        var mode = mode
        if mode == .normal && selectingLock { mode = isBoxSelection ? .box : .select }
        switch mode {
        case .normal:
            // 原版：有选择时先取消（←→ 只取消、光标到选择的一端）
            if move != .left && move != .right && hasSelection { clearSelection() }
            performMove(move, box: false)
        case .select:
            modifySelection { performMove(move, box: false) }
        case .box:
            if !isBoxSelection { beginBoxSelection(lock: document.editSettings.boxSelectLock) }
            let previousX = boxEnd.x
            extendingSelection = true
            performMove(move, box: true)
            extendingSelection = false
            var end = caretBoxPoint
            if move.isVertical { end.x = previousX }	// 上下移动时矩形的横向不变
            boxEnd = end
            needsDisplay = true
        }
    }

    /// 光标在矩形选择里的位置
    var caretBoxPoint: BoxPoint {
        let c = caretRowAndIndex
        let xs = row(c.row).xs
        return BoxPoint(row: c.row, x: xs[min(max(0, c.index), xs.count - 1)])
    }

    /// 画面上能显示的行数（原版 m_nViewRowNum）
    var viewRowCount: Int {
        guard lineHeight > 0 else { return 1 }
        return max(1, Int(floor(visibleRect.height / lineHeight)))
    }

    /// 这一行放到画面的最上面（原版 SetViewTopLine / ScrollAtV）
    func scrollRow(toTop r: Int) {
        let maxY = max(0, bounds.height - visibleRect.height)
        let y = min(max(0, lineTop(max(0, r)) - topMargin), maxY)
        scroll(NSPoint(x: visibleRect.minX, y: y))
    }

    private func performMove(_ move: CursorMove, box: Bool) {
        switch move {
        case .up: moveVertically(-1)
        case .down: moveVertically(1)
        case .up2: moveVertically(-2)
        case .down2: moveVertically(2)
        case .left: moveCaretLeft()
        case .right: moveCaretRight()
        case .wordLeft: moveWord(left: true)
        case .wordRight: moveWord(left: false)
        case .lineTop: goLineTop()
        case .lineEnd:
            let r = caretRowAndIndex.row
            setCaret(position(row: r, index: row(r).text.length), atLineEnd: isWrapped(r))
        case .logicalLineTop: goLogicalLineTop()
        case .logicalLineEnd:
            setCaret(EditorPosition(line: caret.line, column: lineLength(caret.line)))
        case .halfPageUp: moveVertically(-viewRowCount / 2)
        case .halfPageDown: moveVertically(viewRowCount / 2)
        case .pageUp, .pageDown:
            // 原版 Command_1PageUp / Down：画面上的光标位置不变，翻一页（画面行数 - 1）
            let n = max(1, viewRowCount - 1) * (move == .pageUp ? -1 : 1)
            let top = topVisibleRow
            moveVertically(n)
            scrollRow(toTop: top + n)
        case .fileTop:
            addCurrentLineToHistory()
            if box { moveVertically(-displayLineCount) } else { setCaret(EditorPosition(line: 0, column: 0)) }
        case .fileEnd:
            addCurrentLineToHistory()
            if box { moveVertically(displayLineCount) } else { setCaret(document.endPosition) }
        case .nextParagraph, .prevParagraph:
            let target = document.paragraphTarget(fromLine: caret.line, next: move == .nextParagraph)
            guard target >= 0 else { return }
            // 原版用 Cursor_UPDOWN 上下移动到那一行（横向位置不变）
            let targetRow = target >= lineCountForLayout ? displayLineCount - 1
                : rowAndIndex(of: EditorPosition(line: target, column: 0)).row
            moveVertically(targetRow - caretRowAndIndex.row)
        case .nextModified, .prevModified:
            moveToModifiedLine(next: move == .nextModified)
        }
    }

    private var lineCountForLayout: Int { document.lineCount }

    /// 上下移动：按排版行移动（折り返した行里也一行一行地移动）。横向位置尽量保持。
    /// 超出文档时停在第一行、最后一行（原版 Cursor_UPDOWN）
    func moveVertically(_ delta: Int) {
        let current = caretRowAndIndex
        let target = min(max(0, current.row + delta), max(0, displayLineCount - 1))
        guard target != current.row else { return }
        let x = preferredX ?? displayX(row: current.row, index: current.index)
        preferredX = x
        let i = index(row: target, x: x)
        setCaret(position(row: target, index: i), keepPreferredX: true, atLineEnd: isWrapped(target) && i == row(target).text.length)
    }

    /// 原版 Command_LEFT：有选择时只取消选择；行头时到上一行的末尾
    private func moveCaretLeft() {
        if cancelSelectionBeforeMove(toEnd: false) { return }
        if caret.column > 0 {
            setCaret(EditorPosition(line: caret.line, column: composedCharacterRange(line: caret.line, at: caret.column - 1).location))
        } else if caret.line > 0 {
            setCaret(EditorPosition(line: caret.line - 1, column: lineLength(caret.line - 1)))
        }
    }

    /// 原版 Command_RIGHT：有选择时只取消选择；行末时到下一行的开头
    private func moveCaretRight() {
        if cancelSelectionBeforeMove(toEnd: true) { return }
        if caret.column < lineLength(caret.line) {
            setCaret(EditorPosition(line: caret.line, column: NSMaxRange(composedCharacterRange(line: caret.line, at: caret.column))))
        } else if caret.line < document.endPosition.line {
            setCaret(EditorPosition(line: caret.line + 1, column: 0))
        }
    }

    /// 原版 Command_WORDLEFT / WORDRIGHT
    private func moveWord(left: Bool) {
        var target = EditorPosition()
        if document.wordMoveTarget(from: caret, left: left, position: &target) {
            setCaret(target)
            return
        }
        // 行内没有时按一个字移动（跨到前后的行）
        if left {
            moveCaretLeft()
            return
        }
        moveCaretRight()
        // 原版：移到下一行后，那一行以空白开始时再找一次单词
        let first = document.text(in: EditorRange(from: EditorPosition(line: caret.line, column: 0),
                                                   to: EditorPosition(line: caret.line, column: min(1, lineLength(caret.line))))) as NSString
        if caret.column == 0, first.length > 0, first.character(at: 0) == 0x20 || first.character(at: 0) == 0x09,
           document.wordMoveTarget(from: caret, left: false, position: &target) {
            setCaret(target)
        }
    }

    /// 原版 Command_GOLINETOP：先到行头的空白之后；已经在那里时到行头
    private func goLineTop() {
        let c = caretRowAndIndex
        let r = row(c.row)
        guard r.isLayoutLine else { return }
        let start = r.start.column
        let end = start + r.text.length + (r.eol != .none ? 1 : 0)
        let indent = document.indentEnd(line: r.start.line, from: start, to: end)
        let target = EditorPosition(line: r.start.line, column: indent)
        setCaret(Self.same(target, caret) ? r.start : target)
    }

    /// 改行単位的行头（原版 Command_GOLINETOP 的 lparam 8）
    private func goLogicalLineTop() {
        let line = caret.line
        guard line < document.lineCount else { return }
        let indent = document.indentEnd(line: line, from: 0, to: lineLength(line) + 1)
        let target = EditorPosition(line: line, column: indent)
        setCaret(Self.same(target, caret) ? EditorPosition(line: line, column: 0) : target)
    }

    /// 原版 Command_MODIFYLINE_NEXT / PREV
    private func moveToModifiedLine(next: Bool) {
        var target = EditorPosition()
        var wrapped: ObjCBool = false
        if document.modifiedLineTarget(from: caret, next: next, position: &target, wrapped: &wrapped) {
            setCaret(target)	// 「▼先頭から再検索しました」原版显示在状态栏（Mac 版还没有状态栏）
            return
        }
        Self.alertNotFound(next
            ? NSLocalizedString("前方(↓) に変更行が見つかりません。", comment: "STR_MODLINE_NEXT_NOT_FOUND")
            : NSLocalizedString("後方(↑) に変更行が見つかりません。", comment: "STR_MODLINE_PREV_NOT_FOUND"))
    }

    // MARK: - 画面的滚动

    /// カーソル行をウィンドウ中央へ（F_CURLINECENTER）
    @objc func curLineCenter(_ sender: Any?) {
        scrollRow(toTop: caretRowAndIndex.row - viewRowCount / 2)
    }

    /// カーソル行をウィンドウ上部へ（F_CURLINETOP）
    @objc func curLineTop(_ sender: Any?) {
        scrollRow(toTop: caretRowAndIndex.row)
    }

    /// カーソル行をウィンドウ下部へ（F_CURLINEBOTTOM）：光标行是画面的最后一行
    @objc func curLineBottom(_ sender: Any?) {
        scrollRow(toTop: caretRowAndIndex.row - viewRowCount + 1)
    }

    /// テキストを１行下へスクロール（F_WndScrollDown，原版 Ctrl+↑）。光标出了画面时跟着移动（没有选择时）
    @objc func wndScrollDown(_ sender: Any?) {
        let top = topVisibleRow - 1
        scrollRow(toTop: top)
        if !hasSelection && caretRowAndIndex.row > topVisibleRow + viewRowCount - 1 {
            moveVertically(topVisibleRow + viewRowCount - 1 - caretRowAndIndex.row)
            scrollRow(toTop: top)
        }
    }

    /// テキストを１行上へスクロール（F_WndScrollUp，原版 Ctrl+↓）
    @objc func wndScrollUp(_ sender: Any?) {
        let top = topVisibleRow + 1
        scrollRow(toTop: top)
        if !hasSelection && caretRowAndIndex.row < topVisibleRow {
            moveVertically(topVisibleRow - caretRowAndIndex.row)
            scrollRow(toTop: top)
        }
    }

    /// ホイールアップ／ダウン／左／右、ホイールページ～（F_WHEELUP 等：按键分配给鼠标的滚轮时用）。
    /// 一次 3 行（3 桁），ページ是画面的大小
    @objc func wheelCommandAction(_ sender: Any?) {
        guard let code = Self.commandCode(of: sender) else { return }
        let page = max(1, viewRowCount - 1)
        let columns = max(1, Int(visibleRect.width / charWidth) - 1)
        var dy = 0, dx = 0
        switch code {
        case 30385: dy = -3			// F_WHEELUP
        case 30386: dy = 3			// F_WHEELDOWN
        case 30387: dx = -3			// F_WHEELLEFT
        case 30388: dx = 3			// F_WHEELRIGHT
        case 30389: dy = -page		// F_WHEELPAGEUP
        case 30390: dy = page		// F_WHEELPAGEDOWN
        case 30391: dx = -columns	// F_WHEELPAGELEFT
        case 30392: dx = columns	// F_WHEELPAGERIGHT
        default: return
        }
        let maxY = max(0, bounds.height - visibleRect.height)
        let maxX = max(0, bounds.width - visibleRect.width)
        let y = min(max(0, visibleRect.minY + CGFloat(dy) * lineHeight), maxY)
        let x = min(max(0, visibleRect.minX + CGFloat(dx) * charWidth), maxX)
        scroll(NSPoint(x: x, y: y))
    }

    // MARK: - 移動履歴

    /// 原版 CEditView::AddCurrentLineToHistory
    func addCurrentLineToHistory() {
        jumpHistory.add(caret)
    }

    /// 移動履歴: 前へ（F_JUMPHIST_PREV）
    @objc func jumpHistoryPrev(_ sender: Any?) {
        // 原版：没有「次」时（在最新的位置）先记下现在的位置再回去
        if !jumpHistory.canNext {
            addCurrentLineToHistory()
            _ = jumpHistory.prev()
        }
        if let p = jumpHistory.prev() { moveCursorSelecting(p) }
    }

    /// 移動履歴: 次へ（F_JUMPHIST_NEXT）
    @objc func jumpHistoryNext(_ sender: Any?) {
        if let p = jumpHistory.next() { moveCursorSelecting(p) }
    }

    /// 現在位置を移動履歴に登録（F_JUMPHIST_SET）
    @objc func jumpHistorySet(_ sender: Any?) {
        addCurrentLineToHistory()
    }

    /// 原版 MoveCursorSelecting：選択状態のロック中一边选择一边移动
    func moveCursorSelecting(_ position: EditorPosition) {
        if selectingLock && !isBoxSelection {
            modifySelection { setCaret(position) }
        } else {
            setCaret(position)
        }
    }

    // MARK: - 選択

    /// 現在位置の単語選択（F_SELECTWORD）：单词选中，光标在单词的末尾
    @objc func selectCurrentWord(_ sender: Any?) {
        guard !hasMarkedText() else { return }
        clearSelection()
        var range = EditorRange()
        guard document.wordRange(at: caret, range: &range) else { return }
        setSelection(from: range.from, to: range.to)
    }

    /// 1行選択（F_SELECTLINE）：光标所在的逻辑行（含换行）
    @objc func selectCurrentLine(_ sender: Any?) {
        guard !hasMarkedText() else { return }
        let line = caret.line
        let from = EditorPosition(line: line, column: 0)
        let to = line + 1 < document.lineCount ? EditorPosition(line: line + 1, column: 0) : document.endPosition
        if Self.same(from, to) {
            clearSelection()	// 只有 [EOF] 的行不选择
            setCaret(from)
            return
        }
        setSelection(from: from, to: to)
    }

    /// 範囲選択開始（F_BEGIN_SEL，F6）：从光标开始选择，并锁定（再按一次解除锁定）
    @objc func beginSelection(_ sender: Any?) {
        guard !hasMarkedText() else { return }
        if !hasSelection {
            isBoxSelection = false
            selectionAnchor = caret
        }
        selectingLock.toggle()
    }

    /// 矩形範囲選択開始（F_BEGIN_BOX，Shift+F6）
    @objc func beginBoxSelectionAction(_ sender: Any?) {
        guard !hasMarkedText() else { return }
        clearSelection()
        beginBoxSelection(lock: true)
    }

    /// 从光标开始矩形选择（原版 Command_BEGIN_BOXSELECT）
    func beginBoxSelection(lock: Bool) {
        selectionAnchor = nil
        isBoxSelection = true
        boxAnchor = caretBoxPoint
        boxEnd = boxAnchor
        selectingLock = lock
        needsDisplay = true
    }

    /// 移动系菜单的有效・無効（原版 IsFuncEnable）。不是移动系时 nil
    func validateCursorMenuItem(_ menuItem: NSMenuItem) -> Bool? {
        switch menuItem.action {
        case #selector(cursorCommandAction(_:)), #selector(curLineCenter(_:)), #selector(curLineTop(_:)),
             #selector(curLineBottom(_:)), #selector(wndScrollDown(_:)), #selector(wndScrollUp(_:)),
             #selector(wheelCommandAction(_:)), #selector(jumpHistorySet(_:)), #selector(selectCurrentWord(_:)),
             #selector(selectCurrentLine(_:)), #selector(beginSelection(_:)), #selector(beginBoxSelectionAction(_:)):
            return !hasMarkedText()
        case #selector(jumpHistoryPrev(_:)):
            return !hasMarkedText() && (jumpHistory.canPrev || !jumpHistory.marks.isEmpty)
        case #selector(jumpHistoryNext(_:)):
            return !hasMarkedText() && jumpHistory.canNext
        default:
            return nil
        }
    }
}

/// 按键执行命令时的 sender：带着功能编号（菜单是 NSMenuItem.tag）
final class CommandSender: NSObject {
    let code: Int
    init(_ code: Int) {
        self.code = code
    }
}
