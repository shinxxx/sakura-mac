# Mac 版核心库的单元测试：沿用原版 src/test/cpp/tests1 的测试代码。
# test-design_template.cpp 依赖 Windows 的模块句柄，不在 Mac 上运行。
# 只列出对应模块已经移植完成的测试文件。后续步骤每移植一个模块，就把相应的测试加进来。
set(SAKURA_CORE_TEST_SOURCES
  src/test/cpp/tests1/test-ccodebase.cpp
  src/test/cpp/tests1/test-cconvert.cpp
  src/test/cpp/tests1/test-cdecode.cpp
  src/test/cpp/tests1/test-cdoctypemanager.cpp         # 第 21 步
  src/test/cpp/tests1/test-cdocline.cpp                # 第 20 步
  src/test/cpp/tests1/test-cdoclinemgr.cpp             # 第 20 步
  src/test/cpp/tests1/test-ceol.cpp
  src/test/cpp/tests1/test-cfileext.cpp                # 第 21 步
  src/test/cpp/tests1/test-cfuncinfoarr.cpp            # 第 20 步
  src/test/cpp/tests1/test-charcode.cpp
  src/test/cpp/tests1/test-charset.cpp
  src/test/cpp/tests1/test-clayoutint.cpp
  src/test/cpp/tests1/test-codechecker.cpp
  src/test/cpp/tests1/test-cmemory.cpp
  src/test/cpp/tests1/test-cnative.cpp
  src/test/cpp/tests1/test-cprofile.cpp                # 第 21 步
  src/test/cpp/tests1/test-crunningtimer.cpp
  src/test/cpp/tests1/test-csearchagent.cpp            # 第 20 步。编辑窗口的部分用 mac-share-data.hpp 代替
  src/test/cpp/tests1/test-detectindentationstyle.cpp  # 第 20 步
  src/test/cpp/tests1/test-docoutline.cpp              # 第 20 步
  src/test/cpp/tests1/test-cwordparse.cpp
  src/test/cpp/tests1/test-editinfo.cpp
  src/test/cpp/tests1/test-format.cpp
  src/test/cpp/tests1/test-grepmessageformat.cpp       # 第 21 步
  src/test/cpp/tests1/test-cgrepenumkeys.cpp           # 第 43 步：Grep 的对象文件模式（Windows 的绝对路径换成 Mac 的）
  src/test/cpp/tests1/test-grepenum.cpp                # 第 43 步：Grep 的文件枚举（FindFirstFile 的 Mac 版）
  src/test/cpp/tests1/test-grep-exclude-regex.cpp      # 第 43 步：除外ファイル 的正規表現（一时フォルダー是 mac-grep-temp-folder.hpp）
  src/test/cpp/tests1/test-grepinfo.cpp                # 第 43 步：GrepInfo（CCommandLine、CDlgGrep 的部分只在 Windows 版）
  src/test/cpp/tests1/test-int2dec.cpp
  src/test/cpp/tests1/test-is_mailaddress.cpp
  src/test/cpp/tests1/test-statictype.cpp
  src/test/cpp/tests1/test-string_ex.cpp
  src/test/cpp/tests1/env/ShareDataTestSuite.cpp       # 第 21 步：测试用的共通设置（CShareData::InitShareData，与原版相同）
)
list(TRANSFORM SAKURA_CORE_TEST_SOURCES PREPEND "${SAKURA_ROOT}/")
# Mac 版专用的测试（Win32 替代函数等）
list(APPEND SAKURA_CORE_TEST_SOURCES
  "${CMAKE_CURRENT_LIST_DIR}/test-mac-charcode.cpp"
  "${CMAKE_CURRENT_LIST_DIR}/test-mac-codepage.cpp"
  "${CMAKE_CURRENT_LIST_DIR}/test-mac-io.cpp"
  "${CMAKE_CURRENT_LIST_DIR}/test-mac-roundtrip.cpp"   # 第 18 步：编码往返测试，样本在 data/roundtrip/
  "${CMAKE_CURRENT_LIST_DIR}/test-mac-extmodule.cpp"   # 第 19 步：正则、Migemo、uchardet
  "${CMAKE_CURRENT_LIST_DIR}/test-mac-doc.cpp"         # 第 20 步：文件 API、CFile、CFileLoad、撤销、差异标记、类型设置
  "${CMAKE_CURRENT_LIST_DIR}/test-mac-env.cpp"         # 第 21 步：设置模块（ini 往返、路径、互斥锁、资源等）
  "${CMAKE_CURRENT_LIST_DIR}/mac-test-home.cpp"        # 第 21 步：测试时把 HOME 换成临时文件夹（不碰真正的 sakura.ini）
  "${CMAKE_CURRENT_LIST_DIR}/test-mac-core-api.cpp"    # 第 22 步：核心库的对外接口（打开、编辑、保存、查找、命令）
  "${CMAKE_CURRENT_LIST_DIR}/test-mac-layout.cpp"      # 第 27 步：排版（换行位置、TAB、禁则、位置换算、编辑后的排版）
  "${CMAKE_CURRENT_LIST_DIR}/test-mac-view.cpp"        # 第 28 步：编辑画面的颜色、変更行
  "${CMAKE_CURRENT_LIST_DIR}/test-mac-edit.cpp"        # 第 29 步：基本编辑（矩形、缩进、复制）
  "${CMAKE_CURRENT_LIST_DIR}/test-mac-save.cpp"        # 第 30 步：打开与保存（编码列表、BOM、保存前的检查）
  "${CMAKE_CURRENT_LIST_DIR}/test-mac-recent.cpp"      # 第 31 步：最近使ったファイル・フォルダー、前回の文字コード、カーソル位置復元
  "${CMAKE_CURRENT_LIST_DIR}/test-mac-search.cpp"      # 第 32 步：検索・置換・すべて置換・指定行へジャンプ、検索文字列の色、検索の設定と履歴
  "${CMAKE_CURRENT_LIST_DIR}/test-mac-syntax-color.cpp" # 第 33 步：语法颜色（各内置类型的色分け）
  "${CMAKE_CURRENT_LIST_DIR}/test-mac-menu.cpp"         # 第 34 步：主菜单、按键分配
  "${CMAKE_CURRENT_LIST_DIR}/test-mac-cursor.cpp"       # 第 34 步：光标移动的目标
  "${CMAKE_CURRENT_LIST_DIR}/test-mac-mode.cpp"         # 第 34 步：文件、模式、设定的命令
  "${CMAKE_CURRENT_LIST_DIR}/test-mac-import.cpp"       # 第 35 步：导入 Windows 版的设置
  "${CMAKE_CURRENT_LIST_DIR}/test-mac-perf.cpp"         # 第 36 步：大文件、超长行的性能
  "${CMAKE_CURRENT_LIST_DIR}/test-mac-common-settings.cpp"  # 第 39 步：共通設定的读写
  "${CMAKE_CURRENT_LIST_DIR}/test-mac-type-settings.cpp"    # 第 40 步：タイプ別設定的读写、打开着的文档跟着变
  "${CMAKE_CURRENT_LIST_DIR}/test-mac-command-settings.cpp" # 第 41 步：キー割り当て・メインメニュー・ツールバー・カスタムメニュー
  "${CMAKE_CURRENT_LIST_DIR}/test-mac-outline.cpp"          # 第 42 步：アウトライン解析（样本在 data/outline/，与 Windows 版的结果比较）
  "${CMAKE_CURRENT_LIST_DIR}/test-mac-grep.cpp"             # 第 43 步：Grep・Grep置換（原版 test-grep-cmdline.cpp 移到 Mac 版）
  "${CMAKE_CURRENT_LIST_DIR}/test-mac-filetree.cpp"         # 第 43 步：ファイルツリー
  "${CMAKE_CURRENT_LIST_DIR}/test-mac-edit-support.cpp"     # 第 44 步：編集支援（対括弧、ブックマーク、差分、補完、タグ）
  "${CMAKE_CURRENT_LIST_DIR}/test-mac-macro.cpp"           # 第 45 步：マクロ（関数表、キーマクロの読み書き、JScript の前処理、ExpandParameter、Cookie）
  "${CMAKE_CURRENT_LIST_DIR}/test-mac-backup.cpp"          # 第 46 步：バックアップ（ファイル名の書式、作成、連番の世代、確認。data/backup/ は Windows 版の結果と比較）
  "${CMAKE_CURRENT_LIST_DIR}/test-mac-print.cpp"           # 第 47 步：印刷（印刷ページ設定、用紙、印刷用の排版、ヘッダー・フッター、行番号。data/print/ は Windows 版の PDF と比較）
  "${CMAKE_CURRENT_LIST_DIR}/test-mac-l10n.cpp"            # 第 48 步：界面本地化（各語言の文字列表、言語の切り替え）
  "${CMAKE_CURRENT_LIST_DIR}/test-mac-help.cpp"            # 第 49 步：ヘルプ（機能の話題番号、原版のヘルプにページがある）
  "${CMAKE_CURRENT_LIST_DIR}/test-mac-statusbar.cpp"       # 第 38 步：ステータスバー（行・桁、カーソル位置の文字コード、ShowCodeBox）
)
