import SwiftUI
import LocalAuthentication

/// Controla o bloqueio do app e o botão de ocultar valores.
///
/// Regras:
/// 1. O app abre bloqueado (se a proteção estiver ligada).
/// 2. Ao ir para segundo plano, conta o tempo; ao voltar, bloqueia se passou do limite.
/// 3. Desbloquear exige Face ID, com o código do iPhone como alternativa.
@MainActor
final class AppLock: ObservableObject {
    @Published private(set) var isLocked: Bool
    @Published var valuesHidden: Bool
    @Published private(set) var errorMessage: String?
    @Published private(set) var isAuthenticating = false

    /// Nome e ícone da biometria do aparelho ("Face ID", "faceid").
    let biometryName: String
    let biometryIcon: String

    private let defaults = UserDefaults.standard
    /// Momento em que o app foi para segundo plano, num relógio monotônico.
    private var backgroundedAt: UInt64?

    init() {
        SettingsDefaults.register()
        isLocked = UserDefaults.standard.bool(forKey: SettingsKey.requireAuth)
        valuesHidden = UserDefaults.standard.bool(forKey: SettingsKey.hideValuesOnOpen)

        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID:
            biometryName = "Face ID"
            biometryIcon = "faceid"
        case .touchID:
            biometryName = "Touch ID"
            biometryIcon = "touchid"
        default:
            biometryName = "código"
            biometryIcon = "lock"
        }
    }

    // MARK: Autenticação

    /// Pede a identidade da pessoa. Devolve true só se ela foi confirmada.
    ///
    /// A política `.deviceOwnerAuthentication` usa o Face ID e, se ele falhar,
    /// oferece o código do iPhone. Quem decide é o iOS: o app nunca vê o rosto
    /// nem o código, só recebe "confirmado" ou "não confirmado".
    func authenticate(reason: String) async -> Bool {
        guard !isAuthenticating else { return false }
        isAuthenticating = true
        defer { isAuthenticating = false }

        let context = LAContext()
        context.localizedCancelTitle = "Cancelar"

        var policyError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) else {
            // Sem código definido no iPhone não há como proteger o app.
            errorMessage = "Defina um código no iPhone (Ajustes › Face ID e Código) para usar o Fluxo."
            return false
        }

        do {
            let confirmed = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            errorMessage = nil
            return confirmed
        } catch let error as LAError where [.userCancel, .appCancel, .systemCancel, .notInteractive].contains(error.code) {
            errorMessage = nil
            return false
        } catch {
            errorMessage = "Não foi possível confirmar sua identidade. Tente de novo."
            return false
        }
    }

    func unlock() async {
        guard isLocked else { return }
        if await authenticate(reason: "Desbloquear o Fluxo") {
            valuesHidden = defaults.bool(forKey: SettingsKey.hideValuesOnOpen)
            isLocked = false
        }
    }

    func lockNow() {
        if defaults.bool(forKey: SettingsKey.requireAuth) {
            isLocked = true
        }
    }

    // MARK: Ciclo de vida

    func handleScenePhase(_ phase: ScenePhase) {
        guard defaults.bool(forKey: SettingsKey.requireAuth) else {
            backgroundedAt = nil
            return
        }
        let delay = UInt64(max(0, defaults.integer(forKey: SettingsKey.lockDelay)))

        switch phase {
        case .background:
            backgroundedAt = Self.monotonicNow()
            if delay == 0 { isLocked = true }
        case .active:
            if let since = backgroundedAt {
                let elapsedSeconds = (Self.monotonicNow() - since) / 1_000_000_000
                if elapsedSeconds >= delay { isLocked = true }
                backgroundedAt = nil
            }
        default:
            break
        }
    }

    /// Relógio que só anda para a frente e continua contando com o iPhone em repouso.
    /// Diferente da data do sistema, não pode ser burlado mudando o horário do aparelho.
    private static func monotonicNow() -> UInt64 {
        clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)
    }
}
