import SwiftUI
import GestureCore
import ScoreFollowCore

enum MusicXMLPage {
    /// 가상 페이지(A4)의 정규화 좌표계 크기 — 필기 저장 기준
    static let size = CGSize(width: 595, height: 842)
}

/// 음표가 놓인 페이지와 그 페이지 안의 시스템(줄) 순번
struct NoteLocation: Equatable {
    let page: Int
    let system: Int
}

/// 따라가기에 필요한 조판 인덱스
struct ScoreLayoutIndex {
    var noteLocation: [String: NoteLocation] = [:]
    var systemCounts: [Int: Int] = [:]
    var measureFirstEvent: [String: Int] = [:]
}

/// Verovio 엔진으로 MusicXML을 조판해 ScoreViewerShell에 페이지 SVG를 공급하고,
/// 오디오 따라가기(하이라이트·자동 넘김·탭 재지정)를 연동한다.
struct MusicXMLScoreViewer: View {
    let score: Score
    @ObservedObject var library: ScoreLibraryStore
    @StateObject private var cursor = PageCursor()
    @StateObject private var follower = ScoreFollower()
    @Environment(\.scenePhase) private var scenePhase
    @State private var pageCount: Int?
    @State private var errorMessage: String?
    @State private var svgs: [Int: String] = [:]
    @State private var layout = ScoreLayoutIndex()
    @State private var controllers: [Int: SVGPageController] = [:]
    /// 같은 페이지에서 자동 넘김을 두 번 하지 않기 위한 기록
    @State private var lastAutoTurnedFrom: Int?

    var body: some View {
        Group {
            if let pageCount {
                ScoreViewerShell(
                    score: score,
                    library: library,
                    pageCount: pageCount,
                    cursor: cursor,
                    pageSize: { _ in MusicXMLPage.size },
                    disablesTapTurning: follower.isListening
                ) { index in
                    SVGPage(
                        index: index,
                        svgs: $svgs,
                        highlightIDs: highlightIDs(for: index),
                        controller: controllers[index],
                        onTapNormalized: follower.isListening ? { x, y in relocate(page: index, x: x, y: y) } : nil
                    )
                } accessory: {
                    FollowControls(follower: follower, onToggle: toggleFollow)
                }
                .overlay(alignment: .top) {
                    if follower.permissionDenied {
                        Text("마이크 권한이 없어 따라가기를 쓸 수 없습니다. 설정 앱 > 개인정보 보호 > 마이크에서 허용해 주세요.")
                            .font(.footnote)
                            .padding(10)
                            .background(.yellow.opacity(0.9), in: RoundedRectangle(cornerRadius: 8))
                            .padding(.top, 4)
                            .allowsHitTesting(false)
                    }
                }
            } else if let errorMessage {
                ContentUnavailableView("악보를 열 수 없습니다", systemImage: "exclamationmark.triangle",
                                       description: Text(errorMessage))
            } else {
                ProgressView("악보를 조판하는 중…")
            }
        }
        .task(id: score.id) { await load() }
        .onChange(of: follower.currentEvent) { _, event in autoTurn(for: event) }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { follower.stop() }
        }
        .onDisappear { follower.stop() }
    }

    // MARK: 로딩

    private func load() async {
        do {
            svgs = [:]
            layout = ScoreLayoutIndex()
            lastAutoTurnedFrom = nil
            let count = try await VerovioEngine.shared.load(fileURL: score.url)
            controllers = Dictionary(uniqueKeysWithValues: (0..<count).map { ($0, SVGPageController()) })
            pageCount = count

            // 따라가기 준비 — 실패해도 뷰어 자체는 동작한다
            let entries = try await VerovioEngine.shared.timemapEntries()
            let ids = Array(Set(entries.flatMap { $0.on ?? [] }))
            let pitches = try await VerovioEngine.shared.pitches(for: ids)
            let events = ScoreTemplateBuilder.events(from: entries, pitches: pitches)

            var index = ScoreLayoutIndex()
            for page in 0..<count {
                let map = try await VerovioEngine.shared.systemMap(page: page)
                index.systemCounts[page] = map.count
                for (id, system) in map.notes {
                    index.noteLocation[id] = NoteLocation(page: page, system: system)
                }
            }
            for event in events {
                if let measure = event.measureID, index.measureFirstEvent[measure] == nil {
                    index.measureFirstEvent[measure] = event.index
                }
            }
            layout = index
            follower.configure(events: events)
        } catch {
            if pageCount == nil { errorMessage = error.localizedDescription }
        }
    }

    // MARK: 따라가기

    private func highlightIDs(for page: Int) -> [String] {
        guard follower.isListening, let event = follower.currentEvent else { return [] }
        return event.noteIDs.filter { layout.noteLocation[$0]?.page == page }
    }

    private func toggleFollow() {
        if follower.isListening {
            follower.stop()
        } else {
            lastAutoTurnedFrom = nil
            Task { await follower.start() }
        }
    }

    /// 현재 이벤트가 보이는 마지막 페이지의 마지막 줄에 들어오면 다음 펼침으로.
    /// 이벤트가 화면 앞쪽 페이지에 있으면 그 페이지로 즉시 이동한다.
    private func autoTurn(for event: ScoreEvent?) {
        guard follower.isListening, let event,
              let first = event.noteIDs.first,
              let location = layout.noteLocation[first],
              let lastVisible = cursor.visibleIndices.last else { return }

        if location.page > lastVisible {
            cursor.show(page: location.page)
            return
        }
        if location.page == lastVisible,
           let systemCount = layout.systemCounts[location.page], systemCount > 0,
           location.system == systemCount - 1,
           lastAutoTurnedFrom != location.page {
            lastAutoTurnedFrom = location.page
            cursor.turn(.next)
        }
    }

    /// 따라가기 중 탭한 마디의 첫 이벤트로 위치를 재지정
    private func relocate(page: Int, x: CGFloat, y: CGFloat) {
        guard let controller = controllers[page] else { return }
        Task {
            guard let measure = await controller.measureID(atX: x, y: y),
                  let eventIndex = layout.measureFirstEvent[measure] else { return }
            follower.relocate(toEventIndex: eventIndex)
            lastAutoTurnedFrom = nil
        }
    }
}

/// 페이지 SVG를 필요할 때 엔진에서 받아와 표시하고, 따라가기 중에는 탭 위치를 정규화해 전달한다.
private struct SVGPage: View {
    let index: Int
    @Binding var svgs: [Int: String]
    let highlightIDs: [String]
    let controller: SVGPageController?
    let onTapNormalized: ((CGFloat, CGFloat) -> Void)?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let svg = svgs[index] {
                    SVGPageView(svg: svg, highlightIDs: highlightIDs, controller: controller)
                } else {
                    Color.white.overlay(ProgressView())
                }
                if let onTapNormalized {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture(coordinateSpace: .local) { point in
                            guard geo.size.width > 0, geo.size.height > 0 else { return }
                            onTapNormalized(point.x / geo.size.width, point.y / geo.size.height)
                        }
                }
            }
        }
        .task(id: index) {
            guard svgs[index] == nil else { return }
            if let svg = try? await VerovioEngine.shared.pageSVG(index) {
                svgs[index] = svg
            }
        }
    }
}
