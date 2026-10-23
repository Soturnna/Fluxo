import SwiftUI
import Charts

/// Cores dos gráficos. As cinco categóricas foram validadas para daltonismo
/// (separação entre vizinhas ΔE ≥ 9) e aparecem sempre na mesma ordem.
/// Como três delas têm pouco contraste com o fundo, todo gráfico traz o nome
/// e o valor escritos ao lado (a cor nunca é a única pista).
enum ChartPalette {
    static let categorical: [Color] = [
        Color(hex: 0x2A78D6),   // azul
        Color(hex: 0xEB6834),   // laranja
        Color(hex: 0x1BAF7A),   // verde-água
        Color(hex: 0xEDA100),   // amarelo
        Color(hex: 0xE87BA4)    // rosa
    ]
    static let other = Color(hex: 0xA3A89F)       // "Outros" e mês anterior
    static let income = Color(hex: 0x2A78D6)
    static let spending = Color(hex: 0xEB6834)
    static let single = Theme.link                // série única

    static func color(for index: Int?) -> Color {
        guard let index, categorical.indices.contains(index) else { return other }
        return categorical[index]
    }
}

enum ChartFormat {
    static func brl(_ value: Double) -> String {
        value.formatted(.currency(code: "BRL").locale(.ptBR))
    }

    /// Eixos: 0, 500, 1,2 mil...
    static func compact(_ value: Double) -> String {
        if abs(value) >= 1000 {
            return (value / 1000).formatted(.number.precision(.fractionLength(0...1)).locale(.ptBR)) + " mil"
        }
        return value.formatted(.number.precision(.fractionLength(0)).locale(.ptBR))
    }

    static func percent(_ share: Double) -> String {
        share < 0.01 && share > 0 ? "<1%" : "\(Int((share * 100).rounded()))%"
    }
}

// MARK: - Cartão da resposta

struct AgentAnswerView: View {
    let answer: AgentAnswer
    var suggestionsEnabled = true
    let onSuggestion: (AgentAnswer.Suggestion) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(answer.blocks) { block in
                blockView(block)
            }

            if !answer.suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Próximos passos")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.inkSecondary)
                        .textCase(.uppercase)
                    ForEach(answer.suggestions) { suggestion in
                        SuggestionChip(text: suggestion.display) { onSuggestion(suggestion) }
                            .disabled(!suggestionsEnabled)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: Self.shape)
        .overlay(Self.shape.strokeBorder(Theme.line, lineWidth: Theme.hairline))
    }

    private static let shape = UnevenRoundedRectangle(
        topLeadingRadius: 6, bottomLeadingRadius: 22, bottomTrailingRadius: 22, topTrailingRadius: 22, style: .continuous
    )

    @ViewBuilder
    private func blockView(_ block: AgentAnswer.Block) -> some View {
        switch block {
        case .heading(_, let text):
            Text(Self.markdown(text))
                .font(.headline)
                .foregroundStyle(Theme.ink)
                .padding(.top, 2)

        case .paragraph(_, let text):
            Text(Self.markdown(text))
                .font(.body)
                .foregroundStyle(Theme.ink)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

        case .bullets(_, let items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Circle()
                            .fill(Theme.forest)
                            .frame(width: 6, height: 6)
                            .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 2 }
                        Text(Self.markdown(item))
                            .font(.callout)
                            .foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

        case .numbered(_, let items):
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(item.number)")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(Theme.ink)
                            .frame(width: 22, height: 22)
                            .background(Theme.lime.opacity(0.6), in: Circle())
                            .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 5 }
                        Text(Self.markdown(item.text))
                            .font(.callout)
                            .foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

        case .tip(_, let text):
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lightbulb.fill")
                    .font(.footnote)
                    .foregroundStyle(Theme.ink)
                    .padding(.top, 2)
                    .accessibilityLabel("Dica")
                Text(Self.markdown(text))
                    .font(.callout)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.lime.opacity(0.28), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

        case .chart(let chart):
            AnswerChartView(chart: chart)
        }
    }

    static func markdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

private struct SuggestionChip: View {
    let text: String
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text(text)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.inkSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(Theme.lime.opacity(0.22), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.lime.opacity(0.9), lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Envia este pedido ao agente")
    }
}

