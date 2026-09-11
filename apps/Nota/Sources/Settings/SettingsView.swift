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
    @AppStorage("nota.showMarginByDefault") private var showMarginByDefault = true

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
                Text("Every statement in a note can be traced back to the words that produced it.")
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
                    Text("No templates were reported by the engine.")
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
                Text("Templates are read-only here on purpose. Editing them changes what a required section is, which is a clinical decision, not a preference.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct RecordingSettings: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section("Shortcuts") {
                LabeledContent("Start or stop recording", value: "⌥⌘R")
                LabeledContent("Pause or resume", value: "⌥⌘P")
                LabeledContent("Open Nota", value: "⌘⇧N")
                LabeledContent("File a note", value: "⌘↩")
            }
            Section("Audio") {
                Text("Audio is captured and discarded. Nota does not keep a recording unless you ask it to, and never sends audio anywhere.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct PrivacySettings: View {
    var body: some View {
        Form {
            Section("Where your data is") {
                Text("Everything Nota produces stays in this Mac's application support folder. There is no account, no sync, and no server.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Nota contains no networking code at all. This is enforced in continuous integration, not just promised.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Not yet implemented") {
                Text("Encryption at rest and a retention policy are not built yet. Until they are, do not use Nota with real patient data.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Section("Identifiers") {
                Text("Nota stores an opaque reference for an encounter, never a name, record number, or date of birth.")
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
            Text("Nota")
                .font(.system(size: 26, weight: .semibold, design: .serif))
            Text("Clinical notes that never leave the room.")
                .foregroundStyle(.secondary)
            Text("Engine contract \(NotaCore.schemaVersion)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
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
