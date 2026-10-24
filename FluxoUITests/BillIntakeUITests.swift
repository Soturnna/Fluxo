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

    // MARK: Seletor de arquivos

    private func pick(_ id: String) {
        app.buttons[id].tap()
        sleep(3)
        snap("seletor aberto")
        let name = NSPredicate(format: "label CONTAINS 'Teste_2026-11-08'")
        var target = app.descendants(matching: .any).matching(name).firstMatch
        if !target.waitForExistence(timeout: 5) {
            let tab = app.tabBars.buttons.matching(NSPredicate(format: "label IN %@", ["Browse", "Explorar"])).firstMatch
            if tab.exists { tab.tap(); sleep(2) }
            snap("explorar")
            let place = app.cells.matching(NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@", "On My", "No Meu")).firstMatch
            if place.exists && place.isHittable { place.tap(); sleep(2) }
            snap("no meu iphone")
            // Pasta do app (compartilhamento ligado só na compilação de teste).
            let folder = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Fluxo'")).firstMatch
            if folder.exists && folder.isHittable { folder.tap(); sleep(2) }
            snap("pasta fluxo")
            target = app.descendants(matching: .any).matching(name).firstMatch
        }
        XCTAssertTrue(target.waitForExistence(timeout: 20), "arquivo não apareceu no seletor")
        target.tap()
        sleep(2)
        snap("depois do toque no arquivo")
    }

    func testPickerUIKit() {
        pick("pick.uikit")
        expectResult("OK linhas=3 soma=68 banco=150")
    }

    /// Investigação: `.fileImporter` do SwiftUI (builds 26 e 27). O app não usa mais;
    /// a árvore de acessibilidade dele às vezes demora, então não reprova a suíte.
    func testZPickerSwiftUIInvestigation() {
        app.buttons["pick.swiftui"].tap()
        sleep(6)
        let file = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Teste_2026-11-08'")).firstMatch
        let visible = file.waitForExistence(timeout: 10)
        if visible { file.tap(); sleep(3) }
        snap("fileImporter depois")
        print("INVESTIGACAO fileImporter (builds 26-27): arquivo acessivel=\(visible) resultado=\(app.staticTexts["result"].label)")
    }

    /// Investigação: seletor dentro de uma folha do SwiftUI (builds 28 e 29).
    /// Não reprova a suíte; registra no log o que aconteceu.
    func testZPickerInSheetInvestigation() {
        app.buttons["pick.sheet"].tap()
        sleep(4)
        snap("seletor em folha")
        let file = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Teste_2026-11-08'")).firstMatch
        let visible = file.waitForExistence(timeout: 5)
        if visible { file.tap(); sleep(3) }
        snap("seletor em folha depois")
        let result = app.staticTexts["result"].label
        print("INVESTIGACAO seletor em folha (builds 28-29): arquivo acessivel=\(visible) resultado=\(result)")
    }
}
