import SwiftUI
import UIKit

/// Mostra a tela de bloqueio numa janela própria, acima de TUDO.
///
/// Por que uma janela separada?
/// A tela de bloqueio precisa cobrir também folhas, alertas e telas cheias
/// que estejam abertas (por exemplo, o agente). Um overlay comum do SwiftUI
/// ficaria por baixo delas. Uma UIWindow com nível acima dos alertas cobre tudo,
/// e o app por baixo continua exatamente como estava.
@MainActor
final class LockWindowController {
    private var window: UIWindow?

    func show(lock: AppLock) {
        guard window == nil,
              let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first
        else { return }

        let host = UIHostingController(rootView: LockView().environmentObject(lock))
        host.overrideUserInterfaceStyle = .light
        host.view.backgroundColor = UIColor(Theme.forest)

        let lockWindow = UIWindow(windowScene: scene)
        lockWindow.windowLevel = .alert + 2   // acima até da proteção do alternador
        lockWindow.rootViewController = host
        lockWindow.makeKeyAndVisible()        // recebe o foco (inclusive do VoiceOver)
        window = lockWindow
    }

    func hide() {
        guard let lockWindow = window else { return }
        window = nil

        // Devolve o foco à janela principal do app.
        lockWindow.windowScene?.windows
            .first(where: { $0.windowLevel == .normal })?
            .makeKey()

        UIView.animate(withDuration: 0.2, animations: {
            lockWindow.alpha = 0
        }, completion: { _ in
            lockWindow.isHidden = true
        })
    }
}
