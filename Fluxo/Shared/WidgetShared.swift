import Foundation

/// Pasta compartilhada entre o app e os widgets (App Group) e os dados que vão nela.
///
/// Instalado pelo iloader, o app ganha outro identificador (com.soturnna.fluxo.<EQUIPE>)
/// e o grupo criado é "group.<esse identificador>". Por isso o nome do grupo é
/// descoberto na hora, a partir do identificador do próprio app.
///
/// SEGURANÇA — dois arquivos, duas proteções:
/// - `widget-publico.json`: nada em reais nem nomes (dias até vencer, % do orçamento,
///   formato do gráfico). Legível depois do primeiro desbloqueio, para a tela bloqueada.
/// - `widget-valores.json`: os valores em reais e os nomes. Só existe se você ligar
///   "Mostrar valores nos widgets" e fica FECHADO enquanto o iPhone está travado
///   (proteção completa): com o iPhone travado o widget não consegue lê-lo.
enum WidgetShared {
    static let baseBundleID = "com.soturnna.fluxo"
    private static let publicFile = "widget-publico.json"
    private static let valuesFile = "widget-valores.json"
    private static let legacyFiles = ["widget.json"]

    // MARK: Grupo

    static var mainBundleID: String {
        mainBundleID(from: Bundle.main.bundleIdentifier ?? baseBundleID,
                     isExtension: Bundle.main.bundleURL.pathExtension == "appex")
    }

    static func mainBundleID(from id: String, isExtension: Bool) -> String {
        guard isExtension else { return id }
        return id.split(separator: ".").dropLast().joined(separator: ".")
    }

    static var groupCandidates: [String] { groupCandidates(mainBundleID: mainBundleID) }

    /// O iloader (isideload) cria "group.<id do app instalado>"; o original fica de reserva.
    static func groupCandidates(mainBundleID: String) -> [String] {
        let installed = "group.\(mainBundleID)"
        let original = "group.\(baseBundleID)"
        return installed == original ? [original] : [installed, original]
    }

    /// Primeira pasta de grupo que o iOS liberou para este app (nil = sem permissão).
    static func container() -> (group: String, url: URL)? {
        for group in groupCandidates {
            if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) {
                return (group, url)
            }
        }
        return nil
    }

    // MARK: Dados

    /// Parte SEM valores em reais e sem nomes.
    struct PublicData: Codable, Equatable {
        enum EventKind: String, Codable { case income, recurring, planned, cardBill }
        struct Event: Codable, Equatable {
            var date: Date
            var kind: EventKind
            var isIncome: Bool
        }

        var updatedAt: Date
        var hasBank: Bool
        var hasCard: Bool
        var showValues: Bool
        var billDue: Date?
        var cardOverLimit: Bool
        /// Limite usado (0…1+); nil = banco não informou o limite.
        var cardUsedFraction: Double?
        var monthName: String
        /// Gasto ÷ orçamento do mês; nil = sem orçamento.
        var budgetFraction: Double?
        var daysLeftInMonth: Int
        /// Gastando mais rápido que o mês anda.
        var paceAlert: Bool
        var tightestDay: Date?
        var goesNegative: Bool
        /// Formato do saldo previsto (0…1), sem valores.
        var sparkline: [Double]
        var pendingCount: Int
        var nextEvents: [Event]

        static let empty = PublicData(updatedAt: .distantPast, hasBank: false, hasCard: false, showValues: false,
                                      billDue: nil, cardOverLimit: false, cardUsedFraction: nil, monthName: "",
                                      budgetFraction: nil, daysLeftInMonth: 0, paceAlert: false, tightestDay: nil,
                                      goesNegative: false, sparkline: [], pendingCount: 0, nextEvents: [])
    }

    /// Parte COM valores em reais e nomes (só com "Mostrar valores" ligado).
    struct Values: Codable, Equatable {
        struct Event: Codable, Equatable {
            var title: String
            var amount: Decimal
        }
        var balance: Decimal?
        var bill: Decimal?
        var spent: Decimal
        var budget: Decimal?
        var accountSpent: Decimal
        var cardSpent: Decimal
        var lowestBalance: Decimal?
        /// Na mesma ordem de `PublicData.nextEvents`.
        var events: [Event]
    }

    // MARK: Gravar e ler

    /// Grava os dados do widget. Sem `values`, apaga o arquivo de valores.
    /// Devolve o grupo usado, ou nil se não houver pasta compartilhada.
    @discardableResult
    static func write(_ data: PublicData, values: Values?) -> String? {
        guard let found = container() else { return nil }
        let encoder = JSONEncoder()
        do {
            try encoder.encode(data).write(to: found.url.appendingPathComponent(publicFile),
                                           options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            let valuesURL = found.url.appendingPathComponent(valuesFile)
            if let values {
                try encoder.encode(values).write(to: valuesURL, options: [.atomic, .completeFileProtection])
            } else {
                try? FileManager.default.removeItem(at: valuesURL)
            }
            for legacy in legacyFiles { try? FileManager.default.removeItem(at: found.url.appendingPathComponent(legacy)) }
            return found.group
        } catch {
            return nil
        }
    }

    static func readPublic() -> PublicData? {
        guard let found = container(),
              let data = try? Data(contentsOf: found.url.appendingPathComponent(publicFile)) else { return nil }
        return try? JSONDecoder().decode(PublicData.self, from: data)
    }

    /// Nil com o iPhone travado (arquivo fechado) ou com valores desligados.
    static func readValues() -> Values? {
        guard let found = container(),
              let data = try? Data(contentsOf: found.url.appendingPathComponent(valuesFile)) else { return nil }
        return try? JSONDecoder().decode(Values.self, from: data)
    }

    /// Apaga tudo (Apagar todos os dados).
    static func removeAll() {
        guard let found = container() else { return }
        for name in [publicFile, valuesFile] + legacyFiles {
            try? FileManager.default.removeItem(at: found.url.appendingPathComponent(name))
        }
    }
}
