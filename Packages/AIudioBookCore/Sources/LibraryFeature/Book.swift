//
//  Book.swift
//  LibraryFeature
//
//  SwiftData model for a book in the user's library.
//

import Foundation
import SwiftData

/// A book in the user's library, backed by an on-disk folder containing
/// the original .epub file and its extracted contents.
///
/// CloudKit-ready by design: no unique constraints, and every stored
/// property either has a default value or is optional.
@Model
public final class Book {
    public var bookID: UUID = UUID()
    public var title: String = ""
    public var authors: [String] = []
    public var language: String?
    public var synopsis: String?
    public var publisher: String?
    /// Name of this book's folder inside the library's Books directory.
    /// Only the folder *name* is stored so the record survives container moves.
    public var folderName: String = ""
    /// Path of the cover image, relative to the book's folder.
    public var coverRelativePath: String?
    public var importedAt: Date = Date.now
    public var lastOpenedAt: Date?

    /// Resume position: index of the chapter in the spine, and progress within it (0...1).
    public var lastSpineIndex: Int = 0
    public var lastChapterProgress: Double = 0

    public init(
        title: String,
        authors: [String] = [],
        language: String? = nil,
        synopsis: String? = nil,
        publisher: String? = nil,
        folderName: String,
        coverRelativePath: String? = nil
    ) {
        self.title = title
        self.authors = authors
        self.language = language
        self.synopsis = synopsis
        self.publisher = publisher
        self.folderName = folderName
        self.coverRelativePath = coverRelativePath
    }

    /// "Jeanne Dupont, John Smith" — for display under the cover.
    public var authorsLabel: String {
        authors.joined(separator: ", ")
    }
}
