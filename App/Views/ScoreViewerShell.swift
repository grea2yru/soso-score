import SwiftUI
import PencilKit
import GestureCore

/// 페이지 소스와 무관한 뷰어 공통부: 펼침 배치, 탭/얼굴 제스처 넘김, 플래시, 페이지 표시,
/// 필기 모드(PencilKit) + 저장, 마지막 페이지 기억.
struct ScoreViewerShell<Content: View>: View {
    let score: Score
    @ObservedObject var library: ScoreLibraryStore
    let pageCount: Int
    /// 페이지의 정규화 좌표계 크기 (필기 좌표 기준)
    let pageSize: (Int) -> CGSize
    @ViewBuilder let content: (Int) -> Content

    @EnvironmentObject var settings: AppSettings
    @StateObject private var tracker = FaceTrackingSession()
    @Environment(\.scenePhase) private var scenePhase
    /// 현재 펼침의 첫(왼쪽) 페이지 인덱스
    @State private var currentPageIndex = 0
    @State private var flashEdge: Edge?
    @State private var isTwoUp = false
    /// 필기 모드. 켜면 탭 넘김이 꺼지고 펜슬 캔버스가 입력을 받는다 (얼굴 제스처는 계속 동작)
    @State private var isAnnotating = false
    /// 페이지 인덕스별 필기 (정규화 좌표계)
    @State private var drawings: [Int: PKDrawing] = [:]
    /// 악보 메모에 필요한 도구만: 펜·마커·연필·지우개·올가미 (자·스크리블 제외)
    @State private var toolPicker = PKToolPicker(toolItems: [
        PKToolPickerInkingItem(type: .pen),
        PKToolPickerInkingItem(type: .marker),
        PKToolPickerInkingItem(type: .pencil),
        PKToolPickerEraserItem(type: .vector),
        PKToolPickerLassoItem(),
    ])

    private var navigator: PageNavigator {
        PageNavigator(pageCount: pageCount, twoUp: isTwoUp)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                SpreadView(indices: navigator.visibleIndices(from: currentPageIndex), twoUp: isTwoUp,
                           pageSize: pageSize) { index in
                    content(index)
                } overlay: { index, scale in
                    PencilCanvasView(
                        drawing: drawingBinding(for: index),
                        scale: scale,
                        isActive: isAnnotating,
                        toolPicker: toolPicker
                    )
                    .id(index)
                }
                .padding(.horizontal, 8)

                // 좌/우 30% 탭 영역 (필기 모드에서는 펜슬 입력을 방해하지 않도록 끔)
                if !isAnnotating {
                    HStack(spacing: 0) {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { turn(.previous) }
                        Color.clear
                            .frame(width: geo.size.width * 0.4)
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { turn(.next) }
                    }
                }

                if tracker.didFail {
                    VStack {
                        Text("카메라를 사용할 수 없어 손·탭으로만 넘길 수 있습니다. 설정 앱 > 개인정보 보호 > 카메라에서 권한을 확인하세요.")
                            .font(.footnote)
                            .padding(10)
                            .background(.yellow.opacity(0.9), in: RoundedRectangle(cornerRadius: 8))
                            .padding(.top, 4)
                        Spacer()
                    }
                    .allowsHitTesting(false)
                }

                if let edge = flashEdge {
                    FlashOverlay(edge: edge)
                }
            }
            .onAppear { isTwoUp = geo.size.width > geo.size.height }
            .onChange(of: geo.size) { _, size in
                isTwoUp = size.width > size.height
            }
        }
        .background(Color(.systemBackground))
        .navigationTitle(score.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Toggle(isOn: $isAnnotating) {
                    Image(systemName: isAnnotating ? "pencil.tip.crop.circle.fill" : "pencil.tip.crop.circle")
                }
                .toggleStyle(.button)
                .accessibilityLabel("필기 모드")
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    // 얼굴 추적 상태: 초록 = 추적 중, 회색 = 미검출/꺼짐
                    Circle()
                        .fill(tracker.isTrackingFace ? Color.green : Color.gray.opacity(0.5))
                        .frame(width: 10, height: 10)
                        .accessibilityLabel(tracker.isTrackingFace ? "얼굴 추적 중" : "얼굴 미검출")
                    Text(pageLabel)
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear {
            currentPageIndex = min(library.lastPage(of: score), max(pageCount - 1, 0))
            drawings = library.annotations.load(for: score.id)
            tracker.updateSettings(settings.gesture)
            tracker.start()
        }
        .onDisappear {
            tracker.pause()
            library.setLastPage(currentPageIndex, of: score)
            saveDrawings()
        }
        .onChange(of: isTwoUp) { _, _ in
            // 회전 시 펼침 경계(짝수 인덕스)에 맞춰 스냅
            currentPageIndex = navigator.leadingIndex(from: currentPageIndex)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { tracker.start() } else { tracker.pause() }
        }
        .onChange(of: settings.gesture) { _, newValue in
            tracker.updateSettings(newValue)
        }
        .onReceive(tracker.events) { event in
            turn(event)
        }
    }

    private func drawingBinding(for pageIndex: Int) -> Binding<PKDrawing> {
        Binding(
            get: { drawings[pageIndex] ?? PKDrawing() },
            set: { newValue in
                drawings[pageIndex] = newValue
                saveDrawings()
            }
        )
    }

    private func saveDrawings() {
        try? library.annotations.save(drawings, for: score.id)
    }

    private var pageLabel: String {
        let visible = navigator.visibleIndices(from: currentPageIndex).map { $0 + 1 }
        guard let first = visible.first else { return "0 / \(pageCount)" }
        if let last = visible.last, last != first {
            return "\(first)–\(last) / \(pageCount)"
        }
        return "\(first) / \(pageCount)"
    }

    func turn(_ event: PageTurnEvent) {
        let target: Int
        switch event {
        case .next: target = navigator.next(from: currentPageIndex)
        case .previous: target = navigator.previous(from: currentPageIndex)
        }
        guard target != currentPageIndex else { return }
        currentPageIndex = target
        flash(event == .next ? .trailing : .leading)
    }

    private func flash(_ edge: Edge) {
        withAnimation(.easeIn(duration: 0.05)) { flashEdge = edge }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            withAnimation(.easeOut(duration: 0.3)) { flashEdge = nil }
        }
    }
}

/// 페이지 넘김 시각 피드백: 넘긴 방향 가장자리에 짧은 색 플래시
struct FlashOverlay: View {
    let edge: Edge

    var body: some View {
        HStack {
            if edge == .trailing { Spacer() }
            Rectangle()
                .fill(Color.accentColor.opacity(0.35))
                .frame(width: 24)
            if edge == .leading { Spacer() }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
