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
                Section("Resultado") {
                    Text(result).accessibilityIdentifier("result")
                }
            }
            .navigationTitle("Teste de fatura")
        }
        .onAppear { Self.writeFixture() }
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

    /// Arquivo SINTÉTICO na pasta Documentos do app. O workflow de testes liga o
    /// compartilhamento de arquivos só na compilação de teste, então a pasta aparece
    /// em "No meu iPhone › Fluxo" no seletor (a .ipa não expõe a pasta).
    static func writeFixture() {
        let lines = ["OFXHEADER:100", "<OFX>", "<CREDITCARDMSGSRSV1><CCSTMTTRNRS><CCSTMTRS><BANKTRANLIST>",
                     "<STMTTRN>", "<TRNTYPE>DEBIT", "<DTPOSTED>20261001000000[-3:BRT]", "<TRNAMT>-200.50", "<MEMO>Loja Exemplo", "</STMTTRN>",
                     "<STMTTRN>", "<TRNTYPE>DEBIT", "<DTPOSTED>20261002000000[-3:BRT]", "<TRNAMT>-50.00", "<MEMO>Mercado Exemplo - Parcela 2/3", "</STMTTRN>",
                     "<STMTTRN>", "<TRNTYPE>CREDIT", "<DTPOSTED>20261003000000[-3:BRT]", "<TRNAMT>182.50", "<MEMO>Estorno Exemplo", "</STMTTRN>",
                     "</BANKTRANLIST><LEDGERBAL><BALAMT>-150.00</BALAMT></LEDGERBAL></CCSTMTRS></CCSTMTTRNRS></CREDITCARDMSGSRSV1></OFX>"]
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        try? lines.joined(separator: "\n").data(using: .utf8)?.write(to: docs.appendingPathComponent("Teste_2026-11-08.ofx"))
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

#if DEBUG
/// Galeria SÓ PARA TESTE: desenha as telas dos widgets (as mesmas do widget de verdade)
/// nos tamanhos do iPhone, com dados FICTÍCIOS, para conferir o layout por print.
struct UITestWidgetGallery: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                gallery(title: "Valores visíveis", data: WidgetSamples.data(showValues: true))
                gallery(title: "Valores ocultos", data: WidgetSamples.data(showValues: false))
                lockScreen(WidgetSamples.data(showValues: false))
                gallery(title: "Sem dados", data: WidgetData(info: .empty, values: nil, now: .now))
            }
            .padding(12)
        }
        .background(Color(red: 0.2, green: 0.26, blue: 0.23))
    }

    @ViewBuilder
    private func gallery(title: String, data: WidgetData) -> some View {
        Text(title).font(.headline).foregroundStyle(.white).accessibilityIdentifier("gallery.\(title)")
        HStack(spacing: 14) {
            frame(ResumoWidgetView(data: data), ResumoWidgetView.background, width: 170)
            frame(RegistrarWidgetView(data: data), RegistrarWidgetView.background, width: 170)
        }
        frame(MesWidgetView(data: data), MesWidgetView.background, width: 354)
        frame(ProximosWidgetView(data: data), ProximosWidgetView.background, width: 354)
        frame(CartaoWidgetView(data: data), CartaoWidgetView.background, width: 170)
    }

    private func frame<V: View>(_ view: V, _ background: Color, width: CGFloat) -> some View {
        view
            .padding(16)
            .frame(width: width, height: 170)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    @ViewBuilder
    private func lockScreen(_ data: WidgetData) -> some View {
        Text("Tela bloqueada").font(.headline).foregroundStyle(.white)
        VStack(spacing: 12) {
            FaturaInlineView(data: data).font(.subheadline.weight(.semibold))
            HStack(spacing: 12) {
                FaturaRectView(data: data).frame(width: 172, height: 76)
                DiasCircularView(data: data).frame(width: 76, height: 76)
                OrcamentoCircularView(data: data).frame(width: 76, height: 76)
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color(red: 0.13, green: 0.19, blue: 0.16), in: RoundedRectangle(cornerRadius: 22))
    }
}
#endif
