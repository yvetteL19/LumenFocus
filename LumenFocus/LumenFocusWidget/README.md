# LumenFocusWidget

Widget 源文件就绪。在 Xcode 里完成一次性 target 配置后即可启用：

## 一次性 Xcode UI 设置

1. 打开 `LumenFocus.xcodeproj`
2. `File → New → Target...` → macOS → **Widget Extension**
3. Product Name：`LumenFocusWidget`；Bundle ID：`Yvette.LumenFocus.LumenFocusWidget`
4. 创建后 Xcode 自动生成模板文件——**全部删除**，本目录下的源文件会以同步文件夹方式自动加入
5. 在主 app 和 widget 两个 target 的 **Signing & Capabilities** 中各加一项：
   - **App Groups** → `+` → 新建/选择 `group.Yvette.LumenFocus`
6. `Utils/SharedDataAccess.swift` 已经把 group ID 写死为 `group.Yvette.LumenFocus`，保持一致即可
7. 主 app 在 AppState 数据变化时调用：
   ```swift
   SharedDataAccess.writeTodaySnapshot(
       restCount: AppState.shared.todayRestCount,
       workSeconds: AppState.shared.todayWorkDuration,
       currentStreak: StatisticsManager.shared.getCurrentStreak(),
       weeklyBars: StatisticsManager.shared.getWeeklyStatistics().map(\.restCount)
   )
   WidgetCenter.shared.reloadAllTimelines()
   ```
   建议接入位置：`StatisticsManager.incrementTodayRestCount()` 之后、`AppState.completeRest()` 之后

## 调试

- Widget Extension target 的 deployment target 也要降到 13.0（与主 app 对齐）
- 在 macOS 通知中心 / 桌面右键 → 编辑小组件，将 LumenFocus 拖到桌面
- 主 app 写入数据 → `WidgetCenter.shared.reloadAllTimelines()` → widget 立即刷新

## 已包含

- `LumenFocusWidget.swift` — Small（今日次数 + streak）和 Medium（7 日 bar chart + streak）两种尺寸
- `LumenFocusWidgetBundle.swift` — `@main` Bundle 入口
