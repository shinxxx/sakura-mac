#!/bin/bash
# Xcode 构建 EditorBridge 框架之前运行：用 CMake 构建核心库（macos/core）的静态库。
# 计划第 24 步。由 project.yml 的 preBuildScripts 调用，也可以手动运行（参数同下面的环境变量）。
#
# 需要：CMake（brew install cmake）、Python 3（Xcode 自带）、
#       子模块 externals/Onigmo、externals/bregonig、externals/cmigemo（git submodule update --init ...）
#
# 输出：${SAKURA_CORE_BUILD_DIR}/lib*.a（sakura_core_api、sakura_core、bregonig、onigmo、cmigemo）
set -euo pipefail

# Xcode 的脚本环境里 PATH 很短，加上 Homebrew 的位置
export PATH="/opt/homebrew/bin:/usr/local/bin:${PATH}"

SRCROOT="${SRCROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO_ROOT="$(cd "${SRCROOT}/../.." && pwd)"
CONFIGURATION="${CONFIGURATION:-Debug}"
BUILD_DIR="${SAKURA_CORE_BUILD_DIR:-${REPO_ROOT}/build/xcode-core/${CONFIGURATION}}"
# Xcode 的 ARCHS 用空格分隔，CMake 用分号
ARCHS_CMAKE="$(echo "${ARCHS:-$(uname -m)}" | tr ' ' ';')"
DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-13.0}"

if ! command -v cmake > /dev/null; then
  echo "error: 找不到 cmake。请先安装：brew install cmake" >&2
  exit 1
fi
for m in Onigmo bregonig cmigemo; do
  if [ ! -e "${REPO_ROOT}/externals/${m}/.git" ]; then
    echo "error: 缺少子模块 externals/${m}。请先运行：git submodule update --init externals/Onigmo externals/bregonig externals/cmigemo" >&2
    exit 1
  fi
done

case "${CONFIGURATION}" in
  Release) CMAKE_BUILD_TYPE=Release ;;
  *)       CMAKE_BUILD_TYPE=Debug ;;
esac

# 架构或系统版本变了时重新配置
STAMP="${BUILD_DIR}/.xcode-config"
WANT="${CMAKE_BUILD_TYPE}|${ARCHS_CMAKE}|${DEPLOYMENT_TARGET}"
if [ ! -f "${BUILD_DIR}/CMakeCache.txt" ] || [ "$(cat "${STAMP}" 2>/dev/null)" != "${WANT}" ]; then
  rm -rf "${BUILD_DIR}"
  cmake -S "${REPO_ROOT}/macos/core" -B "${BUILD_DIR}" \
    -DCMAKE_BUILD_TYPE="${CMAKE_BUILD_TYPE}" \
    -DCMAKE_OSX_ARCHITECTURES="${ARCHS_CMAKE}" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET}" \
    -DSAKURA_BUILD_TESTS=OFF
  echo "${WANT}" > "${STAMP}"
fi

JOBS="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"
cmake --build "${BUILD_DIR}" --target sakura_core_api -j "${JOBS}"
