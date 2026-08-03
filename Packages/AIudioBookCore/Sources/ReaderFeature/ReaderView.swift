//
//  ReaderView.swift
//  ReaderFeature
//
//  The reading screen: current chapter in a text view, chapter navigation,
//  table of contents sidebar, reading settings, and resume-at-last-position.
//

import EPUBKit
import LibraryFeature
import SwiftUI

public struct ReaderView: View {
    private let book: Book

    @State private var epub: EPUBBook?
    @State private var currentIndex = 0
    @State private var isTOCVisible = false
    @State private var isSettingsPresented = false
    @State private var isAIPanelVisible = false
    @State private var hasEverOpenedAIPanel = false
    @State private var isTTSSettingsPresented = false
    @State private var tts = TTSController()
    @State private var chapterSpeechText = ""
    @State private var chapterHeadingTexts: Set<String> = []
    @State private var ttsStartOffset: Int? = nil
    @State private var currentPage = 0
    @State private var totalPages = 1
    @State private var loadFailureMessage: String?
    @State private var bookmarkProgress: Double = 0
    @State private var chapterScrollTarget: Double? = nil
    @State private var isBookmarkListPresented = false

    @Environment(BookmarkStore.self) private var bookmarkStore

    @AppStorage("reader.fontSize")      private var fontSize: Double = 17
    @AppStorage("reader.theme")         private var theme: ReaderTheme = .light
    @AppStorage("reader.readingMode")   private var readingMode: ReadingMode = .scroll

    public init(book: Book) {
        self.book = book
    }

    public var body: some View {
        Group {
            if let epub {
                content(for: epub)
            } else if let loadFailureMessage {
                ContentUnavailableView {
                    Label {
                        Text("Unable to Open Book", bundle: .module)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                    }
                } description: {
                    Text(loadFailureMessage)
                }
            } else {
                ProgressView()
                    .task { await load() }
            }
        }
        .navigationTitle(book.title)
    }

