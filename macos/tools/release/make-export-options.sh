#!/bin/bash
# 第 37 步：生成 xcodebuild -exportArchive 用的 ExportOptions.plist。
#   make-export-options.sh app-store|developer-id 团队ID 输出文件
# app-store：Mac App Store・TestFlight 用（.pkg，Apple Distribution + Mac Installer Distribution 证书）
# developer-id：App Store 以外直接发布用（.app，Developer ID Application 证书，之后公证）
# 证书和描述文件都由 Xcode 自动管理（signingStyle automatic + -allowProvisioningUpdates + API 密钥）
set -eu
METHOD="$1"
TEAM="$2"
OUT="$3"
case "$METHOD" in
    app-store) XCODE_METHOD=app-store-connect ;;
    developer-id) XCODE_METHOD=developer-id ;;
    *) echo "不认识的方式：$METHOD（app-store 或 developer-id）" >&2; exit 2 ;;
esac
if ! [[ "$TEAM" =~ ^[A-Z0-9]{10}$ ]]; then
    echo "团队 ID 应该是 10 个大写字母或数字：$TEAM" >&2
    exit 2
fi
cat > "$OUT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>$XCODE_METHOD</string>
	<key>teamID</key>
	<string>$TEAM</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>destination</key>
	<string>export</string>
	<key>manageAppVersionAndBuildNumber</key>
	<false/>
	<key>uploadSymbols</key>
	<true/>
</dict>
</plist>
PLIST
