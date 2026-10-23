import Foundation
import CryptoKit

/// Cofre local: um arquivo com contas e transações, cifrado com AES-GCM.
///
/// Três camadas de proteção, de dentro para fora:
/// 1. **AES-GCM com chave de 256 bits.** A chave é gerada no próprio iPhone e
///    fica no Keychain como `ThisDeviceOnly`: ela nunca vai para backups.
///    Uma cópia do arquivo, em qualquer outro aparelho ou computador, é ilegível.
///    O GCM também detecta adulteração: se um único byte mudar, a abertura falha.
/// 2. **Proteção de Dados "completa" do iOS.** Com o iPhone bloqueado, o próprio
///    sistema mantém o arquivo cifrado e inacessível.
/// 3. **Fora do backup.** O arquivo é marcado para não ir ao iCloud nem ao computador.
///    Se o app for reinstalado, os dados são baixados de novo do Pluggy.
enum Vault {
    enum VaultError: Error {
        case sealFailed
    }

    private static var directoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Cofre", isDirectory: true)
    }

    private static var fileURL: URL {
        directoryURL.appendingPathComponent("financas.cofre")
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

    static func save(_ snapshot: VaultSnapshot) throws {
        let plain = try JSONEncoder().encode(snapshot)
        let sealed = try AES.GCM.seal(plain, using: try key())
        guard let cipher = sealed.combined else { throw VaultError.sealFailed }

        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
        // .atomic: grava num arquivo temporário e troca no fim; um corte de
        // energia no meio nunca deixa o cofre pela metade.
        try cipher.write(to: fileURL, options: [.atomic, .completeFileProtection])

        var url = fileURL
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    /// Abre o cofre. Se ele não existir, devolve nil. Se estiver corrompido,
    /// adulterado ou a chave tiver sumido, o arquivo é descartado e devolve nil:
    /// na próxima sincronização tudo é baixado de novo.
    static func load() -> VaultSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let cipher = try Data(contentsOf: fileURL)
            let box = try AES.GCM.SealedBox(combined: cipher)
            let plain = try AES.GCM.open(box, using: try key())
            return try JSONDecoder().decode(VaultSnapshot.self, from: plain)
        } catch {
            destroy()
            return nil
        }
    }

    /// Apaga o arquivo e a chave.
    static func destroy() {
        try? FileManager.default.removeItem(at: directoryURL)
        KeychainStore.delete(.vaultKey)
    }
}
