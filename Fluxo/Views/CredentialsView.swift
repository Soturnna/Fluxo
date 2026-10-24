import SwiftUI

enum CredentialKind {
    case pluggy, gemini, brapi

    var title: String {
        switch self {
        case .pluggy: return "Pluggy"
        case .gemini: return "Chave do Gemini"
        case .brapi: return "Chave do brapi"
        }
    }

    /// Itens do Keychain que, juntos, formam esta credencial.
    var keys: [KeychainKey] {
        switch self {
        case .pluggy: return [.pluggyClientId, .pluggyClientSecret, .pluggyItemIds]
        case .gemini: return [.geminiApiKey]
        case .brapi: return [.brapiToken]
        }
    }
}

/// Cadastro de credenciais.
///
/// Três regras de segurança:
/// 1. Os campos são "só escrita": o valor guardado nunca volta para a tela.
/// 2. Salvar ou remover exige Face ID.
/// 3. Ao sair da tela (ou quando a sessão expira), o que foi digitado é apagado da memória.
struct CredentialsView: View {
    let kind: CredentialKind
    @EnvironmentObject private var lock: AppLock
    @EnvironmentObject private var connections: FinanceStore

    @State private var clientId = ""
    @State private var clientSecret = ""
    @State private var itemIdsText = ""
    @State private var apiKey = ""
    @State private var configured = false
    @State private var feedback: Feedback?
    @State private var checks: [ModelCheck] = []
    @State private var testing = false

    private struct Feedback {
        let text: String
        let isError: Bool
    }

    var body: some View {
        Form {
            Section {
                if configured {
                    StatusBadge(text: "Guardada no Keychain", icon: "lock.fill", color: Theme.positive)
                } else {
                    StatusBadge(text: "Nenhuma credencial guardada", icon: "lock.open", color: Theme.warning)
                }
            } footer: {
                Text("Por segurança, os valores guardados nunca são exibidos. Para trocar, digite os novos e salve.")
            }

            fields

            if kind == .gemini && configured {
                Section {
                    Button {
                        Task { await runChecks() }
                    } label: {
                        HStack {
                            Text("Testar modelos")
                            Spacer()
                            if testing { ProgressView() }
                        }
                    }
                    .disabled(testing)
                    ForEach(checks) { check in
                        HStack(spacing: 10) {
                            Image(systemName: check.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(check.ok ? Theme.positive : Theme.danger)
                            Text(GeminiClient.displayName(check.model))
                                .font(.subheadline.weight(.medium))
                            Spacer(minLength: 8)
                            Text(check.detail)
                                .font(.footnote)
                                .foregroundStyle(Theme.inkSecondary)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                } footer: {
                    Text("Testa cada modelo, um por vez, com a frase “Responda apenas: ok”. Nenhum dado seu sai do iPhone. Escolha o modelo em Ajustes › Modelo de IA.")
                }
            }

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
                // O Client ID identifica a aplicação, não é segredo: fica visível
                // para você conferir o que colou. O Secret, sim, fica oculto.
                TextField("Client ID", text: $clientId)
                    .font(.callout.monospaced())
                SecureField("Client Secret", text: $clientSecret)
                TextField("IDs das conexões, separados por vírgula", text: $itemIdsText, axis: .vertical)
                    .font(.callout.monospaced())
            } header: {
                Text("Dashboard Pluggy")
            } footer: {
                Text("Crie as credenciais em dashboard.pluggy.ai, na aplicação ligada ao Meu Pluggy. Cada banco conectado tem um ID de conexão (item ID), no formato 8-4-4-4-12.\n\nPode sair do app para copiar os dados: o que já foi digitado continua aqui por até 5 minutos.")
            }
        case .gemini:
            Section {
                SecureField("Chave da API", text: $apiKey)
            } header: {
                Text("Google AI Studio")
            } footer: {
                Text("Crie a chave em aistudio.google.com. Ela só será usada quando o agente for ativado.")
            }
        case .brapi:
            Section {
                SecureField("Token do brapi", text: $apiKey)
            } header: {
                Text("brapi.dev (cotações da B3)")
            } footer: {
                Text("Crie grátis em brapi.dev, no plano Free. O app só envia códigos de ativos (ex.: listas de mais negociados); nenhum dado seu sai do iPhone.")
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
        case .gemini, .brapi:
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
            case .brapi:
                try KeychainStore.save(trimmed(apiKey), for: .brapiToken)
            }
            clearFields()
            configured = true
            feedback = Feedback(text: "Salvo no Keychain.", isError: false)
            if kind == .pluggy { await connections.credentialsChanged() }
        } catch {
            feedback = Feedback(text: "Não foi possível salvar: \(error.localizedDescription)", isError: true)
        }
    }

    /// Um modelo por vez: cada linha aparece assim que o teste dela termina.
    @MainActor
    private func runChecks() async {
        testing = true
        checks = []
        let client = GeminiClient()
        for model in GeminiClient.allModels {
            checks.append(await client.check(model))
        }
        testing = false
    }

    @MainActor
    private func remove() async {
        guard await lock.authenticate(reason: "Remover credenciais do Keychain") else { return }
        kind.keys.forEach { KeychainStore.delete($0) }
        configured = false
        if kind == .pluggy { await connections.credentialsChanged() }
        feedback = Feedback(text: "Removido do Keychain.", isError: false)
    }

    private func clearFields() {
        clientId = ""
        clientSecret = ""
        itemIdsText = ""
        apiKey = ""
    }
}
