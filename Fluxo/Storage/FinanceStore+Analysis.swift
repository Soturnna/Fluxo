import Foundation

/// Cálculos de apoio para o agente e os gráficos das respostas.
/// Tudo roda no iPhone, a partir do cofre local.
extension FinanceStore {
    /// Gasto de cada dia do mês (dia → valor positivo).
    func dailySpending(inMonthOf month: Date) -> [Int: Decimal] {
        let calendar = Calendar.current
        var result: [Int: Decimal] = [:]
        for item in transactions(inMonthOf: month) where isExpense(item) {
            result[calendar.component(.day, from: item.date), default: 0] += -item.amount
        }
        return result
    }

    /// Gasto do mês até um dia (inclusive). Sem dia, o mês inteiro.
    /// Serve para comparar "outubro até o dia 23" com "setembro até o dia 23".
    func spent(inMonthOf month: Date, upToDay day: Int?) -> Decimal {
        dailySpending(inMonthOf: month)
            .filter { day == nil || $0.key <= day! }
            .reduce(Decimal(0)) { $0 + $1.value }
    }

    /// Dias já vividos do mês: hoje, se for o mês atual; o mês inteiro, se já passou.
    func elapsedDays(inMonthOf month: Date) -> Int {
        let calendar = Calendar.current
        if calendar.isDate(month, equalTo: .now, toGranularity: .month) {
            return calendar.component(.day, from: .now)
        }
        return Self.daysInMonth(month)
    }

    /// Momento dos dados do banco por trás do saldo. Com várias contas, vale
    /// a mais antiga: o saldo total só é tão atual quanto a parte mais velha.
    var bankDataAt: Date? {
        accounts.filter { !$0.isCreditCard }.compactMap(\.bankDataAt).min()
    }

    /// "hoje, 10:14", "ontem, 22:10", "amanhã, 10:14" ou "21/10, 08:30".
    static func bankTimeLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        let time = date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(.ptBR))
        if calendar.isDateInToday(date) { return "hoje, \(time)" }
        if calendar.isDateInYesterday(date) { return "ontem, \(time)" }
        if calendar.isDateInTomorrow(date) { return "amanhã, \(time)" }
        return "\(date.formatted(.dateTime.day(.twoDigits).month(.twoDigits).locale(.ptBR))), \(time)"
    }

    static func daysInMonth(_ month: Date) -> Int {
        Calendar.current.range(of: .day, in: .month, for: month)?.count ?? 30
    }

    static func isCurrentMonth(_ month: Date) -> Bool {
        Calendar.current.isDate(month, equalTo: .now, toGranularity: .month)
    }
}
