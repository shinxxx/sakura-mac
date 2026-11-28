#!/bin/bash
# 第 37 步：检查要发布的 App 是否符合 Mac App Store・TestFlight（或直接发布）的要求。
#
#   check-release.sh --adhoc        App      本机签名的 Release 构建（CI 用：不需要开发者账号）
#   check-release.sh --app-store    App.pkg  上传 TestFlight 的安装包（先展开再检查里面的 App）
#   check-release.sh --developer-id App      Developer ID 签名、公证过的 App
#
# 检查项（全部模式）：Info.plist（Bundle ID、版本、分类、出口合规、图标名）、Assets.car 里有 1024 像素的图标、
# 只含 arm64、签名有效（--deep --strict）、开启沙盒、没有临时例外（temporary-exception）、没有 get-task-allow。
# --app-store 另查：用发布证书签名、嵌入了描述文件、application-identifier 是「团队ID.BundleID」、安装包用安装包证书签名。
# --developer-id 另查：Developer ID 证书、Hardened Runtime、已公证（stapler、spctl）。
# 全部通过时返回 0，有不合格的项目时返回 1。每项打印「OK」或「NG」。
set -u -o pipefail

BUNDLE_ID="${BUNDLE_ID:-com.hanagumo.texteditor}"
MODE="${1:-}"
TARGET="${2:-}"
if [ -z "$MODE" ] || [ -z "$TARGET" ]; then
    sed -n '2,13p' "$0"
    exit 2
fi
HERE="$(cd "$(dirname "$0")" && pwd)"
NG=0
ok() { echo "OK  $*"; }
ng() { echo "NG  $*"; NG=1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

case "$MODE" in
    --adhoc|--developer-id) APP="$TARGET" ;;
    --app-store)
        PKG="$TARGET"
        if [ ! -f "$PKG" ]; then ng "没有安装包：$PKG"; exit 1; fi
        SIG="$(pkgutil --check-signature "$PKG" 2>&1)"
        if echo "$SIG" | grep -qE "3rd Party Mac Developer Installer|Mac Installer Distribution"; then
            ok "安装包的签名：$(echo "$SIG" | grep -E '^ *1\.' | head -1 | sed 's/^ *1\. *//')"
        else
            ng "安装包没有用 Mac Installer Distribution 证书签名：$(echo "$SIG" | head -3 | tr '\n' ' ')"
        fi
        pkgutil --expand-full "$PKG" "$WORK/pkg" > /dev/null
        APP="$(find "$WORK/pkg" -maxdepth 4 -name '*.app' -type d | head -1)"
        if [ -z "$APP" ]; then ng "安装包里没有 App"; exit 1; fi
        ;;
    *) echo "不认识的模式：$MODE" >&2; exit 2 ;;
esac

