import Foundation

// MARK: - Seus dados
//
// Tudo o que você cria ou ajusta no app (categorias, trocas de categoria,
// orçamentos) fica numa gaveta separada do cofre. As transações podem ser
// baixadas de novo do Pluggy; estes dados, não. Por isso ficam à parte:
// uma ressincronização nunca apaga o que você configurou.

/// Mudanças que você fez numa categoria pronta (nome, ícone, tipo).
struct CategoryEdit: Codable, Equatable {
    var name: String
    var icon: String
    var kind: CategoryKind
}

/// Limite mensal de uma categoria. Vale para todos os meses até você mudar.
struct Budget: Codable, Identifiable, Equatable {
    let categoryId: String
    var limit: Decimal

    var id: String { categoryId }
}

/// Um gasto que ainda vai acontecer ("dia 26 vou comprar um tênis de R$ 300").
/// Não existe no banco: é um lembrete seu, usado para projetar o mês.
struct PlannedExpense: Codable, Identifiable, Equatable {
    let id: String
    var date: Date
    var title: String
    var amount: Decimal          // sempre positivo
    var categoryId: String?
    var createdByAgent: Bool

    init(id: String = UUID().uuidString, date: Date, title: String, amount: Decimal,
         categoryId: String?, createdByAgent: Bool) {
        self.id = id
        self.date = date
        self.title = title
        self.amount = amount
        self.categoryId = categoryId
        self.createdByAgent = createdByAgent
    }
}

/// Algo que você registrou antes de o banco mandar: print de Pix, compra no
/// Apple Pay, digitado ou pedido ao agente. Fica "provisório" até a conciliação
/// achar a transação real correspondente; aí sai da conta do saldo estimado.
struct ProvisionalEntry: Codable, Identifiable, Equatable {
    enum Source: String, Codable {
        case screenshot   // print
        case applePay     // automação da Carteira
        case manual       // digitado
        case agent        // pedido ao agente
    }

    /// Por onde o dinheiro passou. Só o que passa pela conta mexe no saldo.
    enum Method: String, Codable {
        case account      // Pix, débito, boleto, transferência
        case creditCard   // compra no crédito: vai para a fatura

        var label: String { self == .account ? "Conta" : "Cartão de crédito" }
    }

    let id: String
    var date: Date               // quando aconteceu (com hora)
    var title: String            // "Pix enviado", "Mercado"
    var counterparty: String?    // nome de quem recebeu/pagou (só neste iPhone)
    var amount: Decimal          // negativo = saída, positivo = entrada
    var method: Method
    var source: Source
    var createdAt: Date
    /// Transação do banco que confirmou este lançamento (conciliação).
    var matchedTransactionId: String?

    init(id: String = UUID().uuidString, date: Date, title: String, counterparty: String?,
         amount: Decimal, method: Method, source: Source) {
        self.id = id
        self.date = date
        self.title = title
        self.counterparty = counterparty
        self.amount = amount
        self.method = method
        self.source = source
        self.createdAt = .now
        self.matchedTransactionId = nil
    }

    var isPending: Bool { matchedTransactionId == nil }

    /// "Pix enviado · Fulano de Tal"
    var displayTitle: String {
        guard let counterparty, !counterparty.isEmpty else { return title }
        return "\(title) · \(counterparty)"
    }
}

/// Questionário curto de perfil de investidor (4 perguntas, 0 a 2 pontos cada).
struct InvestorProfile: Codable, Equatable {
    var objective: Int     // 0 proteger · 1 renda extra · 2 crescer
    var horizon: Int       // 0 menos de 1 ano · 1 de 1 a 3 anos · 2 mais de 3 anos
    var reaction: Int      // queda de 20%: 0 resgata · 1 espera · 2 compra mais
    var experience: Int    // 0 nunca · 1 só renda fixa · 2 ações ou FIIs

    static let questions: [(title: String, options: [String])] = [
        ("Qual é o principal objetivo?", ["Proteger o dinheiro", "Ter renda extra", "Fazer o dinheiro crescer"]),
        ("Por quanto tempo pode deixar o dinheiro aplicado?", ["Menos de 1 ano", "De 1 a 3 anos", "Mais de 3 anos"]),
        ("Se o investimento caísse 20% em um mês, você…", ["Resgataria tudo", "Esperaria voltar", "Aproveitaria para comprar mais"]),
        ("Qual a sua experiência com investimentos?", ["Nunca investi", "Só renda fixa", "Já investi em ações ou FIIs"])
    ]

    var answers: [Int] { [objective, horizon, reaction, experience] }
    var score: Int { answers.map { min(max($0, 0), 2) }.reduce(0, +) }

    /// 0–2 conservador · 3–5 moderado · 6–8 arrojado
    var label: String {
        switch score {
        case ...2: return "Conservador"
        case 3...5: return "Moderado"
        default: return "Arrojado"
        }
    }

