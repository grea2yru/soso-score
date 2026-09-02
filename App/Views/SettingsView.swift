import SwiftUI
import GestureCore

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Form {
            Section("페이지 넘김 제스처") {
                Picker("방식", selection: $settings.gesture.mode) {
                    Text("고개 돌리기").tag(GestureMode.head)
                    Text("윙크").tag(GestureMode.wink)
                    Text("둘 다").tag(GestureMode.both)
                    Text("끄기").tag(GestureMode.off)
                }
                Toggle("방향 반전 (왼쪽/왼눈 = 다음)", isOn: $settings.gesture.invertDirection)
            }

            Section("고개 돌리기") {
                LabeledSlider(label: "감지 각도", value: $settings.gesture.headYawThresholdDegrees,
                              range: 10...35, format: "%.0f°")
                LabeledSlider(label: "유지 시간", value: $settings.gesture.headHoldDuration,
                              range: 0.1...1.0, format: "%.2f초")
            }

            Section("윙크") {
                LabeledSlider(label: "감김 민감도", value: $settings.gesture.winkClosedThreshold,
                              range: 0.5...0.95, format: "%.2f")
                LabeledSlider(label: "유지 시간", value: $settings.gesture.winkHoldDuration,
                              range: 0.1...0.5, format: "%.2f초")
            }

            Section("공통") {
                LabeledSlider(label: "쿨다운", value: $settings.gesture.cooldown,
                              range: 0.5...3.0, format: "%.1f초")
                Button("기본값으로 되돌리기") {
                    settings.gesture = .default
                }
            }
        }
        .navigationTitle("설정")
    }
}

struct LabeledSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                Spacer()
                Text(String(format: format, value))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: $value, in: range)
        }
    }
}
