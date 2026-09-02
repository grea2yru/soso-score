import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var library: ScoreLibraryStore
    @State private var showImporter = false
    @State private var importError: String?
    @State private var renamingScore: Score?
    @State private var newTitle = ""

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 20)]

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
                } else {
                    LazyVGrid(columns: columns, spacing: 24) {
                        ForEach(library.scores) { score in
                            NavigationLink(value: score) {
                                ScoreCell(score: score)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("이름 변경") {
                                    newTitle = score.title
                                    renamingScore = score
                                }
                                Button("삭제", role: .destructive) {
                                    library.delete(score)
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("악보 보관함")
            .navigationDestination(for: Score.self) { score in
                ScoreViewerView(score: score)
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
                    do { try library.importPDF(from: url) }
                    catch { importError = error.localizedDescription }
                }
            }
            .alert("가져오기 실패", isPresented: .constant(importError != nil)) {
                Button("확인") { importError = nil }
            } message: {
                Text(importError ?? "")
            }
            .alert("이름 변경", isPresented: .constant(renamingScore != nil)) {
                TextField("새 이름", text: $newTitle)
                Button("확인") {
                    if let score = renamingScore { library.rename(score, to: newTitle) }
                    renamingScore = nil
                }
                Button("취소", role: .cancel) { renamingScore = nil }
            }
        }
        .onOpenURL { url in
            // Files/AirDrop의 "다음으로 열기"로 전달된 PDF
            try? library.importPDF(from: url)
        }
    }
}

struct ScoreCell: View {
    @EnvironmentObject var library: ScoreLibraryStore
    let score: Score

    var body: some View {
        VStack(spacing: 8) {
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

            Text(score.title)
                .font(.callout)
                .lineLimit(1)
        }
    }
}
