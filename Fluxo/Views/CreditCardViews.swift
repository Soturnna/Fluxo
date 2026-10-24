import SwiftUI
import Charts

/// Desenho pequeno de um cartão (verde-escuro com chip lima).
struct CardGlyph: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Theme.forest)
            .frame(width: 44, height: 30)
            .overlay(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 2).fill(Theme.lime)
                    .frame(width: 10, height: 8)
                    .padding(.leading, 7).padding(.top, 8)
            }
            .overlay(alignment: .bottomLeading) {
                Capsule().fill(Theme.onForestSecondary)
                    .frame(width: 26, height: 2)
                    .padding(.leading, 7).padding(.bottom, 6)
            }
            .accessibilityHidden(true)
    }
}

struct BlockedBadge: View {
    var body: some View {
        Label("Bloqueado", systemImage: "lock.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.warning)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Theme.warning.opacity(0.12), in: Capsule())
    }
}

/// Início: o cartão de crédito como parte separada da conta.
struct CreditCardHomeCard: View {
    @EnvironmentObject private var store: FinanceStore

    var body: some View {
        if let card = store.creditCards.first {
            filled(store.cardSummary(card))
        } else if store.isConfigured {
            unavailable
        }
    }

    private func filled(_ summary: FinanceStore.CardSummary) -> some View {
        let card = summary.account
        return NavigationLink(value: HomeRoute.card) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    CardGlyph()
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Cartão de crédito")
                            .font(.callout.weight(.semibold))
                        Text("\(card.institution) · separado do saldo da conta")
                            .font(.footnote)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    Spacer(minLength: 4)
                    if card.isCardBlocked { BlockedBadge() }
                }

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Fatura aberta")
                            .font(.footnote)
                            .foregroundStyle(Theme.inkSecondary)
                        MoneyText(value: summary.openBill, font: .rounded(.title2, weight: .bold))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        if let close = card.billCloseDate {
                            Text("Fecha \(FinanceStore.dayLabel(close))")
                                .font(.footnote)
                                .foregroundStyle(Theme.inkSecondary)
                        }
                        if let due = card.billDueDate {
                            Text("Vence \(FinanceStore.dayLabel(due))")
                                .font(.footnote.weight(.semibold))
                        }
                    }
                }

                if let fraction = summary.usedFraction {
                    VStack(spacing: 6) {
                        ProgressBar(fraction: fraction, fill: ChartPalette.spending, track: Theme.track, height: 8)
                        HStack {
                            HStack(spacing: 4) {
                                Text("Limite usado").foregroundStyle(Theme.inkSecondary)
                                MoneyText(value: summary.used, font: .caption.weight(.semibold))
                            }
                            Spacer()
                            HStack(spacing: 4) {
                                Text("Disponível").foregroundStyle(Theme.inkSecondary)
                                MoneyText(value: summary.available, font: .caption.weight(.semibold))
                            }
                        }
                        .font(.caption)
                    }
                }

                Divider().overlay(Theme.line)
                HStack {
                    Text("Ver fatura e parcelas")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.link)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.link)
                }
            }
            .foregroundStyle(Theme.ink)
            .card(padding: 18)
        }
        .buttonStyle(.plain)
    }

    private var unavailable: some View {
        NavigationLink(value: HomeRoute.card) {
            HStack(spacing: 12) {
                CardGlyph().opacity(0.45)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cartão de crédito")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    Text("Ainda não chega pelo Open Finance. Toque para ver o motivo.")
                        .font(.footnote)
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.inkTertiary)
            }
            .card(padding: 16)
        }
        .buttonStyle(.plain)
    }
}

/// Tela do cartão: fatura aberta, limite, parcelas futuras e faturas.
struct CreditCardView: View {
    @EnvironmentObject private var store: FinanceStore
    @EnvironmentObject private var lock: AppLock
    @State private var section: BillTab = .current
    @State private var selected: StoredTransaction?

    enum BillTab: String, CaseIterable, Identifiable {
        case current = "Fatura atual"
        case upcoming = "Próximas"
        case closed = "Fechadas"
        var id: String { rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let card = store.creditCards.first {
                    content(store.cardSummary(card))
                } else {
                    unavailable
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .background(Theme.ground.ignoresSafeArea())
        .navigationTitle("Cartão de crédito")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await store.sync() }
        .sheet(item: $selected) { transaction in
            TransactionDetailSheet(transaction: transaction)
                .environmentObject(store)
                .environmentObject(lock)
        }
    }

