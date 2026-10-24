# LumenFocusTests

测试 target 和共享 scheme 已纳入项目，克隆后无需在 Xcode 中手动配置。

从仓库根目录运行：

```sh
xcodebuild -project LumenFocus/LumenFocus.xcodeproj -scheme LumenFocus \
  -configuration Debug -destination 'platform=macOS' \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test
```

也可以在 Xcode 中选择 LumenFocus scheme 后按 ⌘U。

## 回归范围

- `CycleEngineTests`：注入时钟，验证精确休息时长、延后/跳过/取消、重复暂停、环境与暂停叠加、睡眠返回、设置变更、晚到心跳与系统时间调整。
- `RestControllerStateMachineTests`：验证视觉阶段和用户动作转发；不初始化生产计时器或音频。
- `StatisticsManagerTests`：独立 UserDefaults suite，验证旧数据合并、完成去重、跨午夜与夏令时、动态时区、历法变化保护、上下文回收、重启持久化、保留策略、时钟回拨及损坏数据恢复。
- `AppSettingsTests`：独立 UserDefaults suite，验证秒级设置、旧分钟迁移、数值边界、规则持久化与完整重置。
- `OnboardingDraftTests`：已选节奏唯一提交、取消保留原值、登录设置失败不部分提交。
- `AppStateTests`：完成、提前结束和延后的轻量结果区分；下一次提醒及暂停不保留旧结果。
- `LocalizationTests`：四语言真实资源、英法复数、中日计数句、地区与小时制、秒级格式。
- `RelaunchHandoffTests`：新实例等旧实例终止后才启动，覆盖错误 PID、重复事件、退出竞态与取消等待，避免统计快照覆盖和快捷键抢先注册。
- `RelaunchIntentTests`：独立临时目录验证沙盒重启意图的一次性消费、同秒启动日期精度、30 秒过期、错误身份/损坏文件、失败重试和旧 token 清理；结合真实独立统计仓库验证退出前最终记录先保存、新实例再读取。
- `ReminderPresentationTests`：验证不足一分钟、分钟取整与暂停/环境状态的呈现语义。
- `StatisticsPresentationTests`：验证所选日期范围、无记录与零值、摘要与导出一致性、原子日期快照，以及日历边界。
- `DisplayLayoutTests`：覆盖负坐标、上下排列、缩放后逻辑坐标、屏幕移除/新增/改尺寸、主屏保持及小区域提醒定位。
- `RestPresentationTests`：创建未显示的原生窗口，验证内容坐标、Reduce Motion、结束/延后控件和 Esc 路径、重复动作与旧窗口回调失效、焦点策略及非激活提醒面板。不会切换系统辅助功能选项或实际显示罩层。
- `WorkspaceRuleResolverTests`：验证前台规则开关、主开关与应用自身设置窗口的上下文继承。
- `PresentationLifecycleTests`：弱引用确认关闭设置、统计和 popover 后释放 hosting 控制器及视图，重开可重建；同轮多字段发布只渲染最终状态，渲染期间的新变化不会丢失。

测试宿主的 `AppDelegate` 跳过正常启动/退出逻辑，不启动菜单栏、引导、计时器、通知或真实偏好迁移。新增测试也应注入依赖，不能清空 `UserDefaults.standard` 或重置生产单例。

GitHub Actions 在 PR 和 main 分支运行相同测试、`scripts/test_validate_release.py` 的隔离通过/失败样例，以及 arm64/x86_64 通用 Release Archive。发布脚本校验四语言、复数资源、元数据、架构与资源，再打包带校验报告的内部 ZIP。CI 产物不能代替 App Store 分发签名、TestFlight 和实机发行验收，详见 [发布前验收](../../docs/release-validation.md)。
