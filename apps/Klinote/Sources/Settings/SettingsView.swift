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
            PrivacySettings(model: model)
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
                    Text("Psychology").tag("psychology")
                    Text("General practice").tag("general_practice")
                    Text("Physiotherapy").tag("physiotherapy")
                    Text("Dentistry").tag("dentistry")
                    Text("Veterinary").tag("veterinary")
                }
                .pickerStyle(.menu)

                Picker("Note template", selection: $model.templateId) {
                    ForEach(model.noteTemplates) { template in
                        Text(template.name).tag(template.id)
                    }
                    if model.noteTemplates.isEmpty {
                        Text("Therapy Session Note").tag("psychology")
                    }
                }
                .pickerStyle(.menu)

                if !model.documentTemplates.isEmpty {
                    Text("Referral letters and the client's copy are made from a session, on the Session menu.")
                        .font(KlinoteFont.caption())
                        .foregroundStyle(KlinoteColor.secondary)
                }
            }

            Section("Starting up") {
                Toggle("Open the letter when Klinote starts", isOn: $model.openWindowAtLaunch)
                Text("Klinote is a menu-bar app. With this off it starts silently and waits for ⌥⌘R or the menu-bar icon.")
                    .font(KlinoteFont.caption())
                    .foregroundStyle(KlinoteColor.secondary)
            }

            Section("Who is at the desk") {
                TextField("Your name", text: $model.clinicianName)
                TextField("Registration or professional number", text: $model.clinicianRegistration)
                Text("Appears in the signature block, and identifies your sessions on a shared Mac. Not a login — Klinote still has no account.")
                    .font(KlinoteFont.caption())
                    .foregroundStyle(KlinoteColor.secondary)
                Toggle("Show other clinicians' sessions", isOn: $model.showAllClinicians)
                    .disabled(model.clinicianName.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Section("Review window") {
                Toggle("Show the evidence margin", isOn: $showMarginByDefault)
                Text("Click a sentence to see the words that produced it.")
                    .font(KlinoteFont.caption())
                    .foregroundStyle(KlinoteColor.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct TemplateSettings: View {
    @ObservedObject var model: AppModel
    @State private var selectedID = ""
    @State private var draft: TemplateSummary?
    @State private var status: String?

    private var hasOverride: Bool {
        let path = KlinoteCore.templatesDirectory
            .appendingPathComponent("\(selectedID).toml")
        return FileManager.default.fileExists(atPath: path.path)
    }

    var body: some View {
        Form {
            if model.templates.isEmpty {
                Section {
                    Text("No templates loaded.")
                        .foregroundStyle(KlinoteColor.secondary)
                }
            } else {
                Section("Template") {
                    Picker("Editing", selection: $selectedID) {
                        ForEach(model.templates) { template in
                            Text(template.name).tag(template.id)
                        }
                    }
                    .pickerStyle(.menu)
                }

                if let draft = Binding($draft) {
                    Section("About this template") {
                        TextField("Name", text: draft.name)
                        TextField("Description", text: draft.description)
                        TextField(
                            "Register (how the model should write it)",
                            text: Binding(
                                get: { draft.wrappedValue.voice ?? "" },
                                set: { draft.wrappedValue.voice = $0 }
                            ),
                            axis: .vertical
                        )
                        LabeledContent("Id", value: draft.wrappedValue.id)
                            .font(KlinoteFont.caption())
                    }

                    ForEach(draft.sections) { section in
                        Section(section.wrappedValue.title) {
                            TextField("Title", text: section.title)
                            Toggle("Required before signing", isOn: section.required)
                            TextField("Guidance", text: section.guidance, axis: .vertical)
                            TextField("Cues (comma separated)", text: section.cuesText, axis: .vertical)
                                .font(KlinoteFont.data())
                            Text(
                                section.wrappedValue.cues.isEmpty
                                    ? "No cues: the rule-based engine will not route anything here."
                                    : "\(section.wrappedValue.cues.count) cues"
                            )
                            .font(KlinoteFont.caption())
                            .foregroundStyle(KlinoteColor.secondary)
                        }
                    }

                    Section {
                        HStack {
                            Button("Save") { save() }
                            Button("Revert to built-in") { revert() }
                                .disabled(!hasOverride)
                            Spacer()
                            if let status {
                                Text(status)
                                    .font(KlinoteFont.caption())
                                    .foregroundStyle(KlinoteColor.secondary)
                            }
                        }
                        Text("Saved to \(KlinoteCore.templatesDirectory.path). A practice template survives an app update and can be read, diffed or shared. Deleting it restores the built-in.")
                            .font(KlinoteFont.caption())
                            .foregroundStyle(KlinoteColor.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: load)
        .onChange(of: selectedID) { _, _ in load() }
        .onChange(of: model.templates) { _, _ in load() }
    }

    private func load() {
        if selectedID.isEmpty || !model.templates.contains(where: { $0.id == selectedID }) {
            selectedID = model.templates.first?.id ?? ""
        }
        draft = model.templates.first { $0.id == selectedID }
        status = nil
    }

    private func save() {
        guard let draft else { return }
        do {
            try KlinoteCore.saveTemplate(draft)
            model.reloadTemplates()
            status = "Saved"
        } catch {
            status = "Could not save: \(error.localizedDescription)"
        }
    }

    private func revert() {
        do {
            try KlinoteCore.revertTemplate(id: selectedID)
            model.reloadTemplates()
            status = "Built-in restored"
        } catch {
            status = "Could not revert: \(error.localizedDescription)"
        }
    }
}

private struct RecordingSettings: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var downloader = ModelDownloader.shared

    var body: some View {
        Form {
            Section("Listening") {
                // Not a download any more, and not a one-off decision: this is a
                // capability of the Mac. See Transcriber.swift.
                LabeledContent(
                    "Status",
                    value: Transcriber.isAvailable ? "Ready on this Mac" : "Not available"
                )
                if let reason = Transcriber.unavailableReason {
                    Text(reason)
                        .font(KlinoteFont.caption())
                        .foregroundStyle(KlinoteColor.caution)
                } else {
                    Text("Speech is transcribed on this Mac by the system's own speech model. There is nothing to download, and the audio is never uploaded.")
                        .font(KlinoteFont.caption())
                        .foregroundStyle(KlinoteColor.secondary)
                }
            }
            Section("Shortcuts") {
                LabeledContent("Start or stop recording", value: "⌥⌘R")
                LabeledContent("Pause or resume", value: "⌥⌘P")
                LabeledContent("Copy note", value: "⌘⇧C")
                LabeledContent("Swap therapist and client", value: "⌥⌘S")
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
                    Text("Writes the note from the transcript. Stays on this Mac. Without it the built-in rules write a thinner draft, and the note says so. It can be added later — a note already written is written again from its saved transcript.")
                        .font(KlinoteFont.caption())
                        .foregroundStyle(KlinoteColor.secondary)
                case .downloading(let fraction):
                    ProgressView(value: fraction)
                case .ready:
                    Text("Ready. Notes are written on this Mac.")
                        .font(KlinoteFont.caption())
                        .foregroundStyle(KlinoteColor.secondary)
                case .failed(let message):
                    Text(message).font(KlinoteFont.caption()).foregroundStyle(KlinoteColor.caution)
                    Button("Retry download") { downloader.startNote() }
                }
            }
            Section("Audio") {
                Text("Audio is used to write the note, then discarded. It is not uploaded.")
                    .font(KlinoteFont.caption())
                    .foregroundStyle(KlinoteColor.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct PrivacySettings: View {
    @ObservedObject var model: AppModel

    private let periods: [(String, Int)] = [
        ("Keep everything", 0),
        ("3 months", 3),
        ("12 months", 12),
        ("36 months", 36),
    ]

    var body: some View {
        Form {
            Section("Retention") {
                Picker("Keep notes for", selection: $model.retentionMonths) {
                    ForEach(periods, id: \.1) { period in
                        Text(period.0).tag(period.1)
                    }
                }
                .pickerStyle(.menu)
                Text(model.retentionMonths == 0
                     ? "Nothing is deleted automatically. Check what your jurisdiction and college require."
                     : "Notes older than \(model.retentionMonths) months are deleted at launch. This is a real delete, not a flag.")
                    .font(KlinoteFont.caption())
                    .foregroundStyle(model.retentionMonths == 0 ? .secondary : .primary)
                Button("Delete expired notes now") {
                    model.purgeExpiredNotes()
                }
                .disabled(model.retentionMonths == 0)
            }

            PrivacyReceipt()

            Section("Where it lives") {
                Text("Notes stay on this Mac, encrypted. There is no account, no sync, and no server. Audio and notes are never uploaded.")
                    .font(KlinoteFont.caption())
                    .foregroundStyle(KlinoteColor.secondary)
            }

            LearnedVocabulary()

            Section("Names") {
                Text("Klinote stores a code for the session, never a name, record number, or date of birth.")
                    .font(KlinoteFont.caption())
                    .foregroundStyle(KlinoteColor.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// The claim, with the only number we can honestly compute. This is a receipt,
/// not a badge: it says what arrives, where the data is, and how the claim is
/// checked on every build.
private struct PrivacyReceipt: View {
    @ObservedObject private var downloader = ModelDownloader.shared

    private var received: String {
        ByteCountFormatter.string(fromByteCount: downloader.bytesReceived, countStyle: .file)
    }

    var body: some View {
        Section("Receipt") {
            LabeledContent("Sent from this Mac", value: "Nothing")
            LabeledContent("Received", value: "\(received) (models only)")
            LabeledContent("Model downloads", value: "\(downloader.downloadsCompleted)")
            Text("Klinote has no server, no account and no telemetry. The app can only issue downloads — never uploads — and that is checked on every build by scripts/check-network-surface.sh. The Rust engine contains no networking code at all.")
                .font(KlinoteFont.caption())
                .foregroundStyle(KlinoteColor.secondary)
        }
    }
}

/// What this practice has taught it. Visible and forgettable, because a
/// correction the clinician cannot see is a correction they cannot trust.
private struct LearnedVocabulary: View {
    @State private var terms: [String: String] = LearnedTerms.load()
    @State private var newHeard = ""
    @State private var newReplacement = ""

    var body: some View {
        Section("Your vocabulary") {
            if terms.isEmpty {
                Text("Accept a name suggestion in a note and it is remembered here.")
                    .font(KlinoteFont.caption())
                    .foregroundStyle(KlinoteColor.secondary)
            } else {
                ForEach(terms.sorted(by: { $0.key < $1.key }), id: \.key) { heard, replacement in
                    HStack {
                        Text("\(heard) → \(replacement)")
                            .font(KlinoteFont.data())
                        Spacer()
                        Button("Forget") {
                            LearnedTerms.forget(heard)
                            terms = LearnedTerms.load()
                        }
                        .controlSize(.small)
                    }
                }
            }

            HStack(spacing: KlinoteMetrics.space8) {
                TextField("heard", text: $newHeard)
                Text("→")
                TextField("use instead", text: $newReplacement)
                Button("Add") {
                    LearnedTerms.learn(heard: newHeard, replacement: newReplacement)
                    newHeard = ""
                    newReplacement = ""
                    terms = LearnedTerms.load()
                }
                .disabled(newHeard.isEmpty || newReplacement.isEmpty)
            }
        }
    }
}

private struct AboutSettings: View {
    var body: some View {
        VStack(spacing: KlinoteMetrics.space12) {
            BrandMark(size: 28)
            Text("The session stays in the room. The note still gets written.")
                .foregroundStyle(KlinoteColor.secondary)
            Text(AppVersion.display)
                .font(.system(size: KlinoteMetrics.iconSmall))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.top, KlinoteMetrics.space32)
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
