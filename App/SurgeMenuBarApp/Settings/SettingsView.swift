import SurgeCore
import SurgeStateStore
import SurgeUI
import SwiftUI

/// The standard settings window: shortcut, stall thresholds, notification opt-ins and balances.
struct SettingsView: View {
    @Bindable private var settings: SurgeSettings
    @State private var capture = ShortcutCapture()

    init(model: AppModel) {
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
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 640)
        .onChange(of: capture.captured) { _, shortcut in
            guard let shortcut else { return }
            settings.shortcut = shortcut
            capture.reset()
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
