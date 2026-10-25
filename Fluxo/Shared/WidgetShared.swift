import Foundation

/// Pasta compartilhada entre o app e o widget (App Group).
///
/// Instalado pelo iloader, o app ganha outro identificador (com.soturnna.fluxo.<EQUIPE>)
/// e o grupo criado é "group.<esse identificador>". Por isso o nome do grupo é
/// descoberto na hora, a partir do identificador do próprio app.
///
/// ETAPA 1 (teste técnico): só um horário e um texto, nenhum dado financeiro.
enum WidgetShared {
    static let baseBundleID = "com.soturnna.fluxo"
    private static let fileName = "widget.json"

    /// Identificador do app principal. Dentro do widget (.appex), tira o último pedaço (".widget").
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

    struct Snapshot: Codable, Equatable {
        var updatedAt: Date
        var note: String
    }

    /// Grava o resumo do widget. Devolve o grupo usado, ou nil se não houver pasta compartilhada.
    @discardableResult
    static func write(_ snapshot: Snapshot) -> String? {
        guard let found = container() else { return nil }
        do {
            let data = try JSONEncoder().encode(snapshot)
            // Legível depois do primeiro desbloqueio (o widget também desenha com o iPhone travado).
            try data.write(to: found.url.appendingPathComponent(fileName),
                           options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return found.group
        } catch {
            return nil
        }
    }

    static func read() -> Snapshot? {
        guard let found = container(),
              let data = try? Data(contentsOf: found.url.appendingPathComponent(fileName)) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }
}
