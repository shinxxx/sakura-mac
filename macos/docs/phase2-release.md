# 签名与 TestFlight（第 37 步）

用开发者账号（2026-11-28 注册的个人账号）给 Mac 版签名，上传到 App Store Connect，用 TestFlight 安装。
另外可以做 Developer ID 签名、公证（notarization）过的版本，在 App Store 以外直接发布。只编 Apple 芯片（arm64）。

## 一次性的准备（在 App Store Connect 和 Mac 上）

1. App Store Connect 的 API 密钥（「ユーザとアクセス」→「統合」→「App Store Connect API」→ チームキー，アクセス：Admin）。
   下载的 `AuthKey_<密钥ID>.p8` 放在 `~/.appstoreconnect/private_keys/`（仓库外，权限 600）。
2. `~/.config/sakura-mac/signing.env`：团队 ID、密钥 ID、Issuer ID、密钥的路径（格式见 `macos/tools/release/signing.env.example`）。
   这些只是编号；密钥本身不放进仓库，也不放进 GitHub Secrets。
3. 注册 Bundle ID：`macos/tools/release/release.sh --register`（API 注册 macOS 的 `com.hanagumo.texteditor`）。
4. 在 App Store Connect 建 App 的记录（「マイ App」→「＋」→「新規 App」。API 不能建，只能在网页上）。

App Store 用的证书（Apple Distribution、Mac Installer Distribution）和描述文件由 Xcode 自动准备
（`-allowProvisioningUpdates` + API 密钥，云端管理的证书），不用在钥匙串里手动建，也不用 Apple ID 的密码。

Developer ID Application 证书只能由账户持有人建，API 密钥用不了云端管理的 Developer ID 证书
（2026-11-28 实测：`Cloud signing permission error`）。直接发布（`--developer-id`）之前，在 Xcode 里建一次：
「设置」→「Accounts」→ 选团队 →「Manage Certificates…」→ 左下角「+」→「Developer ID Application」。

## 发布

```sh
macos/tools/release/release.sh                 # TestFlight：归档 → 导出 .pkg → 检查 → 上传 → 等处理完 → 内部测试组
macos/tools/release/release.sh --no-upload     # 只做到检查
macos/tools/release/release.sh --developer-id  # 直接发布用：Developer ID 签名 → 公证 → 装订 → 检查 → .zip
```

- 构建号默认是「年月日.时分」（每次上传必须比上次大）；版本号是 `Config/App.xcconfig` 的 `MARKETING_VERSION`。
- 上传用 `xcrun altool --upload-app`，之后用 App Store Connect API 等构建处理完（`VALID`），
  再建内部测试组「Sakura 内部テスト」（所有构建自动可用），把团队的成员加为测试者。测试者在 Mac 的 TestFlight App 里安装。
- 结果在 `macos/app/build/release/<时间>/`（`summary.txt`、各阶段的日志、`.xcarchive`、`.pkg` 或 `.zip`）。

## 自动检查（`macos/tools/release/check-release.sh`）

| 检查 | CI（`--adhoc`，本机签名的 Release） | Mac 上发布时（`--app-store` / `--developer-id`） |
|---|---|---|
| Info.plist：Bundle ID、版本号格式、分类、出口合规（`ITSAppUsesNonExemptEncryption = NO`）、图标名、最低 macOS | ✓ | ✓ |
| `Assets.car` 里有 16〜1024 像素的 AppIcon | ✓ | ✓ |
| 只含 arm64（App 和框架） | ✓ | ✓ |
| 签名有效（`codesign --verify --deep --strict`） | ✓ | ✓ |
| 沙盒开启、没有临时例外、没有 `get-task-allow` | ✓ | ✓ |
| 发布证书、嵌入描述文件、`application-identifier`、安装包证书 | | `--app-store` |
| Developer ID 证书、Hardened Runtime、公证票据、Gatekeeper | | `--developer-id` |

CI 另外检查：图标与生成结果相同（`make_app_icon.py --check`）、`asc.py` 的 JWT 签名（`test_asc.py`，临时密钥）、
ExportOptions.plist 的格式、输入法工具能编译。

## 图标

Mac App Store 要求 1024×1024 的图标。原版只有 32×32、16×16 的点阵图标（`src/main/resources/images/icon_std.ico`），
所以 `macos/tools/icon/make_app_icon.py` 把 32×32 的图案按整数倍（20 倍）放大，保持点阵的样子，
放在 macOS 图标规格的圆角方块（1024 里 824×824）上，生成 `macos/app/Resources/Assets.xcassets/AppIcon.appiconset`。
名字和图标是否沿用原版，在第 53 步之前联系上游时一起确认（第 3 步）；要换的话只改这个脚本的输入。

## 不放进 CI 的部分

发布证书签名、上传、公证都需要 API 密钥，目前只在 Mac 上运行（2026-11-28 决定：密钥不放进 GitHub Secrets，
CI 不能每次都新建证书）。以后要在 CI 上自动上传时，把 `signing.env` 的内容和 `.p8` 放进 Secrets，
在 CI 里用 `release.sh` 即可（需要先得到项目负责人同意）。
