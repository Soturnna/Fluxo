import SwiftUI

/// Ajustes e segurança.
///
/// Regra central desta tela: LIGAR uma proteção é livre, mas DESLIGAR ou
/// AFROUXAR qualquer uma exige Face ID. Assim, alguém com o seu iPhone
/// desbloqueado na mão não consegue desativar a segurança do Fluxo.
struct SettingsView: View {
    @EnvironmentObject private var lock: AppLock

    @AppStorage(SettingsKey.requireAuth) private var requireAuth = true
    @AppStorage(SettingsKey.lockDelay) private var lockDelay = LockDelay.immediately.rawValue
    @AppStorage(SettingsKey.hideValuesOnOpen) private var hideValuesOnOpen = false
    @AppStorage(SettingsKey.shieldInSwitcher) private var shieldInSwitcher = true
    @AppStorage(SettingsKey.anonymizeNames) private var anonymizeNames = true

    @State private var pluggyConfigured = false
    @State private var geminiConfigured = false
    @State private var confirmWipe = false

    var body: some View {
        NavigationStack {
            List {
                securitySection
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
                        lock.lockNow()
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
                rowLabel("Exigir \(lock.biometryName) para abrir", icon: lock.biometryIcon)
            }
            Picker(selection: lockDelayBinding) {
                ForEach(LockDelay.allCases) { option in
                    Text(option.label).tag(option.rawValue)
                }
            } label: {
                rowLabel("Bloquear ao sair", icon: "lock")
            }
            .disabled(!requireAuth)
            Toggle(isOn: $hideValuesOnOpen) {
                rowLabel("Abrir com valores ocultos", icon: "eye.slash")
            }
            Toggle(isOn: loosening($shieldInSwitcher, reason: "Mostrar o Fluxo no alternador de apps")) {
                rowLabel("Esconder no alternador de apps", icon: "rectangle.on.rectangle")
            }
        } header: {
            Text("Segurança")
        } footer: {
            Text("Se o \(lock.biometryName) falhar, o iPhone pede o seu código. Para desligar ou afrouxar uma proteção, o app confirma sua identidade antes.")
        }
    }

    private var agentSection: some View {
        Section {
            Toggle(isOn: loosening($anonymizeNames, reason: "Enviar nomes de pessoas para a IA")) {
                rowLabel(
                    "Trocar nomes de pessoas",
                    detail: "Pix vão para a IA como “Pessoa 1”",
                    icon: "person.crop.circle.badge.questionmark",
                    tile: Theme.lime,
                    glyph: Theme.ink
                )
            }
            LabeledContent {
                Text("Google Gemini")
            } label: {
                rowLabel("Provedor de IA", icon: "sparkles", tile: Theme.lime, glyph: Theme.ink)
            }
        } header: {
            Text("Privacidade do agente")
        } footer: {
            Text("O agente terá só ferramentas de leitura: não paga, não transfere e não altera nada no banco. CPF, contas e agências nunca são enviados à IA.")
        }
    }

    private var credentialsSection: some View {
        Section {
            NavigationLink {
                CredentialsView(kind: .pluggy)
            } label: {
                credentialRow("Pluggy", configured: pluggyConfigured)
            }
            NavigationLink {
                CredentialsView(kind: .gemini)
            } label: {
                credentialRow("Chave do Gemini", configured: geminiConfigured)
            }
        } header: {
            Text("Credenciais")
        } footer: {
            Text("As chaves ficam no Keychain, presas a este iPhone. Nunca entram no código do app nem no GitHub.")
        }
    }

    private var dataSection: some View {
        Section {
            Button(role: .destructive) {
                confirmWipe = true
            } label: {
                rowLabel("Apagar todos os dados", icon: "trash", tile: Theme.dangerSoft, glyph: Theme.danger)
                    .foregroundStyle(Theme.danger)
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
    }

    private var versionLabel: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Fluxo \(version) (build \(build))"
    }

    private func rowLabel(
        _ title: String,
        detail: String? = nil,
        icon: String,
        tile: Color = Theme.forest,
        glyph: Color = Theme.lime
    ) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
        } icon: {
            IconTile(systemName: icon, background: tile, foreground: glyph)
        }
    }

    private func credentialRow(_ title: String, configured: Bool) -> some View {
        LabeledContent {
            Label(
                configured ? "No Keychain" : "Não configurado",
                systemImage: configured ? "lock.fill" : "exclamationmark.circle"
            )
            .font(.subheadline)
            .foregroundStyle(configured ? Theme.inkSecondary : Theme.warning)
        } label: {
            rowLabel(title, icon: "key", tile: Theme.track, glyph: Theme.ink)
        }
    }
}
