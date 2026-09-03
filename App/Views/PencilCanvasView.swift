import SwiftUI
import PencilKit

/// 페이지 위에 올라가는 PencilKit 필기 레이어.
/// `drawing`은 페이지 포인트 좌표계로 주고받으며, 화면 표시 시 `scale`로 확대/축소한다.
struct PencilCanvasView: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    /// 화면에 표시된 페이지 크기 ÷ 페이지 포인트 크기
    let scale: CGFloat
    /// 필기 모드 여부. 꺼져 있으면 표시만 하고 터치는 아래로 통과시킨다.
    let isActive: Bool
    let toolPicker: PKToolPicker

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.isScrollEnabled = false
        canvas.drawingPolicy = .default
        canvas.delegate = context.coordinator
        toolPicker.addObserver(canvas)
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        context.coordinator.parent = self

        if context.coordinator.appliedScale != scale {
            // 페이지 좌표 → 화면 좌표. 회전 등으로 표시 크기가 바뀔 때만 다시 적용.
            // 프로그램적 설정에도 canvasViewDrawingDidChange가 불리므로, 뷰 업데이트 중
            // 바인딩(@State)을 되쓰지 않도록 콜백을 잠시 무시한다.
            context.coordinator.isApplyingProgrammatically = true
            canvas.drawing = drawing.transformed(using: CGAffineTransform(scaleX: scale, y: scale))
            context.coordinator.isApplyingProgrammatically = false
            context.coordinator.appliedScale = scale
        }

        canvas.isUserInteractionEnabled = isActive
        if isActive {
            toolPicker.setVisible(true, forFirstResponder: canvas)
            DispatchQueue.main.async { canvas.becomeFirstResponder() }
        } else {
            toolPicker.setVisible(false, forFirstResponder: canvas)
            if canvas.isFirstResponder { canvas.resignFirstResponder() }
        }
    }

    static func dismantleUIView(_ canvas: PKCanvasView, coordinator: Coordinator) {
        coordinator.parent.toolPicker.removeObserver(canvas)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: PencilCanvasView
        var appliedScale: CGFloat = 0
        /// updateUIView에서 코드로 drawing을 설정하는 동안 true
        var isApplyingProgrammatically = false

        init(_ parent: PencilCanvasView) { self.parent = parent }

        func canvasViewDrawingDidChange(_ canvas: PKCanvasView) {
            guard !isApplyingProgrammatically else { return }
            // 화면 좌표 → 페이지 좌표로 되돌려 저장
            let inverse = CGAffineTransform(scaleX: 1 / parent.scale, y: 1 / parent.scale)
            parent.drawing = canvas.drawing.transformed(using: inverse)
        }
    }
}
