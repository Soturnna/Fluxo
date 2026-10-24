import SwiftUI

/// Ajustes e segurança.
///
/// Regra central desta tela: LIGAR uma proteção é livre, mas DESLIGAR ou
/// AFROUXAR qualquer uma exige Face ID. Assim, alguém com o seu iPhone
/// desbloqueado na mão não consegue desativar a segurança do Fluxo.
struct SettingsView: View {
    @EnvironmentObject private var lock: AppLock
    @Environment(\.dismiss) private var dismiss

    @AppStorage(SettingsKey.requireAuth) private var requireAuth = true
    @AppStorage(SettingsKey.lockDelay) private var lockDelay = LockDelay.immediately.rawValue
    @AppStorage(SettingsKey.hideValuesOnOpen) private var hideValuesOnOpen = false
    @AppStorage(SettingsKey.shieldInSwitcher) private var shieldInSwitcher = true
    @AppStorage(SettingsKey.anonymizeNames) private var anonymizeNames = true
    @AppStorage(SettingsKey.agentModel) private var agentModel = AgentModelChoice.automatic.rawValue
    @AppStorage(SettingsKey.notifyEnabled) private var notificationsOn = false

    @State private var pluggyConfigured = false
    @State private var geminiConfigured = false
    @State private var brapiConfigured = false
    @State private var confirmWipe = false

    var body: some View {
        NavigationStack {
            List {
                securitySection
                organizationSection
                agentSection
                credentialsSection
                dataSection
                Section {
                } footer: {
                    Text(versionLabel)
                        .frame(maxWidth: .infinity)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.ground.ignoresSafeArea())
            .navigationTitle("Ajustes")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("OK") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 84) }
            .onAppear(perform: refreshCredentialStatus)
            .confirmationDialog(
                "Apagar todos os dados do Fluxo?",
                isPresented: $confirmWipe,
                titleVisibility: .visible
            ) {
                Button("Apagar tudo", role: .destructive) {
                    Task { @MainActor in
                        guard await lock.authenticate(reason: "Apagar todos os dados do Fluxo") else { return }
                        DataWiper.wipeEverything()
                        lock.endSession()
                    }
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("As chaves do Pluggy e do Gemini e todas as preferências serão removidas deste iPhone. Não dá para desfazer.")
            }
        }
    }

    // MARK: Seções

    private var securitySection: some View {
        Section {
            Toggle(isOn: loosening($requireAuth, reason: "Desligar o bloqueio do Fluxo")) {
                SettingLabel(title: "Exigir \(lock.biometryName) para abrir", icon: lock.biometryIcon)
            }
            Picker(selection: lockDelayBinding) {
                ForEach(LockDelay.allCases) { option in
                    Text(option.label).tag(option.rawValue)
                }
            } label: {
                SettingLabel(title: "Bloquear ao sair", icon: "lock")
            }
            .disabled(!requireAuth)
            Toggle(isOn: $hideValuesOnOpen) {
                SettingLabel(title: "Abrir com valores ocultos", icon: "eye.slash")
            }
            Toggle(isOn: loosening($shieldInSwitcher, reason: "Mostrar o Fluxo no alternador de apps")) {
                SettingLabel(title: "Esconder no alternador", icon: "rectangle.on.rectangle")
            }
        } header: {
            Text("Segurança")
        } footer: {
            Text("Se o \(lock.biometryName) falhar, o iPhone pede o seu código. Para desligar ou afrouxar uma proteção, o app confirma sua identidade antes.")
        }
    }

    private var organizationSection: some View {
        Section {
            NavigationLink {
                CategoriesView()
            } label: {
                SettingLabel(title: "Categorias", detail: "Criar, renomear e trocar ícones", icon: "square.grid.2x2", style: .neutral)
            }
            NavigationLink {
                ApplePaySetupView()
            } label: {
                SettingLabel(title: "Compras do Apple Pay", detail: "Registrar na hora, pelo app Atalhos", icon: "wave.3.right", style: .neutral)
            }
            NavigationLink {
                NotificationsView()
            } label: {
                SettingLabel(
                    title: "Notificações",
                    detail: notificationsOn ? "Ligadas" : "Orçamentos, previstos, gasto alto e resumo",
                    icon: "bell",
                    style: .neutral
                )
            }
        } header: {
            Text("Organização")
        }
    }

