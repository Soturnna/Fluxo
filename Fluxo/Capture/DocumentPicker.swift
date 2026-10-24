import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Seletor do app Arquivos (UIKit), usado no lugar do `.fileImporter`.
///
/// `asCopy: true`: o iOS entrega uma CÓPIA dentro do app, sem acesso ao original.
/// Quem recebe apaga a cópia depois de ler. O seletor fica dentro de uma folha do
/// SwiftUI, então ele mesmo fecha a folha (`isPresented = false`) ao escolher.
struct DocumentPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType] = [UTType("com.soturnna.fluxo.ofx"), .commaSeparatedText, .item].compactMap { $0 }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        var parent: DocumentPicker
        init(parent: DocumentPicker) { self.parent = parent }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            parent.isPresented = false
            if let url = urls.first { parent.onPick(url) }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.isPresented = false
        }
    }
}

/// Fatura recebida pelo "Compartilhar → Fluxo" (ou "Abrir com"). Fica guardada só
/// na memória até o app estar desbloqueado; então a tela do app a abre.
@MainActor
final class IncomingBill: ObservableObject {
    static let shared = IncomingBill()
    @Published var pending: URL?

    func receive(_ url: URL) {
        guard url.isFileURL else { return }
        if let old = pending, old != url { try? FileManager.default.removeItem(at: old) }
        pending = url
    }
}
