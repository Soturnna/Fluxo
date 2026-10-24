import Foundation
import UIKit
import UserNotifications

/// Preferências de notificação, lidas do UserDefaults.
enum NotificationPrefs {
    private static var defaults: UserDefaults { .standard }

    static var enabled: Bool { defaults.bool(forKey: SettingsKey.notifyEnabled) }
    static var budgets: Bool { defaults.bool(forKey: SettingsKey.notifyBudgets) }
    static var planned: Bool { defaults.bool(forKey: SettingsKey.notifyPlanned) }
    static var largeExpense: Bool { defaults.bool(forKey: SettingsKey.notifyLarge) }
    static var weekly: Bool { defaults.bool(forKey: SettingsKey.notifyWeekly) }
    static var connection: Bool { defaults.bool(forKey: SettingsKey.notifyConnection) }
    static var showValues: Bool { defaults.bool(forKey: SettingsKey.notifyShowValues) }

    /// Valor mínimo do "gasto alto", entre R$ 1 e R$ 1 milhão.
    static var largeThreshold: Decimal {
        let value = defaults.double(forKey: SettingsKey.notifyLargeThreshold)
        guard value.isFinite, value >= 1, value <= 1_000_000 else { return 200 }
        return Money.decimal(from: value)
    }
}

/// O que já foi avisado, para nunca repetir o mesmo alerta.
/// Fica no cofre cifrado (gaveta avisos.cofre), como os demais dados.
struct NotificationLedger: Codable {
    /// "2026-10|idDaCategoria" → "near" (90%) ou "over" (estourou).
    var budgetLevels: [String: String] = [:]
    /// Alertas de uma vez por mês: "2026-10|ritmo", "2026-10|limite-near"...
    var monthFlags: Set<String> = []
    /// Gastos altos já avisados: "estabelecimento|valor" → quando avisou.
    var largeExpenses: [String: Date] = [:]
    /// Só gastos a partir desta data entram no alerta (evita avisar o histórico antigo).
    var largeBaseline: Date?
}

/// Decide quais notificações mandar e agenda as que têm data marcada.
///
/// Dois tipos:
/// - **Imediatas** (dependem de dados novos do banco): orçamento em 90%,
///   orçamento estourado, ritmo do mês acima do limite e gasto alto.
///   Avaliadas depois de cada sincronização, no app ou em segundo plano.
/// - **Agendadas** (têm data): gasto previsto no dia, resumo semanal e
///   conexão do Open Finance expirando. Refeitas do zero a cada avaliação,
///   então nunca ficam desatualizadas nem duplicadas.
@MainActor
enum NotificationPlanner {
    private static var running = false
    private static var runAgain = false

    /// Ponto de entrada único. Chamado depois de cada sincronização, quando
    /// seus dados mudam e quando você mexe nas preferências.
    static func evaluate(_ store: FinanceStore) async {
        // Duas avaliações ao mesmo tempo poderiam mandar o mesmo alerta duas vezes.
        if running { runAgain = true; return }
        running = true
        defer { running = false }

        repeat {
            runAgain = false
            await evaluateOnce(store)
        } while runAgain
    }

    static func isAuthorized() async -> Bool {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional || status == .ephemeral
    }

    private static func evaluateOnce(_ store: FinanceStore) async {
        guard NotificationPrefs.enabled, await isAuthorized() else {
            NotificationCleanup.removeAll()
            return
        }
        // Com o iPhone bloqueado, o cofre e as chaves ficam fechados (de propósito).
        guard UIApplication.shared.isProtectedDataAvailable else { return }

        var ledger = Vault.load(NotificationLedger.self, from: .notifications) ?? NotificationLedger()
        prune(&ledger)

        var alerts: [Alert] = []
        if NotificationPrefs.budgets {
            alerts += budgetAlerts(store, &ledger)
            alerts += cashFlowAlerts(store, &ledger)
        }
        if NotificationPrefs.largeExpense { alerts += largeExpenseAlerts(store, &ledger) }
        // Teto por rodada: nunca uma enxurrada de avisos de uma vez.
        alerts.prefix(4).forEach(post)
        try? Vault.save(ledger, in: .notifications)

        await reschedule(store)
    }

    // MARK: Imediatas

