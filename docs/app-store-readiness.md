# Mac App Store 首发准备

产品文案更新：2026-10-24，以 [产品契约](product-contract.md) 为准。用户已确定首发 Mac App Store，目前尚未加入 Apple Developer Program。本文件是提交准备材料，不代表已经通过 Apple 校验或审核。

## 当前工程方向

- 保留 `Yvette.LumenFocus` Bundle ID；以后创建 App Store Connect 记录时注册这个精确标识，勿仅为命名风格更换已有安装身份。
- 最低系统为 macOS 13，构建包含 Apple Silicon 与 Intel 架构；最低系统与 Intel 仍需真实设备测试。
- 正式目标启用 App Sandbox，仅保留用户主动选择文件的读写权限，供 CSV 保存面板使用。没有网络、联系人、位置、相机、麦克风、屏幕录制或辅助功能权限。
- 不引入 Developer ID 直销、公证、站外更新器或许可证系统。App Store 的签名、上传、TestFlight 和商店分发是本次选定渠道。
- 版本号来自 Xcode 的 `MARKETING_VERSION` 与 `CURRENT_PROJECT_VERSION`，Archive 不应再夹带写死的旧版本值。

Apple 要求 Mac App Store 应用使用沙盒；标准 `NSSavePanel` 可以提供用户选中文件的访问。当前权限针对实际 CSV 功能，不添加宽泛目录权限。[App Sandbox](https://developer.apple.com/documentation/security/app-sandbox)、[沙盒文件访问](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox)。

## 账号就绪后需要完成

1. 加入 Apple Developer Program，在 Xcode 选择所属 Team，注册 Bundle ID，并配置 Mac App Store 所需签名。真实身份和协议由账号持有人完成。
2. 在 App Store Connect 创建 macOS 应用记录，确认名称、SKU、主语言、地区、价格、版权、审核联系人和商店年龄分级。当前没有提交这些内容。
3. 在届时支持的稳定 Xcode 上生成签名 Archive，运行本地发布预检，再在 Organizer 执行 Validate App / Distribute App。保留每个候选构建的版本、提交 SHA、工具链和校验记录。
4. 上传 TestFlight 后，重新验证**商店签名和沙盒**下的菜单栏、无声自动渐暗、任意键返回、停止/暂停持久化、锁屏睡眠、全局快捷键、登录项、CSV 保存及升级保留偏好与记录。临时本机签名不能替代该步骤。
5. 完成 `release-validation.md` 的设备验收；准备来自最终候选构建的真实截图。审核通过并获得发布决定前不自动发布。

TestFlight/App Store 分发需使用加入开发者计划的 Team，首次上传后 Bundle ID 不可更改。[Apple 分发准备](https://help.apple.com/xcode/mac/current/en.lproj/dev91fe7130a.html)。提交时重新核对[当前要求](https://developer.apple.com/news/upcoming-requirements/)；不把针对 iOS、tvOS、visionOS、watchOS 的 SDK 最低要求机械套用到 macOS。

## 隐私声明的代码依据

- `PrivacyInfo.xcprivacy` 声明无追踪域、无开发者收集的数据。`CA92.1` 说明本应用对自身偏好/统计 UserDefaults 的访问；未启用 App Group，不声明共享组用途。
- 计时、锁屏/睡眠事件和休息记录在设备上处理；不识别前台应用、会议、视频或输入空闲。应用不上传统计或 MetricKit 报告；用户可主动导出 CSV 或自行通过邮件联系支持。
- 按当前实现，App Store 隐私问卷可从“不收集数据”准备；账号持有人仍需逐项核实最终候选版及届时接入的服务。新增遥测、支付或服务后必须重新审阅。
- Apple 将仅设备内处理且不发送到服务器的数据与其隐私标签中的“收集”区分。当前 required-reason API 平台说明未列 macOS；本项目主动提供清单，不声称缺少该清单必然导致 Mac 审核拒绝。[隐私标签](https://developer.apple.com/app-store/app-privacy-details/)、[隐私清单](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)、[UserDefaults 理由](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)。

隐私政策：<https://yvettel19.github.io/LumenFocus/>。支持页候选：<https://yvettel19.github.io/LumenFocus/support.html>。支持页在本 PR 合并后由现有 Pages 的 `main:/docs` 发布；提交商店前需实际打开两个链接确认成功。

## 商店文案草稿（未上传）

名称：**LumenFocus**

中文副标题：**专注忘了时间，屏幕提醒一下**

英文副标题：**A quiet cue to take a break**

中文介绍：

> 专注起来，时间很容易悄悄过去。LumenFocus 按设定间隔让 Mac 屏幕无声地缓缓变暗，提醒你休息一下。看看窗外、伸个懒腰，或喝口水；按任意键就能返回工作，休息计时结束后也会自动渐亮。视频、会议和其他应用任务照常运行。你可以开启、停止、跳过本次，或暂停指定时长。没有应用识别或避让规则，需要安静一段时间时由你决定。偏好和记录保存在这台 Mac，无需账号。

英文介绍：

> It is easy to lose track of time when you are deeply focused. LumenFocus silently dims your Mac displays at the interval you choose, giving you a visible cue to take a break. Look out a window, stretch, or get a drink. Press any key to return to work, or let the displays brighten automatically when the break timer ends. Videos, calls and other app tasks keep running. Turn reminders on or off, skip one, or pause for a duration you choose. There are no app-detection or avoidance rules: you decide when to pause. Preferences and records stay on this Mac. No account is needed.

记录只是计时事实，不用于健康评分或完成目标。不要宣传治疗效果、会议/视频识别、应用控制、主动周报、Widget 或环境音。

## App Review notes draft

> LumenFocus is a macOS menu-bar utility. Find its progress-ring status item after setup; it does not keep a Dock window open. No account or sign-in is required.
>
> Choose a reminder interval and break length, then turn reminders on. Its only reminder style is automatic, silent dimming across all displays. It does not show a preliminary notification or inspect foreground apps, calls, videos or input inactivity. The overlay does not pause or control underlying applications.
>
> During a break, any key, including Escape, or the Back to work button immediately dismisses the overlay. The dismissal key is consumed, not forwarded or replayed to another application. If left alone, the overlay brightens away after the configured break length. Dimming transitions are separate from that length. No Accessibility or screen-recording permission is requested.
>
> Skip, pause expiry, manual resume and returning from a break start a new full reminder interval. Pause supports 1/2/4 hours and a custom duration. Stop remains stopped after relaunch; pause deadlines also persist. Lock and sleep are handled separately. Launch at login is optional.
>
> Records supports 7/30/90-day ranges and CSV export through the standard save panel. Preferences, timer records and diagnostics remain local. These records are not health measurements or a task-completion score.

审核联系姓名/电话、定价、出口合规回答、最终年龄分级及截图仍需账号持有人确认。这里不代填未知身份或法律声明。此前版本的真实截图和验收不能替代本轮自动遮罩与任意键退出的最终候选版证据。
