import XCTest
@testable import Fluxo

/// Conta da fatura atual × próximas, com os números do caso real do cartão
/// (valores fictícios só no nome: "Banco", "x").
@MainActor
final class CardSummaryTests: XCTestCase {
    private func money(_ text: String) -> Decimal { Decimal(string: text)! }

    private func cycle(_ index: Int, _ amount: String) -> FinanceStore.BillCycle {
        let due = Calendar.current.date(byAdding: .month, value: index, to: Date().addingTimeInterval(10 * 86_400))!
        var cycle = FinanceStore.BillCycle(index: index, close: due.addingTimeInterval(-8 * 86_400), due: due,
                                           status: index == 0 ? .open : .upcoming)
        cycle.projected = [FinanceStore.ProjectedInstallment(title: "x", installment: "1/2", amount: -money(amount), date: due)]
        return cycle
    }

    /// App: atual 275,69 em compras; dezembro 557,09 (com lançamento a mais), jan e fev 167,13.
    /// Banco: total 1.192,83; fatura atual 561,46 (arquivo OFX).
    private func summary(bankFile: Decimal?) -> FinanceStore.CardSummary {
        let account = StoredAccount(id: "c", itemId: "i", institution: "Banco", isCreditCard: true,
                                    isSavings: false, balance: money("1192.83"))
        let schedule = FinanceStore.CardSchedule(card: account, closeDay: 1, dueDay: 9, closeDayIsEstimate: false,
                                                 cycles: [cycle(0, "275.69"), cycle(1, "557.09"), cycle(2, "167.13"), cycle(3, "167.13")])
        return FinanceStore.CardSummary(account: account, schedule: schedule, bankOpenTotal: bankFile)
    }

    func testWithoutBankFileUsesTotalMinusListedMonths() {
        let s = summary(bankFile: nil)
        XCTAssertEqual(s.listedFutureBills, money("891.35"))
        XCTAssertEqual(s.openBill, money("301.48"), "sem o arquivo: 1.192,83 − 891,35")
        XCTAssertEqual(s.futureBills, money("891.35"))
        XCTAssertEqual(s.futureNotListed, 0)
    }

    func testBankFileTotalBecomesCurrentBill() {
        let s = summary(bankFile: money("561.46"))
        XCTAssertEqual(s.openBill, money("561.46"), "fatura atual = total do arquivo do banco")
        XCTAssertEqual(s.futureBills, money("631.37"), "próximas = 1.192,83 − 561,46 (como no Nubank)")
        XCTAssertEqual(s.totalUsed, money("1192.83"))
        XCTAssertEqual(s.futureNotListed, money("-259.98"), "dezembro tem 259,98 a mais no app")
        XCTAssertEqual(s.unitemized, money("285.77"), "parte da fatura que não é compra")
    }
}
