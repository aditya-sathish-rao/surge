import SurgeCore
import SurgeUI
import SwiftUI

/// The Billing section of Settings: which Claude plan reports a window, and the explicit bindings
/// that settle a model two accounts could pay for.
struct BillingSettingsSection: View {
    @Bindable var settings: SurgeSettings

    @State private var newHarness: HarnessIdentity.Kind = .claudeCode
    @State private var newPrefix = ""
    @State private var newAccountID = "anthropic"

    var body: some View {
        Section("Accounts and billing") {
            LabeledContent("Claude billing") {
                Picker("Claude billing", selection: claudePlan) {
                    Text("API account").tag("")
                    ForEach(QuotaWindow.Preset.allCases, id: \.self) { preset in
                        Text(preset.name).tag(preset.rawValue)
                    }
                }
                .labelsHidden()
                .frame(minWidth: 180)
            }
            if settings.quotaWindow(forAccount: "anthropic") != nil {
                LabeledContent("Window length") {
                    HStack(spacing: SurgeSpacing.space2) {
                        TextField("Hours", value: windowHours, format: .number)
                            .labelsHidden()
                            .frame(width: 64)
                            .multilineTextAlignment(.trailing)
                        Text("hours")
                            .font(SurgeTypography.meta)
                            .foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Window budget") {
                    TextField("Amount", value: windowBudget, format: .currency(code: "USD"))
                        .labelsHidden()
                        .frame(width: 96)
                        .multilineTextAlignment(.trailing)
                }
                caption(
                    "A plan reports no dollar balance. Surge shows burn and headroom against this "
                        + "budget for one window, so the row never reads as an unavailable balance."
                )
            }
            ForEach(settings.bindings) { binding in
                LabeledContent("\(binding.harness.name) · \(binding.modelPrefix)") {
                    HStack(spacing: SurgeSpacing.space2) {
                        Text(accountName(for: binding.accountID))
                            .font(SurgeTypography.meta)
                            .foregroundStyle(.secondary)
                        Button("Remove") { settings.removeBinding(id: binding.id) }
                    }
                }
            }
            bindingEditor
            caption(
                "A binding wins over the model match. Otherwise exactly one account must match the "
                    + "model id; when two do, Surge shows the harness's own figure and names no account."
            )
        }
    }

    private var bindingEditor: some View {
        LabeledContent("Bind a model") {
            HStack(spacing: SurgeSpacing.space1) {
                Picker("Harness", selection: $newHarness) {
                    ForEach(HarnessIdentity.Kind.allCases, id: \.self) { kind in
                        Text(kind.name).tag(kind)
                    }
                }
                .labelsHidden()
                .frame(width: 120)
                TextField("Model prefix", text: $newPrefix)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 130)
                Picker("Account", selection: $newAccountID) {
                    ForEach(billingAccounts) { account in
                        Text(accountLabel(account)).tag(account.id)
                    }
                }
                .labelsHidden()
                .frame(width: 130)
                Button("Add") {
                    settings.addBinding(
                        harness: newHarness,
                        modelPrefix: newPrefix,
                        accountID: newAccountID
                    )
                    newPrefix = ""
                }
                .disabled(newPrefix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var billingAccounts: [BillingAccount] {
        settings.billingConfiguration().accounts
    }

    private func accountLabel(_ account: BillingAccount) -> String {
        account.id == "anthropic-api" ? "\(account.name) API" : account.name
    }

    private func accountName(for id: String) -> String {
        billingAccounts.first { $0.id == id }.map(accountLabel) ?? id
    }

    private var claudePlan: Binding<String> {
        Binding(
            get: { settings.quotaWindow(forAccount: "anthropic")?.preset.rawValue ?? "" },
            set: { raw in
                guard let preset = QuotaWindow.Preset(rawValue: raw) else {
                    settings.setQuotaWindow(nil, forAccount: "anthropic")
                    return
                }
                let existing = settings.quotaWindow(forAccount: "anthropic")
                settings.setQuotaWindow(
                    QuotaWindow(
                        preset: preset,
                        style: existing?.style ?? .rolling,
                        interval: existing?.interval,
                        limitUSD: existing?.limitUSD
                    ),
                    forAccount: "anthropic"
                )
            }
        )
    }

    private var windowHours: Binding<Double> {
        Binding(
            get: { (settings.quotaWindow(forAccount: "anthropic")?.interval ?? 18_000) / 3600 },
            set: { hours in
                guard let window = settings.quotaWindow(forAccount: "anthropic") else { return }
                settings.setQuotaWindow(
                    QuotaWindow(
                        preset: window.preset,
                        style: window.style,
                        interval: max(hours, 0.02) * 3600,
                        limitUSD: window.limitUSD
                    ),
                    forAccount: "anthropic"
                )
            }
        )
    }

    private var windowBudget: Binding<Double> {
        Binding(
            get: { settings.quotaWindow(forAccount: "anthropic")?.limitUSD ?? 20 },
            set: { budget in
                guard let window = settings.quotaWindow(forAccount: "anthropic") else { return }
                settings.setQuotaWindow(
                    QuotaWindow(
                        preset: window.preset,
                        style: window.style,
                        interval: window.interval,
                        limitUSD: max(budget, 0)
                    ),
                    forAccount: "anthropic"
                )
            }
        )
    }

    /// Settings is a system form, so its captions take the system secondary colour.
    private func caption(_ text: String) -> some View {
        Text(text)
            .font(SurgeTypography.meta)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
