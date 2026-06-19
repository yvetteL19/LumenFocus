# LumenFocus Bug修复检查清单
生成日期: 2026-02-05

## 🔴 严重问题（必须立即修复）

### ✅/❌ #1: 设置保存按钮崩溃
**文件**: `LumenFocus/Views/SettingsView.swift:264-282`
**修复方法**: 将 `enableLaunchAtLogin()` / `disableLaunchAtLogin()` 改为异步执行
```swift
DispatchQueue.global(qos: .userInitiated).async {
    if self.launchAtLogin {
        _ = LaunchAtLoginManager.shared.enable()
    } else {
        _ = LaunchAtLoginManager.shared.disable()
    }
}
```
**测试步骤**:
1. 打开设置 → 勾选"开机自启" → 点击保存 → 窗口应立即关闭
2. 再次打开设置 → 验证设置已保存
3. 系统偏好设置 → 登录项 → 验证LumenFocus出现

---

### ✅/❌ #2: 欢迎页面按钮崩溃
**文件**: `LumenFocus/Views/OnboardingView.swift:117-119`
**修复方法**: 同上，异步处理开机自启
```swift
if launchAtLogin {
    DispatchQueue.global(qos: .userInitiated).async {
        _ = LaunchAtLoginManager.shared.enable()
    }
}
```
**测试步骤**:
1. 重置引导状态: `defaults write Yvette.LumenFocus hasCompletedOnboarding -bool false`
2. 重启应用
3. 勾选"开机自启" → 点击"开始守护我的眼睛"
4. 应用应正常进入工作模式，菜单栏图标出现

---

### ✅/❌ #3: ESC退出UI残留
**文件**: `LumenFocus/Views/RestOverlayWindow.swift` (新增方法)
**修复方法**: 添加清理方法
```swift
func cleanup() {
    contentView?.subviews.forEach { $0.removeFromSuperview() }
    countdownLabel = nil
    tipLabel = nil
    escHintLabel = nil
    overlayView = nil
}
```
**文件**: `LumenFocus/Managers/RestManager.swift:82-100`
**修复方法**: 在关闭窗口前调用cleanup()
```swift
for window in windowsToClose {
    window.cleanup()
    window.orderOut(nil)
    window.close()
}
```
**测试步骤**:
1. 触发休息遮罩（菜单栏 → 开发选项 → 测试休息遮罩）
2. 立即按ESC
3. 屏幕应完全清除（无残留文字）

---

### ✅/❌ #4: 倒计时结束不自动退出
**文件**: `LumenFocus/Managers/RestManager.swift:103-116`
**修复方法**: 改用快速退出，不要20秒慢动画
```swift
private func completeRest() {
    stopCountdownTimer()

    let windowsToClose = overlayWindows
    overlayWindows.removeAll()

    // 使用快速退出（0.5秒）
    for window in windowsToClose {
        window.quickFadeOut {
            window.close()
        }
    }
}
```
**测试步骤**:
1. 设置休息时长为1分钟（方便测试）
2. 触发休息遮罩
3. 等待倒计时到0:00
4. 应在1秒内退出，返回正常工作界面

---

## 🟡 中等问题（1周内修复）

### ✅/❌ #5: PRD要求的最后20秒渐亮动画缺失
**文件**: `LumenFocus/Managers/TimerManager.swift:69-83`
**修复方法**: 在tick()中检测最后20秒
```swift
private func tick() {
    // ...现有代码...

    if appState.remainingSeconds > 0 {
        appState.remainingSeconds -= 1
        appState.updateProgress()

        // 新增：检测最后20秒
        if appState.isResting && appState.remainingSeconds == 20 {
            NotificationCenter.default.post(
                name: .startFadeOutAnimationNotification,
                object: nil
            )
        }
    } else {
        handleTimeUp()
    }
}
```
**文件**: `LumenFocus/Managers/RestManager.swift` (新增通知监听)
**修复方法**: 添加渐亮动画触发逻辑
```swift
// 在setupObservers()中添加
NotificationCenter.default.publisher(for: .startFadeOutAnimationNotification)
    .receive(on: DispatchQueue.main)
    .sink { [weak self] _ in
        self?.startFadeOutAnimation()
    }
    .store(in: &cancellables)

// 实现方法
private func startFadeOutAnimation() {
    for window in overlayWindows {
        window.fadeOut()  // 不带completion
    }
}
```
**测试步骤**:
1. 设置休息时长为1分钟
2. 触发休息遮罩
3. 在倒计时显示"0:20"时，屏幕应开始变亮
4. 到"0:00"时，屏幕应已完全恢复

