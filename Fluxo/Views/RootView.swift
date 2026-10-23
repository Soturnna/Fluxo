import SwiftUI

enum AppTab: Hashable {
    case home, transactions, budgets, settings
}

/// Estrutura do app desbloqueado: as quatro abas e a barra flutuante.
struct RootView: View {
    @State private var tab: AppTab = .home
    @State private var showAgent = false
    /// Criado aqui (e não no App) de propósito: quando a sessão expira, o
    /// RootView é recriado e leva junto da memória saldos, transações e o
    /// token do Pluggy. No disco, eles continuam só dentro do cofre cifrado.
    @StateObject private var finance = FinanceStore()
    /// A conversa com o agente vive enquanto a sessão estiver aberta.
    @StateObject private var agent = AgentEngine()
    @StateObject private var audit = AuditLog()
    @EnvironmentObject private var lock: AppLock

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch tab {
                case .home:
                    HomeView(
                        openAgent: { showAgent = true },
                        openSettings: { tab = .settings },
                        openTransactions: { tab = .transactions }
                    )
                case .transactions:
                    TransactionsView()
                case .budgets:
                    BudgetsView()
                case .settings:
                    SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            FloatingTabBar(selection: $tab, onAgent: { showAgent = true })
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
                .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .background(Theme.ground.ignoresSafeArea())
        // A barra fica sempre colada embaixo, mesmo com o teclado aberto.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .environmentObject(finance)
        .environmentObject(agent)
        .environmentObject(audit)
        .fullScreenCover(isPresented: $showAgent) {
            AgentView()
                .environmentObject(finance)
                .environmentObject(agent)
                .environmentObject(audit)
                .environmentObject(lock)
        }
    }
}

/// Barra de abas flutuante com vidro (camada de navegação) e o botão do agente.
struct FloatingTabBar: View {
    @Binding var selection: AppTab
    let onAgent: () -> Void

    private struct Item: Identifiable {
        let tab: AppTab
        let title: String
        let icon: String
        var id: AppTab { tab }
    }

    private let items: [Item] = [
        Item(tab: .home, title: "Início", icon: "house"),
        Item(tab: .transactions, title: "Transações", icon: "list.bullet"),
        Item(tab: .budgets, title: "Orçamentos", icon: "chart.pie"),
        Item(tab: .settings, title: "Ajustes", icon: "slider.horizontal.3")
    ]

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 0) {
                ForEach(items) { item in
                    let isSelected = selection == item.tab
                    Button {
                        selection = item.tab
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: item.icon)
                                .font(.system(size: 17, weight: .medium))
                            Text(item.title)
                                .font(.caption2.weight(isSelected ? .semibold : .medium))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .foregroundStyle(isSelected ? Theme.ink : Theme.inkSecondary)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(isSelected ? Theme.ink.opacity(0.06) : Color.clear, in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(5)
            .fluxoGlass(in: Capsule())
            .floatingShadow()
            .sensoryFeedback(.selection, trigger: selection)

            Button(action: onAgent) {
                Image(systemName: "sparkles")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 60, height: 60)
                    .background(Theme.lime, in: Circle())
            }
            .buttonStyle(.plain)
            .floatingShadow()
            .accessibilityLabel("Abrir o agente")
        }
    }
}
