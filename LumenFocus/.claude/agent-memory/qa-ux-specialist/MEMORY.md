# LumenFocus QA/UX 专家记忆库

## 项目基本信息
- **项目名称**: LumenFocus
- **应用类型**: macOS 菜单栏护眼应用
- **技术栈**: SwiftUI + AppKit (混合架构)
- **Bundle ID**: Yvette.LumenFocus
- **设计风格**: 黑白极简主义

## 已知的代码架构
1. **窗口管理器模式**: OnboardingWindowManager、SettingsWindowManager 负责窗口生命周期
2. **通知驱动**: 使用 NotificationCenter 进行组件间通信
3. **崩溃修复策略**: 所有窗口关闭操作都使用 `DispatchQueue.main.async` 避免 SwiftUI 渲染过程中崩溃

## 常见问题模式
1. **SwiftUI + AppKit 混合崩溃**: 在 SwiftUI 渲染过程中同步关闭窗口会导致 EXC_BAD_ACCESS
2. **内存管理**: NSColor 静态存储属性改为计算属性避免内存问题
3. **测试休息遮罩**: 通过菜单栏 → 开发选项 → 测试休息遮罩 触发
4. **SMAppService.register() 死锁**: 在主线程调用 `SMAppService.mainApp.register()` 会阻塞UI（等待系统权限弹窗），必须异步执行
5. **窗口关闭UI残留**: 使用 `orderOut()` + `close()` 不会自动清理子视图，需手动调用 `removeFromSuperview()`
6. **状态机时序错误**: `triggeringRest` → `resting` 的过渡需要精确计算动画时长，避免UI卡顿
7. **防重标志未重置**: 使用布尔标志防止重复操作时，必须在新周期开始时重置

## 测试路径
- 欢迎引导: 通过重置 `defaults write Yvette.LumenFocus hasCompletedOnboarding -bool false` 触发
- 设置页面: 通过菜单栏 → 设置打开
- 休息遮罩: 通过菜单栏 → 开发选项 → 测试休息遮罩

## 设计规范参考
- 主要文本: SF Pro Text, #1A1A1A
- 次要文本: #666666
- 背景色: #FFFFFF (主)、#F5F5F5 (次)
- CTA 按钮: 纯黑背景 #000000 + 白色文字
- 圆角: 8pt
- 间距: 遵循 24pt/32pt/48pt 网格系统

## PRD核心要求
### 休息遮罩动画时序（5分钟总时长示例）
1. **0:00-0:20**: 渐暗动画（alpha 0.0 → 0.7）
2. **0:20-4:40**: 保持暗态，显示倒计时和护眼提示
3. **4:40-5:00**: 渐亮动画（alpha 0.7 → 0.0）
4. **5:00**: 自动退出，返回工作周期

当前实现缺失第3步（最后20秒渐亮动画）

## 已知Bug及修复状态
### 🔴 严重崩溃（2026-02-05审查）
1. **设置保存按钮崩溃**: `LaunchAtLoginManager.enable()` 同步阻塞主线程 → 需异步执行
2. **欢迎页面按钮崩溃**: 同上，影响新用户onboarding
3. **ESC退出UI残留**: 窗口关闭未清理子视图，倒计时文字仍显示
4. **倒计时结束卡死**: 缺少最后20秒渐亮动画，用户以为应用崩溃

### 🟡 功能缺失
- 最后20秒渐亮动画未实现（违反PRD）