    // MARK: Com cartão

    @ViewBuilder
    private func content(_ summary: FinanceStore.CardSummary) -> some View {
        let card = summary.account
        if let bankAt = card.bankDataAt {
            Text("\(card.institution) · dados do banco de \(FinanceStore.bankTimeLabel(bankAt))")
                .font(.footnote)
                .foregroundStyle(Theme.inkSecondary)
                .padding(.horizontal, 4)
        }

        if card.isCardBlocked {
            Label {
                Text("**Cartão bloqueado no banco.** Compras novas não passam, mas a fatura e as parcelas continuam.")
                    .font(.footnote)
            } icon: {
                Image(systemName: "lock.fill")
            }
            .foregroundStyle(Theme.warning)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.warning.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }

        hero(summary)
        if summary.limit != nil { limitCard(summary) }
        installmentsCard(card)

        Picker("Faturas", selection: $section) {
            ForEach(BillTab.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)

        switch section {
        case .current: currentList(card)
        case .upcoming: upcomingList(card)
        case .closed: closedList(card)
        }
    }

    private func hero(_ summary: FinanceStore.CardSummary) -> some View {
        let card = summary.account
        return VStack(alignment: .leading) {
            HStack {
                RoundedRectangle(cornerRadius: 5).fill(Theme.lime).frame(width: 34, height: 26)
                    .accessibilityHidden(true)
                Spacer()
                Text("Fatura aberta")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.onForestSecondary)
            }
            Spacer()
            MoneyText(value: summary.openBill, font: .rounded(.largeTitle, weight: .bold))
                .foregroundStyle(.white)
            Text(datesLine(card))
                .font(.subheadline)
                .foregroundStyle(Theme.onForestSecondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 190, alignment: .leading)
        .background(
            ZStack(alignment: .topTrailing) {
                Theme.ink
                Circle()
                    .strokeBorder(Theme.lime.opacity(0.10), lineWidth: 28)
                    .frame(width: 200, height: 200)
                    .offset(x: 40, y: -60)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        )
        .accessibilityElement(children: .combine)
    }

    private func datesLine(_ card: StoredAccount) -> String {
        var parts: [String] = []
        if let close = card.billCloseDate { parts.append("Fecha em \(FinanceStore.dayLabel(close))") }
        if let due = card.billDueDate { parts.append("vence em \(FinanceStore.dayLabel(due))") }
        return parts.isEmpty ? "Datas da fatura não informadas pelo banco" : parts.joined(separator: " · ")
    }

    private func limitCard(_ summary: FinanceStore.CardSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Limite usado").foregroundStyle(Theme.inkSecondary)
                Spacer()
                Text("Limite total").foregroundStyle(Theme.inkSecondary)
                MoneyText(value: summary.limit, font: .footnote.weight(.semibold))
            }
            .font(.footnote)
            ProgressBar(fraction: summary.usedFraction ?? 0, fill: ChartPalette.spending, track: Theme.track, height: 10)
            HStack {
                MoneyText(value: summary.used, font: .subheadline.weight(.semibold))
                if let fraction = summary.usedFraction {
                    Text("(\(Int((fraction * 100).rounded()))%)")
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSecondary)
                }
                Spacer()
                Text("Disponível").font(.subheadline).foregroundStyle(Theme.inkSecondary)
                MoneyText(value: summary.available, font: .subheadline.weight(.semibold))
            }
        }
        .card(padding: 16)
    }

    private func installmentsCard(_ card: StoredAccount) -> some View {
        let months = store.upcomingInstallments(card)
        let hasAny = months.contains { $0.total > 0 }
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Já comprometido em parcelas")
                    .font(.subheadline.weight(.semibold))
                Text("Quanto das próximas faturas já está decidido")
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
            }
            if hasAny {
                Chart(months) { entry in
                    BarMark(
                        x: .value("Mês", Self.monthShort(entry.month)),
                        y: .value("Valor", (entry.total as NSDecimalNumber).doubleValue),
                        width: .fixed(22)
                    )
                    .foregroundStyle(ChartPalette.spending)
                    .cornerRadius(4)
                    .annotation(position: .top, spacing: 4) {
                        if entry.total > 0 && !lock.valuesHidden {
                            Text(ChartFormat.compact((entry.total as NSDecimalNumber).doubleValue))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                        }
                    }
                }
                .chartYAxis(.hidden)
                .frame(height: 140)
                .accessibilityHidden(true)
                Text("Valores em reais, só parcelas de compras já feitas.")
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
            } else {
                Text("Nenhuma compra parcelada pela frente.")
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
        .card(padding: 16)
    }

