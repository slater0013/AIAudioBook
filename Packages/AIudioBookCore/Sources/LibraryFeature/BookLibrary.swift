//
//  BookLibrary.swift
//  LibraryFeature
//
//  On-disk storage for imported books:
//  Application Support/Books/<folder>/original.epub + content/ (extracted).
//

import EPUBKit
import Foundation

/// Result of a successful EPUB import, used to create the `Book` record.
public struct ImportedBook: Sendable {
    public let metadata: EPUBMetadata
    public let folderName: String
    public let coverRelativePath: String?
}

/// Manages the books' backing folders and the import pipeline.
public enum BookLibrary {
    /// Root directory holding one folder per imported book.
    public nonisolated static func booksDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appending(path: "Books", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    public nonisolated static func bookFolderURL(for book: Book) throws -> URL {
        try booksDirectory().appending(path: book.folderName, directoryHint: .isDirectory)
    }

    /// Extracted EPUB contents of a book (parseable with `EPUBParser.parse(extractedAt:)`).
    public nonisolated static func contentDirectoryURL(for book: Book) throws -> URL {
        try bookFolderURL(for: book).appending(path: "content", directoryHint: .isDirectory)
    }

    public nonisolated static func coverURL(for book: Book) -> URL? {
        guard let coverRelativePath = book.coverRelativePath,
              let folder = try? bookFolderURL(for: book) else { return nil }
        return folder.appending(path: coverRelativePath)
    }

    /// Imports an .epub: copies it into the library, extracts and parses it.
    /// Heavy file work — call from a background task, then create the `Book`
    /// record from the returned value on the main actor.
    public nonisolated static func importEPUB(at sourceURL: URL) throws -> ImportedBook {
        // The URL comes from a user file picker; access is security-scoped (sandbox).
        let hasScopedAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if hasScopedAccess { sourceURL.stopAccessingSecurityScopedResource() }
        }

        let fileManager = FileManager.default
        let folderName = UUID().uuidString
        let bookFolder = try booksDirectory().appending(path: folderName, directoryHint: .isDirectory)
        do {
            try fileManager.createDirectory(at: bookFolder, withIntermediateDirectories: true)
            try fileManager.copyItem(at: sourceURL, to: bookFolder.appending(path: "original.epub"))

            let contentDirectory = bookFolder.appending(path: "content", directoryHint: .isDirectory)
            let book = try EPUBParser.extractAndParse(
                epubAt: bookFolder.appending(path: "original.epub"),
                to: contentDirectory
            )

            // Store the cover path relative to the book folder ("content/...").
            var coverRelativePath: String?
            if let coverURL = book.coverImageURL {
                let folderPath = bookFolder.standardizedFileURL.path
                let coverPath = coverURL.standardizedFileURL.path
                if coverPath.hasPrefix(folderPath + "/") {
                    coverRelativePath = String(coverPath.dropFirst(folderPath.count + 1))
                }
            }

            return ImportedBook(
                metadata: book.metadata,
                folderName: folderName,
                coverRelativePath: coverRelativePath
            )
        } catch {
            // Leave no orphaned folder behind on failure.
            try? fileManager.removeItem(at: bookFolder)
            throw error
        }
    }

    /// Deletes the book's backing folder and its RAG index files (call before removing the record).
    public nonisolated static func deleteFolder(of book: Book) {
        if let folder = try? bookFolderURL(for: book) {
            try? FileManager.default.removeItem(at: folder)
        }
        let fm = FileManager.default
        guard let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let indexDir = support.appendingPathComponent("AIudioBook/BookIndices")
        let uuid = book.bookID.uuidString
        // Current format (v2): two files per book.
        try? fm.removeItem(at: indexDir.appendingPathComponent("\(uuid).meta.json"))
        try? fm.removeItem(at: indexDir.appendingPathComponent("\(uuid).data.json"))
        // Legacy format (v1): single file — clean up if it still exists.
        try? fm.removeItem(at: indexDir.appendingPathComponent("\(uuid).json"))
    }
}
