import XCTest
@testable import ScoreForYou

final class LocalizationTests: XCTestCase {
    override func tearDown() {
        L10n.apply(.system)
    }

    func testLanguageLocales() {
        XCTAssertNil(AppLanguage.system.localeIdentifier)
        XCTAssertEqual(AppLanguage.korean.locale.identifier, "ko")
        XCTAssertEqual(AppLanguage.english.locale.identifier, "en")
    }

    func testEnglishBundleTranslatesStrings() {
        L10n.apply(.english)
        XCTAssertEqual(L10n.string("설정"), "Settings")
        XCTAssertEqual(L10n.string("PDF 악보"), "PDF Scores")
        XCTAssertEqual(ScoreKind.musicXML.title, "Digital Scores")
        XCTAssertEqual(L10n.format("악보 렌더링 오류: %@", "x"), "Score rendering error: x")
    }

    func testKoreanBundleKeepsSourceStrings() {
        L10n.apply(.korean)
        XCTAssertEqual(L10n.string("설정"), "설정")
        XCTAssertEqual(ScoreKind.pdf.title, "PDF 악보")
    }

    func testAppSettingsPersistsLanguage() {
        let settings = AppSettings()
        settings.language = .english
        XCTAssertEqual(UserDefaults.standard.string(forKey: "appLanguage"), "en")
        XCTAssertEqual(AppSettings().language, .english)
        settings.language = .system
        XCTAssertEqual(AppSettings().language, .system)
    }
}