    // MARK: Listas

    @ViewBuilder
    private func currentList(_ card: StoredAccount) -> some View {
        let items = store.currentBillTransactions(card).sorted { $0.date > $1.date }
        if items.isEmpty {
            Text("Nenhuma compra nesta fatura ainda.")
                .font(.subheadline)
                .foregroundStyle(Theme.inkSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
        } else {
            listCard {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Divider().overlay(Theme.line) }
                    Button { selected = item } label: {
                        TransactionRow(transaction: item, category: store.category(for: item), accountName: nil)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func upcomingList(_ card: StoredAccount) -> some View {
        let months = store.upcomingInstallments(card)
        return listCard {
            ForEach(Array(months.enumerated()), id: \.element.id) { index, entry in
                if index > 0 { Divider().overlay(Theme.line) }
                HStack {
                    Text(entry.month.formatted(.dateTime.month(.wide).year().locale(.ptBR)).capitalized)
                        .font(.subheadline)
                    Spacer()
                    MoneyText(value: entry.total, font: .subheadline.weight(.semibold))
                }
                .padding(.vertical, 12)
            }
        }
    }

    @ViewBuilder
    private func closedList(_ card: StoredAccount) -> some View {
        let bills = store.closedBills(card)
        if bills.isEmpty {
            Text("O banco ainda não enviou faturas fechadas.")
                .font(.subheadline)
                .foregroundStyle(Theme.inkSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
        } else {
            listCard {
                ForEach(Array(bills.enumerated()), id: \.element.id) { index, bill in
                    if index > 0 { Divider().overlay(Theme.line) }
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Venceu em \(bill.dueDate.formatted(.dateTime.day(.twoDigits).month(.twoDigits).year().locale(.ptBR)))")
                                .font(.subheadline)
                            if let minimum = bill.minimumPayment {
                                HStack(spacing: 4) {
                                    Text("Mínimo")
                                    MoneyText(value: minimum, font: .caption)
                                }
                                .font(.caption)
                                .foregroundStyle(Theme.inkSecondary)
                            }
                        }
                        Spacer()
                        MoneyText(value: bill.total, font: .subheadline.weight(.semibold))
                    }
                    .padding(.vertical, 12)
                }
            }
        }
    }

    private func listCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .padding(.horizontal, 14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(Theme.line, lineWidth: Theme.hairline)
            )
    }

    // MARK: Sem cartão

    private var unavailable: some View {
        let diagnosis = store.connections.compactMap(\.creditCardDiagnosis).first
            ?? "O Pluggy não devolveu nenhum cartão nas suas conexões."
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                CardGlyph().opacity(0.45)
                Text("Seu cartão ainda não chega pelo Open Finance")
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(diagnosis)
                .font(.subheadline)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider().overlay(Theme.line)
            Text("Como resolver")
                .font(.subheadline.weight(.semibold))
            ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.caption.weight(.bold))
                        .frame(width: 22, height: 22)
                        .background(Theme.lime.opacity(0.6), in: Circle())
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 5 }
                    Text(step)
                        .font(.footnote)
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text("Faça isso enquanto o teste do painel do Pluggy estiver ativo: depois dele, não dá para criar conexões novas.")
                .font(.caption)
                .foregroundStyle(Theme.warning)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card(padding: 18)
    }

    private static let steps = [
        "No Meu Pluggy, refaça a conexão do banco e marque Cartão de crédito na autorização do Open Finance.",
        "No painel do Pluggy, autorize de novo pelo Conectar Conta, escolhendo MeuPluggy.",
        "Copie o ID da nova conexão e troque em Ajustes › Credenciais do Pluggy."
    ]

    static func monthShort(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).locale(.ptBR)).replacingOccurrences(of: ".", with: "")
    }
}