    private static func budgetAlerts(_ store: FinanceStore, _ ledger: inout NotificationLedger) -> [Alert] {
        let month = AgentTools.monthString(.now)
        var alerts: [Alert] = []

        for item in store.progress(inMonthOf: .now) where item.level != .ok {
            let key = "\(month)|\(item.category.id)"
            let level = item.level == .over ? "over" : "near"
            let previous = ledger.budgetLevels[key]
            // Só avisa quando o nível SOBE: nada → 90% → estourou.
            guard previous != "over", previous != level else { continue }
            ledger.budgetLevels[key] = level

            let name = item.category.name
            let values = "\(brl(item.spent)) de \(brl(item.budget.limit)) (\(item.percent)%)"
            if item.level == .over {
                alerts.append(Alert(id: "budget-\(key)-over", title: "Orçamento estourado",
                                    body: show("\(name): \(values).", or: "\(name) passou do orçamento do mês."),
                                    tab: .budgets))
            } else {
                alerts.append(Alert(id: "budget-\(key)-near", title: "Orçamento quase no limite",
                                    body: show("\(name): \(values).", or: "\(name) chegou a 90% do orçamento do mês."),
                                    tab: .budgets))
            }
        }

        // Limite geral do mês e o ritmo de gasto.
        guard let limit = store.userData.effectiveMonthlyLimit, limit > 0 else { return alerts }
        let spent = store.totals(inMonthOf: .now).spent
        let ratio = (spent as NSDecimalNumber).doubleValue / (limit as NSDecimalNumber).doubleValue

        if ratio > 1, ledger.monthFlags.insert("\(month)|limite-over").inserted {
            ledger.monthFlags.insert("\(month)|limite-near")
            alerts.append(Alert(id: "limit-\(month)-over", title: "Limite do mês estourado",
                                body: show("Gastos do mês: \(brl(spent)) de \(brl(limit)).",
                                           or: "Os gastos do mês passaram do seu limite."),
                                tab: .budgets))
        } else if ratio >= 0.9, ratio <= 1, ledger.monthFlags.insert("\(month)|limite-near").inserted {
            alerts.append(Alert(id: "limit-\(month)-near", title: "Limite do mês quase no fim",
                                body: show("Gastos do mês: \(brl(spent)) de \(brl(limit)) (\(Int((ratio * 100).rounded()))%).",
                                           or: "Os gastos do mês chegaram a 90% do seu limite."),
                                tab: .budgets))
        } else if ratio < 0.9 {
            // Ritmo: com pelo menos uma semana de dados, projeta o fim do mês.
            let elapsed = store.elapsedDays(inMonthOf: .now)
            let projected = spent / Decimal(max(elapsed, 1)) * Decimal(FinanceStore.daysInMonth(.now))
            if elapsed >= 7, store.daysLeft(inMonthOf: .now) >= 3, projected > limit * Decimal(1.05),
               ledger.monthFlags.insert("\(month)|ritmo").inserted {
                alerts.append(Alert(id: "pace-\(month)", title: "Ritmo acima do limite",
                                    body: show("No ritmo atual, o mês fecha perto de \(brl(projected)); o limite é \(brl(limit)).",
                                               or: "No ritmo atual, você vai passar do limite do mês."),
                                    tab: .budgets))
            }
        }
        return alerts
    }

    /// Saldo previsto negativo nos próximos 30 dias: um aviso por "buraco".
    private static func cashFlowAlerts(_ store: FinanceStore, _ ledger: inout NotificationLedger) -> [Alert] {
        guard let projection = store.projectCashFlow(), let first = projection.firstNegative else { return [] }
        let key = "\(AgentTools.dayString(first))|saldo-negativo"
        guard ledger.monthFlags.insert(key).inserted else { return [] }
        let day = FinanceStore.dayLabel(first)
        return [Alert(
            id: "cashflow-\(AgentTools.dayString(first))",
            title: "Saldo pode ficar negativo",
            body: show("Previsão: \(brl(projection.minBalance)) em \(FinanceStore.dayLabel(projection.minDate)). \(projection.suggestion ?? "")",
                       or: "Pela previsão, o saldo da conta fica negativo a partir de \(day)."),
            tab: .home
        )]
    }

