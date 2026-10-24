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

/// "Fecha 1 nov · vence 7 nov"
@MainActor
func billDatesLine(_ summary: FinanceStore.CardSummary) -> String {
    var parts: [String] = []
    if let close = summary.nextClose { parts.append("Fecha \(FinanceStore.dayLabel(close))") }
    if let due = summary.schedule.open?.due { parts.append("vence \(FinanceStore.dayLabel(due))") }
    return parts.joined(separator: " · ")
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
                        Text(summary.openBill < 0 ? "Saldo a favor" : "Fatura atual")
                            .font(.footnote)
                            .foregroundStyle(Theme.inkSecondary)
                        MoneyText(value: abs(summary.openBill), font: .rounded(.title2, weight: .bold))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(billDatesLine(summary))
                            .font(.footnote)
                            .foregroundStyle(Theme.inkSecondary)
                        if summary.futureBills > 0 {
                            HStack(spacing: 4) {
                                Text("Próximas")
                                MoneyText(value: summary.futureBills, font: .footnote.weight(.semibold))
                            }
                            .font(.footnote)
                        }
                    }
                }

                if let fraction = summary.usedFraction {
                    VStack(spacing: 6) {
                        ProgressBar(fraction: fraction, fill: summary.isOverLimit ? Theme.danger : ChartPalette.spending,
                                    track: Theme.track, height: 8)
                        HStack {
                            HStack(spacing: 4) {
                                Text(summary.isOverLimit ? "Acima do limite" : "Limite usado")
                                    .foregroundStyle(summary.isOverLimit ? Theme.danger : Theme.inkSecondary)
                                if let percent = summary.usedPercent {
                                    Text("\(percent)%").fontWeight(.semibold)
                                }
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
                    Text("Ver faturas e parcelas")
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

/// Tela do cartão: fatura atual, próximas, limite e faturas fechadas.
struct CreditCardView: View {
    @EnvironmentObject private var store: FinanceStore
    @EnvironmentObject private var lock: AppLock
    @State private var tab: BillTab = .current
    @State private var selected: StoredTransaction?
    @State private var importing: ImportRequest?
    @State private var pickingFile = false
    @State private var importError: String?

    struct ImportRequest: Identifiable {
        let card: StoredAccount
        let file: BillFile?
        let id = UUID()
    }

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
        .sheet(item: $importing) { request in
            BillImportSheet(card: request.card, initialFile: request.file)
                .environmentObject(store)
                .environmentObject(lock)
        }
        .fileImporter(isPresented: $pickingFile, allowedContentTypes: BillFileParser.contentTypes) { outcome in
            guard let card = store.creditCards.first else { return }
            switch outcome {
            case .success(let url):
                do {
                    importing = ImportRequest(card: card, file: try BillFileParser.read(url))
                    importError = nil
                } catch {
                    importError = (error as? LocalizedError)?.errorDescription ?? BillImportError.unreadable.errorDescription
                }
            case .failure:
                importError = BillImportError.unreadable.errorDescription
            }
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
            banner("**Cartão bloqueado no banco.** Compras novas não passam, mas a fatura e as parcelas continuam.",
                   icon: "lock.fill", color: Theme.warning)
        }
        if let unpaid = summary.schedule.closedUnpaid, unpaid.total > 0 {
            banner("**Fatura de \(unpaid.monthName) fechada:** \(lock.valuesHidden ? "R$ ••••" : AgentTools.brl(unpaid.total)), vence \(FinanceStore.dayLabel(unpaid.due)).",
                   icon: "calendar.badge.exclamationmark", color: Theme.ink)
        }

        hero(summary)
        if summary.limit != nil { limitCard(summary) }
        closeDayCard(summary.schedule)
        checkCard(summary)
        Button { pickingFile = true } label: {
            Label("Importar fatura do banco (CSV ou OFX)", systemImage: "doc.badge.arrow.up")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .tint(Theme.forest)
        if let importError {
            banner(LocalizedStringKey(importError), icon: "exclamationmark.triangle", color: Theme.danger)
        }
        Text("Também dá para conferir pelo agente: toque na foto, depois em \"Conferir fatura do cartão\" e mande os prints da fatura.")
            .font(.caption)
            .foregroundStyle(Theme.inkSecondary)
            .padding(.horizontal, 4)
        upcomingChart(summary.schedule)

        Picker("Faturas", selection: $tab) {
            ForEach(BillTab.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)

        switch tab {
        case .current: cycleList(summary.schedule.open)
        case .upcoming: upcomingList(summary.schedule)
        case .closed: closedList(summary)
        }
    }

    private func banner(_ text: LocalizedStringKey, icon: String, color: Color) -> some View {
        Label {
            Text(text).font(.footnote)
        } icon: {
            Image(systemName: icon)
        }
        .foregroundStyle(color)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func hero(_ summary: FinanceStore.CardSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                RoundedRectangle(cornerRadius: 5).fill(Theme.lime).frame(width: 34, height: 26)
                    .accessibilityHidden(true)
                Spacer()
                Text(summary.openBill < 0 ? "Saldo a favor" : "Fatura atual")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.onForestSecondary)
            }
            Spacer(minLength: 18)
            // Estornos maiores que as compras deixam crédito na fatura: mostra sem o "−".
            MoneyText(value: abs(summary.openBill), font: .rounded(.largeTitle, weight: .bold))
                .foregroundStyle(.white)
            Text(billDatesLine(summary))
                .font(.subheadline)
                .foregroundStyle(Theme.onForestSecondary)
            HStack(spacing: 14) {
                HStack(spacing: 4) {
                    Text("Próximas faturas").foregroundStyle(Theme.onForestSecondary)
                    MoneyText(value: summary.futureBills, font: .footnote.weight(.semibold)).foregroundStyle(.white)
                }
                HStack(spacing: 4) {
                    Text("Total").foregroundStyle(Theme.onForestSecondary)
                    MoneyText(value: summary.totalUsed, font: .footnote.weight(.semibold)).foregroundStyle(.white)
                }
            }
            .font(.footnote)
            .padding(.top, 6)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 200, alignment: .leading)
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

    private func limitCard(_ summary: FinanceStore.CardSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(summary.isOverLimit ? "Acima do limite" : "Limite usado")
                    .foregroundStyle(summary.isOverLimit ? Theme.danger : Theme.inkSecondary)
                Spacer()
                Text("Limite total").foregroundStyle(Theme.inkSecondary)
                MoneyText(value: summary.limit, font: .footnote.weight(.semibold))
            }
            .font(.footnote)
            ProgressBar(fraction: summary.usedFraction ?? 0,
                        fill: summary.isOverLimit ? Theme.danger : ChartPalette.spending,
                        track: Theme.track, height: 10)
            HStack {
                MoneyText(value: summary.used, font: .subheadline.weight(.semibold))
                if let percent = summary.usedPercent {
                    Text("(\(percent)%)")
                        .font(.subheadline)
                        .foregroundStyle(summary.isOverLimit ? Theme.danger : Theme.inkSecondary)
                }
                Spacer()
                Text("Disponível").font(.subheadline).foregroundStyle(Theme.inkSecondary)
                MoneyText(value: summary.available, font: .subheadline.weight(.semibold))
            }
        }
        .card(padding: 16)
    }

    /// Conferência: a soma das faturas montadas no app bate com o total do banco?
    private func checkCard(_ summary: FinanceStore.CardSummary) -> some View {
        let gap = summary.unmatched
        let matches = abs(gap) < 1
        let money = { (value: Decimal) in lock.valuesHidden ? "R$ ••••" : AgentTools.brl(value) }
        return HStack(alignment: .top, spacing: 12) {
            IconTile(systemName: matches ? "checkmark.seal" : "exclamationmark.triangle", style: .neutral, size: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(matches ? "Faturas conferidas com o banco" : "Faturas não batem com o banco")
                    .font(.subheadline.weight(.medium))
                if !matches {
                    Text(gap > 0
                         ? "\(money(gap)) do total do banco (\(money(summary.totalUsed))) não entrou em nenhuma fatura."
                         : "As faturas somam \(money(-gap)) a mais que o total do banco (\(money(summary.totalUsed))).")
                        .font(.caption)
                        .foregroundStyle(Theme.warning)
                }
                Text(sourceLine(summary.schedule))
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .card(padding: 14)
    }

    private func sourceLine(_ schedule: FinanceStore.CardSchedule) -> String {
        let bank = schedule.placedByBank, byDate = schedule.placedByDate
        if bank + byDate == 0 { return "Nenhum lançamento no período." }
        if byDate == 0 { return "A fatura de cada compra veio do banco." }
        if bank == 0 { return "O banco não informou a fatura de cada compra: separadas pelo dia de fechamento." }
        return "\(bank) lançamentos com a fatura informada pelo banco e \(byDate) separados pelo dia de fechamento."
    }

    /// O banco nem sempre informa o dia de fechamento: dá para ajustar.
    private func closeDayCard(_ schedule: FinanceStore.CardSchedule) -> some View {
        HStack(spacing: 12) {
            IconTile(systemName: "calendar", style: .neutral, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("Fecha todo dia \(schedule.closeDay) · vence dia \(schedule.dueDay)")
                    .font(.subheadline.weight(.medium))
                Text(schedule.closeDayIsEstimate ? "Fechamento estimado. Ajuste se for outro dia." : "Usado para separar as faturas.")
                    .font(.caption)
                    .foregroundStyle(schedule.closeDayIsEstimate ? Theme.warning : Theme.inkSecondary)
            }
            Spacer(minLength: 4)
            Menu {
                Picker("Dia do fechamento", selection: Binding(
                    get: { schedule.closeDay },
                    set: { store.setCardCloseDay($0, for: schedule.card.id) }
                )) {
                    ForEach(1...31, id: \.self) { Text("Dia \($0)").tag($0) }
                }
            } label: {
                Text("Ajustar")
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
            }
        }
        .card(padding: 14)
    }

    private func upcomingChart(_ schedule: FinanceStore.CardSchedule) -> some View {
        let upcoming = Array(schedule.upcoming.prefix(6))
        let hasAny = upcoming.contains { $0.total > 0 }
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Próximas faturas")
                    .font(.subheadline.weight(.semibold))
                Text("O que já está comprometido, por mês de vencimento")
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
            }
            if hasAny {
                Chart(upcoming) { cycle in
                    BarMark(
                        x: .value("Mês", Self.monthShort(cycle.due)),
                        y: .value("Valor", (cycle.total as NSDecimalNumber).doubleValue),
                        width: .fixed(22)
                    )
                    .foregroundStyle(ChartPalette.spending)
                    .cornerRadius(4)
                    .annotation(position: .top, spacing: 4) {
                        if cycle.total > 0 && !lock.valuesHidden {
                            Text(ChartFormat.compact((cycle.total as NSDecimalNumber).doubleValue))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                        }
                    }
                }
                .chartYAxis(.hidden)
                .frame(height: 140)
                .accessibilityHidden(true)
            } else {
                Text("Nenhuma parcela pela frente.")
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
        .card(padding: 16)
    }

    // MARK: Listas

    @ViewBuilder
    private func cycleList(_ cycle: FinanceStore.BillCycle?) -> some View {
        if let cycle, !(cycle.transactions.isEmpty && cycle.projected.isEmpty) {
            BillItemsList(cycle: cycle) { selected = $0 }
        } else {
            Text("Nenhuma compra nesta fatura ainda.")
                .font(.subheadline)
                .foregroundStyle(Theme.inkSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
        }
    }

    private func upcomingList(_ schedule: FinanceStore.CardSchedule) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            listCard {
                // Até 6 meses sempre; depois disso, só os meses que têm parcela.
                let shown = schedule.upcoming.enumerated().filter { $0.offset < 6 || $0.element.total != 0 }.map(\.element)
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, cycle in
                    if index > 0 { Divider().overlay(Theme.line) }
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Fatura de \(cycle.monthName)")
                                .font(.subheadline)
                            Text("vence \(FinanceStore.dayLabel(cycle.due)) · \(cycle.transactions.count + cycle.projected.count) lançamentos")
                                .font(.caption)
                                .foregroundStyle(Theme.inkSecondary)
                        }
                        Spacer()
                        MoneyText(value: cycle.total, font: .subheadline.weight(.semibold))
                    }
                    .padding(.vertical, 12)
                }
            }
            Text("Os lançamentos de cada fatura estão em Transações › Cartão.")
                .font(.caption)
                .foregroundStyle(Theme.inkTertiary)
                .padding(.horizontal, 4)
        }
    }

    @ViewBuilder
    private func closedList(_ summary: FinanceStore.CardSummary) -> some View {
        let bills = store.closedBills(summary.account)
        if !bills.isEmpty {
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
        } else {
            // Sem faturas do banco: as fechadas montadas pelo app.
            listCard {
                ForEach(Array(summary.schedule.closed.enumerated()), id: \.element.id) { index, cycle in
                    if index > 0 { Divider().overlay(Theme.line) }
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Fatura de \(cycle.monthName)")
                                .font(.subheadline)
                            Text("venceu \(FinanceStore.dayLabel(cycle.due)) · calculada pelo app")
                                .font(.caption)
                                .foregroundStyle(Theme.inkSecondary)
                        }
                        Spacer()
                        MoneyText(value: cycle.total, font: .subheadline.weight(.semibold))
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

/// Lançamentos de uma fatura: compras (por dia) e parcelas previstas pelo app.
struct BillItemsList: View {
    @EnvironmentObject private var store: FinanceStore
    /// Mostra, em cada compra, o que o banco informou (para conferir a fatura).
    @AppStorage("card.bankDetails") private var bankDetails = false
    let cycle: FinanceStore.BillCycle
    var query = ""
    let onSelect: (StoredTransaction) -> Void

    private var items: [StoredTransaction] {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return cycle.transactions }
        return cycle.transactions.filter {
            $0.title.localizedStandardContains(text) || store.category(for: $0).name.localizedStandardContains(text)
        }
    }

    /// Compras repetidas na mesma fatura (mesmo nome, valor e parcela).
    private var duplicates: Set<String> {
        var seen: [String: String] = [:]
        var result = Set<String>()
        for item in cycle.transactions {
            let key = "\(item.title.lowercased())|\(item.amount)|\(item.installment ?? "-")"
            if let first = seen[key] { result.insert(first); result.insert(item.id) } else { seen[key] = item.id }
        }
        return result
    }

    /// "data 12/10 · parcela 2/3 · banco: fatura 2026-12 · pendente"
    static func bankLine(_ item: StoredTransaction, duplicated: Bool) -> String {
        var parts = ["data " + item.date.formatted(.dateTime.day(.twoDigits).month(.twoDigits).year(.twoDigits).locale(.ptBR))]
        if let installment = item.installment { parts.append("parcela \(installment)") }
        parts.append("banco: " + (item.billMonth.map { "fatura \($0)" } ?? "sem previsão"))
        if item.billId != nil { parts.append("já lançada") }
        parts.append(item.isPending ? "pendente" : "confirmada")
        if duplicated { parts.append("REPETIDA?") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Mostrar o que o banco informou", isOn: $bankDetails)
                .font(.footnote)
                .tint(Theme.forest)
                .padding(.horizontal, 4)
            if !items.isEmpty {
                ForEach(DaySection.make(from: items)) { section in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(section.title)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.inkTertiary)
                            .padding(.horizontal, 4)
                        VStack(spacing: 0) {
                            ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                                if index > 0 { Divider().overlay(Theme.line) }
                                Button { onSelect(item) } label: {
                                    VStack(alignment: .leading, spacing: 0) {
                                        TransactionRow(transaction: item, category: store.category(for: item), accountName: nil)
                                        if bankDetails {
                                            Text(Self.bankLine(item, duplicated: duplicates.contains(item.id)))
                                                .font(.caption2.monospacedDigit())
                                                .foregroundStyle(duplicates.contains(item.id) ? Theme.danger : Theme.inkTertiary)
                                                .padding(.bottom, 8)
                                        }
                                    }
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
            if !cycle.projected.isEmpty && query.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Parcelas previstas (o banco ainda não mandou)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.inkTertiary)
                        .padding(.horizontal, 4)
                    VStack(spacing: 0) {
                        ForEach(Array(cycle.projected.enumerated()), id: \.element.id) { index, item in
                            if index > 0 { Divider().overlay(Theme.line) }
                            HStack(spacing: 12) {
                                IconTile(systemName: "calendar.badge.clock", style: .neutral, size: 36)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(.subheadline.weight(.medium))
                                        .lineLimit(1)
                                    Text("Parcela \(item.installment) · prevista")
                                        .font(.caption)
                                        .foregroundStyle(Theme.inkSecondary)
                                }
                                Spacer(minLength: 6)
                                SignedMoneyText(amount: item.amount)
                            }
                            .padding(.vertical, 12)
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
    }
}