// MARK: - Gráficos

struct AnswerChartView: View {
    let chart: AnswerChart

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(chart.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text(chart.subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.ground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private var content: some View {
        switch chart.content {
        case .kpis(let tiles): KpiGrid(tiles: tiles)
        case .donut(let total, let slices): DonutChart(total: total, slices: slices)
        case .ranking(let items): RankingChart(items: items)
        case .trend(let current, let previous, let currentLabel, let previousLabel, let lastDay):
            TrendChart(current: current, previous: previous, currentLabel: currentLabel,
                       previousLabel: previousLabel, lastDay: lastDay)
        case .months(let bars): MonthsChart(bars: bars)
        case .budgets(let lines): BudgetLines(lines: lines)
        }
    }
}

/// Indicadores: número em destaque, sem gráfico (é o formato certo para um valor só).
private struct KpiGrid: View {
    let tiles: [AnswerChart.Kpi]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(tiles) { tile in
                VStack(alignment: .leading, spacing: 4) {
                    Text(tile.label)
                        .font(.caption)
                        .foregroundStyle(Theme.inkSecondary)
                    Text(ChartFormat.brl(tile.value))
                        .font(.callout.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if let detail = tile.detail {
                        Text(detail)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(color(tile.tone))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private func color(_ tone: AnswerChart.Tone) -> Color {
        switch tone {
        case .neutral: return Theme.inkSecondary
        case .good: return Theme.positive
        case .bad: return Theme.danger
        }
    }
}

/// Rosca: parte de um todo, com até 5 categorias + "Outros".
private struct DonutChart: View {
    let total: Double
    let slices: [AnswerChart.Slice]

    var body: some View {
        VStack(spacing: 14) {
            Chart(slices) { slice in
                SectorMark(
                    angle: .value("Valor", slice.value),
                    innerRadius: .ratio(0.64),
                    angularInset: 1.5
                )
                .cornerRadius(3)
                .foregroundStyle(ChartPalette.color(for: slice.colorIndex))
            }
            .chartLegend(.hidden)
            .frame(width: 150, height: 150)
            .overlay {
                VStack(spacing: 1) {
                    Text("Total")
                        .font(.caption2)
                        .foregroundStyle(Theme.inkSecondary)
                    Text(ChartFormat.brl(total))
                        .font(.footnote.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(maxWidth: 90)
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)

            // Legenda com nome, fatia e valor: a cor nunca é a única pista.
            VStack(spacing: 8) {
                ForEach(slices) { slice in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 2.5)
                            .fill(ChartPalette.color(for: slice.colorIndex))
                            .frame(width: 10, height: 10)
                        Text(slice.name)
                            .font(.footnote)
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        Text(ChartFormat.percent(slice.share))
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(Theme.inkSecondary)
                        Text(ChartFormat.brl(slice.value))
                            .font(.footnote.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Theme.ink)
                            .frame(minWidth: 84, alignment: .trailing)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

/// Maiores gastos: barras horizontais com nome e valor escritos.
private struct RankingChart: View {
    let items: [AnswerChart.RankItem]

    var body: some View {
        let maxValue = items.map(\.value).max() ?? 1
        VStack(spacing: 12) {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(item.label)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        Text(ChartFormat.brl(item.value))
                            .font(.footnote.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Theme.ink)
                    }
                    ProgressBar(fraction: maxValue > 0 ? item.value / maxValue : 0,
                                fill: ChartPalette.single, track: Theme.track, height: 8)
                    Text(item.detail)
                        .font(.caption2)
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// Gasto acumulado dia a dia, com o mês anterior tracejado para comparar o ritmo.
private struct TrendChart: View {
    let current: [AnswerChart.TrendPoint]
    let previous: [AnswerChart.TrendPoint]
    let currentLabel: String
    let previousLabel: String
    let lastDay: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Chart {
                ForEach(previous) { point in
                    LineMark(x: .value("Dia", point.day), y: .value("Acumulado", point.value),
                             series: .value("Mês", previousLabel))
                        .foregroundStyle(ChartPalette.other)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [4, 4]))
                }
                ForEach(current) { point in
                    LineMark(x: .value("Dia", point.day), y: .value("Acumulado", point.value),
                             series: .value("Mês", currentLabel))
                        .foregroundStyle(ChartPalette.categorical[0])
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    AreaMark(x: .value("Dia", point.day), y: .value("Acumulado", point.value))
                        .foregroundStyle(ChartPalette.categorical[0].opacity(0.1))
                }
                if let last = current.last {
                    PointMark(x: .value("Dia", last.day), y: .value("Acumulado", last.value))
                        .foregroundStyle(ChartPalette.categorical[0])
                        .symbolSize(60)
                        .annotation(position: .top, spacing: 6) {
                            Text(ChartFormat.brl(last.value))
                                .font(.caption2.weight(.semibold).monospacedDigit())
                                .foregroundStyle(Theme.ink)
                        }
                }
            }
            .chartXScale(domain: 1...max(lastDay, 2))
            .chartXAxis {
                AxisMarks(values: [1, 10, 20, 30]) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let day = value.as(Int.self) { Text("dia \(day)") }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let amount = value.as(Double.self) { Text(ChartFormat.compact(amount)) }
                    }
                }
            }
            .frame(height: 170)
            .accessibilityHidden(true)

            HStack(spacing: 16) {
                LegendKey(color: ChartPalette.categorical[0], dashed: false, label: currentLabel,
                          value: current.last.map { ChartFormat.brl($0.value) })
                LegendKey(color: ChartPalette.other, dashed: true, label: previousLabel,
                          value: previous.last.map { ChartFormat.brl($0.value) })
            }
        }
    }
}

/// Últimos meses: entradas e gastos lado a lado, no mesmo eixo.
private struct MonthsChart: View {
    let bars: [AnswerChart.MonthBar]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Chart(bars) { bar in
                BarMark(x: .value("Mês", bar.label), y: .value("Valor", bar.value), width: .fixed(10))
                    .position(by: .value("Tipo", bar.kind))
                    .foregroundStyle(by: .value("Tipo", bar.kind))
                    .cornerRadius(3)
            }
            .chartForegroundStyleScale(["Entradas": ChartPalette.income, "Gastos": ChartPalette.spending])
            .chartLegend(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let amount = value.as(Double.self) { Text(ChartFormat.compact(amount)) }
                    }
                }
            }
            .frame(height: 170)
            .accessibilityHidden(true)

            HStack(spacing: 16) {
                LegendKey(color: ChartPalette.income, dashed: false, label: "Entradas", value: nil)
                LegendKey(color: ChartPalette.spending, dashed: false, label: "Gastos", value: nil)
            }
        }
    }
}

/// Orçamentos: barra de uso com o percentual escrito e ícone quando passa do limite.
private struct BudgetLines: View {
    let lines: [AnswerChart.BudgetLine]

    var body: some View {
        VStack(spacing: 12) {
            ForEach(lines) { line in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        IconTile(systemName: line.icon, style: .neutral, size: 26)
                        Text(line.name)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        HStack(spacing: 4) {
                            if line.level != .ok {
                                Image(systemName: line.level == .over ? "exclamationmark.triangle.fill" : "exclamationmark.circle")
                            }
                            Text("\(line.percent)%")
                                .monospacedDigit()
                        }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(color(line.level))
                    }
                    ProgressBar(fraction: line.fraction, fill: color(line.level), track: Theme.track, height: 8)
                    Text("\(ChartFormat.brl(line.spent)) de \(ChartFormat.brl(line.limit))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Theme.inkSecondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func color(_ level: BudgetLevel) -> Color {
        switch level {
        case .ok: return Theme.forest
        case .near: return Theme.warning
        case .over: return Theme.danger
        }
    }
}

private struct LegendKey: View {
    let color: Color
    let dashed: Bool
    let label: String
    let value: String?

    var body: some View {
        HStack(spacing: 6) {
            Path { path in
                path.move(to: CGPoint(x: 1.5, y: 1.5))
                path.addLine(to: CGPoint(x: 16.5, y: 1.5))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: dashed ? [3, 4] : []))
            .frame(width: 18, height: 3)
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.inkSecondary)
            if let value {
                Text(value)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.ink)
            }
        }
    }
}
