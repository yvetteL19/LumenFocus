# LumenFocus

LumenFocus 是一款原生 macOS 菜单栏离屏休息提醒工具。无需账号，工作与休息记录保存在本机。

- 默认轻提醒：到点提示，由你决定何时开始；也可主动选择沉浸渐暗。
- 秒级休息：支持 20 秒至 15 分钟，渐暗渐亮不占用所选休息时间。
- 清楚的控制：延后本次、暂停提醒、跳过本次和提前结束各有独立语义；每块屏幕全程保留结束与延后按钮，支持 Esc。
- 应用避让规则：指定会议或媒体应用在前台时暂缓提醒，工作计时继续。无输入仅降低提醒强度；锁屏与睡眠暂停工作计时。
- 清晰设置：节奏、勿扰规则、通用、数据与支持分组，支持直接调整休息时长与随时开始休息。
- 本地统计：切换最近 7 / 30 / 90 天，查看已计时工作、完成休息和每日明细，按当前范围导出 CSV。无记录与记录为零分别显示；统计不代表实际屏幕暴露或健康效果。

## 开发

要求 macOS 13 或以上。项目使用 Swift 5、SwiftUI、AppKit 和 Combine。当前共享 scheme 已在 Xcode 16.4 验证。

打开 `LumenFocus/LumenFocus.xcodeproj`，选择 `LumenFocus` scheme。

```sh
xcodebuild -project LumenFocus/LumenFocus.xcodeproj -scheme LumenFocus \
  -configuration Debug -destination 'platform=macOS' \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test
```

通用 Release 编译：

```sh
xcodebuild -project LumenFocus/LumenFocus.xcodeproj -scheme LumenFocus \
  -configuration Release -destination 'generic/platform=macOS' \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO build
```

[测试说明](LumenFocus/LumenFocusTests/README.md)介绍隔离时钟和存储的回归套件；[开发约定](CLAUDE.md)记录状态语义与模块职责。GitHub Actions 在 PR 和 main 分支执行测试、双语与发布元数据检查及通用 Release Archive，保留明确标注不可分发的内部测试包。

[核心流程验收](docs/refactor-validation.md)、[界面体验验收](docs/interface-validation.md)和[发布前验收](docs/release-validation.md)记录各阶段证据。[构建检查说明](docs/release-build.md)提供可重复执行的产物校验与内部打包命令。

## Mac App Store 首发

首发渠道已确定为 Mac App Store，当前尚未加入 Apple Developer Program。工程保持 App Sandbox，仅开放用户通过保存面板选择文件的读写权限，并维护隐私清单。商店文案、审核说明与账号就绪后的操作见 [App Store 准备](docs/app-store-readiness.md)。

## 当前边界

前台应用规则不能确认正在通话、共享屏幕或全屏播放。音频素材和 Widget target 尚未交付；界面不展示相应功能。旧版重复周报已停用，避免发送过期快照。

源码验证、无签名 Archive 和本机临时签名验证不等于发行完成。正式发布还需覆盖多显示器布局/热插拔、Spaces、真实锁屏睡眠、VoiceOver、最低系统版本与长时间能耗，以及 App Store 分发签名、TestFlight 和安装升级测试。
