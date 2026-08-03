//
//  ContentView.swift
//  AIudioBook
//
//  Created by sanchezg on 17/07/2026.
//

import LibraryFeature
import ReaderFeature
import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            LibraryView()
                .navigationDestination(for: Book.self) { book in
                    ReaderView(book: book)
                }
        }
        .frame(minWidth: 700, minHeight: 500)
    }
}

#Preview {
    ContentView()
}
