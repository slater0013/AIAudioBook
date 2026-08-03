//
//  EPUBParserTests.swift
//  EPUBKitTests
//

import Foundation
import Testing
@testable import EPUBKit

@Suite("EPUBParser")
struct EPUBParserTests {
    /// Extracts the fixture EPUB to a fresh temporary directory and parses it.
    private func parseFixture(includeNavDocument: Bool = true) throws -> EPUBBook {
        let epubURL = try EPUBFixture.makeEPUB(includeNavDocument: includeNavDocument)
        let destination = FileManager.default.temporaryDirectory
            .appending(path: "EPUBKitTests-extracted-\(UUID().uuidString)")
        return try EPUBParser.extractAndParse(epubAt: epubURL, to: destination)
    }

    @Test("Metadata is extracted from the OPF")
    func metadata() throws {
        let book = try parseFixture()
        #expect(book.metadata.title == "Le Livre de Test")
        #expect(book.metadata.authors == ["Jeanne Dupont", "John Smith"])
        #expect(book.metadata.language == "fr")
        #expect(book.metadata.identifier == "urn:uuid:test-book-0001")
        #expect(book.metadata.synopsis == "Un roman de démonstration.")
        #expect(book.metadata.publisher == "Éditions Test")
        #expect(book.metadata.publicationDate == "2026-01-01")
    }

    @Test("Spine preserves reading order and linearity, and files exist on disk")
    func spine() throws {
        let book = try parseFixture()
        #expect(book.spine.map(\.idref) == ["ch1", "ch2", "notes"])
        #expect(book.spine.map(\.isLinear) == [true, true, false])
        for item in book.spine {
            #expect(FileManager.default.fileExists(atPath: item.fileURL.path),
                    "Missing chapter file: \(item.href)")
        }
    }

    @Test("Table of contents comes from the EPUB 3 nav document, with nesting")
    func tableOfContentsNav() throws {
        let book = try parseFixture()
        #expect(book.tableOfContents.count == 2)
        let first = try #require(book.tableOfContents.first)
        #expect(first.title == "Chapitre 1 — Le départ")
        #expect(first.children.count == 1)
        #expect(first.children.first?.title == "Une rencontre")
        #expect(first.children.first?.fragment == "part2")
        #expect(book.tableOfContents.last?.title == "Chapitre 2 — La suite")
    }

    @Test("Table of contents falls back to the EPUB 2 NCX when there is no nav document")
    func tableOfContentsNCXFallback() throws {
        let book = try parseFixture(includeNavDocument: false)
        #expect(book.tableOfContents.count == 2)
        let first = try #require(book.tableOfContents.first)
        #expect(first.title == "Chapitre 1 — Le départ")
        #expect(first.children.first?.fragment == "part2")
    }

    @Test("Cover image is located via the cover-image property")
    func coverImage() throws {
        let book = try parseFixture()
        let coverURL = try #require(book.coverImageURL)
        #expect(coverURL.lastPathComponent == "cover.jpg")
        #expect(FileManager.default.fileExists(atPath: coverURL.path))
    }

    @Test("A non-EPUB file is rejected with a clear error")
    func invalidArchive() throws {
        let bogusURL = FileManager.default.temporaryDirectory
            .appending(path: "bogus-\(UUID().uuidString).epub")
        try Data("this is not a zip".utf8).write(to: bogusURL)
        let destination = FileManager.default.temporaryDirectory
            .appending(path: "bogus-out-\(UUID().uuidString)")
        #expect(throws: EPUBError.self) {
            _ = try EPUBParser.extractAndParse(epubAt: bogusURL, to: destination)
        }
    }

    @Test("A missing file is rejected with a clear error")
    func missingFile() throws {
        let missingURL = FileManager.default.temporaryDirectory
            .appending(path: "missing-\(UUID().uuidString).epub")
        let destination = FileManager.default.temporaryDirectory
            .appending(path: "missing-out-\(UUID().uuidString)")
        #expect(throws: EPUBError.self) {
            _ = try EPUBParser.extractAndParse(epubAt: missingURL, to: destination)
        }
    }
}
