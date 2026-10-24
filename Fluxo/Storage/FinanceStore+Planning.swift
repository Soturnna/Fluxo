import Foundation

// MARK: - Conta × cartão

extension FinanceStore {
    enum Origin: String, CaseIterable, Identifiable {
        case account, card
        var id: String { rawValue }
        var label: String { self == .account ? "Conta" : "Cartão" }
    }

    func origin(of transaction: StoredTransaction) -> Origin {
        account(withId: transaction.accountId)?.isCreditCard == true ? .card : .account
    }

    var creditCards: [StoredAccount] { accounts.filter(\.isCreditCard) }

    /// Totais do mês de uma origem (conta ou cartão).
    func totals(inMonthOf month: Date, origin: Origin) -> (spent: Decimal, income: Decimal) {
        let items = transactions(inMonthOf: month).filter { self.origin(of: $0) == origin }
        let spent = items.filter { isExpense($0) }.reduce(Decimal(0)) { $0 - $1.amount }
        let income = items.filter { isIncome($0) }.reduce(Decimal(0)) { $0 + $1.amount }
        return (spent, income)
    }
}

// MARK: - Cartão de crédito
//
// O "saldo" de um cartão no Pluggy é TUDO o que está comprometido (fatura
// atual + próximas), não a fatura atual. E a data de vencimento que chega
// pode ser a da fatura que já passou. Por isso o app monta os CICLOS da
// fatura como o banco faz: cada compra entra na fatura cujo fechamento vem
// logo depois da data dela. Alguns bancos mandam todas as parcelas futuras
// de uma vez, cada uma datada no mês da sua fatura; outros mandam uma por
// mês. No segundo caso, as que faltam são PREVISTAS pelo app.

extension FinanceStore {
    /// Uma parcela que o banco ainda não mandou, prevista pelo app.
    struct ProjectedInstallment: Identifiable {
        let id = UUID()
        let title: String
        let installment: String      // "4/10"
        let amount: Decimal          // negativo
        let date: Date
    }

    /// Uma fatura (ciclo): do fechamento anterior até o fechamento dela.
    struct BillCycle: Identifiable {
        enum Status { case closed, open, upcoming }
        let index: Int               // 0 = aberta; negativos = fechadas; positivos = futuras
        let close: Date
        let due: Date
        let status: Status
        var transactions: [StoredTransaction] = []
        var projected: [ProjectedInstallment] = []

        var id: Int { index }

        /// Valor da fatura (positivo = a pagar).
        var total: Decimal {
            -(transactions.reduce(Decimal(0)) { $0 + $1.amount } + projected.reduce(Decimal(0)) { $0 + $1.amount })
        }

        /// "novembro" (mês do vencimento).
        var monthName: String {
            due.formatted(.dateTime.month(.wide).locale(.ptBR))
        }
    }

    struct CardSchedule {
        let card: StoredAccount
        let closeDay: Int
        let dueDay: Int
        /// Dia de fechamento calculado (o banco não informou e você não ajustou).
        let closeDayIsEstimate: Bool
        let cycles: [BillCycle]

        var open: BillCycle? { cycles.first { $0.index == 0 } }
        var upcoming: [BillCycle] { cycles.filter { $0.index > 0 } }
        var closed: [BillCycle] { cycles.filter { $0.index < 0 }.sorted { $0.index > $1.index } }
        /// Fatura que já fechou mas ainda não venceu (a pagar).
        var closedUnpaid: BillCycle? {
            let today = Calendar.current.startOfDay(for: .now)
            return cycles.first { $0.index == -1 && $0.due >= today }
        }
        var futureTotal: Decimal { upcoming.reduce(Decimal(0)) { $0 + $1.total } }
    }

