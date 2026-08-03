//
//  TOCSidebar.swift
//  ReaderFeature
//
//  Table of contents panel; selecting an entry jumps to its chapter.
//

import EPUBKit
import SwiftUI

struct TOCSidebar: View {
    let entries: [EPUBTOCEntry]
    let onSelect: (EPUBTOCEntry) -> Void

    var body: some View {
        List {
            OutlineGroup(entries, id: \.self, children: \.outlineChildren) { entry in
                Button {
                    onSelect(entry)
                } label: {
                    Text(entry.title)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.sidebar)
    }
}

extension EPUBTOCEntry {
    /// `OutlineGroup` expects `nil` (not an empty array) for leaf nodes.
    fileprivate var outlineChildren: [EPUBTOCEntry]? {
        children.isEmpty ? nil : children
    }
}
