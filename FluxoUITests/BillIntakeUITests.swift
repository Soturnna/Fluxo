import XCTest

/// Testes de interface no simulador: abre a tela de teste (só existe em Debug),
/// usa cada entrada de fatura e confere o resultado. Cada passo deixa um print.
final class BillIntakeUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITestHarness"]
        app.launch()
    }

    private func snap(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name + " (árvore)"
        tree.lifetime = .keepAlways
        add(tree)
    }

    private func fixture(_ ext: String) throws -> Data {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Teste_2026-11-08", withExtension: ext))
        return try Data(contentsOf: url)
    }

    private func expectResult(_ prefix: String, file: StaticString = #filePath, line: UInt = #line) {
        let result = app.staticTexts["result"]
        let ok = NSPredicate(format: "label BEGINSWITH %@", prefix)
        let found = XCTWaiter.wait(for: [expectation(for: ok, evaluatedWith: result)], timeout: 15) == .completed
        snap("resultado")
        XCTAssertTrue(found, "resultado: \(result.label)", file: file, line: line)
    }

    // MARK: Colar

    private func paste(_ data: Data, type: String) {
        UIPasteboard.general.setItems([[type: data]])
        snap("antes de colar (\(type))")
        let button = app.buttons["paste"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        button.tap()
        // Se o iOS pedir permissão de colar, aceita.
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow Paste"]
        if allow.waitForExistence(timeout: 2) { allow.tap() }
    }

    func testPasteOFXDeclaredType() throws {
        paste(try fixture("ofx"), type: "com.soturnna.fluxo.ofx")
        expectResult("OK linhas=7 soma=68 banco=150")
    }

    func testPasteCSV() throws {
        paste(try fixture("csv"), type: "public.comma-separated-values-text")
        expectResult("OK linhas=7 soma=68")
    }

    // MARK: Seletor de arquivos (o workflow põe o arquivo em "No meu iPhone")

    private func pick(_ id: String) {
        app.buttons[id].tap()
        sleep(3)
        snap("seletor aberto")
        let name = NSPredicate(format: "label CONTAINS 'Teste_2026-11-08'")
        var target = app.descendants(matching: .any).matching(name).firstMatch
        if !target.waitForExistence(timeout: 3) {
            for label in ["Browse", "Explorar"] where app.buttons[label].exists { app.buttons[label].tap(); break }
            sleep(2)
            snap("explorar")
            for label in ["On My iPhone", "No Meu iPhone", "On My iPad"] {
                let place = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
                if place.exists { place.tap(); break }
            }
            sleep(2)
            snap("no meu iphone")
            target = app.descendants(matching: .any).matching(name).firstMatch
        }
        XCTAssertTrue(target.waitForExistence(timeout: 10), "arquivo não apareceu no seletor")
        target.tap()
        sleep(2)
        snap("depois do toque no arquivo")
    }

    func testPickerUIKit() {
        pick("pick.uikit")
        expectResult("OK linhas=7 soma=68 banco=150")
    }

    func testPickerSwiftUI() {
        pick("pick.swiftui")
        expectResult("OK linhas=7 soma=68 banco=150")
    }

    func testPickerInSheet() {
        pick("pick.sheet")
        expectResult("OK linhas=7 soma=68 banco=150")
    }
}
