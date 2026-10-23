import SwiftUI

enum CredentialKind {
    case pluggy, gemini

    var title: String {
        switch self {
        case .pluggy: return "Pluggy"
        case .gemini: return "Chave do Gemini"
        }
    }

    /// Itens do Keychain que, juntos, formam esta credencial.
    var keys: [KeychainKey] {
        switch self {
        case .pluggy: return [.pluggyClientId, .pluggyClientSecret, .pluggyItemIds]
        case .gemini: return [.geminiApiKey]
        }
    }
}

/// Cadastro de credenciais.
///
/// Três regras de segurança:
/// 1. Os campos são "só escrita": o valor guardado nunca volta para a tela.
/// 2. Salvar ou remover exige Face ID.
/// 3. Ao sair da tela, o que foi digitado é apagado da memória.
struct CredentialsView: View {
    let kind: CredentialKind
    @EnvironmentObject private var lock: AppLock

    @State private var clientId = ""
    @State private var clientSecret = ""
    @State private var itemIdsText = ""
    @State private var apiKey = ""
    @State private var configured = false
    @State private var feedback: Feedback?

    private struct Feedback {
        let text: String
        let isError: Bool
    }

    var body: some View {
        Form {
            Section {
                Label(
                    configured ? "Guardada no Keychain" : "Nenhuma credencial guardada",
                    systemImage: configured ? "lock.fill" : "lock.open"
                )
                .foregroundStyle(configured ? Theme.positive : Theme.warning)
            } footer: {
                Text("Por segurança, os valores guardados nunca são exibidos. Para trocar, digite os novos e salve.")
            }

            fields

            Section {
                Button {
                    Task { await save() }
                } label: {
                    Text("Salvar no Keychain")
                        .frame(maxWidth: .infinity)
                }
                .disabled(!canSave || lock.isAuthenticating)

                if configured {
                    Button(role: .destructive) {
                        Task { await remove() }
                    } label: {
                        Text("Remover do Keychain")
                            .frame(maxWidth: .infinity)
                    }
                }
            } footer: {
                if let feedback {
                    Label(feedback.text, systemImage: feedback.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(feedback.isError ? Theme.danger : Theme.positive)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.ground.ignoresSafeArea())
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 84) }
        .onAppear {
            configured = kind.keys.allSatisfy { KeychainStore.exists($0) }
        }
        .onDisappear(perform: clearFields)
    }

    @ViewBuilder
    private var fields: some View {
        switch kind {
        case .pluggy:
            Section {
                SecureField("Client ID", text: $clientId)
                SecureField("Client Secret", text: $clientSecret)
                TextField("IDs das conexões, separados por vírgula", text: $itemIdsText, axis: .vertical)
                    .font(.callout.monospaced())
            } header: {
                Text("Dashboard Pluggy")
            } footer: {
                Text("Crie as credenciais em dashboard.pluggy.ai, na aplicação ligada ao Meu Pluggy. Cada banco conectado tem um ID de conexão (item ID), no formato 8-4-4-4-12.")
            }
        case .gemini:
            Section {
                SecureField("Chave da API", text: $apiKey)
            } header: {
                Text("Google AI Studio")
            } footer: {
                Text("Crie a chave em aistudio.google.com. Ela só será usada quando o agente for ativado.")
            }
        }
    }

    // MARK: Validação

    private func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Separa os IDs digitados e mantém só os que têm formato de UUID válido.
    private var itemIdTokens: [String] {
        itemIdsText
            .split(whereSeparator: { $0 == "," || $0 == ";" || $0.isWhitespace })
            .map(String.init)
    }

    private var validItemIds: [String] {
        itemIdTokens.filter { UUID(uuidString: $0) != nil }
    }

    private var canSave: Bool {
        switch kind {
        case .pluggy:
            return !trimmed(clientId).isEmpty
                && !trimmed(clientSecret).isEmpty
                && !validItemIds.isEmpty
        case .gemini:
            return !trimmed(apiKey).isEmpty
        }
    }

    // MARK: Ações

    @MainActor
    private func save() async {
        if kind == .pluggy, validItemIds.count != itemIdTokens.count {
            feedback = Feedback(text: "Algum ID de conexão não está no formato correto.", isError: true)
            return
        }
        guard await lock.authenticate(reason: "Salvar credenciais no Keychain") else { return }

        do {
            switch kind {
            case .pluggy:
                try KeychainStore.save(trimmed(clientId), for: .pluggyClientId)
                try KeychainStore.save(trimmed(clientSecret), for: .pluggyClientSecret)
                try KeychainStore.save(validItemIds.joined(separator: ","), for: .pluggyItemIds)
            case .gemini:
                try KeychainStore.save(trimmed(apiKey), for: .geminiApiKey)
            }
            clearFields()
            configured = true
            feedback = Feedback(text: "Salvo no Keychain.", isError: false)
        } catch {
            feedback = Feedback(text: "Não foi possível salvar: \(error.localizedDescription)", isError: true)
        }
    }

    @MainActor
    private func remove() async {
        guard await lock.authenticate(reason: "Remover credenciais do Keychain") else { return }
        kind.keys.forEach { KeychainStore.delete($0) }
        configured = false
        feedback = Feedback(text: "Removido do Keychain.", isError: false)
    }

    private func clearFields() {
        clientId = ""
        clientSecret = ""
        itemIdsText = ""
        apiKey = ""
    }
}
