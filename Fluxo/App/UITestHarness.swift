#if DEBUG
import SwiftUI
import UniformTypeIdentifiers

/// Tela SÓ PARA TESTES AUTOMÁTICOS no simulador (compilada apenas em Debug; a .ipa
/// é Release e não contém este arquivo). Abre com o argumento `-UITestHarness`.
/// Exercita as três entradas de fatura sem cofre, sem Face ID e sem dados reais.
struct UITestHarnessView: View {
    @State private var result = "aguardando"
    @State private var swiftUIPicker = false
    @State private var sheetPicker = false

    var body: some View {
        NavigationStack {
            List {
                Section("Entradas da fatura") {
                    Button("Seletor UIKit") {
                        DocumentPickerPresenter.shared.present { url in show(url) }
                    }
                    .accessibilityIdentifier("pick.uikit")

                    Button("Seletor SwiftUI") { swiftUIPicker = true }
                        .accessibilityIdentifier("pick.swiftui")

                    Button("Seletor em folha") { sheetPicker = true }
                        .accessibilityIdentifier("pick.sheet")

                    PasteButton(supportedContentTypes: [.data]) { providers in
                        Task { @MainActor in
                            do { report(try await BillIntake.fromProviders(providers), via: "colar") }
                            catch { result = "ERRO colar: \(error.localizedDescription)" }
                        }
                    }
                    .accessibilityIdentifier("paste")
                }
                Section("Resultado") {
                    Text(result).accessibilityIdentifier("result")
                }
            }
            .navigationTitle("Teste de fatura")
        }
        .fileImporter(isPresented: $swiftUIPicker, allowedContentTypes: BillFileParser.contentTypes) { outcome in
            switch outcome {
            case .success(let url): show(url)
            case .failure(let error): result = "ERRO swiftui: \(error.localizedDescription)"
            }
        }
        .sheet(isPresented: $sheetPicker) {
            DocumentPicker(isPresented: $sheetPicker) { url in show(url) }
                .ignoresSafeArea()
        }
    }

    private func show(_ url: URL) {
        do { report(try BillFileParser.read(url, deleteAfter: false), via: url.lastPathComponent) }
        catch { result = "ERRO arquivo: \(error.localizedDescription)" }
    }

    private func report(_ file: BillFile, via source: String) {
        let bank = file.bankTotal.map { "\($0)" } ?? "-"
        result = "OK linhas=\(file.lines.count) soma=\(file.total) banco=\(bank) fonte=\(source)"
    }
}
#endif
