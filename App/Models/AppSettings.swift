import Foundation
import GestureCore

/// GestureSettings를 UserDefaults에 JSON으로 영속화
final class AppSettings: ObservableObject {
    private static let key = "gestureSettings"

    @Published var gesture: GestureSettings {
        didSet { save() }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode(GestureSettings.self, from: data) {
            gesture = saved
        } else {
            gesture = .default
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(gesture) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
