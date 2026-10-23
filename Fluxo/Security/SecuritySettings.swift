import Foundation

/// Nomes das preferências salvas no UserDefaults.
/// Aqui ficam só escolhas de comportamento, nunca segredos.
enum SettingsKey {
    static let requireAuth = "security.requireAuth"
    static let lockDelay = "security.lockDelaySeconds"
    static let hideValuesOnOpen = "security.hideValuesOnOpen"
    static let shieldInSwitcher = "security.shieldInSwitcher"
    static let anonymizeNames = "agent.anonymizeNames"
    static let agentModel = "agent.model"
    // Notificações (só escolhas; nenhum dado financeiro fica no UserDefaults).
    static let notifyEnabled = "notify.enabled"
    static let notifyBudgets = "notify.budgets"
    static let notifyPlanned = "notify.planned"
    static let notifyLarge = "notify.largeExpense"
    static let notifyLargeThreshold = "notify.largeExpenseThreshold"
    static let notifyWeekly = "notify.weekly"
    static let notifyConnection = "notify.connection"
    static let notifyShowValues = "notify.showValues"
    static let profileName = "profile.name"
    static let hasLaunchedBefore = "app.hasLaunchedBefore"
}

/// Tempo que o app pode ficar em segundo plano antes de bloquear.
enum LockDelay: Int, CaseIterable, Identifiable {
    case immediately = 0
    case oneMinute = 60
    case fiveMinutes = 300

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .immediately: return "Imediatamente"
        case .oneMinute: return "Após 1 minuto"
        case .fiveMinutes: return "Após 5 minutos"
        }
    }
}

enum SettingsDefaults {
    /// Valores de fábrica: tudo começa no modo mais protegido.
    static func register() {
        UserDefaults.standard.register(defaults: [
            SettingsKey.requireAuth: true,
            SettingsKey.lockDelay: LockDelay.immediately.rawValue,
            SettingsKey.hideValuesOnOpen: false,
            SettingsKey.shieldInSwitcher: true,
            SettingsKey.anonymizeNames: true,
            SettingsKey.agentModel: AgentModelChoice.automatic.rawValue,
            SettingsKey.notifyEnabled: false,          // só liga depois da permissão do iOS
            SettingsKey.notifyBudgets: true,
            SettingsKey.notifyPlanned: true,
            SettingsKey.notifyLarge: true,
            SettingsKey.notifyLargeThreshold: 200.0,
            SettingsKey.notifyWeekly: true,
            SettingsKey.notifyConnection: true,
            SettingsKey.notifyShowValues: true,        // escolha sua: valores visíveis
            SettingsKey.profileName: "Marcos"
        ])
    }
}

enum FirstLaunch {
    /// O Keychain sobrevive à desinstalação do app; o UserDefaults, não.
    /// Se o app foi apagado e instalado de novo, credenciais antigas podem ter
    /// ficado para trás. Na primeira abertura, elas são removidas.
    static func purgeLeftoverSecretsIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: SettingsKey.hasLaunchedBefore) else { return }
        KeychainStore.deleteAll()
        defaults.set(true, forKey: SettingsKey.hasLaunchedBefore)
    }
}

enum DataWiper {
    /// Apaga o cofre local, as credenciais e as preferências.
    static func wipeEverything() {
        NotificationCleanup.removeAll()
        ProvisionalInbox.removeAll()
        Vault.destroy()
        KeychainStore.deleteAll()
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
        UserDefaults.standard.set(true, forKey: SettingsKey.hasLaunchedBefore)
    }
}
