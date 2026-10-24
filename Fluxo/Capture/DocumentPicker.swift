import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Seletor do app Arquivos (UIKit). Usado no lugar do `.fileImporter` do SwiftUI,
/// que deixava os arquivos .ofx/.csv cinza (sem poder tocar).
///
/// `asCopy: true`: o iOS entrega uma CÓPIA dentro do app, sem precisar de
/// permissão de acesso ao arquivo original. Quem recebe apaga a cópia depois de ler.
struct DocumentPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first { onPick(url) }
        }
    }
}