    /// Monta as faturas do cartão: `past` fechadas, a aberta e `future` futuras.
    func cardSchedule(_ card: StoredAccount, past: Int = 3, future: Int = 6) -> CardSchedule {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let dueDay = card.billDueDate.map { calendar.component(.day, from: $0) } ?? 10
        let userClose = userData.cardCloseDays[card.id]
        let bankClose = card.billCloseDate.map { calendar.component(.day, from: $0) }
        let closeDay = userClose ?? bankClose ?? Self.estimatedCloseDay(dueDay: dueDay)

        func make(_ monthStart: Date, day: Int) -> Date {
            let length = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 28
            return calendar.date(byAdding: .day, value: min(day, length) - 1, to: monthStart) ?? monthStart
        }
        func month(_ base: Date, plus value: Int) -> Date {
            calendar.date(byAdding: .month, value: value, to: base) ?? base
        }

        // Fatura aberta: a primeira cujo fechamento é hoje ou depois.
        var openMonth = calendar.dateInterval(of: .month, for: today)?.start ?? today
        if make(openMonth, day: closeDay) < today { openMonth = month(openMonth, plus: 1) }

        func closeDate(_ k: Int) -> Date { make(month(openMonth, plus: k), day: closeDay) }
        func dueDate(_ k: Int) -> Date {
            // Vence no mesmo mês do fechamento se o dia vier depois; senão, no mês seguinte.
            make(month(openMonth, plus: dueDay > closeDay ? k : k + 1), day: dueDay)
        }
        func endOfDay(_ date: Date) -> Date { date.addingTimeInterval(86_399) }

        var cycles = (-past...future).map { k in
            BillCycle(index: k, close: closeDate(k), due: dueDate(k),
                      status: k < 0 ? .closed : (k == 0 ? .open : .upcoming))
        }

        // Cada fatura é identificada pelo MÊS do vencimento.
        func monthStart(_ date: Date) -> Date { calendar.dateInterval(of: .month, for: date)?.start ?? date }
        var positionByDueMonth: [Date: Int] = [:]
        for (position, cycle) in cycles.enumerated() { positionByDueMonth[monthStart(cycle.due)] = position }

        func installmentParts(_ item: StoredTransaction) -> (number: Int, total: Int)? {
            guard let parts = item.installment?.split(separator: "/").compactMap({ Int($0) }),
                  parts.count == 2, parts[0] >= 1, parts[0] <= parts[1] else { return nil }
            return (parts[0], parts[1])
        }

        /// Mês do vencimento da fatura em que o lançamento cai.
        /// - Compra à vista ou 1ª parcela: a data é a da compra → vale o
        ///   fechamento (entra na fatura que fecha logo depois).
        /// - 2ª parcela em diante: a data já é a do lançamento na fatura,
        ///   no mês do vencimento (regra descrita na documentação do Pluggy).
        func dueMonth(of item: StoredTransaction) -> Date {
            if let parts = installmentParts(item), parts.number >= 2 { return monthStart(item.date) }
            let base = monthStart(item.date)
            var close = make(base, day: closeDay)
            if endOfDay(close) < item.date { close = make(month(base, plus: 1), day: closeDay) }
            return month(monthStart(close), plus: dueDay > closeDay ? 0 : 1)
        }

        // Compras e estornos do cartão (pagamentos da fatura ficam de fora).
        let items = transactions.filter { $0.accountId == card.id && category(for: $0).kind != .transfer }
        for item in items {
            if let position = positionByDueMonth[dueMonth(of: item)] { cycles[position].transactions.append(item) }
        }

        // Parcelas que o banco ainda não mandou: a partir da mais alta vista,
        // uma por fatura seguinte.
        var latest: [String: (number: Int, total: Int, item: StoredTransaction)] = [:]
        for item in items where item.amount < 0 {
            guard let parts = installmentParts(item) else { continue }
            let key = "\(Self.ruleKey(item.title))|\(item.amount)|\(parts.total)"
            if let current = latest[key], current.number >= parts.number { continue }
            latest[key] = (parts.number, parts.total, item)
        }
        for entry in latest.values where entry.number < entry.total {
            let firstMonth = dueMonth(of: entry.item)
            for step in 1...(entry.total - entry.number) {
                guard let position = positionByDueMonth[month(firstMonth, plus: step)] else { continue }
                cycles[position].projected.append(ProjectedInstallment(
                    title: entry.item.title, installment: "\(entry.number + step)/\(entry.total)",
                    amount: entry.item.amount, date: cycles[position].due))
            }
        }

        for position in cycles.indices {
            cycles[position].transactions.sort { $0.date > $1.date }
        }
        return CardSchedule(card: card, closeDay: closeDay, dueDay: dueDay,
                            closeDayIsEstimate: userClose == nil && bankClose == nil, cycles: cycles)
    }

