import SwiftUI
import PencilKit
import GestureCore

/// 페이지 소스와 무관한 뷰어 공통부: 펼침 배치, 탭/얼굴 제스처 넘김, 플래시, 페이지 표시,
/// 필기 모드(PencilKit) + 저장, 마지막 페이지 기억.
struct ScoreViewerShell<Content: View, Accessory: View>: View {
    let score: Score
    @ObservedObject var library: ScoreLibraryStore
    let pageCount: Int
    /// 현재 펼침 위치 (부모가 소유; 따라가기 등 외부 로직이 함께 조작)
    @ObservedObject var cursor: PageCursor
    /// 페이지의 정규화 좌표계 크기 (필기 좌표 기준)
    let pageSize: (Int) -> CGSize
    /// true면 좌/우 탭 넘김을 끈다 (따라가기 중 탭은 위치 재지정에 쓰임)
    var disablesTapTurning: Bool = false
    @ViewBuilder let content: (Int) -> Content
    /// 툴바 오른쪽에 추가되는 부속 뷰 (예: 따라가기 컨트롤)
    @ViewBuilder let accessory: () -> Accessory

    @EnvironmentObject var settings: AppSettings
    @StateObject private var tracker = FaceTrackingSession()
    @Environment(\.scenePhase) private var scenePhase
    @State private var flashEdge: Edge?
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

    var body: some View {
        GeometryReader { geo in
            ZStack {
                SpreadView(indices: cursor.visibleIndices, twoUp: cursor.isTwoUp,
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

                // 좌/우 30% 탭 영역 (필기 모드·따라가기 중에는 끔)
                if !isAnnotating && !disablesTapTurning {
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
            .onAppear {
                cursor.isTwoUp = geo.size.width > geo.size.height
                cursor.snap()
            }
            .onChange(of: geo.size) { _, size in
                cursor.isTwoUp = size.width > size.height
                cursor.snap()
            }
        }
        .background(Color(.systemBackground))
        .navigationTitle(score.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                accessory()
            }
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
            cursor.pageCount = pageCount
            cursor.leadingIndex = min(library.lastPage(of: score), max(pageCount - 1, 0))
            drawings = library.annotations.load(for: score.id)
            tracker.updateSettings(settings.gesture)
            tracker.start()
        }
        .onDisappear {
            tracker.pause()
            library.setLastPage(cursor.leadingIndex, of: score)
            saveDrawings()
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
        let visible = cursor.visibleIndices.map { $0 + 1 }
        guard let first = visible.first else { return "0 / \(pageCount)" }
        if let last = visible.last, last != first {
            return "\(first)–\(last) / \(pageCount)"
        }
        return "\(first) / \(pageCount)"
    }

    func turn(_ event: PageTurnEvent) {
        guard cursor.turn(event) else { return }
        flash(event == .next ? .trailing : .leading)
    }

    private func flash(_ edge: Edge) {
        withAnimation(.easeIn(duration: 0.05)) { flashEdge = edge }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            withAnimation(.easeOut(duration: 0.3)) { flashEdge = nil }
        }
    }
}

extension ScoreViewerShell where Accessory == EmptyView {
    init(score: Score, library: ScoreLibraryStore, pageCount: Int, cursor: PageCursor,
         pageSize: @escaping (Int) -> CGSize, disablesTapTurning: Bool = false,
         @ViewBuilder content: @escaping (Int) -> Content) {
        self.init(score: score, library: library, pageCount: pageCount, cursor: cursor,
                  pageSize: pageSize, disablesTapTurning: disablesTapTurning,
                  content: content, accessory: { EmptyView() })
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
