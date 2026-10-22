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
- `StatisticsManagerTests`：独立 UserDefaults suite，验证旧数据合并、完成去重、跨午夜与夏令时、重启持久化、保留策略、时钟回拨及损坏数据恢复。
- `AppSettingsTests`：独立 UserDefaults suite，验证秒级设置、旧分钟迁移、数值边界、规则持久化与完整重置。

测试宿主的 `AppDelegate` 跳过正常启动/退出逻辑，不启动菜单栏、引导、计时器、通知或真实偏好迁移。新增测试也应注入依赖，不能清空 `UserDefaults.standard` 或重置生产单例。

GitHub Actions 在 PR 和 main 分支运行相同测试，以及 arm64/x86_64 通用 Release 构建。CI 产物是无签名构建验证，不能代替签名、公证和实机发行验收。
