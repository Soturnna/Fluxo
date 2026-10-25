import Foundation
import WidgetKit

/// Lado do app: monta o resumo dos widgets a partir do cofre (já aberto) e grava
/// na pasta compartilhada. Sem "Mostrar valores", nenhum valor em reais nem nome
/// sai do cofre: o arquivo de valores nem existe.
@MainActor
enum WidgetBridge {
    /// Último grupo usado, para o diagnóstico em Ajustes.
    private(set) static var lastGroup: String?

    static var showValues: Bool { UserDefaults.standard.bool(forKey: SettingsKey.widgetShowValues) }

    static func refresh(_ store: FinanceStore) {
        let (info, values) = makeData(store, showValues: showValues)
        lastGroup = WidgetShared.write(info, values: values)
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func clear() {
        WidgetShared.removeAll()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Monta as duas partes (pública e de valores). Separado para os testes.
    static func makeData(_ store: FinanceStore, showValues: Bool, now: Date = .now)
        -> (WidgetShared.PublicData, WidgetShared.Values?) {
        let calendar = Calendar.current
        let balance = store.estimatedBalance?.value ?? store.bankBalance
        let card = store.creditCards.first.map { store.cardSummary($0) }

        // Mês: gasto × orçamento e ritmo.
        let month = store.totals(inMonthOf: now)
        let budget = store.userData.effectiveMonthlyLimit
        let budgetFraction = budget.flatMap { $0 > 0 ? ratio(month.spent, $0) : nil }
        let daysInMonth = calendar.range(of: .day, in: .month, for: now)?.count ?? 30
        let today = calendar.component(.day, from: now)
        let elapsed = Double(today) / Double(daysInMonth)
        let paceAlert = (budgetFraction ?? 0) > elapsed + 0.05 && (budgetFraction ?? 0) > 0.2

        // Próximos 30 dias.
        let projection = store.projectCashFlow()
        let start = calendar.startOfDay(for: now)
        let upcoming = (projection?.events ?? []).filter { $0.date >= start }.prefix(2)
        let sparkline = projection.map { normalized($0.daily.map(\.balance)) } ?? []

        let info = WidgetShared.PublicData(
            updatedAt: now,
            hasBank: balance != nil || card != nil,
            hasCard: card != nil,
            showValues: showValues,
            billDue: card?.nextDue,
            cardOverLimit: card?.isOverLimit ?? false,
            cardUsedFraction: card?.usedFraction,
            monthName: now.formatted(.dateTime.month(.wide).locale(.ptBR)),
            budgetFraction: budgetFraction,
            daysLeftInMonth: max(daysInMonth - today, 0),
            paceAlert: paceAlert,
            tightestDay: projection?.minDate,
            goesNegative: projection?.goesNegative ?? false,
            sparkline: sparkline,
            pendingCount: store.pendingProvisionals.count,
            nextEvents: upcoming.map { .init(date: $0.date, kind: kind($0.kind), isIncome: $0.amount > 0) }
        )
        guard showValues else { return (info, nil) }

        let values = WidgetShared.Values(
            balance: balance,
            bill: card?.openBill,
            spent: month.spent,
            budget: budget,
            accountSpent: store.totals(inMonthOf: now, origin: .account).spent,
            cardSpent: store.totals(inMonthOf: now, origin: .card).spent,
            lowestBalance: projection?.minBalance,
            events: upcoming.map { .init(title: String($0.title.prefix(40)), amount: $0.amount) }
        )
        return (info, values)
    }

    private static func ratio(_ a: Decimal, _ b: Decimal) -> Double {
        (a as NSDecimalNumber).doubleValue / (b as NSDecimalNumber).doubleValue
    }

    /// Só o formato da curva (0…1), sem valores. No máximo 31 pontos.
    static func normalized(_ values: [Decimal]) -> [Double] {
        let numbers = values.map { ($0 as NSDecimalNumber).doubleValue }
        guard let low = numbers.min(), let high = numbers.max() else { return [] }
        let step = max(1, numbers.count / 31 + (numbers.count % 31 == 0 ? 0 : 1))
        let sampled = stride(from: 0, to: numbers.count, by: step).map { numbers[$0] }
        guard high > low else { return sampled.map { _ in 0.5 } }
        return sampled.map { ($0 - low) / (high - low) }
    }

    private static func kind(_ kind: FinanceStore.CashFlowEvent.Kind) -> WidgetShared.PublicData.EventKind {
        switch kind {
        case .income: return .income
        case .recurring: return .recurring
        case .planned: return .planned
        case .cardBill: return .cardBill
        }
    }
}

/// Toque num widget: fluxo://inicio, fluxo://cartao, fluxo://fluxo-de-caixa, fluxo://registrar.
/// Só navegação (o app continua bloqueado até o Face ID); qualquer outro endereço é ignorado.
enum DeepLink: String, Equatable {
    case home = "inicio"
    case card = "cartao"
    case cashFlow = "fluxo-de-caixa"
    case register = "registrar"

    init?(url: URL) {
        guard url.scheme?.lowercased() == "fluxo", let host = url.host?.lowercased(),
              url.path.isEmpty || url.path == "/", url.query == nil else { return nil }
        self.init(rawValue: host)
    }
}

@MainActor
final class DeepLinkRouter: ObservableObject {
    static let shared = DeepLinkRouter()
    @Published var pending: DeepLink?
}
