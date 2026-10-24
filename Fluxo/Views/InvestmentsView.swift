import SwiftUI

/// Aba Investimentos › Minha carteira: o que você já tem, vindo do Open Finance.
struct InvestmentsView: View {
    @EnvironmentObject private var store: FinanceStore
    @EnvironmentObject private var lock: AppLock
    @State private var showWithdrawn = false

    var body: some View {
        Screen("Investimentos") {
            if let bankAt = store.bankDataAt {
                Text("Dados do banco de \(FinanceStore.bankTimeLabel(bankAt))")
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSecondary)
                    .padding(.horizontal, 4)
            }

            if store.investments.isEmpty {
                EmptyStateView(
                    systemName: "chart.line.uptrend.xyaxis",
                    title: store.state == .loading ? "Buscando seus investimentos…" : "Nenhum investimento encontrado",
                    message: "Os investimentos chegam pela mesma conexão do Open Finance. Puxe para baixo para sincronizar."
                )
            } else {
                hero
                if store.investmentAllocation.count > 0 { allocationCard }

                Picker("Situação", selection: $showWithdrawn) {
                    Text("Ativos · \(store.activeInvestments.count)").tag(false)
                    Text("Resgatados · \(store.withdrawnInvestments.count)").tag(true)
                }
                .pickerStyle(.segmented)

                let list = showWithdrawn ? store.withdrawnInvestments : store.activeInvestments
                if list.isEmpty {
                    Text(showWithdrawn ? "Nenhum investimento resgatado." : "Nenhum investimento ativo.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card()
                } else {
                    ForEach(list) { InvestmentCard(investment: $0) }
                }

                Text("Taxa, vencimento e rendimento são os que o banco informa pelo Open Finance. O agente também responde sobre a sua carteira.")
                    .font(.caption)
                    .foregroundStyle(Theme.inkTertiary)
                    .padding(.horizontal, 4)
            }
        }
        .refreshable { await store.sync() }
        .task { await store.syncIfStale() }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Total investido")
                .font(.subheadline)
                .foregroundStyle(Theme.onForestSecondary)
            MoneyText(value: store.investedTotal, font: .rounded(.largeTitle, weight: .bold))
                .foregroundStyle(.white)
            if let profit = store.investmentsLastMonthProfit {
                HStack(spacing: 4) {
                    Text("Rendeu no último mês ≈")
                        .foregroundStyle(Theme.onForestSecondary)
                    MoneyText(value: profit, font: .subheadline.weight(.semibold))
                        .foregroundStyle(Theme.lime)
                }
                .font(.subheadline)
                .padding(.top, 4)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.forest, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// Barra empilhada + legenda com % e valor (a cor nunca é a única pista).
    private var allocationCard: some View {
        let parts = store.investmentAllocation
        let total = parts.reduce(Decimal(0)) { $0 + $1.value }
        let shares = parts.map { total > 0 ? ($0.value as NSDecimalNumber).doubleValue / (total as NSDecimalNumber).doubleValue : 0 }

        return VStack(alignment: .leading, spacing: 12) {
            Text("Onde está o dinheiro")
                .font(.subheadline.weight(.semibold))
            GeometryReader { proxy in
                let gaps = CGFloat(max(parts.count - 1, 0)) * 2
                HStack(spacing: 2) {
                    ForEach(Array(parts.enumerated()), id: \.offset) { index, _ in
                        Rectangle()
                            .fill(ChartPalette.color(for: index < 5 ? index : nil))
                            .frame(width: max((proxy.size.width - gaps) * shares[index], 2))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            .frame(height: 12)
            .accessibilityHidden(true)

            VStack(spacing: 8) {
                ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 2.5)
                            .fill(ChartPalette.color(for: index < 5 ? index : nil))
                            .frame(width: 10, height: 10)
                        Text(part.label)
                            .font(.footnote)
                        Spacer()
                        Text(ChartFormat.percent(shares[index]))
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(Theme.inkSecondary)
                        MoneyText(value: part.value, font: .footnote.weight(.semibold))
                            .frame(minWidth: 84, alignment: .trailing)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .card(padding: 16)
    }
}

private struct InvestmentCard: View {
    let investment: StoredInvestment

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                IconTile(systemName: "building.columns", style: .neutral, size: 40)
                VStack(alignment: .leading, spacing: 5) {
                    Text(investment.name)
                        .font(.callout.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        chip("\(investment.familyLabel) · \(investment.kindLabel)", tint: Theme.link)
                        if let rate = investment.rateLabel { chip(rate, tint: Theme.inkSecondary) }
                    }
                }
                Spacer(minLength: 4)
                MoneyText(value: investment.balance, font: .rounded(.callout, weight: .bold))
            }
            Divider().overlay(Theme.line)
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(investment.dueDate == nil ? "Vencimento" : "Vence em")
                        .font(.caption)
                        .foregroundStyle(Theme.inkSecondary)
                    Text(investment.dueDate.map { $0.formatted(.dateTime.day(.twoDigits).month(.twoDigits).year().locale(.ptBR)) } ?? "Não informado")
                        .font(.subheadline.weight(.medium))
                }
                Spacer()
                if let rate = investment.lastMonthRate {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("No último mês")
                            .font(.caption)
                            .foregroundStyle(Theme.inkSecondary)
                        Text("\(rate >= 0 ? "+" : "")\(rate.formatted(.number.precision(.fractionLength(2)).locale(.ptBR)))%")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(rate >= 0 ? Theme.positive : Theme.danger)
                    }
                } else if let issuer = investment.issuer, !issuer.isEmpty {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("Emissor")
                            .font(.caption)
                            .foregroundStyle(Theme.inkSecondary)
                        Text(issuer)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                    }
                }
            }
        }
        .card(padding: 16)
        .accessibilityElement(children: .combine)
    }

    private func chip(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.10), in: Capsule())
            .lineLimit(1)
    }
}
