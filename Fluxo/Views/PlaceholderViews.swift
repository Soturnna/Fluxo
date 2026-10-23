import SwiftUI

/// Telas que ganham conteúdo nas próximas partes.
/// Já existem para a navegação funcionar e para testar o visual no iPhone.

struct TransactionsView: View {
    var body: some View {
        Screen("Transações") {
            EmptyStateView(
                systemName: "list.bullet.rectangle",
                title: "Nenhuma transação ainda",
                message: "Depois que os bancos forem conectados, as transações aparecem aqui, agrupadas por dia."
            )
        }
    }
}

struct BudgetsView: View {
    var body: some View {
        Screen("Orçamentos") {
            EmptyStateView(
                systemName: "chart.pie",
                title: "Nenhum orçamento ainda",
                message: "Com as transações importadas, você poderá definir limites por categoria e acompanhar o mês."
            )
        }
    }
}

struct AgentView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Label("Somente leitura · não move dinheiro", systemImage: "checkmark.shield")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.inkSecondary)
                    EmptyStateView(
                        systemName: "sparkles",
                        title: "O agente chega numa próxima etapa",
                        message: "Ele vai responder perguntas sobre seus gastos usando o Gemini. CPF, contas, agências e nomes de pessoas são filtrados antes de qualquer envio."
                    )
                }
                .padding(16)
            }
            .background(Theme.ground.ignoresSafeArea())
            .navigationTitle("Agente Fluxo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .accessibilityLabel("Fechar o agente")
                }
            }
        }
    }
}