---

### ✅/❌ #6: ESC重复触发风险
**文件**: `LumenFocus/Views/RestOverlayWindow.swift:197`
**修复方法**: 在cleanup()中重置标志
```swift
func cleanup() {
    contentView?.subviews.forEach { $0.removeFromSuperview() }
    countdownLabel = nil
    tipLabel = nil
    escHintLabel = nil
    overlayView = nil
    hasHandledEscape = false  // ← 新增
}
```
**测试步骤**:
1. 触发休息 → 按ESC退出
2. 等待下一个工作周期结束
3. 再次触发休息 → 再次按ESC
4. 第二次ESC应该仍然有效

---

## 🟢 轻微问题（下个版本修复）

### ✅/❌ #7: 窗口管理器缺少错误处理
**文件**: `LumenFocus/Managers/SettingsWindowManager.swift:36`
**修复方法**: 添加guard检查

### ✅/❌ #8: LaunchAtLoginManager错误提示缺失
**文件**: `LumenFocus/Views/SettingsView.swift:293-298`
**修复方法**: 检查返回值，显示错误提示

### ✅/❌ #9: StatisticsManager迁移Key拼写错误
**文件**: `LumenFocus/Managers/StatisticsManager.swift:198`
**修复方法**: 修正 `"hasM igratedToStatisticsManager"` → `"hasMigratedToStatisticsManager"`

### ✅/❌ #10: RestManager硬编码访问子视图
**文件**: `LumenFocus/Managers/RestManager.swift:179`
**修复方法**: 在RestOverlayWindow中添加 `setOverlayAlpha()` 公开方法

---

## 📋 回归测试清单

完成所有修复后，执行以下完整流程测试：

### 新用户首次体验
- [ ] 应用首次启动显示欢迎界面
- [ ] 勾选"开机自启" → 点击"开始守护我的眼睛" → 成功进入
- [ ] 菜单栏图标显示倒计时
- [ ] 系统偏好设置中出现LumenFocus登录项

### 设置功能
- [ ] 打开设置窗口
- [ ] 修改工作时长（如20分钟）
- [ ] 修改休息时长（如1分钟）
- [ ] 勾选/取消"开机自启"
- [ ] 点击"保存" → 窗口立即关闭
- [ ] 重新打开设置 → 验证修改已保存

### 休息遮罩流程
- [ ] 等待工作周期结束（或通过测试菜单触发）
- [ ] 前20秒：屏幕应缓慢变暗
- [ ] 中间时段：显示倒计时和护眼提示
- [ ] 最后20秒（倒计时显示0:20时）：屏幕应开始变亮
- [ ] 倒计时到0:00：立即退出，返回工作周期

### ESC退出测试
- [ ] 触发休息遮罩
- [ ] 按ESC键
- [ ] 所有UI元素（遮罩、倒计时、提示文字）应立即消失
- [ ] 无残留元素

### 多周期测试
- [ ] 完成一个完整的工作-休息周期
- [ ] 验证统计数据正确更新（今日护眼次数+1）
- [ ] 第二个工作周期正常开始
- [ ] 第二次休息时ESC仍然有效

### 边缘场景
- [ ] 休息期间插拔外接显示器（应自动适配）
- [ ] 切换系统深色/浅色模式（界面应正常显示）
- [ ] 暂停1小时 → 验证1小时后自动恢复
- [ ] 暂停至今日结束 → 验证午夜后自动恢复

---

## 📊 修复进度追踪

| 问题编号 | 优先级 | 状态 | 修复人 | 完成日期 |
|---------|-------|------|--------|---------|
| #1 | 🔴 高 | ⏳ 待修复 | | |
| #2 | 🔴 高 | ⏳ 待修复 | | |
| #3 | 🔴 高 | ⏳ 待修复 | | |
| #4 | 🔴 高 | ⏳ 待修复 | | |
| #5 | 🟡 中 | ⏳ 待修复 | | |
| #6 | 🟡 中 | ⏳ 待修复 | | |
| #7-#10 | 🟢 低 | ⏳ 待修复 | | |

---

## 🔧 修复后验证要点

1. **无崩溃**: 所有流程不出现彩色旋转圈或系统无响应
2. **UI清理**: 窗口关闭后无残留元素
3. **符合PRD**: 休息遮罩动画时序完全符合设计文档
4. **性能良好**: 所有操作响应时间 < 100ms
5. **多平台兼容**: 在macOS 13和14上都能正常工作
