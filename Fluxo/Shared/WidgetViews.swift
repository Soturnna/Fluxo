import SwiftUI
import WidgetKit

// Telas dos widgets. Compiladas no widget E no app (a tela de testes do simulador
// desenha estas mesmas telas para conferir o layout antes de entregar).
// Sem margem externa: o iOS já põe a margem padrão dos widgets.

/// O que um widget recebe para desenhar.
struct WidgetData {
    var info: WidgetShared.PublicData
    /// Nil = valores desligados ou iPhone travado → mostra R$ ••••.
    var values: WidgetShared.Values?
    var now: Date

    var hasData: Bool { info.updatedAt > .distantPast }
}

enum WPalette {
    static let forest = Color(red: 0x14 / 255, green: 0x2A / 255, blue: 0x1C / 255)
    static let lime = Color(red: 0xC8 / 255, green: 0xF0 / 255, blue: 0x3C / 255)
    static let ink = Color(red: 0x10 / 255, green: 0x1A / 255, blue: 0x13 / 255)
    static let sub = Color(red: 0x4A / 255, green: 0x55 / 255, blue: 0x4D / 255)
    static let mist = Color(red: 0xC9 / 255, green: 0xD3 / 255, blue: 0xCB / 255)
    static let line = Color(red: 0xDF / 255, green: 0xE3 / 255, blue: 0xD8 / 255)
    static let track = Color(red: 0xE8 / 255, green: 0xEB / 255, blue: 0xE3 / 255)
    static let blue = Color(red: 0x2A / 255, green: 0x78 / 255, blue: 0xD6 / 255)
    static let orange = Color(red: 0xEB / 255, green: 0x68 / 255, blue: 0x34 / 255)
    static let green = Color(red: 0x1F / 255, green: 0x7A / 255, blue: 0x3A / 255)
    static let danger = Color(red: 0xB4 / 255, green: 0x34 / 255, blue: 0x2D / 255)
    static let warn = Color(red: 0x7A / 255, green: 0x4A / 255, blue: 0x00 / 255)
    static let limeInk = Color(red: 0x2E / 255, green: 0x3A / 255, blue: 0x10 / 255)
}

enum WFormat {
    private static let ptBR = Locale(identifier: "pt_BR")

    static func brl(_ value: Decimal?) -> String {
        guard let value else { return "R$ ••••" }
        return value.formatted(.currency(code: "BRL").locale(ptBR))
    }

    static func signed(_ value: Decimal?) -> String {
        guard let value else { return "R$ ••••" }
        let text = brl(value < 0 ? -value : value)
        return (value < 0 ? "−" : "+") + text
    }

    /// "9 nov"
    static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = ptBR
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date).replacingOccurrences(of: ".", with: "")
    }

    static func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(ptBR))
    }

    static func daysUntil(_ date: Date, from now: Date) -> Int {
        let calendar = Calendar.current
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
    }

    static func percent(_ fraction: Double) -> String { "\(Int((fraction * 100).rounded()))%" }

    static func dueLine(_ due: Date?, from now: Date) -> String {
        guard let due else { return "sem vencimento" }
        let days = daysUntil(due, from: now)
        if days < 0 { return "venceu \(day(due))" }
        if days == 0 { return "vence hoje" }
        if days == 1 { return "vence amanhã" }
        return "vence em \(days) dias"
    }
}