    private func content(for epub: EPUBBook) -> some View {
        HStack(spacing: 0) {
            if isTOCVisible {
                TOCSidebar(entries: epub.tableOfContents) { entry in
                    navigate(to: entry, in: epub)
                }
                .frame(width: 260)
                Divider()
            }
            if epub.spine.isEmpty {
                ContentUnavailableView {
                    Label {
                        Text("Unable to Open Book", bundle: .module)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                    }
                }
            } else {
                VStack(spacing: 0) {
                    ChapterTextView(
                        fileURL: epub.spine[currentIndex].fileURL,
                        fontSize: fontSize,
                        theme: theme,
                        readingMode: readingMode,
                        currentPage: currentPage,
                        savedProgress: book.lastChapterProgress,
                        onProgressChange: { book.lastChapterProgress = $0 },
                        highlightRange: tts.currentSentenceRange,
                        onTextReady: { chapterSpeechText = $0 },
                        onSelectionChange: { ttsStartOffset = $0 },
                        onHeadingsReady: { chapterHeadingTexts = $0 },
                        onTotalPagesChanged: { totalPages = $0; currentPage = 0 },
                        scrollTarget: chapterScrollTarget
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Kept permanently in hierarchy once opened so state (history, session) survives toggle.
                    if hasEverOpenedAIPanel {
                        BookAIPanel(epub: epub, bookID: book.bookID)
                            .frame(height: isAIPanelVisible ? 280 : 0)
                            .clipped()
                    }
                }
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    withAnimation { isTOCVisible.toggle() }
                } label: {
                    Label {
                        Text("Table of Contents", bundle: .module)
                    } icon: {
                        Image(systemName: "sidebar.leading")
                    }
                }
                .disabled(epub.tableOfContents.isEmpty)

                Button {
                    currentIndex -= 1
                } label: {
                    Label {
                        Text("Previous Chapter", bundle: .module)
                    } icon: {
                        Image(systemName: "chevron.left")
                    }
                }
                .disabled(currentIndex <= 0)

                Text("\(currentIndex + 1) / \(epub.spine.count)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .font(.subheadline)

                Button {
                    currentIndex += 1
                } label: {
                    Label {
                        Text("Next Chapter", bundle: .module)
                    } icon: {
                        Image(systemName: "chevron.right")
                    }
                }
                .disabled(currentIndex >= epub.spine.count - 1)

                if readingMode == .page {
                    Divider()
                    Button {
                        currentPage -= 1
                    } label: {
                        Label {
                            Text("Previous Page", bundle: .module)
                        } icon: {
                            Image(systemName: "arrow.left")
                        }
                    }
                    .disabled(currentPage <= 0)

                    Text("p. \(currentPage + 1) / \(totalPages)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .font(.subheadline)

                    Button {
                        currentPage += 1
                    } label: {
                        Label {
                            Text("Next Page", bundle: .module)
                        } icon: {
                            Image(systemName: "arrow.right")
                        }
                    }
                    .disabled(currentPage >= totalPages - 1)
                }

                Button {
                    isSettingsPresented.toggle()
                } label: {
                    Label {
                        Text("Display Settings", bundle: .module)
                    } icon: {
                        Image(systemName: "textformat")
                    }
                }
                .popover(isPresented: $isSettingsPresented, arrowEdge: .bottom) {
                    ReaderSettingsView(fontSize: $fontSize, theme: $theme, readingMode: $readingMode)
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isAIPanelVisible.toggle()
                        if isAIPanelVisible { hasEverOpenedAIPanel = true }
                    }
                } label: {
                    Label {
                        Text("Ask AI", bundle: .module)
                    } icon: {
                        Image(systemName: "sparkles")
                            .symbolVariant(isAIPanelVisible ? .fill : .none)
                    }
                }

                let isBookmarked = bookmarkStore.hasBookmark(
                    bookID: book.bookID,
                    spineIndex: currentIndex,
                    progress: book.lastChapterProgress
                )
                Button {
                    toggleBookmark(in: epub)
                } label: {
                    Label {
                        Text(isBookmarked ? "Remove Bookmark" : "Add Bookmark", bundle: .module)
                    } icon: {
                        Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                    }
                }

                Button {
                    isBookmarkListPresented.toggle()
                } label: {
                    Label {
                        Text("Bookmarks List", bundle: .module)
                    } icon: {
                        Image(systemName: "list.bullet.rectangle")
                    }
                }
                .popover(isPresented: $isBookmarkListPresented, arrowEdge: .bottom) {
                    BookmarkListView(
                        bookmarks: bookmarkStore.bookmarks(for: book.bookID),
                        onNavigate: { navigateTo(bookmark: $0) },
                        onDelete: { bookmarkStore.remove(id: $0) }
                    )
                }

                Divider()

                // TTS controls
                Button {
                    if tts.isPlaying || tts.isPaused {
                        tts.pauseResume()
                    } else {
                        tts.play(text: chapterSpeechText, headings: chapterHeadingTexts, from: ttsStartOffset)
                    }
                } label: {
                    Label {
                        Text(tts.isPlaying ? "Pause" : "Play", bundle: .module)
                    } icon: {
                        if tts.isLoading {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: tts.isPlaying ? "pause.fill" : "play.fill")
                        }
                    }
                }
                .disabled((chapterSpeechText.isEmpty && !tts.isPlaying && !tts.isPaused) || tts.isLoading)

                if tts.isPlaying || tts.isPaused {
                    Button { tts.stop() } label: {
                        Label {
                            Text("Stop", bundle: .module)
                        } icon: {
                            Image(systemName: "stop.fill")
                        }
                    }
                }

                Button { isTTSSettingsPresented.toggle() } label: {
                    Label {
                        Text("Read Aloud Settings", bundle: .module)
                    } icon: {
                        Image(systemName: "speaker.wave.2")
                    }
                }
                .popover(isPresented: $isTTSSettingsPresented, arrowEdge: .bottom) {
                    TTSSettingsView(controller: tts)
                }
            }
        }
        .onChange(of: currentIndex) {
            tts.stop()
            chapterSpeechText = ""
            chapterHeadingTexts = []
            ttsStartOffset = nil
            currentPage = 0
            totalPages = 1
            chapterScrollTarget = nil
            book.lastSpineIndex = currentIndex
            book.lastChapterProgress = bookmarkProgress
            bookmarkProgress = 0
        }
        .onChange(of: readingMode) {
            currentPage = 0
            totalPages = 1
        }
    }

