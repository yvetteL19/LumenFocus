//
//  Tips.swift
//  LumenFocus
//
//  Rest-time tip library. Bucketed by time of day; locale-aware (zh-Hans / en).
//

import Foundation

enum Tips {
    /// 按当前时间和系统语言随机一条
    static func random(for date: Date = Date()) -> String {
        let bucket = bucket(for: date, isChinese: isChineseLocale())
        return bucket.randomElement() ?? defaultFallback()
    }

    private static func isChineseLocale() -> Bool {
        if #available(macOS 13.0, *) {
            return Locale.current.language.languageCode?.identifier == "zh"
        } else {
            return Locale.current.languageCode == "zh"
        }
    }

    private static func defaultFallback() -> String {
        isChineseLocale() ? "眺望远方，放松眼部肌肉" : "Look at something far and let your eye muscles relax"
    }

    /// 时段桶选择
    private static func bucket(for date: Date, isChinese: Bool) -> [String] {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5..<11:  return isChinese ? morningZh : morningEn
        case 11..<14: return isChinese ? noonZh    : noonEn
        case 14..<18: return isChinese ? afternoonZh : afternoonEn
        case 18..<22: return isChinese ? eveningZh : eveningEn
        default:      return isChinese ? nightZh   : nightEn
        }
    }

    // MARK: - Chinese

    static let morningZh: [String] = [
        "新的一天，先眨眨眼让泪液重新覆盖角膜",
        "看向窗外的远处，让眼球转动起来",
        "深呼吸三次，让大脑也跟着醒过来",
        "起身走两步，给颈椎也松松绑",
        "喝一杯温水，唤醒身体",
        "把肩膀往后展开，舒展整夜蜷缩的姿势",
        "试着把视线锁定在最远处的物体 20 秒",
        "用手心搓热，轻轻贴在闭着的眼睛上",
        "看看远山或对面楼宇的边线",
        "环顾房间四角，让眼球做一次大范围运动",
    ]

    static let noonZh: [String] = [
        "一上午高强度用眼，闭眼休息 30 秒",
        "起身去倒一杯水，顺便活动手腕",
        "走到窗边，看看天上的云",
        "做一组缓慢的颈部画圈动作",
        "把双手往天花板伸展，背部拉一拉",
        "看看你最远的那本书的书脊文字",
        "用力闭眼 3 秒再睁开，重复 5 次",
        "去趟洗手间，给眼睛一段离开屏幕的时间",
        "想想晚餐想吃什么，让大脑切换主题",
        "盯着远处发呆也是放松",
    ]

    static let afternoonZh: [String] = [
        "下午精力下滑期，闭眼深呼吸恢复",
        "看看远处的绿色植物，绿色最舒缓眼睛",
        "做一组眼球画圈：顺时针 5 圈，逆时针 5 圈",
        "把窗户打开一条缝，呼吸点新鲜空气",
        "起来走两步，让血液循环回头部",
        "把视线远近交替切换：远处→桌面→远处",
        "试着用余光感知窗外的颜色",
        "用指腹轻按太阳穴 10 秒",
        "看向远处天际线，让眼肌彻底放松",
        "如果有零食，吃一口换换状态",
    ]

    static let eveningZh: [String] = [
        "夜幕将至，看看窗外光线的变化",
        "今天工作累了，闭上眼让眼皮休息一会",
        "向远处望去，让眼睛跟着天色变暗",
        "做一组缓慢眨眼，让泪液重新分布",
        "起身拉伸脊背，结束一天的伏案",
        "看向房间最远的角落，让眼球放松",
        "想想今天最满意的一件事",
        "深呼吸，让心率慢下来",
        "用温水洗一下脸，给眼睛降温",
        "看看远处的灯光，感受焦距的变化",
    ]

    static let nightZh: [String] = [
        "夜深了，眼睛比平时更容易疲劳",
        "如果可以，建议早点结束今天的工作",
        "闭眼深呼吸，让神经放松",
        "看向远处弱光区域，让瞳孔扩张休息",
        "用手心捂住双眼 30 秒，让世界完全暗下来",
        "做一组缓慢的颈部前后弯曲",
        "想想明天最想做的事",
        "把屏幕亮度再调低一档",
        "起身去喝一杯水，离开屏幕一会",
        "深夜的工作，眼睛最需要这 5 分钟",
    ]

    // MARK: - English

    static let morningEn: [String] = [
        "Start the day by blinking to coat your cornea with fresh tears",
        "Look out the window to the far distance and let your eyes track",
        "Take three deep breaths — wake the brain along with the eyes",
        "Stand up and walk a few steps to unkink your neck",
        "Sip a glass of warm water to wake the body",
        "Pull your shoulders back to undo the curl from the night",
        "Lock your gaze on the farthest object you can see for 20 seconds",
        "Rub your palms warm and gently rest them on closed eyes",
        "Look at the silhouette of distant buildings or hills",
        "Sweep your gaze across all four corners of the room",
    ]

    static let noonEn: [String] = [
        "After a heavy morning, close your eyes for 30 seconds",
        "Go refill your water and flex your wrists on the way",
        "Walk to the window — watch the clouds for a bit",
        "Slowly rotate your neck in small circles",
        "Reach toward the ceiling and stretch your back",
        "Try reading the spine text of your farthest book",
        "Squeeze your eyes shut for 3 seconds, then open. Repeat 5×",
        "Hit the restroom — give your eyes time off-screen",
        "Daydream about dinner — switch the mental channel",
        "Just stare into the distance — that counts too",
    ]

    static let afternoonEn: [String] = [
        "Afternoon energy dip — close your eyes and breathe deeply",
        "Look at a green plant in the distance — green soothes the eyes",
        "Eye circles: 5 clockwise, 5 counterclockwise",
        "Crack a window for some fresh air",
        "Walk around a bit to send blood back to your head",
        "Refocus: distant → desk → distant. Repeat slowly",
        "Use peripheral vision to scan the outside colors",
        "Press your temples gently with your fingertips for 10s",
        "Gaze at the horizon and let the eye muscles fully relax",
        "If there's a snack within reach, take one — change of pace",
    ]

    static let eveningEn: [String] = [
        "Dusk is coming — notice how the light is shifting outside",
        "It's been a long day. Just close your eyes for a moment",
        "Look into the distance and let your eyes adjust with the dusk",
        "Slow blinks — let your tears spread evenly",
        "Stretch your back; the desk day is ending",
        "Find the farthest corner of the room and rest your gaze there",
        "Recall one good moment from today",
        "Breathe slowly. Let your heart rate come down",
        "Splash warm water on your face — cools your eyes",
        "Watch a distant light — feel your focus shift",
    ]

    static let nightEn: [String] = [
        "Late hours strain the eyes more than daylight",
        "If you can, consider wrapping it up earlier than planned",
        "Close your eyes, breathe deeply, let your nerves settle",
        "Look into a dim distant area — let your pupils dilate to rest",
        "Cup your palms over closed eyes for 30 seconds of total darkness",
        "Slowly tip your head forward and back, twice each",
        "Picture the one thing you want to do tomorrow",
        "Lower your screen brightness one notch",
        "Stand up and grab some water — get off the screen for a moment",
        "Late-night work is when these 5 minutes matter most",
    ]
}
