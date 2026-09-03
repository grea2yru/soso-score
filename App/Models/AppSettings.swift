import Foundation
import GestureCore

/// 앱 표시 언어. 시스템 설정을 따르거나 한국어/영어를 고정한다.
enum AppLanguage: String, CaseIterable, Codable {
    case system
    case korean = "ko"
    case english = "en"

    /// nil이면 시스템 언어
    var localeIdentifier: String? {
        switch self {
        case .system: return nil
        case .korean: return "ko"
        case .english: return "en"
        }
    }

    /// SwiftUI 환경(\.locale)에 넣을 로케일
    var locale: Locale {
        localeIdentifier.map(Locale.init(identifier:)) ?? .autoupdatingCurrent
    }
}

/// 제스처 설정과 언어 설정을 UserDefaults에 영속화
final class AppSettings: ObservableObject {
    private static let gestureKey = "gestureSettings"
    private static let languageKey = "appLanguage"

    @Published var gesture: GestureSettings {
        didSet { saveGesture() }
    }

    @Published var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: Self.languageKey)
            L10n.apply(language)
            // 시스템 컴포넌트(도구 팔레트·파일 선택기 등)는 다음 실행부터 이 언어를 따른다
            if let code = language.localeIdentifier {
                UserDefaults.standard.set([code], forKey: "AppleLanguages")
            } else {
                UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            }
        }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.gestureKey),
           let saved = try? JSONDecoder().decode(GestureSettings.self, from: data) {
            gesture = saved
        } else {
            gesture = .default
        }
        language = UserDefaults.standard.string(forKey: Self.languageKey)
            .flatMap(AppLanguage.init(rawValue:)) ?? .system
        L10n.apply(language)
    }

    private func saveGesture() {
        if let data = try? JSONEncoder().encode(gesture) {
            UserDefaults.standard.set(data, forKey: Self.gestureKey)
        }
    }
}
