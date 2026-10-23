import Foundation
import CryptoKit

/// Cofre local: arquivos cifrados com AES-GCM.
///
/// Três camadas de proteção, de dentro para fora:
/// 1. **AES-GCM com chave de 256 bits.** A chave é gerada no próprio iPhone e
///    fica no Keychain como `ThisDeviceOnly`: ela nunca vai para backups.
///    Uma cópia dos arquivos, em qualquer outro aparelho ou computador, é ilegível.
///    O GCM também detecta adulteração: se um único byte mudar, a abertura falha.
/// 2. **Proteção de Dados "completa" do iOS.** Com o iPhone bloqueado, o próprio
///    sistema mantém os arquivos cifrados e inacessíveis.
/// 3. **Fora do backup.** Os arquivos não vão ao iCloud nem ao computador.
enum Vault {
    /// Cada "gaveta" do cofre é um arquivo separado, com a mesma chave.
    enum Drawer: String {
        case finance = "financas.cofre"      // contas e transações (recriável pelo Pluggy)
        case userData = "meus-dados.cofre"   // categorias, trocas e orçamentos (só existem aqui)
    }

    enum VaultError: Error {
        case sealFailed
    }

    private static var directoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Cofre", isDirectory: true)
    }

    private static func fileURL(_ drawer: Drawer) -> URL {
        directoryURL.appendingPathComponent(drawer.rawValue)
    }

    // MARK: Chave

    /// Busca a chave no Keychain ou, na primeira vez, gera uma nova.
    private static func key() throws -> SymmetricKey {
        if let stored = KeychainStore.read(.vaultKey),
           let data = Data(base64Encoded: stored),
           data.count == 32 {
            return SymmetricKey(data: data)
        }
        let newKey = SymmetricKey(size: .bits256)   // gerador aleatório seguro do sistema
        let raw = newKey.withUnsafeBytes { Data($0) }
        try KeychainStore.save(raw.base64EncodedString(), for: .vaultKey)
        return newKey
    }

    // MARK: Gravar e ler

    static func save<T: Encodable>(_ value: T, in drawer: Drawer) throws {
        let plain = try JSONEncoder().encode(value)
        let sealed = try AES.GCM.seal(plain, using: try key())
        guard let cipher = sealed.combined else { throw VaultError.sealFailed }

        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
        // .atomic: grava num arquivo temporário e troca no fim; um corte de
        // energia no meio nunca deixa o cofre pela metade.
        var url = fileURL(drawer)
        try cipher.write(to: url, options: [.atomic, .completeFileProtection])

        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    /// Abre uma gaveta. Se ela não existir, devolve nil. Se estiver corrompida
    /// ou adulterada, só aquele arquivo é descartado e devolve nil.
    static func load<T: Decodable>(_ type: T.Type, from drawer: Drawer) -> T? {
        let url = fileURL(drawer)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let cipher = try Data(contentsOf: url)
            let box = try AES.GCM.SealedBox(combined: cipher)
            let plain = try AES.GCM.open(box, using: try key())
            return try JSONDecoder().decode(T.self, from: plain)
        } catch {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
    }

    /// Apaga todas as gavetas e a chave.
    static func destroy() {
        try? FileManager.default.removeItem(at: directoryURL)
        KeychainStore.delete(.vaultKey)
    }
}
