import SwiftUI
import UIKit
import UserNotifications

@main
struct FluxoApp: App {
    @StateObject private var lock = AppLock()

    init() {
        SettingsDefaults.register()
        FirstLaunch.purgeLeftoverSecretsIfNeeded()
        // Notificações: o delegado e a tarefa de segundo plano precisam
        // existir antes de o app terminar de abrir.
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        BackgroundRefresh.register()
    }

    var body: some Scene {
        WindowGroup {
            AppRoot()
                .environmentObject(lock)
                .preferredColorScheme(.light)
                .tint(Theme.link)
        }
    }
}

/// Liga o ciclo de vida do app às regras de segurança.
///
/// - Antes do primeiro desbloqueio da sessão, nenhuma tela com dados é montada.
/// - Bloquear cobre o app com uma janela própria; o que estava aberto continua.
/// - Uma sessão nova (após 5 min fora) recria todas as telas do zero,
///   descartando saldos, contas, token do Pluggy e qualquer texto digitado.
struct AppRoot: View {
    @EnvironmentObject private var lock: AppLock
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(SettingsKey.shieldInSwitcher) private var shieldInSwitcher = true
    @State private var shield = ShieldWindowController()
    @State private var lockWindow = LockWindowController()

    var body: some View {
        ZStack {
            if lock.sessionStarted {
                RootView()
                    .id(lock.sessionID)                   // sessão nova = telas novas
                    .accessibilityHidden(lock.isLocked)   // VoiceOver não lê o que está por baixo
            } else {
                Theme.forest.ignoresSafeArea()
            }
        }
        // Fatura compartilhada com o Fluxo: fica na fila até o app ser desbloqueado.
        .onOpenURL { url in IncomingBill.shared.receive(url) }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase != .active { Self.dismissKeyboard() }
            lock.handleScenePhase(phase)
            if phase == .active {
                shield.hide()
            } else if shieldInSwitcher {
                shield.show()
            }
            if phase == .background { BackgroundRefresh.schedule() }
        }
        .onChange(of: lock.isLocked, initial: true) { _, locked in
            if locked {
                lockWindow.show(lock: lock)
            } else {
                lockWindow.hide()
            }
        }
    }

    /// Fecha o teclado ao sair do app. Assim o iOS não "esquece" o espaço
    /// reservado para ele, que antes empurrava a barra de abas para o meio da tela.
    private static func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
