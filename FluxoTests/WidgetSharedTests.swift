import XCTest
@testable import Fluxo

/// Nome do App Group como o iloader cria (isideload: "group.<id do app instalado>").
final class WidgetSharedTests: XCTestCase {
    func testInstalledByILoader() {
        // O iloader troca com.soturnna.fluxo → com.soturnna.fluxo.<EQUIPE> (e o widget junto).
        let app = WidgetShared.mainBundleID(from: "com.soturnna.fluxo.ABCDE12345", isExtension: false)
        let widget = WidgetShared.mainBundleID(from: "com.soturnna.fluxo.ABCDE12345.widget", isExtension: true)
        XCTAssertEqual(app, widget, "app e widget chegam ao mesmo id")
        XCTAssertEqual(WidgetShared.groupCandidates(mainBundleID: app).first, "group.com.soturnna.fluxo.ABCDE12345")
    }

    func testOriginalBundle() {
        XCTAssertEqual(WidgetShared.groupCandidates(mainBundleID: "com.soturnna.fluxo"), ["group.com.soturnna.fluxo"])
    }

    func testSnapshotRoundTrip() throws {
        let snapshot = WidgetShared.Snapshot(updatedAt: Date(timeIntervalSince1970: 1_800_000_000), note: "Teste")
        let data = try JSONEncoder().encode(snapshot)
        XCTAssertEqual(try JSONDecoder().decode(WidgetShared.Snapshot.self, from: data), snapshot)
    }
}
