import UIKit
import UniformTypeIdentifiers

/// Formas de trazer o arquivo da fatura para dentro do app.
///
/// 1. **Colar** (`fromProviders`): o app Arquivos ("Copiar") e o menu Compartilhar
///    ("Copiar") põem o CONTEÚDO do arquivo na área de transferência. O app recebe
///    os bytes, sem precisar de permissão de acesso ao arquivo. É o caminho mais
///    robusto, inclusive em apps instalados fora da App Store.
/// 2. **Seletor** (`DocumentPickerPresenter`): o seletor do iOS, apresentado pelo
///    UIKit (forma recomendada pela Apple), com cópia do arquivo para dentro do app.
enum BillIntake {
    /// Identificador declarado no Info.plist para arquivos .ofx.
    static let ofxType = "com.soturnna.fluxo.ofx"

    /// Tipos que nunca são o conteúdo do arquivo (são links para ele).
    private static let skipped: Set<String> = ["public.file-url", "public.url", "com.apple.finder.node"]

    /// Ordem de preferência dos tipos oferecidos por um item colado.
    static func preferredType(in identifiers: [String]) -> String? {
        let usable = identifiers.filter { !skipped.contains($0) }
        func conforms(_ id: String, to type: UTType) -> Bool { UTType(id)?.conforms(to: type) ?? false }
        if let ofx = usable.first(where: { $0 == ofxType || $0.lowercased().contains("ofx") }) { return ofx }
        if let csv = usable.first(where: { conforms($0, to: .commaSeparatedText) }) { return csv }
        if let text = usable.first(where: { conforms($0, to: .text) }) { return text }
        return usable.first { id in
            guard let type = UTType(id) else { return id.hasPrefix("dyn.") }
            return type.conforms(to: .data) && !type.conforms(to: .image) && !type.conforms(to: .audiovisualContent)
        }
    }

    /// Lê a fatura do primeiro item colado que tiver um conteúdo legível.
    static func fromProviders(_ providers: [NSItemProvider]) async throws -> BillFile {
        var lastError: Error = BillImportError.unreadable
        for provider in providers {
            guard let type = preferredType(in: provider.registeredTypeIdentifiers) else { continue }
            do {
                let data = try await loadData(provider, type: type)
                return try BillFileParser.parse(data: data, fileName: provider.suggestedName ?? "")
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private static func loadData(_ provider: NSItemProvider, type: String) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: type) { data, error in
                if let data, data.count <= BillFileParser.maxBytes {
                    continuation.resume(returning: data)
                } else if let data, data.count > BillFileParser.maxBytes {
                    continuation.resume(throwing: BillImportError.tooLarge)
                } else {
                    continuation.resume(throwing: error ?? BillImportError.unreadable)
                }
            }
        }
    }
}

/// Apresenta o seletor do iOS por cima da tela que estiver no topo (UIKit `present`).
/// Fica fora do SwiftUI de propósito: o seletor dentro de uma folha do SwiftUI
/// pode não responder ao toque no arquivo.
@MainActor
final class DocumentPickerPresenter: NSObject, UIDocumentPickerDelegate {
    static let shared = DocumentPickerPresenter()
    private var onPick: ((URL) -> Void)?

    func present(onPick: @escaping (URL) -> Void) {
        guard let top = Self.topViewController() else { return }
        self.onPick = onPick
        let types: [UTType] = [UTType(BillIntake.ofxType), .commaSeparatedText, .plainText, .data].compactMap { $0 }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        picker.delegate = self
        picker.modalPresentationStyle = .formSheet
        top.present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        let handler = onPick
        onPick = nil
        if let url = urls.first { handler?(url) }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        onPick = nil
    }

    /// A tela mais ao topo da janela principal (nível normal, não a de bloqueio).
    static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first { $0.windowLevel == .normal && !$0.isHidden }
        var top = window?.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed { top = presented }
        return top
    }
}
