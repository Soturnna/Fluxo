import SwiftUI

enum AppTab: Hashable {
    case home, transactions, budgets, settings
}

/// Estrutura do app desbloqueado: as quatro abas e a barra flutuante.
struct RootView: View {
    @State private var tab: AppTab = .home
    @State private var showAgent = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch tab {
                case .home:
                    HomeView(openAgent: { showAgent = true }, openSettings: { tab = .settings })
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
        .fullScreenCover(isPresented: $showAgent) {
            AgentView()
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
                        VStack(spacing: 2) {
                            Image(systemName: item.icon)
                                .font(.system(size: 19, weight: .semibold))
                            Text(item.title)
                                .font(.caption2.weight(isSelected ? .bold : .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .foregroundStyle(isSelected ? Theme.ink : Theme.inkSecondary)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(isSelected ? Theme.ink.opacity(0.08) : Color.clear, in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(6)
            .fluxoGlass(in: Capsule())
            .shadow(color: Theme.ink.opacity(0.12), radius: 15, y: 8)
            .sensoryFeedback(.selection, trigger: selection)

            Button(action: onAgent) {
                Image(systemName: "sparkles")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 64, height: 64)
                    .background(Theme.lime, in: Circle())
                    .overlay(Circle().stroke(Theme.ink.opacity(0.1), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .shadow(color: Theme.ink.opacity(0.18), radius: 15, y: 8)
            .accessibilityLabel("Abrir o agente")
        }
    }
}
