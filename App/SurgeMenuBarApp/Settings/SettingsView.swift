import SurgeCore
import SurgeStateStore
import SurgeUI
import SurgeWallets
import SwiftUI

/// The standard settings window: shortcut, stall thresholds, notifications, balances and keys.
struct SettingsView: View {
    @Bindable private var settings: SurgeSettings
    @State private var capture = ShortcutCapture()
    @State private var keyStates: [Provider: ProviderKeyState] = [:]
    @State private var drafts: [Provider: String] = [:]
    @State private var keyError: String?
    private let model: AppModel

    /// Only the providers whose keys Surge actually uses. Anthropic is read from local
    /// transcripts and exposes no balance endpoint, so it asks for no key.
    private static let keyProviders: [Provider] = [.deepseek, .openrouter]

    init(model: AppModel) {
        self.model = model
        _settings = Bindable(wrappedValue: model.settings)
    }

    private var modelNames: [String] {
        SurgeStateStore.defaultPricing.models.keys.sorted()
    }

    var body: some View {
        Form {
            Section("Keyboard") {
                LabeledContent("Toggle the panel") {
                    shortcutRecorder
                }
                caption("No shortcut is set by default. A global shortcut works while Surge runs.")
            }

            Section("Stall threshold") {
                ForEach(modelNames, id: \.self) { name in
                    stallRow(for: name)
                }
                caption("A change applies the next time Surge starts.")
            }

            Section("Notifications") {
                Toggle("Send stalls as Time Sensitive", isOn: $settings.notifyStallTimeSensitive)
                Toggle("Send completed sessions as Passive", isOn: $settings.notifyCompletionPassive)
                caption(
                    "Waiting for you always notifies. Stalls are Active unless you ask for Time Sensitive. "
                        + "Working, idle and compacting never notify."
                )
            }

            Section("Balances") {
                LabeledContent("Low below") {
                    currencyField($settings.lowBalanceThreshold)
                }
                LabeledContent("Empty below") {
                    currencyField($settings.emptyBalanceThreshold)
                }
                caption("Each account is measured on its own. Balances are never added together.")
            }

            Section("Provider keys") {
                ForEach(Self.keyProviders, id: \.self) { provider in
                    keyRow(for: provider)
                }
                if let keyError {
                    Text(keyError)
                        .font(SurgeTypography.meta)
                        .foregroundStyle(SurgeColors.alert)
                        .fixedSize(horizontal: false, vertical: true)
                }
                caption(
                    "Keys go to the macOS Keychain and nowhere else. They are used for balances "
                        + "and model metadata, and are never written to a file, a preference, or "
                        + "the widget snapshot."
                )
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 760)
        .task { refreshKeyStates() }
        .onChange(of: capture.captured) { _, shortcut in
            guard let shortcut else { return }
            settings.shortcut = shortcut
            capture.reset()
        }
    }

    private func keyRow(for provider: Provider) -> some View {
        VStack(alignment: .leading, spacing: SurgeSpacing.space1) {
            LabeledContent(provider.name) {
                HStack(spacing: SurgeSpacing.space2) {
                    SecureField("Paste a key", text: draftBinding(for: provider))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 220)
                        .accessibilityLabel("\(provider.name) API key")
                        .onSubmit { save(provider) }
                    Button("Save") { save(provider) }
                        .disabled(draft(for: provider).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Remove") { remove(provider) }
                        .disabled(keyStates[provider] != .configured)
                }
            }
            caption(keyStatusText(for: provider))
        }
    }

    private func keyStatusText(for provider: Provider) -> String {
        switch keyStates[provider] {
        case .configured: "Configured in the Keychain."
        case .notConfigured: "Not configured."
        case .unavailable: "The Keychain could not be read, so \(provider.name) is unavailable."
        case nil: "Checking the Keychain…"
        }
    }

    private func draft(for provider: Provider) -> String {
        drafts[provider] ?? ""
    }

    private func draftBinding(for provider: Provider) -> Binding<String> {
        Binding(
            get: { drafts[provider] ?? "" },
            set: { drafts[provider] = $0 }
        )
    }

    /// Keychain work runs off the main actor, so opening Settings or saving a key never stalls
    /// the window or the poll loop.
    private func refreshKeyStates() {
        let keys = model.keys
        let providers = Self.keyProviders
        Task {
            let states = await Task.detached { () -> [Provider: ProviderKeyState] in
                var states: [Provider: ProviderKeyState] = [:]
                for provider in providers {
                    states[provider] = keys.keyState(for: provider)
                }
                return states
            }.value
            keyStates = states
        }
    }

    private func save(_ provider: Provider) {
        let key = draft(for: provider)
        let keys = model.keys
        Task {
            let failure = await Task.detached { () -> Bool in
                do {
                    try keys.saveKey(key, for: provider)
                    return false
                } catch {
                    return true
                }
            }.value
            keyError = failure ? "The Keychain refused the key for \(provider.name). Nothing was saved." : nil
            if !failure { drafts[provider] = "" }
            refreshKeyStates()
            await model.refreshModelCatalog()
        }
    }

    private func remove(_ provider: Provider) {
        let keys = model.keys
        Task {
            let failure = await Task.detached { () -> Bool in
                do {
                    try keys.removeKey(for: provider)
                    return false
                } catch {
                    return true
                }
            }.value
            keyError = failure ? "The Keychain refused to remove the key for \(provider.name)." : nil
            refreshKeyStates()
        }
    }

    private var shortcutRecorder: some View {
        HStack(spacing: SurgeSpacing.space2) {
            Text(settings.shortcut?.displayName ?? "None")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(minWidth: 56, alignment: .leading)
            Button(capture.isRecording ? "Press keys…" : "Record") {
                if capture.isRecording {
                    capture.stop()
                } else {
                    capture.start()
                }
            }
            Button("Clear") {
                settings.shortcut = nil
            }
            .disabled(settings.shortcut == nil)
        }
    }

    private func stallRow(for modelName: String) -> some View {
        LabeledContent(AgentRowPresentation.displayName(forModel: modelName)) {
            HStack(spacing: SurgeSpacing.space2) {
                TextField("Seconds", value: threshold(for: modelName), format: .number)
                    .labelsHidden()
                    .frame(width: 72)
                    .multilineTextAlignment(.trailing)
                Text("seconds")
                    .font(SurgeTypography.meta)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                Button("Reset") {
                    settings.setStallThreshold(nil, for: modelName)
                }
                .disabled(settings.stallOverrides[modelName] == nil)
            }
        }
    }

    private func threshold(for modelName: String) -> Binding<Double> {
        Binding(
            get: { settings.stallThreshold(for: modelName) },
            set: { settings.setStallThreshold($0, for: modelName) }
        )
    }

    private func currencyField(_ binding: Binding<Double>) -> some View {
        TextField("Amount", value: binding, format: .currency(code: "USD"))
            .labelsHidden()
            .frame(width: 96)
            .multilineTextAlignment(.trailing)
    }

    /// Settings is a system form, so its captions take the system secondary colour. The dark-card
    /// ink tokens are invisible on a light form.
    private func caption(_ text: String) -> some View {
        Text(text)
            .font(SurgeTypography.meta)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
