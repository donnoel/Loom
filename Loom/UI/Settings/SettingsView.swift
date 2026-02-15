import SwiftUI
import AppKit
import AVFoundation

struct SettingsView: View {
    private let store: SessionStore
    @Environment(\.colorScheme) private var colorScheme

    @AppStorage(LoomPreferenceKeys.statusAutoRefreshEnabled)
    private var statusAutoRefreshEnabled: Bool = true

    @AppStorage(LoomPreferenceKeys.modelsAutoCheckEnabled)
    private var modelsAutoCheckEnabled: Bool = true

    @AppStorage(LoomPreferenceKeys.voiceReplyVoiceIdentifier)
    private var voiceReplyVoiceIdentifier: String = ""

    @AppStorage(LoomPreferenceKeys.voiceReplyRate)
    private var voiceReplyRate: Double = VoiceReplyPreferences.defaultRate

    @State private var previewSynthesizer = AVSpeechSynthesizer()
    @State private var isShowingDeleteAllConfirmation: Bool = false

    private var sessionsRootURL: URL? {
        try? LoomPaths.sessionsRoot()
    }

    init(store: SessionStore) {
        self.store = store
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                introCard
                automationCard
                voiceRepliesCard
                localDataCard
                dangerCard
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("screen.settings")
        .navigationTitle("Settings")
        .confirmationDialog(
            "Delete all sessions?",
            isPresented: $isShowingDeleteAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete All", role: .destructive) {
                deleteAllSessions()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes all local sessions and cannot be undone.")
        }
        .onDisappear {
            previewSynthesizer.stopSpeaking(at: .immediate)
        }
    }

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Settings")
                .font(LoomTheme.Typography.pageHero)

            Text("Control how Loom stays up to date and where your local session data is stored.")
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LoomTheme.accentGradient(for: colorScheme).opacity(colorScheme == .dark ? 0.28 : 0.16))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
        )
    }

    private var automationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Automation")
                .font(LoomTheme.Typography.sectionTitle)

            Toggle("Refresh status automatically", isOn: $statusAutoRefreshEnabled)
            Toggle("Check model availability automatically", isOn: $modelsAutoCheckEnabled)

            Text("Turn these off if you prefer manual refresh while troubleshooting.")
                .font(LoomTheme.Typography.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .loomCard(cornerRadius: 12)
    }

    private var localDataCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Local Data & Privacy")
                .font(LoomTheme.Typography.sectionTitle)

            VStack(alignment: .leading, spacing: 4) {
                Text("Sessions folder")
                    .font(LoomTheme.Typography.caption)
                    .foregroundStyle(.secondary)

                Text(sessionsRootURL?.path ?? "Unavailable")
                    .font(LoomTheme.Typography.monospacedFootnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Button("Open Sessions Folder") {
                guard let url = sessionsRootURL else { return }
                NSWorkspace.shared.open(url)
            }
            .buttonStyle(.bordered)
            .disabled(sessionsRootURL == nil)
            .accessibilityIdentifier("settings.openSessionsFolder")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .loomCard(cornerRadius: 12)
    }

    private var voiceRepliesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Voice Replies")
                .font(LoomTheme.Typography.sectionTitle)

            VStack(alignment: .leading, spacing: 6) {
                Text("Voice")
                    .font(LoomTheme.Typography.caption)
                    .foregroundStyle(.secondary)

                Picker("Voice", selection: selectedVoiceIdentifier) {
                    Text("System Default")
                        .tag("")
                    ForEach(availableVoices, id: \.identifier) { voice in
                        let languageName = localizedLanguageName(for: voice.language)
                        Text("\(voice.name) (\(languageName))")
                            .tag(voice.identifier)
                    }
                }
                .labelsHidden()
                .accessibilityIdentifier("settings.voicePicker")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Rate: \(normalizedVoiceReplyRate.wrappedValue, specifier: "%.2f")")
                    .font(LoomTheme.Typography.caption)
                    .foregroundStyle(.secondary)

                Slider(
                    value: normalizedVoiceReplyRate,
                    in: VoiceReplyPreferences.minRate...VoiceReplyPreferences.maxRate,
                    step: 0.01
                )
                .accessibilityIdentifier("settings.voiceRateSlider")
            }

            Button("Preview Voice") {
                previewVoice()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("settings.previewVoice")

            Text("Choose the voice and speed Loom uses when reading assistant replies aloud.")
                .font(LoomTheme.Typography.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .loomCard(cornerRadius: 12)
    }

    private var dangerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Danger Zone")
                .font(LoomTheme.Typography.sectionTitle)

            Text("Delete all sessions from this Mac. This cannot be undone.")
                .font(LoomTheme.Typography.body)
                .foregroundStyle(.secondary)

            Button("Delete All Sessions…", role: .destructive) {
                isShowingDeleteAllConfirmation = true
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("settings.deleteAllSessions")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .loomCard(cornerRadius: 12)
    }

    private var availableVoices: [AVSpeechSynthesisVoice] {
        var seenIdentifiers = Set<String>()
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { seenIdentifiers.insert($0.identifier).inserted }
            .sorted { lhs, rhs in
                let leftLanguage = localizedLanguageName(for: lhs.language)
                let rightLanguage = localizedLanguageName(for: rhs.language)
                if leftLanguage != rightLanguage {
                    return leftLanguage.localizedCaseInsensitiveCompare(rightLanguage) == .orderedAscending
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private var selectedVoiceIdentifier: Binding<String> {
        Binding(
            get: {
                guard let identifier = voiceReplyVoiceIdentifier.nonEmptyTrimmed else { return "" }
                return AVSpeechSynthesisVoice(identifier: identifier) == nil ? "" : identifier
            },
            set: { newIdentifier in
                voiceReplyVoiceIdentifier = newIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        )
    }

    private var normalizedVoiceReplyRate: Binding<Double> {
        Binding(
            get: {
                VoiceReplyPreferences.normalizedRate(voiceReplyRate)
            },
            set: { newRate in
                voiceReplyRate = VoiceReplyPreferences.normalizedRate(newRate)
            }
        )
    }

    private func localizedLanguageName(for identifier: String) -> String {
        Locale.current.localizedString(forIdentifier: identifier) ?? identifier
    }

    private func previewVoice() {
        let utterance = AVSpeechUtterance(string: VoiceReplyPreferences.previewText)
        utterance.rate = Float(VoiceReplyPreferences.normalizedRate(voiceReplyRate))

        if let identifier = voiceReplyVoiceIdentifier.nonEmptyTrimmed,
           let configuredVoice = AVSpeechSynthesisVoice(identifier: identifier) {
            utterance.voice = configuredVoice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.identifier)
        }

        previewSynthesizer.stopSpeaking(at: .immediate)
        previewSynthesizer.speak(utterance)
    }

    private func deleteAllSessions() {
        Task {
            try? await store.deleteAllSessions()
            NotificationCenter.default.post(name: .loomSessionsDidChange, object: nil)
        }
    }
}
