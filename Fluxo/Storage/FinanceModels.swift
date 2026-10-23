import Foundation

// MARK: - O que fica guardado no cofre
//
// Estes modelos são a versão "limpa" dos dados do Pluggy: só os campos
// permitidos e com regras já aplicadas (sinal do valor, nome do banco).

/// Uma conta guardada no iPhone.
struct StoredAccount: Codable, Identifiable, Equatable {
    let id: String
    let itemId: String
    let institution: String      // "Nubank", "Itaú"...
    let isCreditCard: Bool
    let isSavings: Bool
    var balance: Decimal
    /// Quando o Pluggy buscou estes dados no banco (não quando o app falou
    /// com o Pluggy). É a "idade" real do saldo. Opcional: cofres antigos não têm.
    var bankDataAt: Date? = nil

    /// Ex.: "Nubank · Conta", "Nubank · Cartão".
    var displayName: String {
        let kind = isCreditCard ? "Cartão" : (isSavings ? "Poupança" : "Conta")
        return "\(institution) · \(kind)"
    }
}

/// Uma transação guardada no iPhone.
struct StoredTransaction: Codable, Identifiable, Equatable {
    let id: String
    let accountId: String
    let date: Date
    let description: String
    /// Valor NORMALIZADO: negativo = dinheiro saindo, positivo = entrando.
    let amount: Decimal
    let rawCategory: String?
    let isPending: Bool
    let installment: String?     // "3/10"
    let merchantName: String?

    /// Converte a transação do Pluggy aplicando a regra de sinal.
    ///
    /// O Pluggy usa convenções diferentes de sinal para conta e cartão
    /// (no cartão, compra vem positiva). Por isso o sinal é decidido pelo
    /// campo `type`, que é sempre coerente: DEBIT = saída, CREDIT = entrada.
    init(pluggy source: PluggyTransaction) {
        id = source.id
        accountId = source.accountId
        date = source.date
        description = source.description
        let magnitude = abs(source.amount)
        amount = source.type == "DEBIT" ? -magnitude : magnitude
        rawCategory = source.category
        isPending = source.status == "PENDING"
        if let number = source.installmentNumber, let total = source.totalInstallments, total > 1 {
            installment = "\(number)/\(total)"
        } else {
            installment = nil
        }
        merchantName = source.merchantName
    }

    /// Nome mostrado na lista: o estabelecimento, se houver; senão, a descrição.
    var title: String {
        if let merchantName, !merchantName.isEmpty { return merchantName }
        return description
    }

    /// Categoria sugerida automaticamente a partir da categoria do banco.
    /// A categoria final (que você pode trocar) é decidida pelo FinanceStore.
    var automaticGroup: CategoryGroup {
        CategoryGroup(rawCategory: rawCategory, description: description)
    }
}

/// O conteúdo inteiro do cofre.
struct VaultSnapshot: Codable {
    var version = 1
    var lastSyncAt: Date?
    var accounts: [StoredAccount] = []
    var transactions: [StoredTransaction] = []

    static let empty = VaultSnapshot()
}

// MARK: - Categorias

/// O papel de uma categoria nas contas do mês.
enum CategoryKind: String, Codable, CaseIterable, Identifiable {
    case expense    // gasto
    case income     // renda
    case transfer   // movimentação entre contas próprias: não conta

    var id: String { rawValue }

    var label: String {
        switch self {
        case .expense: return "Gasto"
        case .income: return "Renda"
        case .transfer: return "Não conta"
        }
    }

    var explanation: String {
        switch self {
        case .expense: return "Entra no gasto do mês e pode ter orçamento."
        case .income: return "Entra nas entradas do mês."
        case .transfer: return "Movimentação entre contas suas, como pagar a fatura ou investir. Fica fora dos totais para não contar duas vezes."
        }
    }
}

/// Uma categoria: as que vêm prontas ou as que você criar.
struct Category: Codable, Identifiable, Hashable {
    static let customPrefix = "custom-"

    let id: String       // prontas: nome do grupo ("delivery"); suas: "custom-<UUID>"
    var name: String
    var icon: String     // nome de um SF Symbol
    var kind: CategoryKind

    var isBuiltIn: Bool { !id.hasPrefix(Self.customPrefix) }

    /// Ícones oferecidos ao criar ou editar uma categoria.
    static let iconChoices = [
        "cart", "fork.knife", "takeoutbag.and.cup.and.straw", "cup.and.saucer", "car",
        "fuelpump", "bus", "airplane", "house", "bolt", "drop", "wifi", "phone",
        "bag", "tshirt", "gift", "heart", "cross.case", "pills", "pawprint",
        "book", "graduationcap", "gamecontroller", "film", "music.note", "dumbbell",
        "figure.and.child.holdinghands", "person.2", "wrench.and.screwdriver", "leaf",
        "briefcase", "banknote", "creditcard", "chart.line.uptrend.xyaxis",
        "arrow.left.arrow.right", "percent", "repeat", "sparkles", "ellipsis"
    ]
}