    /// Sem informação do banco: fecha 7 dias antes do vencimento.
    static func estimatedCloseDay(dueDay: Int) -> Int {
        let day = dueDay - 7
        return day >= 1 ? day : day + 30
    }

    func setCardCloseDay(_ day: Int?, for cardId: String) {
        var data = userData
        data.cardCloseDays[cardId] = day.map { min(max($0, 1), 31) }
        saveUserData(data)
    }

    struct CardSummary {
        let account: StoredAccount
        let schedule: CardSchedule
        /// Fatura aberta (ciclo atual).
        var openBill: Decimal { schedule.open?.total ?? 0 }
        /// Soma das próximas faturas (parcelas já compradas).
        var futureBills: Decimal { schedule.futureTotal }
        /// Tudo o que está comprometido no cartão, segundo o banco.
        var totalUsed: Decimal { abs(account.balance) }
        var limit: Decimal? { account.creditLimit }
        var available: Decimal? { account.availableCreditLimit }
        var nextClose: Date? { schedule.open?.close }
        var nextDue: Date? { schedule.closedUnpaid?.due ?? schedule.open?.due }

        /// Limite comprometido = limite − disponível.
        var used: Decimal? {
            guard let limit, let available else { return nil }
            return limit - available
        }
        /// Para a barra (vai até 100%).
        var usedFraction: Double? {
            guard let ratio = usedRatio else { return nil }
            return min(max(ratio, 0), 1)
        }
        /// Sem teto: 149% quando passou do limite.
        var usedPercent: Int? { usedRatio.map { Int(($0 * 100).rounded()) } }
        var isOverLimit: Bool { (usedRatio ?? 0) > 1 }

        private var usedRatio: Double? {
            guard let used, let limit, limit > 0 else { return nil }
            return (used as NSDecimalNumber).doubleValue / (limit as NSDecimalNumber).doubleValue
        }
    }

    func cardSummary(_ card: StoredAccount) -> CardSummary {
        CardSummary(account: card, schedule: cardSchedule(card))
    }

    /// Faturas fechadas informadas pelo banco, da mais recente para a mais antiga.
    func closedBills(_ card: StoredAccount) -> [StoredBill] {
        bills.filter { $0.accountId == card.id }.sorted { $0.dueDate > $1.dueDate }
    }
}

// MARK: - Recorrentes

extension FinanceStore {
    struct Recurring: Identifiable {
        let id: String               // chave do padrão
        let name: String
        let sample: StoredTransaction
        let amount: Decimal          // com sinal: negativo = saída
        let previousAmount: Decimal?
        let varies: Bool
        let nextDate: Date
        let origin: Origin
        let months: Int
        let isCandidate: Bool        // só 2 meses: precisa da sua confirmação

        var isIncome: Bool { amount > 0 }

        /// Subiu mais de 2% (e pelo menos R$ 1) em relação à vez anterior.
        var priceIncrease: Decimal? {
            guard !varies, !isIncome, let previousAmount else { return nil }
            let now = -amount, before = -previousAmount
            return now > before * Decimal(1.02) && now - before >= 1 ? before : nil
        }
    }

