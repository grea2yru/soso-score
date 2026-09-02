import Foundation
import PencilKit

/// 악보별 필기(PKDrawing)를 페이지 단위로 파일에 저장한다. 원본 PDF는 건드리지 않는다.
/// 좌표는 PDF 페이지 포인트(회전 적용 후 mediaBox) 기준으로 정규화된 상태로 저장된다.
struct AnnotationStore {
    private struct FileFormat: Codable {
        var pages: [Int: Data]
    }

    let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    func load(for scoreID: String) -> [Int: PKDrawing] {
        guard let data = try? Data(contentsOf: fileURL(scoreID)),
              let file = try? JSONDecoder().decode(FileFormat.self, from: data) else {
            return [:]
        }
        return file.pages.compactMapValues { try? PKDrawing(data: $0) }
    }

    /// 획이 없는 페이지는 저장하지 않고, 전 페이지가 비면 파일 자체를 지운다.
    func save(_ drawings: [Int: PKDrawing], for scoreID: String) throws {
        let pages = drawings
            .filter { !$0.value.strokes.isEmpty }
            .mapValues { $0.dataRepresentation() }
        guard !pages.isEmpty else {
            try? FileManager.default.removeItem(at: fileURL(scoreID))
            return
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(FileFormat(pages: pages))
        try data.write(to: fileURL(scoreID), options: .atomic)
    }

    func move(from oldID: String, to newID: String) {
        try? FileManager.default.moveItem(at: fileURL(oldID), to: fileURL(newID))
    }

    func delete(for scoreID: String) {
        try? FileManager.default.removeItem(at: fileURL(scoreID))
    }

    private func fileURL(_ scoreID: String) -> URL {
        directory.appendingPathComponent("\(scoreID).annotations")
    }
}
