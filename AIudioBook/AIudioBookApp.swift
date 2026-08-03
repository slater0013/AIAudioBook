//
//  AIudioBookApp.swift
//  AIudioBook
//
//  Created by sanchezg on 17/07/2026.
//

import LibraryFeature
import SwiftData
import SwiftUI

@main
struct AIudioBookApp: App {
    @State private var bookmarkStore = BookmarkStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(bookmarkStore)
        }
        .modelContainer(for: Book.self)
    }
}
