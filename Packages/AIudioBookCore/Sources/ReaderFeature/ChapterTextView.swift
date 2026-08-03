//
//  ChapterTextView.swift
//  ReaderFeature
//
//  Renders one EPUB chapter using NSTextView + NSAttributedString(html:).
//  Runs entirely in the app process — no WKWebView sub-process, no sandbox issues.
//

import AppKit
import SwiftUI

struct ChapterTextView: NSViewRepresentable {
    let fileURL: URL
    let fontSize: Double
    let theme: ReaderTheme
    let readingMode: ReadingMode
    /// In page mode: the desired page to display (0-indexed). Ignored in scroll mode.
    let currentPage: Int
    /// Fractional scroll position (0–1) to restore when this chapter loads. Ignored in page mode.
    let savedProgress: Double
    /// Called when the user finishes a live scroll gesture, with the new fraction.
    let onProgressChange: (Double) -> Void
    /// Range to highlight in the text storage for karaoke (TTS word tracking).
    var highlightRange: NSRange?
    /// Called once after the chapter text is loaded into the text storage.
    var onTextReady: ((String) -> Void)?
    /// Called when the user moves the insertion point (click). Int = UTF-16 offset.
    var onSelectionChange: ((Int) -> Void)?
    /// Called once after the chapter loads with the set of heading texts extracted from HTML.
    var onHeadingsReady: ((Set<String>) -> Void)? = nil
    /// Called (in page mode) with the total page count once layout is complete.
    var onTotalPagesChanged: ((Int) -> Void)? = nil
    /// Optional fractional scroll position (0–1) to apply as an imperative command.
    /// Used for bookmark navigation within the same chapter (cross-chapter navigation uses savedProgress).
    var scrollTarget: Double? = nil

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.scrollsDynamically = true   // required for live-scroll notifications

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.drawsBackground = true
        textView.textContainerInset = NSSize(width: 48, height: 32)
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        // Cmd+F find bar embedded in the scroll view.
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        // Writing Tools: limited mode is appropriate for read-only text —
        // results appear in the Writing Tools panel and can be copied.
        textView.writingToolsBehavior = .limited
        scrollView.documentView = textView

