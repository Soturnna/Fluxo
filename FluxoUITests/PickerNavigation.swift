import XCTest

/// Navega no seletor do iOS até o arquivo de teste e toca nele.
/// O seletor lembra a última pasta: às vezes abre em "Recentes", às vezes já na
/// pasta do app. Por isso espera bastante antes de navegar, e só toca em CÉLULAS
/// (tocar no título "Fluxo" abre o menu da pasta e esconde o arquivo).
enum PickerNavigation {
    static let fileName = "Teste_2026-11-08"

    static func fileElement(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", fileName)).firstMatch
    }

    @discardableResult
    static func tapTestFile(in app: XCUIApplication, snap: (String) -> Void) -> Bool {
        var file = fileElement(in: app)
        if !file.waitForExistence(timeout: 15) {
            snap("seletor sem o arquivo")
            let browse = app.tabBars.buttons.matching(NSPredicate(format: "label IN %@", ["Browse", "Explorar"])).firstMatch
            if browse.exists { browse.tap(); sleep(2) }
            let place = app.cells.matching(NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@", "On My", "No Meu")).firstMatch
            if place.waitForExistence(timeout: 5) && place.isHittable { place.tap(); sleep(2) }
            let folder = app.cells.matching(NSPredicate(format: "label BEGINSWITH 'Fluxo'")).firstMatch
            if folder.waitForExistence(timeout: 5) && folder.isHittable { folder.tap(); sleep(2) }
            snap("pasta fluxo")
            file = fileElement(in: app)
        }
        guard file.waitForExistence(timeout: 15) else { return false }
        file.tap()
        sleep(3)
        snap("depois do toque no arquivo")
        return true
    }
}
