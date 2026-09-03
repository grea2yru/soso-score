import Foundation
import PDFKit
import UniformTypeIdentifiers

extension UTType {
    /// .musicxml (Info.plist UTImportedTypeDeclarations에 선언)
    static let musicXML = UTType(importedAs: "com.yru.musicxml")
    /// .mxl (압축 MusicXML)
    static let mxl = UTType(importedAs: "com.yru.mxl")
}

/// 악보 종류. 폴더·확장자·UserDefaults 키·검증 규칙을 한곳에 모은다.
enum ScoreKind: String, CaseIterable, Hashable {
    case pdf
    case musicXML

    var title: String {
        switch self {
        case .pdf: return "PDF 악보"
        case .musicXML: return "디지털 악보"
        }
    }

    var symbolName: String {
        switch self {
        case .pdf: return "doc.richtext"
        case .musicXML: return "music.note.list"
        }
    }

    /// Documents 아래 하위 폴더. nil이면 Documents 루트(기존 PDF 위치 유지)
    var subdirectory: String? {
        switch self {
        case .pdf: return nil
        case .musicXML: return "MusicXML"
        }
    }

    var allowedExtensions: Set<String> {
        switch self {
        case .pdf: return ["pdf"]
        case .musicXML: return ["musicxml", "mxl", "xml"]
        }
    }

    var contentTypes: [UTType] {
        switch self {
        case .pdf: return [.pdf]
        case .musicXML: return [.musicXML, .mxl, .xml]
        }
    }

    var favoritesKey: String {
        switch self {
        case .pdf: return "favoriteScoreIDs"
        case .musicXML: return "favoriteScoreIDs.musicxml"
        }
    }

    var samplesInstalledKey: String {
        switch self {
        case .pdf: return "didInstallSamples"
        case .musicXML: return "didInstallSamples.musicxml"
        }
    }

    var lastPageKeyPrefix: String {
        switch self {
        case .pdf: return "lastPage."
        case .musicXML: return "lastPage.musicxml."
        }
    }

    /// 가져오기 안내에 쓰는 형식 설명
    var formatDescription: String {
        switch self {
        case .pdf: return "PDF"
        case .musicXML: return "MusicXML(.musicxml/.mxl)"
        }
    }

    static func kind(forExtension ext: String) -> ScoreKind? {
        let lower = ext.lowercased()
        return allCases.first { $0.allowedExtensions.contains(lower) }
    }

    /// 가져오기 전에 파일이 이 종류로 열릴 수 있는지 가볍게 검사한다.
    func validate(fileAt url: URL) -> Bool {
        guard allowedExtensions.contains(url.pathExtension.lowercased()) else { return false }
        switch self {
        case .pdf:
            return PDFDocument(url: url) != nil
        case .musicXML:
            guard let handle = try? FileHandle(forReadingFrom: url),
                  let head = try? handle.read(upToCount: 64 * 1024) else { return false }
            if url.pathExtension.lowercased() == "mxl" {
                return head.starts(with: [0x50, 0x4B])   // ZIP 매직
            }
            guard let text = String(data: head, encoding: .utf8) else { return false }
            return text.contains("<score-partwise") || text.contains("<score-timewise")
        }
    }
}
