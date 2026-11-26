#!/bin/bash
# 确认 Mac 版的二进制只含 Apple 芯片（arm64）。不支持 Intel 芯片（x86_64）：2026-11-26 项目负责人决定。
# 用法：macos/tools/check-arch.sh 文件...（App 的可执行文件、框架、核心库的 .a 等）
# 每个文件打印「文件: 架构」，有不是只含 arm64 的文件、或文件不存在时返回 1。
set -u
status=0
for f in "$@"; do
    if [ ! -e "$f" ]; then
        echo "没有文件：$f"
        status=1
        continue
    fi
    archs="$(lipo -archs "$f" 2>/dev/null)"
    echo "$f: ${archs:-?}"
    if [ "$archs" != "arm64" ]; then
        echo "  ↑ 应该只含 arm64（Mac 版只支持 Apple 芯片）"
        status=1
    fi
done
exit "$status"
