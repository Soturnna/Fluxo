import XCTest
import UniformTypeIdentifiers
@testable import Fluxo

/// Leitura da fatura (CSV/OFX no formato do Nubank) com dados SINTÉTICOS.
final class BillParserTests: XCTestCase {

    private func fixture(_ name: String, _ ext: String) throws -> Data {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: ext), "fixture \(name).\(ext)")
        return try Data(contentsOf: url)
    }

    func testCSVNubank() throws {
        let file = try BillFileParser.parse(data: fixture("Teste_2026-11-08", "csv"), fileName: "Teste_2026-11-08.csv")
        XCTAssertEqual(file.lines.count, 7, "pagamento recebido fica de fora")
        XCTAssertEqual(file.total, Decimal(string: "68.00"))
        XCTAssertNil(file.bankTotal)
        let loja = try XCTUnwrap(file.lines.first { $0.title == "Loja Exemplo" })
        XCTAssertEqual(loja.installment, "2/3")
        XCTAssertEqual(loja.amount, Decimal(string: "-50.00"), "compra fica negativa")
        let reneg = try XCTUnwrap(file.lines.first { $0.installment == "1/4" })
        XCTAssertEqual(reneg.title, "Renegociação de pendências (08/Outubro)")
        XCTAssertEqual(file.lines.first { $0.amount > 0 && $0.title.hasPrefix("Renegocia") }?.amount, Decimal(string: "300.00"))
        let day = Calendar.current.dateComponents([.year, .month, .day], from: try XCTUnwrap(file.nameDate))
        XCTAssertEqual([day.year, day.month, day.day], [2026, 11, 8])
    }

    func testOFXNubank() throws {
        let file = try BillFileParser.parse(data: fixture("Teste_2026-11-08", "ofx"), fileName: "Teste_2026-11-08.ofx")
        XCTAssertEqual(file.lines.count, 7)
        XCTAssertEqual(file.total, Decimal(string: "68.00"))
        XCTAssertEqual(file.bankTotal, Decimal(string: "150.00"), "LEDGERBAL vira o total do banco")
        XCTAssertEqual(file.lines.first { $0.title == "Mercado Exemplo" }?.amount, Decimal(string: "-35.40"))
    }

    // MARK: Colar (o app Arquivos põe o conteúdo do arquivo na área de transferência)

    private func provider(_ data: Data, types: [String], name: String? = "Teste_2026-11-08") -> NSItemProvider {
        let provider = NSItemProvider()
        for type in types {
            provider.registerDataRepresentation(forTypeIdentifier: type, visibility: .all) { completion in
                completion(type == "public.file-url" ? Data("file:///nao/existe.ofx".utf8) : data, nil)
                return nil
            }
        }
        provider.suggestedName = name
        return provider
    }

    func testPasteWithDeclaredOFXType() async throws {
        let file = try await BillIntake.fromProviders([provider(fixture("Teste_2026-11-08", "ofx"), types: [BillIntake.ofxType])])
        XCTAssertEqual(file.lines.count, 7)
        XCTAssertEqual(file.bankTotal, Decimal(string: "150.00"))
    }

    func testPasteWithDynamicType() async throws {
        let dynamic = try XCTUnwrap(UTType(filenameExtension: "qfx", conformingTo: .data)).identifier
        let file = try await BillIntake.fromProviders([provider(fixture("Teste_2026-11-08", "ofx"), types: ["public.file-url", dynamic])])
        XCTAssertEqual(file.lines.count, 7)
    }

    func testPasteCSVAndPlainText() async throws {
        let csv = try fixture("Teste_2026-11-08", "csv")
        let fromCSV = try await BillIntake.fromProviders([provider(csv, types: [UTType.commaSeparatedText.identifier])])
        XCTAssertEqual(fromCSV.total, Decimal(string: "68.00"))
        let fromText = try await BillIntake.fromProviders([provider(csv, types: [UTType.utf8PlainText.identifier], name: nil)])
        XCTAssertEqual(fromText.lines.count, 7)
    }

    func testPreferredTypeSkipsLinks() {
        XCTAssertEqual(BillIntake.preferredType(in: ["public.file-url", "public.data"]), "public.data")
        XCTAssertNil(BillIntake.preferredType(in: ["public.file-url", "public.url"]))
        XCTAssertNil(BillIntake.preferredType(in: ["public.png"]))
    }

    func testReadFileAndDeleteCopy() throws {
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("Teste_2026-11-08.ofx")
        try fixture("Teste_2026-11-08", "ofx").write(to: copy)
        let file = try BillFileParser.read(copy, deleteAfter: true)
        XCTAssertEqual(file.lines.count, 7)
        XCTAssertFalse(FileManager.default.fileExists(atPath: copy.path), "a cópia é apagada depois de ler")
    }
}
