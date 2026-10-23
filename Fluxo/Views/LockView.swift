import SwiftUI

/// Tela de bloqueio. Pede o Face ID assim que aparece.
struct LockView: View {
    @EnvironmentObject private var lock: AppLock

    var body: some View {
        ZStack {
            Theme.forest.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                AppMark(size: 80)
                Text("Fluxo")
                    .font(.rounded(.largeTitle, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.top, 18)
                Text("Seu dinheiro, sem planilha.")
                    .font(.body)
                    .foregroundStyle(Theme.onForestSecondary)
                    .padding(.top, 4)

                Label("Bloqueado", systemImage: "lock.fill")
                    .font(.subheadline)
                    .foregroundStyle(Theme.onForestSecondary)
                    .padding(.top, 40)

                Spacer()

                if let message = lock.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 14)
                }

                Button {
                    Task { await lock.unlock() }
                } label: {
                    Label("Desbloquear com \(lock.biometryName)", systemImage: lock.biometryIcon)
                        .frame(maxWidth: .infinity, minHeight: 54)
                }
                .buttonStyle(LimeButtonStyle())
                .disabled(lock.isAuthenticating)

                Text("O app bloqueia sozinho ao sair e esconde os valores no alternador de apps.")
                    .font(.footnote)
                    .foregroundStyle(Theme.onForestSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 14)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        // Abre o Face ID sozinho uma vez por retorno ao app.
        // O próprio pedido de Face ID deixa a cena "inativa" e depois "ativa" de novo;
        // sem a trava abaixo, cancelar o Face ID faria ele reabrir em ciclo.
        .task(id: scenePhase) {
            switch scenePhase {
            case .background:
                didAutoPrompt = false
            case .active where !didAutoPrompt:
                didAutoPrompt = true
                try? await Task.sleep(nanoseconds: 350_000_000)
                await lock.unlock()
            default:
                break
            }
        }
    }

    @Environment(\.scenePhase) private var scenePhase
    @State private var didAutoPrompt = false
}
