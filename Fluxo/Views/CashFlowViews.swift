import SwiftUI
import Charts

/// Início: resumo dos próximos 30 dias com um mini gráfico.
struct CashFlowPreviewCard: View {
    @EnvironmentObject private var store: FinanceStore
    @EnvironmentObject private var lock: AppLock

    var body: some View {
        if let projection = store.projectCashFlow() {
            NavigationLink(value: HomeRoute.cashFlow) {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Próximos 30 dias")
                            .font(.footnote)
                            .foregroundStyle(Theme.inkSecondary)
                        Text(headline(projection))
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(projection.goesNegative ? Theme.danger : Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(detail(projection))
                            .font(.footnote)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    Spacer(minLength: 4)
                    Chart(projection.daily) { point in
                        LineMark(x: .value("Dia", point.date), y: .value("Saldo", (point.balance as NSDecimalNumber).doubleValue))
                            .interpolationMethod(.stepEnd)
                            .foregroundStyle(projection.goesNegative ? Theme.danger : ChartPalette.income)
                            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .frame(width: 104, height: 44)
                    .accessibilityHidden(true)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.inkTertiary)
                }
                .card(padding: 16)
            }
            .buttonStyle(.plain)
        }
    }

    private func headline(_ p: FinanceStore.CashFlowProjection) -> String {
        if let first = p.firstNegative {
            return "Saldo pode ficar negativo em \(FinanceStore.dayLabel(first))"
        }
        return "Dia mais apertado: \(FinanceStore.dayLabel(p.minDate))"
    }

    private func detail(_ p: FinanceStore.CashFlowProjection) -> String {
        if lock.valuesHidden { return "Toque para ver a projeção" }
        return "Saldo previsto: \(AgentTools.brl(p.minBalance))"
    }
}

/// Tela do fluxo de caixa: projeção, movimentos e recorrentes.
struct CashFlowView: View {
    @EnvironmentObject private var store: FinanceStore
    @EnvironmentObject private var lock: AppLock

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let projection = store.projectCashFlow() {
                    hero(projection)
                    chartCard(projection)
                    eventsSection(projection)
                } else {
                    EmptyStateView(
                        systemName: "chart.xyaxis.line",
                        title: "Sem saldo para projetar",
                        message: "Assim que o saldo da conta chegar do banco, a projeção aparece aqui."
                    )
                }
                recurringSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .background(Theme.ground.ignoresSafeArea())
        .navigationTitle("Fluxo de caixa")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Destaque

