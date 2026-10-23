import Foundation
import UIKit
import Vision

/// O que deu para entender de um print de comprovante.
/// Tudo é sugestão: a folha de confirmação deixa você corrigir antes de salvar.
struct ReceiptDraft {
    var amount: Decimal?          // sempre positivo
    var isIncome = false
    var title = "Saída"
    var counterparty: String?
    var date: Date?
    var lines: [String] = []
}

/// Lê comprovantes (Pix, transferência, boleto) a partir de um print.
///
/// Privacidade: o reconhecimento de texto é o Vision, da Apple, rodando no
/// próprio iPhone. A imagem não sai do aparelho, não vai para a IA e não é
/// guardada: depois da leitura, só os campos que você confirmar ficam no cofre.
enum ReceiptReader {

    // MARK: Reconhecer o texto

    static func read(_ image: UIImage) async throws -> ReceiptDraft {
        let lines = try await recognizeLines(image)
        return parse(lines)
    }

    /// Linhas de texto, de cima para baixo e, na mesma altura, da esquerda
    /// para a direita (assim "Valor   R$ 50,00" fica rótulo → valor).
    static func recognizeLines(_ image: UIImage) async throws -> [String] {
        guard let cgImage = image.cgImage else { throw ReaderError.unreadableImage }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)

        return try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["pt-BR"]
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
            try handler.perform([request])

