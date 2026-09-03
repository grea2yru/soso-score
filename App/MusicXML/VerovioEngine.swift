import Foundation
import WebKit
import ScoreFollowCore

enum VerovioError: LocalizedError {
    case notReady
    case loadFailed(String)
    case scriptFailed(String)

    var errorDescription: String? {
        switch self {
        case .notReady: return L10n.string("악보 엔진이 준비되지 않았습니다.")
        case .loadFailed(let detail): return L10n.string("악보를 열 수 없습니다. (\(detail))")
        case .scriptFailed(let detail): return L10n.string("악보 렌더링 오류: \(detail)")
        }
    }
}

/// 페이지 안의 시스템(줄) 구성: 음표/마디 id → 시스템 순번
struct PageSystemMap: Codable, Sendable {
    let count: Int
    let notes: [String: Int]
    let measures: [String: Int]
}

/// Verovio(WASM)를 숨김 WKWebView에 올려 MusicXML을 A4 비율 고정 가상 페이지로 조판한다.
/// 한 번에 악보 하나만 열려 있으며, 페이지 SVG는 메모리에 캐시한다.
/// 여러 곳에서 동시에 쓰면 문서가 뒤바뀌므로 독점 사용은 `ScoreTypesetter`가 조정한다.
@MainActor
final class VerovioEngine {
    static let shared = VerovioEngine()

    private let webView: WKWebView
    private var isReady = false
    private var pageCache: [Int: String] = [:]

    init() {
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        if let url = Bundle.main.url(forResource: "verovio", withExtension: "html", subdirectory: "verovio") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
    }

    /// WASM 초기화 완료를 최대 30초 기다린다 (100ms 폴링)
    private func waitUntilReady() async throws {
        if isReady { return }
        for _ in 0..<300 {
            if let ready = try? await webView.evaluateJavaScript("window.vrvReady === true") as? Bool, ready {
                isReady = true
                return
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw VerovioError.notReady
    }

    private func evaluate(_ script: String) async throws -> Any? {
        do {
            return try await webView.evaluateJavaScript(script)
        } catch {
            throw VerovioError.scriptFailed(error.localizedDescription)
        }
    }

    /// 파일을 로드하고 페이지 수를 반환한다. .mxl(ZIP)은 자동 판별.
    func load(fileURL: URL) async throws -> Int {
        try await waitUntilReady()
        let data = try Data(contentsOf: fileURL)
        let isZip = fileURL.pathExtension.lowercased() == "mxl" || data.starts(with: [0x50, 0x4B])
        pageCache = [:]
        let result = try await evaluate("window.vrv.load(\"\(data.base64EncodedString())\", \(isZip))")
        guard let count = result as? Int, count > 0 else {
            throw VerovioError.loadFailed(L10n.string("조판 실패"))
        }
        return count
    }

    func pageSVG(_ index: Int) async throws -> String {
        if let cached = pageCache[index] { return cached }
        guard let svg = try await evaluate("window.vrv.pageSVG(\(index + 1))") as? String else {
            throw VerovioError.scriptFailed(L10n.string("SVG 없음"))
        }
        pageCache[index] = svg
        return svg
    }

    /// 메모리의 페이지 SVG를 비운다 (문서를 다 쓴 뒤 메모리 회수)
    func clearPageCache() {
        pageCache = [:]
    }

    func timemap() async throws -> Data {
        guard let json = try await evaluate("window.vrv.timemap()") as? String else {
            throw VerovioError.scriptFailed(L10n.string("타임맵 없음"))
        }
        return Data(json.utf8)
    }

    func timemapEntries() async throws -> [TimemapEntry] {
        try JSONDecoder().decode([TimemapEntry].self, from: try await timemap())
    }

    /// 음표 id → MIDI 피치. JS 쪽에서 MEI를 한 번 파싱해 만든 표를 조회한다 (한 번의 JS 호출)
    func pitches(for ids: [String]) async throws -> [String: Int] {
        let idsJSON = String(data: try JSONSerialization.data(withJSONObject: ids), encoding: .utf8) ?? "[]"
        let escaped = idsJSON
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        guard let json = try await evaluate("window.vrv.pitches('\(escaped)')") as? String else {
            throw VerovioError.scriptFailed(L10n.string("피치 조회 실패"))
        }
        return try JSONDecoder().decode([String: Int].self, from: Data(json.utf8))
    }

    func systemMap(page index: Int) async throws -> PageSystemMap {
        guard let json = try await evaluate("window.vrv.systemMap(\(index + 1))") as? String else {
            throw VerovioError.scriptFailed(L10n.string("시스템 맵 실패"))
        }
        return try JSONDecoder().decode(PageSystemMap.self, from: Data(json.utf8))
    }

    func pageWithElement(_ id: String) async throws -> Int {
        let escaped = id.replacingOccurrences(of: "\"", with: "\\\"")
        guard let page = try await evaluate("window.vrv.pageWithElement(\"\(escaped)\")") as? Int else {
            throw VerovioError.scriptFailed(L10n.string("페이지 조회 실패"))
        }
        return page - 1
    }
}
