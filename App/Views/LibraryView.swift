import SwiftUI

struct LibraryView: View {
    @ObservedObject var library: ScoreLibraryStore
    @State private var showImporter = false
    @State private var importError: String?
    @State private var renamingScore: Score?
    @State private var newTitle = ""
    @State private var searchText = ""
    @State private var favoritesOnly = false

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 20)]

    private var visibleScores: [Score] {
        library.filteredScores(query: searchText, favoritesOnly: favoritesOnly)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if library.scores.isEmpty {
                    ContentUnavailableView(
                        "악보가 없습니다",
                        systemImage: "music.note.list",
                        description: Text("오른쪽 위 + 버튼으로 PDF 악보를 가져오세요.")
                    )
                    .padding(.top, 120)
                } else if visibleScores.isEmpty {
                    if favoritesOnly && searchText.isEmpty {
                        ContentUnavailableView(
                            "즐겨찾기한 악보가 없습니다",
                            systemImage: "star",
                            description: Text("악보 카드의 ⋯ 메뉴에서 즐겨찾기에 추가하세요.")
                        )
                        .padding(.top, 120)
                    } else {
                        ContentUnavailableView.search(text: searchText)
                            .padding(.top, 120)
                    }
                } else {
                    LazyVGrid(columns: columns, spacing: 24) {
                        ForEach(visibleScores) { score in
                            ScoreCell(library: library, score: score, onRename: { beginRename(score) })
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("악보 보관함")
            .searchable(text: $searchText, prompt: "제목으로 검색")
            .navigationDestination(for: Score.self) { score in
                PDFScoreViewer(score: score, library: library)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Toggle(isOn: $favoritesOnly) {
                        Image(systemName: favoritesOnly ? "star.fill" : "star")
                    }
                    .toggleStyle(.button)
                    .accessibilityLabel("즐겨찾기만 보기")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showImporter = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.pdf],
                allowsMultipleSelection: true
            ) { result in
                guard case .success(let urls) = result else { return }
                for url in urls {
                    do { try library.importFile(from: url) }
                    catch { importError = error.localizedDescription }
                }
            }
            .alert("가져오기 실패", isPresented: .constant(importError != nil)) {
                Button("확인") { importError = nil }
            } message: {
                Text(importError ?? "")
            }
            .alert("제목 변경", isPresented: .constant(renamingScore != nil)) {
                TextField("악보 제목", text: $newTitle)
                Button("확인") {
                    if let score = renamingScore { library.rename(score, to: newTitle) }
                    renamingScore = nil
                }
                Button("취소", role: .cancel) { renamingScore = nil }
            }
        }
        .onOpenURL { url in
            // Files/AirDrop의 "다음으로 열기"로 전달된 PDF
            try? library.importFile(from: url)
        }
    }

    private func beginRename(_ score: Score) {
        newTitle = score.title
        renamingScore = score
    }
}

/// 악보 카드. 썸네일은 뷰어로 이동하는 링크, 제목 옆 ⋯ 메뉴는 링크 바깥에 두어
/// 탭이 링크에 가로채이지 않게 한다.
struct ScoreCell: View {
    @ObservedObject var library: ScoreLibraryStore
    let score: Score
    let onRename: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            NavigationLink(value: score) {
                thumbnail
            }
            .buttonStyle(.plain)
            .contextMenu { ScoreActions(library: library, score: score, onRename: onRename) }

            HStack(spacing: 4) {
                Text(score.title)
                    .font(.callout)
                    .lineLimit(1)
                Menu {
                    ScoreActions(library: library, score: score, onRename: onRename)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("\(score.title) 메뉴")
            }
            .frame(width: 160)
        }
    }

    private var thumbnail: some View {
        Group {
            if let image = library.thumbnail(for: score, size: CGSize(width: 160, height: 220)) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "doc.richtext")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 160, height: 220)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 2)
        .overlay(alignment: .topTrailing) {
            if library.isFavorite(score) {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                    .shadow(radius: 1)
                    .padding(6)
            }
        }
    }
}

/// 컨텍스트 메뉴와 ⋯ 메뉴가 공유하는 동작 목록
struct ScoreActions: View {
    @ObservedObject var library: ScoreLibraryStore
    let score: Score
    let onRename: () -> Void

    var body: some View {
        Button {
            library.toggleFavorite(score)
        } label: {
            Label(library.isFavorite(score) ? "즐겨찾기 해제" : "즐겨찾기 추가",
                  systemImage: library.isFavorite(score) ? "star.slash" : "star")
        }
        Button {
            onRename()
        } label: {
            Label("제목 변경", systemImage: "pencil")
        }
        Button(role: .destructive) {
            library.delete(score)
        } label: {
            Label("삭제", systemImage: "trash")
        }
    }
}
