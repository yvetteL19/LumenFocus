# LumenFocus

LumenFocus 是一款原生 macOS 菜单栏休息提醒工具，为专注起来容易忘记时间的人而做。设定间隔后，屏幕会自动、无声地缓缓变暗，提醒你休息一下。

- 自动提醒是唯一主流程：到点直接渐暗，无需先发现通知或点击开始。
- 随时返回：按任意键（包括 Esc）或点击“返回工作”即可立即退出遮罩；到达休息时长后自动渐亮。触发退出的按键不会转发或重放到其他应用。
- 其他任务照常运行：遮罩不会暂停或控制视频、会议、下载、渲染或底层应用任务。
- 用户决定何时提醒：可开启、停止、跳过本次，或暂停 1 / 2 / 4 小时及自定义时长。返回工作、跳过、暂停结束或手动恢复后，重新计算完整提醒间隔。
- 不判断你正在使用什么应用：没有会议、视频、前台应用或无操作避让规则。需要一段时间不提醒时，由你主动暂停；锁屏和睡眠仍自动处理。
- 四种界面语言：英语、简体中文、日语和法语，默认跟随系统。记录与偏好保存在本机，无需账号。
- 历史记录是次要工具：保留最近 7 / 30 / 90 天查看与 CSV 导出，不设置完成目标、连续打卡或健康评分。

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

[测试说明](LumenFocus/LumenFocusTests/README.md)介绍隔离时钟和存储的回归套件；[开发约定](CLAUDE.md)记录状态语义与模块职责。GitHub Actions 在 PR 和 main 分支执行测试、四语言资源与发布元数据检查及通用 Release Archive，保留明确标注不可分发的内部测试包。

现行行为以 [产品契约](docs/product-contract.md) 为准，本轮结果见 [自动渐暗流程验收](docs/automatic-dimming-validation-2026-10-24.md)。[核心流程验收](docs/refactor-validation.md)、[界面体验验收](docs/interface-validation.md)、[发布前验收](docs/release-validation.md)和[前一轮体验验收](docs/ux-implementation-validation-2026-10-23.md)保留历史证据，不能作为本轮新交互的验收结论。[构建检查说明](docs/release-build.md)提供可重复执行的产物校验与内部打包命令。

## Mac App Store 首发

首发渠道已确定为 Mac App Store，当前尚未加入 Apple Developer Program。工程保持 App Sandbox，仅开放用户通过保存面板选择文件的读写权限，并维护隐私清单。商店文案、审核说明与账号就绪后的操作见 [App Store 准备](docs/app-store-readiness.md)。

## 当前边界

现行目标和动作语义见 [产品契约](docs/product-contract.md)。旧版轻提醒、应用避让、无操作检测和完成导向的主流程已被取代。休息提示不是医学测量，也不判断用户是否真的离开屏幕。

音频、Widget 和主动周报不属于当前产品。源码验证、无签名 Archive 和本机临时签名验证不等于发行完成。正式发布还需覆盖多显示器/热插拔、Spaces、真实锁屏睡眠、任意键退出、VoiceOver、最低系统版本、长时间能耗，以及 App Store 分发签名、TestFlight 和安装升级测试。
