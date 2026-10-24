# 构建检查与内部测试包

当前目标是 Mac App Store 首发，尚未配置 Apple Developer 会员与分发身份。以下工具不登录账户、不读取私钥、不签名、不上传，也不创建 tag 或 GitHub Release。CI 产物只用于内部验证。

从仓库根目录运行，依赖 Python 3.9+；打包使用 macOS 自带的 `ditto`。签名预检额外使用 `codesign`。

```sh
# 只检查源码；明确不代表检查过构建产物
python3 scripts/validate-release.py --source-only

# 完整检查现有 universal .app，或 Xcode archive 内的 .app
python3 scripts/validate-release.py --app /path/LumenFocus.app --report /tmp/lumen-validation.json
python3 scripts/validate-release.py --app /path/LumenFocus.xcarchive --report /tmp/lumen-validation.json

# 一条命令检查并生成内部测试 zip、内置报告及外部 SHA-256 文件
python3 scripts/package-unsigned.py --app /path/LumenFocus.xcarchive --output /tmp/lumen-artifacts

# 使用临时 fixture 验证通过与失败路径，不构建或运行 App
python3 -m unittest discover -s scripts -p 'test_*.py' -v
```

省略 `--app` 会失败，除非明确使用 `--source-only`。版本默认读取项目中的 `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`；若构建时有覆盖，两种脚本都需传入相同的 `--version 1.1 --build 2`。源码 Info.plist 必须引用构建变量，产物必须包含已展开且与预期相符的版本。

检查内容：

- 英语、简体中文、日语、法语的键集合一致、无重复或空翻译、格式化参数类型/数量/位置一致；允许 `%1$@` 等显式重排。检查独立复数资源的分支、参数和普通键冲突，以及显式 `L`、`NSLocalizedString`、`LocalizedStringKey`、`localize` 的静态字符串参数。任意运行时拼接键、所有 SwiftUI 可见文字与视觉排版仍需人工核对。
- 10 个 Mac 图标表示均有文件，PNG 尺寸匹配 asset 声明；不套用 iOS 图标透明度规则。
- Bundle ID 为 `Yvette.LumenFocus`、菜单栏应用标记为真、版本符合预期、声明最低 macOS 13.0；主可执行文件同时含 arm64 与 x86_64，两个 Mach-O slice 的实际最低系统均不高于 13.0。
- 产物包含非空 `Assets.car`、`AppIcon.icns`，以及四语言的 Localizable.strings 和 Localizable.stringsdict；翻译与源码完全一致。PrivacyInfo.xcprivacy 必须合法且与源码一致。源码隐私与最小 entitlement 基线有意采用严格匹配，改动需同时审阅检查规则。
- 传入 `.xcarchive` 时校验 ArchiveVersion、应用路径与应用身份/版本一致。这不是 Xcode Organizer 的完整 archive 验证，也不核对 dSYM UUID 或恢复符号能力。

PrivacyInfo.xcprivacy 是本项目主动维护的声明，不表示“缺少此文件的 macOS App 必然被拒”。脚本也不判断某个 Xcode/SDK 是否满足未来提交时 Apple 的版本要求；正式提交前须重新核对。

CI 运行脚本 fixture、源码检查、XCTest 和 universal unsigned Release archive，再生成 `LumenFocus-<version>-<build>-unsigned-not-for-distribution.zip`。包内有 `README.txt` 和 `validation.json`，报告记录校验时间、元数据、每个 App 文件的 SHA-256。包外 `.zip.sha256` 用于验证下载完整性，不是代码签名。打包工具拒绝覆盖同名产物。GitHub artifact 保留 7 天，不发布到 Release。

获得分发身份后，可运行额外的本地 App Store 预检：

```sh
python3 scripts/validate-release.py --app /path/DistributionSigned/LumenFocus.app \
  --app-store-ready --team-id YOURTEAMID --report /tmp/lumen-store-preflight.json
```

此模式要求 Apple 信任链下的 App Store 应用分发签名、指定 Team ID、App Sandbox 与用户选择文件读写权限，并拒绝 debugger entitlement、额外未审阅权限、未签名、ad-hoc、开发签名和 Developer ID 签名。兼容 `Apple Distribution` 与 Mac App Distribution 的证书名称 `3rd Party Mac Developer Application`；不接受 Installer 证书作为应用签名。Apple 当前[证书类型表](https://developer.apple.com/help/account/certificates/certificates-overview)仍列出这两类，名称对应见 [TN3161](https://developer.apple.com/documentation/technotes/tn3161-inside-code-signing-certificates)。这里的 `YOURTEAMID` 必须替换为实际 10 位 Team ID。工具只读取待检 App 的公开签名信息，不枚举钥匙串或使用私钥。

`--app-store-ready` 是本地前置检查名称，报告仍始终写入 `distributionReady: false`。Apple Developer Program 会员、App Store Connect 记录、分发 provisioning、Xcode Organizer 验证、上传后的处理、TestFlight 和 App Review 仍在后续流程中。特别是 TestFlight 必须有 provisioning profile；本脚本不验证该 profile 的服务器有效性或分发权限。采用 Apple Distribution 与 App Sandbox 的依据分别见 [Apple 的 macOS 分发签名说明](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac/)和[发行准备说明](https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution/)，profile 边界见 [TN3125](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles)。

通过这些检查不证明真实多屏/热插拔、Spaces/全屏、锁屏/睡眠、VoiceOver、最低系统、长期耗电或正式沙盒导出流程已经验收。应按项目验收文档另行记录设备与操作证据。
