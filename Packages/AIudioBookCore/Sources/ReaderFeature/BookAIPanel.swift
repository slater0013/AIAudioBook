//
//  BookAIPanel.swift
//  ReaderFeature
//
//  Chat panel for AI Q&A on the full book using RAG (BookIndexer) + FoundationModels.
//

import EPUBKit
import FoundationModels
import SwiftUI

// MARK: - Data model

private struct ChatMessage: Identifiable {
    let id = UUID()
    enum Role { case user, assistant }
    let role: Role
    var content: String
}

// MARK: - Panel

struct BookAIPanel: View {
    let epub: EPUBBook
    let bookID: UUID

    @State private var messages: [ChatMessage] = []
    @State private var question = ""
    @State private var isThinking = false
    @State private var streamingText = ""
    @State private var errorMessage: String?
    @State private var session: LanguageModelSession?

    // Indexing state
    @State private var bookIndex: BookIndex?
    @State private var isCheckingCache = true    // true until the fast meta-file check completes
    @State private var isLoadingFromCache = false // true while the full data file is being read
    @State private var cacheChunkCount = 0       // shown during isLoadingFromCache
    @State private var isIndexing = false
    @State private var indexingChapter = 0
    @State private var indexingTotal = 0
    @State private var indexError: String?
    @State private var indexingTask: Task<Void, Never>?

    private var model = SystemLanguageModel.default

