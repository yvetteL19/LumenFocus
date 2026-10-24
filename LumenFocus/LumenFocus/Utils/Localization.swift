import Foundation

/// 本地化字符串短名（AppKit 路径用）
/// 例：`L("退出")` → en 区显示 "Quit"，zh-Hans 区显示 "退出"
@inline(__always) func L(_ key: String, comment: String = "") -> String {
    NSLocalizedString(key, comment: comment)
}

/// Shared work-time formatting. Preserve short recorded intervals as seconds;
/// longer activity uses the system's abbreviated hours and minutes.
func formatWorkDuration(_ seconds: Int) -> String {
    formatBreakDuration(seconds)
}

/// Keep UI language independent from the user's region, time zone and calendar.
/// The effective bundle language is used until relaunch, never a pending picker value.
enum AppLocalization {
    static let supportedLanguages = ["en", "zh-Hans", "ja", "fr"]
    static var locale: Locale { formattingLocale() }

    static func formattingLocale(languageIdentifier: String? = nil,
                                 regionLocale: Locale = .current) -> Locale {
        let language = languageIdentifier ?? Bundle.main.preferredLocalizations.first ?? "en"
        var components = Locale.Components(identifier: regionLocale.identifier)
        let selected = Locale.Language.Components(identifier: language)
        components.languageComponents.languageCode = selected.languageCode
        components.languageComponents.script = selected.script
        return Locale(components: components)
    }
}

/// The same abbreviated units are used in reminders, settings and recorded work.
func formatBreakDuration(_ seconds: Int, locale: Locale = AppLocalization.locale) -> String {
    let seconds = max(0, seconds)
    let f = DateComponentsFormatter()
    var calendar = Calendar.current
    calendar.locale = locale
    f.calendar = calendar
    if seconds >= 3600 { f.allowedUnits = [.hour, .minute] }
    else if seconds >= 60 { f.allowedUnits = seconds % 60 == 0 ? [.minute] : [.minute, .second] }
    else { f.allowedUnits = [.second] }
    f.unitsStyle = .abbreviated
    f.zeroFormattingBehavior = .dropAll
    // A valid, bounded interval always formats; retain a localized numeric fallback.
    return f.string(from: TimeInterval(seconds)) ?? String(format: L("%d 秒"), seconds)
}

func localizedCompletedBreaks(_ count: Int, bundle: Bundle = .main, locale: Locale = AppLocalization.locale) -> String {
    String(format: bundle.localizedString(forKey: "completed_break_count", value: nil, table: nil),
           locale: locale, arguments: [max(0, count)])
}

func localizedCompletedBreaksToday(_ count: Int, bundle: Bundle = .main, locale: Locale = AppLocalization.locale) -> String {
    String(format: bundle.localizedString(forKey: "completed_breaks_today", value: nil, table: nil),
           locale: locale, arguments: [max(0, count)])
}

func localizedRecordAccessibility(dayLabel: String, count: Int, workDuration: String,
                                  bundle: Bundle = .main, locale: Locale = AppLocalization.locale) -> String {
    String(format: bundle.localizedString(forKey: "daily_record_accessibility", value: nil, table: nil),
           locale: locale, arguments: [dayLabel, max(0, count), workDuration])
}