    private static func largeExpenseAlerts(_ store: FinanceStore, _ ledger: inout NotificationLedger) -> [Alert] {
        let calendar = Calendar.current
        if ledger.largeBaseline == nil { ledger.largeBaseline = .now }
        let baseline = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: ledger.largeBaseline ?? .now)) ?? .now
        let recent = calendar.date(byAdding: .day, value: -3, to: .now) ?? .now
        let cutoff = max(baseline, recent)
        let threshold = NotificationPrefs.largeThreshold

        var alerts: [Alert] = []
        let candidates = store.transactions
            .filter { $0.date >= cutoff && store.isExpense($0) && -$0.amount >= threshold }
            .sorted { $0.date < $1.date }

        for item in candidates {
            // Uma compra "pendente" muda de id ao ser confirmada; por isso a
            // identidade do aviso é estabelecimento + valor, não o id.
            let fingerprint = "\(FinanceStore.ruleKey(item.title))|\(item.amount)"
            guard ledger.largeExpenses[fingerprint] == nil else { continue }
            ledger.largeExpenses[fingerprint] = .now

            // Num Pix para uma pessoa, o nome dela não vai para a tela bloqueada.
            let what = PrivacyFilter.looksLikePersonTransfer(item) ? "Pix ou transferência" : item.title
            alerts.append(Alert(
                id: "large-\(item.id)",
                title: "Gasto alto",
                body: show("\(brl(-item.amount)) · \(what)",
                           or: "Um gasto acima do seu valor de alerta foi registrado."),
                tab: .transactions
            ))
        }
        return alerts
    }

    // MARK: Agendadas

    private static let scheduledPrefixes = ["planned-", "weekly", "consent-"]

    private static func reschedule(_ store: FinanceStore) async {
        let center = UNUserNotificationCenter.current()
        // As de conexão só são refeitas quando há dados de uma sincronização desta sessão.
        let prefixes = scheduledPrefixes.filter { $0 != "consent-" || !store.connections.isEmpty }
        let pending = await center.pendingNotificationRequests()
        let stale = pending.map(\.identifier).filter { id in prefixes.contains { id.hasPrefix($0) } }
        center.removePendingNotificationRequests(withIdentifiers: stale)

        if NotificationPrefs.planned { schedulePlanned(store) }
        if NotificationPrefs.weekly { scheduleWeekly(store) }
        if NotificationPrefs.connection, !store.connections.isEmpty { scheduleConsent(store) }
    }

    /// Lembrete às 9h do dia de cada gasto previsto (até 60 dias à frente).
    private static func schedulePlanned(_ store: FinanceStore) {
        let calendar = Calendar.current
        let horizon = calendar.date(byAdding: .day, value: 60, to: .now) ?? .now
        let upcoming = store.userData.plannedExpenses
            .compactMap { item -> (PlannedExpense, Date)? in
                guard let fire = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: item.date),
                      fire > .now, fire <= horizon else { return nil }
                return (item, fire)
            }
            .sorted { $0.1 < $1.1 }
            .prefix(30)   // o iOS guarda até 64 agendadas por app

        for (item, fire) in upcoming {
            schedule(Alert(id: "planned-\(item.id)", title: "Gasto previsto para hoje",
                           body: show("\(item.title) · \(brl(item.amount))",
                                      or: "Você marcou um gasto para hoje: \(item.title)."),
                           tab: .transactions),
                     at: fire)
        }
    }

    /// Resumo na próxima segunda, às 9h, sobre a semana de segunda a domingo.
    private static func scheduleWeekly(_ store: FinanceStore) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        calendar.firstWeekday = 2
        guard let fire = calendar.nextDate(after: .now, matching: DateComponents(hour: 9, minute: 0, weekday: 2),
                                           matchingPolicy: .nextTime),
              let weekEnd = Optional(calendar.startOfDay(for: fire)),
              let weekStart = calendar.date(byAdding: .day, value: -7, to: weekEnd),
              let previousStart = calendar.date(byAdding: .day, value: -7, to: weekStart),
              let lastDay = calendar.date(byAdding: .day, value: -1, to: weekEnd)
        else { return }

        func spent(_ start: Date, _ end: Date) -> Decimal {
            store.transactions
                .filter { $0.date >= start && $0.date < end && store.isExpense($0) }
                .reduce(Decimal(0)) { $0 - $1.amount }
        }
        let week = spent(weekStart, weekEnd)
        let previous = spent(previousStart, weekStart)

        let range = "\(weekStart.formatted(.dateTime.day().locale(.ptBR))) a \(lastDay.formatted(.dateTime.day().month(.twoDigits).locale(.ptBR)))"
        var body = "Semana de \(range): \(brl(week)) em gastos"
        // A semana só está completa se a última avaliação foi no domingo à tarde ou depois.
        let complete = Date.now >= weekEnd.addingTimeInterval(-6 * 3600)
        if complete, previous > 0 {
            let change = Int((((week - previous) as NSDecimalNumber).doubleValue / (previous as NSDecimalNumber).doubleValue * 100).rounded())
            body += change == 0 ? ", igual à semana anterior." : " (\(change > 0 ? "▲" : "▼") \(abs(change))% vs semana anterior)."
        } else if !complete {
            body += " (dados até \(Date.now.formatted(.dateTime.weekday(.abbreviated).locale(.ptBR))))."
        } else {
            body += "."
        }

        schedule(Alert(id: "weekly", title: "Resumo da semana",
                       body: show(body, or: "Seu resumo da semana está pronto. Abra o Fluxo para ver."),
                       tab: .home),
                 at: fire)
    }

    /// Aviso 7 dias e 1 dia antes de a autorização do Open Finance vencer.
    private static func scheduleConsent(_ store: FinanceStore) {
        let calendar = Calendar.current
        for connection in store.connections {
            guard let expires = connection.item?.consentExpiresAt else { continue }
            for days in [7, 1] {
                guard let day = calendar.date(byAdding: .day, value: -days, to: expires),
                      let fire = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day),
                      fire > .now else { continue }
                let when = days == 1 ? "amanhã" : "em \(days) dias"
                schedule(Alert(id: "consent-\(connection.id)-\(days)", title: "Conexão expirando",
                               body: "A autorização do \(connection.institution) no Open Finance vence \(when). Renove no Meu Pluggy para continuar recebendo as transações.",
                               tab: .settings),
                         at: fire)
            }
        }
    }

    // MARK: Envio

    struct Alert {
        let id: String
        let title: String
        let body: String
        let tab: NotificationRoute
    }

    static func post(_ alert: Alert) {
        add(alert, trigger: nil)   // sem gatilho = entrega imediata
    }

    private static func schedule(_ alert: Alert, at date: Date) {
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        add(alert, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
    }

    private static func add(_ alert: Alert, trigger: UNNotificationTrigger?) {
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        content.sound = .default
        content.threadIdentifier = "fluxo-\(alert.tab.rawValue)"
        content.userInfo = ["tab": alert.tab.rawValue]
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: alert.id, content: content, trigger: trigger)
        )
    }

    // MARK: Apoio

    /// Texto com valores ou a versão discreta, conforme a preferência.
    private static func show(_ detailed: String, or discreet: String) -> String {
        NotificationPrefs.showValues ? detailed : discreet
    }

    private static func brl(_ value: Decimal) -> String {
        AgentTools.brl(value)
    }

    /// Guarda só o mês atual e o anterior, e gastos altos dos últimos 10 dias.
    private static func prune(_ ledger: inout NotificationLedger) {
        let calendar = Calendar.current
        // Chaves começam por "AAAA-MM": comparar o texto já ordena por data.
        // Ficam o mês anterior em diante (inclusive avisos de dias do mês que vem).
        let oldest = AgentTools.monthString(calendar.date(byAdding: .month, value: -1, to: .now) ?? .now)
        ledger.budgetLevels = ledger.budgetLevels.filter { String($0.key.prefix(7)) >= oldest }
        ledger.monthFlags = ledger.monthFlags.filter { String($0.prefix(7)) >= oldest }
        let tenDaysAgo = calendar.date(byAdding: .day, value: -10, to: .now) ?? .now
        ledger.largeExpenses = ledger.largeExpenses.filter { $0.value >= tenDaysAgo }
    }
}

/// Para onde o app vai quando você toca numa notificação.
enum NotificationRoute: String {
    case home, transactions, budgets, settings
}

/// Limpeza total (desligar notificações ou apagar todos os dados).
enum NotificationCleanup {
    static func removeAll() {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }
}
