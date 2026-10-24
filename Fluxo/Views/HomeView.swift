import SwiftUI

/// Telas que abrem a partir do Início.
enum HomeRoute: Hashable {
    case card, cashFlow
}

/// Tela inicial: saldo, cartão, mês, próximos 30 dias e últimas transações.
/// Mostra na hora o que está no cofre e sincroniza em seguida.
struct HomeView: View {
    @EnvironmentObject private var lock: AppLock
    @EnvironmentObject private var store: FinanceStore
    @AppStorage(SettingsKey.profileName) private var name = "Marcos"
    @State private var selected: StoredTransaction?
    @State private var planned: PlannedEditorTarget?
    @State private var registering = false

    let openAgent: () -> Void
    let openSettings: () -> Void
    let openTransactions: () -> Void
    let openInvestments: () -> Void

    private var monthLabel: String {
        Date.now
            .formatted(.dateTime.month(.wide).year().locale(.ptBR))
            .uppercased()
    }

    var body: some View {
        NavigationStack {
            content
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: HomeRoute.self) { route in
                    switch route {
                    case .card: CreditCardView()
                    case .cashFlow: CashFlowView()
                    }
                }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                balanceCard
                if store.isConfigured {
                    CreditCardHomeCard()
                    monthCard
                    CashFlowPreviewCard()
                    investmentsCard
                    agentCard
                    ProvisionalSection(onAdd: { registering = true })
                    UpcomingPlannedSection(
                        onAdd: { planned = .new },
                        onSelect: { planned = .edit($0) }
                    )
                    recentSection
                } else {
                    agentCard
                    EmptyStateView(
                        systemName: "building.columns",
                        title: "Conecte seus bancos",
                        message: "Cadastre as credenciais do Meu Pluggy em Ajustes para ver saldos e transações aqui.",
                        actionTitle: "Ir para Ajustes",
                        action: openSettings
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .background(Theme.ground.ignoresSafeArea())
        .refreshable { await store.sync() }
        .task { await store.syncIfStale() }
        .sheet(item: $selected) { transaction in
            TransactionDetailSheet(transaction: transaction)
                .environmentObject(store)
                .environmentObject(lock)
        }
        .sheet(isPresented: $registering) {
            ProvisionalEditorSheet()
                .environmentObject(store)
                .environmentObject(lock)
        }
        .sheet(item: $planned) { target in
            PlannedExpenseEditor(existing: target.expense)
                .environmentObject(store)
                .environmentObject(lock)
        }
    }

    // MARK: Cabeçalho

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(monthLabel)
                    .tracking(0.4)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.inkTertiary)
                Text("Olá, \(name)")
                    .font(.rounded(.title2, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer()
            Button {
                lock.valuesHidden.toggle()
            } label: {
                Image(systemName: lock.valuesHidden ? "eye.slash" : "eye")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 44, height: 44)
                    .background(Theme.surface, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.line, lineWidth: Theme.hairline))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(lock.valuesHidden ? "Mostrar valores" : "Ocultar valores")
            .sensoryFeedback(.selection, trigger: lock.valuesHidden)

            Button(action: openSettings) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 44, height: 44)
                    .background(Theme.surface, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.line, lineWidth: Theme.hairline))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ajustes")
        }
        .padding(.horizontal, 4)
    }

    // MARK: Saldo

    private var balanceCard: some View {
        let estimate = store.estimatedBalance
        return VStack(alignment: .leading, spacing: 8) {
            Text(estimate == nil ? "Saldo em conta" : "Saldo estimado agora")
                .font(.subheadline)
                .foregroundStyle(Theme.onForestSecondary)
            MoneyText(value: estimate?.value ?? store.bankBalance, font: .rounded(.largeTitle, weight: .bold))
                .foregroundStyle(.white)
            if let estimate {
                // Transparência: de onde vem a estimativa.
                Text(estimateCaption(estimate))
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.lime)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 6) {
                if store.state == .loading {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(Theme.onForestSecondary)
                } else if store.failedConnectionCount > 0 {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .imageScale(.small)
                }
                Text(balanceCaption)
            }
            .font(.footnote)
            .foregroundStyle(Theme.onForestSecondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.forest, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func estimateCaption(_ estimate: (value: Decimal, adjustment: Decimal, count: Int)) -> String {
        let when = store.bankDataAt.map { FinanceStore.bankTimeLabel($0) } ?? "última busca"
        let items = estimate.count == 1 ? "1 lançamento registrado depois" : "\(estimate.count) lançamentos registrados depois"
        if lock.valuesHidden { return "Saldo do banco (\(when)) + \(items)" }
        let bank = (store.bankBalance ?? 0).formatted(.currency(code: "BRL").locale(.ptBR))
        let delta = abs(estimate.adjustment).formatted(.currency(code: "BRL").locale(.ptBR))
        let sign = estimate.adjustment < 0 ? "−" : "+"
        return "Banco \(bank) (\(when)) \(sign) \(delta) de \(items)"
    }

    private var balanceCaption: String {
        if !store.isConfigured { return "Nenhum banco conectado ainda" }
        if case .failed(let message) = store.state { return message }
        if store.failedConnectionCount > 0 {
            return store.failedConnectionCount == 1
                ? "1 conexão com falha · veja em Conexões"
                : "\(store.failedConnectionCount) conexões com falha · veja em Conexões"
        }

        var parts: [String] = []
        let accounts = store.bankAccountCount
        if accounts > 0 { parts.append(accounts == 1 ? "1 conta" : "\(accounts) contas") }
        if store.cardCount > 0 { parts.append(store.cardCount == 1 ? "1 cartão" : "\(store.cardCount) cartões") }
        if let bankAt = store.bankDataAt {
            // A hora que importa é a do banco, não a da conversa com o Pluggy.
            parts.append("saldo do banco de \(FinanceStore.bankTimeLabel(bankAt))")
        } else if let last = store.lastSyncAt {
            parts.append("atualizado \(last.formatted(Date.RelativeFormatStyle(presentation: .named, locale: .ptBR)))")
        } else if store.state == .loading {
            parts.append("buscando seus dados…")
        }
        return parts.isEmpty ? "Puxe para baixo para sincronizar" : parts.joined(separator: " · ")
    }

    // MARK: Mês

    private var monthCard: some View {
        let totals = store.totals(inMonthOf: .now)
        let accountSpent = store.totals(inMonthOf: .now, origin: .account).spent
        let cardSpent = store.totals(inMonthOf: .now, origin: .card).spent
        return VStack(alignment: .leading, spacing: 12) {
            monthTotals(totals)
            if cardSpent > 0 {
                originSplit(account: accountSpent, card: cardSpent)
            }
        }
        .card(padding: 16)
    }

    /// Divisão do gasto do mês: conta (azul) e cartão (laranja), com valores escritos.
    private func originSplit(account: Decimal, card: Decimal) -> some View {
        let total = (account + card as NSDecimalNumber).doubleValue
        let accountShare = total > 0 ? (account as NSDecimalNumber).doubleValue / total : 0
        return VStack(alignment: .leading, spacing: 8) {
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    Rectangle().fill(ChartPalette.income)
                        .frame(width: max((proxy.size.width - 2) * accountShare, 0))
                    Rectangle().fill(ChartPalette.spending)
                }
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            .frame(height: 10)
            .accessibilityHidden(true)
            HStack(spacing: 14) {
                legend(color: ChartPalette.income, label: "Conta", value: account)
                legend(color: ChartPalette.spending, label: "Cartão", value: card)
            }
        }
    }

    private func legend(color: Color, label: String, value: Decimal) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 10, height: 10)
            Text(label).foregroundStyle(Theme.inkSecondary)
            MoneyText(value: value, font: .footnote.weight(.semibold))
        }
        .font(.footnote)
        .accessibilityElement(children: .combine)
    }

    private func monthTotals(_ totals: (spent: Decimal, income: Decimal)) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Gasto do mês", systemImage: "arrow.up.right")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.inkSecondary)
                MoneyText(value: totals.spent, font: .rounded(.title3, weight: .semibold))
                    .foregroundStyle(Theme.ink)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle()
                .fill(Theme.line)
                .frame(width: Theme.hairline, height: 40)
                .padding(.horizontal, 12)

            VStack(alignment: .leading, spacing: 4) {
                Label("Entradas", systemImage: "arrow.down.left")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.inkSecondary)
                MoneyText(value: totals.income, font: .rounded(.title3, weight: .semibold))
                    .foregroundStyle(Theme.positive)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Investimentos

    @ViewBuilder
    private var investmentsCard: some View {
        if !store.activeInvestments.isEmpty {
            Button(action: openInvestments) {
                HStack(spacing: 12) {
                    IconTile(systemName: "chart.line.uptrend.xyaxis", style: .neutral, size: 40)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Investimentos")
                            .font(.footnote)
                            .foregroundStyle(Theme.inkSecondary)
                        MoneyText(value: store.investedTotal, font: .rounded(.title3, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                        if let profit = store.investmentsLastMonthProfit {
                            HStack(spacing: 3) {
                                Text("+")
                                MoneyText(value: profit, font: .caption.weight(.medium))
                                Text("no último mês")
                            }
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Theme.positive)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.inkTertiary)
                }
                .card(padding: 16)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Agente

    private var agentCard: some View {
        Button(action: openAgent) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.lime)
                    .frame(width: 34, height: 34)
                    .background(Theme.ink, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Agente Fluxo")
                        .font(.subheadline.weight(.semibold))
                    Text("Pergunte, organize e preveja gastos.")
                        .font(.footnote)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(Theme.ink)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.lime, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Últimas transações

    @ViewBuilder
    private var recentSection: some View {
        let recent = Array(store.transactions.prefix(4))
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Últimas transações")
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if !recent.isEmpty {
                    Button("Ver todas", action: openTransactions)
                        .font(.subheadline.weight(.medium))
                }
            }
            .padding(.horizontal, 4)

            if recent.isEmpty {
                Text(store.state == .loading ? "Buscando suas transações…" : "Nenhuma transação importada ainda.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recent.enumerated()), id: \.element.id) { index, item in
                        if index > 0 {
                            Divider().overlay(Theme.line)
                        }
                        Button {
                            selected = item
                        } label: {
                            TransactionRow(
                                transaction: item,
                                category: store.category(for: item),
                                accountName: store.account(withId: item.accountId)?.displayName
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                        .strokeBorder(Theme.line, lineWidth: Theme.hairline)
                )
            }
        }
    }
}
