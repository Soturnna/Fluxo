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

    @Published private(set) var snapshot: VaultSnapshot {
        didSet { rebuildAutomaticCategories() }
    }
    @Published private(set) var userData: UserData {
        didSet { rebuildCategoryIndex() }
    }
    @Published private(set) var connections: [Connection] = []
    @Published private(set) var state: LoadState = .idle
    @Published private(set) var isConfigured = false

    /// Todas as categorias (prontas + suas), por id.
    private(set) var categoryIndex: [String: Category] = [:]
    /// Categoria automática de cada transação, calculada uma vez por sincronização.
    private var automaticCategory: [String: String] = [:]

    private let client = PluggyClient()
    private var syncTask: Task<Void, Never>?

    /// Primeira sincronização de uma conta: busca 1 ano de histórico.
    private static let initialHistoryDays = 365
    /// Sincronizações seguintes: refaz os últimos 10 dias. Transações pendentes
    /// mudam de id quando são confirmadas; refazer a janela evita duplicatas.
    private static let overlapDays = 10

    init() {
        snapshot = Vault.load(VaultSnapshot.self, from: .finance) ?? .empty
        userData = Vault.load(UserData.self, from: .userData) ?? .empty
        isConfigured = Self.hasCredentials()
        // didSet não roda dentro do init; monta os índices aqui.
        rebuildCategoryIndex()
        rebuildAutomaticCategories()
        reconcileProvisionals()
    }

    // MARK: Categorias

    /// Categorias prontas (com suas edições) seguidas das que você criou.
    var allCategories: [Category] {
        let builtIns = CategoryGroup.allCases.compactMap { categoryIndex[$0.rawValue] }
        return builtIns + userData.customCategories
    }

    func category(withId id: String) -> Category? {
        categoryIndex[id]
    }

    /// A categoria de uma transação, em ordem de prioridade:
    /// 1. troca feita por você nesta transação;
    /// 2. regra do estabelecimento ("sempre usar Delivery para iFood");
    /// 3. sugestão automática a partir da categoria do banco.
    func category(for transaction: StoredTransaction) -> Category {
        if let id = userData.transactionCategory[transaction.id], let chosen = categoryIndex[id] {
            return chosen
        }
        if let id = userData.merchantRules[Self.ruleKey(transaction.title)], let ruled = categoryIndex[id] {
            return ruled
        }
        let automatic = automaticCategory[transaction.id] ?? transaction.automaticGroup.rawValue
        return categoryIndex[automatic] ?? CategoryGroup.other.builtInCategory
    }

    func isExpense(_ transaction: StoredTransaction) -> Bool {
        transaction.amount < 0 && category(for: transaction).kind != .transfer
    }

    func isIncome(_ transaction: StoredTransaction) -> Bool {
        transaction.amount > 0 && category(for: transaction).kind != .transfer
    }

    /// Quantas transações têm o mesmo estabelecimento (para oferecer a regra).
    func sameTitleCount(as transaction: StoredTransaction) -> Int {
        let key = Self.ruleKey(transaction.title)
        return transactions.filter { $0.id != transaction.id && Self.ruleKey($0.title) == key }.count
    }

    func transactionCount(inCategory id: String) -> Int {
        transactions.filter { category(for: $0).id == id }.count
    }

    /// Troca a categoria de uma transação. Com `applyToSameTitle`, cria uma regra
    /// para o estabelecimento: as transações dele, atuais e futuras, seguem a escolha.
    func assignCategory(_ categoryId: String, to transaction: StoredTransaction, applyToSameTitle: Bool) {
        guard categoryIndex[categoryId] != nil else { return }
        var data = userData
        if applyToSameTitle {
            let key = Self.ruleKey(transaction.title)
            data.merchantRules[key] = categoryId
            // A regra passa a valer para todas: limpa trocas avulsas do mesmo estabelecimento.
            for other in transactions where Self.ruleKey(other.title) == key {
                data.transactionCategory.removeValue(forKey: other.id)
            }
        } else {
            data.transactionCategory[transaction.id] = categoryId
        }
        saveUserData(data)
    }

    @discardableResult
    func createCategory(name: String, icon: String, kind: CategoryKind) -> Category? {
        guard let cleanName = Self.sanitizedName(name), isNameAvailable(cleanName, excluding: nil) else { return nil }
        let category = Category(
            id: Category.customPrefix + UUID().uuidString,
            name: cleanName,
            icon: Category.iconChoices.contains(icon) ? icon : "ellipsis",
            kind: kind
        )
        var data = userData
        data.customCategories.append(category)
        saveUserData(data)
        return category
    }

    /// Edita nome, ícone e tipo. Vale para categorias prontas e para as suas.
    @discardableResult
    func updateCategory(id: String, name: String, icon: String, kind: CategoryKind) -> Bool {
        guard let cleanName = Self.sanitizedName(name), isNameAvailable(cleanName, excluding: id) else { return false }
        let safeIcon = Category.iconChoices.contains(icon) || CategoryGroup(rawValue: id)?.icon == icon ? icon : "ellipsis"
        var data = userData
        if let index = data.customCategories.firstIndex(where: { $0.id == id }) {
            data.customCategories[index].name = cleanName
            data.customCategories[index].icon = safeIcon
            data.customCategories[index].kind = kind
        } else if CategoryGroup(rawValue: id) != nil {
            data.builtInEdits[id] = CategoryEdit(name: cleanName, icon: safeIcon, kind: kind)
        } else {
            return false
        }
        if kind != .expense { data.budgets.removeAll { $0.categoryId == id } }
        saveUserData(data)
        return true
    }

    /// Volta uma categoria pronta ao original.
    func resetBuiltInCategory(id: String) {
        var data = userData
        data.builtInEdits.removeValue(forKey: id)
        saveUserData(data)
    }

    /// Exclui uma categoria sua. As transações dela voltam à categoria automática.
    func deleteCustomCategory(id: String) {
        guard id.hasPrefix(Category.customPrefix) else { return }
        var data = userData
        data.customCategories.removeAll { $0.id == id }
        data.budgets.removeAll { $0.categoryId == id }
        data.transactionCategory = data.transactionCategory.filter { $0.value != id }
        data.merchantRules = data.merchantRules.filter { $0.value != id }
        saveUserData(data)
    }

    func isNameAvailable(_ name: String, excluding id: String?) -> Bool {
        let key = Self.ruleKey(name)
        return !allCategories.contains { $0.id != id && Self.ruleKey($0.name) == key }
    }

    // MARK: Orçamentos

    /// Cria ou altera o limite mensal de uma categoria de gasto.
    func setBudget(categoryId: String, limit: Decimal) {
        guard categoryIndex[categoryId]?.kind == .expense, limit > 0 else { return }
        var data = userData
        if let index = data.budgets.firstIndex(where: { $0.categoryId == categoryId }) {
            data.budgets[index].limit = limit
        } else {
            data.budgets.append(Budget(categoryId: categoryId, limit: limit))
        }
        saveUserData(data)
    }

    func removeBudget(categoryId: String) {
        var data = userData
        data.budgets.removeAll { $0.categoryId == categoryId }
        saveUserData(data)
    }

    /// Limite geral do mês. `nil` volta a usar a soma das categorias.
    func setMonthlyLimit(_ value: Decimal?) {
        var data = userData
        data.monthlyLimit = value
        saveUserData(data)
    }

    // MARK: Gastos previstos e notas

    /// Previstos ordenados por data. `fromDaysAgo` mantém visíveis os que
    /// acabaram de passar, para você marcar como resolvidos.
    func plannedExpenses(fromDaysAgo days: Int = 3) -> [PlannedExpense] {
        let start = Calendar.current.date(byAdding: .day, value: -days, to: Calendar.current.startOfDay(for: .now)) ?? .now
        return userData.plannedExpenses
            .filter { $0.date >= start }
            .sorted { $0.date < $1.date }
    }

    func plannedExpenses(inMonthOf month: Date) -> [PlannedExpense] {
        guard let interval = Calendar.current.dateInterval(of: .month, for: month) else { return [] }
        return userData.plannedExpenses.filter { interval.contains($0.date) }.sorted { $0.date < $1.date }
    }

    /// Quanto ainda está comprometido no mês: previstos de hoje em diante.
    func pendingPlannedTotal(inMonthOf month: Date) -> Decimal {
        let today = Calendar.current.startOfDay(for: .now)
        return plannedExpenses(inMonthOf: month)
            .filter { $0.date >= today }
            .reduce(Decimal(0)) { $0 + $1.amount }
    }

    /// Cria ou atualiza um gasto previsto, validando cada campo.
    @discardableResult
    func savePlannedExpense(_ expense: PlannedExpense) -> Bool {
        guard let title = Self.sanitizedName(expense.title, maxLength: 60),
              expense.amount > 0, expense.amount < 10_000_000,
              Self.isReasonablePlanDate(expense.date)
        else { return false }
        var clean = expense
        clean.title = title
        if let id = clean.categoryId, categoryIndex[id] == nil { clean.categoryId = nil }

        var data = userData
        if let index = data.plannedExpenses.firstIndex(where: { $0.id == clean.id }) {
            data.plannedExpenses[index] = clean
        } else {
            data.plannedExpenses.append(clean)
        }
        saveUserData(data)
        return true
    }

    func deletePlannedExpense(id: String) {
        var data = userData
        data.plannedExpenses.removeAll { $0.id == id }
        saveUserData(data)
    }

    func note(for transaction: StoredTransaction) -> String? {
        userData.transactionNotes[transaction.id]
    }

    func setNote(_ text: String?, for transactionId: String) {
        var data = userData
        if let text, let clean = Self.sanitizedName(text, maxLength: 200) {
            data.transactionNotes[transactionId] = clean
        } else {
            data.transactionNotes.removeValue(forKey: transactionId)
        }
        saveUserData(data)
    }

    /// Datas aceitas para um gasto previsto: de 1 mês atrás até 2 anos à frente.
    static func isReasonablePlanDate(_ date: Date) -> Bool {
        let calendar = Calendar.current
        guard let min = calendar.date(byAdding: .month, value: -1, to: .now),
              let max = calendar.date(byAdding: .year, value: 2, to: .now)
        else { return false }
        return date >= min && date <= max
    }

    // MARK: Leituras para as telas

    var accounts: [StoredAccount] { snapshot.accounts }
    var transactions: [StoredTransaction] { snapshot.transactions }
    var bills: [StoredBill] { snapshot.bills }
    var investments: [StoredInvestment] { snapshot.investments }
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
        let spent = items.filter { isExpense($0) }.reduce(Decimal(0)) { $0 - $1.amount }
        let income = items.filter { isIncome($0) }.reduce(Decimal(0)) { $0 + $1.amount }
        return (spent, income)
    }

    /// Gasto de cada categoria no mês (só gastos reais), por id da categoria.
    func spendingByCategory(inMonthOf month: Date) -> [String: Decimal] {
        var result: [String: Decimal] = [:]
        for item in transactions(inMonthOf: month) where isExpense(item) {
            result[category(for: item).id, default: 0] += -item.amount
        }
        return result
    }

    func progress(inMonthOf month: Date) -> [BudgetProgress] {
        let spending = spendingByCategory(inMonthOf: month)
        return userData.budgets
            .compactMap { budget in
                guard let category = categoryIndex[budget.categoryId] else { return nil }
                return BudgetProgress(budget: budget, category: category, spent: spending[budget.categoryId] ?? 0)
            }
            .sorted { $0.fraction > $1.fraction }   // os mais críticos primeiro
    }

    /// Gasto em categorias sem orçamento definido.
    func unbudgetedSpending(inMonthOf month: Date) -> Decimal {
        let budgeted = Set(userData.budgets.map(\.categoryId))
        return spendingByCategory(inMonthOf: month)
            .filter { !budgeted.contains($0.key) }
            .reduce(Decimal(0)) { $0 + $1.value }
    }

    /// Média mensal de gasto da categoria nos 3 meses completos anteriores.
    func averageSpending(ofCategory id: String, monthsBack: Int = 3) -> Decimal {
        let calendar = Calendar.current
        guard let thisMonth = calendar.dateInterval(of: .month, for: .now)?.start else { return 0 }
        var total = Decimal(0)
        for offset in 1...monthsBack {
            guard let month = calendar.date(byAdding: .month, value: -offset, to: thisMonth) else { continue }
            total += spendingByCategory(inMonthOf: month)[id] ?? 0
        }
        return Money.decimal(from: (total as NSDecimalNumber).doubleValue / Double(monthsBack))
    }

    /// Dias que faltam no mês (contando hoje). Zero para meses passados.
    func daysLeft(inMonthOf month: Date) -> Int {
        let calendar = Calendar.current
        guard calendar.isDate(month, equalTo: .now, toGranularity: .month),
              let range = calendar.range(of: .day, in: .month, for: .now)
        else { return 0 }
        return range.count - calendar.component(.day, from: .now) + 1
    }

    func storedTransactionCount(forItem itemId: String) -> Int {
        let ids = Set(accounts.filter { $0.itemId == itemId }.map(\.id))
        return transactions.filter { ids.contains($0.accountId) }.count
    }

    // MARK: Índices e gravação

    private func rebuildCategoryIndex() {
        var index: [String: Category] = [:]
        for group in CategoryGroup.allCases {
            var category = group.builtInCategory
            if let edit = userData.builtInEdits[group.rawValue] {
                category.name = edit.name
                category.icon = edit.icon
                category.kind = edit.kind
            }
            index[category.id] = category
        }
        for custom in userData.customCategories {
            index[custom.id] = custom
        }
        categoryIndex = index
    }

    private func rebuildAutomaticCategories() {
        var map: [String: String] = [:]
        for item in snapshot.transactions {
            map[item.id] = item.automaticGroup.rawValue
        }
        automaticCategory = map
    }

    func saveUserData(_ data: UserData) {
        userData = data
        do {
            try Vault.save(data, in: .userData)
        } catch {
            state = .failed("Não foi possível gravar suas alterações no iPhone.")
        }
    }

    /// Chave para comparar nomes: sem maiúsculas, acentos e espaços nas pontas.
    static func ruleKey(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "pt_BR"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Limpa o nome digitado: tira caracteres de controle, espaços nas pontas e
    /// limita a 30 caracteres. Devolve nil se ficar vazio.
    static func sanitizedName(_ raw: String, maxLength: Int = 30) -> String? {
        let cleaned = String(raw.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let limited = String(cleaned.prefix(maxLength))
        return limited.isEmpty ? nil : limited
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
                        balance: account.balance,
                        bankDataAt: connection.item?.lastUpdatedAt,
                        creditLimit: account.creditLimit,
                        availableCreditLimit: account.availableCreditLimit,
                        billCloseDate: account.billCloseDate,
                        billDueDate: account.billDueDate,
                        minimumPayment: account.minimumPayment,
                        cardStatus: account.cardStatus,
                        brand: account.brand
                    )
                    newSnapshot.accounts.removeAll { $0.id == account.id }
                    newSnapshot.accounts.append(stored)
                    syncedAccountIds.insert(account.id)

                    // Faturas fechadas do cartão. Falhar aqui não derruba a sincronização.
                    if account.isCreditCard, let bills = try? await client.bills(accountId: account.id) {
                        newSnapshot.bills.removeAll { $0.accountId == account.id }
                        newSnapshot.bills += bills.map {
                            StoredBill(id: $0.id, accountId: account.id, dueDate: $0.dueDate,
                                       total: $0.totalAmount, minimumPayment: $0.minimumPaymentAmount)
                        }
                    }
                }

                // Investimentos da conexão (opcional: sem eles, o resto segue).
                if let investments = try? await client.investments(itemId: itemId) {
                    newSnapshot.investments.removeAll { $0.itemId == itemId }
                    newSnapshot.investments += investments.map { StoredInvestment(pluggy: $0, itemId: itemId) }
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
        newSnapshot.bills.removeAll { !validAccounts.contains($0.accountId) }
        newSnapshot.investments.removeAll { !validItems.contains($0.itemId) }

        newSnapshot.transactions.sort { $0.date > $1.date }
        if !syncedAccountIds.isEmpty { newSnapshot.lastSyncAt = .now }

        snapshot = newSnapshot
        connections = liveConnections
        state = .loaded(.now)
        reconcileProvisionals()

        // Trocas avulsas de transações que não existem mais são descartadas.
        let existing = Set(newSnapshot.transactions.map(\.id))
        if userData.transactionCategory.keys.contains(where: { !existing.contains($0) })
            || userData.transactionNotes.keys.contains(where: { !existing.contains($0) }) {
            var data = userData
            data.transactionCategory = data.transactionCategory.filter { existing.contains($0.key) }
            data.transactionNotes = data.transactionNotes.filter { existing.contains($0.key) }
            saveUserData(data)
        }

        do {
            try Vault.save(newSnapshot, in: .finance)
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

    /// Por que o cartão de crédito não aparece. Nil quando aparece (ou sem dados).
    /// Baseado nos códigos de aviso do Pluggy: CC_001 = sem permissão para
    /// cartões; CC_002 = aprovação pendente no banco; CC_003/CC_004 = cartão
    /// indisponível no banco; CC_005/CC_006 = sem permissão para faturas/compras.
    var creditCardDiagnosis: String? {
        guard let item, errorMessage == nil, !accounts.contains(where: \.isCreditCard) else { return nil }
        let codes = item.creditCardWarnings
        let list = codes.joined(separator: ", ")

        if codes.contains(where: { ["CC_001", "CC_005", "CC_006"].contains($0) }) {
            return "Não aparece porque a autorização não inclui o cartão (\(list)). Refaça a conexão do \(institution) no Meu Pluggy e marque Cartão de crédito ao autorizar."
        }
        if codes.contains("CC_002") || item.hasResourcesPendingAuthorization {
            return "Não aparece porque o cartão espera sua aprovação no app do \(institution) (Open Finance › compartilhamentos)."
        }
        if codes.contains("CC_003") || codes.contains("CC_004") {
            return "O \(institution) informa o cartão como indisponível no Open Finance (\(list)). Pode ser efeito do bloqueio do cartão."
        }
        if !item.products.isEmpty && !item.products.contains("CREDIT_CARDS") {
            return "Não aparece porque esta conexão não pediu o produto Cartão de crédito ao banco."
        }
        if !codes.isEmpty {
            return "O Pluggy não devolveu o cartão e avisou: \(list)."
        }
        return "O Pluggy não devolveu nenhum cartão nesta conexão e não informou o motivo. Confira no Meu Pluggy se o cartão aparece na conexão do \(institution)."
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
