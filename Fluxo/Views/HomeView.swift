import SwiftUI

/// Tela inicial: saldo, resumo do mês e últimas transações.
/// Mostra na hora o que está no cofre e sincroniza em seguida.
struct HomeView: View {
    @EnvironmentObject private var lock: AppLock
    @EnvironmentObject private var store: FinanceStore
    @AppStorage(SettingsKey.profileName) private var name = "Marcos"
    @State private var selected: StoredTransaction?
    @State private var planned: PlannedEditorTarget?

    let openAgent: () -> Void
    let openSettings: () -> Void
    let openTransactions: () -> Void

    private var monthLabel: String {
        Date.now
            .formatted(.dateTime.month(.wide).year().locale(.ptBR))
            .uppercased()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                balanceCard
                if store.isConfigured {
                    monthCard
                    agentCard
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
        }
        .padding(.horizontal, 4)
    }

    // MARK: Saldo

    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Saldo em conta")
                .font(.subheadline)
                .foregroundStyle(Theme.onForestSecondary)
            MoneyText(value: store.bankBalance, font: .rounded(.largeTitle, weight: .bold))
                .foregroundStyle(.white)
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
        if let last = store.lastSyncAt {
            parts.append("atualizado \(last.formatted(Date.RelativeFormatStyle(presentation: .named, locale: .ptBR)))")
        } else if store.state == .loading {
            parts.append("buscando seus dados…")
        }
        return parts.isEmpty ? "Puxe para baixo para sincronizar" : parts.joined(separator: " · ")
    }

    // MARK: Mês

    private var monthCard: some View {
        let totals = store.totals(inMonthOf: .now)
        return HStack(spacing: 0) {
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
        .card(padding: 16)
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