    private func hero(_ p: FinanceStore.CashFlowProjection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(p.goesNegative ? "VAI FALTAR" : "TUDO CERTO")
                .font(.caption.weight(.bold))
                .tracking(0.3)
                .foregroundStyle(p.goesNegative ? Color(hex: 0x5C1A0A) : Theme.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(p.goesNegative ? Color(hex: 0xFFB4A0) : Theme.lime, in: Capsule())
            Text(headline(p))
                .font(.rounded(.title2, weight: .bold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text(advice(p))
                .font(.subheadline)
                .foregroundStyle(Theme.onForestSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.forest, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func headline(_ p: FinanceStore.CashFlowProjection) -> String {
        if let first = p.firstNegative, let last = p.lastNegative {
            return first == last
                ? "Saldo negativo em \(FinanceStore.dayLabel(first))"
                : "Saldo negativo de \(FinanceStore.dayLabel(first)) a \(FinanceStore.dayLabel(last))"
        }
        if lock.valuesHidden { return "Dia mais apertado: \(FinanceStore.dayLabel(p.minDate))" }
        return "Dia mais apertado: \(FinanceStore.dayLabel(p.minDate)) · \(AgentTools.brl(p.minBalance))"
    }

    private func advice(_ p: FinanceStore.CashFlowProjection) -> String {
        if p.goesNegative {
            let low = lock.valuesHidden ? "" : "Chega a \(AgentTools.brl(p.minBalance)). "
            return low + (p.suggestion ?? "")
        }
        let end = p.daily.last?.date ?? .now
        let value = lock.valuesHidden ? "" : ": \(AgentTools.brl(p.endBalance))"
        return "O saldo fica positivo nos próximos 30 dias. Sobra prevista em \(FinanceStore.dayLabel(end))\(value)."
    }

    // MARK: Gráfico

    private func chartCard(_ p: FinanceStore.CashFlowProjection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Saldo previsto dia a dia")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("hoje → \(FinanceStore.dayLabel(p.daily.last?.date ?? .now))")
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
            }
            Chart {
                ForEach(p.daily) { point in
                    AreaMark(x: .value("Dia", point.date), y: .value("Saldo", Self.double(point.balance)))
                        .interpolationMethod(.stepEnd)
                        .foregroundStyle(ChartPalette.income.opacity(0.10))
                    LineMark(x: .value("Dia", point.date), y: .value("Saldo", Self.double(point.balance)))
                        .interpolationMethod(.stepEnd)
                        .foregroundStyle(ChartPalette.income)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
                if p.goesNegative {
                    RuleMark(y: .value("Zero", 0))
                        .foregroundStyle(Theme.danger)
                        .lineStyle(StrokeStyle(lineWidth: 1))
                }
                PointMark(x: .value("Dia", p.minDate), y: .value("Saldo", Self.double(p.minBalance)))
                    .foregroundStyle(p.minBalance < 0 ? Theme.danger : ChartPalette.income)
                    .symbolSize(70)
                    .annotation(position: .top, spacing: 6) {
                        if !lock.valuesHidden {
                            Text("mín. \(AgentTools.brl(p.minBalance))")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 10)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let date = value.as(Date.self) { Text(FinanceStore.dayLabel(date)) }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let amount = value.as(Double.self) {
                            Text(lock.valuesHidden ? "•••" : ChartFormat.compact(amount))
                        }
                    }
                }
            }
            .frame(height: 180)
            .accessibilityHidden(true)
        }
        .card(padding: 16)
    }

    // MARK: Movimentos

    @ViewBuilder
    private func eventsSection(_ p: FinanceStore.CashFlowProjection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Próximos movimentos")
                .font(.headline)
                .padding(.horizontal, 4)
            if p.events.isEmpty {
                Text("Nada previsto para os próximos 30 dias. Recorrentes, gastos previstos e a fatura do cartão aparecem aqui.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(p.events.enumerated()), id: \.element.id) { index, event in
                        if index > 0 { Divider().overlay(Theme.line) }
                        HStack(spacing: 12) {
                            VStack(spacing: 0) {
                                Text(event.date.formatted(.dateTime.day().locale(.ptBR)))
                                    .font(.callout.weight(.bold))
                                Text(CreditCardView.monthShort(event.date))
                                    .font(.caption2)
                                    .foregroundStyle(Theme.inkSecondary)
                            }
                            .frame(width: 40)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(event.title)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                Text(event.kindLabel)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(Theme.inkSecondary)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(Theme.track, in: Capsule())
                            }
                            Spacer(minLength: 6)
                            VStack(alignment: .trailing, spacing: 2) {
                                SignedMoneyText(amount: event.amount)
                                HStack(spacing: 3) {
                                    Text("saldo:")
                                    MoneyText(value: event.balanceAfter, font: .caption2)
                                }
                                .font(.caption2)
                                .foregroundStyle(event.balanceAfter < 0 ? Theme.danger : Theme.inkSecondary)
                            }
                        }
                        .padding(.vertical, 11)
                    }
                }
                .padding(.horizontal, 14)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                        .strokeBorder(Theme.line, lineWidth: Theme.hairline)
                )
            }
            Text("Compras no cartão não mexem no saldo no dia: entram juntas no vencimento da fatura.")
                .font(.caption)
                .foregroundStyle(Theme.inkTertiary)
                .padding(.horizontal, 4)
        }
    }

    // MARK: Recorrentes

    private var recurringSection: some View {
        let all = store.detectRecurring()
        let confirmed = all.filter { !$0.isCandidate }
        let candidates = all.filter(\.isCandidate)
        let monthly = confirmed.filter { !$0.isIncome }.reduce(Decimal(0)) { $0 - $1.amount }

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recorrentes detectados")
                    .font(.headline)
                Spacer()
                if monthly > 0 && !lock.valuesHidden {
                    Text("\(AgentTools.brl(monthly))/mês · \(AgentTools.brl(monthly * 12))/ano")
                        .font(.caption)
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            .padding(.horizontal, 4)

            if all.isEmpty {
                Text("Ainda não há padrão suficiente. Um gasto vira recorrente depois de aparecer 3 meses seguidos.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(confirmed.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Divider().overlay(Theme.line) }
                        RecurringRow(item: item)
                            .contextMenu {
                                Button(role: .destructive) {
                                    store.setRecurringDecision(item.id, isRecurring: false)
                                } label: {
                                    Label("Não é recorrente", systemImage: "xmark.circle")
                                }
                            }
                    }
                    ForEach(candidates) { item in
                        if !confirmed.isEmpty || item.id != candidates.first?.id { Divider().overlay(Theme.line) }
                        VStack(alignment: .leading, spacing: 8) {
                            RecurringRow(item: item)
                            HStack(spacing: 8) {
                                Text("Padrão novo: é recorrente?")
                                    .font(.caption)
                                    .foregroundStyle(Theme.inkSecondary)
                                Spacer()
                                Button("Ignorar") { store.setRecurringDecision(item.id, isRecurring: false) }
                                    .font(.footnote.weight(.medium))
                                    .frame(minHeight: 36)
                                Button {
                                    store.setRecurringDecision(item.id, isRecurring: true)
                                } label: {
                                    Text("Confirmar")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(Theme.ink)
                                        .padding(.horizontal, 12)
                                        .frame(minHeight: 36)
                                        .background(Theme.lime.opacity(0.35), in: Capsule())
                                        .overlay(Capsule().strokeBorder(Theme.lime, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.bottom, 10)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                        .strokeBorder(Theme.line, lineWidth: Theme.hairline)
                )
                Text("Detectados pelo app: mesmo nome, valor parecido e cerca de 1 mês entre um e outro, por 3 meses. Toque e segure para dizer que não é.")
                    .font(.caption)
                    .foregroundStyle(Theme.inkTertiary)
                    .padding(.horizontal, 4)
            }
        }
    }

    static func double(_ value: Decimal) -> Double {
        (value as NSDecimalNumber).doubleValue
    }
}

private struct RecurringRow: View {
    let item: FinanceStore.Recurring

    private var initials: String {
        String(item.name.split(separator: " ").prefix(2).compactMap(\.first)).uppercased()
    }

    private var meta: String {
        let day = Calendar.current.component(.day, from: item.nextDate)
        let when = item.varies ? "por volta do dia \(day)" : "todo dia \(day)"
        return "\(item.origin.label) · \(when)"
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(initials)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.inkSecondary)
                .frame(width: 36, height: 36)
                .background(Theme.track, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Circle()
                        .fill(item.origin == .account ? ChartPalette.income : ChartPalette.spending)
                        .frame(width: 7, height: 7)
                    Text(meta)
                }
                .font(.caption)
                .foregroundStyle(Theme.inkSecondary)
                if let before = item.priceIncrease {
                    HStack(spacing: 3) {
                        Text("Subiu de")
                        MoneyText(value: before, font: .caption2.weight(.semibold))
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.warning)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Theme.warning.opacity(0.12), in: Capsule())
                }
            }
            Spacer(minLength: 6)
            HStack(spacing: 2) {
                if item.varies { Text("≈").font(.subheadline) }
                SignedMoneyText(amount: item.amount)
            }
        }
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
    }
}
