# LumenFocusTests

测试源文件已就绪。一次性 Xcode UI 配置（约 30 秒）后即可自动编入：

1. 打开 `LumenFocus.xcodeproj`
2. `File → New → Target...` → macOS → Unit Testing Bundle
3. Product Name 填 `LumenFocusTests`，Team / Bundle Identifier 用默认
4. 创建后，新 target 会自动以同步文件夹方式吸收 `LumenFocusTests/` 下的所有 `.swift`
5. 命令行运行：

   ```
   xcodebuild -project LumenFocus.xcodeproj -scheme LumenFocus -destination 'platform=macOS' test
   ```

   或 Xcode 内按 ⌘U

## 已包含的测试

- `RestControllerStateMachineTests` — 状态机所有转换路径、ESC 取消、snooze 边界
- `StatisticsManagerTests` — 持久化 codable 往返、周报基础
- `AppSettingsTests` — 默认值与边界校验

## 写新测试

依赖：`@testable import LumenFocus`。访问单例的内部状态时，使用 `#if DEBUG` 暴露的辅助方法（如 `RestController._testReset()`）。
