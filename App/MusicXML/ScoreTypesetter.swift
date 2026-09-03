import Foundation
import ScoreFollowCore

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

/// 따라가기 준비물: 이벤트 열과 조판 인덱스
struct FollowIndex {
    let events: [ScoreEvent]
    let layout: ScoreLayoutIndex

    /// 타임맵·피치·페이지별 시스템 맵으로 만든다 (엔진·디스크 캐시 공용)
    static func build(entries: [TimemapEntry], pitches: [String: Int], systems: [PageSystemMap]) -> FollowIndex {
        let events = ScoreTemplateBuilder.events(from: entries, pitches: pitches)
        var layout = ScoreLayoutIndex()
        for (page, map) in systems.enumerated() {
            layout.systemCounts[page] = map.count
            for (id, system) in map.notes {
                layout.noteLocation[id] = NoteLocation(page: page, system: system)
            }
        }
        for event in events {
            if let measure = event.measureID, layout.measureFirstEvent[measure] == nil {
                layout.measureFirstEvent[measure] = event.index
            }
        }
        return FollowIndex(events: events, layout: layout)
    }
}

/// 악보 하나의 조판 결과 공급자. 디스크 캐시가 있으면 엔진 없이 파일에서 읽고,
/// 없으면 엔진으로 실시간 조판하다가 인덱스를 다 만들면 캐시에 저장하고 엔진을 놓는다.
@MainActor
final class TypesetDocument {
    let pageCount: Int
    private let key: String
    private var bundle: TypesetBundle?
    private var lease: ScoreTypesetter.EngineLease?
    private unowned let typesetter: ScoreTypesetter

    init(key: String, pageCount: Int, bundle: TypesetBundle?, lease: ScoreTypesetter.EngineLease?, typesetter: ScoreTypesetter) {
        self.key = key
        self.pageCount = pageCount
        self.bundle = bundle
        self.lease = lease
        self.typesetter = typesetter
    }

    /// 디스크 캐시에서 읽고 있으면 true (엔진을 쓰지 않음)
    var isCached: Bool { bundle != nil }

    func pageSVG(_ index: Int) async throws -> String {
        if let bundle {
            return try await Task.detached(priority: .userInitiated) { try bundle.pageSVG(index) }.value
        }
        guard let lease else { throw VerovioError.notReady }
        return try await lease.engine.pageSVG(index)
    }

    /// 따라가기 인덱스를 만든다. 엔진 조판이면 모든 페이지를 렌더해야 하므로 `priorityPages`가 돌려주는
    /// (지금 보이는) 페이지부터 처리하고, 끝나면 결과를 캐시에 저장한 뒤 엔진을 놓는다.
    func buildFollowIndex(priorityPages: @escaping @MainActor () -> [Int]) async throws -> FollowIndex {
        if let bundle {
            return try await Task.detached(priority: .utility) {
                FollowIndex.build(entries: try bundle.timemapEntries(), pitches: try bundle.pitches(), systems: try bundle.systemMaps())
            }.value
        }
        guard let lease else { throw VerovioError.notReady }
        let engine = lease.engine

        let timemap = try await engine.timemap()
        let entries = try JSONDecoder().decode([TimemapEntry].self, from: timemap)
        let ids = Array(Set(entries.flatMap { $0.on ?? [] }))
        let pitches = try await engine.pitches(for: ids)

        var pages = [String?](repeating: nil, count: pageCount)
        var systems = [PageSystemMap?](repeating: nil, count: pageCount)
        var remaining = Set(0..<pageCount)
        while let page = priorityPages().first(where: remaining.contains) ?? remaining.min() {
            try Task.checkCancellation()
            pages[page] = try await engine.pageSVG(page)
            systems[page] = try await engine.systemMap(page: page)
            remaining.remove(page)
            await Task.yield()   // 표시 웹뷰의 페이지 요청이 끼어들 틈
        }

        let index = FollowIndex.build(entries: entries, pitches: pitches, systems: systems.compactMap { $0 })
        let contents = TypesetCache.Contents(pages: pages.compactMap { $0 }, timemap: timemap, pitches: pitches, systems: systems.compactMap { $0 })
        let cache = typesetter.cache
        let key = key
        // 캐시 저장에 실패해도 뷰어는 엔진으로 계속 동작한다
        if let stored = try? await Task.detached(priority: .utility) { try cache.store(contents, forKey: key) }.value {
            bundle = stored
            releaseEngine()
        }
        return index
    }

    /// 뷰어를 떠날 때. 아직 엔진을 잡고 있으면 놓는다.
    func close() {
        releaseEngine()
    }

    private func releaseEngine() {
        guard let lease else { return }
        self.lease = nil
        typesetter.release(lease)
    }
}

