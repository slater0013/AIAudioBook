//
//  Bookmark.swift
//  LibraryFeature
//
//  Position bookmark for a book: stores chapter index + fractional scroll progress.
//

import Foundation
import Observation

// MARK: - Bookmark

public struct Bookmark: Identifiable, Codable, Sendable {
    public let id: UUID
    public let bookID: UUID
    public let spineIndex: Int
    /// Fractional scroll position within the chapter (0–1).
    public let chapterProgress: Double
    /// Human-readable label (chapter title + percentage), set at creation time.
    public let label: String
    public let createdAt: Date

    public init(bookID: UUID, spineIndex: Int, chapterProgress: Double, label: String) {
        id             = UUID()
        self.bookID    = bookID
        self.spineIndex = spineIndex
        self.chapterProgress = chapterProgress
        self.label     = label
        createdAt      = Date()
    }
}

// MARK: - BookmarkStore

@Observable
public final class BookmarkStore {
    public private(set) var bookmarks: [Bookmark] = []

    public init() { load() }

    // MARK: Public API

    public func add(_ bookmark: Bookmark) {
        guard !isDuplicate(bookmark) else { return }
        bookmarks.append(bookmark)
        save()
    }

    public func remove(id: UUID) {
        bookmarks.removeAll { $0.id == id }
        save()
    }

    public func bookmarks(for bookID: UUID) -> [Bookmark] {
        bookmarks
            .filter { $0.bookID == bookID }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// Returns true if a bookmark already exists at this position (within 2% tolerance).
    public func hasBookmark(bookID: UUID, spineIndex: Int, progress: Double) -> Bool {
        bookmarks.contains {
            $0.bookID    == bookID &&
            $0.spineIndex == spineIndex &&
            abs($0.chapterProgress - progress) < 0.02
        }
    }

    /// Returns the existing bookmark at this position, if any.
    public func bookmark(bookID: UUID, spineIndex: Int, progress: Double) -> Bookmark? {
        bookmarks.first {
            $0.bookID    == bookID &&
            $0.spineIndex == spineIndex &&
            abs($0.chapterProgress - progress) < 0.02
        }
    }

    // MARK: Private helpers

    private func isDuplicate(_ b: Bookmark) -> Bool {
        hasBookmark(bookID: b.bookID, spineIndex: b.spineIndex, progress: b.chapterProgress)
    }

    // MARK: Persistence

    private static var storeURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("AIudioBook/bookmarks.json")
    }

    private func save() {
        guard let url = Self.storeURL else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? JSONEncoder().encode(bookmarks).write(to: url)
    }

    private func load() {
        guard let url = Self.storeURL,
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([Bookmark].self, from: data)
        else { return }
        bookmarks = decoded
    }
}
