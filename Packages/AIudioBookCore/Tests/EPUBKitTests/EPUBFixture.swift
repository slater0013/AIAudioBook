//
//  EPUBFixture.swift
//  EPUBKitTests
//
//  Builds a small but realistic EPUB 3 file (with EPUB 2 NCX fallback) for tests.
//

import Foundation
import ZIPFoundation

enum EPUBFixture {
    /// Creates a complete .epub file in a temporary directory and returns its URL.
    static func makeEPUB(includeNavDocument: Bool = true) throws -> URL {
        let workDirectory = FileManager.default.temporaryDirectory
            .appending(path: "EPUBKitTests-\(UUID().uuidString)")
        let sourceDirectory = workDirectory.appending(path: "book")
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: sourceDirectory.appending(path: "META-INF"), withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: sourceDirectory.appending(path: "OEBPS"), withIntermediateDirectories: true)

        func write(_ content: String, to relativePath: String) throws {
            try content.data(using: .utf8)!
                .write(to: sourceDirectory.appending(path: relativePath))
        }

        try write("application/epub+zip", to: "mimetype")

        try write(
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
              <rootfiles>
                <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
              </rootfiles>
            </container>
            """, to: "META-INF/container.xml")

        let navManifestItem = includeNavDocument
            ? #"<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>"#
            : ""
        try write(
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">
              <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
                <dc:identifier id="uid">urn:uuid:test-book-0001</dc:identifier>
                <dc:title>Le Livre de Test</dc:title>
                <dc:title>Un sous-titre ignoré</dc:title>
                <dc:creator>Jeanne Dupont</dc:creator>
                <dc:creator>John Smith</dc:creator>
                <dc:language>fr</dc:language>
                <dc:description>Un roman de démonstration.</dc:description>
                <dc:publisher>Éditions Test</dc:publisher>
                <dc:date>2026-01-01</dc:date>
                <meta name="cover" content="cover-img"/>
              </metadata>
              <manifest>
                \(navManifestItem)
                <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
                <item id="cover-img" href="images/cover.jpg" media-type="image/jpeg" properties="cover-image"/>
                <item id="ch1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
                <item id="ch2" href="chapter2.xhtml" media-type="application/xhtml+xml"/>
                <item id="notes" href="notes.xhtml" media-type="application/xhtml+xml"/>
              </manifest>
              <spine toc="ncx">
                <itemref idref="ch1"/>
                <itemref idref="ch2"/>
                <itemref idref="notes" linear="no"/>
              </spine>
            </package>
            """, to: "OEBPS/content.opf")

        try write(
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
            <head><title>Sommaire</title></head>
            <body>
              <nav epub:type="toc">
                <ol>
                  <li><a href="chapter1.xhtml">Chapitre 1 — Le départ</a>
                    <ol>
                      <li><a href="chapter1.xhtml#part2">Une rencontre</a></li>
                    </ol>
                  </li>
                  <li><a href="chapter2.xhtml">Chapitre 2 — La suite</a></li>
                </ol>
              </nav>
            </body>
            </html>
            """, to: "OEBPS/nav.xhtml")

        try write(
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
              <navMap>
                <navPoint id="np1" playOrder="1">
                  <navLabel><text>Chapitre 1 — Le départ</text></navLabel>
                  <content src="chapter1.xhtml"/>
                  <navPoint id="np1b" playOrder="2">
                    <navLabel><text>Une rencontre</text></navLabel>
                    <content src="chapter1.xhtml#part2"/>
                  </navPoint>
                </navPoint>
                <navPoint id="np2" playOrder="3">
                  <navLabel><text>Chapitre 2 — La suite</text></navLabel>
                  <content src="chapter2.xhtml"/>
                </navPoint>
              </navMap>
            </ncx>
            """, to: "OEBPS/toc.ncx")

        for (name, title) in [("chapter1", "Le départ"), ("chapter2", "La suite"), ("notes", "Notes")] {
            try write(
                """
                <?xml version="1.0" encoding="UTF-8"?>
                <html xmlns="http://www.w3.org/1999/xhtml">
                <head><title>\(title)</title></head>
                <body><h1 id="part2">\(title)</h1><p>Texte du chapitre.</p></body>
                </html>
                """, to: "OEBPS/\(name).xhtml")
        }

        try fileManager.createDirectory(
            at: sourceDirectory.appending(path: "OEBPS/images"), withIntermediateDirectories: true)
        try Data([0xFF, 0xD8, 0xFF, 0xE0]) // minimal JPEG signature
            .write(to: sourceDirectory.appending(path: "OEBPS/images/cover.jpg"))

        let epubURL = workDirectory.appending(path: "fixture.epub")
        try fileManager.zipItem(at: sourceDirectory, to: epubURL, shouldKeepParent: false)
        return epubURL
    }
}
