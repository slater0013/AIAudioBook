//
//  EPUBError.swift
//  EPUBKit
//

import Foundation

/// Errors thrown while opening or parsing an EPUB file.
public enum EPUBError: Error, LocalizedError {
    case fileNotFound(URL)
    case invalidArchive(underlying: Error)
    case missingContainerDocument
    case missingPackageDocument(path: String)
    case malformedDocument(name: String)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            return "The EPUB file could not be found at \(url.path)."
        case .invalidArchive(let underlying):
            return "The file is not a readable EPUB (ZIP) archive: \(underlying.localizedDescription)"
        case .missingContainerDocument:
            return "The EPUB is missing its META-INF/container.xml document."
        case .missingPackageDocument(let path):
            return "The EPUB package document could not be read at \(path)."
        case .malformedDocument(let name):
            return "The EPUB document '\(name)' is malformed and could not be parsed."
        }
    }
}
