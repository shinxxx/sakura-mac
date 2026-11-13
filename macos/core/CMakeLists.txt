# Sakura Editor for Mac：核心库（libsakura_core）和单元测试
#
# 阶段 1 第 16 步起使用。在 macOS 上构建；Linux 上只能用 clang（只用于开发时快速检查，不支持 GCC）。
#
#   cmake -S macos/core -B build/mac-core -DCMAKE_BUILD_TYPE=Debug
#   cmake --build build/mac-core -j
#   ctest --test-dir build/mac-core --output-on-failure
#
# 核心库只包含已经移植到非 Windows 平台的目录，见 SAKURA_CORE_DIRS。
# 后续步骤每移植一个目录，就加到这里。
cmake_minimum_required(VERSION 3.24)
project(sakura_core_mac LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

get_filename_component(SAKURA_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../.." ABSOLUTE)
set(SAKURA_CORE "${SAKURA_ROOT}/sakura_core")
set(GEN_DIR "${CMAKE_CURRENT_BINARY_DIR}/gen")
set(STUB_DIR "${CMAKE_CURRENT_BINARY_DIR}/winsdk_stub")

# ---------------------------------------------------------------------------
# Windows SDK 头文件的空替身。原版有些头文件直接 #include <Windows.h>；
# 需要的定义已经由 macos/platform/include/StdAfx.h 提供。
# 大小写不同的写法都要有（Linux 区分大小写），所以在配置时生成，而不是放进仓库。
# ---------------------------------------------------------------------------
foreach(h Windows.h windows.h windowsx.h ntstatus.h tchar.h mbstring.h io.h process.h
          Shlwapi.h shlwapi.h shellapi.h ShlObj.h ObjIdl.h objidl.h CommCtrl.h Commctrl.h
          CommDlg.h commdlg.h Uxtheme.h uxtheme.h vsstyle.h vssym32.h HtmlHelp.h imm.h
          oaidl.h ole2.h OleAuto.h ObjBase.h Unknwn.h WTypes.h comdef.h wrl.h wrl/client.h
          bcrypt.h ShlDisp.h shobjidl.h wincodec.h WinSpool.h dwmapi.h crtdbg.h InitGuid.h
          intrin.h vadefs.h DbgHelp.h ActivScp.h)
  if(NOT EXISTS "${STUB_DIR}/${h}")
    file(WRITE "${STUB_DIR}/${h}" "// Windows SDK stub for non-Windows builds\n#pragma once\n")
  endif()
endforeach()

# ---------------------------------------------------------------------------
# Funccode_define.h / Funccode_enum.h（与 Windows 版相同，由 hsrc 生成）
# ---------------------------------------------------------------------------
find_package(Python3 REQUIRED COMPONENTS Interpreter)
set(HSRC "${SAKURA_CORE}/Funccode_x.hsrc")
set(HEADER_MAKE "${SAKURA_ROOT}/src/main/py/header_make.py")
add_custom_command(
  OUTPUT "${GEN_DIR}/Funccode_define.h" "${GEN_DIR}/Funccode_enum.h"
  COMMAND ${CMAKE_COMMAND} -E make_directory "${GEN_DIR}"
  COMMAND Python3::Interpreter "${HEADER_MAKE}" "-in=${HSRC}" "-out=${GEN_DIR}/Funccode_define.h" -mode=define
  COMMAND Python3::Interpreter "${HEADER_MAKE}" "-in=${HSRC}" "-out=${GEN_DIR}/Funccode_enum.h" -mode=enum -enum=EFunctionCode
  DEPENDS "${HSRC}" "${HEADER_MAKE}"
  COMMENT "Generating Funccode headers"
  VERBATIM)
add_custom_target(sakura_funccode DEPENDS "${GEN_DIR}/Funccode_define.h" "${GEN_DIR}/Funccode_enum.h")

# version.h（与 Windows 版相同，由 src/main/cmake/version.cmake 生成。第 21 步：共通设置里的版本号）
find_package(Git QUIET)
add_custom_command(
  OUTPUT "${GEN_DIR}/version.h"
  COMMAND ${CMAKE_COMMAND} -E make_directory "${GEN_DIR}"
  COMMAND ${CMAKE_COMMAND} -DSOURCE_DIR=${SAKURA_ROOT} -DGIT_EXECUTABLE=${GIT_EXECUTABLE}
    -P "${SAKURA_ROOT}/src/main/cmake/version.cmake"
  WORKING_DIRECTORY "${GEN_DIR}"
  DEPENDS "${SAKURA_ROOT}/src/main/cmake/version.cmake" "${SAKURA_ROOT}/src/main/cmake/version.h.in"
  COMMENT "Generating version.h"
  VERBATIM)
add_custom_target(sakura_version DEPENDS "${GEN_DIR}/version.h")

# 界面字符串：从 sakura_rc.rc 的 STRINGTABLE 生成（Windows 版 sakura.exe 内置的日文字符串）
# 第 21 步起，用户定义类型的资源（MainMenu.ini）的内容也放进同一个文件
add_custom_command(
  OUTPUT "${GEN_DIR}/sakura_rc_strings.cpp"
  COMMAND Python3::Interpreter "${SAKURA_ROOT}/macos/tools/rc_strings.py"
    "${SAKURA_CORE}/sakura_rc.rc" "${GEN_DIR}/sakura_rc_strings.cpp"
    "${SAKURA_ROOT}/src/main/resources/sakura_rc.h" "${GEN_DIR}/Funccode_define.h"
  DEPENDS "${SAKURA_ROOT}/macos/tools/rc_strings.py" "${SAKURA_CORE}/sakura_rc.rc"
    "${SAKURA_ROOT}/src/main/resources/sakura_rc.h" "${GEN_DIR}/Funccode_define.h"
    "${SAKURA_ROOT}/src/main/resources/MainMenu.ini"   # 第 21 步：用户定义资源（主菜单的默认设置）也嵌入
  VERBATIM)

# ---------------------------------------------------------------------------
# 核心库
# ---------------------------------------------------------------------------
set(SAKURA_CORE_DIRS basis charset config convert debug docplus io mem parse doc/logic types env recent grep)
# 暂不编入核心库的文件（依赖尚未移植的模块，或 Mac 版不需要）
set(SAKURA_CORE_EXCLUDE
  # Mac 版不需要
  basis/CErrorInfo.cpp            # COM 的 IErrorInfo 实现
  io/CZipFile.cpp                 # 用 Windows Shell 解压 zip，只给插件安装用；Mac 版不支持 DLL 插件
  # 第 20 步：编辑画面的部分
  types/CTypeSupport.cpp          # 按类型设置绘制颜色和字体（CGraphics）：第 28 步（Core Text 绘制）
  # 第 21 步：env 里属于界面或编辑画面的部分
  env/CAppNodeManager.cpp         # 编辑窗口的列表和切换（窗口消息）：第 26 步（窗口框架）
  env/CCodeChecker.cpp            # 保存时的字符检查（依赖编辑画面）：第 29 步（打开与保存）
  env/CReadManager.cpp            # 读入文件（依赖编辑画面的进度显示）：第 29 步
  env/CWriteManager.cpp           # 保存文件：第 29 步
  env/CHokanMgr.cpp               # 输入补全的弹出窗口：之后的界面步骤
  env/CFormatManager.cpp          # 日期、时间的格式（插入日期命令、打印页眉）：与这些命令一起移植
  env/CSakuraEnvironment.cpp      # 展开 $F 等宏参数（标题栏、打印页眉、外部命令）：与这些功能一起移植
  recent/CMRUFile.cpp             # “最近的文件”菜单：第 26 步之后的菜单步骤（历史记录本身在 recent 的其他文件）
  recent/CMRUFolder.cpp           # “最近的文件夹”菜单：同上
  recent/CMruListener.cpp         # 打开、关闭文件时更新历史：第 29 步（打开与保存）
  env/CPropertyManager.cpp        # 打开共通设置对话框：之后的设置对话框步骤
)

set(SAKURA_CORE_SOURCES)
foreach(d ${SAKURA_CORE_DIRS})
  file(GLOB files CONFIGURE_DEPENDS "${SAKURA_CORE}/${d}/*.cpp")
  list(APPEND SAKURA_CORE_SOURCES ${files})
endforeach()
foreach(x ${SAKURA_CORE_EXCLUDE})
  list(REMOVE_ITEM SAKURA_CORE_SOURCES "${SAKURA_CORE}/${x}")
endforeach()
# 核心目录之外、已经能在 Mac 上编译的单个文件（核心目录依赖它们）
set(SAKURA_CORE_EXTRA_SOURCES
  sakura_core/util/format.cpp
  sakura_core/util/tchar_convert.cpp
  sakura_core/util/string_ex.cpp
  sakura_core/util/string_ex2.cpp
  sakura_core/util/relation_tool.cpp      # 第 20 步：CSubject / CListener（文档事件的通知）
  sakura_core/window/CMainStatusBar.cpp   # 只编译 UnicodeToHex（状态栏的字符编码显示），其余是 Windows 界面
  # 第 19 步：外部模块。对应的库在上面的“第三方库”里编译
  sakura_core/extmodule/CDllHandler.cpp
  sakura_core/extmodule/CBregexpDll2.cpp
  sakura_core/extmodule/CBregexp.cpp
  sakura_core/extmodule/CUchardet.cpp     # uchardet 不内置（与 Windows 官方版相同），加载总是失败
  sakura_core/extmodule/CMigemo.cpp       # 第 21 步：用到共通设置里的 DLL 名和词典路径
  # 第 20 步：文档模型和语法类型（doc/logic、types 整个目录在上面的 SAKURA_CORE_DIRS）
  # doc 目录里只编入不依赖编辑画面的文件；CEditDoc、CDocEditor、CDocFileOperation 等是文档窗口的部分，
  # 第 26 步（窗口框架）、第 29 步（打开与保存）加入。doc/layout（排版）是第 27 步
  sakura_core/doc/CBlockComment.cpp
  sakura_core/doc/CLineComment.cpp
  sakura_core/doc/CDocTypeSetting.cpp
  sakura_core/doc/CDocReader.cpp
  sakura_core/doc/CDocFile.cpp
  sakura_core/doc/CDocOutline.cpp         # 大纲解析（各语言的解析函数在 types/CType_*.cpp）
  sakura_core/outline/CFuncInfo.cpp
  sakura_core/outline/CFuncInfoArr.cpp
  sakura_core/cmd/COpe.cpp                # 撤销/重做的操作记录
  sakura_core/cmd/COpeBlk.cpp
  sakura_core/cmd/COpeBuf.cpp
  sakura_core/agent/CSearchAgent.cpp      # 文档内的查找和替换
  sakura_core/doc/CDocListener.cpp        # 文档事件（读入、保存）的通知
  sakura_core/docplus/CModifyManager.cpp  # 行的修改标记
  sakura_core/_main/global.cpp            # 查找选项等共用定义（进程相关的部分在第 26 步）
  # 第 21 步：设置模块 env（整个目录在上面的 SAKURA_CORE_DIRS）和它用到的文件
  sakura_core/util/file.cpp               # 路径操作。Mac 版的路径分隔符是 '/'
  sakura_core/_main/CMutex.cpp            # Mac 版是进程内的命名互斥锁
  sakura_core/uiparts/CMenuDrawer.cpp     # 只编译工具栏按钮表（共通设置的工具栏项目），绘制菜单是界面的步骤
  sakura_core/macro/CSMacroMgr.cpp        # 只编译宏函数名表（按键分配的 ini 读写），宏的执行是第 45 步
  sakura_core/view/colors/CColorStrategy.cpp  # 只编译颜色名表（ini 的颜色设置），文字着色是第 28 步
  sakura_core/func/CKeyBind.cpp           # 按键分配的默认值和查找（Windows 的加速键表不用）
  sakura_core/print/CPrint.cpp            # 只编译打印设置的默认值和用纸表，打印本身在之后的打印步骤
)
list(TRANSFORM SAKURA_CORE_EXTRA_SOURCES PREPEND "${SAKURA_ROOT}/")
list(APPEND SAKURA_CORE_SOURCES ${SAKURA_CORE_EXTRA_SOURCES})

# ---------------------------------------------------------------------------
# 第三方库（第 19 步）：原版运行时加载的 DLL，Mac 版作为源码编进来。
# CDllImp 的 LoadLibraryW / GetProcAddress 由 macos/platform/src/static_modules.cpp 提供，
# 按 DLL 名找到静态链接的函数表，所以 sakura_core/extmodule 的代码不用改。
# ---------------------------------------------------------------------------
set(ONIGMO_DIR "${SAKURA_ROOT}/externals/Onigmo")
set(BREGONIG_DIR "${SAKURA_ROOT}/externals/bregonig/src")
if(NOT EXISTS "${ONIGMO_DIR}/onigmo.h" OR NOT EXISTS "${BREGONIG_DIR}/bregonig.cpp")
  message(FATAL_ERROR "缺少子模块，请先运行：git submodule update --init externals/Onigmo externals/bregonig")
endif()

# Onigmo（正则引擎，BSD 许可证）
set(ONIGMO_SOURCES regcomp regenc regerror regext regexec reggnu regparse regposerr regposix
  regsyntax regtrav regversion st
  enc/ascii enc/big5 enc/euc_jp enc/euc_kr enc/euc_tw enc/gb18030 enc/koi8_r enc/koi8_u
  enc/iso_8859_1 enc/iso_8859_2 enc/iso_8859_3 enc/iso_8859_4 enc/iso_8859_5 enc/iso_8859_6
  enc/iso_8859_7 enc/iso_8859_8 enc/iso_8859_9 enc/iso_8859_10 enc/iso_8859_11 enc/iso_8859_13
  enc/iso_8859_14 enc/iso_8859_15 enc/iso_8859_16 enc/shift_jis enc/unicode enc/utf_16be
  enc/utf_16le enc/utf_32be enc/utf_32le enc/utf_8 enc/windows_31j enc/windows_1250
  enc/windows_1251 enc/windows_1252 enc/windows_1253 enc/windows_1254 enc/windows_1257)
list(TRANSFORM ONIGMO_SOURCES PREPEND "${ONIGMO_DIR}/")
list(TRANSFORM ONIGMO_SOURCES APPEND ".c")
add_library(onigmo STATIC ${ONIGMO_SOURCES})
target_compile_definitions(onigmo PRIVATE HAVE_CONFIG_H)
target_include_directories(onigmo PRIVATE
  "${SAKURA_ROOT}/macos/thirdparty/onigmo"   # config.h
  "${ONIGMO_DIR}/enc/unicode")
target_include_directories(onigmo PUBLIC "${ONIGMO_DIR}")
target_compile_options(onigmo PRIVATE -w)

# bregonig（BREGEXP 兼容的接口，Perl 许可证：GPL 或 Artistic）。
# 原版 DLL 把每个源文件编译两次（UNICODE 版和多字节版），这里也一样，用两个 OBJECT 库
set(BREGONIG_SOURCES bregonig bsplit btrans subst sv)
list(TRANSFORM BREGONIG_SOURCES PREPEND "${BREGONIG_DIR}/")
list(TRANSFORM BREGONIG_SOURCES APPEND ".cpp")
foreach(variant unicode ansi)
  add_library(bregonig_${variant} OBJECT ${BREGONIG_SOURCES})
  set_target_properties(bregonig_${variant} PROPERTIES CXX_STANDARD 17)  # 用了 register 关键字
  target_compile_definitions(bregonig_${variant} PRIVATE
    USE_ONIGMO_6 USE_VTAB PERL_5_8_COMPAT NAMEGROUP_RIGHTMOST ONIG_EXTERN=extern
    $<$<STREQUAL:${variant},ansi>:BREGONIG_MAC_ANSI>)
  target_compile_options(bregonig_${variant} PRIVATE
    -include "${SAKURA_ROOT}/macos/thirdparty/bregonig/bregonig_mac.h" -Wno-register -w)
  target_include_directories(bregonig_${variant} PRIVATE "${ONIGMO_DIR}")
  target_include_directories(bregonig_${variant} SYSTEM PRIVATE "${STUB_DIR}")  # 空的 windows.h、tchar.h、mbstring.h
endforeach()
add_library(bregonig STATIC $<TARGET_OBJECTS:bregonig_unicode> $<TARGET_OBJECTS:bregonig_ansi>)
target_link_libraries(bregonig PUBLIC onigmo)

# C/Migemo（ローマ字で日文检索，MIT 许可证）。词典在 externals/cmigemo-dict（GPL，见 macos/docs/phase1-extmodule.md）
set(CMIGEMO_DIR "${SAKURA_ROOT}/externals/cmigemo/src")
if(NOT EXISTS "${CMIGEMO_DIR}/migemo.h")
  message(FATAL_ERROR "缺少子模块，请先运行：git submodule update --init externals/cmigemo")
endif()
add_library(cmigemo STATIC
  "${CMIGEMO_DIR}/charset.c" "${CMIGEMO_DIR}/filename.c" "${CMIGEMO_DIR}/migemo.c" "${CMIGEMO_DIR}/mnode.c"
  "${CMIGEMO_DIR}/romaji.c" "${CMIGEMO_DIR}/rxgen.c" "${CMIGEMO_DIR}/wordbuf.c" "${CMIGEMO_DIR}/wordlist.c")
target_include_directories(cmigemo PUBLIC "${CMIGEMO_DIR}")
# 原版的 extmodule/CMigemo.h 用 #include "cmigemo/migemo.h"（Windows 版由构建脚本准备头文件），
# Mac 版在生成目录里放一个转发头文件（第 21 步）
file(WRITE "${GEN_DIR}/cmigemo/migemo.h.in" "// 生成文件：转发到 C/Migemo 的头文件\n#pragma once\n#include \"${CMIGEMO_DIR}/migemo.h\"\n")
configure_file("${GEN_DIR}/cmigemo/migemo.h.in" "${GEN_DIR}/cmigemo/migemo.h" COPYONLY)
target_compile_options(cmigemo PRIVATE -w)

add_library(sakura_core STATIC
  ${SAKURA_CORE_SOURCES}
  "${SAKURA_ROOT}/macos/platform/src/win32_api.cpp"
  "${SAKURA_ROOT}/macos/platform/src/codepage.cpp"
  "${SAKURA_ROOT}/macos/platform/src/codepage_data.cpp"
  "${SAKURA_ROOT}/macos/platform/src/ui_bridge.cpp"
  "${SAKURA_ROOT}/macos/platform/src/static_modules.cpp"
  "${SAKURA_ROOT}/macos/platform/src/ole_types.cpp"      # 第 20 步：BSTR、VARIANT
  "${SAKURA_ROOT}/macos/platform/src/file_api.cpp"       # 第 20 步：CreateFileW、文件映射
  "${SAKURA_ROOT}/macos/platform/src/resources.cpp"      # 第 21 步：FindResource、LoadResource
  "${CMAKE_CURRENT_SOURCE_DIR}/src/layout_stub.cpp"      # 第 24 步：排版移植（第 27 步）前的 LogicToLayout（原来在测试里）
  "${GEN_DIR}/sakura_rc_strings.cpp")
# 代码页转换表（在 Windows 上导出，见 macos/tools/codepage_dump）。用 .incbin 嵌入
set(SAKURA_CODEPAGES_BIN "${SAKURA_ROOT}/macos/platform/data/codepages.bin")
string(REPLACE "\\" "\\\\" _cp_path "${SAKURA_CODEPAGES_BIN}")
string(REPLACE "\"" "\\\"" _cp_path "${_cp_path}")
file(WRITE "${GEN_DIR}/codepage_data_path.h.in"
  "#pragma once\n#define SAKURA_CODEPAGES_INCBIN \".incbin \\\"@_cp_path@\\\"\\n\"\n")
configure_file("${GEN_DIR}/codepage_data_path.h.in" "${GEN_DIR}/codepage_data_path.h" @ONLY)
set_source_files_properties("${SAKURA_ROOT}/macos/platform/src/codepage_data.cpp" PROPERTIES
  OBJECT_DEPENDS "${SAKURA_CODEPAGES_BIN}"
  SKIP_PRECOMPILE_HEADERS ON)
add_dependencies(sakura_core sakura_funccode sakura_version)
target_link_libraries(sakura_core PUBLIC bregonig cmigemo)
target_include_directories(sakura_core PUBLIC
  "${SAKURA_ROOT}/macos/platform/include"   # Mac 版 StdAfx.h 优先
  "${SAKURA_CORE}"
  "${SAKURA_ROOT}/src/main/cpp"
  "${SAKURA_ROOT}/src/main/resources"
  "${GEN_DIR}")
target_include_directories(sakura_core SYSTEM PUBLIC "${STUB_DIR}")
target_compile_definitions(sakura_core PUBLIC NOMINMAX $<$<CONFIG:Debug>:_DEBUG>)
if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
  # 原版代码在 MSVC 下编译，先关掉与移植无关的大量警告，只保留错误
  target_compile_options(sakura_core PRIVATE -Wno-everything)
  if(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
    target_compile_options(sakura_core PRIVATE -w)
  endif()
endif()

# ---------------------------------------------------------------------------
# 核心库的对外接口（第 22 步）。界面层只使用 include/sakura_core/SakuraCore.h
# ---------------------------------------------------------------------------
add_library(sakura_core_api STATIC "${CMAKE_CURRENT_SOURCE_DIR}/api/SakuraCore.cpp")
target_include_directories(sakura_core_api PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(sakura_core_api PRIVATE sakura_core)
add_dependencies(sakura_core_api sakura_funccode)
if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
  target_compile_options(sakura_core_api PRIVATE -Wno-everything)   # 原版的头文件有大量警告
endif()

# 接口头文件不引用任何平台头文件的检查：包含路径只有 include/，
# 没有 macos/platform、sakura_core、Windows SDK 的替身，并且打开全部警告、警告当作错误
add_library(sakura_core_api_header_check OBJECT "${CMAKE_CURRENT_SOURCE_DIR}/api/header_check.cpp")
target_include_directories(sakura_core_api_header_check PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/include")
if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
  target_compile_options(sakura_core_api_header_check PRIVATE -Wall -Wextra -Wpedantic -Werror)
endif()
add_dependencies(sakura_core_api sakura_core_api_header_check)

# ---------------------------------------------------------------------------
# 单元测试（GoogleTest）
# ---------------------------------------------------------------------------
option(SAKURA_BUILD_TESTS "Build unit tests" ON)
if(SAKURA_BUILD_TESTS)
  include(FetchContent)
  FetchContent_Declare(googletest
    URL https://github.com/google/googletest/releases/download/v1.17.0/googletest-1.17.0.tar.gz
    URL_HASH SHA256=65fab701d9829d38cb77c14acdc431d2108bfdbf8979e40eb8ae567edf10b27c
    DOWNLOAD_EXTRACT_TIMESTAMP TRUE)
  set(INSTALL_GTEST OFF CACHE BOOL "" FORCE)
  FetchContent_MakeAvailable(googletest)

  include("${CMAKE_CURRENT_SOURCE_DIR}/tests/tests.cmake")
  add_executable(sakura_core_tests ${SAKURA_CORE_TEST_SOURCES})
  target_include_directories(sakura_core_tests PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/tests"          # Mac 版 pch.h 优先
    "${SAKURA_ROOT}/src/test/cpp/tests1"         # 第 21 步：原版测试的 env/ShareDataTestSuite.hpp
    "${SAKURA_ROOT}/src/test/resources")
  target_link_libraries(sakura_core_tests PRIVATE sakura_core sakura_core_api GTest::gmock_main)
  # Migemo 的测试用词典（与原版测试相同，externals/cmigemo-dict 的 zip）
  set(MIGEMO_DICT_DIR "${CMAKE_CURRENT_BINARY_DIR}/migemo-dict")
  if(NOT EXISTS "${MIGEMO_DICT_DIR}/utf-8/migemo-dict")
    file(ARCHIVE_EXTRACT INPUT "${SAKURA_ROOT}/externals/cmigemo-dict/cmigemo-dict-utf-8.zip" DESTINATION "${MIGEMO_DICT_DIR}")
  endif()
  if(NOT EXISTS "${MIGEMO_DICT_DIR}/cp932/migemo-dict")   # 第 21 步：Shift_JIS 的词典（原版 CMigemoTest.test003）
    file(ARCHIVE_EXTRACT INPUT "${SAKURA_ROOT}/externals/cmigemo-dict/cmigemo-dict-cp932.zip" DESTINATION "${MIGEMO_DICT_DIR}")
  endif()
  target_compile_definitions(sakura_core_tests PRIVATE
    SAKURA_ROUNDTRIP_DATA_DIR="${CMAKE_CURRENT_SOURCE_DIR}/tests/data/roundtrip"
    SAKURA_MIGEMO_DICT_DIR="${MIGEMO_DICT_DIR}"
    SAKURA_ROOT_DIR="${SAKURA_ROOT}")
  # 与 MSVC 的预编译头（/Yu"pch.h"）一样，让 pch.h 先于测试文件里的其他头文件
  target_precompile_headers(sakura_core_tests PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/tests/pch.h")
  if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
    target_compile_options(sakura_core_tests PRIVATE -w)
  endif()
  enable_testing()
  # 第 24 步：与 App 一样只链接核心库接口（不链接测试代码），确认没有缺少的函数
  add_executable(sakura_core_api_link_check "${CMAKE_CURRENT_SOURCE_DIR}/tests/core-api-link-check.cpp")
  target_link_libraries(sakura_core_api_link_check PRIVATE sakura_core_api)
  add_test(NAME CoreApiLinkCheck COMMAND sakura_core_api_link_check)
  include(GoogleTest)
  gtest_discover_tests(sakura_core_tests DISCOVERY_MODE PRE_TEST)
endif()
