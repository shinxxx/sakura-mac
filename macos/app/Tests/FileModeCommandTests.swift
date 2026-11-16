// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge
import XCTest

/// ファイル、モード切り替え、設定、バージョン情報的命令（计划第 34 步的第 3 个 PR）的测试。
///
/// 按功能编号执行（CommandTable.perform，与菜单、快捷键相同的路径），或者直接调用文档的命令
/// （单元测试里 NSApp 的响应链上没有文档）。对话框换成不出来的（chooseCharset、confirmReload）。
/// 上書き的规则、折り返し的切换顺序、倍率表由核心库的测试（test-mac-mode.cpp）逐项确认。
final class FileModeCommandTests: XCTestCase {
    private var workDir: URL!
    private var documents: [SakuraDocument] = []
    private var savedChooseCharset: ((EditorTextView, EditorEncoding, Bool, @escaping ((EditorEncoding, Bool)?) -> Void) -> Void)!
    private var savedConfirmReload: ((String) -> Bool)!

    override func setUpWithError() throws {
        _ = TestCore.home
        _ = NSApplication.shared
        workDir = TestCore.home.appendingPathComponent("filemode-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        savedChooseCharset = EditorTextView.chooseCharset
        savedConfirmReload = SakuraDocument.confirmReload
        EditorTextView.resetFont()
    }

    override func tearDown() {
        EditorTextView.chooseCharset = savedChooseCharset
        SakuraDocument.confirmReload = savedConfirmReload
        EditorTextView.resetFont()
        for document in documents {
            for controller in document.windowControllers {
                controller.window?.orderOut(nil)
                document.removeWindowController(controller)
            }
        }
        documents = []
    }

    private func write(_ name: String, _ bytes: [UInt8]) throws -> URL {
        let url = workDir.appendingPathComponent(name)
        try Data(bytes).write(to: url)
        return url
    }

    private func open(_ url: URL) throws -> SakuraDocument {
        let document = try SakuraDocument(contentsOf: url, ofType: "public.plain-text")
        document.makeWindowControllers()
        documents.append(document)
        return document
    }

    private func untitled() -> SakuraDocument {
        let document = SakuraDocument()
        document.makeWindowControllers()
        documents.append(document)
        return document
    }

    private func view(_ document: SakuraDocument) throws -> EditorTextView {
        try XCTUnwrap(document.editorWindowController?.textView)
    }

    private func type(_ view: EditorTextView, _ text: String) {
        view.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    private func menuItem(_ code: Int) -> NSMenuItem {
        let item = NSMenuItem(title: "", action: CommandTable.selector(for: code), keyEquivalent: "")
        item.tag = code
        return item
    }

    // MARK: - 挿入／上書きモード

    /// Insert 键（F_CHGMOD_INS）：上書き时输入的字换掉光标处的字；菜单打勾；光标变成一个字宽
    func testInsertModeToggle() throws {
        let view = try view(untitled())
        type(view, "abcd")
        view.setCaret(EditorPosition(line: 0, column: 1))
        let item = menuItem(31001)
        XCTAssertTrue(view.validateMenuItem(item))
        XCTAssertEqual(item.state, .on, "挿入モード")
        XCTAssertEqual(view.caretRect.width, 2)

        XCTAssertTrue(CommandTable.perform(31001, from: view))
        XCTAssertFalse(view.document.insertMode)
        XCTAssertTrue(view.validateMenuItem(item))
        XCTAssertEqual(item.state, .off)
        XCTAssertEqual(view.caretRect.width, view.charWidth, "上書きモード：一个字的宽度")

        type(view, "XY")
        XCTAssertEqual(view.document.text, "aXYd")
        XCTAssertEqual(view.caret.column, 3)
        // 有选择时与挿入モード相同：换掉选择范围
        view.setSelection(from: EditorPosition(line: 0, column: 0), to: EditorPosition(line: 0, column: 2))
        type(view, "Z")
        XCTAssertEqual(view.document.text, "ZYd")
        // 撤销是一步
        view.setCaret(EditorPosition(line: 0, column: 1))
        type(view, "QQ")
        XCTAssertEqual(view.document.text, "ZQQ")
        view.undo(nil)
        XCTAssertEqual(view.document.text, "ZYd")

        XCTAssertTrue(CommandTable.perform(31001, from: view))
        XCTAssertTrue(view.document.insertMode)
    }

    // MARK: - 入力改行コード指定

    func testNewLineEolCommands() throws {
        let view = try view(untitled())
        XCTAssertTrue(CommandTable.perform(31082, from: view))		// F_CHGMOD_EOL_LF
        XCTAssertEqual(view.document.newLineEol, .lf)
        let lf = menuItem(31082)
        let crlf = menuItem(31081)
        XCTAssertTrue(view.validateMenuItem(lf))
        XCTAssertEqual(lf.state, .on)
        XCTAssertTrue(view.validateMenuItem(crlf))
        XCTAssertEqual(crlf.state, .off)
        view.insertNewline(nil)
        XCTAssertEqual(view.document.text, "\n")
        XCTAssertTrue(CommandTable.perform(31083, from: view))		// F_CHGMOD_EOL_CR
        XCTAssertEqual(view.document.newLineEol, .cr)
    }

    // MARK: - 文字コードセット指定

    /// 对话框选的编码和 BOM 成为下次保存的设置；打开的文件改了编码时关闭前要确认
    func testChangeCharset() throws {
        let document = try open(try write("cs.txt", Array("abc\r\n".utf8)))
        let view = try view(document)
        XCTAssertEqual(document.editor.encoding, ECEncodingUTF8)
        var shown: (EditorEncoding, Bool)?
        EditorTextView.chooseCharset = { _, encoding, bom, completion in
            shown = (encoding, bom)
            completion((ECEncodingUTF16LE, true))
        }
        XCTAssertTrue(CommandTable.perform(31010, from: view))
        XCTAssertEqual(shown?.0, ECEncodingUTF8, "对话框一开始是现在的编码")
        XCTAssertEqual(document.editor.encoding, ECEncodingUTF16LE)
        XCTAssertTrue(document.editor.hasBOM)
        XCTAssertTrue(document.editor.isEncodingChanged)
        XCTAssertTrue(document.isDocumentEdited, "原版：文字コードセットが変更されています → 关闭前确认")
        XCTAssertFalse(document.editor.isModified)
        // 取消时不变
        EditorTextView.chooseCharset = { _, _, _, completion in completion(nil) }
        XCTAssertTrue(CommandTable.perform(31010, from: view))
        XCTAssertEqual(document.editor.encoding, ECEncodingUTF16LE)
    }

    /// 文字コードの指定 对话框（FileDialogAccessory 的 .charset）：没有「自動選択」、有 BOM，没有改行コード
    func testCharsetAccessory() {
        let accessory = FileDialogAccessory(mode: .charset, encoding: ECEncodingUTF8, bom: true)
        XCTAssertEqual(accessory.encoding, ECEncodingUTF8)
        XCTAssertTrue(accessory.bom)
        XCTAssertFalse(accessory.selectEncoding(ECEncodingAutoDetect))
        XCTAssertTrue(accessory.selectEncoding(ECEncodingSJIS))
        XCTAssertFalse(accessory.bom, "SJIS 不能加 BOM")
        XCTAssertTrue(accessory.selectEncoding(ECEncodingUTF16LE))
        accessory.setBOM(true)
        XCTAssertTrue(accessory.bom)
    }

    // MARK: - ○○で開き直す

    func testReopenWithEncoding() throws {
        let url = try write("sjis.txt", [0x82, 0xA0, 0x0D, 0x0A, 0x61, 0x62, 0x63])	// SJIS「あ」+ 改行 + abc
        let document = try open(url)
        let view = try view(document)
        XCTAssertEqual(document.editor.encoding, ECEncodingSJIS)
        let sjis = menuItem(30111)
        XCTAssertTrue(document.validateUserInterfaceItem(sjis))
        XCTAssertEqual(sjis.state, .on, "现在的编码打勾")

        view.setCaret(EditorPosition(line: 1, column: 2))
        document.reopenWithEncoding(CommandSender(30122))		// Latin1：2 字节各是一个字
        XCTAssertEqual(document.editor.encoding, ECEncodingLatin1)
        XCTAssertEqual((document.editor.line(at: 0) as NSString).length, 2)
        XCTAssertEqual(view.caret.line, 1, "光标留在原来的地方")
        XCTAssertEqual(view.caret.column, 2)
        XCTAssertFalse(document.isDocumentEdited)

        // 修改过时先确认，取消时不读
        type(view, "x")
        var asked: String?
        SakuraDocument.confirmReload = { path in asked = path; return false }
        document.reopenWithEncoding(CommandSender(30111))
        XCTAssertEqual(asked, url.path)
        XCTAssertEqual(document.editor.encoding, ECEncodingLatin1)
        XCTAssertTrue(document.editor.isModified)
        // OK 时读入，修改丢掉
        SakuraDocument.confirmReload = { _ in true }
        document.reopenWithEncoding(CommandSender(30111))
        XCTAssertEqual(document.editor.encoding, ECEncodingSJIS)
        XCTAssertEqual(document.editor.text, "あ\r\nabc")
        XCTAssertFalse(document.editor.isModified)
        // 開き直す（30119）：现在的编码
        document.reopenWithEncoding(CommandSender(30119))
        XCTAssertEqual(document.editor.encoding, ECEncodingSJIS)
    }

    /// 无题（没有文件）时只设定编码（原版 ReloadCurrentFile：ファイルが存在しない）
    func testReopenUntitledSetsEncoding() {
        let document = untitled()
        document.reopenWithEncoding(CommandSender(30117))		// UnicodeBE
        XCTAssertEqual(document.editor.encoding, ECEncodingUTF16BE)
        XCTAssertEqual(document.editor.hasBOM, EditorCore.bomDefault(ECEncodingUTF16BE))
    }

    // MARK: - 閉じて(無題)

    func testCloseToUntitled() throws {
        let document = try open(try write("close.txt", Array("hello\n".utf8)))
        let view = try view(document)
        let window = try XCTUnwrap(view.window)
        let path = try XCTUnwrap(document.fileURL).path
        view.setCaret(EditorPosition(line: 0, column: 3))
        document.closeToUntitled(nil)		// 没有修改：不问
        XCTAssertNil(document.fileURL)
        XCTAssertEqual(document.editor.text, "")
        XCTAssertEqual(document.editor.path, "")
        XCTAssertEqual(view.caret.line, 0)
        XCTAssertEqual(view.caret.column, 0)
        XCTAssertTrue(view.window === window, "同一个窗口")
        XCTAssertEqual(window.title, "(無題)")
        // 之后照常输入
        type(view, "new")
        XCTAssertEqual(document.editor.text, "new")
        // 关闭前登记到了「最近使ったファイル」：光标位置
        let recent = try XCTUnwrap(EditorCore.recentFile(path: path))
        XCTAssertEqual(recent.caret.column, 3)
    }

    // MARK: - 保存

    /// 上書き保存(限定動作)：无题、没有修改时什么也不做；有修改时保存
    func testSaveQuietly() throws {
        let plain = untitled()
        type(try view(plain), "x")
        XCTAssertFalse(plain.validateUserInterfaceItem(menuItem(30121)))
        plain.saveQuietly(nil)			// 不出「名前を付けて保存」
        XCTAssertNil(plain.fileURL)

        let url = try write("quiet.txt", Array("abc".utf8))
        let document = try open(url)
        XCTAssertFalse(document.canSaveInPlace, "没有修改")
        type(try view(document), "Z")
        XCTAssertTrue(document.validateUserInterfaceItem(menuItem(30121)))
        document.saveQuietly(nil)
        let saved = expectation(for: NSPredicate { _, _ in (try? String(contentsOf: url, encoding: .utf8)) == "Zabc" },
                                evaluatedWith: nil)
        wait(for: [saved], timeout: 10)
        XCTAssertFalse(document.editor.isModified)
    }

    // MARK: - 現在のウィンドウ幅で折り返し

    func testWrapWindowWidthToggle() throws {
        let view = try view(untitled())
        type(view, String(repeating: "a", count: 300))
        let windowColumns = view.document.wrapColumns(forWidth: Int(view.enclosingScrollView!.contentSize.width - view.textOriginX))
        XCTAssertTrue(CommandTable.perform(31140, from: view))
        XCTAssertEqual(view.settings.wrapMethod, .settingWidth)
        XCTAssertEqual(view.settings.wrapColumns, windowColumns, "ウィンドウ幅")
        XCTAssertTrue(CommandTable.perform(31140, from: view))
        XCTAssertEqual(view.settings.wrapColumns, 10240, "最大値")
        XCTAssertTrue(CommandTable.perform(31140, from: view))
        // 最大値 → 設定値。設定値也是最大値（10240）时跳过这一步，回到ウィンドウ幅（原版 GetWrapMode 的 b）
        let typeColumns = view.settings.typeWrapColumns
        XCTAssertEqual(view.settings.wrapColumns, typeColumns == 10240 ? windowColumns : typeColumns, "設定値")
    }

    // MARK: - フォントサイズ拡大／縮小

    func testFontSizeUpDown() throws {
        let view = try view(untitled())
        XCTAssertEqual(EditorTextView.displayFontSize, 13)
        XCTAssertTrue(CommandTable.perform(31122, from: view))		// 13 × 1.1 = 14.3 → 14
        XCTAssertEqual(EditorTextView.displayFontSize, 14)
        XCTAssertEqual(view.font.pointSize, 14, "窗口的字体也变")
        XCTAssertEqual(EditorTextView.fontSize, 13, "设置不变（不保存）")
        XCTAssertTrue(CommandTable.perform(31122, from: view))		// 13 × 1.25 = 16.25 → 16
        XCTAssertEqual(EditorTextView.displayFontSize, 16)
        XCTAssertTrue(CommandTable.perform(31123, from: view))
        XCTAssertTrue(CommandTable.perform(31123, from: view))
        XCTAssertEqual(EditorTextView.displayFontSize, 13)
        XCTAssertTrue(CommandTable.perform(31123, from: view))		// 13 × 0.9 = 11.7 → 11
        XCTAssertEqual(EditorTextView.displayFontSize, 11)
        // 字体设置改变时倍率回到 1
        EditorTextView.setFont(NSFont(name: "Menlo", size: 15)!)
        XCTAssertEqual(EditorTextView.displayFontSize, 15)
        XCTAssertEqual(EditorTextView.fontZoom, 1.0)
    }

    // MARK: - バージョン情報

    /// 原版的内容（名字、原作者、版权、URL、说明）和 zlib 许可证、修改版的声明
    func testAboutPanel() throws {
        XCTAssertEqual(CommandTable.selector(for: 31455), #selector(NSApplication.showSakuraAbout(_:)))
        XCTAssertTrue(AboutPanel.versionText.hasPrefix("サクラエディタ for Mac Ver. "))
        XCTAssertEqual(AboutPanel.originalAuthor, "原作者: たけ(竹パンダ) さん")
        XCTAssertEqual(AboutPanel.copyright, "Copyright (C) 1998-2022  by Norio Nakatani & Collaborators")
        let description = AboutPanel.descriptionText
        XCTAssertTrue(description.hasPrefix("このソフトウェアは「テキストエディタ(共同開発版)」を改称したものです。"))
        XCTAssertTrue(description.contains("サクラエディタの公式版ではありません"))
        XCTAssertTrue(description.contains("zlib License"))
        XCTAssertTrue(description.contains("Copyright (C) 2018-2022, Sakura Editor Organization"))
        XCTAssertTrue(description.contains("2. Altered source versions must be plainly marked as such"))
        XCTAssertTrue(description.contains("3. This notice may not be removed or altered from any source distribution."))

        AboutPanel.shared.show()
        let panel = try XCTUnwrap(AboutPanel.shared.window)
        XCTAssertEqual(panel.title, "バージョン情報")
        XCTAssertTrue(panel.isVisible)
        // 情報をコピー：版本的部分
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("sakura-test-\(UUID().uuidString)"))
        let saved = AboutPanel.pasteboard
        AboutPanel.pasteboard = pasteboard
        defer { AboutPanel.pasteboard = saved }
        AboutPanel.shared.copyInfo(nil)
        XCTAssertEqual(pasteboard.string(forType: .string), AboutPanel.versionText)
        AboutPanel.shared.closePanel(nil)
        XCTAssertNil(AboutPanel.shared.window)
    }

    // MARK: - 菜单

    /// 这个 PR 的命令都有动作（菜单不变灰）
    func testCommandsAreMapped() {
        let codes = [30105, 30107, 30109, 30110, 30111, 30112, 30113, 30114, 30115, 30116, 30117, 30118, 30119,
                     30120, 30121, 30122, 31001, 31010, 31081, 31082, 31083, 31084, 31085, 31086,
                     31122, 31123, 31140, 31455]
        for code in codes {
            XCTAssertNotNil(CommandTable.selector(for: code), "功能 \(code)")
        }
    }
}
