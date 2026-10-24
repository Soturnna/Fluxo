import Foundation

// MARK: - Lista de permissão
//
// Estes modelos têm SÓ os campos que o Fluxo usa. O JSON do Pluggy traz muito
// mais: CPF do titular (taxNumber), número da conta, agência, e no bloco
// `paymentData` o nome e o CPF de quem pagou e de quem recebeu cada Pix.
//
// Como esses campos não existem nas structs abaixo, o JSONDecoder simplesmente
// os ignora. É o equivalente a um SELECT com colunas explícitas em vez de
// SELECT *: se o Pluggy acrescentar um campo sensível amanhã, ele não entra no app.

struct PluggyAuthResponse: Decodable {
    let apiKey: String
}

/// Uma conexão (item) do Meu Pluggy: um banco autorizado.
struct PluggyItem: Decodable {
    let id: String
    let status: String
    let lastUpdatedAt: Date?
    let consentExpiresAt: Date?
    let nextAutoSyncAt: Date?
    let error: ItemError?
    /// Produtos pedidos na conexão (ex.: ACCOUNTS, CREDIT_CARDS, TRANSACTIONS).
    let products: [String]
    /// Algum dado ainda espera sua aprovação no app do banco.
    let hasResourcesPendingAuthorization: Bool
    /// Códigos de aviso do Pluggy sobre o cartão (ex.: CC_001 = sem permissão).
    /// Só os códigos: o texto dos avisos não é guardado.
    let creditCardWarnings: [String]

    struct ItemError: Decodable {
        let code: String?
    }

    private enum CodingKeys: String, CodingKey {
        case id, status, lastUpdatedAt, consentExpiresAt, nextAutoSyncAt, error
        case products, hasResourcesPendingAuthorization, statusDetail, warnings
    }

    /// Formatos possíveis dos avisos: dentro de statusDetail.creditCards.warnings
    /// ou num bloco warnings.creditCards. Os dois são lidos.
    private struct StatusDetail: Decodable {
        let creditCards: ProductStatus?
    }
    private struct ProductStatus: Decodable {
        let warnings: [Warning]?
    }
    private struct TopWarnings: Decodable {
        let creditCards: [Warning]?
    }
    private struct Warning: Decodable {
        let code: String?
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        status = try c.decode(String.self, forKey: .status)
        lastUpdatedAt = try c.decodeIfPresent(Date.self, forKey: .lastUpdatedAt)
        consentExpiresAt = try c.decodeIfPresent(Date.self, forKey: .consentExpiresAt)
        nextAutoSyncAt = try c.decodeIfPresent(Date.self, forKey: .nextAutoSyncAt)
        error = try? c.decodeIfPresent(ItemError.self, forKey: .error)

        // Campos de diagnóstico: lidos com `try?`. Se o formato mudar, viram
        // vazios em vez de derrubar a sincronização inteira.
        products = (try? c.decodeIfPresent([String].self, forKey: .products)) ?? []
        hasResourcesPendingAuthorization = (try? c.decodeIfPresent(Bool.self, forKey: .hasResourcesPendingAuthorization)) ?? false
        let detail = (try? c.decodeIfPresent(StatusDetail.self, forKey: .statusDetail))?.creditCards?.warnings ?? []
        let top = (try? c.decodeIfPresent(TopWarnings.self, forKey: .warnings))?.creditCards ?? []
        let codes = (detail + top).compactMap(\.code)
            .filter { $0.range(of: "^[A-Z]{2,5}_[0-9]{3}$", options: .regularExpression) != nil }
        creditCardWarnings = Array(Set(codes)).sorted()
    }
}

/// Uma conta: corrente, poupança ou cartão de crédito.
struct PluggyAccount: Decodable, Identifiable {
    let id: String
    let itemId: String
    let type: String          // "BANK" ou "CREDIT"
    let subtype: String       // "CHECKING_ACCOUNT", "SAVINGS_ACCOUNT", "CREDIT_CARD"
    let name: String
    let marketingName: String?
    let balance: Decimal
    let currencyCode: String
    /// Só o código do banco (COMPE, ex.: 260). Agência e conta são descartadas.
    let bankCode: String?
    let creditLimit: Decimal?
    let availableCreditLimit: Decimal?
    /// Só para cartão: fechamento e vencimento da fatura atual, pagamento
    /// mínimo, situação no banco (ACTIVE, BLOCKED…) e bandeira.
    let billCloseDate: Date?
    let billDueDate: Date?
    let minimumPayment: Decimal?
    let cardStatus: String?
    let brand: String?

    var isCreditCard: Bool { type == "CREDIT" }

