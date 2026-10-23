import Foundation

/// Resposta do agente já organizada em blocos visuais.
///
/// O Gemini escreve texto simples com algumas marcações combinadas:
///   - tópicos ("- ") e listas numeradas ("1. ");
///   - dica numa linha começando com "> ";
///   - [[grafico:tipo:AAAA-MM]] no ponto onde um gráfico deve aparecer;
///   - [[acao:pedido]] para cada sugestão de próximo passo.
///
/// O ponto central de segurança e de confiança: o marcador de gráfico só diz
/// QUAL gráfico mostrar. Os números são calculados aqui, a partir do cofre
/// local. A IA não consegue inventar nem alterar um valor desenhado.
struct AgentAnswer {
    enum Block: Identifiable {
        case heading(id: UUID, text: String)
        case paragraph(id: UUID, text: String)
        case bullets(id: UUID, items: [String])
        case numbered(id: UUID, items: [(number: Int, text: String)])
        case tip(id: UUID, text: String)
        case chart(AnswerChart)

        var id: UUID {
            switch self {
            case .heading(let id, _), .paragraph(let id, _), .bullets(let id, _),
                 .numbered(let id, _), .tip(let id, _):
                return id
            case .chart(let chart):
                return chart.id
            }
        }
    }

    /// Sugestão tocável. `display` tem os nomes reais (só na tela);
    /// `prompt` mantém os pseudônimos, e é ele que volta para a IA.
    struct Suggestion: Identifiable {
        let id = UUID()
        let display: String
        let prompt: String
    }

    var blocks: [Block]
    var suggestions: [Suggestion]
}

/// Dados de um gráfico, já calculados no iPhone.
struct AnswerChart: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let content: Content

    enum Content {
        case kpis([Kpi])
        case donut(total: Double, slices: [Slice])
        case ranking([RankItem])
        case trend(current: [TrendPoint], previous: [TrendPoint], currentLabel: String, previousLabel: String, lastDay: Int)
        case months([MonthBar])
        case budgets([BudgetLine])
    }

    enum Tone { case neutral, good, bad }

    struct Kpi: Identifiable {
        let id = UUID()
        let label: String
        let value: Double
        let detail: String?
        let tone: Tone
    }

    struct Slice: Identifiable {
        let id = UUID()
        let name: String
        let value: Double
        let share: Double          // 0 a 1
        let colorIndex: Int?       // nil = "Outros", em cinza
    }

    struct RankItem: Identifiable {
        let id = UUID()
        let label: String
        let detail: String
        let value: Double
    }

    struct TrendPoint: Identifiable {
        let id = UUID()
        let day: Int
        let value: Double
    }

    struct MonthBar: Identifiable {
        let id = UUID()
        let label: String
        let kind: String           // "Gastos" ou "Entradas"
        let value: Double
    }

    struct BudgetLine: Identifiable {
        let id = UUID()
        let name: String
        let icon: String
        let spent: Double
        let limit: Double
        let fraction: Double
        let percent: Int
        let level: BudgetLevel
    }
}

// MARK: - Leitura do texto

@MainActor
enum AnswerParser {
    static let maxCharts = 2
    static let maxSuggestions = 3
    static let fallback = "Não consegui responder a isso. Pode reformular?"