            let observations = request.results ?? []
            // No Vision, y = 0 é a BASE da imagem. Agrupa em "linhas visuais".
            let sorted = observations.sorted { $0.boundingBox.midY > $1.boundingBox.midY }
            var rows: [[VNRecognizedTextObservation]] = []
            for observation in sorted {
                if let last = rows.last?.first,
                   abs(last.boundingBox.midY - observation.boundingBox.midY) < 0.008 {
                    rows[rows.count - 1].append(observation)
                } else {
                    rows.append([observation])
                }
            }
            return rows.flatMap { row in
                row.sorted { $0.boundingBox.minX < $1.boundingBox.minX }
                    .compactMap { $0.topCandidates(1).first?.string.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            }
        }.value
    }

    enum ReaderError: LocalizedError {
        case unreadableImage
        var errorDescription: String? { "Não consegui abrir essa imagem." }
    }

    // MARK: Interpretar

    static func parse(_ lines: [String]) -> ReceiptDraft {
        var draft = ReceiptDraft(lines: lines)
        let folded = lines.map(fold)
        let all = folded.joined(separator: "\n")

        // Direção: frases típicas de recebimento; na dúvida, é saída.
        let incomingPhrases = ["pix recebido", "voce recebeu", "transferencia recebida",
                               "recebimento de pix", "deposito recebido", "credito em conta", "recebeu um pix"]
        draft.isIncome = incomingPhrases.contains { all.contains($0) }

        // Tipo, para a descrição.
        if all.contains("pix") {
            draft.title = draft.isIncome ? "Pix recebido" : "Pix enviado"
        } else if all.contains("boleto") {
            draft.title = "Boleto pago"
        } else if all.contains("transferencia") || all.range(of: #"\bted\b"#, options: .regularExpression) != nil {
            draft.title = draft.isIncome ? "Transferência recebida" : "Transferência enviada"
        } else if all.contains("pagamento") {
            draft.title = "Pagamento"
        } else {
            draft.title = draft.isIncome ? "Entrada" : "Saída"
        }

        draft.amount = findAmount(lines, folded)
        draft.date = findDate(lines)
        draft.counterparty = findCounterparty(lines, folded, incoming: draft.isIncome)
        return draft
    }

    /// Valor: o que vem junto ou logo abaixo de "Valor"; senão, o primeiro "R$".
    private static func findAmount(_ lines: [String], _ folded: [String]) -> Decimal? {
        for (index, line) in folded.enumerated() where line.hasPrefix("valor") {
            for candidate in lines[index..<min(index + 3, lines.count)] {
                if let value = amount(in: candidate) { return value }
            }
        }
        for line in lines {
            if let value = amount(in: line, requireSymbol: true) { return value }
        }
        return nil
    }

    /// "R$ 1.234,56", "R$50,00", "- R$ 50,00" ou "50,00" (sem símbolo, se permitido).
    static func amount(in text: String, requireSymbol: Bool = false) -> Decimal? {
        let pattern = requireSymbol
            ? #"R\$\s*-?\s*(\d{1,3}(?:\.\d{3})+|\d+),(\d{2})\b"#
            : #"(?:R\$\s*)?-?\s*(\d{1,3}(?:\.\d{3})+|\d+),(\d{2})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let whole = Range(match.range(at: 1), in: text),
              let cents = Range(match.range(at: 2), in: text)
        else { return nil }
        let digits = text[whole].replacingOccurrences(of: ".", with: "")
        guard let value = Decimal(string: "\(digits).\(text[cents])", locale: Locale(identifier: "en_US_POSIX")),
              value > 0, value < 10_000_000
        else { return nil }
        return value
    }

    private static let months = ["jan": 1, "fev": 2, "mar": 3, "abr": 4, "mai": 5, "jun": 6,
                                 "jul": 7, "ago": 8, "set": 9, "out": 10, "nov": 11, "dez": 12]

    /// "23/10/2026", "23 OUT 2026", "23 de outubro de 2026" + hora "15:32" se houver.
    private static func findDate(_ lines: [String]) -> Date? {
        var day: Int?, month: Int?, year: Int?
        var hour = 12, minute = 0, foundTime = false

        for line in lines {
            let text = fold(line)
            if day == nil {
                if let m = firstMatch(#"\b(\d{2})/(\d{2})/(\d{4})\b"#, text) {
                    day = Int(m[0]); month = Int(m[1]); year = Int(m[2])
                } else if let m = firstMatch(#"\b(\d{1,2})\s*(?:de\s+)?(jan|fev|mar|abr|mai|jun|jul|ago|set|out|nov|dez)[a-z]*\.?\s*(?:de\s+)?(\d{4})\b"#, text) {
                    day = Int(m[0]); month = months[m[1]]; year = Int(m[2])
                }
            }
            if !foundTime, let m = firstMatch(#"\b([01]\d|2[0-3])[:h]([0-5]\d)\b"#, text) {
                hour = Int(m[0]) ?? 12; minute = Int(m[1]) ?? 0; foundTime = true
            }
        }
        guard let day, let month, let year else { return nil }
        var components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        components.timeZone = .current
        return Calendar.current.date(from: components)
    }

    private static let outgoingLabels = ["destino", "para", "recebedor", "favorecido", "quem recebeu",
                                         "destinatario", "beneficiario", "pago para", "nome do recebedor"]
    private static let incomingLabels = ["origem", "de", "pagador", "quem pagou", "remetente", "enviado por"]
    private static let notNames: Set<String> = ["nome", "cpf", "cnpj", "instituicao", "agencia", "conta",
                                                "chave", "chave pix", "tipo", "tipo de conta", "banco", "valor",
                                                "data", "horario", "id da transacao", "conta corrente", "conta pagamento",
                                                "destino", "origem", "para", "de", "pix", "comprovante"]

    /// Quem recebeu (saída) ou quem pagou (entrada): procura o rótulo e pega
    /// a primeira linha seguinte com cara de nome (só letras, sem números).
    private static func findCounterparty(_ lines: [String], _ folded: [String], incoming: Bool) -> String? {
        let labels = incoming ? incomingLabels : outgoingLabels
        for (index, line) in folded.enumerated() {
            for label in labels {
                if line == label || line.hasPrefix(label + ":") {
                    let rest = lines[index].split(separator: ":", maxSplits: 1).dropFirst().first
                        .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
                    if isNameLike(rest) { return titleCase(rest) }
                    for next in lines[(index + 1)..<min(index + 5, lines.count)] where isNameLike(next) {
                        return titleCase(next)
                    }
                }
            }
        }
        return nil
    }

    private static func isNameLike(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3, trimmed.count <= 60,
              trimmed.range(of: #"^[\p{L}][\p{L} .'&-]+$"#, options: .regularExpression) != nil
        else { return false }
        return !notNames.contains(fold(trimmed))
    }

    /// "FULANO DE TAL" → "Fulano de Tal".
    private static func titleCase(_ text: String) -> String {
        let particles: Set<String> = ["de", "da", "do", "das", "dos", "e"]
        return text.lowercased().split(separator: " ").enumerated().map { index, word in
            index > 0 && particles.contains(String(word)) ? String(word) : word.prefix(1).uppercased() + word.dropFirst()
        }.joined(separator: " ")
    }

    // MARK: Apoio

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "pt_BR"))
            .trimmingCharacters(in: .whitespaces)
    }

    private static func firstMatch(_ pattern: String, _ text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        else { return nil }
        return (1..<match.numberOfRanges).compactMap { Range(match.range(at: $0), in: text).map { String(text[$0]) } }
    }
}

extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
