//
// SettingsView.swift
//
// Native macOS Preferences: a tabbed window, grouped forms, no invention.
// The Privacy pane is the one a practice will read before saying yes.
//

import SwiftUI

struct SettingsRootView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        TabView {
            GeneralSettings(model: model)
                .tabItem { Label("General", systemImage: "gearshape") }
            TemplateSettings(model: model)
                .tabItem { Label("Templates", systemImage: "list.bullet.rectangle") }
            RecordingSettings(model: model)
                .tabItem { Label("Recording", systemImage: "waveform") }
            PrivacySettings()
                .tabItem { Label("Privacy", systemImage: "lock") }
            AboutSettings()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 560, height: 420)
    }
}

private struct GeneralSettings: View {
    @ObservedObject var model: AppModel
    @AppStorage("klinote.showMarginByDefault") private var showMarginByDefault = true

    var body: some View {
        Form {
            Section("Defaults") {
                Picker("Discipline", selection: $model.discipline) {
                    Text("General practice").tag("general_practice")
                    Text("Physiotherapy").tag("physiotherapy")
                    Text("Psychology").tag("psychology")
                    Text("Dentistry").tag("dentistry")
                    Text("Veterinary").tag("veterinary")
                }
                .pickerStyle(.menu)

                Picker("Template", selection: $model.templateId) {
                    ForEach(model.templates) { template in
                        Text(template.name).tag(template.id)
                    }
                    if model.templates.isEmpty {
                        Text("SOAP Note").tag("soap")
                    }
                }
                .pickerStyle(.menu)
            }

            Section("Review window") {
                Toggle("Show the evidence margin", isOn: $showMarginByDefault)
                Text("Click a sentence to see the words that produced it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct TemplateSettings: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            if model.templates.isEmpty {
                Section {
                    Text("No templates loaded.")
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(model.templates) { template in
                Section(template.name) {
                    LabeledContent("Discipline", value: template.discipline)
                    LabeledContent("Version", value: template.version)
                    if !template.description.isEmpty {
                        Text(template.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(template.sections) { section in
                        HStack {
                            Text(section.title)
                            Spacer()
                            Text(section.required ? "Required" : "Optional")
                                .font(.caption)
                                .foregroundStyle(section.required ? .primary : .secondary)
                        }
                    }
                }
            }
            Section {
                Text("Required sections are a clinical decision. That is why templates are read-only here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct RecordingSettings: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var downloader = ModelDownloader.shared

    var body: some View {
        Form {
            Section("Listening") {
                LabeledContent("Status", value: downloader.state.word)
                switch downloader.state {
                case .missing:
                    Button("Download listening (465 MB, once)") {
                        downloader.start()
                    }
                    Text("Turns speech into text on this Mac. Download before a consult, not during one.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .downloading(let fraction):
                    ProgressView(value: fraction)
                    Button("Cancel") { downloader.cancel() }
                case .ready:
                    Text("Ready. Speech is transcribed on this Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .failed(let message):
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Button("Retry download") { downloader.start() }
                }
            }
            Section("Shortcuts") {
                LabeledContent("Start or stop recording", value: "⌥⌘R")
                LabeledContent("Pause or resume", value: "⌥⌘P")
                LabeledContent("Copy note", value: "⌘⇧C")
                LabeledContent("Swap clinician and patient", value: "⌥⌘S")
                LabeledContent("Open Klinote", value: "⌘⇧N")
                LabeledContent("File a note", value: "⌘↩")
            }
            Section("Quire") {
                LabeledContent("Status", value: downloader.noteState.word)
                switch downloader.noteState {
                case .missing:
                    Button("Download Quire (1.9 GB, once)") {
                        downloader.startNote()
                    }
                    Text("Writes the note from the consult. Stays on this Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .downloading(let fraction):
                    ProgressView(value: fraction)
                case .ready:
                    Text("Ready. Notes are written on this Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .failed(let message):
                    Text(message).font(.caption).foregroundStyle(.orange)
                    Button("Retry download") { downloader.startNote() }
                }
            }
            Section("Audio") {
                Text("Audio is used to write the note, then discarded. It is not uploaded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct PrivacySettings: View {
    @AppStorage("klinote.teachingBuildAcknowledged") private var teachingBuildAcknowledged = false

    var body: some View {
        Form {
            Section("This build") {
                Toggle("I understand this build is for teaching only", isOn: $teachingBuildAcknowledged)
                Text("Nothing is encrypted at rest yet. Do not record real patients. Recording stays off until you confirm this.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Section("Where it lives") {
                Text("Notes stay on this Mac. There is no account, no sync, and no server. The only download is listening and Quire, once each. Audio and notes are never uploaded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Not yet") {
                Text("No encryption at rest. No retention policy. Do not use real patient data in this build.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Section("Names") {
                Text("Klinote stores a code for the encounter, never a name, record number, or date of birth.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct AboutSettings: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("klinote")
                .font(.system(size: 28, weight: .semibold))
                .tracking(-0.8)
                .foregroundStyle(KlinoteColor.ink)
            Text("Clinical notes that never leave the room.")
                .foregroundStyle(.secondary)
            Text(AppVersion.display)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.top, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

enum AppVersion {
    static var display: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "Version \(version) (build \(build))"
    }
}
