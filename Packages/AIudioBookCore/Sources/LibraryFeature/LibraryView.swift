//
//  LibraryView.swift
//  LibraryFeature
//
//  The user's book library: a grid of covers with import and delete actions.
//

import SwiftData
import SwiftUI
import UniformTypeIdentifiers

public struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Book.importedAt, order: .reverse) private var books: [Book]

    @State private var isImporterPresented = false
    @State private var isImporting = false
    @State private var importFailureMessage: String?

    public init() {}

    public var body: some View {
        Group {
            if books.isEmpty {
                ContentUnavailableView {
                    Label {
                        Text("Your Library Is Empty", bundle: .module)
                    } icon: {
                        Image(systemName: "books.vertical")
                    }
                } description: {
                    Text("Import an EPUB file to get started.", bundle: .module)
                } actions: {
                    importButton
                }
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 24)],
                        alignment: .leading,
                        spacing: 32
                    ) {
                        ForEach(books) { book in
                            NavigationLink(value: book) {
                                BookCoverCell(book: book)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) {
                                    delete(book)
                                } label: {
                                    Label {
                                        Text("Delete Book", bundle: .module)
                                    } icon: {
                                        Image(systemName: "trash")
                                    }
                                }
                            }
                        }
                    }
                    .padding(24)
                }
            }
        }
        .navigationTitle(Text("Library", bundle: .module))
        .toolbar {
            ToolbarItem {
                if isImporting {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    importButton
                }
            }
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.epub],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                importBooks(from: urls)
            }
        }
        .alert(
            Text("Import Failed", bundle: .module),
            isPresented: Binding(
                get: { importFailureMessage != nil },
                set: { if !$0 { importFailureMessage = nil } }
            )
        ) {
            Button("OK") { importFailureMessage = nil }
        } message: {
            Text(importFailureMessage ?? "")
        }
    }

    private var importButton: some View {
        Button {
            isImporterPresented = true
        } label: {
            Label {
                Text("Import Books…", bundle: .module)
            } icon: {
                Image(systemName: "plus")
            }
        }
    }

    private func importBooks(from urls: [URL]) {
        isImporting = true
        Task {
            for url in urls {
                do {
                    // File copy + unzip + XML parsing happen off the main actor.
                    let imported = try await Task.detached {
                        try BookLibrary.importEPUB(at: url)
                    }.value
                    let book = Book(
                        title: imported.metadata.title,
                        authors: imported.metadata.authors,
                        language: imported.metadata.language,
                        synopsis: imported.metadata.synopsis,
                        publisher: imported.metadata.publisher,
                        folderName: imported.folderName,
                        coverRelativePath: imported.coverRelativePath
                    )
                    modelContext.insert(book)
                } catch {
                    importFailureMessage = error.localizedDescription
                }
            }
            isImporting = false
        }
    }

    private func delete(_ book: Book) {
        BookLibrary.deleteFolder(of: book)
        modelContext.delete(book)
    }
}

#Preview {
    NavigationStack {
        LibraryView()
    }
    .modelContainer(for: Book.self, inMemory: true)
}