    // [[nome]] ou [[nome:argumento]]
    private static let marker = try! NSRegularExpression(pattern: #"\[\[\s*([^\]:\s]+)\s*(?::([^\]]*))?\]\]"#)
    private static let headingPattern = try! NSRegularExpression(pattern: #"^#{1,4}\s+(.+)$"#)
    private static let bulletPattern = try! NSRegularExpression(pattern: #"^[-*•]\s+(.+)$"#)
    private static let numberedPattern = try! NSRegularExpression(pattern: #"^(\d{1,2})[.)]\s+(.+)$"#)
    private static let tipPattern = try! NSRegularExpression(pattern: #"^>\s?(.+)$"#)

    static func parse(_ raw: String, store: FinanceStore, privacy: PrivacyFilter) -> AgentAnswer {
        var blocks: [AgentAnswer.Block] = []
        var suggestions: [AgentAnswer.Suggestion] = []
        var chartKeys = Set<String>()

        var paragraph: [String] = []
        var bullets: [String] = []
        var numbered: [(Int, String)] = []

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(id: UUID(), text: privacy.reveal(paragraph.joined(separator: "\n"))))
            paragraph = []
        }
        func flushLists() {
            if !bullets.isEmpty { blocks.append(.bullets(id: UUID(), items: bullets.map(privacy.reveal))) }
            if !numbered.isEmpty {
                blocks.append(.numbered(id: UUID(), items: numbered.map { (number: $0.0, text: privacy.reveal($0.1)) }))
            }
            bullets = []
            numbered = []
        }

        for rawLine in raw.components(separatedBy: .newlines) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)

            // 1. Marcadores: viram gráficos ou sugestões e saem do texto.
            var charts: [AnswerChart] = []
            let range = NSRange(line.startIndex..., in: line)
            let matches = marker.matches(in: line, range: range)
            for match in matches {
                let name = capture(match, 1, in: line).lowercased()
                    .folding(options: .diacriticInsensitive, locale: nil)
                let argument = capture(match, 2, in: line)
                switch name {
                case "grafico":
                    guard chartKeys.count < maxCharts,
                          let built = AnswerChartBuilder.build(argument, store: store),
                          !chartKeys.contains(built.key)
                    else { continue }
                    chartKeys.insert(built.key)
                    charts.append(built.chart)
                case "acao":
                    guard suggestions.count < maxSuggestions,
                          let prompt = sanitizedSuggestion(argument),
                          !suggestions.contains(where: { $0.prompt == prompt })
                    else { continue }
                    suggestions.append(.init(display: privacy.reveal(prompt), prompt: prompt))
                default:
                    continue   // marcador desconhecido: descartado
                }
            }
            if !matches.isEmpty {
                line = marker.stringByReplacingMatches(in: line, range: range, withTemplate: "")
                    .trimmingCharacters(in: .whitespaces)
            }

            // 2. Estrutura do texto.
            if line.isEmpty || line == "---" || line == "***" {
                flushParagraph()          // linha em branco não encerra uma lista
            } else if let text = firstCapture(headingPattern, line) {
                flushParagraph(); flushLists()
                blocks.append(.heading(id: UUID(), text: privacy.reveal(text.replacingOccurrences(of: "**", with: ""))))
            } else if let text = firstCapture(bulletPattern, line) {
                flushParagraph()
                if !numbered.isEmpty { flushLists() }
                bullets.append(text)
            } else if let match = numberedPattern.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
                flushParagraph()
                if !bullets.isEmpty { flushLists() }
                numbered.append((Int(capture(match, 1, in: line)) ?? numbered.count + 1, capture(match, 2, in: line)))
            } else if let text = firstCapture(tipPattern, line) {
                flushParagraph(); flushLists()
                blocks.append(.tip(id: UUID(), text: privacy.reveal(text)))
            } else {
                flushLists()
                paragraph.append(line)
            }

            // 3. Gráficos entram exatamente onde o marcador estava.
            if !charts.isEmpty {
                flushParagraph(); flushLists()
                blocks.append(contentsOf: charts.map { .chart($0) })
            }
        }
        flushParagraph()
        flushLists()

        if blocks.isEmpty {
            blocks = [.paragraph(id: UUID(), text: fallback)]
        }
        return AgentAnswer(blocks: blocks, suggestions: suggestions)
    }

    /// Sugestões são só texto que você pode enviar de volta. Ainda assim,
    /// passam por limpeza: sem caracteres de controle nem marcações, até 80 caracteres.
    private static func sanitizedSuggestion(_ raw: String) -> String? {
        let cleaned = raw
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")
            .unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        let text = String(String.UnicodeScalarView(cleaned))
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard text.count >= 3 else { return nil }
        return String(text.prefix(80))
    }

    private static func capture(_ match: NSTextCheckingResult, _ index: Int, in text: String) -> String {
        guard let range = Range(match.range(at: index), in: text) else { return "" }
        return String(text[range]).trimmingCharacters(in: .whitespaces)
    }

    private static func firstCapture(_ regex: NSRegularExpression, _ text: String) -> String? {
        guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        let value = capture(match, 1, in: text)
        return value.isEmpty ? nil : value
    }
}

// MARK: - Cálculo dos gráficos

@MainActor
enum AnswerChartBuilder {
    /// Interpreta "categorias:2026-10" e calcula o gráfico com os dados locais.
    /// Tipo desconhecido ou sem dados: nada é desenhado.
    static func build(_ spec: String, store: FinanceStore) -> (key: String, chart: AnswerChart)? {
        let parts = spec.split(separator: ":", maxSplits: 1)
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased().folding(options: .diacriticInsensitive, locale: nil) }
        guard let kind = parts.first, !kind.isEmpty else { return nil }
        let month = resolveMonth(parts.count > 1 ? parts[1] : nil)
        let key = "\(kind)|\(AgentTools.monthString(month))"

