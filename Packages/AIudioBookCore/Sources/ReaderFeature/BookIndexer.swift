//
//  BookIndexer.swift
//  ReaderFeature
//
//  On-device RAG engine: chunks every chapter, embeds with NLEmbedding,
//  persists the index to Application Support, and retrieves relevant passages.
//

import EPUBKit
import Foundation
import NaturalLanguage

// MARK: - BookChunk

struct BookChunk: Sendable {
    let text: String
    let chapterTitle: String
    let chapterIndex: Int
    let embedding: [Double]
}

// MARK: - BookIndex

struct BookIndex: Sendable {
    let chunks: [BookChunk]

    /// Returns up to `k` most relevant chunks for `query`.
    /// For contrastive questions ("X mais Y"), runs two searches and merges.
    func topChunks(for query: String, k: Int = 8) -> [BookChunk] {
        guard let model = Self.bestEmbeddingModel(for: query) else {
            return Array(chunks.prefix(k))
        }
        if isContrastive(query) {
            let parts = contrastiveParts(of: query)
            var seen = Set<String>()
            var merged: [BookChunk] = []
            let perPart = max(2, k / parts.count + 1)
            for part in parts {
                guard let vec = vectorize(part, model: model) else { continue }
                for chunk in ranked(by: vec, k: perPart) {
                    if seen.insert(chunk.text).inserted { merged.append(chunk) }
                }
            }
            return Array(merged.prefix(k))
        }
        guard let queryVec = vectorize(query, model: model) else {
            return Array(chunks.prefix(k))
        }
        return ranked(by: queryVec, k: k)
    }

    // MARK: Private – retrieval

    private func ranked(by vec: [Double], k: Int) -> [BookChunk] {
        chunks
            .map { ($0, cosine(vec, $0.embedding)) }
            .sorted { $0.1 > $1.1 }
            .prefix(k)
            .map(\.0)
    }

