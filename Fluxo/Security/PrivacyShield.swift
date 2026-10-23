import SwiftUI
import UIKit

/// Cobre a tela quando o app sai do primeiro plano.
///
/// O iOS tira uma "foto" do app para o alternador de apps no instante em que
/// ele vai para segundo plano. Sem esta proteção, essa foto mostraria o saldo.
///
/// Por que uma janela separada (UIWindow) e não um simples overlay?
/// Folhas, alertas e telas cheias do SwiftUI ficam ACIMA de um overlay comum.
/// Uma janela com nível acima de alertas cobre absolutamente tudo.
@MainActor
final class ShieldWindowController {
    private var window: UIWindow?

    func show() {
        guard window == nil,
              let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first
        else { return }

        let host = UIHostingController(rootView: ShieldView())
        host.overrideUserInterfaceStyle = .light

        let shieldWindow = UIWindow(windowScene: scene)
        shieldWindow.windowLevel = .alert + 1
        shieldWindow.rootViewController = host
        shieldWindow.isHidden = false
        window = shieldWindow
    }

    func hide() {
        window?.isHidden = true
        window = nil
    }
}

/// O que aparece no alternador de apps: só a marca, nenhum dado.
struct ShieldView: View {
    var body: some View {
        ZStack {
            Theme.forest.ignoresSafeArea()
            AppMark(size: 96)
        }
        .accessibilityLabel("Fluxo protegido")
    }
}
