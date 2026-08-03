//
//  NavigationParser.swift
//  EPUBKit
//
//  Parses the table of contents: EPUB 3 navigation document (nav.xhtml)
//  with a fallback to the EPUB 2 NCX document.
//

import Foundation

/// Mutable tree node used while parsing; converted to immutable `EPUBTOCEntry` at the end.
private final class TOCNode {
    var title = ""
    var href: String?
    var children: [TOCNode] = []
}

private func makeEntries(_ nodes: [TOCNode], resolver: (String) -> (URL?, String?)) -> [EPUBTOCEntry] {
    nodes.compactMap { node in
        let title = node.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let children = makeEntries(node.children, resolver: resolver)
        guard !title.isEmpty || !children.isEmpty else { return nil }
        let (fileURL, fragment) = node.href.map(resolver) ?? (nil, nil)
        return EPUBTOCEntry(title: title, href: node.href, fileURL: fileURL, fragment: fragment, children: children)
    }
}

// MARK: - EPUB 3 navigation document (XHTML)

/// Extracts the `<nav epub:type="toc">` list from an EPUB 3 navigation document.
final class NavDocumentParser: NSObject, XMLParserDelegate {
    private var insideTOCNav = false
    private var navDepth = 0
    private var stack: [TOCNode] = []
    private var roots: [TOCNode] = []
    private var capturingText = false

    /// `resolver` maps an href (relative to the OPF directory) to a resolved file URL + fragment.
    static func parse(_ data: Data, resolver: (String) -> (URL?, String?)) -> [EPUBTOCEntry] {
        let delegate = NavDocumentParser()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = delegate
        parser.parse()
        return makeEntries(delegate.roots, resolver: resolver)
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        switch elementName {
        case "nav":
            if insideTOCNav {
                navDepth += 1
            } else {
                // The TOC nav is marked epub:type="toc" (or role="doc-toc").
                let type = attributeDict["epub:type"] ?? attributeDict["type"] ?? ""
                let role = attributeDict["role"] ?? ""
                if type.split(separator: " ").contains("toc") || role == "doc-toc" {
                    insideTOCNav = true
                    navDepth = 1
                }
            }
        case "li" where insideTOCNav:
            let node = TOCNode()
            if let parent = stack.last {
                parent.children.append(node)
            } else {
                roots.append(node)
            }
            stack.append(node)
        case "a", "span":
            guard insideTOCNav, let current = stack.last, current.title.isEmpty else { return }
            if elementName == "a" {
                current.href = attributeDict["href"]
            }
            capturingText = true
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if capturingText, let current = stack.last {
            current.title += string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch elementName {
        case "nav" where insideTOCNav:
            navDepth -= 1
            if navDepth == 0 { insideTOCNav = false }
        case "li" where insideTOCNav:
            if !stack.isEmpty { stack.removeLast() }
        case "a", "span":
            capturingText = false
        default:
            break
        }
    }
}

// MARK: - EPUB 2 NCX document

/// Extracts the `<navMap>` hierarchy from an EPUB 2 NCX document.
final class NCXParser: NSObject, XMLParserDelegate {
    private var stack: [TOCNode] = []
    private var roots: [TOCNode] = []
    private var capturingText = false

    static func parse(_ data: Data, resolver: (String) -> (URL?, String?)) -> [EPUBTOCEntry] {
        let delegate = NCXParser()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = delegate
        parser.parse()
        return makeEntries(delegate.roots, resolver: resolver)
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        switch elementName {
        case "navPoint":
            let node = TOCNode()
            if let parent = stack.last {
                parent.children.append(node)
            } else {
                roots.append(node)
            }
            stack.append(node)
        case "text":
            capturingText = stack.last?.title.isEmpty ?? false
        case "content":
            stack.last?.href = attributeDict["src"]
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if capturingText, let current = stack.last {
            current.title += string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch elementName {
        case "navPoint":
            if !stack.isEmpty { stack.removeLast() }
        case "text":
            capturingText = false
        default:
            break
        }
    }
}
