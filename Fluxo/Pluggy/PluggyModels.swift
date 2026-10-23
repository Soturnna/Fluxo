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

    struct ItemError: Decodable {
        let code: String?
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

    var isCreditCard: Bool { type == "CREDIT" }

    private enum CodingKeys: String, CodingKey {
        case id, itemId, type, subtype, name, marketingName, balance, currencyCode, bankData, creditData
    }
    private enum BankDataKeys: String, CodingKey { case transferNumber }
    private enum CreditDataKeys: String, CodingKey { case creditLimit, availableCreditLimit }

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

        if let credit = try? c.nestedContainer(keyedBy: CreditDataKeys.self, forKey: .creditData) {
            creditLimit = try credit.decodeMoneyIfPresent(forKey: .creditLimit)
            availableCreditLimit = try credit.decodeMoneyIfPresent(forKey: .availableCreditLimit)
        } else {
            creditLimit = nil
            availableCreditLimit = nil
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