    init(epub: EPUBBook, bookID: UUID) {
        self.epub = epub
        self.bookID = bookID
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            switch model.availability {
            case .available:
                if let bookIndex {
                    chatContent(index: bookIndex)
                } else if isCheckingCache {
                    loadingStatusView("Vérification du cache IA…")
                } else if isLoadingFromCache {
                    loadingStatusView("Chargement de l'index IA (\(cacheChunkCount) passages)…")
                } else if isIndexing {
                    indexingProgressView
                } else if let indexError {
                    errorView(message: indexError)
                } else {
                    startView
                }
            case .unavailable(let reason):
                unavailableContent(reason: reason)
            }
        }
        // On open: silently check for a cached index (fast disk read).
        .task { await tryLoadFromCache() }
    }

    // MARK: - Loading status view (checking cache or loading index)

    private func loadingStatusView(_ message: String) -> some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Start view

    private var startView: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Activer l'assistant IA", bundle: .module)
                .font(.headline)
            Text(
                "L'assistant analyse le livre avec un modèle IA embarqué et crée une représentation sémantique de chaque passage. Cela permet de retrouver les extraits pertinents pour répondre à vos questions. L'opération peut prendre quelques minutes ; elle n'est faite qu'une seule fois par livre.",
                bundle: .module
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            Button {
                startIndexing()
            } label: {
                Label("Lancer l'analyse IA", systemImage: "brain")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    // MARK: - Indexing progress view

    private var indexingProgressView: some View {
        VStack(spacing: 14) {
            ProgressView(
                value: indexingTotal > 0 ? Double(indexingChapter) / Double(indexingTotal) : nil,
                total: 1.0
            )
            .progressViewStyle(.linear)
            .frame(maxWidth: 300)

            if indexingTotal > 0 {
                Text("Analyse IA… chapitre \(indexingChapter) / \(indexingTotal)", bundle: .module)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else {
                Text("Analyse IA en cours…", bundle: .module)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button(role: .destructive) {
                cancelIndexing()
            } label: {
                Text("Annuler", bundle: .module)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    // MARK: - Error view

    private func errorView(message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                indexError = nil
                startIndexing()
            } label: {
                Text("Réessayer", bundle: .module)
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    // MARK: - Chat UI

    private func chatContent(index: BookIndex) -> some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(messages) { msg in
                            messageBubble(msg)
                                .id(msg.id)
                        }
                        if isThinking {
                            messageBubble(ChatMessage(
                                role: .assistant,
                                content: streamingText.isEmpty ? "…" : streamingText
                            ))
                            .id("streaming")
                        }
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .padding(.horizontal, 14)
                        }
                    }
                    .padding(.vertical, 10)
                }
                .onChange(of: streamingText) {
                    withAnimation { proxy.scrollTo("streaming", anchor: .bottom) }
                }
                .onChange(of: messages.count) {
                    withAnimation { proxy.scrollTo(messages.last?.id, anchor: .bottom) }
                }
            }
            Divider()
            inputBar(index: index)
        }
    }

    private func messageBubble(_ message: ChatMessage) -> some View {
        HStack(alignment: .bottom) {
            if message.role == .user { Spacer(minLength: 48) }
            Text(message.content)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    message.role == .user
                        ? AnyShapeStyle(Color.accentColor)
                        : AnyShapeStyle(Color.secondary.opacity(0.15)),
                    in: RoundedRectangle(cornerRadius: 14)
                )
                .foregroundStyle(message.role == .user ? Color.white : Color.primary)
            if message.role == .assistant { Spacer(minLength: 48) }
        }
        .padding(.horizontal, 12)
    }

    private func inputBar(index: BookIndex) -> some View {
        HStack(spacing: 8) {
            TextField(String(localized: "Posez une question sur le livre…", bundle: .module), text: $question)
                .textFieldStyle(.plain)
                .onSubmit { sendQuestion(index: index) }
            Button { sendQuestion(index: index) } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(canSend ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var canSend: Bool {
        !question.trimmingCharacters(in: .whitespaces).isEmpty && !isThinking
    }

    // MARK: - Unavailable

    @ViewBuilder
    private func unavailableContent(reason: SystemLanguageModel.Availability.UnavailableReason) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles.slash")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text(unavailableMessage(for: reason))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func unavailableMessage(for reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible:
            return String(localized: "Apple Intelligence is not supported on this device.", bundle: .module)
        case .appleIntelligenceNotEnabled:
            return String(localized: "Enable Apple Intelligence in System Settings to use AI Q&A.", bundle: .module)
        case .modelNotReady:
            return String(localized: "The AI model is loading. Please try again in a moment.", bundle: .module)
        default:
            return String(localized: "Apple Intelligence is not available.", bundle: .module)
        }
    }

    // MARK: - Cache check on open

    private func tryLoadFromCache() async {
        guard bookIndex == nil else { isCheckingCache = false; return }
        let bid = bookID
        let spineCount = epub.spine.count

        // Phase 1: fast meta-file check — reads ~80 bytes, returns in microseconds.
        let chunkCount = await Task.detached(priority: .utility) {
            BookIndexer.cachedChunkCount(bookID: bid, spineCount: spineCount)
        }.value
        isCheckingCache = false

        guard let chunkCount else { return }  // pas de cache valide → vue "Démarrer l'indexation"

        // Phase 2: lecture complète du fichier de données (embeddings en binaire, ~1 s).
        cacheChunkCount = chunkCount
        isLoadingFromCache = true
        let cached = await Task.detached(priority: .utility) {
            BookIndexer.loadFromCache(bookID: bid, spineCount: spineCount)
        }.value
        isLoadingFromCache = false

        if let cached {
            bookIndex = cached
            if model.isAvailable { session = makeSession() }
        }
    }

    // MARK: - Indexing control

    private func startIndexing() {
        guard !isIndexing else { return }
        isIndexing = true
        indexingChapter = 0
        indexingTotal = epub.spine.count
        indexError = nil

        let epubCopy = epub
        let bid = bookID
        indexingTask = Task {
            do {
                for try await event in BookIndexer.stream(epub: epubCopy, bookID: bid) {
                    switch event {
                    case .progress(let chapter, let total):
                        indexingChapter = chapter
                        indexingTotal = total
                    case .completed(let idx):
                        bookIndex = idx
                        if model.isAvailable { session = makeSession() }
                    }
                }
            } catch is CancellationError {
                // User cancelled — return to start view.
            } catch {
                indexError = error.localizedDescription
            }
            isIndexing = false
            indexingTask = nil
        }
    }

    private func cancelIndexing() {
        indexingTask?.cancel()
        indexingTask = nil
        isIndexing = false
        indexingChapter = 0
    }

    // MARK: - Session

    private func makeSession() -> LanguageModelSession {
        let authors = epub.metadata.authors.joined(separator: ", ")
        let bookInfo = authors.isEmpty ? "\"\(epub.metadata.title)\"" : "\"\(epub.metadata.title)\" de \(authors)"
        let localeHint = Locale.Language(identifier: "en_US").isEquivalent(to: Locale.current.language)
            ? ""
            : "The person's locale is \(Locale.current.identifier). "
        let toc = buildTOCText()
        let tocSection = toc.isEmpty ? "" : "\n\nTABLE OF CONTENTS:\n\(toc)"
        return LanguageModelSession(instructions: """
            You are a concise reading assistant for the book \(bookInfo).\(tocSection)
            Each question will also include relevant passages retrieved from the book — use them to answer.
            \(localeHint)Respond in the same language as the question. Quote the text when relevant.
            """)
    }

    private func buildTOCText() -> String {
        func format(_ entries: [EPUBTOCEntry], depth: Int) -> String {
            entries.map { entry in
                let indent = String(repeating: "  ", count: depth)
                let sub = format(entry.children, depth: depth + 1)
                return indent + "- " + entry.title + (sub.isEmpty ? "" : "\n" + sub)
            }.joined(separator: "\n")
        }
        return format(epub.tableOfContents, depth: 0)
    }

    // MARK: - Send

    private func sendQuestion(index: BookIndex) {
        let q = question.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        question = ""
        messages.append(ChatMessage(role: .user, content: q))
        isThinking = true
        streamingText = ""
        errorMessage = nil

        Task {
            if session == nil { session = makeSession() }
            guard let session else { return }

            let chunks = index.topChunks(for: q, k: 8)
            let augmented = buildAugmentedQuery(question: q, chunks: chunks)

            do {
                let stream = session.streamResponse(to: augmented)
                for try await snapshot in stream {
                    streamingText = snapshot.content
                }
                messages.append(ChatMessage(role: .assistant, content: streamingText))
            } catch let genError as LanguageModelSession.GenerationError {
                switch genError {
                case .exceededContextWindowSize:
                    self.session = makeSession()
                    errorMessage = String(
                        localized: "Context limit reached. Session reset — please ask again.",
                        bundle: .module
                    )
                default:
                    errorMessage = genError.localizedDescription
                }
            } catch {
                errorMessage = error.localizedDescription
            }

            isThinking = false
            streamingText = ""
        }
    }

    private func buildAugmentedQuery(question: String, chunks: [BookChunk]) -> String {
        guard !chunks.isEmpty else { return question }
        let passages = chunks
            .map { "[\($0.chapterTitle)]\n\($0.text)" }
            .joined(separator: "\n\n---\n\n")
        return """
            Passages pertinents du livre :

            \(passages)

            ---
            Question : \(question)
            """
    }
}
