#!/bin/bash
# 第 37 步：在 Mac 上签名、打包、上传 TestFlight（或做公证过的直接发布版）。只编 arm64。
#
#   macos/tools/release/release.sh                    App Store 用：归档 → 导出 .pkg → 检查 → 上传 → 等处理完 → 内部测试组
#   macos/tools/release/release.sh --no-upload        只做到检查（不上传）
#   macos/tools/release/release.sh --developer-id     App Store 以外直接发布用：Developer ID 签名 → 公证 → 装订 → 检查 → .zip
#   macos/tools/release/release.sh --register         只注册 Bundle ID（第一次，在 App Store Connect 建 App 记录之前）
#
# 设置：~/.config/sakura-mac/signing.env（格式见同目录的 signing.env.example。不放进仓库）。
# 证书和描述文件由 Xcode 自动管理（-allowProvisioningUpdates + App Store Connect API 密钥），不用 Apple ID 的密码。
# 结果放在 macos/app/build/release/<时间>/（summary.txt、日志、.xcarchive、.pkg 或 .zip）。
# 构建号默认是「年月日.时分」（每次上传必须比上次大），可用环境变量 BUILD_NUMBER 指定。
set -u -o pipefail

MODE=app-store
UPLOAD=1
REGISTER_ONLY=0
for arg in "$@"; do
    case "$arg" in
        --developer-id) MODE=developer-id ;;
        --no-upload) UPLOAD=0 ;;
        --register) REGISTER_ONLY=1 ;;
        -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
        *) echo "未知的参数：$arg" >&2; exit 2 ;;
    esac
done

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
ENV_FILE="${SIGNING_ENV:-$HOME/.config/sakura-mac/signing.env}"
if [ ! -f "$ENV_FILE" ]; then
    echo "没有设置文件 $ENV_FILE（参考 $HERE/signing.env.example）" >&2
    exit 1
fi
# shellcheck disable=SC1090
set -a; . "$ENV_FILE"; set +a
for v in TEAM_ID ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_PATH; do
    if [ -z "${!v:-}" ]; then echo "$ENV_FILE 里没有 $v" >&2; exit 1; fi
done
ASC_KEY_PATH="${ASC_KEY_PATH/#\~/$HOME}"
export ASC_KEY_PATH
if [ ! -f "$ASC_KEY_PATH" ]; then echo "没有 API 密钥文件：$ASC_KEY_PATH" >&2; exit 1; fi

BUNDLE_ID="$(sed -n 's/^PRODUCT_BUNDLE_IDENTIFIER *= *//p' "$ROOT/macos/app/Config/App.xcconfig" | tr -d ' ')"
APP_NAME="$(sed -n 's/^APP_DISPLAY_NAME *= *//p' "$ROOT/macos/app/Config/App.xcconfig")"
export BUNDLE_ID

if [ "$REGISTER_ONLY" = 1 ]; then
    python3 "$HERE/asc.py" register-bundle-id "$BUNDLE_ID" "$APP_NAME"
    exit $?
fi

# 开发者目录指向 Command Line Tools 时改用 /Applications 里的 Xcode（不改系统设置）
if [ -z "${DEVELOPER_DIR:-}" ] && ! xcodebuild -version > /dev/null 2>&1; then
    XCODE=$(ls -d /Applications/Xcode*.app 2>/dev/null | head -1)
    [ -n "$XCODE" ] && export DEVELOPER_DIR="$XCODE/Contents/Developer"
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d.%H%M)}"
OUT="$ROOT/macos/app/build/release/$STAMP"
mkdir -p "$OUT"
SUMMARY="$OUT/summary.txt"
say() { echo "$*" | tee -a "$SUMMARY"; }
fail() { say "失败：$*"; say "详细：$OUT"; exit 1; }

AUTH=(-allowProvisioningUpdates
    -authenticationKeyPath "$ASC_KEY_PATH"
    -authenticationKeyID "$ASC_KEY_ID"
    -authenticationKeyIssuerID "$ASC_ISSUER_ID")

say "== $APP_NAME（$BUNDLE_ID）构建 $BUILD_NUMBER，方式：$MODE =="

cd "$ROOT"
git submodule update --init externals/Onigmo externals/bregonig externals/cmigemo > /dev/null
cd "$ROOT/macos/app"
xcodegen generate --quiet || fail "xcodegen generate"

# 1. 归档（Release，arm64）
ARCHIVE="$OUT/SakuraMac.xcarchive"
say "归档中…"
if ! xcodebuild -project SakuraMac.xcodeproj -scheme SakuraMac -configuration Release \
    -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" \
    DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_STYLE=Automatic CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    "${AUTH[@]}" archive > "$OUT/archive.log" 2>&1; then
    grep -E "error:" "$OUT/archive.log" | head -20 | tee -a "$SUMMARY"
    fail "归档（$OUT/archive.log）"