private extension Font {
    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

/// Mensagem quando ainda não há dados.
private struct EmptyWidgetMessage: View {
    let data: WidgetData
    var dark = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Fluxo").font(.headline)
            Spacer(minLength: 0)
            Text(data.hasData ? "Conecte seu banco no app" : "Abra o Fluxo uma vez")
                .font(.caption.bold())
            Text("para o widget receber os dados.")
                .font(.caption2)
                .foregroundStyle(dark ? WPalette.mist : WPalette.sub)
        }
        .foregroundStyle(dark ? Color.white : WPalette.ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Pequeno · Saldo e fatura

struct ResumoWidgetView: View {
    let data: WidgetData
    static let background = WPalette.forest

    var body: some View {
        if !data.info.hasBank {
            EmptyWidgetMessage(data: data, dark: true)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 5).fill(WPalette.lime).frame(width: 16, height: 16)
                    Text("Conta").font(.caption.weight(.semibold)).foregroundStyle(WPalette.mist)
                    Spacer(minLength: 0)
                    Text(WFormat.time(data.info.updatedAt)).font(.caption2).foregroundStyle(WPalette.mist)
                }
                Spacer(minLength: 6)
                Text("Saldo agora").font(.caption).foregroundStyle(WPalette.mist)
                Text(WFormat.brl(data.values?.balance))
                    .font(.rounded(22))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .privacySensitive()
                if data.info.hasCard {
                    Rectangle().fill(Color.white.opacity(0.16)).frame(height: 0.75).padding(.vertical, 7)
                    Text("Fatura atual").font(.caption).foregroundStyle(WPalette.mist)
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(WFormat.brl(data.values?.bill))
                            .font(.rounded(15, .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .privacySensitive()
                        if let due = data.info.billDue {
                            Text("vence \(WFormat.day(due))")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(WPalette.lime)
                                .lineLimit(1)
                        }
                    }
                } else if data.values == nil {
                    Spacer(minLength: 0)
                    HiddenValuesHint()
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

private struct HiddenValuesHint: View {
    var body: some View {
        Label("Valores ocultos", systemImage: "eye.slash")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(WPalette.lime)
    }
}

// MARK: - Pequeno · Registrar

struct RegistrarWidgetView: View {
    let data: WidgetData
    static let background = WPalette.lime

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(data.info.pendingCount > 0 ? "Aguardando o banco · \(data.info.pendingCount)" : "Nada aguardando o banco")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text("Pix e compras que o banco ainda não mostrou")
                .font(.caption)
                .lineLimit(3)
            Spacer(minLength: 6)
            HStack(spacing: 8) {
                Image(systemName: "plus").font(.body.weight(.bold))
                Text("Registrar").font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(WPalette.lime)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(WPalette.ink, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .foregroundStyle(WPalette.limeInk)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Médio · Mês

struct MesWidgetView: View {
    let data: WidgetData
    static let background = Color.white

    var body: some View {
        if !data.info.hasBank {
            EmptyWidgetMessage(data: data)
        } else {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Gastos de \(data.info.monthName)").font(.caption.weight(.semibold)).foregroundStyle(WPalette.sub)
                    Text(WFormat.brl(data.values?.spent))
                        .font(.rounded(22))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .privacySensitive()
                    Text(budgetLine).font(.caption).foregroundStyle(WPalette.sub).lineLimit(1).minimumScaleFactor(0.8)
                    if let fraction = data.info.budgetFraction {
                        ProgressBarShape(fraction: fraction, fill: fraction > 1 ? WPalette.danger : WPalette.forest)
                            .frame(height: 8)
                            .padding(.top, 6)
                    }
                    Spacer(minLength: 4)
                    Text(paceLine)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(data.info.paceAlert ? WPalette.warn : WPalette.sub)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Rectangle().fill(WPalette.line).frame(width: 0.75)
                VStack(alignment: .leading, spacing: 8) {
                    origin("Conta", color: WPalette.blue, value: data.values?.accountSpent)
                    if data.info.hasCard {
                        origin("Cartão", color: WPalette.orange, value: data.values?.cardSpent)
                    }
                    Spacer(minLength: 0)
                    Text("Atualizado \(WFormat.time(data.info.updatedAt))").font(.caption2).foregroundStyle(WPalette.sub)
                }
                .frame(width: 112, alignment: .leading)
            }
            .foregroundStyle(WPalette.ink)
        }
    }

    private var budgetLine: String {
        guard let fraction = data.info.budgetFraction else { return "Sem orçamento definido" }
        if let budget = data.values?.budget { return "de \(WFormat.brl(budget)) (\(WFormat.percent(fraction)))" }
        return "\(WFormat.percent(fraction)) do orçamento"
    }

    private var paceLine: String {
        let days = data.info.daysLeftInMonth
        let left = days == 1 ? "Falta 1 dia" : "Faltam \(days) dias"
        return data.info.paceAlert ? "\(left) · cuidado com o ritmo" : left
    }

    private func origin(_ title: String, color: Color, value: Decimal?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 2.5).fill(color).frame(width: 9, height: 9)
                Text(title).font(.caption).foregroundStyle(WPalette.sub)
            }
            Text(WFormat.brl(value))
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .privacySensitive()
        }
    }
}

struct ProgressBarShape: View {
    let fraction: Double
    let fill: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(WPalette.track)
                Capsule().fill(fill).frame(width: max(proxy.size.width * min(max(fraction, 0), 1), 4))
            }
        }
    }
}

// MARK: - Médio · Próximos 30 dias

struct ProximosWidgetView: View {
    let data: WidgetData
    static let background = Color.white

