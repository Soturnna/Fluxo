import SwiftUI

/// O que está sendo editado na folha de orçamento.
enum BudgetEditorTarget: Identifiable {
    case newBudget
    case budget(String)   // id da categoria
    case monthlyLimit

    var id: String {
        switch self {
        case .newBudget: return "novo"
        case .budget(let id): return "categoria-\(id)"
        case .monthlyLimit: return "limite-geral"
        }
    }
}

/// Orçamentos do mês: quanto ainda dá para gastar e como está cada categoria.
struct BudgetsView: View {
    @EnvironmentObject private var store: FinanceStore
    @EnvironmentObject private var lock: AppLock
    @State private var month = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
    @State private var editing: BudgetEditorTarget?
    @State private var managingCategories = false

    private var isCurrentMonth: Bool {
        Calendar.current.isDate(month, equalTo: .now, toGranularity: .month)
    }

    var body: some View {
        Screen("Orçamentos") {
            monthSwitcher
            overviewCard
            if store.userData.budgets.isEmpty {
                EmptyStateView(
                    systemName: "chart.pie",
                    title: "Nenhum orçamento ainda",
                    message: "Defina limites por categoria. O Fluxo sugere um valor com base na sua média dos últimos 3 meses.",
                    actionTitle: "Criar primeiro orçamento",
                    action: { editing = .newBudget }
                )
            } else {
                budgetList
                actionButtons
            }
        }
        .refreshable { await store.sync() }
        .task { await store.syncIfStale() }
        .sheet(item: $editing) { target in
            BudgetEditorSheet(target: target)
                .environmentObject(store)
                .environmentObject(lock)
        }
        .sheet(isPresented: $managingCategories) {
            NavigationStack {
                CategoriesView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Fechar") { managingCategories = false }
                        }
                    }
            }
            .environmentObject(store)
            .environmentObject(lock)
            .tint(Theme.link)
        }
    }

    // MARK: Mês

    private var monthSwitcher: some View {
        HStack {
            Button { shiftMonth(by: -1) } label: {
                Image(systemName: "chevron.left").frame(width: 44, height: 44)
            }
            .accessibilityLabel("Mês anterior")
            Spacer()
            Text(month.formatted(.dateTime.month(.wide).year().locale(.ptBR)).capitalized)
                .font(.headline)
            Spacer()
            Button { shiftMonth(by: 1) } label: {
                Image(systemName: "chevron.right").frame(width: 44, height: 44)
            }
            .disabled(isCurrentMonth)
            .accessibilityLabel("Próximo mês")
        }
        .font(.body.weight(.medium))
        .foregroundStyle(Theme.ink)
    }

    // MARK: Resumo

    private var overviewCard: some View {
        let spent = store.totals(inMonthOf: month).spent
        let limit = store.userData.effectiveMonthlyLimit
        let daysLeft = store.daysLeft(inMonthOf: month)
        let planned = store.pendingPlannedTotal(inMonthOf: month)

        return VStack(alignment: .leading, spacing: 10) {
            if let limit {
                let free = limit - spent - planned
                Text(free >= 0 ? (isCurrentMonth ? "Livre para gastar" : "Sobrou no mês") : "Acima do limite")
                    .font(.subheadline)
                    .foregroundStyle(Theme.onForestSecondary)
                MoneyText(value: abs(free), font: .rounded(.largeTitle, weight: .bold))
                    .foregroundStyle(.white)
                ProgressBar(fraction: Self.fraction(spent + planned, of: limit), fill: free >= 0 ? Theme.lime : Theme.dangerSoft, track: .white.opacity(0.16))
                Text(overviewCaption(spent: spent, planned: planned, limit: limit, free: free, daysLeft: daysLeft))
                    .font(.footnote)
                    .foregroundStyle(Theme.onForestSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Gasto no mês")
                    .font(.subheadline)
                    .foregroundStyle(Theme.onForestSecondary)
                MoneyText(value: spent, font: .rounded(.largeTitle, weight: .bold))
                    .foregroundStyle(.white)
                Text("Defina orçamentos para ver quanto ainda pode gastar.")
                    .font(.footnote)
                    .foregroundStyle(Theme.onForestSecondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.forest, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func overviewCaption(spent: Decimal, planned: Decimal, limit: Decimal, free: Decimal, daysLeft: Int) -> String {
        if lock.valuesHidden { return "Valores ocultos" }
        var parts = ["\(Self.brl(spent)) de \(Self.brl(limit))"]
        if planned > 0 { parts.append("\(Self.brl(planned)) previstos") }
        if daysLeft > 0 {
            parts.append(daysLeft == 1 ? "último dia" : "faltam \(daysLeft) dias")
            if free > 0 {
                let perDay = Money.decimal(from: (free as NSDecimalNumber).doubleValue / Double(daysLeft))
                parts.append("\(Self.brl(perDay)) por dia")
            }
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Lista

    private var budgetList: some View {
        let items = store.progress(inMonthOf: month)
        let unbudgeted = store.unbudgetedSpending(inMonthOf: month)

        return VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 { Divider().overlay(Theme.line) }
                Button {
                    editing = .budget(item.budget.categoryId)
                } label: {
                    BudgetRow(progress: item)
                }
                .buttonStyle(.plain)
            }
            if unbudgeted > 0 {
                Divider().overlay(Theme.line)
                HStack(spacing: 12) {
                    IconTile(systemName: "ellipsis", style: .neutral, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sem orçamento")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.ink)
                        Text("Categorias sem limite definido")
                            .font(.caption)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    Spacer(minLength: 8)
                    MoneyText(value: unbudgeted, font: .rounded(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                }
                .padding(.vertical, 12)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, 14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(Theme.line, lineWidth: Theme.hairline)
        )
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            Button {
                editing = .newBudget
            } label: {
                Label("Novo orçamento", systemImage: "plus")
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(LimeButtonStyle())
            .disabled(store.allCategories.filter { $0.kind == .expense }.allSatisfy { category in
                store.userData.budgets.contains { $0.categoryId == category.id }
            })

            Button {
                editing = .monthlyLimit
            } label: {
                Text(store.userData.monthlyLimit == nil ? "Definir um limite geral do mês" : "Editar limite geral do mês")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }

            Button {
                managingCategories = true
            } label: {
                Text("Gerenciar categorias")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
    }

    // MARK: Apoio

    private func shiftMonth(by value: Int) {
        if let next = Calendar.current.date(byAdding: .month, value: value, to: month) {
            month = next
        }
    }

    static func fraction(_ spent: Decimal, of limit: Decimal) -> Double {
        guard limit > 0 else { return spent > 0 ? 1 : 0 }
        let value = (spent as NSDecimalNumber).doubleValue / (limit as NSDecimalNumber).doubleValue
        return min(max(value, 0), 1)
    }

    static func brl(_ value: Decimal) -> String {
        value.formatted(.currency(code: "BRL").locale(.ptBR))
    }
}

/// Barra de progresso simples, desenhada (não informa nada só pela cor).
struct ProgressBar: View {
    let fraction: Double
    var fill: Color = Theme.forest
    var track: Color = Theme.track
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule()
                    .fill(fill)
                    .frame(width: max(proxy.size.width * fraction, fraction > 0 ? height : 0))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// Uma linha de orçamento: categoria, gasto de limite, barra e situação.
private struct BudgetRow: View {
    @EnvironmentObject private var lock: AppLock
    let progress: BudgetProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                IconTile(systemName: progress.category.icon, style: tileStyle, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(progress.category.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.ink)
                    Text(amountLine)
                        .font(.caption)
                        .foregroundStyle(Theme.inkSecondary)
                        .monospacedDigit()
                }
                Spacer(minLength: 8)
                Text("\(progress.percent)%")
                    .font(.rounded(.subheadline, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(levelColor)
            }
            ProgressBar(fraction: progress.fraction, fill: barColor)
            statusLine
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Toque para editar o orçamento")
    }

    private var amountLine: String {
        if lock.valuesHidden { return "R$ •••• de R$ ••••" }
        return "\(BudgetsView.brl(progress.spent)) de \(BudgetsView.brl(progress.budget.limit))"
    }

    @ViewBuilder
    private var statusLine: some View {
        switch progress.level {
        case .over:
            Label(lock.valuesHidden ? "Passou do limite" : "Passou \(BudgetsView.brl(-progress.remaining)) do limite",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.danger)
        case .near:
            Label(lock.valuesHidden ? "Quase no limite" : "Quase no limite · \(BudgetsView.brl(progress.remaining)) livres",
                  systemImage: "exclamationmark.circle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.warning)
        case .ok:
            Text(lock.valuesHidden ? "Dentro do limite" : "\(BudgetsView.brl(progress.remaining)) livres")
                .font(.caption)
                .foregroundStyle(Theme.inkSecondary)
        }
    }

    private var tileStyle: IconTile.Style {
        progress.level == .over ? .danger : .security
    }

    private var levelColor: Color {
        switch progress.level {
        case .over: return Theme.danger
        case .near: return Theme.warning
        case .ok: return Theme.ink
        }
    }

    private var barColor: Color {
        switch progress.level {
        case .over: return Color(hex: 0xB3401F)
        case .near: return Color(hex: 0xC98A12)
        case .ok: return Theme.forest
        }
    }
}
