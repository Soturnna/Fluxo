import SwiftUI
import UIKit

/// Ajustes › Compras do Apple Pay: passo a passo da automação no app Atalhos.
struct ApplePaySetupView: View {
    private let steps: [(title: String, detail: String)] = [
        ("Abra o app Atalhos", "Toque em Automação, embaixo, e depois em Nova Automação (ou no +)."),
        ("Escolha “Transação”", "É o gatilho da Carteira. Selecione o cartão do Nubank (ou outro) e marque Executar Imediatamente, para não pedir confirmação a cada compra."),
        ("Adicione a ação do Fluxo", "Toque em Nova Automação em Branco › Adicionar Ação e procure “Registrar compra no Fluxo”."),
        ("Ligue os campos", "Em Valor, toque e escolha a variável do valor da Transação. Em Estabelecimento, a do comerciante. Em Meio, Crédito ou Débito, conforme o cartão."),
        ("Pronto", "Cada compra por Apple Pay entra no Início em “Aguardando o banco”. Se for no débito, já desconta do saldo estimado. Quando o banco confirmar, ela sai de lá sozinha.")
    ]

    var body: some View {
        List {
            Section {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.footnote.weight(.bold).monospacedDigit())
                            .foregroundStyle(Theme.ink)
                            .frame(width: 26, height: 26)
                            .background(Theme.lime.opacity(0.6), in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(step.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                            Text(step.detail)
                                .font(.footnote)
                                .foregroundStyle(Theme.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("Passo a passo")
            } footer: {
                Text("Só compras com Apple Pay disparam a automação. Pix e outros pagamentos: mande o print ao agente ou registre no Início.")
            }

            Section {
                Button {
                    if let url = URL(string: "shortcuts://") { UIApplication.shared.open(url) }
                } label: {
                    Label("Abrir o app Atalhos", systemImage: "arrow.up.right.square")
                }
            } footer: {
                Text("A ação só acrescenta um lançamento provisório: não lê nada do Fluxo e não mexe em conta nenhuma. Se a compra acontecer com o iPhone bloqueado, ela fica guardada protegida pelo iOS e entra no cofre quando você abrir o app.")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.ground.ignoresSafeArea())
        .navigationTitle("Compras do Apple Pay")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 84) }
    }
}