        // Observe end-of-live-scroll so we can persist the position.
        context.coordinator.observeScrollEnd(of: scrollView)
        // Observe selection changes (user click) to expose the insertion-point offset.
        context.coordinator.observeSelection(of: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        // Always keep callbacks current (struct props change every render).
        context.coordinator.onProgressChange    = onProgressChange
        context.coordinator.onTextReady         = onTextReady
        context.coordinator.onSelectionChange   = onSelectionChange
        context.coordinator.onHeadingsReady     = onHeadingsReady
        context.coordinator.onTotalPagesChanged = onTotalPagesChanged

        let textView = scrollView.documentView as! NSTextView

        // Scrollbar visibility depends on mode.
        let isPageMode = readingMode == .page
        scrollView.hasVerticalScroller      = !isPageMode
        scrollView.verticalScrollElasticity = isPageMode ? .none : .automatic

        // Karaoke highlight — handled independently, no content reload needed.
        // In page mode we apply the highlight but suppress auto-scrolling (page nav handles position).
        let prevRange = context.coordinator.lastHighlightRange
        if !nsRangesEqual(prevRange, highlightRange) {
            Self.applyHighlight(new: highlightRange, old: prevRange, in: textView)
            context.coordinator.lastHighlightRange = highlightRange
            if let r = highlightRange, !isPageMode {
                textView.scrollRangeToVisible(r)
            }
        }

        let key = CacheKey(url: fileURL.standardizedFileURL, fontSize: fontSize, theme: theme, readingMode: readingMode)

        // Page navigation within the same chapter (before the key guard so it runs every render).
        if isPageMode, context.coordinator.lastKey == key,
           currentPage != context.coordinator.renderedPage,
           currentPage < context.coordinator.pageBreaks.count {
            let y = context.coordinator.pageBreaks[currentPage]
            context.coordinator.renderedPage = currentPage
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                ctx.allowsImplicitAnimation = true
                scrollView.contentView.animator().setBoundsOrigin(NSPoint(x: 0, y: y))
            }
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        // Programmatic scroll command (bookmark navigation within the same chapter).
        if let target = scrollTarget, target != context.coordinator.lastScrollTarget {
            context.coordinator.lastScrollTarget = target
            Self.restore(progress: target, in: scrollView)
        }

        guard context.coordinator.lastKey != key else { return }
        context.coordinator.lastKey = key
        context.coordinator.lastScrollTarget = nil  // New chapter: allow targets to re-apply fresh.

        scrollView.backgroundColor = theme.background
        textView.backgroundColor = theme.background

        let progressToRestore = savedProgress

        Task {
            let rawData = await Task.detached(priority: .userInitiated) {
                try? Data(contentsOf: fileURL)
            }.value
            guard let rawData else { return }

            let htmlString = String(data: rawData, encoding: .utf8)
                          ?? String(data: rawData, encoding: .isoLatin1)
                          ?? ""
            let baseURL = fileURL.deletingLastPathComponent()
            let processed = Self.prepareHTML(htmlString, baseURL: baseURL, fontSize: fontSize, theme: theme)

            let attrStr = NSAttributedString(html: Data(processed.utf8), baseURL: baseURL, documentAttributes: nil)
                       ?? NSAttributedString(
                            string: Self.plainText(from: htmlString),
                            attributes: [.foregroundColor: theme.background.isDark ? NSColor.white : NSColor.black,
                                         .font: NSFont.systemFont(ofSize: fontSize)]
                          )

            textView.textStorage?.setAttributedString(attrStr)

            // Re-apply karaoke highlight after the attributed string replaces all attributes.
            if let r = highlightRange, NSMaxRange(r) <= (textView.textStorage?.length ?? 0) {
                Self.applyHighlight(new: r, old: nil, in: textView)
            }

            // Extract heading texts from raw HTML and notify before sending plain text to TTS.
            let onHeadings = context.coordinator.onHeadingsReady
            onHeadings?(Self.extractHeadingTexts(from: htmlString))

            // Notify TTS controller with the plain text (ranges match textStorage exactly).
            let onReady = context.coordinator.onTextReady
            onReady?(textView.string)

            // Force complete text layout so frame.height is accurate before scrolling.
            // Without this, frame.height may be stale (from the previous chapter),
            // causing the restored position to land slightly higher than expected.
            if let tc = textView.textContainer {
                textView.layoutManager?.ensureLayout(for: tc)
            }
            textView.sizeToFit()

            if readingMode == .page {
                // Compute page breaks now that layout is final.
                let visibleH = scrollView.contentView.bounds.height
                let breaks = Self.computePageBreaks(in: textView, visibleHeight: visibleH)
                context.coordinator.pageBreaks  = breaks
                context.coordinator.renderedPage = 0
                let onPages = context.coordinator.onTotalPagesChanged
                onPages?(breaks.count)
                scrollView.contentView.scroll(to: .zero)
                scrollView.reflectScrolledClipView(scrollView.contentView)
            } else if progressToRestore > 0.01 {
                Self.restore(progress: progressToRestore, in: scrollView)
            } else {
                textView.scrollToBeginningOfDocument(nil)
            }
        }
    }

    // MARK: - Scroll helpers

    static func computeScrollProgress(of scrollView: NSScrollView) -> Double {
        guard let docView = scrollView.documentView else { return 0 }
        let contentHeight = docView.frame.height
        let visibleHeight = scrollView.contentView.bounds.height
        let scrollable = contentHeight - visibleHeight
        guard scrollable > 1 else { return 0 }
        let currentY = scrollView.contentView.bounds.origin.y
        return Double(min(max(currentY / scrollable, 0), 1))
    }

