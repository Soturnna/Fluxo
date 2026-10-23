import SwiftUI

@main
struct FluxoApp: App {
    @StateObject private var lock = AppLock()

    init() {
        SettingsDefaults.register()
        FirstLaunch.purgeLeftoverSecretsIfNeeded()
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

/// Decide entre a tela de bloqueio e o app, e aciona a proteção do alternador.
///
/// Quando o app bloqueia, a árvore de telas inteira (RootView) é DESMONTADA,
/// não apenas escondida. Assim nenhuma tela aberta, folha ou valor continua
/// na memória da interface atrás do bloqueio.
struct AppRoot: View {
    @EnvironmentObject private var lock: AppLock
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(SettingsKey.shieldInSwitcher) private var shieldInSwitcher = true
    @State private var shield = ShieldWindowController()

    var body: some View {
        ZStack {
            if lock.isLocked {
                LockView()
                    .transition(.opacity)
            } else {
                RootView()
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: lock.isLocked)
        .onChange(of: scenePhase) { _, phase in
            lock.handleScenePhase(phase)
            if phase == .active {
                shield.hide()
            } else if shieldInSwitcher {
                shield.show()
            }
        }
    }
}
