import Foundation

/// Tudo o que vai para o Gemini passa por aqui.
///
/// Quatro proteções:
/// 1. **Referências curtas.** Em vez do id real da transação (do Pluggy), a IA
///    recebe "t1", "t2"... O mapa de volta só existe na memória do iPhone.
/// 2. **Pseudônimos para pessoas.** Num Pix ou transferência sem estabelecimento,
///    o "título" costuma ser o nome de alguém. Ele vira "Pessoa 1", "Pessoa 2"...
///    Na resposta, o app troca de volta para o nome real antes de mostrar a você.
/// 3. **Números mascarados.** Qualquer sequência longa de dígitos (CPF, CNPJ,
///    conta, cartão, código de barras) vira "•••".
/// 4. **Lista de permissão.** Só data, valor, categoria, título e nota são enviados.
///    Conta bancária, agência e documentos nem chegam a existir no app.
@MainActor
final class PrivacyFilter {
    private(set) var transactionRefs: [String: String] = [:]   // "t1" → id real
    private var refByTransaction: [String: String] = [:]       // id real → "t1"
    private(set) var plannedRefs: [String: String] = [:]       // "p1" → id real
    private var refByPlanned: [String: String] = [:]
    private var aliasByName: [String: String] = [:]            // "JOAO DA SILVA" → "Pessoa 1"
    private var nameByAlias: [String: String] = [:]

    var anonymizeNames: Bool {
        UserDefaults.standard.bool(forKey: SettingsKey.anonymizeNames)
    }

    // MARK: Referências

    func ref(for transaction: StoredTransaction) -> String {
        if let existing = refByTransaction[transaction.id] { return existing }
        let ref = "t\(transactionRefs.count + 1)"
        transactionRefs[ref] = transaction.id
        refByTransaction[transaction.id] = ref
        return ref
    }

    func ref(for planned: PlannedExpense) -> String {
        if let existing = refByPlanned[planned.id] { return existing }
        let ref = "p\(plannedRefs.count + 1)"
        plannedRefs[ref] = planned.id
        refByPlanned[planned.id] = ref
        return ref
    }

    // MARK: Textos

    /// Título seguro de uma transação.
    func safeTitle(for transaction: StoredTransaction) -> String {
        if anonymizeNames && Self.looksLikePersonTransfer(transaction) {
            return alias(for: transaction.title)
        }
        return Self.neutralizeMarkers(Self.maskNumbers(transaction.title))
    }

    /// Nome de pessoa digitado ou lido de um print: vira "Pessoa N".
    func safeName(_ name: String) -> String {
        anonymizeNames ? alias(for: name) : Self.neutralizeMarkers(Self.maskNumbers(name))
    }

    /// Qualquer texto livre (nota, descrição) antes de sair do iPhone.
    func safeText(_ text: String) -> String {
        Self.neutralizeMarkers(Self.maskNumbers(text))
    }

    /// Troca os pseudônimos pelos nomes reais, só para exibir na tela.
    func reveal(_ text: String) -> String {
        var result = text
        // Do maior para o menor, para "Pessoa 10" não virar "Pessoa 1" + "0".
        for alias in nameByAlias.keys.sorted(by: { $0.count > $1.count }) {
            if let name = nameByAlias[alias] {
                result = result.replacingOccurrences(of: alias, with: name)
            }
        }
        return result
    }

    /// Se a IA pesquisar por "Pessoa 2", buscamos pelo nome real localmente.
    func resolveAlias(_ text: String) -> String {
        nameByAlias[text.trimmingCharacters(in: .whitespaces)] ?? text
    }

    private func alias(for name: String) -> String {
        let key = FinanceStore.ruleKey(name)
        if let existing = aliasByName[key] { return existing }
        let alias = "Pessoa \(aliasByName.count + 1)"
        aliasByName[key] = alias
        nameByAlias[alias] = name
        return alias
    }

    // MARK: Regras

    /// Pix ou transferência sem estabelecimento: o título provavelmente é um nome.
    static func looksLikePersonTransfer(_ transaction: StoredTransaction) -> Bool {
        if let merchant = transaction.merchantName, !merchant.isEmpty { return false }
        let category = (transaction.rawCategory ?? "").lowercased()
        let text = transaction.description.lowercased()
        return category.contains("transfer")
            || text.contains("pix")
            || text.contains("transf")
            || text.contains("ted ")
            || text.contains("doc ")
    }

    /// "[[" e "]]" são as marcações de gráfico e de sugestão nas respostas.
    /// Um texto vindo do banco (descrição de Pix, nome de loja) não pode
    /// carregá-las até a IA, para não "plantar" botões ou gráficos na resposta.
    static func neutralizeMarkers(_ text: String) -> String {
        text.replacingOccurrences(of: "[[", with: "[")
            .replacingOccurrences(of: "]]", with: "]")
    }

    /// Sequências de 5 ou mais dígitos (com ou sem . - / espaço) viram "•••".
    static func maskNumbers(_ text: String) -> String {
        text.replacingOccurrences(
            of: "[0-9][0-9.\\-/ ]{3,}[0-9]",
            with: "•••",
            options: .regularExpression
        )
    }
}
