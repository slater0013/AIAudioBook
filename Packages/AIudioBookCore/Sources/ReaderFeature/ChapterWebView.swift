//
//  ChapterWebView.swift
//  ReaderFeature
//
//  Renders one EPUB chapter in a WKWebView, working around macOS App Sandbox
//  restrictions on WKWebView sub-processes.
//
//  Strategy:
//    • The chapter HTML is read directly by the app process (has full
//      container access) and served via loadHTMLString — no URL scheme needed
//      for the main document.
//    • CSS, images, fonts referenced in the HTML resolve against a custom
//      "epub" base URL. EPUBSchemeHandler intercepts those sub-resource
//      requests in the app process and serves the files from disk.
//
//  This approach guarantees text is always visible, and CSS/images load when
//  the scheme handler path resolves correctly.
//

import SwiftUI
import WebKit

// MARK: - Custom URL scheme handler (sub-resources only)

final class EPUBSchemeHandler: NSObject, WKURLSchemeHandler, @unchecked Sendable {
    private let rootDirectory: URL

    init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let requestURL = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }
        let fileURL = self.fileURL(for: requestURL)
        do {
            let data = try Data(contentsOf: fileURL)
            let response = URLResponse(
                url: requestURL,
                mimeType: Self.mimeType(for: fileURL),
                expectedContentLength: data.count,
                textEncodingName: "utf-8"
            )
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch {
            urlSchemeTask.didFailWithError(error)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}

    /// Maps  epub://book/OEBPS/style.css  →  rootDirectory/OEBPS/style.css
    private func fileURL(for epubURL: URL) -> URL {
        let path = epubURL.path.hasPrefix("/") ? String(epubURL.path.dropFirst()) : epubURL.path
        return rootDirectory.appending(path: path)
    }

    private static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "xhtml", "html", "htm": return "text/html"
        case "css":                   return "text/css"
        case "js":                    return "application/javascript"
        case "jpg", "jpeg":           return "image/jpeg"
        case "png":                   return "image/png"
        case "gif":                   return "image/gif"
        case "svg":                   return "image/svg+xml"
        case "ttf":                   return "font/ttf"
        case "otf":                   return "font/otf"
        case "woff":                  return "font/woff"
        case "woff2":                 return "font/woff2"
        default:                      return "application/octet-stream"
        }
    }
}

// MARK: - Coordinator

extension ChapterWebView {
    /// Persists across re-renders; tracks the chapter file URL we last loaded
    /// to avoid restarting an in-flight navigation on every SwiftUI update.
    final class Coordinator: NSObject {
        var loadedFileURL: URL?
    }
}

// MARK: - SwiftUI wrapper

#if canImport(AppKit)
struct ChapterWebView: NSViewRepresentable {
    let fileURL: URL?
    let readAccessURL: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        makeWebView()
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        load(in: webView, coordinator: context.coordinator)
    }
}
#else
struct ChapterWebView: UIViewRepresentable {
    let fileURL: URL?
    let readAccessURL: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        makeWebView()
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        load(in: webView, coordinator: context.coordinator)
    }
}
#endif

extension ChapterWebView {
    fileprivate func makeWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(
            EPUBSchemeHandler(rootDirectory: readAccessURL),
            forURLScheme: "epub"
        )
        return WKWebView(frame: .zero, configuration: configuration)
    }

    fileprivate func load(in webView: WKWebView, coordinator: Coordinator) {
        guard let fileURL else { return }
        let canonical = fileURL.standardizedFileURL
        guard coordinator.loadedFileURL != canonical else { return }
        coordinator.loadedFileURL = canonical

        // Read the HTML in the app process — bypasses WebContent sandbox entirely.
        // Try UTF-8 first (covers ~99 % of modern EPUBs), fall back to latin-1.
        let html: String
        if let s = try? String(contentsOf: fileURL, encoding: .utf8) {
            html = s
        } else if let s = try? String(contentsOf: fileURL, encoding: .isoLatin1) {
            html = s
        } else {
            return
        }

        // Base URL in our custom scheme so relative sub-resources (CSS, images,
        // fonts) are resolved and served by EPUBSchemeHandler in the app process.
        // If the path-conversion fails we still load the text (nil base URL is fine).
        let baseURL = epubBaseURL(for: fileURL.deletingLastPathComponent())
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    /// Converts the chapter's *directory* to an epub:// URL used as a base URL.
    /// e.g.  rootDirectory/OEBPS/  →  epub://book/OEBPS/
    private func epubBaseURL(for directory: URL) -> URL? {
        var rootPath = readAccessURL.standardizedFileURL.path
        if !rootPath.hasSuffix("/") { rootPath += "/" }
        var dirPath = directory.standardizedFileURL.path
        if !dirPath.hasSuffix("/") { dirPath += "/" }
        guard dirPath.hasPrefix(rootPath) else { return nil }
        let relative = String(dirPath.dropFirst(rootPath.count))
        guard let encoded = relative.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }
        return URL(string: "epub://book/\(encoded)")
    }
}
