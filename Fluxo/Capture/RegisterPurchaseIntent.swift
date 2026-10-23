import AppIntents
import Foundation

/// Meio da compra no atalho: crédito vai para a fatura; débito sai da conta.
enum PurchaseMethodOption: String, AppEnum {
    case credit
    case debit

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Meio de pagamento"
    static var caseDisplayRepresentations: [PurchaseMethodOption: DisplayRepresentation] = [
        .credit: "Cartão de crédito",
        .debit: "Débito na conta"
    ]
}

/// Ação do app Atalhos: "Registrar compra no Fluxo".
///
/// Feita para a automação "Transação" da Carteira: a cada compra com Apple Pay,
/// o iPhone entrega valor e estabelecimento, e o Fluxo guarda como lançamento
/// provisório, até o banco confirmar.
///
/// Segurança: a ação só ACRESCENTA um lançamento provisório. Não lê nada do
/// app, não devolve dados e não mexe em nenhuma conta. Os textos recebidos
/// passam por limpeza e limite de tamanho.
struct RegisterPurchaseIntent: AppIntent {
    static var title: LocalizedStringResource = "Registrar compra no Fluxo"
    static var description = IntentDescription(
        "Registra uma compra (por exemplo, do Apple Pay) como lançamento provisório no Fluxo, até o banco confirmar."
    )
    static var openAppWhenRun = false

    @Parameter(title: "Valor")
    var amount: String

    @Parameter(title: "Estabelecimento")
    var merchant: String?

    @Parameter(title: "Meio", default: .credit)
    var method: PurchaseMethodOption

    static var parameterSummary: some ParameterSummary {
        Summary("Registrar \(\.$amount) em \(\.$merchant) no \(\.$method)")
    }

    func perform() async throws -> some IntentResult {
        guard let value = Self.parseAmount(amount) else { throw IntentError.invalidAmount }
        let title = merchant.flatMap(Self.clean) ?? "Compra no Apple Pay"
        try ProvisionalInbox.add(.init(
            id: UUID().uuidString,
            date: .now,
            title: title,
            amount: -value,
            method: method == .credit ? .creditCard : .account,
            source: .applePay
        ))
        return .result()
    }

    /// Aceita "R$ 34,90", "34,90", "34.9" ou "34.90".
    static func parseAmount(_ raw: String) -> Decimal? {
        if let value = ReceiptReader.amount(in: raw) { return value }
        let digits = raw.filter { "0123456789.,".contains($0) }.replacingOccurrences(of: ",", with: ".")
        guard let value = Decimal(string: digits, locale: Locale(identifier: "en_US_POSIX")),
              value > 0, value < 10_000_000
        else { return nil }
        var rounded = Decimal()
        var source = value
        NSDecimalRound(&rounded, &source, 2, .plain)
        return rounded
    }

    /// Sem caracteres de controle, espaços nas pontas e no máximo 60 caracteres.
    static func clean(_ raw: String) -> String? {
        let text = String(raw.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : String(text.prefix(60))
    }

    enum IntentError: Error, CustomLocalizedStringResourceConvertible {
        case invalidAmount
        var localizedStringResource: LocalizedStringResource { "O Fluxo não entendeu o valor da compra." }
    }
}

/// Deixa a ação pronta no app Atalhos, sem precisar procurar.
struct FluxoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RegisterPurchaseIntent(),
            phrases: ["Registrar compra no \(.applicationName)"],
            shortTitle: "Registrar compra",
            systemImageName: "creditcard"
        )
    }
}
