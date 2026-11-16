// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit

/// バージョン情報（计划第 34 步。原版 CDlgAbout、IDD_ABOUT）。
///
/// 与原版的对话框相同的内容：图标、版本、原作者、版权、Project URL、说明（IDS_ABOUT_DESCRIPTION），
/// 「OK」和「情報をコピー」。说明里加上 zlib 许可证的全文和「这是修改过的版本」的声明
/// （zlib 许可证第 2、3 条：修改过的版本要明确标出，许可证的声明不能去掉）。
/// App 菜单的「について」和ヘルプ > バージョン情報 都打开这里。
final class AboutPanel: NSObject, NSWindowDelegate {
    static let shared = AboutPanel()

    /// 原版 STR_DLGABOUT_APPNAME
    static let appName = NSLocalizedString("サクラエディタ", comment: "STR_DLGABOUT_APPNAME")
    /// 原版 S_COPYRIGHT（sakura_rc.rc2）
    static let copyright = "Copyright (C) 1998-2022  by Norio Nakatani & Collaborators"
    static let originalAuthor = NSLocalizedString("原作者: たけ(竹パンダ) さん", comment: "IDD_ABOUT")
    static let projectURL = URL(string: "https://sakura-editor.github.io/")!

    /// 版本的部分（原版 IDC_EDIT_VER。「情報をコピー」复制这一段）
    static var versionText: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "0"
        let build = info["CFBundleVersion"] as? String ?? "0"
        var lines = ["\(appName) for Mac Ver. \(version) (\(build))"]
        lines.append("")
        lines.append("      macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        #if arch(arm64)
        lines.append("      Architecture: arm64")
        #else
        lines.append("      Architecture: x86_64")
        #endif
        return lines.joined(separator: "\n") + "\n"
    }

    /// 说明的部分（原版 IDC_EDIT_ABOUT 的 IDS_ABOUT_DESCRIPTION），后面是修改版的声明和许可证
    static var descriptionText: String {
        let description = NSLocalizedString(
            "このソフトウェアは「テキストエディタ(共同開発版)」を改称したものです。\n商用・非商用を問わず無償で利用できますが、ソースコードの著作権は各箇所を記述した人が留保しています。\nこのソフトウェアは無保証です。\n",
            comment: "IDS_ABOUT_DESCRIPTION")
        let modified = NSLocalizedString(
            "このアプリはサクラエディタを macOS 用に移植・改変したものです。サクラエディタの公式版ではありません。\n",
            comment: "バージョン情報（Mac 版）")
        return description + "\n" + modified + "\n" + license
    }

    /// zlib 许可证（仓库的 LICENSE 文件）
    static let license = """
        zlib License

        Copyright (C) 2018-2022, Sakura Editor Organization

        This software is provided 'as-is', without any express or implied
        warranty.  In no event will the authors be held liable for any damages
        arising from the use of this software.

        Permission is granted to anyone to use this software for any purpose,
        including commercial applications, and to alter it and redistribute it
        freely, subject to the following restrictions:

        1. The origin of this software must not be misrepresented; you must not
           claim that you wrote the original software. If you use this software
           in a product, an acknowledgment in the product documentation would be
           appreciated but is not required.
        2. Altered source versions must be plainly marked as such, and must not be
           misrepresented as being the original software.
        3. This notice may not be removed or altered from any source distribution.

        """

    private(set) var window: NSPanel?

    /// 显示（已经显示时拿到前面）
    func show() {
        let panel = window ?? makePanel()
        window = panel
        panel.center()
        panel.makeKeyAndOrderFront(nil)
    }

    /// 情報をコピー：版本的部分放到剪贴板（原版 IDC_BUTTON_COPY）
    @objc func copyInfo(_ sender: Any?) {
        Self.pasteboard.clearContents()
        Self.pasteboard.setString(Self.versionText, forType: .string)
    }

    /// 剪贴板（单元测试换成别的）
    static var pasteboard: NSPasteboard = .general

    @objc func closePanel(_ sender: Any?) {
        window?.close()
    }

    @objc private func openProjectURL(_ sender: Any?) {
        NSWorkspace.shared.open(Self.projectURL)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 460),
                            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = NSLocalizedString("バージョン情報", comment: "IDD_ABOUT")
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.setAccessibilityIdentifier("about")

        let icon = NSImageView(image: NSApp.applicationIconImage ?? NSImage())
        icon.imageScaling = .scaleProportionallyUpOrDown
        let version = NSTextField(wrappingLabelWithString: Self.versionText)
        version.isSelectable = true
        version.setAccessibilityIdentifier("version")
        let author = NSTextField(labelWithString: Self.originalAuthor)
        let copyright = NSTextField(labelWithString: Self.copyright)
        let urlCaption = NSTextField(labelWithString: "Project URL:")
        let urlButton = NSButton(title: Self.projectURL.absoluteString, target: self, action: #selector(openProjectURL(_:)))
        urlButton.isBordered = false
        urlButton.contentTintColor = .linkColor

        let scroll = NSTextView.scrollableTextView()
        if let text = scroll.documentView as? NSTextView {
            text.string = Self.descriptionText
            text.isEditable = false
            text.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
            text.setAccessibilityIdentifier("description")
        }
        scroll.borderType = .bezelBorder

        let ok = NSButton(title: NSLocalizedString("OK", comment: "IDD_ABOUT"), target: self, action: #selector(closePanel(_:)))
        ok.keyEquivalent = "\r"
        ok.setAccessibilityIdentifier("aboutOK")
        let copy = NSButton(title: NSLocalizedString("情報をコピー", comment: "IDD_ABOUT"), target: self, action: #selector(copyInfo(_:)))
        copy.setAccessibilityIdentifier("copyInfo")

        let urlRow = NSStackView(views: [urlCaption, urlButton])
        let info = NSStackView(views: [version, author, copyright, urlRow])
        info.orientation = .vertical
        info.alignment = .leading
        info.spacing = 4
        let top = NSStackView(views: [icon, info])
        top.alignment = .top
        let buttons = NSStackView(views: [ok, copy])
        let all = NSStackView(views: [top, scroll, buttons])
        all.orientation = .vertical
        all.alignment = .centerX
        all.spacing = 12
        all.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        all.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(all)
        NSLayoutConstraint.activate([
            all.topAnchor.constraint(equalTo: content.topAnchor),
            all.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            all.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            all.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            icon.widthAnchor.constraint(equalToConstant: 48),
            icon.heightAnchor.constraint(equalToConstant: 48),
            top.widthAnchor.constraint(equalTo: all.widthAnchor, constant: -32),
            scroll.widthAnchor.constraint(equalTo: all.widthAnchor, constant: -32),
            scroll.heightAnchor.constraint(equalToConstant: 220),
        ])
        panel.contentView = content
        return panel
    }
}

extension NSApplication {
    /// バージョン情報（F_ABOUT）
    @objc func showSakuraAbout(_ sender: Any?) {
        AboutPanel.shared.show()
    }
}
