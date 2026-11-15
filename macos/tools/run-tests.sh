#!/bin/bash
# 在 Mac 上一次跑完 Mac 版的全部自动测试，只打印结果摘要。
#
#   macos/tools/run-tests.sh            全部：核心库测试 + App 单元测试 + 界面测试
#   macos/tools/run-tests.sh --no-ui    不跑界面测试（界面测试会真的打开窗口、操作键盘）
#
# 结果放在 macos/app/build/test-results/<时间>/：
#   summary.txt     结果摘要
#   *.xcresult      Xcode 的完整结果（双击用 Xcode 打开）
#   failures/       失败的界面测试当时的截图
# 全部通过时返回 0，有失败时返回 1。
set -u -o pipefail

RUN_UI=1
for arg in "$@"; do
    case "$arg" in
        --no-ui) RUN_UI=0 ;;
        *) echo "未知的参数：$arg" >&2; exit 2 ;;
    esac
done

# 开发者目录指向 Command Line Tools 时 xcodebuild 不能用：这次运行改用 /Applications 里的 Xcode（不改系统设置）
if [ -z "${DEVELOPER_DIR:-}" ] && ! xcodebuild -version > /dev/null 2>&1; then
    XCODE=$(ls -d /Applications/Xcode*.app 2>/dev/null | head -1)
    if [ -n "$XCODE" ]; then
        export DEVELOPER_DIR="$XCODE/Contents/Developer"
        echo "使用 $XCODE（想固定下来：sudo xcode-select -s $DEVELOPER_DIR）"
    fi
fi

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="$ROOT/macos/app/build/test-results/$STAMP"
mkdir -p "$OUT"
SUMMARY="$OUT/summary.txt"
FAILED=0

say() { echo "$*" | tee -a "$SUMMARY"; }

cd "$ROOT"
git submodule update --init externals/Onigmo externals/bregonig externals/cmigemo > /dev/null

# 1. 核心库（C++）的测试
say "== 核心库测试 =="
if cmake -S macos/core -B build/mac-core > "$OUT/core-configure.log" 2>&1 \
    && cmake --build build/mac-core -j8 > "$OUT/core-build.log" 2>&1; then
    if ctest --test-dir build/mac-core -j8 > "$OUT/core-tests.log" 2>&1; then
        say "$(grep -E 'tests passed' "$OUT/core-tests.log")"
    else
        FAILED=1
        grep -E 'tests passed|\*\*\*Failed|Failed  ' "$OUT/core-tests.log" | tee -a "$SUMMARY"
    fi
else
    FAILED=1
    say "核心库编译失败，详细见 $OUT/core-build.log"
    tail -20 "$OUT/core-build.log" | tee -a "$SUMMARY"
fi

# 2. App 的测试（单元测试 + 界面测试）
cd "$ROOT/macos/app"
if ! command -v xcodegen > /dev/null; then
    say "没有 xcodegen，请先运行：brew install xcodegen"
    exit 1
fi
xcodegen generate --quiet

ONLY=(-only-testing:SakuraMacTests)
TITLE="App 单元测试"
if [ "$RUN_UI" = 1 ]; then
    ONLY+=(-only-testing:SakuraMacUITests)
    TITLE="App 单元测试 + 界面测试"
    # 沙盒外的文件重启后从历史打开的界面测试（第 31 步）只在这里运行。
    # xcodebuild 把 TEST_RUNNER_ 开头的环境变量去掉前缀传给测试
    export TEST_RUNNER_SAKURA_SANDBOX_TEST=1
fi
say ""
say "== $TITLE =="
RESULT="$OUT/app.xcresult"
# 不需要开发者账号：在本机签名（ad-hoc）就能运行
if ! xcodebuild \
    -project SakuraMac.xcodeproj \
    -scheme SakuraMac \
    -configuration Debug \
    -derivedDataPath build \
    -resultBundlePath "$RESULT" \
    CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
    "${ONLY[@]}" \
    test > "$OUT/app-tests.log" 2>&1; then
    FAILED=1
fi

if [ -d "$RESULT" ]; then
    # 摘要（Xcode 16 以后的 xcresulttool；旧版本没有这个命令时只看日志）
    if xcrun xcresulttool get test-results summary --path "$RESULT" > "$OUT/app-summary.json" 2>/dev/null; then
        python3 - "$OUT/app-summary.json" <<'PY' | tee -a "$SUMMARY"
import json, sys
s = json.load(open(sys.argv[1]))
print(f"结果：{s.get('result')}  通过 {s.get('passedTests', 0)}，失败 {s.get('failedTests', 0)}，跳过 {s.get('skippedTests', 0)}")
for f in s.get("testFailures", []):
    print(f"  失败：{f.get('targetName', '')} {f.get('testName', '')}")
    print(f"        {f.get('failureText', '')}")
PY
    else
        grep -E 'Executed [0-9]+ tests|error:|failed \(' "$OUT/app-tests.log" | tail -30 | tee -a "$SUMMARY"
    fi
    # 失败时的截图
    if xcrun xcresulttool export attachments --path "$RESULT" --output-path "$OUT/failures" --only-failures > /dev/null 2>&1; then
        SHOTS=$(find "$OUT/failures" -type f \( -name '*.png' -o -name '*.jpg' -o -name '*.heic' \) 2>/dev/null | wc -l | tr -d ' ')
        [ "$SHOTS" != 0 ] && say "失败时的截图：$OUT/failures（$SHOTS 张）"
    fi
else
    say "App 的测试没有运行起来（多半是编译失败），日志的最后部分："
    grep -E 'error:' "$OUT/app-tests.log" | head -20 | tee -a "$SUMMARY"
    tail -15 "$OUT/app-tests.log" | tee -a "$SUMMARY"
fi

say ""
if [ "$FAILED" = 0 ]; then
    say "全部通过"
else
    say "有失败，详细结果：$OUT"
fi
exit "$FAILED"
