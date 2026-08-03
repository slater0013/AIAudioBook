//
//  EPUBArchive.swift
//  EPUBKit
//
//  Extraction of the EPUB (ZIP) archive to a directory on disk.
//

import Foundation
import ZIPFoundation

enum EPUBArchive {
    /// Extracts the EPUB archive into `destinationDirectory`, replacing any previous contents.
    static func extract(epubAt sourceURL: URL, to destinationDirectory: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw EPUBError.fileNotFound(sourceURL)
        }
        if fileManager.fileExists(atPath: destinationDirectory.path) {
            try fileManager.removeItem(at: destinationDirectory)
        }
        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        do {
            try fileManager.unzipItem(at: sourceURL, to: destinationDirectory)
        } catch {
            throw EPUBError.invalidArchive(underlying: error)
        }
    }
}