    private enum CodingKeys: String, CodingKey {
        case id, itemId, type, subtype, name, marketingName, balance, currencyCode, bankData, creditData
    }
    private enum BankDataKeys: String, CodingKey { case transferNumber }
    private enum CreditDataKeys: String, CodingKey {
        case creditLimit, availableCreditLimit, balanceCloseDate, balanceDueDate, minimumPayment, status, brand
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        itemId = try c.decode(String.self, forKey: .itemId)
        type = try c.decode(String.self, forKey: .type)
        subtype = try c.decode(String.self, forKey: .subtype)
        name = try c.decode(String.self, forKey: .name)
        marketingName = try c.decodeIfPresent(String.self, forKey: .marketingName)
        balance = try c.decodeMoney(forKey: .balance)
        currencyCode = try c.decodeIfPresent(String.self, forKey: .currencyCode) ?? "BRL"

        // transferNumber vem como "banco/agência/conta". Lemos o texto,
        // guardamos só o código do banco e o resto morre aqui, sem ser armazenado.
        if let bank = try? c.nestedContainer(keyedBy: BankDataKeys.self, forKey: .bankData),
           let transfer = try? bank.decodeIfPresent(String.self, forKey: .transferNumber),
           let first = transfer.split(separator: "/").first,
           first.count == 3, first.allSatisfy(\.isNumber) {
            bankCode = String(first)
        } else {
            bankCode = nil
        }

        // Dados do cartão: cada campo com `try?`, para um formato inesperado
        // não derrubar a leitura da conta inteira.
        if let credit = try? c.nestedContainer(keyedBy: CreditDataKeys.self, forKey: .creditData) {
            creditLimit = (try? credit.decodeMoneyIfPresent(forKey: .creditLimit)) ?? nil
            availableCreditLimit = (try? credit.decodeMoneyIfPresent(forKey: .availableCreditLimit)) ?? nil
            billCloseDate = (try? credit.decodeIfPresent(Date.self, forKey: .balanceCloseDate)) ?? nil
            billDueDate = (try? credit.decodeIfPresent(Date.self, forKey: .balanceDueDate)) ?? nil
            minimumPayment = (try? credit.decodeMoneyIfPresent(forKey: .minimumPayment)) ?? nil
            cardStatus = (try? credit.decodeIfPresent(String.self, forKey: .status)) ?? nil
            brand = (try? credit.decodeIfPresent(String.self, forKey: .brand)) ?? nil
        } else {
            creditLimit = nil
            availableCreditLimit = nil
            billCloseDate = nil
            billDueDate = nil
            minimumPayment = nil
            cardStatus = nil
            brand = nil
        }
    }
}

/// Uma transação. Sem `paymentData`, sem `descriptionRaw`, sem CNPJ do estabelecimento.
struct PluggyTransaction: Decodable, Identifiable {
    let id: String
    let accountId: String
    let date: Date
    let description: String
    let amount: Decimal
    let currencyCode: String
    let type: String          // "DEBIT" ou "CREDIT"
    let category: String?
    let status: String?       // "PENDING" ou "POSTED"
    let installmentNumber: Int?
    let totalInstallments: Int?
    let merchantName: String?

    private enum CodingKeys: String, CodingKey {
        case id, accountId, date, description, amount, currencyCode, type, category, status
        case creditCardMetadata, merchant
    }
    private enum CardKeys: String, CodingKey { case installmentNumber, totalInstallments }
    private enum MerchantKeys: String, CodingKey { case name, businessName }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        accountId = try c.decode(String.self, forKey: .accountId)
        date = try c.decode(Date.self, forKey: .date)
        description = try c.decode(String.self, forKey: .description)
        amount = try c.decodeMoney(forKey: .amount)
        currencyCode = try c.decodeIfPresent(String.self, forKey: .currencyCode) ?? "BRL"
        type = try c.decode(String.self, forKey: .type)
        category = try c.decodeIfPresent(String.self, forKey: .category)
        status = try c.decodeIfPresent(String.self, forKey: .status)

        if let card = try? c.nestedContainer(keyedBy: CardKeys.self, forKey: .creditCardMetadata) {
            installmentNumber = try? card.decodeIfPresent(Int.self, forKey: .installmentNumber)
            totalInstallments = try? card.decodeIfPresent(Int.self, forKey: .totalInstallments)
        } else {
            installmentNumber = nil
            totalInstallments = nil
        }

        // Nome do estabelecimento (empresa). O CNPJ fica de fora.
        if let merchant = try? c.nestedContainer(keyedBy: MerchantKeys.self, forKey: .merchant) {
            let name = (try? merchant.decodeIfPresent(String.self, forKey: .name)) ?? nil
            let business = (try? merchant.decodeIfPresent(String.self, forKey: .businessName)) ?? nil
            merchantName = name ?? business
        } else {
            merchantName = nil
        }
    }
}

