import Foundation

/// Lançamentos provisórios: o que você registrou antes de o banco mandar.
///
/// Ideia central (igual a uma conciliação bancária em SQL):
///   provisórios  LEFT JOIN  transações do banco
///   ON  mesmo valor  AND  data próxima
/// O que encontra par está confirmado e sai do saldo estimado; o que não
/// encontra continua "aguardando o banco".
extension FinanceStore {

    /// Ainda não confirmados pelo banco, do mais recente para o mais antigo.
    var pendingProvisionals: [ProvisionalEntry] {
        userData.provisionalEntries.filter(\.isPending).sorted { $0.date > $1.date }
    }

    /// Saldo do banco ajustado pelos lançamentos da conta feitos DEPOIS da
    /// última busca do Pluggy. Nil quando não há nada a ajustar.
    ///
    /// Compras no cartão de crédito ficam de fora: vão para a fatura, não
    /// mexem no saldo da conta.
    var estimatedBalance: (value: Decimal, adjustment: Decimal, count: Int)? {
        guard let balance = bankBalance else { return nil }
        let since = bankDataAt ?? .distantPast
        let after = pendingProvisionals.filter { $0.method == .account && $0.date > since }
        guard !after.isEmpty else { return nil }
        let adjustment = after.reduce(Decimal(0)) { $0 + $1.amount }
        return (balance + adjustment, adjustment, after.count)
    }

    // MARK: Gravar

    /// Valida e grava. Devolve false se algum dado estiver fora do esperado.
    @discardableResult
    func saveProvisional(_ entry: ProvisionalEntry) -> Bool {
        let magnitude = abs(entry.amount)
        guard magnitude > 0, magnitude < 10_000_000,
              let title = Self.sanitizedName(entry.title, maxLength: 60),
              Self.isReasonableProvisionalDate(entry.date)
        else { return false }

        var clean = entry
        clean.title = title
        clean.counterparty = entry.counterparty.flatMap { Self.sanitizedName($0, maxLength: 60) }

        var data = userData
        data.provisionalEntries.removeAll { $0.id == clean.id }
        data.provisionalEntries.append(clean)
        // Teto de segurança: guarda no máximo 300.
        if data.provisionalEntries.count > 300 {
            data.provisionalEntries = Array(data.provisionalEntries.sorted { $0.date > $1.date }.prefix(300))
        }
        saveUserData(data)
        reconcileProvisionals()
        return true
    }

    func deleteProvisional(id: String) {
        var data = userData
        data.provisionalEntries.removeAll { $0.id == id }
        saveUserData(data)
    }

    /// De 60 dias atrás até amanhã (aceita fuso e relógio um pouco adiantado).
    static func isReasonableProvisionalDate(_ date: Date) -> Bool {
        let calendar = Calendar.current
        guard let oldest = calendar.date(byAdding: .day, value: -60, to: .now),
              let newest = calendar.date(byAdding: .day, value: 1, to: .now)
        else { return false }
        return date >= oldest && date <= newest
    }

    // MARK: Conciliação

    /// Para cada provisório sem par, procura uma transação do banco com o
    /// MESMO valor (centavo a centavo), de 1 dia antes a 4 dias depois.
    /// Entre várias candidatas, fica a de data mais próxima; empate, a de
    /// nome mais parecido. Cada transação só confirma um provisório.
    func reconcileProvisionals() {
        var data = userData
        guard !data.provisionalEntries.isEmpty else { return }
        let calendar = Calendar.current
        var taken = Set(data.provisionalEntries.compactMap(\.matchedTransactionId))
        var changed = false

        for index in data.provisionalEntries.indices where data.provisionalEntries[index].isPending {
            let entry = data.provisionalEntries[index]
            let day = calendar.startOfDay(for: entry.date)
            guard let from = calendar.date(byAdding: .day, value: -1, to: day),
                  let to = calendar.date(byAdding: .day, value: 5, to: day)
            else { continue }

            let candidates = transactions.filter {
                !taken.contains($0.id) && $0.amount == entry.amount && $0.date >= from && $0.date < to
            }
            let best = candidates.min { a, b in
                let da = abs(a.date.timeIntervalSince(entry.date)), db = abs(b.date.timeIntervalSince(entry.date))
                if abs(da - db) > 3600 { return da < db }
                return Self.similarity(a, entry) > Self.similarity(b, entry)
            }
            if let best {
                data.provisionalEntries[index].matchedTransactionId = best.id
                taken.insert(best.id)
                changed = true
            }
        }

        // Confirmados há mais de 30 dias já cumpriram o papel: saem.
        let monthAgo = calendar.date(byAdding: .day, value: -30, to: .now) ?? .now
        let before = data.provisionalEntries.count
        data.provisionalEntries.removeAll { !$0.isPending && $0.date < monthAgo }
        if data.provisionalEntries.count != before { changed = true }

        if changed { saveUserData(data) }
    }

    /// Quantas palavras do nome do provisório aparecem na transação.
    private static func similarity(_ transaction: StoredTransaction, _ entry: ProvisionalEntry) -> Int {
        let haystack = ruleKey("\(transaction.title) \(transaction.description)")
        let words = ruleKey("\(entry.counterparty ?? "") \(entry.title)")
            .split(separator: " ")
            .filter { $0.count >= 3 }
        return words.filter { haystack.contains($0) }.count
    }
}