    private var agentSection: some View {
        Section {
            Toggle(isOn: loosening($anonymizeNames, reason: "Enviar nomes de pessoas para a IA")) {
                SettingLabel(
                    title: "Trocar nomes de pessoas",
                    detail: "Pix vão para a IA como “Pessoa 1”",
                    icon: "person.crop.circle.badge.questionmark",
                    style: .agent
                )
            }
            NavigationLink {
                AuditLogView()
            } label: {
                SettingLabel(title: "Registro do que foi enviado", icon: "doc.text.magnifyingglass", style: .agent)
            }
            Picker(selection: $agentModel) {
                ForEach(AgentModelChoice.allCases) { option in
                    Text(option.label).tag(option.rawValue)
                }
            } label: {
                SettingLabel(title: "Modelo de IA", icon: "sparkles", style: .agent)
            }
        } header: {
            Text("Privacidade do agente")
        } footer: {
            Text("O agente não paga, não transfere e não acessa o banco. Ele só organiza dados do app, e cada mudança precisa da sua confirmação. CPF, contas e agências nunca são enviados à IA.\n\nNo modo Automático, o app tenta do modelo mais capaz ao mais leve. A troca de modelo vale a partir da próxima conversa.")
        }
    }

    private var credentialsSection: some View {
        Section {
            NavigationLink {
                ConnectionsView()
            } label: {
                SettingLabel(title: "Conexões Open Finance", icon: "building.columns", style: .neutral)
            }
            NavigationLink {
                CredentialsView(kind: .pluggy)
            } label: {
                credentialRow("Credenciais do Pluggy", configured: pluggyConfigured)
            }
            NavigationLink {
                CredentialsView(kind: .gemini)
            } label: {
                credentialRow("Chave do Gemini", configured: geminiConfigured)
            }
            NavigationLink {
                CredentialsView(kind: .brapi)
            } label: {
                credentialRow("Chave do brapi (cotações)", configured: brapiConfigured)
            }
        } header: {
            Text("Conexões e chaves")
        } footer: {
            Text("As chaves ficam no Keychain, presas a este iPhone. Nunca entram no código do app nem no GitHub.")
        }
    }

    private var dataSection: some View {
        Section {
            Button(role: .destructive) {
                confirmWipe = true
            } label: {
                SettingLabel(title: "Apagar todos os dados", icon: "trash", style: .danger)
            }
        } header: {
            Text("Dados")
        } footer: {
            Text("Tudo o que o Fluxo guarda fica só neste iPhone.")
        }
    }

    // MARK: Regras de segurança dos controles

    /// Envolve um Toggle de proteção: ligar é imediato; desligar pede Face ID.
    private func loosening(_ setting: Binding<Bool>, reason: String) -> Binding<Bool> {
        Binding(
            get: { setting.wrappedValue },
            set: { newValue in
                if newValue {
                    setting.wrappedValue = true
                } else {
                    Task { @MainActor in
                        if await lock.authenticate(reason: reason) {
                            setting.wrappedValue = false
                        }
                    }
                }
            }
        )
    }

    /// Diminuir o tempo até o bloqueio é livre; aumentar pede Face ID.
    private var lockDelayBinding: Binding<Int> {
        Binding(
            get: { lockDelay },
            set: { newValue in
                if newValue <= lockDelay {
                    lockDelay = newValue
                } else {
                    Task { @MainActor in
                        if await lock.authenticate(reason: "Aumentar o tempo até o bloqueio") {
                            lockDelay = newValue
                        }
                    }
                }
            }
        )
    }

    // MARK: Apoio

    private func refreshCredentialStatus() {
        pluggyConfigured = CredentialKind.pluggy.keys.allSatisfy { KeychainStore.exists($0) }
        geminiConfigured = CredentialKind.gemini.keys.allSatisfy { KeychainStore.exists($0) }
        brapiConfigured = CredentialKind.brapi.keys.allSatisfy { KeychainStore.exists($0) }
    }

    private var versionLabel: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Fluxo \(version) (build \(build))"
    }

    private func credentialRow(_ title: String, configured: Bool) -> some View {
        HStack(spacing: 8) {
            SettingLabel(title: title, icon: "key", style: .neutral)
            Spacer(minLength: 8)
            if configured {
                StatusBadge(text: "No Keychain", icon: "lock.fill")
            } else {
                StatusBadge(text: "Pendente", icon: "exclamationmark.circle", color: Theme.warning)
            }
        }
    }
}
