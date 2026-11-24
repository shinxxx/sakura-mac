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
        return result
    }

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
