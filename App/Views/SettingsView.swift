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

            Section("실시간 값 (보정용)") {
                if FaceTrackingSession.isSupported {
                    FaceDebugView()
                } else {
                    Text("이 기기에서는 얼굴 추적을 사용할 수 없습니다. (시뮬레이터 포함)")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("설정")
    }
}

/// 실기기에서 임계값을 보정할 수 있도록 현재 얼굴 값을 그대로 보여준다.
/// 설정 화면은 뷰어와 동시에 열리지 않으므로 자체 AR 세션을 사용해도 충돌하지 않는다.
struct FaceDebugView: View {
    @StateObject private var tracker = FaceTrackingSession()

    var body: some View {
        Group {
            if let frame = tracker.latestFrame, tracker.isTrackingFace {
                LabeledContent("고개 각도(yaw)", value: String(format: "%+.1f° (오른쪽이 +)", frame.yawDegrees))
                LabeledContent("왼눈 감김", value: String(format: "%.2f", frame.leftEyeBlink))
                LabeledContent("오른눈 감김", value: String(format: "%.2f", frame.rightEyeBlink))
            } else {
                Text("얼굴이 감지되지 않았습니다. 화면 앞에 얼굴을 비춰주세요.")
                    .foregroundStyle(.secondary)
            }
        }
        .monospacedDigit()
        .onAppear { tracker.start() }
        .onDisappear { tracker.pause() }
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
