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
  "${CMAKE_CURRENT_LIST_DIR}/mac-layout-stub.cpp"      # 第 20 步：排版移植（第 27 步）前的 LogicToLayout
  "${CMAKE_CURRENT_LIST_DIR}/test-mac-env.cpp"         # 第 21 步：设置模块（ini 往返、路径、互斥锁、资源等）
  "${CMAKE_CURRENT_LIST_DIR}/mac-test-home.cpp"        # 第 21 步：测试时把 HOME 换成临时文件夹（不碰真正的 sakura.ini）
  "${CMAKE_CURRENT_LIST_DIR}/test-mac-core-api.cpp"    # 第 22 步：核心库的对外接口（打开、编辑、保存、查找、命令）
)
