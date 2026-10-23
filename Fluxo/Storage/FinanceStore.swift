import Foundation

/// Fonte única dos dados financeiros enquanto a sessão está aberta.
///
/// Fluxo de dados:
///   Pluggy (rede)  →  sincronização  →  cofre cifrado (disco)  →  telas
///
/// Ao abrir, as telas mostram na hora o que está no cofre. Em seguida, a
/// sincronização busca novidades no Pluggy e regrava o cofre.
/// Esta classe pertence à sessão: quando ela expira, os dados saem da memória
/// (o cofre continua cifrado no disco).
@MainActor
final class FinanceStore: ObservableObject {
    /// Situação de cada conexão na última consulta (não vai para o cofre).
    struct Connection: Identifiable {
        let id: String
        var item: PluggyItem?
        var accounts: [PluggyAccount] = []
        var institution: String = "Conexão"
        var errorMessage: String?
    }

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded(Date)
        case failed(String)
    }

    @Published private(set) var snapshot: VaultSnapshot
    @Published private(set) var connections: [Connection] = []
    @Published private(set) var state: LoadState = .idle
    @Published private(set) var isConfigured = false

    private let client = PluggyClient()
    private var syncTask: Task<Void, Never>?

    /// Primeira sincronização de uma conta: busca 1 ano de histórico.
    private static let initialHistoryDays = 365
    /// Sincronizações seguintes: refaz os últimos 10 dias. Transações pendentes
    /// mudam de id quando são confirmadas; refazer a janela evita duplicatas.
    private static let overlapDays = 10

    init() {
        snapshot = Vault.load() ?? .empty
        isConfigured = Self.hasCredentials()
    }

    // MARK: Leituras para as telas

    var accounts: [StoredAccount] { snapshot.accounts }
    var transactions: [StoredTransaction] { snapshot.transactions }
    var lastSyncAt: Date? { snapshot.lastSyncAt }

    /// Soma dos saldos de conta corrente e poupança (cartões ficam de fora).
    var bankBalance: Decimal? {
        let bankAccounts = accounts.filter { !$0.isCreditCard }
        guard !bankAccounts.isEmpty else { return nil }
        return bankAccounts.reduce(Decimal(0)) { $0 + $1.balance }
    }

    var bankAccountCount: Int { accounts.filter { !$0.isCreditCard }.count }
    var cardCount: Int { accounts.filter(\.isCreditCard).count }
    var failedConnectionCount: Int { connections.filter { $0.errorMessage != nil }.count }

    func account(withId id: String) -> StoredAccount? {
        accounts.first { $0.id == id }
    }

    func transactions(inMonthOf month: Date) -> [StoredTransaction] {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return [] }
        return transactions.filter { interval.contains($0.date) }
    }

    func totals(inMonthOf month: Date) -> (spent: Decimal, income: Decimal) {
        let items = transactions(inMonthOf: month)
        let spent = items.filter(\.isExpense).reduce(Decimal(0)) { $0 - $1.amount }
        let income = items.filter(\.isIncome).reduce(Decimal(0)) { $0 + $1.amount }
        return (spent, income)
    }

    func storedTransactionCount(forItem itemId: String) -> Int {
        let ids = Set(accounts.filter { $0.itemId == itemId }.map(\.id))
        return transactions.filter { ids.contains($0.accountId) }.count
    }

    // MARK: Sincronização

    /// Sincroniza, a menos que a última tenha sido há menos de 10 minutos.
    func syncIfStale() async {
        if case .loaded(let date) = state, Date().timeIntervalSince(date) < 600 { return }
        await sync()
    }

    /// Sincroniza com o Pluggy.
    ///
    /// A tarefa pertence a esta classe, e não à tela que pediu. Se você trocar
    /// de aba no meio, ela termina normalmente, em vez de ser cancelada e deixar
    /// os dados pela metade (era a causa do "0 contas" no Início).
    func sync() async {
        if let running = syncTask {
            await running.value
            return
        }
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performSync()
        }
        syncTask = task
        await task.value
        syncTask = nil
    }

    /// Chamado quando as credenciais mudam: descarta o token antigo.
    func credentialsChanged() async {
        await client.reset()
        isConfigured = Self.hasCredentials()
        state = .idle
    }

    private func performSync() async {
        let itemIds = Self.storedItemIds()
        isConfigured = Self.hasCredentials()
        guard isConfigured else {
            connections = []
            state = .idle
            return
        }

        state = .loading
        var newSnapshot = snapshot
        var liveConnections: [Connection] = []
        var syncedAccountIds = Set<String>()

        for itemId in itemIds {
            var connection = Connection(id: itemId)
            do {
                connection.item = try await client.item(id: itemId)
                let pluggyAccounts = try await client.accounts(itemId: itemId)
                connection.accounts = pluggyAccounts
                connection.institution = Self.institutionName(for: pluggyAccounts)

                for account in pluggyAccounts {
                    let hasHistory = newSnapshot.transactions.contains { $0.accountId == account.id }
                    let days = hasHistory ? Self.overlapDays : Self.initialHistoryDays
                    let since = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .now
                    let fresh = try await client.transactions(accountId: account.id, since: since)

                    // Troca a janela [since, hoje] desta conta pelo que veio agora.
                    let windowStart = Calendar.current.startOfDay(for: since)
                    newSnapshot.transactions.removeAll { $0.accountId == account.id && $0.date >= windowStart }
                    newSnapshot.transactions += fresh.map(StoredTransaction.init(pluggy:))

                    // Atualiza (ou cria) a conta guardada.
                    let stored = StoredAccount(
                        id: account.id,
                        itemId: itemId,
                        institution: connection.institution,
                        isCreditCard: account.isCreditCard,
                        isSavings: account.subtype == "SAVINGS_ACCOUNT",
                        balance: account.balance
                    )
                    newSnapshot.accounts.removeAll { $0.id == account.id }
                    newSnapshot.accounts.append(stored)
                    syncedAccountIds.insert(account.id)
                }
            } catch PluggyError.invalidCredentials {
                connections = []
                state = .failed(PluggyError.invalidCredentials.errorDescription ?? "")
                return
            } catch is CancellationError {
                // Interrompido: mantém os dados anteriores intactos.
                state = .idle
                return
            } catch {
                connection.errorMessage = (error as? LocalizedError)?.errorDescription ?? "Erro inesperado."
            }
            liveConnections.append(connection)
        }

        // Remove do cofre contas de conexões que você tirou do app.
        let validItems = Set(itemIds)
        newSnapshot.accounts.removeAll { !validItems.contains($0.itemId) }
        let validAccounts = Set(newSnapshot.accounts.map(\.id))
        newSnapshot.transactions.removeAll { !validAccounts.contains($0.accountId) }

        newSnapshot.transactions.sort { $0.date > $1.date }
        if !syncedAccountIds.isEmpty { newSnapshot.lastSyncAt = .now }

        snapshot = newSnapshot
        connections = liveConnections
        state = .loaded(.now)

        do {
            try Vault.save(newSnapshot)
        } catch {
            // Sem conseguir gravar, os dados continuam só na memória desta sessão.
            state = .failed("Não foi possível gravar os dados no iPhone.")
        }
    }

    // MARK: Apoio

    private static func hasCredentials() -> Bool {
        !storedItemIds().isEmpty
            && KeychainStore.exists(.pluggyClientId)
            && KeychainStore.exists(.pluggyClientSecret)
    }

    private static func storedItemIds() -> [String] {
        (KeychainStore.read(.pluggyItemIds) ?? "")
            .split(separator: ",")
            .map(String.init)
            .filter { UUID(uuidString: $0) != nil } // nunca monta URL com texto fora do formato
    }

    /// Nome do banco: pelo código COMPE; se não houver, pelo nome comercial da conta.
    private static func institutionName(for accounts: [PluggyAccount]) -> String {
        if let code = accounts.compactMap(\.bankCode).first, let name = BankDirectory.name(forCode: code) {
            return name
        }
        if let marketing = accounts.compactMap(\.marketingName).first { return marketing }
        return accounts.first?.name ?? "Conexão"
    }
}

// MARK: - Situação de uma conexão

extension FinanceStore.Connection {
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

    var initials: String {
        let letters = institution
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
