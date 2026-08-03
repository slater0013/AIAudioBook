//
//  TTSSettingsView.swift
//  ReaderFeature
//
//  Popover for TTS speed, voice, and server URL settings.
//

import SwiftUI

struct TTSSettingsView: View {
    @Bindable var controller: TTSController

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            speedSection
            Divider()
            voiceSection
            Divider()
            serverSection
        }
        .padding(20)
        .frame(width: 320)
    }

    // MARK: - Speed

    private var speedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text("Speed", bundle: .module)
            } icon: {
                Image(systemName: "gauge.with.needle")
            }
            .font(.subheadline.weight(.medium))

            HStack(spacing: 10) {
                Image(systemName: "tortoise")
                    .foregroundStyle(.secondary)
                Slider(value: $controller.speed, in: 0.5...2.0, step: 0.1)
                Image(systemName: "hare")
                    .foregroundStyle(.secondary)
                Text(String(format: "%.1f×", controller.speed))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
            }
        }
    }

    // MARK: - Voice

    private var voiceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text("Voice", bundle: .module)
            } icon: {
                Image(systemName: "waveform")
            }
            .font(.subheadline.weight(.medium))

            Picker("", selection: $controller.voice) {
                ForEach(TTSController.availableVoices) { voice in
                    voiceRow(voice).tag(voice.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }

    private func voiceRow(_ voice: TTSController.VoiceInfo) -> some View {
        HStack(spacing: 6) {
            Text(voice.displayName)
            Text("·").foregroundStyle(.secondary)
            Text(voice.locale).foregroundStyle(.secondary)
        }
    }

    // MARK: - Server

    private var serverSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text("TTS Server", bundle: .module)
            } icon: {
                Image(systemName: "server.rack")
            }
            .font(.subheadline.weight(.medium))

            TextField("http://localhost:8880", text: $controller.serverURL)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))
        }
    }
}
