//
//  ReaderTheme.swift
//  ReaderFeature
//

import AppKit

enum ReaderTheme: String, CaseIterable {
    case light, sepia, dark

    /// NSColor used for the NSScrollView/NSTextView background.
    var background: NSColor {
        switch self {
        case .light: .white
        case .sepia: NSColor(srgbRed: 0.969, green: 0.941, blue: 0.902, alpha: 1)
        case .dark:  NSColor(srgbRed: 0.11,  green: 0.11,  blue: 0.118, alpha: 1)
        }
    }

    var cssBackground: String {
        switch self {
        case .light: "#FFFFFF"
        case .sepia: "#F7F0E6"
        case .dark:  "#1C1C1E"
        }
    }

    var cssText: String {
        switch self {
        case .light: "#1A1A1A"
        case .sepia: "#3B2A1A"
        case .dark:  "#E5E5E7"
        }
    }

    var label: String {
        switch self {
        case .light: String(localized: "Light", bundle: .module)
        case .sepia: String(localized: "Sepia", bundle: .module)
        case .dark:  String(localized: "Dark",  bundle: .module)
        }
    }
}

/// Whether the reader shows a continuous scroll or snaps page by page.
enum ReadingMode: String {
    case scroll, page
}