    var body: some View {
        if !data.info.hasBank {
            EmptyWidgetMessage(data: data)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Próximos 30 dias").font(.caption.weight(.semibold)).foregroundStyle(WPalette.sub)
                        Text(headline).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                        Text("Saldo previsto \(WFormat.brl(data.values?.lowestBalance))")
                            .font(.caption)
                            .foregroundStyle(data.info.goesNegative ? WPalette.danger : WPalette.sub)
                            .lineLimit(1)
                            .privacySensitive()
                    }
                    Spacer(minLength: 0)
                    Sparkline(points: data.info.sparkline)
                        .stroke(WPalette.blue, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .frame(width: 110, height: 42)
                }
                Rectangle().fill(WPalette.line).frame(height: 0.75)
                if data.info.nextEvents.isEmpty {
                    Text("Nenhuma conta prevista").font(.caption).foregroundStyle(WPalette.sub)
                } else {
                    ForEach(Array(data.info.nextEvents.prefix(2).enumerated()), id: \.offset) { index, event in
                        HStack(spacing: 8) {
                            Text(WFormat.day(event.date)).foregroundStyle(WPalette.sub).frame(width: 44, alignment: .leading)
                            Text(title(event, index: index)).lineLimit(1)
                            Spacer(minLength: 4)
                            Text(amount(event, index: index))
                                .fontWeight(.semibold)
                                .foregroundStyle(event.isIncome ? WPalette.green : WPalette.ink)
                                .privacySensitive()
                        }
                        .font(.caption)
                    }
                }
            }
            .foregroundStyle(WPalette.ink)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var headline: String {
        guard let day = data.info.tightestDay else { return "Sem previsão" }
        return data.info.goesNegative ? "Fica negativo em \(WFormat.day(day))" : "Dia mais apertado: \(WFormat.day(day))"
    }

    private func title(_ event: WidgetShared.PublicData.Event, index: Int) -> String {
        if let values = data.values, index < values.events.count { return values.events[index].title }
        switch event.kind {
        case .income: return "Entrada prevista"
        case .recurring: return "Conta fixa"
        case .planned: return "Gasto previsto"
        case .cardBill: return "Fatura do cartão"
        }
    }

    private func amount(_ event: WidgetShared.PublicData.Event, index: Int) -> String {
        guard let values = data.values, index < values.events.count else { return "R$ ••••" }
        return WFormat.signed(values.events[index].amount)
    }
}

/// Linha do saldo previsto (só o formato, de 0 a 1).
struct Sparkline: Shape {
    let points: [Double]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard points.count > 1 else {
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return path
        }
        let step = rect.width / CGFloat(points.count - 1)
        for (index, value) in points.enumerated() {
            let point = CGPoint(x: rect.minX + CGFloat(index) * step,
                                y: rect.maxY - CGFloat(min(max(value, 0), 1)) * rect.height)
            index == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        return path
    }
}

// MARK: - Pequeno · Cartão

struct CartaoWidgetView: View {
    let data: WidgetData
    static let background = Color.white