    /// Padrão = mesmo nome, mesma direção e mesma origem; no máximo 1 por mês;
    /// intervalos de 20 a 40 dias. 3 meses ou mais: recorrente. 2 meses
    /// seguidos: candidato (você confirma). Parado há mais de 45 dias: some.
    func detectRecurring(includeIgnored: Bool = false) -> [Recurring] {
        let calendar = Calendar.current
        guard let cutoff = calendar.date(byAdding: .day, value: -125, to: .now),
              let staleLimit = calendar.date(byAdding: .day, value: -45, to: .now)
        else { return [] }
        let today = calendar.startOfDay(for: .now)

        let items = transactions.filter {
            $0.date >= cutoff && !$0.isPending && $0.amount != 0 && category(for: $0).kind != .transfer
        }
        let groups = Dictionary(grouping: items) { item in
            "\(Self.ruleKey(item.title))|\(item.amount < 0 ? "-" : "+")|\(origin(of: item).rawValue)"
        }

        var result: [Recurring] = []
        for (key, group) in groups {
            let sorted = group.sorted { $0.date < $1.date }
            guard let last = sorted.last, last.date >= staleLimit else { continue }

            // Uma ocorrência por mês, no máximo (Uber e iFood ficam de fora).
            let monthKeys = sorted.map { calendar.dateComponents([.year, .month], from: $0.date) }
            guard Set(monthKeys).count == sorted.count, sorted.count >= 2 else { continue }

            let intervals = zip(sorted.dropFirst(), sorted).map { later, earlier in
                calendar.dateComponents([.day], from: earlier.date, to: later.date).day ?? 0
            }
            guard intervals.allSatisfy({ (20...40).contains($0) }) else { continue }

            let decision = userData.recurringDecisions[key]
            if decision == false && !includeIgnored { continue }
            let isCandidate = sorted.count == 2 && decision != true

            let amounts = sorted.map(\.amount)
            let values = amounts.map { abs(($0 as NSDecimalNumber).doubleValue) }
            let average = values.reduce(0, +) / Double(values.count)
            let varies = average > 0 && ((values.max() ?? 0) - (values.min() ?? 0)) / average > 0.15
            let recent = Array(amounts.suffix(3))
            let typical = varies
                ? Money.decimal(from: (recent.reduce(Decimal(0), +) as NSDecimalNumber).doubleValue / Double(recent.count))
                : last.amount

            var next = calendar.date(byAdding: .month, value: 1, to: last.date) ?? last.date
            while next < today { next = calendar.date(byAdding: .month, value: 1, to: next) ?? today }

            result.append(Recurring(
                id: key, name: last.title, sample: last, amount: typical,
                previousAmount: sorted.count >= 2 ? sorted[sorted.count - 2].amount : nil,
                varies: varies, nextDate: next, origin: origin(of: last),
                months: sorted.count, isCandidate: isCandidate
            ))
        }
        return result.sorted { $0.nextDate < $1.nextDate }
    }

    func setRecurringDecision(_ key: String, isRecurring: Bool?) {
        var data = userData
        data.recurringDecisions[key] = isRecurring
        saveUserData(data)
    }
}

// MARK: - Fluxo de caixa projetado

extension FinanceStore {
    struct CashFlowEvent: Identifiable {
        enum Kind { case recurring, income, planned, cardBill }
        let id = UUID()
        let date: Date
        let title: String
        let kind: Kind
        let amount: Decimal
        var balanceAfter: Decimal = 0

        var kindLabel: String {
            switch kind {
            case .recurring: return "Recorrente"
            case .income: return "Entrada recorrente"
            case .planned: return "Gasto previsto"
            case .cardBill: return "Fatura do cartão"
            }
        }
    }

    struct DayBalance: Identifiable {
        let date: Date
        let balance: Decimal
        var id: Date { date }
    }

    struct CashFlowProjection {
        let start: Decimal
        let daily: [DayBalance]
        let events: [CashFlowEvent]
        let minBalance: Decimal
        let minDate: Date
        let firstNegative: Date?
        let lastNegative: Date?
        let endBalance: Decimal
        let suggestion: String?

        var goesNegative: Bool { firstNegative != nil }
    }