    private static func restore(progress: Double, in scrollView: NSScrollView) {
        guard let docView = scrollView.documentView else { return }
        let contentHeight = docView.frame.height
        let visibleHeight = scrollView.contentView.bounds.height
        let scrollable = max(0, contentHeight - visibleHeight)
        guard scrollable > 1 else { return }
        let targetY = CGFloat(progress) * scrollable
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: targetY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    // MARK: - Karaoke highlight

    private static func applyHighlight(new: NSRange?, old: NSRange?, in textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        if let old, NSMaxRange(old) <= storage.length {
            storage.removeAttribute(.backgroundColor, range: old)
        }
        if let new, NSMaxRange(new) <= storage.length {
            storage.addAttribute(.backgroundColor,
                                 value: NSColor.systemYellow.withAlphaComponent(0.45),
                                 range: new)
        }
    }

    // MARK: - Cache key

    struct CacheKey: Equatable {
        let url: URL
        let fontSize: Double
        let theme: ReaderTheme
        let readingMode: ReadingMode
    }

    // MARK: - Coordinator

    final class Coordinator {
        var lastKey: CacheKey?
        var onProgressChange: ((Double) -> Void)?
        var onTextReady: ((String) -> Void)?
        var onSelectionChange: ((Int) -> Void)?
        var onHeadingsReady: ((Set<String>) -> Void)?
        var onTotalPagesChanged: ((Int) -> Void)?
        var lastHighlightRange: NSRange?
        /// Last scroll target applied programmatically; prevents re-applying the same command on re-render.
        var lastScrollTarget: Double? = nil
        /// Y-positions (in scroll coordinate space) of the start of each page.
        var pageBreaks: [CGFloat] = []
        /// The page that is currently visible (matches the last animated scroll target).
        var renderedPage: Int = 0
        nonisolated(unsafe) private var scrollObserver: Any?
        nonisolated(unsafe) private var selectionObserver: Any?

        func observeScrollEnd(of scrollView: NSScrollView) {
            scrollObserver = NotificationCenter.default.addObserver(
                forName: NSScrollView.didEndLiveScrollNotification,
                object: scrollView,
                queue: .main
            ) { [weak self, weak scrollView] _ in
                guard let scrollView else { return }
                let progress = ChapterTextView.computeScrollProgress(of: scrollView)
                self?.onProgressChange?(progress)
            }
        }

        func observeSelection(of textView: NSTextView) {
            selectionObserver = NotificationCenter.default.addObserver(
                forName: NSTextView.didChangeSelectionNotification,
                object: textView,
                queue: .main
            ) { [weak self, weak textView] _ in
                guard let textView else { return }
                self?.onSelectionChange?(textView.selectedRange().location)
            }
        }

        deinit {
            [scrollObserver, selectionObserver].compactMap { $0 }.forEach {
                NotificationCenter.default.removeObserver($0)
            }
        }
    }

    // MARK: - HTML preprocessing

    private static func prepareHTML(_ html: String, baseURL: URL, fontSize: Double, theme: ReaderTheme) -> String {
        var result = html
        result = stripTTSNoise(from: result)
        result = inject(css: cssOverride(fontSize: fontSize, theme: theme), into: result)
        result = absolutifyImageSrcs(in: result, baseURL: baseURL)
        return result
    }

    /// Removes HTML elements that produce noise when read aloud:
    ///  - <sup>: footnote reference numbers (¹ ² ³)
    ///  - <a epub:type="noteref">: inline note-reference anchors
    ///  - <aside epub:type="footnote/note/endnote">: full footnote blocks
    /// Stripping at the HTML level keeps textView.string and NSRange consistent.
    private static func stripTTSNoise(from html: String) -> String {
        var s = html
        let opts: NSString.CompareOptions = [.regularExpression, .caseInsensitive]
        s = s.replacingOccurrences(of: "<sup[^>]*>[\\s\\S]*?</sup>",
                                   with: "", options: opts)
        s = s.replacingOccurrences(of: "<a\\b[^>]*epub:type=[\"']noteref[\"'][^>]*>[\\s\\S]*?</a>",
                                   with: "", options: opts)
        s = s.replacingOccurrences(of: "<aside\\b[^>]*epub:type=[\"'](?:footnote|endnote|note|rearnote)[\"'][^>]*>[\\s\\S]*?</aside>",
                                   with: "", options: opts)
        return s
    }

    private static func cssOverride(fontSize: Double, theme: ReaderTheme) -> String {
        """
        html, body {
            background-color: \(theme.cssBackground) !important;
            color: \(theme.cssText) !important;
            font-family: -apple-system, Georgia, serif !important;
            font-size: \(Int(fontSize))px !important;
            line-height: 1.7 !important;
            max-width: 720px !important;
            margin: 0 auto !important;
        }
        img { max-width: 100% !important; height: auto !important; }
        a { color: inherit !important; }
        """
    }

    private static func inject(css: String, into html: String) -> String {
        let tag = "<style>\(css)</style>"
        if let range = html.range(of: "</head>", options: .caseInsensitive) {
            return html.replacingCharacters(in: range, with: tag + "</head>")
        }
        return tag + html
    }

    private static func absolutifyImageSrcs(in html: String, baseURL: URL) -> String {
        let pattern = #"(?i)\bsrc=(["'])(?!data:|https?:|file:)([^"']*)\1"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return html }
        let nsHTML = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))
        var result = html
        for match in matches.reversed() {
            guard let srcRange = Range(match.range(at: 2), in: html),
                  let wholeRange = Range(match.range, in: result) else { continue }
            let relativeSrc = String(html[srcRange])
            guard let encoded = relativeSrc.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                  let absoluteURL = URL(string: encoded, relativeTo: baseURL)?.absoluteURL else { continue }
            let quoteChar = html[Range(match.range(at: 1), in: html)!]
            result = result.replacingCharacters(in: wholeRange, with: "src=\(quoteChar)\(absoluteURL.absoluteString)\(quoteChar)")
        }
        return result
    }

    /// Computes the Y scroll offsets at which each page starts.
    /// Pages break at line boundaries so no line is ever cut in half.
    private static func computePageBreaks(in textView: NSTextView, visibleHeight: CGFloat) -> [CGFloat] {
        guard let lm = textView.layoutManager, let tc = textView.textContainer, visibleHeight > 0 else {
            return [0]
        }
        lm.ensureLayout(for: tc)
        let insetH = textView.textContainerInset.height
        var breaks: [CGFloat] = [0]
        var pageStartY: CGFloat = 0
        lm.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: lm.numberOfGlyphs)) { rect, _, _, _, _ in
            let lineBottom = rect.maxY + insetH
            if lineBottom > pageStartY + visibleHeight {
                // This line doesn't fit on the current page — start a new page at its top.
                let lineTop = rect.minY + insetH
                breaks.append(lineTop)
                pageStartY = lineTop
            }
        }
        return breaks
    }

    private static func plainText(from html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Extracts the plain-text content of every <h1>–<h6> element in the given HTML.
    /// Used so TTSController can recognise heading sentences and safely convert single-character
    /// Roman numerals ("I. The best and the worse" → "un. The best and the worse").
    static func extractHeadingTexts(from html: String) -> Set<String> {
        guard let re = try? NSRegularExpression(
            pattern: "<h[1-6][^>]*>(.*?)</h[1-6]>",
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return [] }
        let ns = html as NSString
        var result = Set<String>()
        for match in re.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            guard let range = Range(match.range(at: 1), in: html) else { continue }
            let text = String(html[range])
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .replacingOccurrences(of: "&amp;",  with: "&")
                .replacingOccurrences(of: "&lt;",   with: "<")
                .replacingOccurrences(of: "&gt;",   with: ">")
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&nbsp;", with: " ")
                .replacingOccurrences(of: "&#160;", with: " ")
                .replacingOccurrences(of: "\\s+",   with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { result.insert(text) }
        }
        return result
    }
}

// MARK: - NSRange equality helper

private func nsRangesEqual(_ a: NSRange?, _ b: NSRange?) -> Bool {
    switch (a, b) {
    case (nil, nil): return true
    case (let x?, let y?): return x.location == y.location && x.length == y.length
    default: return false
    }
}

// MARK: - NSColor helper

private extension NSColor {
    var isDark: Bool {
        guard let rgb = usingColorSpace(.deviceRGB) else { return false }
        let luminance = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
        return luminance < 0.5
    }
}