    private func load() async {
        do {
            let contentDirectory = try BookLibrary.contentDirectoryURL(for: book)
            let parsed = try await Task.detached {
                try EPUBParser.parse(extractedAt: contentDirectory)
            }.value
            epub = parsed
            if !parsed.spine.isEmpty {
                currentIndex = min(max(book.lastSpineIndex, 0), parsed.spine.count - 1)
            }
            book.lastOpenedAt = .now
        } catch {
            loadFailureMessage = error.localizedDescription
        }
    }

    private func navigate(to entry: EPUBTOCEntry, in epub: EPUBBook) {
        guard let fileURL = entry.fileURL,
              let index = epub.spine.firstIndex(where: { $0.fileURL == fileURL }) else { return }
        currentIndex = index
    }

    // MARK: - Bookmarks

    private func toggleBookmark(in epub: EPUBBook) {
        let progress = book.lastChapterProgress
        if let existing = bookmarkStore.bookmark(
            bookID: book.bookID,
            spineIndex: currentIndex,
            progress: progress
        ) {
            bookmarkStore.remove(id: existing.id)
        } else {
            let label = bookmarkLabel(spineIndex: currentIndex, progress: progress, epub: epub)
            bookmarkStore.add(Bookmark(
                bookID: book.bookID,
                spineIndex: currentIndex,
                chapterProgress: progress,
                label: label
            ))
        }
    }

    private func navigateTo(bookmark: Bookmark) {
        isBookmarkListPresented = false
        if bookmark.spineIndex == currentIndex {
            chapterScrollTarget = bookmark.chapterProgress
        } else {
            bookmarkProgress = bookmark.chapterProgress
            currentIndex = bookmark.spineIndex
        }
    }

    private func bookmarkLabel(spineIndex: Int, progress: Double, epub: EPUBBook) -> String {
        let title = chapterTitle(spineIndex: spineIndex, in: epub)
        let pct = Int(progress * 100)
        return "\(title) – \(pct) %"
    }

    private func chapterTitle(spineIndex: Int, in epub: EPUBBook) -> String {
        let spineURL = epub.spine[spineIndex].fileURL
        func search(_ entries: [EPUBTOCEntry]) -> String? {
            for entry in entries {
                if entry.fileURL == spineURL { return entry.title }
                if let found = search(entry.children) { return found }
            }
            return nil
        }
        return search(epub.tableOfContents) ?? "Chapitre \(spineIndex + 1)"
    }
}

// MARK: - Bookmark list popover

private struct BookmarkListView: View {
    let bookmarks: [Bookmark]
    let onNavigate: (Bookmark) -> Void
    let onDelete: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Signets", bundle: .module)
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            Divider()

            if bookmarks.isEmpty {
                Text("Aucun signet pour ce livre.", bundle: .module)
                    .foregroundStyle(.secondary)
                    .padding(16)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(bookmarks) { bm in
                            HStack(spacing: 10) {
                                Image(systemName: "bookmark.fill")
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 18)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(bm.label)
                                        .lineLimit(2)
                                        .font(.subheadline)
                                    Text(bm.createdAt, style: .date)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Button {
                                    onDelete(bm.id)
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { onNavigate(bm) }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)

                            Divider()
                                .padding(.leading, 44)
                        }
                    }
                }
            }
        }
        .frame(width: 320)
        .frame(maxHeight: bookmarks.isEmpty ? 100 : 360)
    }
}