/// 조판 엔진의 독점 사용과 디스크 캐시, 백그라운드 미리 조판을 조정한다.
/// 뷰어가 열 때는 미리 조판을 멈추고 엔진을 넘기며, 뷰어가 엔진을 놓으면 다시 이어간다.
@MainActor
final class ScoreTypesetter {
    static let shared = ScoreTypesetter(engine: .shared, cache: .shared)

    /// 엔진 독점권. 놓을 때까지 다른 문서를 로드하지 않는다.
    final class EngineLease {
        let engine: VerovioEngine
        init(engine: VerovioEngine) { self.engine = engine }
    }

    let engine: VerovioEngine
    let cache: TypesetCache

    private var currentLease: EngineLease?
    private var waiters: [CheckedContinuation<EngineLease, Never>] = []

    private var prefetchQueue: [Score] = []
    private var prefetchTask: Task<Void, Never>?

    init(engine: VerovioEngine, cache: TypesetCache) {
        self.engine = engine
        self.cache = cache
    }

    // MARK: 뷰어

    /// 캐시가 있으면 즉시(엔진 없이) 열고, 없으면 미리 조판을 멈춘 뒤 엔진으로 조판한다.
    func open(fileURL: URL) async throws -> TypesetDocument {
        let cache = cache
        let key = try await Task.detached(priority: .userInitiated) { try cache.key(for: fileURL) }.value
        if let bundle = cache.bundle(forKey: key) {
            return TypesetDocument(key: key, pageCount: bundle.pageCount, bundle: bundle, lease: nil, typesetter: self)
        }
        prefetchTask?.cancel()
        let lease = await acquire()
        do {
            let count = try await engine.load(fileURL: fileURL)
            try Task.checkCancellation()
            return TypesetDocument(key: key, pageCount: count, bundle: nil, lease: lease, typesetter: self)
        } catch {
            release(lease)
            throw error
        }
    }

    // MARK: 엔진 독점

    private func acquire() async -> EngineLease {
        if currentLease == nil {
            let lease = EngineLease(engine: engine)
            currentLease = lease
            return lease
        }
        return await withCheckedContinuation { waiters.append($0) }
    }

    func release(_ lease: EngineLease) {
        guard currentLease === lease else { return }
        engine.clearPageCache()
        if waiters.isEmpty {
            currentLease = nil
            startPrefetchIfIdle()
        } else {
            let next = EngineLease(engine: engine)
            currentLease = next
            waiters.removeFirst().resume(returning: next)
        }
    }

    // MARK: 백그라운드 미리 조판

    /// 보관함 목록으로 대기열을 갱신한다. 캐시가 없는 악보를 목록 순서대로 미리 조판하고,
    /// 목록에 없는 악보의 캐시는 지운다.
    func schedule(_ scores: [Score]) {
        prefetchQueue = scores.filter { $0.kind == .musicXML }
        let cache = cache
        let urls = prefetchQueue.map(\.url)
        Task.detached(priority: .utility) {
            cache.removeAll(except: Set(urls.compactMap { try? cache.key(for: $0) }))
        }
        startPrefetchIfIdle()
    }

    private func startPrefetchIfIdle() {
        guard prefetchTask == nil, currentLease == nil, waiters.isEmpty, !prefetchQueue.isEmpty else { return }
        prefetchTask = Task(priority: .utility) { [weak self] in
            await self?.runPrefetch()
            self?.prefetchTask = nil
            self?.startPrefetchIfIdle()
        }
    }

    private func runPrefetch() async {
        while !Task.isCancelled, currentLease == nil, !prefetchQueue.isEmpty {
            let score = prefetchQueue.removeFirst()
            await prefetch(score)
        }
    }

    private func prefetch(_ score: Score) async {
        let cache = cache
        guard let key = try? await Task.detached(priority: .utility) { try cache.key(for: score.url) }.value else { return }
        guard cache.bundle(forKey: key) == nil else { return }
        guard currentLease == nil, !Task.isCancelled else {
            prefetchQueue.insert(score, at: 0)
            return
        }
        let lease = EngineLease(engine: engine)
        currentLease = lease
        var document: TypesetDocument?
        do {
            let count = try await engine.load(fileURL: score.url)
            let doc = TypesetDocument(key: key, pageCount: count, bundle: nil, lease: lease, typesetter: self)
            document = doc
            _ = try await doc.buildFollowIndex(priorityPages: { [] })
        } catch is CancellationError {
            prefetchQueue.insert(score, at: 0)   // 뷰어에게 양보했으니 나중에 다시
        } catch {
            // 손상 파일 등은 건너뛴다. 뷰어에서 열 때 오류를 보여준다.
        }
        document?.close()
        release(lease)
    }
}
