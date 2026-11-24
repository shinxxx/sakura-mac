// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit
import EditorBridge
import XCTest

/// 設定画面の外観（计划第 41 步の確認で追加）。
///
/// 原版の対話框の枠のまま Mac の文字を置くと切れることがあった（ボタンの「…」、下拉框の「…」、説明の欠け）。
/// 共通設定・タイプ別設定の全部のページと、ページから開く対話框で、1 行の文字が枠に入り、字が小さくなっていないことを確かめる。
final class PropLayoutTests: XCTestCase {
    private var store: CommonSettingsTests.FakeStore!

    override func setUp() {
        _ = TestCore.home
        _ = NSApplication.shared
        store = CommonSettingsTests.FakeStore()
    }

    /// 1 行の文字が切れている控件（ID と文字と幅）
    static func truncated(_ page: PropPage) -> [String] {
        var result: [String] = []
        for control in page.definition.controls where control.id != "IDC_STATIC" {
            guard let view = page.control(control.id), !view.isHidden else { continue }
            let text = control.text ?? ""
            switch view {
            case let popup as NSPopUpButton:
                // どの項目を選んでも全部見える
                if popup.numberOfItems > 0 && popup.fittingSize.width > popup.frame.width + 0.5 {
                    result.append("\(control.id) 下拉框 \(popup.itemTitles.max { $0.count < $1.count } ?? "") \(popup.fittingSize.width) > \(popup.frame.width)")
                }
            case let button as NSButton:
                if !text.contains("\n") && !control.has("multiline") && button.fittingSize.width > button.frame.width + 0.5 {
                    result.append("\(control.id) \(text) \(button.fittingSize.width) > \(button.frame.width)")
                }
                if button.font?.pointSize != PropPage.font.pointSize {
                    result.append("\(control.id) \(text) 字の大きさ \(button.font?.pointSize ?? 0)")
                }
            default:
                break
            }
        }
        // 説明（IDC_STATIC を含む）
        for case let label as NSTextField in page.view.subviews where !label.isEditable && !label.isHidden && !label.stringValue.isEmpty {
            let singleLine = label.cell?.wraps == false || label.frame.height <= PropPage.points(12)
            if singleLine && !label.stringValue.contains("\n") && label.fittingSize.width > label.frame.width + 0.5 && label.alignment == .left {
                result.append("label \(label.stringValue) \(label.fittingSize.width) > \(label.frame.width)")
            }
        }
        // 広げた控件がほかの控件に重ならない（原版で重なっていないもの同士）
        let controls = page.definition.controls.filter { $0.id != "IDC_STATIC" && $0.kind != "group" && $0.kind != "spin" }
        func original(_ c: PropDialogs.Control) -> NSRect {
            NSRect(x: PropPage.pointsX(c.frame[0]), y: PropPage.points(c.frame[1]), width: PropPage.pointsX(c.frame[2]), height: PropPage.points(c.frame[3]))
        }
        for (i, a) in controls.enumerated() {
            guard let va = page.control(a.id), !va.isHidden, va.superview === page.view else { continue }
            for b in controls[(i + 1)...] {
                guard let vb = page.control(b.id), !vb.isHidden, vb.superview === page.view, !original(a).intersects(original(b)) else { continue }
                if va.frame.insetBy(dx: 1, dy: 1).intersects(vb.frame.insetBy(dx: 1, dy: 1)) {
                    result.append("重なり \(a.id) \(b.id)")
                }
            }
        }
        // 横に並んだボタンの間は 3 点以上（くっついて 1 つのボタンに見えないように）
        let buttons = controls.filter { $0.kind == "button" }.compactMap { c -> (String, NSRect)? in
            guard let v = page.control(c.id), !v.isHidden else { return nil }
            return (c.id, v.frame)
        }
        for (i, a) in buttons.enumerated() {
            for b in buttons[(i + 1)...] where a.1.maxY > b.1.minY + 4 && a.1.minY < b.1.maxY - 4 {
                let gap = a.1.minX < b.1.minX ? b.1.minX - a.1.maxX : a.1.minX - b.1.maxX
                if gap < 3 { result.append("ボタンの間 \(a.0) \(b.0) \(gap)") }
            }
        }
        // 分组框の中の控件は枠線から離す（Mac の分组框は角が丸く、線に触れると窮屈に見える）。ページの外にも出さない
        let groups = page.definition.controls.filter { $0.kind == "group" }.map(original)
        // 上下ボタン（spin）は前の数値欄に付く：数値欄の原版の位置で分组框を決める
        var edgeControls = controls.map { ($0, $0) }
        var lastEdit: PropDialogs.Control?
        for c in page.definition.controls {
            if c.kind == "edit" { lastEdit = c }
            if c.kind == "spin", c.id != "IDC_STATIC", let edit = lastEdit { edgeControls.append((c, edit)) }
        }
        for (c, placed) in edgeControls {
            guard let v = page.control(c.id), !v.isHidden else { continue }
            let frame = v.superview === page.view ? v.frame : v.convert(v.bounds, to: page.view)
            let o = original(placed)
            if frame.minX < 0 || frame.maxX > page.view.frame.width { result.append("ページの外 \(c.id)") }
            // 原版で中にある一番小さい分组框
            guard let group = groups.filter({ $0.contains(o.insetBy(dx: 1, dy: 1)) }).min(by: { $0.width * $0.height < $1.width * $1.height }) else { continue }
            if frame.maxX > group.maxX - Self.groupMargin || frame.minX < group.minX + Self.groupMargin {
                result.append("枠線に近い \(c.id) \(frame.minX)-\(frame.maxX) 枠 \(group.minX)-\(group.maxX)")
            }
        }
        return result
    }

    /// 分组框の枠線と中の控件の間（点）
    static let groupMargin: CGFloat = 4

    func testCommonSettingsPagesHaveNoTruncatedText() throws {
        let controller = try XCTUnwrap(CommonSettingsWindowController(store: store))
        defer { controller.cancel(nil) }
        var problems: [String] = []
        for index in 0..<controller.pageCount {
            let page = controller.page(index)
            problems += Self.truncated(page).map { "\(controller.pageName(index)): \($0)" }
        }
        XCTAssertEqual(problems, [], problems.joined(separator: "\n"))
    }

    func testTypeSettingsPagesHaveNoTruncatedText() throws {
        let controller = try XCTUnwrap(TypeSettingsWindowController(store: store, typeIndex: 0))
        defer { controller.cancel(nil) }
        var problems: [String] = []
        for index in 0..<controller.pageCount {
            let page = controller.page(index)
            problems += Self.truncated(page).map { "\(controller.pageName(index)): \($0)" }
        }
        XCTAssertEqual(problems, [], problems.joined(separator: "\n"))
    }

    /// ページから開く対話框（位置と大きさ、文字色統一、強調キーワードの選択、タイプ別設定一覧 等）
    func testDialogsHaveNoTruncatedText() throws {
        var problems: [String] = []
        for resource in ["CommonSettingsDialogs", "TypeSettingsDialogs"] {
            for definition in PropDialogs.load(resource)?.dialogs ?? [] {
                problems += Self.truncated(PropPage(definition: definition)).map { "\(definition.dialog): \($0)" }
            }
        }
        XCTAssertEqual(problems, [], problems.joined(separator: "\n"))
    }
}
