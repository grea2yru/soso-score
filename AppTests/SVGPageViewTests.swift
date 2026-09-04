import XCTest
import SwiftUI
import WebKit
@testable import SoSoScore

/// 페이지 슬롯의 웹뷰가 페이지를 넘겨도 살아 있는지 확인한다.
/// WKWebView를 만들고 버릴 때마다 WebContent 프로세스가 뜨고 죽으며
/// "Failed to terminate process … Client not entitled" 로그가 남는다.
@MainActor
final class SVGPageViewTests: XCTestCase {
    @MainActor final class Model: ObservableObject {
        @Published var index = 0
        @Published var svgs: [Int: String] = [:]
        let controller = SVGPageController()
    }

    struct Harness: View {
        @ObservedObject var model: Model
        var body: some View {
            SVGPage(index: model.index, svgs: $model.svgs, loadSVG: { _ in nil },
                    highlightIDs: [], controller: model.controller, onTapNormalized: nil)
                .frame(width: 300, height: 400)
        }
    }

    private var window: UIWindow?

    override func tearDown() async throws {
        window?.isHidden = true
        window = nil
    }

    private func show<V: View>(_ view: V) {
        let scene = UIApplication.shared.connectedScenes.first { $0 is UIWindowScene } as? UIWindowScene
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: CGRect(x: 0, y: 0, width: 600, height: 800))
        window.rootViewController = UIHostingController(rootView: view)
        window.makeKeyAndVisible()
        self.window = window
    }

    private func settle() async throws {
        try await Task.sleep(nanoseconds: 400_000_000)
    }

    private func svg(_ label: String) -> String {
        "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 100\"><text y=\"50\">\(label)</text></svg>"
    }

    func testWebViewSurvivesTurningToUnloadedPage() async throws {
        let model = Model()
        show(Harness(model: model))
        try await settle()
        // SVG가 없어도 웹뷰는 이미 만들어져 있다 (로딩 표시가 위를 덮음)
        let webView = try XCTUnwrap(model.controller.webView)

        model.svgs[0] = svg("page 0")
        try await settle()
        XCTAssertTrue(model.controller.webView === webView)

        // 아직 조판되지 않은 페이지로 넘김 → 웹뷰가 파괴되지 않아야 한다
        model.index = 1
        try await settle()
        XCTAssertTrue(model.controller.webView === webView)

        model.svgs[1] = svg("page 1")
        try await settle()
        XCTAssertTrue(model.controller.webView === webView, "페이지 로드 후에도 같은 웹뷰를 써야 한다")

        // 여러 장 연속 넘김 — 같은 웹뷰에 내용만 갈아 끼운다
        NSLog("MARK turns begin")
        for page in 2..<6 {
            model.index = page
            try await settle()
            model.svgs[page] = svg("page \(page)")
            try await settle()
            XCTAssertTrue(model.controller.webView === webView, "page \(page)")
        }
        NSLog("MARK turns end")
    }
}
