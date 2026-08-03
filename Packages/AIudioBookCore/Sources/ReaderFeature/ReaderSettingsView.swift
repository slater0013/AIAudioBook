//
//  ReaderSettingsView.swift
//  ReaderFeature
//
//  Popover with font-size slider and theme selector shown from the reader toolbar.
//

import AppKit
import SwiftUI

struct ReaderSettingsView: View {
    @Binding var fontSize: Double
    @Binding var theme: ReaderTheme
    @Binding var readingMode: ReadingMode

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            fontSizeSection
            Divider()
            themeSection
            Divider()
            readingModeSection
        }
        .padding(20)
        .frame(width: 300)
    }

    // MARK: - Font size

    private var fontSizeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text("Text Size", bundle: .module)
            } icon: {
                Image(systemName: "textformat.size")
            }
            .font(.subheadline.weight(.medium))

            HStack(spacing: 10) {
                Image(systemName: "textformat.size.smaller")
                    .foregroundStyle(.secondary)
                Slider(value: $fontSize, in: 12...28, step: 1)
                Image(systemName: "textformat.size.larger")
                    .foregroundStyle(.secondary)
                Text("\(Int(fontSize))")
                    .monospacedDigit()
                    .frame(width: 26, alignment: .trailing)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Reading mode

    private var readingModeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text("Reading Mode", bundle: .module)
            } icon: {
                Image(systemName: "book.pages")
            }
            .font(.subheadline.weight(.medium))

            Picker("", selection: $readingMode) {
                Text("Scroll", bundle: .module).tag(ReadingMode.scroll)
                Text("Pages",  bundle: .module).tag(ReadingMode.page)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    // MARK: - Theme

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text("Theme", bundle: .module)
            } icon: {
                Image(systemName: "circle.lefthalf.filled")
            }
            .font(.subheadline.weight(.medium))

            HStack(spacing: 12) {
                ForEach(ReaderTheme.allCases, id: \.self) { t in
                    ThemeButton(theme: t, isSelected: theme == t) { theme = t }
                }
            }
        }
    }
}

// MARK: - Theme button

private struct ThemeButton: View {
    let theme: ReaderTheme
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: theme.background))
                    .frame(width: 72, height: 44)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(
                                isSelected ? Color.accentColor : Color.gray.opacity(0.35),
                                lineWidth: isSelected ? 2.5 : 1
                            )
                    )
                Text(theme.label)
                    .font(.caption)
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}