/// Página numerada (usada em /accounts).
/// Fatura FECHADA de um cartão (/bills). Só datas e valores.
struct PluggyBill: Decodable {
    let id: String
    let dueDate: Date
    let totalAmount: Decimal
    let minimumPaymentAmount: Decimal?

    private enum CodingKeys: String, CodingKey { case id, dueDate, totalAmount, minimumPaymentAmount }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        dueDate = try c.decode(Date.self, forKey: .dueDate)
        totalAmount = try c.decodeMoney(forKey: .totalAmount)
        minimumPaymentAmount = (try? c.decodeMoneyIfPresent(forKey: .minimumPaymentAmount)) ?? nil
    }
}

/// Um investimento (/investments). Lista de permissão: sem titular, sem CPF,
/// sem número de conta e sem CNPJ do emissor (só o nome dele).
struct PluggyInvestment: Decodable {
    let id: String
    let name: String
    let type: String              // FIXED_INCOME, MUTUAL_FUND, EQUITY, ETF, COE, CRYPTO…
    let subtype: String?          // CDB, LCI, LCA, TREASURY…
    let balance: Decimal
    let profit: Decimal?          // amountProfit: rendimento acumulado
    let status: String?           // ACTIVE, PENDING, TOTAL_WITHDRAWAL
    let rate: Double?             // ex.: 100 (do CDI)
    let rateType: String?         // CDI, SELIC, IPCA…
    let fixedAnnualRate: Double?  // pré-fixado, % ao ano
    let dueDate: Date?
    let issuer: String?
    let lastMonthRate: Double?    // % no último mês
    let lastTwelveMonthsRate: Double?

    private enum CodingKeys: String, CodingKey {
        case id, name, type, subtype, balance, amountProfit, status, rate, rateType, fixedAnnualRate
        case dueDate, issuer, lastMonthRate, lastTwelveMonthsRate
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Investimento"
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? "OTHER"
        subtype = (try? c.decodeIfPresent(String.self, forKey: .subtype)) ?? nil
        balance = (try? c.decodeMoney(forKey: .balance)) ?? 0
        profit = (try? c.decodeMoneyIfPresent(forKey: .amountProfit)) ?? nil
        status = (try? c.decodeIfPresent(String.self, forKey: .status)) ?? nil
        rate = (try? c.decodeIfPresent(Double.self, forKey: .rate)) ?? nil
        rateType = (try? c.decodeIfPresent(String.self, forKey: .rateType)) ?? nil
        fixedAnnualRate = (try? c.decodeIfPresent(Double.self, forKey: .fixedAnnualRate)) ?? nil
        dueDate = (try? c.decodeIfPresent(Date.self, forKey: .dueDate)) ?? nil
        issuer = (try? c.decodeIfPresent(String.self, forKey: .issuer)) ?? nil
        lastMonthRate = (try? c.decodeIfPresent(Double.self, forKey: .lastMonthRate)) ?? nil
        lastTwelveMonthsRate = (try? c.decodeIfPresent(Double.self, forKey: .lastTwelveMonthsRate)) ?? nil
    }
}

struct PluggyPage<T: Decodable>: Decodable {
    let results: [T]
}

/// Página por cursor (usada em /v2/transactions).
struct PluggyCursorPage<T: Decodable>: Decodable {
    let results: [T]
    let next: String?
}

// MARK: - Apoio à decodificação

extension KeyedDecodingContainer {
    /// Dinheiro chega como número de ponto flutuante. Convertemos para Decimal
    /// com 2 casas, para que somas não acumulem erros como 0,1 + 0,2 = 0,30000000000000004.
    func decodeMoney(forKey key: Key) throws -> Decimal {
        Money.decimal(from: try decode(Double.self, forKey: key))
    }

    func decodeMoneyIfPresent(forKey key: Key) throws -> Decimal? {
        guard let value = try decodeIfPresent(Double.self, forKey: key) else { return nil }
        return Money.decimal(from: value)
    }
}

enum Money {
    static func decimal(from value: Double) -> Decimal {
        Decimal(string: String(format: "%.2f", value)) ?? Decimal(value)
    }
}

enum PluggyDates {
    /// Datas do Pluggy vêm em ISO 8601, com ou sem milissegundos.
    static func parse(_ text: String) -> Date? {
        if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text) { return date }
        if let date = try? Date.ISO8601FormatStyle().parse(text) { return date }
        if let date = try? Date.ISO8601FormatStyle().year().month().day().parse(text) { return date }
        return nil
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = PluggyDates.parse(text) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Data em formato inesperado")
            }
            return date
        }
        return decoder
    }
}
