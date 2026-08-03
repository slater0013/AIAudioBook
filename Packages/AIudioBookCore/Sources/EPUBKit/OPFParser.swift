//
//  OPFParser.swift
//  EPUBKit
//
//  Parses the OPF package document: Dublin Core metadata, manifest and spine.
//

import Foundation

/// Raw parsing result, before hrefs are resolved against the OPF directory.
struct OPFDocument {
    struct ManifestEntry {
        let id: String
        let href: String
        let mediaType: String
        let properties: Set<String>
    }

    struct SpineEntry {
        let idref: String
        let isLinear: Bool
    }

    var title: String?
    var authors: [String] = []
    var language: String?
    var identifier: String?
    var synopsis: String?
    var publisher: String?
    var publicationDate: String?
    /// Manifest id referenced by `<meta name="cover" content="...">` (EPUB 2 convention).
    var coverItemID: String?
    /// Manifest id referenced by the spine's `toc` attribute (EPUB 2 NCX).
    var ncxItemID: String?
    var manifest: [ManifestEntry] = []
    var spine: [SpineEntry] = []
}

final class OPFParser: NSObject, XMLParserDelegate {
    private static let dublinCoreNamespace = "http://purl.org/dc/elements/1.1/"
    /// Dublin Core elements whose text content we capture.
    private static let capturedElements: Set<String> = [
        "title", "creator", "language", "identifier", "description", "publisher", "date",
    ]

    private var document = OPFDocument()
    private var capturedElement: String?
    private var capturedText = ""

    static func parse(_ opfData: Data) throws -> OPFDocument {
        let delegate = OPFParser()
        let parser = XMLParser(data: opfData)
        parser.shouldProcessNamespaces = true
        parser.delegate = delegate
        guard parser.parse() else {
            throw EPUBError.malformedDocument(name: "package document (OPF)")
        }
        return delegate.document
    }

    // MARK: - XMLParserDelegate

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        if namespaceURI == Self.dublinCoreNamespace, Self.capturedElements.contains(elementName) {
            capturedElement = elementName
            capturedText = ""
            return
        }

        switch elementName {
        case "meta":
            // EPUB 2 cover convention: <meta name="cover" content="manifest-id"/>
            if attributeDict["name"] == "cover", let content = attributeDict["content"] {
                document.coverItemID = content
            }
        case "item":
            guard
                let id = attributeDict["id"],
                let href = attributeDict["href"],
                let mediaType = attributeDict["media-type"]
            else { return }
            let properties = Set((attributeDict["properties"] ?? "").split(separator: " ").map(String.init))
            document.manifest.append(.init(id: id, href: href, mediaType: mediaType, properties: properties))
        case "spine":
            document.ncxItemID = attributeDict["toc"]
        case "itemref":
            guard let idref = attributeDict["idref"] else { return }
            document.spine.append(.init(idref: idref, isLinear: attributeDict["linear"] != "no"))
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if capturedElement != nil {
            capturedText += string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard let element = capturedElement, element == elementName else { return }
        let text = capturedText.trimmingCharacters(in: .whitespacesAndNewlines)
        capturedElement = nil
        guard !text.isEmpty else { return }

        switch element {
        case "title":
            // Keep the first title only (subsequent ones are usually subtitles).
            if document.title == nil { document.title = text }
        case "creator":
            document.authors.append(text)
        case "language":
            if document.language == nil { document.language = text }
        case "identifier":
            if document.identifier == nil { document.identifier = text }
        case "description":
            if document.synopsis == nil { document.synopsis = text }
        case "publisher":
            if document.publisher == nil { document.publisher = text }
        case "date":
            if document.publicationDate == nil { document.publicationDate = text }
        default:
            break
        }
    }
}