/// Agrupa as categorias do Pluggy (em inglês) em grupos em português.
/// A categoria original continua guardada em `rawCategory`.
enum CategoryGroup: String, CaseIterable, Codable {
    case delivery, restaurants, groceries, transport, shopping, subscriptions
    case health, education, home, leisure, transfers, income, investments
    case cardPayment, fees, other

    init(rawCategory: String?, description: String) {
        let text = (rawCategory ?? "").lowercased()
        let desc = description.lowercased()

        func has(_ words: String...) -> Bool { words.contains { text.contains($0) } }

        if has("credit card payment") || desc.contains("pagamento de fatura") || desc.contains("pgto fatura") {
            self = .cardPayment
        } else if has("same person") {
            self = .transfers
        } else if has("investment") {
            self = .investments
        } else if has("food delivery", "delivery") {
            self = .delivery
        } else if has("restaurant", "eating out", "bar", "coffee", "food and drinks") {
            self = .restaurants
        } else if has("groceries", "supermarket") {
            self = .groceries
        } else if has("transport", "taxi", "ride", "gas station", "fuel", "parking", "toll", "vehicle", "automotive") {
            self = .transport
        } else if has("subscription", "streaming", "digital services", "software") {
            self = .subscriptions
        } else if has("health", "pharmac", "drugstore", "hospital", "dent", "doctor", "medical") {
            self = .health
        } else if has("education", "school", "course", "book") {
            self = .education
        } else if has("housing", "rent", "electricity", "water", "internet", "utilities", "telecom", "phone") {
            self = .home
        } else if has("leisure", "entertainment", "travel", "ticket", "gym", "sport") {
            self = .leisure
        } else if has("shopping", "clothing", "electronics", "online", "department") {
            self = .shopping
        } else if has("salary", "income", "wage", "payroll", "pension", "refund") {
            self = .income
        } else if has("tax", "fee", "interest", "fine") {
            self = .fees
        } else if has("transfer", "pix") {
            self = .transfers
        } else {
            self = .other
        }
    }

    var label: String {
        switch self {
        case .delivery: return "Delivery"
        case .restaurants: return "Restaurantes"
        case .groceries: return "Mercado"
        case .transport: return "Transporte"
        case .shopping: return "Compras"
        case .subscriptions: return "Assinaturas"
        case .health: return "Saúde"
        case .education: return "Educação"
        case .home: return "Casa"
        case .leisure: return "Lazer"
        case .transfers: return "Transferências"
        case .income: return "Renda"
        case .investments: return "Investimentos"
        case .cardPayment: return "Pagamento de fatura"
        case .fees: return "Taxas e juros"
        case .other: return "Outros"
        }
    }

    var icon: String {
        switch self {
        case .delivery: return "takeoutbag.and.cup.and.straw"
        case .restaurants: return "fork.knife"
        case .groceries: return "cart"
        case .transport: return "car"
        case .shopping: return "bag"
        case .subscriptions: return "repeat"
        case .health: return "cross.case"
        case .education: return "book"
        case .home: return "house"
        case .leisure: return "face.smiling"
        case .transfers: return "arrow.left.arrow.right"
        case .income: return "briefcase"
        case .investments: return "chart.line.uptrend.xyaxis"
        case .cardPayment: return "creditcard"
        case .fees: return "percent"
        case .other: return "ellipsis"
        }
    }

    /// Movimentações internas: não contam como gasto nem renda.
    var isInternal: Bool {
        self == .cardPayment || self == .investments
    }

    var defaultKind: CategoryKind {
        if isInternal { return .transfer }
        return self == .income ? .income : .expense
    }

    /// A categoria pronta correspondente a este grupo.
    var builtInCategory: Category {
        Category(id: rawValue, name: label, icon: icon, kind: defaultKind)
    }
}

// MARK: - Bancos

/// Códigos COMPE dos bancos mais comuns. Não é dado pessoal: identifica só a instituição.
enum BankDirectory {
    private static let names: [String: String] = [
        "001": "Banco do Brasil",
        "033": "Santander",
        "041": "Banrisul",
        "077": "Inter",
        "104": "Caixa",
        "208": "BTG Pactual",
        "212": "Banco Original",
        "237": "Bradesco",
        "260": "Nubank",
        "290": "PagBank",
        "323": "Mercado Pago",
        "336": "C6 Bank",
        "341": "Itaú",
        "380": "PicPay",
        "422": "Safra",
        "748": "Sicredi",
        "756": "Sicoob"
    ]

    static func name(forCode code: String) -> String? {
        names[code]
    }
}
