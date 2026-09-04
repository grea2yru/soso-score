import SwiftUI
import WebKit

/// 표시 웹뷰에 JS 질의를 보내기 위한 핸들 (페이지별 1개)
@MainActor
final class SVGPageController: ObservableObject {
    weak var webView: WKWebView?

    /// 페이지 내 정규화 좌표(0…1)에 있는 마디(g.measure)의 id
    func measureID(atX x: CGFloat, y: CGFloat) async -> String? {
        guard let webView else { return nil }
        let js = """
        (function(){
          const e = document.elementFromPoint(\(x) * window.innerWidth, \(y) * window.innerHeight);
          const m = e && e.closest('g.measure');
          return m ? m.id : '';
        })()
        """
        let result = try? await webView.evaluateJavaScript(js) as? String
        return (result?.isEmpty ?? true) ? nil : result
    }
}

/// Verovio가 만든 SVG 페이지 하나를 표시하는 가벼운 웹뷰.
/// 상호작용은 받지 않는다(탭 영역·필기 캔버스가 위에서 처리).
///
/// 페이지를 넘겨도 슬롯의 웹뷰는 그대로 두고 내용만 갈아 끼운다 — WKWebView를 만들고 버릴 때마다
/// WebKit이 웹 콘텐츠 프로세스를 종료하며 "Failed to terminate process … Client not entitled" 로그를 남긴다.
/// `svg`가 nil이면(아직 조판 전) 이전 내용을 유지한다. 부모가 그 위에 로딩 표시를 덮는다.
struct SVGPageView: UIViewRepresentable {
    let svg: String?
    /// 하이라이트할 SVG 요소 id 목록 (따라가기)
    var highlightIDs: [String] = []
    var controller: SVGPageController? = nil

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        controller?.webView = webView
        webView.isOpaque = false
        webView.backgroundColor = .white
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isUserInteractionEnabled = false
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        controller?.webView = webView
        guard let svg else { return }
        if context.coordinator.loadedSVG != svg {
            context.coordinator.loadedSVG = svg
            context.coordinator.pendingHighlight = highlightIDs
            webView.loadHTMLString(Self.html(for: svg), baseURL: nil)
        } else if context.coordinator.appliedHighlight != highlightIDs {
            context.coordinator.apply(highlightIDs, to: webView)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedSVG: String?
        var appliedHighlight: [String] = []
        var pendingHighlight: [String] = []

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            apply(pendingHighlight, to: webView)
        }

        func apply(_ ids: [String], to webView: WKWebView) {
            appliedHighlight = ids
            let json = (try? JSONSerialization.data(withJSONObject: ids))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
            webView.evaluateJavaScript("window.setHighlight(\(json)); 0")
        }
    }

    static func html(for svg: String) -> String {
        """
        <!DOCTYPE html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, user-scalable=no">
        <style>
          html, body { margin:0; padding:0; width:100%; height:100%; background:#fff; overflow:hidden; }
          svg { width:100%; height:100%; display:block; }
          .highlighted, .highlighted * { fill:#e0532f !important; color:#e0532f !important; stroke:#e0532f; }
        </style></head><body>\(svg)
        <script>
          window.setHighlight = function(ids) {
            document.querySelectorAll('.highlighted').forEach(e => e.classList.remove('highlighted'));
            ids.forEach(id => { const e = document.getElementById(id); if (e) e.classList.add('highlighted'); });
          };
        </script></body></html>
        """
    }
}
