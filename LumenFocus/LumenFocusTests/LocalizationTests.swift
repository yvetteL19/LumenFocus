import XCTest
@testable import LumenFocus

final class LocalizationTests: XCTestCase {
    private func bundle(_ identifier: String) throws -> Bundle {
        let path = try XCTUnwrap(Bundle.main.path(forResource: identifier, ofType: "lproj"))
        return try XCTUnwrap(Bundle(path: path))
    }

    func testAllSupportedLanguagesHaveRealRuntimeResources() throws {
        for language in AppLocalization.supportedLanguages {
            let localized = try bundle(language)
            XCTAssertNotNil(localized.url(forResource: "Localizable", withExtension: "strings"))
            XCTAssertNotNil(localized.url(forResource: "Localizable", withExtension: "stringsdict"))
            let text = localizedCompletedBreaksToday(2, bundle: localized, locale: Locale(identifier: language))
            XCTAssertFalse(text.contains("completed_breaks_today"))
            XCTAssertFalse(text.contains("%#@"))
        }
    }

    func testEnglishZeroOneAndManyUseCorrectPluralForms() throws {
        let localized = try bundle("en")
        let locale = Locale(identifier: "en_US")
        XCTAssertEqual(localizedCompletedBreaksToday(0, bundle: localized, locale: locale), "0 timed endings today")
        XCTAssertEqual(localizedCompletedBreaksToday(1, bundle: localized, locale: locale), "1 timed ending today")
        XCTAssertEqual(localizedCompletedBreaksToday(2, bundle: localized, locale: locale), "2 timed endings today")
        XCTAssertEqual(localizedRecordAccessibility(dayLabel: "Today", count: 1, workDuration: "5 min",
                                                    bundle: localized, locale: locale),
                       "Today, 1 timed ending, 5 min timed work")
    }

    func testFrenchPluralSelectionUsesAppliedLanguageNotTheTestProcessLanguage() throws {
        let localized = try bundle("fr")
        // French uses the singular category for zero and one, even with a US region.
        let locale = AppLocalization.formattingLocale(languageIdentifier: "fr", regionLocale: Locale(identifier: "en_US"))
        XCTAssertEqual(localizedCompletedBreaks(0, bundle: localized, locale: locale), "0 fin automatique")
        XCTAssertEqual(localizedCompletedBreaks(1, bundle: localized, locale: locale), "1 fin automatique")
        XCTAssertEqual(localizedCompletedBreaks(2, bundle: localized, locale: locale), "2 fins automatiques")
    }

    func testChineseAndJapaneseCountSentencesAreLocalized() throws {
        XCTAssertEqual(localizedCompletedBreaksToday(1, bundle: try bundle("zh-Hans"), locale: Locale(identifier: "zh-Hans")),
                       "今日定时结束 1 次")
        XCTAssertEqual(localizedCompletedBreaksToday(1, bundle: try bundle("ja"), locale: Locale(identifier: "ja")),
                       "今日の自動終了 1 回")
    }

    func testLanguageOverridePreservesRegionAndHourCycle() {
        let region = Locale(identifier: "en_US@hours=h23")
        let french = AppLocalization.formattingLocale(languageIdentifier: "fr", regionLocale: region)
        XCTAssertEqual(french.language.languageCode?.identifier, "fr")
        XCTAssertEqual(french.region?.identifier, "US")
        XCTAssertTrue(french.identifier.contains("hours=h23"))
        let chinese = AppLocalization.formattingLocale(languageIdentifier: "zh-Hans", regionLocale: region)
        XCTAssertEqual(chinese.language.script?.identifier, "Hans")
        XCTAssertEqual(chinese.region?.identifier, "US")
    }

    func testSubMinuteDurationsRetainSecondsInEveryLanguage() {
        for language in AppLocalization.supportedLanguages {
            let locale = AppLocalization.formattingLocale(languageIdentifier: language, regionLocale: Locale(identifier: "en_US"))
            let value = formatBreakDuration(59, locale: locale)
            XCTAssertTrue(value.contains("59"), "\(language): \(value)")
            XCTAssertFalse(value.contains("%"))
            XCTAssertTrue(formatBreakDuration(0, locale: locale).contains("0"))
        }
    }
}
