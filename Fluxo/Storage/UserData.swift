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