fi
say "归档：完成"

# 2. 导出（证书和描述文件由 Xcode 自动准备）
"$HERE/make-export-options.sh" "$MODE" "$TEAM_ID" "$OUT/ExportOptions.plist" || fail "ExportOptions.plist"
say "导出中…"
if ! xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$OUT/export" \
    -exportOptionsPlist "$OUT/ExportOptions.plist" "${AUTH[@]}" > "$OUT/export.log" 2>&1; then
    grep -E "error:|Error " "$OUT/export.log" | head -20 | tee -a "$SUMMARY"
    if grep -q 'No signing certificate "Developer ID Application"' "$OUT/export.log"; then
        # Developer ID 证书只能由账户持有人建，API 密钥用不了云端管理的 Developer ID 证书
        say "钥匙串里没有 Developer ID Application 证书：在 Xcode →「设置」→「Accounts」→ 选团队 →「Manage Certificates…」"
        say "→ 左下角「+」→「Developer ID Application」建一次（证书和私钥放进钥匙串），然后再运行"
    fi
    fail "导出（$OUT/export.log）"
fi

if [ "$MODE" = app-store ]; then
    PKG="$(find "$OUT/export" -maxdepth 1 -name '*.pkg' | head -1)"
    [ -n "$PKG" ] || fail "导出的结果里没有 .pkg"
    say "导出：$(basename "$PKG")"
    say ""
    say "== 检查 =="
    "$HERE/check-release.sh" --app-store "$PKG" | tee -a "$SUMMARY" || fail "检查不合格"
    if [ "$UPLOAD" = 0 ]; then
        say ""
        say "没有上传（--no-upload）：$PKG"
        exit 0
    fi
    say ""
    say "== 上传 TestFlight =="
    python3 "$HERE/asc.py" app-id "$BUNDLE_ID" > "$OUT/app-id.txt" \
        || fail "App Store Connect 里还没有 App 记录（$(cat "$OUT/app-id.txt")）"
    # altool 在 ~/.appstoreconnect/private_keys/ 里找 AuthKey_<ID>.p8
    if ! xcrun altool --upload-app -f "$PKG" -t macos \
        --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID" > "$OUT/upload.log" 2>&1; then
        grep -iE "error|fail" "$OUT/upload.log" | head -20 | tee -a "$SUMMARY"
        fail "上传（$OUT/upload.log）"
    fi
    say "上传：完成"
    say "等 App Store Connect 处理（一般 5〜30 分钟）…"
    python3 "$HERE/asc.py" wait-build "$BUNDLE_ID" "$BUILD_NUMBER" "${WAIT_SECONDS:-3600}" | tee -a "$SUMMARY" \
        || fail "构建没有处理成功"
    python3 "$HERE/asc.py" setup-internal-testing "$BUNDLE_ID" | tee -a "$SUMMARY" || fail "内部测试组"
    say ""
    say "完成：构建 $BUILD_NUMBER 已经可以用 TestFlight 安装"
else
    APP="$(find "$OUT/export" -maxdepth 1 -name '*.app' | head -1)"
    [ -n "$APP" ] || fail "导出的结果里没有 .app"
    say ""
    say "== 公证 =="
    ZIP="$OUT/notarize.zip"
    ditto -c -k --keepParent "$APP" "$ZIP"
    if ! xcrun notarytool submit "$ZIP" --key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" \
        --wait --output-format json > "$OUT/notarize.json" 2> "$OUT/notarize.err"; then
        cat "$OUT/notarize.err" | tee -a "$SUMMARY"
    fi
    STATUS="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("status",""))' "$OUT/notarize.json" 2>/dev/null)"
    SUB_ID="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("id",""))' "$OUT/notarize.json" 2>/dev/null)"
    if [ "$STATUS" != "Accepted" ]; then
        [ -n "$SUB_ID" ] && xcrun notarytool log "$SUB_ID" --key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" \
            --issuer "$ASC_ISSUER_ID" "$OUT/notarize-log.json" > /dev/null 2>&1
        fail "公证没有通过：${STATUS:-?}（$OUT/notarize-log.json）"
    fi
    say "公证：通过"
    xcrun stapler staple "$APP" > "$OUT/staple.log" 2>&1 || fail "装订（$OUT/staple.log）"
    say ""
    say "== 检查 =="
    "$HERE/check-release.sh" --developer-id "$APP" | tee -a "$SUMMARY" || fail "检查不合格"
    FINAL="$OUT/$(basename "$APP" .app)-$BUILD_NUMBER.zip"
    ditto -c -k --keepParent "$APP" "$FINAL"
    say ""
    say "完成：$FINAL"
fi
