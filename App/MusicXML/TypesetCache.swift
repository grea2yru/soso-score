import CryptoKit
import Foundation
import ScoreFollowCore

/// 디스크에 저장된 조판 결과물 하나. 페이지 SVG·타임맵·피치·시스템 맵을 파일에서 읽는다.
struct TypesetBundle: Sendable {
    let directory: URL
    let pageCount: Int

    func pageSVG(_ index: Int) throws -> String {
        try String(contentsOf: directory.appendingPathComponent(TypesetCache.pageFile(index)), encoding: .utf8)
    }

    func timemapEntries() throws -> [TimemapEntry] {
        try JSONDecoder().decode([TimemapEntry].self, from: Data(contentsOf: directory.appendingPathComponent(TypesetCache.timemapFile)))
    }

    func pitches() throws -> [String: Int] {
        try JSONDecoder().decode([String: Int].self, from: Data(contentsOf: directory.appendingPathComponent(TypesetCache.pitchesFile)))
    }

    func systemMaps() throws -> [PageSystemMap] {
        try JSONDecoder().decode([PageSystemMap].self, from: Data(contentsOf: directory.appendingPathComponent(TypesetCache.systemsFile)))
    }
}

/// 조판 결과 디스크 캐시. 키는 파일 내용 해시 + 조판 버전이라 이름을 바꿔도 유지되고,
/// 조판 옵션이 바뀌면(`layoutVersion`) 옛 캐시는 자동으로 무시된다.
struct TypesetCache: Sendable {
    /// verovio.html의 조판 옵션이나 결과물 형식이 바뀌면 올린다
    static let layoutVersion = 1

    static let shared = TypesetCache(
        directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Typeset", isDirectory: true))

    static let metaFile = "meta.json"
    static let timemapFile = "timemap.json"
    static let pitchesFile = "pitches.json"
    static let systemsFile = "systems.json"
    static func pageFile(_ index: Int) -> String { "page-\(index).svg" }

    let directory: URL

    /// 저장할 조판 결과물 (페이지 순서대로)
    struct Contents: Sendable {
        var pages: [String]
        var timemap: Data
        var pitches: [String: Int]
        var systems: [PageSystemMap]
    }

    private struct Meta: Codable {
        let pageCount: Int
        let layoutVersion: Int
    }

    /// 파일 내용 SHA-256 앞 16바이트 + 조판 버전
    func key(for fileURL: URL) throws -> String {
        let data = try Data(contentsOf: fileURL)
        let digest = SHA256.hash(data: data).prefix(16).map { String(format: "%02x", $0) }.joined()
        return "\(digest)-v\(Self.layoutVersion)"
    }

    /// 완성된 캐시가 있으면 돌려준다 (meta.json은 저장 마지막 단계에 쓰이므로 있으면 완전하다)
    func bundle(forKey key: String) -> TypesetBundle? {
        let dir = directory.appendingPathComponent(key, isDirectory: true)
        guard let data = try? Data(contentsOf: dir.appendingPathComponent(Self.metaFile)),
              let meta = try? JSONDecoder().decode(Meta.self, from: data),
              meta.layoutVersion == Self.layoutVersion, meta.pageCount > 0 else { return nil }
        return TypesetBundle(directory: dir, pageCount: meta.pageCount)
    }

    /// 임시 폴더에 모두 쓴 뒤 한 번에 옮긴다 — 중간에 중단돼도 반쪽 캐시가 남지 않는다
    func store(_ contents: Contents, forKey key: String) throws -> TypesetBundle {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let tmp = directory.appendingPathComponent(".tmp-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        do {
            for (index, svg) in contents.pages.enumerated() {
                try Data(svg.utf8).write(to: tmp.appendingPathComponent(Self.pageFile(index)))
            }
            try contents.timemap.write(to: tmp.appendingPathComponent(Self.timemapFile))
            try JSONEncoder().encode(contents.pitches).write(to: tmp.appendingPathComponent(Self.pitchesFile))
            try JSONEncoder().encode(contents.systems).write(to: tmp.appendingPathComponent(Self.systemsFile))
            let meta = Meta(pageCount: contents.pages.count, layoutVersion: Self.layoutVersion)
            try JSONEncoder().encode(meta).write(to: tmp.appendingPathComponent(Self.metaFile))

            let dest = directory.appendingPathComponent(key, isDirectory: true)
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.moveItem(at: tmp, to: dest)
            return TypesetBundle(directory: dest, pageCount: contents.pages.count)
        } catch {
            try? fm.removeItem(at: tmp)
            throw error
        }
    }

    func remove(forKey key: String) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(key, isDirectory: true))
    }

    /// 보관함에 없는 악보의 캐시(고아)를 지운다. 쓰는 중인 임시 폴더는 한 시간이 지난 것만 치운다.
    func removeAll(except keys: Set<String>) {
        let fm = FileManager.default
        let items = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for item in items where !keys.contains(item.lastPathComponent) {
            if item.lastPathComponent.hasPrefix(".tmp-") {
                let modified = (try? item.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                guard Date().timeIntervalSince(modified) > 3600 else { continue }
            }
            try? fm.removeItem(at: item)
        }
    }
}
