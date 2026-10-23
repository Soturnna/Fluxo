import Foundation

/// Registro de tudo o que saiu do iPhone para o Gemini.
///
/// Serve para você auditar: cada pergunta e cada resultado de ferramenta
/// enviado fica guardado (cifrado, na gaveta "registro" do cofre). São
/// mantidos só os 100 envios mais recentes.
@MainActor
final class AuditLog: ObservableObject {
    struct Entry: Codable, Identifiable {
        enum Kind: String, Codable {
            case question     // sua pergunta
            case toolData     // dados que uma ferramenta devolveu à IA
        }

        var id = UUID()
        let date: Date
        let kind: Kind
        let content: String
    }

    @Published private(set) var entries: [Entry]

    private static let maxEntries = 100
    private static let maxContentLength = 4000

    init() {
        entries = Vault.load([Entry].self, from: .auditLog) ?? []
    }

    func record(kind: Entry.Kind, content: String) {
        let entry = Entry(date: .now, kind: kind, content: String(content.prefix(Self.maxContentLength)))
        entries.insert(entry, at: 0)
        if entries.count > Self.maxEntries {
            entries.removeLast(entries.count - Self.maxEntries)
        }
        try? Vault.save(entries, in: .auditLog)
    }

    func clear() {
        entries = []
        try? Vault.save(entries, in: .auditLog)
    }
}
