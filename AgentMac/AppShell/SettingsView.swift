import ComposableArchitecture
import Perception
import SwiftUI

/// Settings 视图。
struct SettingsView: View {
    /// Settings 页面 store。
    @Perception.Bindable var store: StoreOf<SettingsFeature>

    /// 当前展示中的 API Key 表单副本，避免 SwiftUI sheet 的 escaping binding 直接读取 Perception state。
    @State private var presentedAPIKeyForm: ProviderAPIKeyForm?

    /// 页面内容。
    var body: some View {
        WithPerceptionTracking {
            let apiKeyForm = store.apiKeyForm

            VStack(alignment: .leading, spacing: 0) {
                header
                Divider()
                content
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .task {
                store.send(.task)
            }
            .onAppear {
                presentedAPIKeyForm = apiKeyForm
            }
            .onChange(of: apiKeyForm) { form in
                presentedAPIKeyForm = form
            }
            .sheet(item: presentedAPIKeyFormBinding) { form in
                WithPerceptionTracking {
                    ProviderAPIKeySheet(
                        form: form,
                        apiKey: $store.apiKeyInput.sending(\.apiKeyInputChanged),
                        isSaving: store.isSavingAPIKey,
                        canSave: store.canSaveAPIKey,
                        onSave: {
                            store.send(.saveAPIKeyButtonTapped)
                        },
                        onCancel: {
                            store.send(.apiKeyFormDismissed)
                        }
                    )
                }
            }
        }
    }

    private var presentedAPIKeyFormBinding: Binding<ProviderAPIKeyForm?> {
        Binding(
            get: {
                presentedAPIKeyForm
            },
            set: { newValue in
                if newValue == nil {
                    store.send(.apiKeyFormDismissed)
                }
                presentedAPIKeyForm = newValue
            }
        )
    }

    private var header: some View {
        WithPerceptionTracking {
            HStack(alignment: .center, spacing: 12) {
                Text("提供商")
                    .font(.title2.weight(.semibold))

                Spacer()

                Button {
                    store.send(.refreshButtonTapped)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(store.hasOperationInFlight)
                .help("Refresh")
            }
            .padding(16)
        }
    }

    private var content: some View {
        WithPerceptionTracking {
            VStack(alignment: .leading, spacing: 16) {
                if let errorMessage = store.errorMessage {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }

                if let successMessage = store.successMessage {
                    Text(successMessage)
                        .font(.callout)
                        .foregroundStyle(.green)
                        .textSelection(.enabled)
                }

                if store.isLoading || store.isLoadingCredentials {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            providerSection(
                                title: "API Key 授权",
                                providers: ModelProviderCatalog.apiKeyProviders,
                                actionStyle: .apiKey
                            )

                            providerSection(
                                title: "OAuth / 订阅授权",
                                providers: ModelProviderCatalog.oauthProviders,
                                actionStyle: .oauthPreview
                            )
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(16)
        }
    }

    private func providerSection(
        title: String,
        providers: [ModelProviderDefinition],
        actionStyle: ProviderRowActionStyle
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.headline)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                ForEach(Array(providers.enumerated()), id: \.element.id) { index, provider in
                    WithPerceptionTracking {
                        ProviderRow(
                            provider: provider,
                            status: credentialStatus(for: provider.id),
                            actionStyle: actionStyle,
                            isOperationInFlight: store.hasOperationInFlight,
                            onConnect: {
                                store.send(.connectProviderButtonTapped(provider.id))
                            },
                            onDisconnect: {
                                store.send(.disconnectProviderButtonTapped(provider.id))
                            }
                        )

                        if index < providers.count - 1 {
                            Divider()
                                .padding(.leading, 56)
                        }
                    }
                }
            }
        }
    }

    private func credentialStatus(for providerID: String) -> ProviderCredentialStatus {
        store.credentialStatuses.first { $0.providerID == providerID }
            ?? ProviderCredentialStatus(providerID: providerID, hasAPIKey: false, hasOAuth: false)
    }
}

private enum ProviderRowActionStyle {
    case apiKey
    case oauthPreview
}

private struct ProviderRow: View {
    let provider: ModelProviderDefinition
    let status: ProviderCredentialStatus
    let actionStyle: ProviderRowActionStyle
    let isOperationInFlight: Bool
    let onConnect: () -> Void
    let onDisconnect: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            ProviderMark(provider: provider)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(provider.name)
                        .font(.title3.weight(.semibold))

                    if status.isConnected {
                        Text(status.hasAPIKey ? "API Key" : "OAuth")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.green.opacity(0.14))
                            .foregroundStyle(.green)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }

                Text(provider.subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 16)

            actionButton
        }
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var actionButton: some View {
        switch actionStyle {
        case .apiKey:
            if status.hasAPIKey {
                Button(role: .destructive) {
                    onDisconnect()
                } label: {
                    Label("断开", systemImage: "xmark")
                }
                .disabled(isOperationInFlight)
            } else {
                Button {
                    onConnect()
                } label: {
                    Label("连接", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(isOperationInFlight)
            }

        case .oauthPreview:
            Button {
            } label: {
                Label(status.hasOAuth ? "已连接" : "稍后支持", systemImage: status.hasOAuth ? "checkmark" : "clock")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(true)
        }
    }
}

private struct ProviderMark: View {
    let provider: ModelProviderDefinition

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.12))
                .frame(width: 40, height: 40)

            Text(initials)
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)
        }
        .accessibilityHidden(true)
    }

    private var initials: String {
        let words = provider.name
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
        let value = words.map(String.init).joined().uppercased()
        return value.isEmpty ? String(provider.id.prefix(2)).uppercased() : value
    }
}

private struct ProviderAPIKeySheet: View {
    @Environment(\.dismiss) private var dismiss

    let form: ProviderAPIKeyForm
    @Binding var apiKey: String
    let isSaving: Bool
    let canSave: Bool
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(form.provider.name)
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 8) {
                Text("API Key")
                    .font(.headline)
                SecureField("API Key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isSaving)

                if let environmentVariable = form.provider.apiKeyEnvironmentVariable {
                    Text(environmentVariable)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            HStack {
                Spacer()

                Button("取消") {
                    onCancel()
                    dismiss()
                }
                .disabled(isSaving)

                Button(isSaving ? "保存中" : "保存") {
                    onSave()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
