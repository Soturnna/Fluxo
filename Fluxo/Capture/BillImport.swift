import Foundation
import UniformTypeIdentifiers

/// Uma linha da fatura exportada pelo banco (CSV ou OFX).
struct BillFileLine: Identifiable {
    let id: Int
    let date: Date
    let title: String
    /// Convenção do app: compra negativa, estorno positivo.
    let amount: Decimal
    let installment: String?   // "2/3"
}

/// Fatura lida de um arquivo. Nada é guardado: o arquivo é lido na memória,
/// usado na conferência e descartado.
struct BillFile {
    let lines: [BillFileLine]
    /// Data encontrada no nome do arquivo (o Nubank usa o vencimento: "Nubank_2026-11-07.csv").
    let nameDate: Date?
    /// Soma das compras e estornos (sem pagamentos). Positiva = valor a pagar.
    var total: Decimal { -lines.reduce(Decimal(0)) { $0 + $1.amount } }
}

enum BillImportError: LocalizedError {
    case tooLarge, unreadable, noLines

    var errorDescription: String? {
        switch self {
        case .tooLarge: return "Arquivo grande demais para uma fatura (máximo 2 MB)."
        case .unreadable: return "Não consegui ler o arquivo. Use o CSV ou o OFX exportado pelo banco."
        case .noLines: return "Nenhuma compra encontrada no arquivo."
        }
    }
}

/// Leitura de faturas em CSV (Nubank: date,title,amount) e OFX.
/// Lista de permissão: só data, descrição, valor e parcela. Tudo no iPhone.
enum BillFileParser {
    static let maxBytes = 2_000_000

    /// CSV, OFX ou texto. `.data` cobre arquivos sem tipo reconhecido pelo iOS.
    static var contentTypes: [UTType] {
        [.commaSeparatedText, .plainText, .text, UTType(filenameExtension: "ofx"), UTType(filenameExtension: "csv"), .data]
            .compactMap { $0 }
    }

    /// Lê um arquivo escolhido no app Arquivos (com acesso temporário e limite de tamanho).
    static func read(_ url: URL) throws -> BillFile {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        var data = Data()
        var readError: Error?
        // Coordena a leitura: arquivos do iCloud são baixados antes de abrir.
        NSFileCoordinator().coordinate(readingItemAt: url, options: [.withoutChanges], error: nil) { safeURL in
            do {
                let size = (try? safeURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                guard size <= maxBytes else { throw BillImportError.tooLarge }
                data = try Data(contentsOf: safeURL, options: .uncached)
            } catch { readError = error }
        }
        if let readError { throw readError }
        guard !data.isEmpty else { throw BillImportError.unreadable }
        return try parse(data: data, fileName: url.lastPathComponent)
    }

    static func parse(data: Data, fileName: String) throws -> BillFile {
        guard data.count <= maxBytes else { throw BillImportError.tooLarge }
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw BillImportError.unreadable
        }
        let raw = text.contains("<STMTTRN>") || text.uppercased().contains("<OFX>") ? parseOFX(text) : parseCSV(text)
        let lines = normalizeSigns(raw.filter { !isPayment($0.title) })
        guard !lines.isEmpty else { throw BillImportError.noLines }
        return BillFile(lines: lines.enumerated().map { index, line in
            BillFileLine(id: index, date: line.date, title: line.title, amount: line.amount, installment: line.installment)
        }, nameDate: dateInName(fileName))
    }

    private typealias Raw = (date: Date, title: String, amount: Decimal, installment: String?)

    // MARK: CSV

