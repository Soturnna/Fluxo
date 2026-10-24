import XCTest

/// O APP DE VERDADE (não a tela de teste): agente › foto › "Conferir fatura com arquivo".
/// Sem bloqueio só aqui, pelo argumento de lançamento `-security.requireAuth NO`
/// (o iPhone não passa argumentos ao abrir um app; isso só existe em teste).
final class RealAppBillUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        // A tela de teste grava o arquivo SINTÉTICO na pasta do app e fecha.
        let harness = XCUIApplication()
        harness.launchArguments = ["-UITestHarness"]
        harness.launch()
        XCTAssertTrue(harness.staticTexts["Teste de fatura"].waitForExistence(timeout: 20))
        harness.terminate()

        app = XCUIApplication()
        app.launchArguments = ["-security.requireAuth", "NO", "-UITestLegacyImporter"]
        addUIInterruptionMonitor(withDescription: "alertas do sistema") { alert in
            for label in ["Don’t Allow", "Don't Allow", "Não Permitir", "Allow", "Permitir", "OK"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }
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

    private func openAgentMenu() {
        let agentButton = app.buttons["Abrir o agente"]
        XCTAssertTrue(agentButton.waitForExistence(timeout: 30), "botão do agente")
        snap("início")
        agentButton.tap()
        let menu = app.buttons["Enviar prints"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10), "botão da foto no agente")
        menu.tap()
        sleep(1)
        snap("menu da foto")
    }

    private func pickTestFile() {
        sleep(3)
        snap("seletor aberto")
        let name = NSPredicate(format: "label CONTAINS 'Teste_2026-11-08'")
        var target = app.descendants(matching: .any).matching(name).firstMatch
        if !target.waitForExistence(timeout: 5) {
            let tab = app.tabBars.buttons.matching(NSPredicate(format: "label IN %@", ["Browse", "Explorar"])).firstMatch
            if tab.exists { tab.tap(); sleep(2) }
            let place = app.cells.matching(NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@", "On My", "No Meu")).firstMatch
            if place.exists && place.isHittable { place.tap(); sleep(2) }
            let folder = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Fluxo'")).firstMatch
            if folder.exists && folder.isHittable { folder.tap(); sleep(2) }
            snap("pasta fluxo")
            target = app.descendants(matching: .any).matching(name).firstMatch
        }
        XCTAssertTrue(target.waitForExistence(timeout: 10), "arquivo não apareceu no seletor")
        target.tap()
        sleep(3)
        snap("depois do toque no arquivo")
    }

    /// Sem cartão conectado no simulador, o agente responde "Nenhum cartão…" —
    /// o que prova que o arquivo chegou e foi lido.
    private var agentReceivedFile: XCUIElement {
        app.staticTexts.matching(NSPredicate(format:
            "label CONTAINS 'Nenhum cartão de crédito conectado' OR label CONTAINS 'Conferir a fatura com o arquivo'")).firstMatch
    }

    func testAgentPicker() {
        openAgentMenu()
        app.buttons["Conferir fatura com arquivo (CSV ou OFX)"].tap()
        let pick = app.buttons["bill.pick"]
        XCTAssertTrue(pick.waitForExistence(timeout: 10))
        snap("folha da fatura")
        pick.tap()
        pickTestFile()
        let ok = agentReceivedFile.waitForExistence(timeout: 15)
        snap("resultado")
        XCTAssertTrue(ok, "o agente não recebeu o arquivo")
    }

    func testAgentPaste() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Teste_2026-11-08", withExtension: "ofx"))
        UIPasteboard.general.setItems([["com.soturnna.fluxo.ofx": try Data(contentsOf: url)]])
        openAgentMenu()
        app.buttons["Conferir fatura com arquivo (CSV ou OFX)"].tap()
        let paste = app.buttons["bill.paste"]
        XCTAssertTrue(paste.waitForExistence(timeout: 10))
        paste.tap()
        let ok = agentReceivedFile.waitForExistence(timeout: 15)
        snap("resultado")
        XCTAssertTrue(ok, "o agente não recebeu o conteúdo colado")
    }

    /// Investigação: o seletor como estava no build 27 (fileImporter nesta tela).
    /// Não reprova a suíte; registra no log se funciona ou não.
    func testZLegacyImporterInvestigation() {
        openAgentMenu()
        app.buttons["Teste: seletor antigo"].tap()
        pickTestFile()
        let ok = agentReceivedFile.waitForExistence(timeout: 10)
        snap("resultado")
        print("INVESTIGACAO seletor antigo (build 27) no app real: \(ok ? "FUNCIONOU" : "NAO FUNCIONOU")")
    }
}