    /// Saldo da conta dia a dia: saldo estimado de hoje + recorrentes da conta
    /// + gastos previstos + fatura do cartão no vencimento. Compras no cartão
    /// não entram no dia: chegam juntas, na fatura.
    func projectCashFlow(days: Int = 30) -> CashFlowProjection? {
        guard let balance = estimatedBalance?.value ?? bankBalance else { return nil }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        guard let horizon = calendar.date(byAdding: .day, value: days, to: today) else { return nil }

        var events: [CashFlowEvent] = []

        for item in detectRecurring() where !item.isCandidate && item.origin == .account {
            var date = item.nextDate
            while date <= horizon {
                events.append(CashFlowEvent(date: date, title: item.name,
                                            kind: item.isIncome ? .income : .recurring, amount: item.amount))
                guard let next = calendar.date(byAdding: .month, value: 1, to: date) else { break }
                date = next
            }
        }
        for planned in userData.plannedExpenses where planned.date >= today && planned.date <= horizon {
            events.append(CashFlowEvent(date: planned.date, title: planned.title, kind: .planned, amount: -planned.amount))
        }
        for card in creditCards {
            let schedule = cardSchedule(card, past: 1, future: 2)
            for cycle in schedule.cycles where cycle.due >= today && cycle.due <= horizon && cycle.total > 0 {
                // Fechada e já paga não entra: só a fechada que ainda vai vencer e as abertas.
                if cycle.status == .closed && schedule.closedUnpaid?.index != cycle.index { continue }
                events.append(CashFlowEvent(date: cycle.due, title: "Fatura do cartão (\(cycle.monthName))",
                                            kind: .cardBill, amount: -cycle.total))
            }
        }
        events.sort { $0.date < $1.date }

        var running = balance
        var daily: [DayBalance] = []
        var index = 0
        for offset in 0...days {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            while index < events.count && calendar.startOfDay(for: events[index].date) <= day {
                running += events[index].amount
                events[index].balanceAfter = running
                index += 1
            }
            daily.append(DayBalance(date: day, balance: running))
        }

        // Ponto mais baixo: o último dia em que o mínimo vale (véspera da entrada).
        var minBalance = daily.first?.balance ?? balance
        var minDate = today
        for point in daily where point.balance <= minBalance {
            minBalance = point.balance
            minDate = point.date
        }
        let negatives = daily.filter { $0.balance < 0 }.map { $0.date }

        var suggestion: String?
        if let lastNegative = negatives.last {
            let shortfall = -minBalance
            let nextIncome = events.first { $0.amount > 0 && $0.date > lastNegative }
            if let candidate = events.filter({ $0.kind == .planned && $0.date <= lastNegative && -$0.amount >= shortfall })
                .min(by: { -$0.amount < -$1.amount }) {
                let after = nextIncome.map { " para depois de \($0.title.lowercased()) (\(Self.dayLabel($0.date)))" } ?? ""
                suggestion = "Adiar \(candidate.title) (\(AgentTools.brl(-candidate.amount)), \(Self.dayLabel(candidate.date)))\(after) resolve."
            } else {
                suggestion = "Faltam \(AgentTools.brl(shortfall)). Veja com o agente o que dá para adiar ou cortar."
            }
        }

        return CashFlowProjection(
            start: balance, daily: daily, events: events,
            minBalance: minBalance, minDate: minDate,
            firstNegative: negatives.first, lastNegative: negatives.last,
            endBalance: daily.last?.balance ?? balance, suggestion: suggestion
        )
    }

    /// "26 out"
    static func dayLabel(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).locale(.ptBR)).replacingOccurrences(of: ".", with: "")
    }
}

// MARK: - Investimentos

extension FinanceStore {
    var activeInvestments: [StoredInvestment] {
        investments.filter { !$0.isWithdrawn }.sorted { $0.balance > $1.balance }
    }

    var withdrawnInvestments: [StoredInvestment] {
        investments.filter(\.isWithdrawn)
    }

    var investedTotal: Decimal {
        activeInvestments.reduce(Decimal(0)) { $0 + $1.balance }
    }

    /// Rendimento aproximado no último mês (saldo × taxa do mês informada pelo banco).
    var investmentsLastMonthProfit: Decimal? {
        let known = activeInvestments.filter { $0.lastMonthRate != nil }
        guard !known.isEmpty else { return nil }
        let value = known.reduce(0.0) { $0 + ($1.balance as NSDecimalNumber).doubleValue * ($1.lastMonthRate ?? 0) / 100 }
        return Money.decimal(from: value)
    }

    /// Soma por tipo (CDB, Tesouro, FIIs…), do maior para o menor.
    var investmentAllocation: [(label: String, value: Decimal)] {
        let grouped = Dictionary(grouping: activeInvestments, by: \.kindLabel)
        return grouped
            .map { (label: $0.key, value: $0.value.reduce(Decimal(0)) { $0 + $1.balance }) }
            .sorted { $0.value > $1.value }
    }
}

