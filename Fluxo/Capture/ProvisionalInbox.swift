import Foundation
import UIKit

/// Caixa de entrada de lançamentos que chegam de FORA do app (o atalho do
/// Apple Pay). O atalho pode rodar com o iPhone bloqueado, quando o cofre
/// está fechado; por isso ele não grava no cofre, e sim aqui.
///
/// Segurança: cada lançamento é um arquivo novo com a proteção do iOS
/// "CompleteUnlessOpen". Com ela, dá para CRIAR o arquivo com o iPhone
/// bloqueado, mas ninguém consegue LER antes do desbloqueio. Ao abrir o app
/// desbloqueado, tudo passa para o cofre cifrado e a caixa é esvaziada.
enum ProvisionalInbox {
    struct Item: Codable {
        let id: String
        let date: Date
        let title: String
        let amount: Decimal
        let method: ProvisionalEntry.Method
        let source: ProvisionalEntry.Source
    }

    private static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("caixa-de-entrada", isDirectory: true)
    }

    static func add(_ item: Item) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var url = directory.appendingPathComponent("\(item.id).json")
        let data = try JSONEncoder().encode(item)
        try data.write(to: url, options: [.withoutOverwriting, .completeFileProtectionUnlessOpen])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    /// Passa tudo para o cofre e apaga os arquivos. Só com o iPhone desbloqueado.
    @MainActor
    @discardableResult
    static func drain(into store: FinanceStore) -> Int {
        guard UIApplication.shared.isProtectedDataAvailable,
              let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else { return 0 }

        var imported = 0
        let decoder = JSONDecoder()
        for file in files.prefix(100) where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file),
               let item = try? decoder.decode(Item.self, from: data) {
                let entry = ProvisionalEntry(id: item.id, date: item.date, title: item.title, counterparty: nil,
                                             amount: item.amount, method: item.method, source: item.source)
                if store.saveProvisional(entry) { imported += 1 }
            }
            // Lido ou inválido, sai da caixa: nada fica fora do cofre.
            try? FileManager.default.removeItem(at: file)
        }
        return imported
    }

    static func removeAll() {
        try? FileManager.default.removeItem(at: directory)
    }
}
