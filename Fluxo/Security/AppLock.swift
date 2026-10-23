import SwiftUI
import LocalAuthentication

/// Controla o bloqueio do app, a sessão de uso e o botão de ocultar valores.
///
/// Duas ideias separadas:
/// - BLOQUEIO: uma tela opaca por cima de tudo, que só sai com Face ID.
///   O que estava aberto embaixo continua lá (você volta de onde parou).
/// - SESSÃO: o conjunto de telas e dados em memória. Se o app ficar mais de
///   5 minutos em segundo plano, a sessão é descartada e tudo é recriado do zero.
@MainActor
final class AppLock: ObservableObject {
    @Published private(set) var isLocked: Bool
    @Published var valuesHidden: Bool
    @Published private(set) var errorMessage: String?
    @Published private(set) var isAuthenticating = false

    /// Muda a cada nova sessão. A árvore de telas usa este valor como identidade:
    /// quando ele muda, o SwiftUI destrói as telas antigas e cria novas.
    @Published private(set) var sessionID = UUID()
    /// Só vira true depois do primeiro desbloqueio da sessão. Antes disso,
    /// nenhuma tela com dados é montada (nem por um instante, atrás do bloqueio).
    @Published private(set) var sessionStarted: Bool

    /// Tempo máximo em segundo plano antes de descartar a sessão.
    static let sessionLifetime: UInt64 = 5 * 60

    /// Nome e ícone da biometria do aparelho ("Face ID", "faceid").
    let biometryName: String
    let biometryIcon: String

    private let defaults = UserDefaults.standard
    /// Momento em que o app foi para segundo plano, num relógio monotônico.
    private var backgroundedAt: UInt64?
    /// Evita abrir o Face ID sozinho mais de uma vez por retorno ao app.
    private var didAutoPrompt = false

    init() {
        SettingsDefaults.register()
        let requireAuth = UserDefaults.standard.bool(forKey: SettingsKey.requireAuth)
        isLocked = requireAuth
        sessionStarted = !requireAuth
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

    private var requireAuth: Bool {
        defaults.bool(forKey: SettingsKey.requireAuth)
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
            if !sessionStarted {
                valuesHidden = defaults.bool(forKey: SettingsKey.hideValuesOnOpen)
            }
            sessionStarted = true
            isLocked = false
        }
    }

    /// Encerra a sessão na hora (usado depois de apagar todos os dados).
    func endSession() {
        startFreshSession()
    }

    private func startFreshSession() {
        sessionID = UUID()
        sessionStarted = !requireAuth
        isLocked = requireAuth
        valuesHidden = defaults.bool(forKey: SettingsKey.hideValuesOnOpen)
    }

    // MARK: Ciclo de vida

    func handleScenePhase(_ phase: ScenePhase) {
        let delay = UInt64(max(0, defaults.integer(forKey: SettingsKey.lockDelay)))

        switch phase {
        case .background:
            backgroundedAt = Self.monotonicNow()
            didAutoPrompt = false
            if requireAuth && delay == 0 { isLocked = true }

        case .active:
            if let since = backgroundedAt {
                let elapsedSeconds = (Self.monotonicNow() - since) / 1_000_000_000
                if elapsedSeconds >= Self.sessionLifetime {
                    startFreshSession()          // muito tempo fora: descarta tudo
                } else if requireAuth && elapsedSeconds >= delay {
                    isLocked = true              // pouco tempo fora: só bloqueia
                }
                backgroundedAt = nil
            }
            if isLocked && !didAutoPrompt {
                didAutoPrompt = true
                Task { [weak self] in
                    // Pequena espera para a tela de bloqueio aparecer antes do Face ID.
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    await self?.unlock()
                }
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
