import Foundation

/// Dados FICTÍCIOS para a galeria de widgets do iOS e para a tela de testes.
enum WidgetSamples {
    static func data(showValues: Bool, now: Date = .now) -> WidgetData {
        let calendar = Calendar.current
        func inDays(_ days: Int) -> Date { calendar.date(byAdding: .day, value: days, to: now) ?? now }
        let info = WidgetShared.PublicData(
            updatedAt: now.addingTimeInterval(-40 * 60),
            hasBank: true,
            hasCard: true,
            showValues: showValues,
            billDue: inDays(15),
            cardOverLimit: false,
            cardUsedFraction: 0.72,
            monthName: now.formatted(.dateTime.month(.wide).locale(Locale(identifier: "pt_BR"))),
            budgetFraction: 0.84,
            daysLeftInMonth: 7,
            paceAlert: true,
            tightestDay: inDays(10),
            goesNegative: false,
            sparkline: [0.70, 0.70, 0.62, 0.60, 0.58, 0.55, 0.50, 0.45, 0.40, 0.30, 0.12, 0.95, 0.90, 0.80, 0.62, 0.60, 0.58],
            pendingCount: 1,
            nextEvents: [.init(date: inDays(11), kind: .income, isIncome: true),
                         .init(date: inDays(15), kind: .cardBill, isIncome: false)]
        )
        let values = WidgetShared.Values(
            balance: Decimal(string: "1248.30"),
            bill: Decimal(string: "561.46"),
            spent: Decimal(string: "3374.75")!,
            budget: Decimal(string: "4000"),
            accountSpent: Decimal(string: "2532.45")!,
            cardSpent: Decimal(string: "842.30")!,
            lowestBalance: Decimal(string: "788.50"),
            events: [.init(title: "Salário", amount: Decimal(string: "2400")!),
                     .init(title: "Fatura do cartão", amount: Decimal(string: "-561.46")!)]
        )
        return WidgetData(info: info, values: showValues ? values : nil, now: now)
    }
}
