import Foundation

/// Estado das conexões do Open Finance enquanto o app está desbloqueado.
///
/// Nesta parte os dados ficam SÓ na memória. Esta classe pertence à árvore de
/// telas do app desbloqueado: quando o app bloqueia, ela é destruída junto
/// com saldos, contas e o token do Pluggy. (O armazenamento local criptografado
/// chega na Parte 3.)
@MainActor
final class ConnectionsStore: ObservableObject {
    struct Connection: Identifiable {
        let id: String
        var item: PluggyItem?
        var accounts: [PluggyAccount] = []
        var recentTransactionCount: Int?
        var errorMessage: String?
    }

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded(Date)
        case failed(String)
    }

    @Published private(set) var connections: [Connection] = []
    @Published private(set) var state: LoadState = .idle
    @Published private(set) var isConfigured = false

    private let client = PluggyClient()

    // MARK: Totais

    /// Soma dos saldos de conta corrente e poupança (cartões ficam de fora).
    var bankBalance: Decimal? {
        let accounts = connections.flatMap(\.accounts).filter { !$0.isCreditCard }
        guard !accounts.isEmpty else { return nil }
        return accounts.reduce(Decimal(0)) { $0 + $1.balance }
    }

    var bankAccountCount: Int {
        connections.flatMap(\.accounts).filter { !$0.isCreditCard }.count
    }

    var cardCount: Int {
        connections.flatMap(\.accounts).filter(\.isCreditCard).count
    }

    // MARK: Atualização

    /// Busca conexões e contas. Com `countTransactions`, também conta as
    /// transações dos últimos 30 dias (para testar a leitura completa).
    func refresh(countTransactions: Bool = false) async {
        guard state != .loading else { return }

        let itemIds = Self.storedItemIds()
        isConfigured = !itemIds.isEmpty
            && KeychainStore.exists(.pluggyClientId)
            && KeychainStore.exists(.pluggyClientSecret)
        guard isConfigured else {
            connections = []
            state = .idle
            return
        }

        state = .loading
        var loaded: [Connection] = []

        for itemId in itemIds {
            var connection = Connection(id: itemId)
            do {
                connection.item = try await client.item(id: itemId)
                connection.accounts = try await client.accounts(itemId: itemId)
                if countTransactions {
                    let since = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
                    var total = 0
                    for account in connection.accounts {
                        total += try await client.transactions(accountId: account.id, since: since).count
                    }
                    connection.recentTransactionCount = total
                }
            } catch PluggyError.invalidCredentials {
                // Credencial errada afeta todas as conexões: para tudo e avisa uma vez.
                connections = []
                state = .failed(PluggyError.invalidCredentials.errorDescription ?? "")
                return
            } catch {
                connection.errorMessage = (error as? LocalizedError)?.errorDescription ?? "Erro inesperado."
            }
            loaded.append(connection)
        }

        connections = loaded
        state = .loaded(.now)
    }

    /// Chamado quando as credenciais mudam: descarta o token antigo.
    func credentialsChanged() async {
        await client.reset()
        state = .idle
    }

    private static func storedItemIds() -> [String] {
        (KeychainStore.read(.pluggyItemIds) ?? "")
            .split(separator: ",")
            .map(String.init)
            .filter { UUID(uuidString: $0) != nil } // nunca monta URL com texto fora do formato
    }
}

// MARK: - Situação de uma conexão

extension ConnectionsStore.Connection {
    enum Health {
        case ok
        case syncing
        case attention(String)
        case failed(String)
    }

    var health: Health {
        if let errorMessage { return .failed(errorMessage) }
        guard let item else { return .failed("Sem resposta") }

        switch item.status {
        case "UPDATING", "MERGING":
            return .syncing
        case "LOGIN_ERROR", "OUTDATED":
            return .failed("Falhou ao sincronizar")
        case "WAITING_USER_INPUT", "WAITING_USER_ACTION":
            return .attention("Precisa de ação")
        default:
            if let days = consentDaysLeft, days <= 7 {
                return .attention(days <= 0 ? "Autorização vencida" : "Expira em \(days) \(days == 1 ? "dia" : "dias")")
            }
            return .ok
        }
    }

    var consentDaysLeft: Int? {
        guard let expires = item?.consentExpiresAt else { return nil }
        return Calendar.current.dateComponents([.day], from: .now, to: expires).day
    }

    /// Nome do banco: pelo código COMPE; se não houver, pelo nome comercial da conta.
    var displayName: String {
        if let code = accounts.compactMap(\.bankCode).first, let name = BankDirectory.name(forCode: code) {
            return name
        }
        if let marketing = accounts.compactMap(\.marketingName).first { return marketing }
        if let first = accounts.first { return first.name }
        return "Conexão"
    }

    var initials: String {
        let letters = displayName
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
        return String(letters).uppercased()
    }

    var accountsSummary: String {
        let banks = accounts.filter { !$0.isCreditCard }.count
        let cards = accounts.filter(\.isCreditCard).count
        var parts: [String] = []
        if banks > 0 { parts.append(banks == 1 ? "1 conta" : "\(banks) contas") }
        if cards > 0 { parts.append(cards == 1 ? "1 cartão" : "\(cards) cartões") }
        return parts.isEmpty ? "Nenhuma conta" : parts.joined(separator: " e ")
    }
}

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
