# Mac 版核心库的单元测试：沿用原版 src/test/cpp/tests1 的测试代码。
# test-design_template.cpp 依赖 Windows 的模块句柄，不在 Mac 上运行。
# test-cfileext.cpp 依赖 env 的 CDocTypeManager，第 21 步加入。
# 只列出对应模块已经移植完成的测试文件。后续步骤每移植一个模块，就把相应的测试加进来。
set(SAKURA_CORE_TEST_SOURCES
  src/test/cpp/tests1/test-ccodebase.cpp
  src/test/cpp/tests1/test-cconvert.cpp
  src/test/cpp/tests1/test-cdecode.cpp
  src/test/cpp/tests1/test-cdocline.cpp                # 第 20 步
  src/test/cpp/tests1/test-cdoclinemgr.cpp             # 第 20 步
  src/test/cpp/tests1/test-ceol.cpp
  src/test/cpp/tests1/test-cfuncinfoarr.cpp            # 第 20 步
  src/test/cpp/tests1/test-charcode.cpp
  src/test/cpp/tests1/test-charset.cpp
  src/test/cpp/tests1/test-clayoutint.cpp
  src/test/cpp/tests1/test-codechecker.cpp
  src/test/cpp/tests1/test-cmemory.cpp
  src/test/cpp/tests1/test-cnative.cpp
  src/test/cpp/tests1/test-crunningtimer.cpp
  src/test/cpp/tests1/test-csearchagent.cpp            # 第 20 步。编辑窗口的部分用 mac-share-data.hpp 代替
  src/test/cpp/tests1/test-detectindentationstyle.cpp  # 第 20 步
  src/test/cpp/tests1/test-docoutline.cpp              # 第 20 步
  src/test/cpp/tests1/test-cwordparse.cpp
  src/test/cpp/tests1/test-editinfo.cpp
  src/test/cpp/tests1/test-format.cpp
  src/test/cpp/tests1/test-int2dec.cpp
  src/test/cpp/tests1/test-is_mailaddress.cpp
  src/test/cpp/tests1/test-statictype.cpp
  src/test/cpp/tests1/test-string_ex.cpp
)
list(TRANSFORM SAKURA_CORE_TEST_SOURCES PREPEND "${SAKURA_ROOT}/")
# Mac 版专用的测试（Win32 替代函数等）
list(APPEND SAKURA_CORE_TEST_SOURCES
  "${CMAKE_CURRENT_LIST_DIR}/test-mac-charcode.cpp"
  "${CMAKE_CURRENT_LIST_DIR}/test-mac-codepage.cpp"
  "${CMAKE_CURRENT_LIST_DIR}/test-mac-io.cpp"
  "${CMAKE_CURRENT_LIST_DIR}/test-mac-roundtrip.cpp"   # 第 18 步：编码往返测试，样本在 data/roundtrip/
  "${CMAKE_CURRENT_LIST_DIR}/test-mac-extmodule.cpp"   # 第 19 步：正则、Migemo、uchardet
  "${CMAKE_CURRENT_LIST_DIR}/mac-share-data.cpp"       # 第 20 步：env 移植（第 21 步）前测试用的共通设置
  "${CMAKE_CURRENT_LIST_DIR}/test-mac-doc.cpp"         # 第 20 步：文件 API、CFile、CFileLoad、撤销、差异标记、类型设置
)