    var body: some View {
        if !data.info.hasCard {
            EmptyWidgetMessage(data: data)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 4).fill(WPalette.forest).frame(width: 28, height: 19)
                        RoundedRectangle(cornerRadius: 1).fill(WPalette.lime).frame(width: 7, height: 5).offset(x: 5, y: 6)
                    }
                    Text("Cartão").font(.caption.weight(.semibold)).foregroundStyle(WPalette.sub)
                }
                Spacer(minLength: 6)
                Text("Fatura atual").font(.caption).foregroundStyle(WPalette.sub)
                Text(WFormat.brl(data.values?.bill))
                    .font(.rounded(22))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .privacySensitive()
                Text(WFormat.dueLine(data.info.billDue, from: data.now).capitalizedFirst)
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 6)
                if let used = data.info.cardUsedFraction {
                    ProgressBarShape(fraction: used, fill: data.info.cardOverLimit ? WPalette.danger : WPalette.orange)
                        .frame(height: 6)
                    Text(data.info.cardOverLimit ? "Acima do limite" : "Limite usado \(WFormat.percent(used))")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(data.info.cardOverLimit ? WPalette.danger : WPalette.sub)
                        .padding(.top, 3)
                }
            }
            .foregroundStyle(WPalette.ink)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

// MARK: - Tela bloqueada

/// Retangular: fatura e orçamento. O valor some com o iPhone travado.
struct FaturaRectView: View {
    let data: WidgetData

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.headline).widgetAccentable().lineLimit(1)
            Text(WFormat.brl(data.values?.bill))
                .font(.system(.title3, design: .rounded).weight(.bold))
                .privacySensitive()
                .lineLimit(1)
            if let fraction = data.info.budgetFraction {
                Text("Orçamento \(WFormat.percent(fraction))").font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var title: String {
        guard data.info.hasCard, let due = data.info.billDue else { return "Fluxo" }
        let days = WFormat.daysUntil(due, from: data.now)
        return days >= 0 ? "Fatura · \(days) \(days == 1 ? "dia" : "dias")" : "Fatura vencida"
    }
}

/// Linha acima do relógio.
struct FaturaInlineView: View {
    let data: WidgetData

    var body: some View {
        if data.info.hasCard, let due = data.info.billDue {
            let days = WFormat.daysUntil(due, from: data.now)
            Label("Fatura vence \(WFormat.day(due)) · \(max(days, 0)) \(days == 1 ? "dia" : "dias")", systemImage: "creditcard")
        } else {
            Label("Fluxo", systemImage: "creditcard")
        }
    }
}

/// Redondo: dias até o vencimento.
struct DiasCircularView: View {
    let data: WidgetData

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                if let due = data.info.billDue, data.info.hasCard {
                    Text("\(max(WFormat.daysUntil(due, from: data.now), 0))").font(.system(.title2, design: .rounded).weight(.bold))
                } else {
                    Text("–").font(.title2.bold())
                }
                Text("DIAS").font(.system(size: 9, weight: .semibold))
            }
        }
    }
}

/// Redondo: orçamento do mês usado.
struct OrcamentoCircularView: View {
    let data: WidgetData

    var body: some View {
        if let fraction = data.info.budgetFraction {
            Gauge(value: min(fraction, 1)) {
                Text("ORÇ.")
            } currentValueLabel: {
                Text(WFormat.percent(fraction)).font(.system(.body, design: .rounded).weight(.bold))
            }
            .gaugeStyle(.accessoryCircularCapacity)
        } else {
            ZStack {
                AccessoryWidgetBackground()
                Text("ORÇ.").font(.caption2.weight(.semibold))
            }
        }
    }
}
