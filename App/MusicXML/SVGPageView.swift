import SwiftUI
import WebKit

/// Verovio가 만든 SVG 페이지 하나를 표시하는 가벼운 웹뷰.
/// 상호작용은 받지 않는다(탭 영역·필기 캔버스가 위에서 처리).
struct SVGPageView: UIViewRepresentable {
    let svg: String
    /// 하이라이트할 SVG 요소 id 목록 (2B 따라가기에서 사용)
    var highlightIDs: [String] = []

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.isOpaque = false
        webView.backgroundColor = .white
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isUserInteractionEnabled = false
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
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
