import Foundation
import UIKit
import BackgroundTasks
import UserNotifications

/// Checagem em segundo plano: sincroniza e avalia os alertas sem você abrir o app.
///
/// Quem decide QUANDO rodar é o iOS (algumas vezes por dia, conforme o seu uso).
/// Regra de segurança mantida: com o iPhone bloqueado, o cofre e as chaves do
/// Keychain ficam fechados, então a checagem simplesmente não acontece. Ela
/// roda quando o iPhone está desbloqueado, por exemplo enquanto você usa outro app.
enum BackgroundRefresh {
    static let identifier = "com.soturnna.fluxo.refresh"

    /// Precisa ser chamado antes de o app terminar de abrir (no init do App).
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(refresh)
        }
    }

    /// Pede ao iOS a próxima checagem (no mínimo daqui a 3 horas).
    static func schedule() {
        guard UserDefaults.standard.bool(forKey: SettingsKey.notifyEnabled) else {
            cancel()
            return
        }
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 3 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }

    static func cancel() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
    }

    private static func handle(_ task: BGAppRefreshTask) {
        schedule()   // já deixa a próxima pedida

        let work = Task { @MainActor () -> Bool in
            guard UIApplication.shared.isProtectedDataAvailable,
                  UserDefaults.standard.bool(forKey: SettingsKey.notifyEnabled)
            else { return false }
            // Um armazenamento próprio, que some ao terminar: nada fica na memória.
            let store = FinanceStore()
            guard store.isConfigured else { return false }
            await store.sync()
            guard !Task.isCancelled else { return false }
            await NotificationPlanner.evaluate(store)
            return true
        }
        // O iOS avisa quando o tempo acabou: a sincronização é cancelada e
        // os dados anteriores ficam intactos (mesma regra do app aberto).
        task.expirationHandler = { work.cancel() }
        Task {
            let success = await work.value
            task.setTaskCompleted(success: success)
        }
    }
}

/// Recebe as notificações com o app aberto e os toques nelas.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    /// Com o app aberto, mostra o aviso no topo mesmo assim.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    /// Toque na notificação: abre o app (sempre atrás do Face ID) na aba certa.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let raw = response.notification.request.content.userInfo["tab"] as? String
        // Só valores da lista fixa são aceitos.
        guard let route = raw.flatMap(NotificationRoute.init(rawValue:)) else { return }
        await MainActor.run { NotificationRouter.shared.requested = route }
    }
}

/// Ponte entre o toque na notificação e a barra de abas.
@MainActor
final class NotificationRouter: ObservableObject {
    static let shared = NotificationRouter()
    @Published var requested: NotificationRoute?
}
