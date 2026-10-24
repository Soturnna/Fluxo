import SwiftUI

/// Transações do mês, agrupadas por dia, com busca e totais.
struct TransactionsView: View {
    @EnvironmentObject private var store: FinanceStore
    @EnvironmentObject private var lock: AppLock
    @State private var selected: StoredTransaction?
    @State private var planned: PlannedEditorTarget?
    @State private var month = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
    @State private var query = ""
    /// Filtro por origem: nil = tudo; conta ou cartão.
    @State private var origin: FinanceStore.Origin?
    /// No modo Cartão, a navegação é por fatura: 0 = aberta, negativos = fechadas, positivos = futuras.
    @State private var billIndex = 0

    /// Faturas do cartão (só no filtro Cartão).
    private var schedule: FinanceStore.CardSchedule? {
        guard origin == .card, let card = store.creditCards.first else { return nil }
        return store.cardSchedule(card)
    }

    private var monthTransactions: [StoredTransaction] {
        let items = store.transactions(inMonthOf: month)
        guard let origin else { return items }
        return items.filter { store.origin(of: $0) == origin }
    }

    /// Busca sem diferenciar maiúsculas e acentos ("cafe" encontra "Café").
    private var filtered: [StoredTransaction] {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return monthTransactions }
        return monthTransactions.filter {
            $0.title.localizedStandardContains(text)
                || $0.description.localizedStandardContains(text)
                || store.category(for: $0).name.localizedStandardContains(text)
        }
    }

    private var isCurrentMonth: Bool {
        Calendar.current.isDate(month, equalTo: .now, toGranularity: .month)
    }

    var body: some View {
        Screen("Transações") {
            searchField
            if !store.creditCards.isEmpty { originPicker }
            if let schedule, let cycle = schedule.cycles.first(where: { $0.index == billIndex }) {
                billSwitcher(schedule, cycle)
                billTotal(cycle)
                if cycle.transactions.isEmpty && cycle.projected.isEmpty {
                    EmptyStateView(systemName: "creditcard", title: "Fatura sem lançamentos",
                                   message: "Nenhuma compra ou parcela cai nesta fatura.")
                } else {
                    BillItemsList(cycle: cycle, query: query) { selected = $0 }
                }
            } else {
                monthSwitcher
                totalsRow
                plannedSection
                content
            }
        }
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

    /// Gastos previstos do mês (só aparecem sem busca ativa).
    @ViewBuilder
    private var plannedSection: some View {
        let items = query.isEmpty ? store.plannedExpenses(inMonthOf: month) : []
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Previstos")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.inkTertiary)
                    .padding(.horizontal, 4)
                    .padding(.top, 6)
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Divider().overlay(Theme.line) }
                        Button {
                            planned = .edit(item)
                        } label: {
                            PlannedExpenseRow(
                                expense: item,
                                category: item.categoryId.flatMap { store.category(withId: $0) }
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .background(Theme.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                        .strokeBorder(Theme.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                )
            }
        }
    }

    // MARK: Partes da tela

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.inkSecondary)
                .accessibilityHidden(true)
            TextField("Loja, descrição ou categoria", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityLabel("Buscar transações")
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.inkTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Limpar busca")
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(Theme.track, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// Tudo | Conta | Cartão (só aparece quando há cartão).
    private var originPicker: some View {
        Picker("Origem", selection: $origin) {
            Text("Tudo").tag(FinanceStore.Origin?.none)
            Text("Conta").tag(FinanceStore.Origin?.some(.account))
            Text("Cartão").tag(FinanceStore.Origin?.some(.card))
        }
        .pickerStyle(.segmented)
    }

    /// ‹ Fatura de novembro › com a situação e as datas.
    private func billSwitcher(_ schedule: FinanceStore.CardSchedule, _ cycle: FinanceStore.BillCycle) -> some View {
        let indices = schedule.cycles.map(\.index)
        let status: String
        switch cycle.status {
        case .open: status = "Aberta · fecha \(FinanceStore.dayLabel(cycle.close)) · vence \(FinanceStore.dayLabel(cycle.due))"
        case .closed: status = cycle.due >= Calendar.current.startOfDay(for: .now)
            ? "Fechada · vence \(FinanceStore.dayLabel(cycle.due))"
            : "Fechada · venceu \(FinanceStore.dayLabel(cycle.due))"
        case .upcoming: status = "Futura · vence \(FinanceStore.dayLabel(cycle.due))"
        }
        return HStack {
            Button { billIndex -= 1 } label: {
                Image(systemName: "chevron.left").frame(width: 44, height: 44)
            }
            .disabled(billIndex <= (indices.min() ?? 0))
            .accessibilityLabel("Fatura anterior")

            Spacer()
            VStack(spacing: 2) {
                Text("Fatura de \(cycle.monthName)")
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                Text(status)
                    .font(.caption)
                    .foregroundStyle(cycle.status == .open ? Theme.link : Theme.inkSecondary)
            }
            Spacer()

            Button { billIndex += 1 } label: {
                Image(systemName: "chevron.right").frame(width: 44, height: 44)
            }
            .disabled(billIndex >= (indices.max() ?? 0))
            .accessibilityLabel("Próxima fatura")
        }
        .font(.body.weight(.medium))
        .foregroundStyle(Theme.ink)
    }

    private func billTotal(_ cycle: FinanceStore.BillCycle) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Total da fatura", systemImage: "creditcard")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.inkSecondary)
                MoneyText(value: cycle.total, font: .rounded(.title3, weight: .semibold))
                    .foregroundStyle(Theme.ink)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: 14)
            if !cycle.projected.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Parcelas previstas", systemImage: "calendar.badge.clock")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.inkSecondary)
                    Text("\(cycle.projected.count)")
                        .font(.rounded(.title3, weight: .semibold))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(padding: 14)
            }
        }
    }

    private var monthSwitcher: some View {
        HStack {
            Button {
                shiftMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Mês anterior")

            Spacer()
            Text(month.formatted(.dateTime.month(.wide).year().locale(.ptBR)).capitalized)
                .font(.headline)
                .foregroundStyle(Theme.ink)
            Spacer()

            Button {
                shiftMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 44, height: 44)
            }
            .disabled(isCurrentMonth)
            .accessibilityLabel("Próximo mês")
        }
        .font(.body.weight(.medium))
        .foregroundStyle(Theme.ink)
    }

    private var totalsRow: some View {
        let totals = origin.map { store.totals(inMonthOf: month, origin: $0) } ?? store.totals(inMonthOf: month)
        return HStack(spacing: 10) {
            totalCard(title: "Saídas", icon: "arrow.up.right", value: totals.spent, color: Theme.ink)
            totalCard(title: "Entradas", icon: "arrow.down.left", value: totals.income, color: Theme.positive)
        }
    }

    private func totalCard(title: String, icon: String, value: Decimal, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.inkSecondary)
            MoneyText(value: value, font: .rounded(.title3, weight: .semibold))
                .foregroundStyle(color)
        }
        .card(padding: 14)
    }

    @ViewBuilder
    private var content: some View {
        if store.transactions.isEmpty {
            if store.state == .loading {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Buscando suas transações…")
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSecondary)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                EmptyStateView(
                    systemName: "list.bullet.rectangle",
                    title: "Nenhuma transação ainda",
                    message: store.isConfigured
                        ? "Puxe a tela para baixo para sincronizar com o Meu Pluggy."
                        : "Cadastre as credenciais do Pluggy em Ajustes para importar suas transações."
                )
            }
        } else if filtered.isEmpty {
            EmptyStateView(
                systemName: query.isEmpty ? "calendar" : "magnifyingglass",
                title: query.isEmpty ? "Nada neste mês" : "Nenhum resultado",
                message: query.isEmpty
                    ? "Não há transações registradas neste mês."
                    : "Nenhuma transação deste mês corresponde à busca."
            )
        } else {
            ForEach(DaySection.make(from: filtered)) { section in
                VStack(alignment: .leading, spacing: 6) {
                    Text(section.title)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.inkTertiary)
                        .padding(.horizontal, 4)
                        .padding(.top, 6)
                    VStack(spacing: 0) {
                        ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
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
                            .accessibilityHint("Toque para ver detalhes e trocar a categoria")
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

    private func shiftMonth(by value: Int) {
        if let next = Calendar.current.date(byAdding: .month, value: value, to: month) {
            month = next
        }
    }
}
