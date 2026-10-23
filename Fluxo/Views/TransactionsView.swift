import SwiftUI

/// Transações do mês, agrupadas por dia, com busca e totais.
struct TransactionsView: View {
    @EnvironmentObject private var store: FinanceStore
    @State private var month = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
    @State private var query = ""

    private var monthTransactions: [StoredTransaction] {
        store.transactions(inMonthOf: month)
    }

    /// Busca sem diferenciar maiúsculas e acentos ("cafe" encontra "Café").
    private var filtered: [StoredTransaction] {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return monthTransactions }
        return monthTransactions.filter {
            $0.title.localizedStandardContains(text)
                || $0.description.localizedStandardContains(text)
                || $0.group.label.localizedStandardContains(text)
        }
    }

    private var isCurrentMonth: Bool {
        Calendar.current.isDate(month, equalTo: .now, toGranularity: .month)
    }

    var body: some View {
        Screen("Transações") {
            searchField
            monthSwitcher
            totalsRow
            content
        }
        .refreshable { await store.sync() }
        .task { await store.syncIfStale() }
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
        let totals = store.totals(inMonthOf: month)
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
                            TransactionRow(
                                transaction: item,
                                accountName: store.account(withId: item.accountId)?.displayName
                            )
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