extension StoredInvestment {
    /// Rótulo do tipo, pelo subtipo quando houver.
    var kindLabel: String {
        let code = (subtype ?? "").uppercased()
        switch code {
        case "TREASURY": return "Tesouro Direto"
        case "REAL_ESTATE_FUND": return "FIIs"
        case "STOCK": return "Ações"
        case "CDB", "LCI", "LCA", "LC", "RDB", "CRI", "CRA", "LF", "LIG": return code
        case "DEBENTURES", "DEBENTURE": return "Debêntures"
        case "":
            switch type {
            case "FIXED_INCOME": return "Renda fixa"
            case "MUTUAL_FUND": return "Fundos"
            case "EQUITY": return "Ações"
            case "ETF": return "ETF"
            case "COE": return "COE"
            case "CRYPTO": return "Cripto"
            default: return "Outros"
            }
        default:
            return code.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    /// "Renda fixa", "Fundos"…: a família do investimento.
    var familyLabel: String {
        switch type {
        case "FIXED_INCOME": return "Renda fixa"
        case "MUTUAL_FUND": return "Fundo"
        case "EQUITY": return "Renda variável"
        case "ETF": return "ETF"
        case "COE": return "COE"
        case "CRYPTO": return "Cripto"
        default: return "Investimento"
        }
    }

    /// "100% do CDI", "IPCA + 6,2% a.a.", "12,5% a.a."
    var rateLabel: String? {
        let number: (Double) -> String = { $0.formatted(.number.precision(.fractionLength(0...2)).locale(.ptBR)) }
        if let rateType, rateType.uppercased() == "IPCA" {
            return fixedAnnualRate.map { "IPCA + \(number($0))% a.a." } ?? "IPCA"
        }
        if let rate, let rateType, !rateType.isEmpty {
            return "\(number(rate))% do \(rateType.uppercased())"
        }
        if let fixedAnnualRate { return "\(number(fixedAnnualRate))% a.a." }
        return nil
    }
}

// MARK: - Antes de investir

extension FinanceStore {
    struct InvestReadiness {
        enum State { case ok, warning, pending, unknown }

        let cardState: State
        let cardDetail: String
        let reserveCurrent: Decimal
        let reserveTarget: Decimal
        let averageSpending: Decimal
        /// Média de (entradas − gastos) nos últimos 3 meses completos.
        let monthlySurplus: Decimal?

        var reserveFraction: Double {
            guard reserveTarget > 0 else { return 0 }
            return min((reserveCurrent as NSDecimalNumber).doubleValue / (reserveTarget as NSDecimalNumber).doubleValue, 1)
        }
        var reserveDone: Bool { reserveTarget > 0 && reserveCurrent >= reserveTarget }
    }

    struct PlanStep: Identifiable {
        let id = UUID()
        let title: String
        let detail: String
    }

    /// Checagens feitas só com dados do iPhone: cartão, reserva e sobra.
    func investReadiness() -> InvestReadiness {
        let calendar = Calendar.current
        let thisMonth = calendar.dateInterval(of: .month, for: .now)?.start ?? .now
        let months = (1...3).compactMap { calendar.date(byAdding: .month, value: -$0, to: thisMonth) }
        let monthTotals = months.map { self.totals(inMonthOf: $0) }
        let withData = monthTotals.filter { $0.spent > 0 || $0.income > 0 }
        let count = Decimal(max(withData.count, 1))
        let averageSpending = withData.reduce(Decimal(0)) { $0 + $1.spent } / count
        let surplus: Decimal? = withData.isEmpty ? nil : withData.reduce(Decimal(0)) { $0 + $1.income - $1.spent } / count

        // Reserva: o que está em renda fixa (onde costuma ficar a reserva).
        let reserve = activeInvestments.filter { $0.type == "FIXED_INCOME" }.reduce(Decimal(0)) { $0 + $1.balance }

        var state = InvestReadiness.State.unknown
        var detail = "Cartão de crédito não aparece no Open Finance."
        if let card = creditCards.first {
            let summary = cardSummary(card)
            if summary.isOverLimit {
                state = .pending
                detail = "Fatura acima do limite. Quitar vem primeiro: o juro do cartão é maior que o rendimento de qualquer investimento."
            } else if card.isCardBlocked {
                state = .pending
                detail = "Cartão bloqueado no banco. Vale entender o motivo e regularizar antes de investir."
            } else if let unpaid = summary.schedule.closedUnpaid, unpaid.total > 0 {
                state = .warning
                detail = "Fatura de \(unpaid.monthName) fechada, vence \(Self.dayLabel(unpaid.due)). Garanta o pagamento integral."
            } else {
                state = .ok
                detail = "Sem fatura atrasada nem limite estourado."
            }
        }

        return InvestReadiness(
            cardState: state, cardDetail: detail,
            reserveCurrent: reserve,
            reserveTarget: Money.decimal(from: (averageSpending as NSDecimalNumber).doubleValue * 6),
            averageSpending: averageSpending,
            monthlySurplus: surplus.map { Money.decimal(from: ($0 as NSDecimalNumber).doubleValue) }
        )
    }

    /// Plano em ordem de prioridade (como um CASE WHEN): cartão → sobra →
    /// reserva → investir conforme o perfil. Educativo, sem indicar ativo.
    func investmentPlan() -> [PlanStep] {
        let readiness = investReadiness()
        let profile = userData.investorProfile
        var steps: [PlanStep] = []

        if readiness.cardState == .pending {
            steps.append(PlanStep(title: "Quitar o cartão",
                                  detail: "Antes de qualquer aplicação. Cada real aqui \"rende\" o juro que você deixa de pagar."))
        }

        guard let surplus = readiness.monthlySurplus, surplus > 0 else {
            steps.append(PlanStep(title: "Fazer sobrar dinheiro no mês",
                                  detail: "Nos últimos meses, saiu mais do que entrou. Os recorrentes e os orçamentos ajudam a achar onde cortar."))
            return steps
        }

        let surplusText = AgentTools.brl(surplus)
        if !readiness.reserveDone {
            let missing = readiness.reserveTarget - readiness.reserveCurrent
            let monthly = Money.decimal(from: (surplus as NSDecimalNumber).doubleValue * 0.6)
            let monthsNeeded = monthly > 0 ? Int(ceil((missing as NSDecimalNumber).doubleValue / (monthly as NSDecimalNumber).doubleValue)) : 0
            steps.append(PlanStep(
                title: "Completar a reserva de emergência",
                detail: "Faltam \(AgentTools.brl(missing)) para 6 meses de gastos. Com \(AgentTools.brl(monthly)) por mês (60% da sua sobra de \(surplusText)), leva cerca de \(monthsNeeded) \(monthsNeeded == 1 ? "mês" : "meses"). Prefira resgate diário, como Caixinha ou Tesouro Selic."
            ))
        }

        let share = readiness.reserveDone ? surplus : Money.decimal(from: (surplus as NSDecimalNumber).doubleValue * 0.4)
        let amount = AgentTools.brl(share)
        switch profile?.label ?? "" {
        case "Conservador":
            steps.append(PlanStep(title: "Investir com segurança", detail: "\(amount) por mês em renda fixa: CDB, LCI/LCA e Tesouro, de bancos e prazos diferentes."))
        case "Arrojado":
            steps.append(PlanStep(title: "Diversificar para crescer", detail: "\(amount) por mês divididos entre renda fixa, FIIs (renda mensal) e ações ou ETFs, de setores diferentes."))
        case "Moderado":
            steps.append(PlanStep(title: "Renda extra com FIIs", detail: "\(amount) por mês: a maior parte em renda fixa e uma parte em 3 a 5 FIIs de setores diferentes, que costumam pagar todo mês."))
        default:
            steps.append(PlanStep(title: "Descobrir o seu perfil", detail: "Responda as 4 perguntas abaixo para o plano indicar como dividir \(amount) por mês."))
        }
        return steps
    }
}

extension FinanceStore {
    func saveInvestorProfile(_ profile: InvestorProfile) {
        var data = userData
        data.investorProfile = profile
        saveUserData(data)
    }
}
