//
//  BookCoverCell.swift
//  LibraryFeature
//
//  One book in the library grid: cover image (or placeholder), title, authors.
//

import SwiftUI

struct BookCoverCell: View {
    let book: Book

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CoverImageView(url: BookLibrary.coverURL(for: book), title: book.title)
                .frame(height: 220)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(color: .black.opacity(0.25), radius: 4, y: 2)

            Text(book.title)
                .font(.headline)
                .lineLimit(2)
            if !book.authors.isEmpty {
                Text(book.authorsLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

/// Loads a cover image from disk asynchronously; falls back to a styled placeholder.
struct CoverImageView: View {
    let url: URL?
    let title: String

    @State private var image: Image?

    var body: some View {
        ZStack {
            if let image {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.quaternary)
                Text(title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(12)
            }
        }
        .task(id: url) {
            image = await Self.loadImage(at: url)
        }
    }

    private nonisolated static func loadImage(at url: URL?) async -> Image? {
        guard let url else { return nil }
        #if canImport(AppKit)
        guard let platformImage = NSImage(contentsOf: url) else { return nil }
        return Image(nsImage: platformImage)
        #else
        guard let data = try? Data(contentsOf: url),
              let platformImage = UIImage(data: data) else { return nil }
        return Image(uiImage: platformImage)
        #endif
    }
}