if [ ! -d "$APP" ]; then ng "没有 App：$APP"; exit 1; fi
PLIST="$APP/Contents/Info.plist"
pb() { /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST" 2>/dev/null; }
EXE="$APP/Contents/MacOS/$(pb CFBundleExecutable)"

# Info.plist
[ "$(pb CFBundleIdentifier)" = "$BUNDLE_ID" ] && ok "Bundle ID：$BUNDLE_ID" || ng "Bundle ID 是「$(pb CFBundleIdentifier)」，应该是 $BUNDLE_ID"
VER="$(pb CFBundleShortVersionString)"; BUILD="$(pb CFBundleVersion)"
if [[ "$VER" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] && [[ "$BUILD" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
    ok "版本：$VER（构建 $BUILD）"
else
    ng "版本号格式不对：「$VER」（构建「$BUILD」），应该是用点分隔的数字"
fi
[ -n "$(pb LSApplicationCategoryType)" ] && ok "分类：$(pb LSApplicationCategoryType)" || ng "没有 LSApplicationCategoryType（App Store 必须）"
[ "$(pb ITSAppUsesNonExemptEncryption)" = "false" ] && ok "出口合规：不使用需要申报的加密" || ng "没有 ITSAppUsesNonExemptEncryption = NO"
[ "$(pb CFBundleIconName)" = "AppIcon" ] && ok "图标名：AppIcon" || ng "Info.plist 里没有 CFBundleIconName = AppIcon"
MINOS="$(pb LSMinimumSystemVersion)"
[ -n "$MINOS" ] && ok "最低 macOS：$MINOS" || ng "没有 LSMinimumSystemVersion"

# 图标：Assets.car 里 AppIcon 有 1024 像素的（512pt @2x）
CAR="$APP/Contents/Resources/Assets.car"
if [ -f "$CAR" ] && xcrun assetutil --info "$CAR" > "$WORK/assets.json" 2>/dev/null \
    && python3 - "$WORK/assets.json" <<'PY'
import json, sys
items = json.load(open(sys.argv[1]))
sizes = {i.get("PixelWidth") for i in items if isinstance(i, dict) and i.get("Name") == "AppIcon"}
sys.exit(0 if 1024 in sizes and 16 in sizes else 1)
PY
then
    ok "图标：Assets.car 里有 16〜1024 像素的 AppIcon"
else
    ng "图标：Assets.car 里没有 1024 像素的 AppIcon"
fi

# 架构：只含 arm64
ARCH_FILES=("$EXE")
while IFS= read -r -d '' fw; do
    ARCH_FILES+=("$fw/$(basename "$fw" .framework)")
done < <(find "$APP/Contents/Frameworks" -maxdepth 1 -name '*.framework' -print0 2>/dev/null)
if "$HERE/../check-arch.sh" "${ARCH_FILES[@]}" > "$WORK/arch.log" 2>&1; then
    ok "架构：只含 arm64（${#ARCH_FILES[@]} 个文件）"
else
    ng "架构：$(tr '\n' ' ' < "$WORK/arch.log")"
fi

# 签名
if codesign --verify --deep --strict "$APP" > "$WORK/verify.log" 2>&1; then
    ok "签名有效（--deep --strict）"
else
    ng "签名无效：$(tr '\n' ' ' < "$WORK/verify.log")"
fi
codesign -d --entitlements :- "$APP" > "$WORK/ent.plist" 2>/dev/null
ent() { /usr/libexec/PlistBuddy -c "Print :$1" "$WORK/ent.plist" 2>/dev/null; }
[ "$(ent com.apple.security.app-sandbox)" = "true" ] && ok "沙盒：开启" || ng "沙盒没有开启（com.apple.security.app-sandbox）"
if grep -q "temporary-exception" "$WORK/ent.plist"; then ng "权限里有临时例外（temporary-exception），App Store 审核不通过"; else ok "权限里没有临时例外"; fi
if [ "$(ent com.apple.security.get-task-allow)" = "true" ]; then ng "权限里有 get-task-allow（调试用，不能上传）"; else ok "没有调试用的 get-task-allow"; fi
codesign -dvv "$APP" > "$WORK/sign.txt" 2>&1
AUTH="$(grep -m1 '^Authority=' "$WORK/sign.txt" | sed 's/^Authority=//')"

case "$MODE" in
    --adhoc)
        grep -q "^Signature=adhoc" "$WORK/sign.txt" && ok "本机签名（ad-hoc）" || ok "签名：${AUTH:-?}"
        ;;
    --app-store)
        if [[ "$AUTH" == "Apple Distribution:"* || "$AUTH" == "3rd Party Mac Developer Application:"* ]]; then
            ok "App 的签名证书：$AUTH"
        else
            ng "App 没有用发布证书签名：${AUTH:-没有}"
        fi
        [ -f "$APP/Contents/embedded.provisionprofile" ] && ok "嵌入了描述文件" || ng "没有 embedded.provisionprofile（TestFlight 必须）"
        TEAM="$(grep -m1 '^TeamIdentifier=' "$WORK/sign.txt" | sed 's/^TeamIdentifier=//')"
        if [ "$(ent com.apple.application-identifier)" = "$TEAM.$BUNDLE_ID" ] && [ "$(ent com.apple.developer.team-identifier)" = "$TEAM" ]; then
            ok "application-identifier：团队ID.$BUNDLE_ID"
        else
            ng "application-identifier 不对：$(ent com.apple.application-identifier)"
        fi
        ;;
    --developer-id)
        [[ "$AUTH" == "Developer ID Application:"* ]] && ok "签名证书：$AUTH" || ng "没有用 Developer ID Application 证书签名：${AUTH:-没有}"
        grep -qE "flags=.*runtime" "$WORK/sign.txt" && ok "Hardened Runtime：开启" || ng "Hardened Runtime 没有开启"
        xcrun stapler validate "$APP" > /dev/null 2>&1 && ok "公证票据已装订（stapler）" || ng "没有装订公证票据"
        if spctl -a -vv -t exec "$APP" > "$WORK/spctl.log" 2>&1 && grep -q "Notarized Developer ID" "$WORK/spctl.log"; then
            ok "Gatekeeper：允许（Notarized Developer ID）"
        else
            ng "Gatekeeper 不允许：$(tr '\n' ' ' < "$WORK/spctl.log")"
        fi
        ;;
esac

[ "$NG" = 0 ] && echo "全部合格" || echo "有不合格的项目"
exit "$NG"
