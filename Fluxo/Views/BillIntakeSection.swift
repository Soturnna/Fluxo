import SwiftUI
import UniformTypeIdentifiers

/// As duas formas de trazer a fatura (CSV/OFX) para o app, usadas no Cartão e no agente.
///
/// 1. **Colar** (recomendado): no app Arquivos, "Copiar" o arquivo e tocar em Colar
///    aqui. O app recebe só o conteúdo, sem acesso ao arquivo. É o `PasteButton` do
///    sistema: o iOS não pede permissão porque é você que toca no botão.
/// 2. **Escolher no Arquivos**: o seletor do iOS, apresentado de forma modal.
struct BillIntakeSection: View {
    let onFile: (BillFile) -> Void
    let onError: (String) -> Void
    @State private var reading = false

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("1. No app Arquivos, toque e segure o arquivo da fatura (.ofx ou .csv) e escolha **Copiar**.")
                Text("2. Volte aqui e toque em **Colar**.")
            }
            .font(.subheadline)
            .padding(.vertical, 4)

            HStack {
                PasteButton(supportedContentTypes: [.data]) { providers in
                    Task { @MainActor in await paste(providers) }
                }
                .labelStyle(.titleAndIcon)
                .buttonBorderShape(.capsule)
                .tint(Theme.forest)
                .accessibilityIdentifier("bill.paste")
                if reading { ProgressView().padding(.leading, 8) }
            }
        } header: {
            Text("Colar o arquivo (recomendado)")
        } footer: {
            Text("No app do Nubank também dá: exporte a fatura, toque em Copiar no menu de compartilhar e cole aqui.")
        }

        Section {
            Button {
                DocumentPickerPresenter.shared.present { url in read(url) }
            } label: {
                Label("Escolher no app Arquivos", systemImage: "folder")
            }
            .accessibilityIdentifier("bill.pick")
        } footer: {
            Text("O arquivo é lido só neste iPhone e descartado em seguida. Nada vai para a internet nem para a IA.")
        }
    }

    @MainActor
    private func paste(_ providers: [NSItemProvider]) async {
        reading = true
        defer { reading = false }
        do {
            onFile(try await BillIntake.fromProviders(providers))
        } catch {
            onError((error as? LocalizedError)?.errorDescription
                    ?? "Não consegui ler o que foi colado. Copie o arquivo .ofx ou .csv da fatura e tente de novo.")
        }
    }

    private func read(_ url: URL) {
        do {
            onFile(try BillFileParser.read(url, deleteAfter: true))
        } catch {
            onError((error as? LocalizedError)?.errorDescription ?? BillImportError.unreadable.errorDescription ?? "")
        }
    }
}
