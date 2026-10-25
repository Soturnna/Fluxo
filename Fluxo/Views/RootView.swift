import SwiftUI
import UIKit

enum AppTab: Hashable {
    case home, transactions, budgets, investments
}

/// Estrutura do app desbloqueado: as quatro abas e a barra flutuante.
struct RootView: View {
    @State private var tab: AppTab = .home
    @State private var showAgent = false
    /// Ajustes abre pela engrenagem do Início (a aba virou Investir).
    @State private var showSettings = false
    /// Criado aqui (e não no App) de propósito: quando a sessão expira, o
    /// RootView é recriado e leva junto da memória saldos, transações e o
    /// token do Pluggy. No disco, eles continuam só dentro do cofre cifrado.
    @StateObject private var finance = FinanceStore()
    /// A conversa com o agente vive enquanto a sessão estiver aberta.
    @StateObject private var agent = AgentEngine()
    @StateObject private var audit = AuditLog()
    @EnvironmentObject private var lock: AppLock
    @ObservedObject private var router = NotificationRouter.shared
    @ObservedObject private var incoming = IncomingBill.shared
    @State private var sharedBill: SharedBill?
    @State private var sharedBillError: String?

    struct SharedBill: Identifiable {
        let card: StoredAccount
        let file: BillFile
        let id = UUID()
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch tab {
                case .home:
                    HomeView(
                        openAgent: { showAgent = true },
                        openSettings: { showSettings = true },
                        openTransactions: { tab = .transactions },
                        openInvestments: { tab = .investments }
                    )
                case .transactions:
                    TransactionsView()
                case .budgets:
                    BudgetsView()
                case .investments:
                    InvestmentsView(
                        askAgent: { prompt in
                            showAgent = true
                            Task { await agent.send(prompt, store: finance, audit: audit) }
                        },
                        openSettings: { showSettings = true }
                    )
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
        // Alertas: avaliados ao abrir a sessão, depois de cada sincronização
        // e quando seus dados mudam (orçamentos, gastos previstos...).
        .task {
            ProvisionalInbox.drain(into: finance)   // compras do Apple Pay que chegaram
            WidgetBridge.refreshTest()              // widget (etapa 1: só o horário)
            await NotificationPlanner.evaluate(finance)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            ProvisionalInbox.drain(into: finance)
            WidgetBridge.refreshTest()
        }
        .onChange(of: finance.lastSyncAt) { _, _ in
            Task { await NotificationPlanner.evaluate(finance) }
        }
        .onChange(of: finance.userData) { _, _ in
            Task { await NotificationPlanner.evaluate(finance) }
        }
        // Toque numa notificação: vai para a aba dela.
        .onChange(of: router.requested, initial: true) { _, route in
            guard let route else { return }
            showAgent = false
            switch route {
            case .home: tab = .home
            case .transactions: tab = .transactions
            case .budgets: tab = .budgets
            case .settings: showSettings = true
            }
            router.requested = nil
        }
        // Fatura recebida pelo "Compartilhar": lê no iPhone, apaga a cópia e abre a conferência.
        .onChange(of: incoming.pending, initial: true) { _, url in
            guard let url else { return }
            incoming.pending = nil
            do {
                let file = try BillFileParser.read(url, deleteAfter: true)
                guard let card = finance.creditCards.first else {
                    sharedBillError = "Nenhum cartão de crédito conectado."
                    return
                }
                showAgent = false
                showSettings = false
                sharedBill = SharedBill(card: card, file: file)
            } catch {
                sharedBillError = (error as? LocalizedError)?.errorDescription ?? BillImportError.unreadable.errorDescription
            }
        }
        .sheet(item: $sharedBill) { bill in
            BillImportSheet(card: bill.card, initialFile: bill.file)
                .environmentObject(finance)
                .environmentObject(lock)
        }
        .alert("Fatura", isPresented: Binding(get: { sharedBillError != nil }, set: { if !$0 { sharedBillError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(sharedBillError ?? "")
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(finance)
                .environmentObject(agent)
                .environmentObject(audit)
                .environmentObject(lock)
        }
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
        Item(tab: .investments, title: "Investir", icon: "chart.line.uptrend.xyaxis")
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
