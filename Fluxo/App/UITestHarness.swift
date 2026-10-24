#if DEBUG
import SwiftUI
import UIKit
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
                Section("Preparação do teste") {
                    // Salva um arquivo SINTÉTICO em "No meu iPhone" pelo próprio iOS
                    // (copiar direto para a pasta do simulador não aparece no seletor).
                    Button("Salvar arquivo de teste") { exportFixture() }
                        .accessibilityIdentifier("prep.export")
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

    private func exportFixture() {
        let lines = ["OFXHEADER:100", "<OFX>", "<CREDITCARDMSGSRSV1><CCSTMTTRNRS><CCSTMTRS><BANKTRANLIST>",
                     "<STMTTRN>", "<TRNTYPE>DEBIT", "<DTPOSTED>20261001000000[-3:BRT]", "<TRNAMT>-200.50", "<MEMO>Loja Exemplo", "</STMTTRN>",
                     "<STMTTRN>", "<TRNTYPE>DEBIT", "<DTPOSTED>20261002000000[-3:BRT]", "<TRNAMT>-50.00", "<MEMO>Mercado Exemplo - Parcela 2/3", "</STMTTRN>",
                     "<STMTTRN>", "<TRNTYPE>CREDIT", "<DTPOSTED>20261003000000[-3:BRT]", "<TRNAMT>182.50", "<MEMO>Estorno Exemplo", "</STMTTRN>",
                     "</BANKTRANLIST><LEDGERBAL><BALAMT>-150.00</BALAMT></LEDGERBAL></CCSTMTRS></CCSTMTTRNRS></CREDITCARDMSGSRSV1></OFX>"]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Teste_2026-11-08.ofx")
        try? lines.joined(separator: "\n").data(using: .utf8)?.write(to: url)
        guard let top = DocumentPickerPresenter.topViewController() else { return }
        let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        top.present(picker, animated: true)
        result = "exportando"
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
