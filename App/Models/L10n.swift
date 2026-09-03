import Foundation

/// String 타입 문구(오류 메시지 등)를 현재 앱 언어로 가져온다.
/// SwiftUI `Text`/`LocalizedStringKey`는 루트의 `.environment(\.locale)`로 전환되고,
/// 이 헬퍼는 그 밖의 문자열 컨텍스트를 같은 언어로 맞춘다.
///
/// 인자가 `String.LocalizationValue`라서 컴파일러가 String Catalog에 문구를 추출한다.
/// 형식 인자는 보간으로 넣는다: `L10n.string("오류: \(detail)")` → 키 `오류: %@`.
enum L10n {
    /// 현재 앱 언어의 문자열 번들. `.system`이면 메인 번들(시스템 언어)
    nonisolated(unsafe) private(set) static var bundle: Bundle = .main

    static func apply(_ language: AppLanguage) {
        guard let code = language.localeIdentifier,
              let path = Bundle.main.path(forResource: code, ofType: "lproj"),
              let languageBundle = Bundle(path: path) else {
            bundle = .main
            return
        }
        bundle = languageBundle
    }

    static func string(_ value: String.LocalizationValue) -> String {
        // 원문이 한국어이므로 번들에 키가 없어도 키 자체가 한국어 문구다
        String(localized: value, bundle: bundle)
    }
}