    var objectiveLabel: String { Self.questions[0].options[min(max(objective, 0), 2)] }
    var horizonLabel: String { Self.questions[1].options[min(max(horizon, 0), 2)] }
}

struct UserData: Codable, Equatable {
    var version = 1
    var customCategories: [Category] = []
    var builtInEdits: [String: CategoryEdit] = [:]
    /// Troca feita numa transação específica: id da transação → id da categoria.
    var transactionCategory: [String: String] = [:]
    /// Regra por estabelecimento: nome normalizado → id da categoria.
    var merchantRules: [String: String] = [:]
    /// Limite geral do mês. Se vazio, usa a soma dos limites das categorias.
    var monthlyLimit: Decimal?
    var budgets: [Budget] = []
    /// Gastos previstos (futuros).
    var plannedExpenses: [PlannedExpense] = []
    /// Notas suas em transações: id da transação → texto.
    var transactionNotes: [String: String] = [:]
    /// Lançamentos provisórios (ainda não confirmados pelo banco).
    var provisionalEntries: [ProvisionalEntry] = []
    /// Suas decisões sobre recorrentes: chave do padrão → true (é recorrente)
    /// ou false (não é; o app para de considerar).
    var recurringDecisions: [String: Bool] = [:]
    /// Dia de fechamento da fatura ajustado por você: id do cartão → dia.
    var cardCloseDays: [String: Int] = [:]
    /// Correções suas na fatura de uma compra do cartão: id da transação →
    /// meses de deslocamento (−1 = fatura anterior, +1 = próxima).
    /// `UserData.billExcluded` = não entra em fatura nenhuma (ex.: repetida).
    var cardBillShift: [String: Int] = [:]
    /// Dia de vencimento ajustado por você: id do cartão → dia.
    var cardDueDays: [String: Int] = [:]
    static let billExcluded = 99
    /// Suas respostas do questionário de perfil de investidor.
    var investorProfile: InvestorProfile?

    static let empty = UserData()

    init() {}

    /// Leitura tolerante: campos que faltarem (de versões futuras ou antigas)
    /// assumem o valor padrão, em vez de invalidar o arquivo inteiro.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        customCategories = try c.decodeIfPresent([Category].self, forKey: .customCategories) ?? []
        builtInEdits = try c.decodeIfPresent([String: CategoryEdit].self, forKey: .builtInEdits) ?? [:]
        transactionCategory = try c.decodeIfPresent([String: String].self, forKey: .transactionCategory) ?? [:]
        merchantRules = try c.decodeIfPresent([String: String].self, forKey: .merchantRules) ?? [:]
        monthlyLimit = try c.decodeIfPresent(Decimal.self, forKey: .monthlyLimit)
        budgets = try c.decodeIfPresent([Budget].self, forKey: .budgets) ?? []
        plannedExpenses = try c.decodeIfPresent([PlannedExpense].self, forKey: .plannedExpenses) ?? []
        transactionNotes = try c.decodeIfPresent([String: String].self, forKey: .transactionNotes) ?? [:]
        provisionalEntries = (try? c.decodeIfPresent([ProvisionalEntry].self, forKey: .provisionalEntries)) ?? []
        recurringDecisions = (try? c.decodeIfPresent([String: Bool].self, forKey: .recurringDecisions)) ?? [:]
        cardCloseDays = (try? c.decodeIfPresent([String: Int].self, forKey: .cardCloseDays)) ?? [:]
        cardBillShift = (try? c.decodeIfPresent([String: Int].self, forKey: .cardBillShift)) ?? [:]
        cardDueDays = (try? c.decodeIfPresent([String: Int].self, forKey: .cardDueDays)) ?? [:]
        investorProfile = try? c.decodeIfPresent(InvestorProfile.self, forKey: .investorProfile)
    }

    var effectiveMonthlyLimit: Decimal? {
        if let monthlyLimit { return monthlyLimit }
        guard !budgets.isEmpty else { return nil }
        return budgets.reduce(Decimal(0)) { $0 + $1.limit }
    }
}

// MARK: - Situação de um orçamento no mês

/// Faixas de alerta, sempre com ícone e texto (nunca só cor).
enum BudgetLevel {
    case ok         // abaixo de 90%
    case near       // de 90% a 100%
    case over       // acima de 100%
}

struct BudgetProgress: Identifiable {
    let budget: Budget
    let category: Category
    let spent: Decimal

    var id: String { budget.id }
    var remaining: Decimal { budget.limit - spent }

    private var ratio: Double {
        guard budget.limit > 0 else { return spent > 0 ? 2 : 0 }
        return (spent as NSDecimalNumber).doubleValue / (budget.limit as NSDecimalNumber).doubleValue
    }

    var level: BudgetLevel {
        if ratio > 1 { return .over }
        if ratio >= 0.9 { return .near }
        return .ok
    }

    /// Fração de 0 a 1 para a barra (cheia quando passa do limite).
    var fraction: Double { min(max(ratio, 0), 1) }

    var percent: Int { Int((ratio * 100).rounded()) }
}