    private func cosine(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot = 0.0, na = 0.0, nb = 0.0
        for i in a.indices { dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i] }
        let denom = sqrt(na) * sqrt(nb)
        return denom > 0 ? dot / denom : 0
    }

    private func vectorize(_ text: String, model: NLEmbedding) -> [Double]? {
        // Sentence embedding: supports arbitrary strings directly.
        if let vec = model.vector(for: text) { return vec }
        // Word embedding fallback: mean-pool individual tokens.
        var sum = [Double](repeating: 0, count: model.dimension)
        var count = 0
        let tok = NLTokenizer(unit: .word)
        tok.string = text
        tok.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            if let vec = model.vector(for: String(text[range]).lowercased()) {
                for (i, v) in vec.enumerated() { sum[i] += v }
                count += 1
            }
            return true
        }
        return count > 0 ? sum.map { $0 / Double(count) } : nil
    }

    // MARK: Private – contrastive detection

    private static let contrastiveMarkers = [
        "mais ", "pourtant", "cependant", "en revanche", "au contraire",
        "contrairement", "paradoxalement", "contradiction", "contredire",
        "however", "whereas", "in contrast", "on the other hand",
    ]

    private func isContrastive(_ query: String) -> Bool {
        let lower = query.lowercased()
        return Self.contrastiveMarkers.contains { lower.contains($0) }
    }

    private func contrastiveParts(of query: String) -> [String] {
        let splitMarkers = ["mais ", "pourtant", "cependant", "en revanche", "however", "whereas"]
        let lower = query.lowercased()
        for marker in splitMarkers {
            if let range = lower.range(of: marker) {
                let before = String(query[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                let after  = String(query[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                if before.count > 5, after.count > 5 { return [before, after] }
            }
        }
        return [query]
    }

    // MARK: Embedding model selection

    static func bestEmbeddingModel(for text: String) -> NLEmbedding? {
        let lang = NLLanguageRecognizer.dominantLanguage(for: text) ?? .french
        return NLEmbedding.sentenceEmbedding(for: lang)
            ?? NLEmbedding.sentenceEmbedding(for: .english)
            ?? NLEmbedding.wordEmbedding(for: lang)
            ?? NLEmbedding.wordEmbedding(for: .english)
    }
}

// MARK: - IndexingEvent

/// Events emitted by `BookIndexer.stream(epub:bookID:)` during indexing.
enum IndexingEvent: Sendable {
    /// Emitted after each chapter is processed.
    case progress(chapter: Int, total: Int)
    /// Emitted once when the full index is ready.
    case completed(BookIndex)
}

// MARK: - BookIndexer

enum BookIndexer {

    // MARK: Public API

    /// Fast check (microseconds): reads only the tiny meta file (~80 bytes).
    /// Returns the passage count if a valid index exists for this book, nil otherwise.
    nonisolated static func cachedChunkCount(bookID: UUID, spineCount: Int) -> Int? {
        guard let data = try? Data(contentsOf: metaCacheURL(for: bookID)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (json["v"] as? Int) == 2,
              (json["bookID"] as? String) == bookID.uuidString,
              (json["spineCount"] as? Int) == spineCount,
              let count = json["chunkCount"] as? Int else { return nil }
        return count
    }

    /// Loads the full index from disk. Synchronous — call from a background context.
    /// Returns nil if no valid cache exists or if the spine has changed since last build.
    nonisolated static func loadFromCache(bookID: UUID, spineCount: Int) -> BookIndex? {
        try? loadCache(bookID: bookID, spineCount: spineCount)
    }

    /// Returns a stream of `IndexingEvent`. Building runs at `.utility` priority in a detached
    /// task; cancelling the stream cancels the build task.
    static func stream(epub: EPUBBook, bookID: UUID) -> AsyncThrowingStream<IndexingEvent, Error> {
        AsyncThrowingStream { continuation in
            let innerTask = Task.detached(priority: .utility) {
                do {
                    // Fast path: valid index already on disk.
                    if let cached = try? Self.loadCache(bookID: bookID, spineCount: epub.spine.count) {
                        continuation.yield(.progress(chapter: epub.spine.count, total: epub.spine.count))
                        continuation.yield(.completed(cached))
                        continuation.finish()
                        return
                    }
                    // Slow path: build from scratch.
                    let index = try await Self.buildIndex(epub: epub) { chapter, total in
                        continuation.yield(.progress(chapter: chapter, total: total))
                    }
                    try? Self.persist(index: index, bookID: bookID, spineCount: epub.spine.count)
                    continuation.yield(.completed(index))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            // Propagate cancellation from the consumer back to the build task.
            continuation.onTermination = { @Sendable _ in innerTask.cancel() }
        }
    }

    // MARK: Build

    nonisolated private static func buildIndex(
        epub: EPUBBook,
        onProgress: @Sendable (Int, Int) -> Void
    ) async throws -> BookIndex {
        let lang = NLLanguage(epub.metadata.language ?? "en")
        // Sentence embedding handles full chunks in one call (fast).
        // Word embedding requires mean-pooling (much slower) — use only as last resort.
        let model = NLEmbedding.sentenceEmbedding(for: lang)
            ?? NLEmbedding.sentenceEmbedding(for: .english)
            ?? NLEmbedding.wordEmbedding(for: lang)
            ?? NLEmbedding.wordEmbedding(for: .english)

        let titleMap = buildTitleMap(from: epub)
        var allChunks: [BookChunk] = []
        let total = epub.spine.count

        for (idx, item) in epub.spine.enumerated() {
            try Task.checkCancellation()
            await Task.yield()

            let html = (try? String(contentsOf: item.fileURL, encoding: .utf8))
                    ?? (try? String(contentsOf: item.fileURL, encoding: .isoLatin1))
                    ?? ""
            let plain = stripHTML(html)
            guard !plain.isEmpty else {
                onProgress(idx + 1, total)
                continue
            }
            let title = titleMap[item.fileURL] ?? "Chapitre \(idx + 1)"

            for text in makeChunks(plain) {
                let vec = model.flatMap { embed(text: text, model: $0) } ?? []
                allChunks.append(BookChunk(
                    text: text,
                    chapterTitle: title,
                    chapterIndex: idx,
                    embedding: vec
                ))
                if allChunks.count % 20 == 0 {
                    try Task.checkCancellation()
                    await Task.yield()
                }
            }
            onProgress(idx + 1, total)
        }
        return BookIndex(chunks: allChunks)
    }

    // MARK: Text helpers

    nonisolated private static func buildTitleMap(from epub: EPUBBook) -> [URL: String] {
        var map: [URL: String] = [:]
        func traverse(_ entries: [EPUBTOCEntry]) {
            for entry in entries {
                if let url = entry.fileURL { map[url] = entry.title }
                traverse(entry.children)
            }
        }
        traverse(epub.tableOfContents)
        return map
    }

    nonisolated private static func makeChunks(_ text: String, size: Int = 400, overlap: Int = 80) -> [String] {
        let chars = Array(text)
        var result: [String] = []
        var start = 0
        while start < chars.count {
            let end = min(start + size, chars.count)
            let s = String(chars[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { result.append(s) }
            if end == chars.count { break }
            start += size - overlap
        }
        return result
    }

    nonisolated private static func embed(text: String, model: NLEmbedding) -> [Double]? {
        if let vec = model.vector(for: text) { return vec }
        var sum = [Double](repeating: 0, count: model.dimension)
        var count = 0
        let tok = NLTokenizer(unit: .word)
        tok.string = text
        tok.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            if let vec = model.vector(for: String(text[range]).lowercased()) {
                for (i, v) in vec.enumerated() { sum[i] += v }
                count += 1
            }
            return true
        }
        return count > 0 ? sum.map { $0 / Double(count) } : nil
    }

    nonisolated private static func stripHTML(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Persistence

    /// Directory holding all index files. Internal so BookLibrary can build the deletion paths.
    nonisolated static func cacheDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AIudioBook/BookIndices")
    }

    // <uuid>.meta.json — tiny header (~80 bytes) validated on every open.
    nonisolated private static func metaCacheURL(for bookID: UUID) -> URL {
        cacheDirectory().appendingPathComponent("\(bookID.uuidString).meta.json")
    }

    // <uuid>.data.json — full chunks with binary-encoded embeddings.
    nonisolated private static func dataCacheURL(for bookID: UUID) -> URL {
        cacheDirectory().appendingPathComponent("\(bookID.uuidString).data.json")
    }

    nonisolated private static func loadCache(bookID: UUID, spineCount: Int) throws -> BookIndex? {
        // Verify identity via the tiny meta file first (avoids loading megabytes of data needlessly).
        guard let metaRaw = try? Data(contentsOf: metaCacheURL(for: bookID)),
              let meta = try? JSONSerialization.jsonObject(with: metaRaw) as? [String: Any],
              (meta["v"] as? Int) == 2,
              (meta["bookID"] as? String) == bookID.uuidString,
              (meta["spineCount"] as? Int) == spineCount else { return nil }

        // Load data file; embeddings are stored as base64 Float32 binary for fast parsing.
        let rawData = try Data(contentsOf: dataCacheURL(for: bookID))
        guard let json = try JSONSerialization.jsonObject(with: rawData) as? [String: Any],
              let chunksArray = json["chunks"] as? [[String: Any]] else { return nil }

        let chunks = chunksArray.compactMap { d -> BookChunk? in
            guard let text   = d["t"] as? String,
                  let title  = d["c"] as? String,
                  let idx    = d["i"] as? Int,
                  let embB64 = d["e"] as? String else { return nil }
            return BookChunk(
                text: text, chapterTitle: title, chapterIndex: idx,
                embedding: base64ToEmbedding(embB64)
            )
        }
        return BookIndex(chunks: chunks)
    }

    nonisolated private static func persist(index: BookIndex, bookID: UUID, spineCount: Int) throws {
        let dir = cacheDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Meta file: tiny, used for fast existence checks without touching the data file.
        let meta: [String: Any] = [
            "v": 2, "bookID": bookID.uuidString,
            "spineCount": spineCount, "chunkCount": index.chunks.count
        ]
        try JSONSerialization.data(withJSONObject: meta).write(to: metaCacheURL(for: bookID))

        // Data file: embeddings stored as base64 Float32 (~3× faster to parse than JSON double arrays).
        let chunksJSON: [[String: Any]] = index.chunks.map {
            ["t": $0.text, "c": $0.chapterTitle, "i": $0.chapterIndex,
             "e": embeddingToBase64($0.embedding)]
        }
        let data = try JSONSerialization.data(withJSONObject: ["chunks": chunksJSON])
        try data.write(to: dataCacheURL(for: bookID))
    }

    // MARK: Binary embedding codec

    nonisolated private static func embeddingToBase64(_ embedding: [Double]) -> String {
        var floats = embedding.map { Float($0) }
        return Data(bytes: &floats, count: floats.count * MemoryLayout<Float>.size)
            .base64EncodedString()
    }

    nonisolated private static func base64ToEmbedding(_ base64: String) -> [Double] {
        guard let data = Data(base64Encoded: base64) else { return [] }
        let count = data.count / MemoryLayout<Float>.size
        return data.withUnsafeBytes { ptr in
            let floats = ptr.bindMemory(to: Float.self)
            return (0..<count).map { Double(floats[$0]) }
        }
    }
}
