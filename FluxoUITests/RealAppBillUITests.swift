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
        XCTAssertTrue(target.waitForExistence(timeout: 20), "arquivo não apareceu no seletor")
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

    /// Os passos exatos do Marcos: app Arquivos › segurar o arquivo › Copiar ›
    /// Fluxo › agente › Conferir fatura com arquivo › Colar.
    func testAgentPasteCopiedInFilesApp() {
        let files = XCUIApplication(bundleIdentifier: "com.apple.DocumentsApp")
        files.launch()
        sleep(3)
        let browse = files.tabBars.buttons.matching(NSPredicate(format: "label IN %@", ["Browse", "Explorar"])).firstMatch
        if browse.waitForExistence(timeout: 10) { browse.tap(); sleep(1); browse.tap(); sleep(2) }
        let place = files.cells.matching(NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@", "On My", "No Meu")).firstMatch
        if place.waitForExistence(timeout: 5) && place.isHittable { place.tap(); sleep(2) }
        let folder = files.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Fluxo'")).firstMatch
        if folder.waitForExistence(timeout: 5) && folder.isHittable { folder.tap(); sleep(2) }
        let shotFiles = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shotFiles.name = "app Arquivos"; shotFiles.lifetime = .keepAlways; add(shotFiles)
        let treeFiles = XCTAttachment(string: files.debugDescription)
        treeFiles.name = "app Arquivos (árvore)"; treeFiles.lifetime = .keepAlways; add(treeFiles)

        let file = files.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Teste_2026-11-08'")).firstMatch
        XCTAssertTrue(file.waitForExistence(timeout: 10), "arquivo não apareceu no app Arquivos")
        file.press(forDuration: 1.5)
        sleep(1)
        let copy = files.buttons.matching(NSPredicate(format: "label IN %@", ["Copy", "Copiar"])).firstMatch
        let shotMenu = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shotMenu.name = "menu do arquivo"; shotMenu.lifetime = .keepAlways; add(shotMenu)
        XCTAssertTrue(copy.waitForExistence(timeout: 5), "opção Copiar não apareceu")
        copy.tap()
        sleep(1)
        print("INVESTIGACAO tipos na area de transferencia: \(UIPasteboard.general.types)")

        app.activate()
        openAgentMenu()
        app.buttons["Conferir fatura com arquivo (CSV ou OFX)"].tap()
        let paste = app.buttons["bill.paste"]
        XCTAssertTrue(paste.waitForExistence(timeout: 10))
        paste.tap()
        let ok = agentReceivedFile.waitForExistence(timeout: 15)
        snap("resultado")
        XCTAssertTrue(ok, "o agente não recebeu o arquivo copiado no app Arquivos")
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
