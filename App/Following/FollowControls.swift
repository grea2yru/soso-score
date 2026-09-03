import SwiftUI

/// 툴바용: 따라가기 토글(귀 아이콘) + 듣는 중 레벨 미터
struct FollowControls: View {
    @ObservedObject var follower: ScoreFollower
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if follower.isListening {
                Capsule()
                    .fill(.secondary.opacity(0.3))
                    .frame(width: 40, height: 6)
                    .overlay(alignment: .leading) {
                        Capsule().fill(.green).frame(width: 40 * CGFloat(follower.level), height: 6)
                    }
                    .accessibilityLabel("입력 레벨")
            }
            Button(action: onToggle) {
                Image(systemName: follower.isListening ? "ear.fill" : "ear")
            }
            .disabled(!follower.isAvailable)
            .accessibilityLabel(follower.isListening ? "따라가기 끄기" : "따라가기 켜기")
        }
    }
}
