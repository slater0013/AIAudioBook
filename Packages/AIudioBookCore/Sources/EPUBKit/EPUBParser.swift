//
//  EPUBParser.swift
//  EPUBKit
//
//  Public entry point: extracts an .epub archive and assembles an `EPUBBook`.
//

import Foundation

public enum EPUBParser {
    /// Extracts the .epub archive into `destinationDirectory` and parses it.
    ///
    /// The destination directory becomes the book's permanent backing store
    /// (chapters are later rendered straight from these files).
    public static func extractAndParse(epubAt epubURL: URL, to destinationDirectory: URL) throws -> EPUBBook {
        try EPUBArchive.extract(epubAt: epubURL, to: destinationDirectory)
        return try parse(extractedAt: destinationDirectory)
    }

    /// Parses an already-extracted EPUB directory (e.g. when reopening a library book).
    public static func parse(extractedAt rootDirectory: URL) throws -> EPUBBook {
        // Normalize to a directory URL (trailing slash) so relative href resolution
        // appends to the path instead of replacing its last component.
        let rootDirectory = URL(filePath: rootDirectory.path, directoryHint: .isDirectory)

        // 1. META-INF/container.xml tells us where the package document (OPF) lives.
        let containerURL = rootDirectory.appending(path: "META-INF/container.xml")
        guard let containerData = try? Data(contentsOf: containerURL) else {
            throw EPUBError.missingContainerDocument
        }
        let opfPath = try ContainerParser.packageDocumentPath(in: containerData)

        // 2. Parse the OPF: metadata, manifest, spine.
        guard
            let opfURL = resolve(href: opfPath, against: rootDirectory),
            let opfData = try? Data(contentsOf: opfURL)
        else {
            throw EPUBError.missingPackageDocument(path: opfPath)
        }
        let opf = try OPFParser.parse(opfData)
        let contentDirectory = opfURL.deletingLastPathComponent()

        // 3. Resolve manifest hrefs to absolute file URLs.
        var manifest: [String: EPUBManifestItem] = [:]
        for entry in opf.manifest {
            guard let fileURL = resolve(href: entry.href, against: contentDirectory) else { continue }
            manifest[entry.id] = EPUBManifestItem(
                id: entry.id,
                href: entry.href,
                mediaType: entry.mediaType,
                properties: entry.properties,
                fileURL: fileURL
            )
        }

        // 4. Build the reading order from the spine.
        let spine: [EPUBSpineItem] = opf.spine.compactMap { entry in
            guard let item = manifest[entry.idref] else { return nil }
            return EPUBSpineItem(
                idref: entry.idref,
                href: item.href,
                mediaType: item.mediaType,
                fileURL: item.fileURL,
                isLinear: entry.isLinear
            )
        }

        // 5. Table of contents: prefer the EPUB 3 nav document, fall back to the EPUB 2 NCX.
        let resolver: (String) -> (URL?, String?) = { href in
            let parts = href.split(separator: "#", maxSplits: 1)
            let path = parts.first.map(String.init) ?? href
            let fragment = parts.count > 1 ? String(parts[1]) : nil
            return (resolve(href: path, against: contentDirectory), fragment)
        }
        var toc: [EPUBTOCEntry] = []
        if let navItem = manifest.values.first(where: { $0.properties.contains("nav") }),
           let navData = try? Data(contentsOf: navItem.fileURL) {
            toc = NavDocumentParser.parse(navData, resolver: resolver)
        }
        if toc.isEmpty {
            let ncxItem = opf.ncxItemID.flatMap { manifest[$0] }
                ?? manifest.values.first(where: { $0.mediaType == "application/x-dtbncx+xml" })
            if let ncxItem, let ncxData = try? Data(contentsOf: ncxItem.fileURL) {
                toc = NCXParser.parse(ncxData, resolver: resolver)
            }
        }

        // 6. Cover image: EPUB 3 "cover-image" property, or EPUB 2 <meta name="cover"> reference.
        let coverItem = manifest.values.first(where: { $0.properties.contains("cover-image") })
            ?? opf.coverItemID.flatMap { manifest[$0] }

        return EPUBBook(
            rootDirectory: rootDirectory,
            contentDirectory: contentDirectory,
            metadata: EPUBMetadata(
                title: opf.title ?? rootDirectory.lastPathComponent,
                authors: opf.authors,
                language: opf.language,
                identifier: opf.identifier,
                synopsis: opf.synopsis,
                publisher: opf.publisher,
                publicationDate: opf.publicationDate
            ),
            manifest: manifest,
            spine: spine,
            tableOfContents: toc,
            coverImageURL: coverItem?.fileURL
        )
    }

    /// Resolves an OPF-relative href (possibly percent-encoded) to a file URL.
    private static func resolve(href: String, against directory: URL) -> URL? {
        if let url = URL(string: href, relativeTo: directory) {
            return url.absoluteURL.standardizedFileURL
        }
        // Some real-world EPUBs use raw spaces or other invalid URI characters.
        guard let encoded = href.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: encoded, relativeTo: directory) else {
            return nil
        }
        return url.absoluteURL.standardizedFileURL
    }
}