        let chart: AnswerChart?
        switch kind {
        case "indicadores", "resumo": chart = kpis(month, store)
        case "categorias": chart = donut(month, store)
        case "maiores": chart = ranking(month, store)
        case "evolucao": chart = trend(month, store)
        case "meses": chart = months(month, store)
        case "orcamentos": chart = budgets(month, store)
        default: chart = nil
        }
        return chart.map { (key, $0) }
    }

    /// Mês pedido, limitado aos últimos 24 meses. Fora disso, o mês atual.
    private static func resolveMonth(_ text: String?) -> Date {
        let calendar = Calendar.current
        let current = calendar.dateInterval(of: .month, for: .now)?.start ?? .now
        guard let text, let parsed = AgentTools.parseMonth(text),
              let oldest = calendar.date(byAdding: .month, value: -24, to: current),
              parsed <= current, parsed >= oldest
        else { return current }
        return parsed
    }

    // MARK: Tipos

    private static func kpis(_ month: Date, _ store: FinanceStore) -> AnswerChart? {
        let totals = store.totals(inMonthOf: month)
        guard totals.spent > 0 || totals.income > 0 else { return nil }
        let previous = shift(month, by: -1)
        let isCurrent = FinanceStore.isCurrentMonth(month)
        let elapsed = store.elapsedDays(inMonthOf: month)

        // Mês em andamento é comparado com o mesmo trecho do mês anterior,
        // para não comparar 23 dias com 30.
        let previousSpent = store.spent(inMonthOf: previous, upToDay: isCurrent ? elapsed : nil)
        var spentDetail: String?
        var spentTone = AnswerChart.Tone.neutral
        if previousSpent > 0 {
            let change = (double(totals.spent) - double(previousSpent)) / double(previousSpent) * 100
            let rounded = Int(change.rounded())
            let arrow = rounded > 0 ? "▲" : (rounded < 0 ? "▼" : "=")
            let period = isCurrent ? "\(shortMonth(previous)) até dia \(elapsed)" : shortMonth(previous)
            spentDetail = "\(arrow) \(abs(rounded))% vs \(period)"
            spentTone = rounded > 0 ? .bad : (rounded < 0 ? .good : .neutral)
        }

        let result = totals.income - totals.spent
        var tiles: [AnswerChart.Kpi] = [
            .init(label: "Gastos", value: double(totals.spent), detail: spentDetail, tone: spentTone),
            .init(label: "Entradas", value: double(totals.income), detail: nil, tone: .neutral),
            .init(label: "Resultado", value: double(result),
                  detail: result >= 0 ? "Sobrou no mês" : "Saiu mais do que entrou",
                  tone: result >= 0 ? .good : .bad)
        ]
        let pending = store.pendingPlannedTotal(inMonthOf: month)
        if pending > 0 {
            tiles.append(.init(label: "Previstos", value: double(pending), detail: "Ainda vão sair", tone: .neutral))
        } else {
            tiles.append(.init(label: "Média por dia", value: double(totals.spent) / Double(max(elapsed, 1)),
                               detail: "\(elapsed) \(elapsed == 1 ? "dia" : "dias")", tone: .neutral))
        }
        return AnswerChart(title: "Visão do mês", subtitle: monthLabel(month), content: .kpis(tiles))
    }

    private static func donut(_ month: Date, _ store: FinanceStore) -> AnswerChart? {
        let spending = store.spendingByCategory(inMonthOf: month)
            .filter { $0.value > 0 }
            .sorted { $0.value > $1.value }
        guard !spending.isEmpty else { return nil }
        let total = spending.reduce(0.0) { $0 + double($1.value) }

        // Cinco cores fixas (validadas para daltonismo); o resto vira "Outros".
        var slices: [AnswerChart.Slice] = spending.prefix(5).enumerated().map { index, entry in
            let value = double(entry.value)
            return .init(name: store.category(withId: entry.key)?.name ?? "Outros",
                         value: value, share: value / total, colorIndex: index)
        }
        let rest = spending.dropFirst(5).reduce(0.0) { $0 + double($1.value) }
        if rest > 0 {
            slices.append(.init(name: "Outros", value: rest, share: rest / total, colorIndex: nil))
        }
        return AnswerChart(title: "Gastos por categoria", subtitle: monthLabel(month),
                           content: .donut(total: total, slices: slices))
    }

    private static func ranking(_ month: Date, _ store: FinanceStore) -> AnswerChart? {
        let items = store.transactions(inMonthOf: month)
            .filter { store.isExpense($0) }
            .sorted { $0.amount < $1.amount }
            .prefix(5)
            .map { item in
                AnswerChart.RankItem(
                    label: item.title,
                    detail: "\(item.date.formatted(.dateTime.day().month(.abbreviated).locale(.ptBR))) · \(store.category(for: item).name)",
                    value: double(-item.amount)
                )
            }
        guard !items.isEmpty else { return nil }
        return AnswerChart(title: "Maiores gastos", subtitle: monthLabel(month), content: .ranking(Array(items)))
    }

    private static func trend(_ month: Date, _ store: FinanceStore) -> AnswerChart? {
        let previous = shift(month, by: -1)
        let current = cumulative(month, store, upTo: FinanceStore.isCurrentMonth(month) ? store.elapsedDays(inMonthOf: month) : nil)
        let earlier = cumulative(previous, store, upTo: nil)
        guard (current.last?.value ?? 0) > 0 || (earlier.last?.value ?? 0) > 0 else { return nil }
        return AnswerChart(
            title: "Gasto acumulado no mês",
            subtitle: "\(firstUpper(monthName(month))) comparado a \(monthName(previous))",
            content: .trend(current: current, previous: earlier,
                            currentLabel: firstUpper(monthName(month)), previousLabel: firstUpper(monthName(previous)),
                            lastDay: max(FinanceStore.daysInMonth(month), FinanceStore.daysInMonth(previous)))
        )
    }

    private static func months(_ month: Date, _ store: FinanceStore) -> AnswerChart? {
        var bars: [AnswerChart.MonthBar] = []
        var hasData = false
        for offset in (0..<6).reversed() {
            let target = shift(month, by: -offset)
            let totals = store.totals(inMonthOf: target)
            if totals.spent > 0 || totals.income > 0 { hasData = true }
            let label = shortMonth(target)
            bars.append(.init(label: label, kind: "Entradas", value: double(totals.income)))
            bars.append(.init(label: label, kind: "Gastos", value: double(totals.spent)))
        }
        guard hasData else { return nil }
        return AnswerChart(title: "Últimos 6 meses", subtitle: "Entradas e gastos por mês", content: .months(bars))
    }

    private static func budgets(_ month: Date, _ store: FinanceStore) -> AnswerChart? {
        let lines = store.progress(inMonthOf: month).prefix(6).map { item in
            AnswerChart.BudgetLine(
                name: item.category.name, icon: item.category.icon,
                spent: double(item.spent), limit: double(item.budget.limit),
                fraction: item.fraction, percent: item.percent, level: item.level
            )
        }
        guard !lines.isEmpty else { return nil }
        return AnswerChart(title: "Orçamentos", subtitle: monthLabel(month), content: .budgets(Array(lines)))
    }

    // MARK: Apoio

    private static func cumulative(_ month: Date, _ store: FinanceStore, upTo limit: Int?) -> [AnswerChart.TrendPoint] {
        let daily = store.dailySpending(inMonthOf: month)
        let last = min(limit ?? FinanceStore.daysInMonth(month), FinanceStore.daysInMonth(month))
        guard last >= 1 else { return [] }
        var sum = 0.0
        return (1...last).map { day in
            sum += double(daily[day] ?? 0)
            return AnswerChart.TrendPoint(day: day, value: sum)
        }
    }

    private static func shift(_ month: Date, by value: Int) -> Date {
        Calendar.current.date(byAdding: .month, value: value, to: month) ?? month
    }

    private static func double(_ value: Decimal) -> Double {
        (value as NSDecimalNumber).doubleValue
    }

    private static func monthLabel(_ month: Date) -> String {
        firstUpper(month.formatted(.dateTime.month(.wide).year().locale(.ptBR)))
    }

    private static func firstUpper(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }

    private static func monthName(_ month: Date) -> String {
        month.formatted(.dateTime.month(.wide).locale(.ptBR))
    }

    private static func shortMonth(_ month: Date) -> String {
        month.formatted(.dateTime.month(.abbreviated).locale(.ptBR)).replacingOccurrences(of: ".", with: "")
    }
}
