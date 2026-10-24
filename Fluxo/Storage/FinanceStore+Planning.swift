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

extension FinanceStore {
    struct CardSummary {
        let account: StoredAccount
        /// Fatura em aberto (o que já está lançado no ciclo atual).
        let openBill: Decimal
        let limit: Decimal?
        let available: Decimal?
        /// Limite comprometido = limite − disponível (inclui parcelas futuras).
        var used: Decimal? {
            guard let limit, let available else { return nil }
            return limit - available
        }
        var usedFraction: Double? {
            guard let used, let limit, limit > 0 else { return nil }
            return min(max((used as NSDecimalNumber).doubleValue / (limit as NSDecimalNumber).doubleValue, 0), 1)
        }
    }

    func cardSummary(_ card: StoredAccount) -> CardSummary {
        CardSummary(account: card, openBill: abs(card.balance), limit: card.creditLimit, available: card.availableCreditLimit)
    }

    /// Compras do ciclo atual: do fechamento anterior até o próximo.
    /// Sem data de fechamento, usa o mês corrente.
    func currentBillTransactions(_ card: StoredAccount) -> [StoredTransaction] {
        let calendar = Calendar.current
        // Pagamentos da fatura ("não conta") ficam fora da lista de compras.
        let cardItems = transactions.filter {
            $0.accountId == card.id && category(for: $0).kind != .transfer
        }
        if let close = card.billCloseDate, let previous = calendar.date(byAdding: .month, value: -1, to: close) {
            return cardItems.filter { $0.date > previous && $0.date <= close.addingTimeInterval(86_399) }
        }
        return cardItems.filter { calendar.isDate($0.date, equalTo: .now, toGranularity: .month) }
    }

    /// Faturas fechadas, da mais recente para a mais antiga.
    func closedBills(_ card: StoredAccount) -> [StoredBill] {
        bills.filter { $0.accountId == card.id }.sorted { $0.dueDate > $1.dueDate }
    }

    struct InstallmentMonth: Identifiable {
        let month: Date
        let total: Decimal
        var id: Date { month }
    }

    /// Quanto das próximas faturas já está decidido por compras parceladas.
    /// Para cada compra parcelada, vale a parcela mais recente vista ("3/10"):
    /// as 7 que faltam caem, uma por mês, nos meses seguintes.
    func upcomingInstallments(_ card: StoredAccount, months: Int = 6) -> [InstallmentMonth] {
        let calendar = Calendar.current
        guard let thisMonth = calendar.dateInterval(of: .month, for: .now)?.start else { return [] }

        var latest: [String: (number: Int, total: Int, amount: Decimal, date: Date)] = [:]
        for item in transactions where item.accountId == card.id && item.amount < 0 {
            guard let installment = item.installment else { continue }
            let parts = installment.split(separator: "/").compactMap { Int($0) }
            guard parts.count == 2, parts[0] < parts[1] else { continue }
            let key = "\(Self.ruleKey(item.title))|\(item.amount)|\(parts[1])"
            if let current = latest[key], current.number >= parts[0] { continue }
            latest[key] = (parts[0], parts[1], -item.amount, item.date)
        }

        var byMonth: [Date: Decimal] = [:]
        for entry in latest.values {
            guard let postedMonth = calendar.dateInterval(of: .month, for: entry.date)?.start else { continue }
            for step in 1...(entry.total - entry.number) {
                guard let month = calendar.date(byAdding: .month, value: step, to: postedMonth), month > thisMonth else { continue }
                byMonth[month, default: 0] += entry.amount
            }
        }
        return (1...months).compactMap { offset in
            guard let month = calendar.date(byAdding: .month, value: offset, to: thisMonth) else { return nil }
            return InstallmentMonth(month: month, total: byMonth[month] ?? 0)
        }
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
            guard let due = card.billDueDate, due >= today, due <= horizon else { continue }
            let open = cardSummary(card).openBill
            if open > 0 {
                events.append(CashFlowEvent(date: due, title: "Fatura do cartão", kind: .cardBill, amount: -open))
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
