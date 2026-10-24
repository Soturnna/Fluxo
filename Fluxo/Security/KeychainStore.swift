import Foundation
import Security

/// Nomes das credenciais guardadas no Keychain.
enum KeychainKey: String, CaseIterable {
    case pluggyClientId = "pluggy.clientId"
    case pluggyClientSecret = "pluggy.clientSecret"
    case pluggyItemIds = "pluggy.itemIds"
    case geminiApiKey = "gemini.apiKey"
    case brapiToken = "brapi.token"         // cotações (só códigos de ativos saem do iPhone)
    case vaultKey = "vault.key"          // chave que cifra o cofre local
}

enum KeychainError: LocalizedError {
    case unexpectedStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            return "Keychain retornou o código \(status)"
        }
    }
}

/// Acesso ao Keychain do iOS: o cofre criptografado do próprio sistema.
///
/// Por que o Keychain e não o UserDefaults?
/// O UserDefaults é um arquivo comum dentro do app. O Keychain é criptografado
/// com chaves protegidas pelo hardware do iPhone e, com a opção usada aqui,
/// só libera os dados com o aparelho desbloqueado.
enum KeychainStore {
    private static let service = "com.soturnna.fluxo"

    /// Consulta-base: identifica um item pelo serviço (o app) e pela conta (o nome da chave).
    private static func baseQuery(_ key: KeychainKey) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
    }

    /// Grava ou substitui um valor.
    static func save(_ value: String, for key: KeychainKey) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            // WhenUnlocked: só legível com o iPhone desbloqueado.
            // ThisDeviceOnly: não vai para backups nem migra para outro aparelho.
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        // Primeiro tenta atualizar; se o item ainda não existe, cria.
        let updateStatus = SecItemUpdate(baseQuery(key) as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var newItem = baseQuery(key)
            newItem.merge(attributes) { _, new in new }
            let addStatus = SecItemAdd(newItem as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.unexpectedStatus(addStatus) }
        } else if updateStatus != errSecSuccess {
            throw KeychainError.unexpectedStatus(updateStatus)
        }
    }

    /// Lê um valor. Usado só no momento de chamar a API, nunca para exibir na tela.
    static func read(_ key: KeychainKey) -> String? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Diz se o item existe SEM carregar o segredo para a memória.
    static func exists(_ key: KeychainKey) -> Bool {
        var query = baseQuery(key)
        query[kSecReturnData as String] = false
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    static func delete(_ key: KeychainKey) {
        SecItemDelete(baseQuery(key) as CFDictionary)
    }

    /// Apaga todas as credenciais do Fluxo.
    static func deleteAll() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        SecItemDelete(query as CFDictionary)
    }
}
