// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge

/// 打开、保存对话框下面追加的部分（第 30 步。原版 CDlgOpenFile_CommonItemDialog::Customize）。
///
/// - 打开：「文字コードセット」（最初是「自動選択」）、「CP」
/// - 保存：「文字コードセット」（没有「自動選択」）、「CP」、「BOM」，「改行コード」
/// - 文字コードセット指定（第 34 步）：「文字コードセット」（没有「自動選択」）、「CP」、「BOM」
///
/// 「CP」勾选后列表里追加代码页，之后不能取消（与原版相同）。
/// 现在的编码是代码页时，一开始就追加并勾选。
/// 原版打开对话框的「読み取り専用」和最近的文件、文件夹的列表以后与这些功能一起移植。
final class FileDialogAccessory: NSObject {
    enum Mode {
        case open
        case save
        /// 文字コードセット指定的对话框（第 34 步，原版 IDD_SETCHARSET）：编码、CP、BOM，没有改行コード
        case charset
    }

    let mode: Mode
    let view: NSView

    private let encodingPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let codePageCheck: NSButton
    private let bomCheck: NSButton
    private let eolPopUp = NSPopUpButton(frame: .zero, pullsDown: false)

    /// 文档现在的编码和 BOM：保存时换回这个编码，BOM 也回到现在的状态（与原版相同）
    private let currentEncoding: EditorEncoding
    private let currentBOM: Bool

    /// 改行コード的选项（原版的顺序）
    static let eolChoices: [(title: String, eol: EditorEol)] = [
        (L10n.tr("変換なし", comment: "保存ダイアログ > 改行コード"), EditorEol.none),
        ("CR+LF", .crlf),
        ("LF (UNIX)", .lf),
        ("CR (Mac)", .cr),
    ]

    /// - Parameters:
    ///   - encoding: 一开始选的编码（打开时是 ECEncodingAutoDetect）
    ///   - bom: 一开始的 BOM（保存时）
    init(mode: Mode, encoding: EditorEncoding, bom: Bool = false) {
        self.mode = mode
        currentEncoding = encoding
        currentBOM = bom
        codePageCheck = NSButton(checkboxWithTitle: "CP", target: nil, action: nil)
        bomCheck = NSButton(checkboxWithTitle: "BOM", target: nil, action: nil)

        let codeLabel = NSTextField(labelWithString: L10n.tr("文字コードセット:", comment: "ファイルダイアログ"))
        let codeRow: [NSView]
        switch mode {
        case .open:
            codeRow = [codeLabel, encodingPopUp, codePageCheck]
        case .save, .charset:
            codeRow = [codeLabel, encodingPopUp, codePageCheck, bomCheck]
        }
        let grid = NSGridView(views: [codeRow])
        if mode == .save {
            let eolLabel = NSTextField(labelWithString: L10n.tr("改行コード:", comment: "保存ダイアログ"))
            grid.addRow(with: [eolLabel, eolPopUp])
        }
        grid.rowSpacing = 8
        grid.columnSpacing = 8
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        grid.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView()
        container.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            grid.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
            grid.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            grid.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 20),
        ])
        view = container
        super.init()

        encodingPopUp.setAccessibilityIdentifier("encoding")
        codePageCheck.setAccessibilityIdentifier("codePage")
        bomCheck.setAccessibilityIdentifier("bom")
        eolPopUp.setAccessibilityIdentifier("eol")
        encodingPopUp.target = self
        encodingPopUp.action = #selector(encodingChanged(_:))
        codePageCheck.target = self
        codePageCheck.action = #selector(codePageToggled(_:))

        for choice in EditorCore.encodingChoices where mode == .open || choice.encoding != ECEncodingAutoDetect {
            addEncoding(choice)
        }
        if !selectEncoding(encoding) {
            // 现在的编码不在基本的列表里（代码页）：一开始就追加代码页（原版相同）
            addCodePages()
            if !selectEncoding(encoding) {
                _ = selectEncoding(ECEncodingSJIS)
            }
        }
        for choice in Self.eolChoices {
            eolPopUp.addItem(withTitle: choice.title)
            eolPopUp.lastItem?.tag = choice.eol.rawValue
        }
        eolPopUp.selectItem(at: 0)
        updateBOM()
    }

    // MARK: - 选择的结果

    var encoding: EditorEncoding {
        encodingPopUp.selectedItem.map { EditorEncoding($0.tag) } ?? currentEncoding
    }

    var bom: Bool {
        bomCheck.isEnabled && bomCheck.state == .on
    }

    var eol: EditorEol {
        eolPopUp.selectedItem.flatMap { EditorEol(rawValue: $0.tag) } ?? EditorEol.none
    }

    var codePagesShown: Bool { codePageCheck.state == .on }

    // MARK: - 操作（测试也用）

    @discardableResult
    func selectEncoding(_ encoding: EditorEncoding) -> Bool {
        guard let index = encodingPopUp.itemArray.firstIndex(where: { EditorEncoding($0.tag) == encoding }) else {
            return false
        }
        encodingPopUp.selectItem(at: index)
        updateBOM()
        return true
    }

    /// 勾选「CP」
    func showCodePages() {
        codePageToggled(nil)
    }

    func setBOM(_ on: Bool) {
        if bomCheck.isEnabled { bomCheck.state = on ? .on : .off }
    }

    func selectEol(_ eol: EditorEol) {
        if let index = eolPopUp.itemArray.firstIndex(where: { $0.tag == eol.rawValue }) {
            eolPopUp.selectItem(at: index)
        }
    }

    // MARK: - 内部

    private func addEncoding(_ choice: EditorEncodingChoice) {
        encodingPopUp.addItem(withTitle: "")
        // 同名的项目 NSPopUpButton 只留一个，所以先加空的再改标题
        encodingPopUp.lastItem?.title = choice.name
        encodingPopUp.lastItem?.tag = Int(choice.encoding)
    }

    private func addCodePages() {
        guard codePageCheck.isEnabled else { return }
        for choice in EditorCore.codePageChoices {
            addEncoding(choice)
        }
        codePageCheck.state = .on
        codePageCheck.isEnabled = false
    }

    @objc private func encodingChanged(_ sender: Any?) {
        updateBOM()
    }

    @objc private func codePageToggled(_ sender: Any?) {
        let selected = encoding
        addCodePages()
        _ = selectEncoding(selected)
    }

    /// 能加 BOM 的编码才能勾选 BOM。勾选状态：换回文档现在的编码时是现在的状态，否则是这个编码的默认值（原版 OnItemSelected）
    private func updateBOM() {
        let code = encoding
        if mode != .open && EditorCore.canHaveBOM(code) {
            bomCheck.isEnabled = true
            bomCheck.state = (code == currentEncoding ? currentBOM : EditorCore.bomDefault(code)) ? .on : .off
        } else {
            bomCheck.isEnabled = false
            bomCheck.state = .off
        }
    }
}
