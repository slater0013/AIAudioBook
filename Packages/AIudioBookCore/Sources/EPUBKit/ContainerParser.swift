//
//  ContainerParser.swift
//  EPUBKit
//
//  Parses META-INF/container.xml to locate the OPF package document.
//

import Foundation

final class ContainerParser: NSObject, XMLParserDelegate {
    private var packageDocumentPath: String?

    /// Returns the path of the OPF package document, relative to the EPUB root.
    static func packageDocumentPath(in containerXML: Data) throws -> String {
        let delegate = ContainerParser()
        let parser = XMLParser(data: containerXML)
        parser.shouldProcessNamespaces = true
        parser.delegate = delegate
        parser.parse()
        guard let path = delegate.packageDocumentPath else {
            throw EPUBError.malformedDocument(name: "container.xml")
        }
        return path
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        // The first <rootfile> pointing to an OEBPS package is the main rendition.
        guard packageDocumentPath == nil, elementName == "rootfile" else { return }
        let mediaType = attributeDict["media-type"]
        if mediaType == nil || mediaType == "application/oebps-package+xml" {
            packageDocumentPath = attributeDict["full-path"]
        }
    }
}
