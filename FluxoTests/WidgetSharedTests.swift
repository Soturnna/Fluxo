import XCTest
@testable import Fluxo

/// Widgets: grupo do iloader, privacidade dos dados, formato do gráfico e toques.
@MainActor
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

    /// Com "Mostrar valores" desligado, nenhum valor em reais nem nome é montado.
    func testNoValuesWhenHidden() {
        let store = FinanceStore()
        let hidden = WidgetBridge.makeData(store, showValues: false)
        XCTAssertNil(hidden.1, "sem valores com a opção desligada")
        XCTAssertFalse(hidden.0.showValues)
        let shown = WidgetBridge.makeData(store, showValues: true)
        XCTAssertNotNil(shown.1)
        XCTAssertTrue(shown.0.showValues)
    }

    /// A parte que fica legível com o iPhone travado só tem estes campos (nada em reais, nenhum nome).
    func testPublicPartHasNoMoney() throws {
        let data = try JSONEncoder().encode(WidgetSamples.data(showValues: true).info)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["updatedAt", "hasBank", "hasCard", "showValues", "billDue", "cardOverLimit",
                                          "cardUsedFraction", "monthName", "budgetFraction", "daysLeftInMonth", "paceAlert",
                                          "tightestDay", "goesNegative", "sparkline", "pendingCount", "nextEvents"])
        let events = try XCTUnwrap(object["nextEvents"] as? [[String: Any]])
        XCTAssertEqual(Set(events.first?.keys.map { $0 } ?? []), ["date", "kind", "isIncome"], "evento sem nome nem valor")
    }

    func testRoundTrip() throws {
        let sample = WidgetSamples.data(showValues: true)
        let info = try JSONDecoder().decode(WidgetShared.PublicData.self, from: JSONEncoder().encode(sample.info))
        XCTAssertEqual(info, sample.info)
        let values = try JSONDecoder().decode(WidgetShared.Values.self, from: JSONEncoder().encode(sample.values!))
        XCTAssertEqual(values, sample.values)
    }

    func testSparklineShapeOnly() {
        let shape = WidgetBridge.normalized([Decimal(10), Decimal(20), Decimal(30)])
        XCTAssertEqual(shape, [0, 0.5, 1])
        XCTAssertEqual(WidgetBridge.normalized([Decimal(5), Decimal(5)]), [0.5, 0.5])
        XCTAssertLessThanOrEqual(WidgetBridge.normalized((0..<61).map { Decimal($0) }).count, 31)
    }

    func testDeepLinks() {
        XCTAssertEqual(DeepLink(url: URL(string: "fluxo://cartao")!), .card)
        XCTAssertEqual(DeepLink(url: URL(string: "fluxo://registrar")!), .register)
        XCTAssertEqual(DeepLink(url: URL(string: "fluxo://fluxo-de-caixa")!), .cashFlow)
        XCTAssertNil(DeepLink(url: URL(string: "fluxo://cartao/apagar")!))
        XCTAssertNil(DeepLink(url: URL(string: "fluxo://cartao?x=1")!))
        XCTAssertNil(DeepLink(url: URL(string: "https://cartao")!))
        XCTAssertNil(DeepLink(url: URL(string: "fluxo://ajustes")!))
    }

    func testDueLine() {
        let now = Date()
        let in15 = Calendar.current.date(byAdding: .day, value: 15, to: now)!
        XCTAssertEqual(WFormat.dueLine(in15, from: now), "vence em 15 dias")
        XCTAssertEqual(WFormat.dueLine(now, from: now), "vence hoje")
        XCTAssertEqual(WFormat.brl(nil), "R$ ••••")
    }
}