    private static func parseCSV(_ text: String) -> [Raw] {
        let rows = text.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let header = rows.first else { return [] }
        let separator: Character = header.filter { $0 == ";" }.count > header.filter { $0 == "," }.count ? ";" : ","
        let names = splitCSV(header, separator).map { fold($0).lowercased() }

        func column(_ options: [String]) -> Int? { names.firstIndex { name in options.contains { name.contains($0) } } }
        guard let dateColumn = column(["date", "data"]),
              let amountColumn = column(["amount", "valor"]),
              let titleColumn = column(["title", "descri", "estabelecimento", "historico"]) else { return [] }

        return rows.dropFirst().compactMap { row in
            let cells = splitCSV(row, separator)
            guard cells.count > max(dateColumn, amountColumn, titleColumn),
                  let date = parseDate(cells[dateColumn]),
                  let amount = parseAmount(cells[amountColumn]) else { return nil }
            let (title, installment) = splitInstallment(cells[titleColumn])
            return (date, title, amount, installment)
        }
    }

    private static func splitCSV(_ line: String, _ separator: Character) -> [String] {
        var cells: [String] = []
        var current = ""
        var quoted = false
        for character in line {
            if character == "\"" { quoted.toggle() }
            else if character == separator && !quoted { cells.append(current); current = "" }
            else { current.append(character) }
        }
        cells.append(current)
        return cells.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    // MARK: OFX

    private static func parseOFX(_ text: String) -> [Raw] {
        text.components(separatedBy: "<STMTTRN>").dropFirst().compactMap { block in
            let body = block.components(separatedBy: "</STMTTRN>").first ?? block
            func tag(_ name: String) -> String? {
                guard let start = body.range(of: "<\(name)>") else { return nil }
                let rest = body[start.upperBound...]
                let end = rest.firstIndex(of: "<") ?? rest.endIndex
                let value = rest[..<end].trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : value
            }
            guard let posted = tag("DTPOSTED"), posted.count >= 8,
                  let date = parseDate(String(posted.prefix(8))),
                  let amount = parseAmount(tag("TRNAMT") ?? "") else { return nil }
            let (title, installment) = splitInstallment(tag("MEMO") ?? tag("NAME") ?? "")
            return (date, title, amount, installment)
        }
    }

    // MARK: Campos

    private static func parseDate(_ text: String) -> Date? {
        let clean = text.trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
        let calendar = Calendar.current
        var parts: [Int] = []
        if clean.count == 8, clean.allSatisfy(\.isNumber) {          // 20261015 (OFX)
            parts = [Int(clean.prefix(4)) ?? 0, Int(clean.dropFirst(4).prefix(2)) ?? 0, Int(clean.suffix(2)) ?? 0]
        } else {
            let numbers = clean.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
            guard numbers.count >= 3 else { return nil }
            parts = numbers[0] > 31 ? [numbers[0], numbers[1], numbers[2]]          // 2026-10-15
                                    : [numbers[2] < 100 ? 2000 + numbers[2] : numbers[2], numbers[1], numbers[0]] // 15/10/2026
        }
        guard (2000...2100).contains(parts[0]), (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }

    /// Aceita "23.45", "-23.45", "23,45", "R$ 1.234,56".
    private static func parseAmount(_ text: String) -> Decimal? {
        var clean = text.filter { $0.isNumber || $0 == "," || $0 == "." || $0 == "-" }
        guard !clean.isEmpty else { return nil }
        if let comma = clean.lastIndex(of: ","), clean.lastIndex(of: ".").map({ $0 < comma }) ?? true {
            clean = clean.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
        } else {
            clean = clean.replacingOccurrences(of: ",", with: "")
        }
        guard let value = Decimal(string: clean, locale: Locale(identifier: "en_US_POSIX")), abs(value) < 1_000_000 else { return nil }
        return value
    }

    /// "Loja X - Parcela 2/3" → ("Loja X", "2/3")
    private static func splitInstallment(_ text: String) -> (String, String?) {
        let title = text.trimmingCharacters(in: CharacterSet(charactersIn: "\" ")).prefix(120)
        let pattern = #"(?i)(?:\s*-\s*)?(?:parcela\s*)?(\d{1,2})\s*/\s*(\d{1,2})\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return (String(title), nil) }
        let string = String(title)
        let range = NSRange(string.startIndex..., in: string)
        guard let match = regex.firstMatch(in: string, range: range),
              let all = Range(match.range, in: string),
              let first = Range(match.range(at: 1), in: string), let second = Range(match.range(at: 2), in: string),
              let number = Int(string[first]), let total = Int(string[second]), number >= 1, number <= total, total > 1
        else { return (string, nil) }
        return (String(string[..<all.lowerBound]).trimmingCharacters(in: .whitespaces), "\(number)/\(total)")
    }

    private static func isPayment(_ title: String) -> Bool {
        let key = fold(title).lowercased()
        return key.contains("pagamento recebido") || key.contains("pagamento de fatura") || key.hasPrefix("pagamento em ")
    }

    /// Bancos exportam compras positivas (Nubank CSV) ou negativas (OFX).
    /// A maioria das linhas é compra: se a maioria for positiva, inverte.
    private static func normalizeSigns(_ lines: [Raw]) -> [Raw] {
        let positives = lines.filter { $0.amount > 0 }.count
        guard positives * 2 > lines.count else { return lines }
        return lines.map { ($0.date, $0.title, -$0.amount, $0.installment) }
    }

    /// Minúsculas, sem acento, sem espaços nas pontas.
    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "pt_BR"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func dateInName(_ name: String) -> Date? {
        guard let range = name.range(of: #"\d{4}-\d{2}-\d{2}"#, options: .regularExpression) else { return nil }
        return parseDate(String(name[range]))
    }
}

/// Cruza a fatura do arquivo com as compras do cartão e propõe as correções.
struct BillReconciliation {
    struct Move: Identifiable {
        let transaction: StoredTransaction
        let from: Date?          // vencimento atual (nil = fora do período)
        var id: String { transaction.id }
    }
    struct Extra: Identifiable {
        let transaction: StoredTransaction
        /// Igual a outra compra que está no arquivo: provavelmente repetida.
        let looksDuplicated: Bool
        /// Fatura em que está hoje no Fluxo.
        let from: Date?
        var id: String { transaction.id }
    }

    let target: FinanceStore.BillCycle
    let matchedCount: Int
    let moves: [Move]
    /// No Fluxo nesta fatura, mas não no arquivo.
    let extras: [Extra]
    /// No arquivo, mas sem compra correspondente no Fluxo.
    let missing: [BillFileLine]
    let fileTotal: Decimal
    /// Correções a gravar (id → deslocamento em meses).
    let baseShifts: [String: Int]
    /// Deslocamento para "a próxima fatura" de cada compra extra.
    let nextShifts: [String: Int]

    /// Total da fatura no app depois de aplicar (com as extras escolhidas fora).
    func totalAfter(removing removed: Set<String>) -> Decimal {
        var total = fileTotal
        for line in missing { total += line.amount }           // não há compra para elas no Fluxo
        for extra in extras where !removed.contains(extra.id) && extra.from.map({ Calendar.current.isDate($0, equalTo: target.due, toGranularity: .month) }) == true {
            total -= extra.transaction.amount
        }
        return total
    }
}

extension FinanceStore {
    /// Monta a conferência da fatura `targetIndex` (índice do ciclo) com o arquivo.
    func reconcile(_ file: BillFile, card: StoredAccount, targetIndex: Int) -> BillReconciliation? {
        let calendar = Calendar.current
        // Lugar automático de cada compra (sem as correções antigas) e lugar atual.
        let automatic = cardSchedule(card, past: 6, future: 12, corrections: false)
        let current = cardSchedule(card, past: 6, future: 12)
        guard let target = current.cycles.first(where: { $0.index == targetIndex }) else { return nil }

        func monthStart(_ date: Date) -> Date { calendar.dateInterval(of: .month, for: date)?.start ?? date }
        func monthsBetween(_ from: Date, _ to: Date) -> Int {
            calendar.dateComponents([.month], from: monthStart(from), to: monthStart(to)).month ?? 0
        }
        var autoDue: [String: Date] = [:]
        for cycle in automatic.cycles { for item in cycle.transactions { autoDue[item.id] = cycle.due } }
        var currentDue: [String: Date] = [:]
        for cycle in current.cycles { for item in cycle.transactions { currentDue[item.id] = cycle.due } }

        let candidates = transactions.filter { $0.accountId == card.id && autoDue[$0.id] != nil }

        // Pontuação de cada par (linha do arquivo, compra do Fluxo). Valor tem que ser idêntico.
        func tokens(_ text: String) -> Set<String> {
            Set(Self.ruleKey(text).lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init).filter { $0.count >= 3 })
        }
        var pairs: [(score: Double, line: Int, id: String)] = []
        for line in file.lines {
            let lineTokens = tokens(line.title)
            for item in candidates where abs(item.amount - line.amount) < Decimal(string: "0.005")! {
                var score = 1.0
                if line.installment == item.installment { score += 3 } else if line.installment != nil && item.installment != nil { continue }
                let itemTokens = tokens(item.title).union(tokens(item.description))
                if !lineTokens.isEmpty { score += 2 * Double(lineTokens.intersection(itemTokens).count) / Double(lineTokens.count) }
                let days = abs(calendar.dateComponents([.day], from: line.date, to: item.date).day ?? 99)
                score += days <= 3 ? 1.5 : (days <= 40 ? 0.5 : 0)
                if currentDue[item.id].map({ monthStart($0) == monthStart(target.due) }) == true { score += 0.5 }
                pairs.append((score, line.id, item.id))
            }
        }
        pairs.sort { $0.score > $1.score }
        var lineTaken = Set<Int>(), itemTaken = Set<String>()
        for pair in pairs where !lineTaken.contains(pair.line) && !itemTaken.contains(pair.id) {
            lineTaken.insert(pair.line)
            itemTaken.insert(pair.id)
        }

        let byId = Dictionary(candidates.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var shifts: [String: Int] = [:]
        var moves: [BillReconciliation.Move] = []
        for id in itemTaken {
            guard let item = byId[id], let auto = autoDue[id] else { continue }
            shifts[id] = monthsBetween(auto, target.due)
            if currentDue[id].map({ monthStart($0) != monthStart(target.due) }) ?? true {
                moves.append(.init(transaction: item, from: currentDue[id]))
            }
        }

        // Compras que o Fluxo põe nesta fatura e o arquivo não tem.
        func key(_ item: StoredTransaction) -> String { "\(Self.ruleKey(item.title))|\(item.amount)|\(item.installment ?? "-")" }
        let matched = itemTaken.compactMap { byId[$0] }
        let matchedKeys = Set(matched.map(key))
        var nextShifts: [String: Int] = [:]
        var extras: [BillReconciliation.Extra] = target.transactions
            .filter { !itemTaken.contains($0.id) }
            .map { item in
                if let auto = autoDue[item.id] { nextShifts[item.id] = monthsBetween(auto, target.due) + 1 }
                return .init(transaction: item, looksDuplicated: matchedKeys.contains(key(item)), from: target.due)
            }
        // Cópias de compras do arquivo em outras faturas (mesma parcela, ou mesmo dia):
        // o banco às vezes recria um lançamento com outro código.
        let inTarget = Set(extras.map(\.id))
        for item in candidates where !itemTaken.contains(item.id) && !inTarget.contains(item.id) {
            guard matchedKeys.contains(key(item)) else { continue }
            let twin = matched.first { key($0) == key(item) }
            let sameDay = twin.map { abs($0.date.timeIntervalSince(item.date)) < 3 * 86_400 } ?? false
            guard item.installment != nil || sameDay else { continue }
            extras.append(.init(transaction: item, looksDuplicated: true, from: currentDue[item.id]))
        }

        return BillReconciliation(
            target: target,
            matchedCount: itemTaken.count,
            moves: moves.sorted { $0.transaction.date > $1.transaction.date },
            extras: extras,
            missing: file.lines.filter { !lineTaken.contains($0.id) },
            fileTotal: file.total,
            baseShifts: shifts,
            nextShifts: nextShifts
        )
    }
}
