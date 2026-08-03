//
//  EPUBModels.swift
//  EPUBKit
//
//  Value types describing the parsed contents of an EPUB publication.
//

import Foundation

/// Dublin Core metadata extracted from the EPUB package document (OPF).
public struct EPUBMetadata: Sendable, Equatable {
    public var title: String
    public var authors: [String]
    public var language: String?
    public var identifier: String?
    public var synopsis: String?
    public var publisher: String?
    public var publicationDate: String?

    public init(
        title: String,
        authors: [String] = [],
        language: String? = nil,
        identifier: String? = nil,
        synopsis: String? = nil,
        publisher: String? = nil,
        publicationDate: String? = nil
    ) {
        self.title = title
        self.authors = authors
        self.language = language
        self.identifier = identifier
        self.synopsis = synopsis
        self.publisher = publisher
        self.publicationDate = publicationDate
    }
}

/// One resource declared in the OPF `<manifest>` (a chapter, image, stylesheet...).
public struct EPUBManifestItem: Sendable, Equatable {
    public let id: String
    /// Path relative to the OPF directory, as written in the package document.
    public let href: String
    public let mediaType: String
    /// EPUB 3 `properties` tokens (e.g. "nav", "cover-image").
    public let properties: Set<String>
    /// Absolute location of the resource inside the extracted EPUB directory.
    public let fileURL: URL
}

/// One entry of the OPF `<spine>`: the linear reading order of the book.
public struct EPUBSpineItem: Sendable, Equatable {
    public let idref: String
    public let href: String
    public let mediaType: String
    /// Absolute location of the chapter document inside the extracted EPUB directory.
    public let fileURL: URL
    /// `false` when the publisher marked the item as auxiliary (linear="no").
    public let isLinear: Bool
}

/// One entry of the table of contents (EPUB 3 nav document, or EPUB 2 NCX).
public struct EPUBTOCEntry: Sendable, Hashable {
    public let title: String
    /// Href relative to the OPF directory; may include a #fragment. Nil for section headings without a link.
    public let href: String?
    /// Resolved chapter file (fragment stripped), when the href points to an existing resource.
    public let fileURL: URL?
    /// Fragment identifier (anchor inside the chapter), if any.
    public let fragment: String?
    public let children: [EPUBTOCEntry]

    public init(title: String, href: String?, fileURL: URL?, fragment: String?, children: [EPUBTOCEntry] = []) {
        self.title = title
        self.href = href
        self.fileURL = fileURL
        self.fragment = fragment
        self.children = children
    }
}

/// A fully parsed EPUB publication, backed by its extracted directory on disk.
public struct EPUBBook: Sendable {
    /// Root of the extracted EPUB archive.
    public let rootDirectory: URL
    /// Directory containing the OPF package document; hrefs are relative to it.
    public let contentDirectory: URL
    public let metadata: EPUBMetadata
    /// All declared resources, keyed by manifest id.
    public let manifest: [String: EPUBManifestItem]
    /// Linear reading order.
    public let spine: [EPUBSpineItem]
    public let tableOfContents: [EPUBTOCEntry]
    /// Cover image file, when the publication declares one.
    public let coverImageURL: URL?
}
