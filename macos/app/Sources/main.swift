// Copyright (C) 2026, Sakura Editor Organization
//
// SPDX-License-Identifier: Zlib

import AppKit

// 不使用 Storyboard / Nib，菜单和窗口都在代码中构建，
// 以便日后按原版的 MainMenu.ini 动态生成菜单。
// 按住字母键时连续输入（与原版相同）。macOS 默认按住字母键会弹出重音字符的选择窗口，不连续输入，
// 这里只对本 App 关掉。重音字符仍可以用 Option 键输入
EditorTextView.registerInputDefaults()
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
