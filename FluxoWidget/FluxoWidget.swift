import WidgetKit
import SwiftUI

/// Os widgets do Fluxo. Eles não buscam nada na internet nem abrem o cofre:
/// só leem o resumo que o app grava na pasta compartilhada (ver WidgetShared).
struct FluxoEntry: TimelineEntry {
    let date: Date
    let data: WidgetData
}

struct FluxoProvider: TimelineProvider {
    func placeholder(in context: Context) -> FluxoEntry {
        FluxoEntry(date: .now, data: WidgetSamples.data(showValues: true))
    }

    func getSnapshot(in context: Context, completion: @escaping (FluxoEntry) -> Void) {
        // Na galeria de widgets, um exemplo; na tela, os dados de verdade.
        completion(context.isPreview && WidgetShared.readPublic() == nil ? placeholder(in: context) : current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FluxoEntry>) -> Void) {
        let entry = current()
        // Redesenha a cada 30 min (os dias até o vencimento mudam à meia-noite).
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: entry.date) ?? entry.date
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func current() -> FluxoEntry {
        let now = Date.now
        let info = WidgetShared.readPublic() ?? .empty
        // Valores só quando ligados E com o iPhone destravado (arquivo com proteção completa).
        let values = info.showValues ? WidgetShared.readValues() : nil
        return FluxoEntry(date: now, data: WidgetData(info: info, values: values, now: now))
    }
}

// MARK: - Widgets da tela de início

struct ResumoWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "fluxo.resumo", provider: FluxoProvider()) { entry in
            ResumoWidgetView(data: entry.data)
                .containerBackground(for: .widget) { ResumoWidgetView.background }
                .widgetURL(URL(string: "fluxo://inicio"))
        }
        .configurationDisplayName("Saldo e fatura")
        .description("Saldo da conta e fatura atual do cartão.")
        .supportedFamilies([.systemSmall])
    }
}

struct RegistrarWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "fluxo.registrar", provider: FluxoProvider()) { entry in
            RegistrarWidgetView(data: entry.data)
                .containerBackground(for: .widget) { RegistrarWidgetView.background }
                .widgetURL(URL(string: "fluxo://registrar"))
        }
        .configurationDisplayName("Registrar")
        .description("Registre um Pix ou uma compra que o banco ainda não mostrou.")
        .supportedFamilies([.systemSmall])
    }
}

struct MesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "fluxo.mes", provider: FluxoProvider()) { entry in
            MesWidgetView(data: entry.data)
                .containerBackground(for: .widget) { MesWidgetView.background }
                .widgetURL(URL(string: "fluxo://inicio"))
        }
        .configurationDisplayName("Gastos do mês")
        .description("Gastos × orçamento e a divisão entre conta e cartão.")
        .supportedFamilies([.systemMedium])
    }
}

struct ProximosWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "fluxo.proximos", provider: FluxoProvider()) { entry in
            ProximosWidgetView(data: entry.data)
                .containerBackground(for: .widget) { ProximosWidgetView.background }
                .widgetURL(URL(string: "fluxo://fluxo-de-caixa"))
        }
        .configurationDisplayName("Próximos 30 dias")
        .description("Dia mais apertado, saldo previsto e as próximas contas.")
        .supportedFamilies([.systemMedium])
    }
}

struct CartaoWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "fluxo.cartao", provider: FluxoProvider()) { entry in
            CartaoWidgetView(data: entry.data)
                .containerBackground(for: .widget) { CartaoWidgetView.background }
                .widgetURL(URL(string: "fluxo://cartao"))
        }
        .configurationDisplayName("Cartão")
        .description("Fatura atual, vencimento e limite usado.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Widgets da tela bloqueada

/// Retangular e linha acima do relógio: fatura (valor oculto com o iPhone travado).
struct FaturaBloqueioWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "fluxo.bloqueio.fatura", provider: FluxoProvider()) { entry in
            FaturaBloqueioView(data: entry.data)
                .containerBackground(for: .widget) { Color.clear }
                .widgetURL(URL(string: "fluxo://cartao"))
        }
        .configurationDisplayName("Fatura")
        .description("Dias até o vencimento. O valor fica oculto com o iPhone travado.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline, .accessoryCircular])
    }
}

struct FaturaBloqueioView: View {
    @Environment(\.widgetFamily) private var family
    let data: WidgetData

    var body: some View {
        switch family {
        case .accessoryInline: FaturaInlineView(data: data)
        case .accessoryCircular: DiasCircularView(data: data)
        default: FaturaRectView(data: data)
        }
    }
}

/// Redondo: orçamento do mês (só a porcentagem).
struct OrcamentoBloqueioWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "fluxo.bloqueio.orcamento", provider: FluxoProvider()) { entry in
            OrcamentoCircularView(data: entry.data)
                .containerBackground(for: .widget) { Color.clear }
                .widgetURL(URL(string: "fluxo://inicio"))
        }
        .configurationDisplayName("Orçamento")
        .description("Quanto do orçamento do mês já foi usado.")
        .supportedFamilies([.accessoryCircular])
    }
}

@main
struct FluxoWidgetBundle: WidgetBundle {
    var body: some Widget {
        ResumoWidget()
        RegistrarWidget()
        MesWidget()
        ProximosWidget()
        CartaoWidget()
        FaturaBloqueioWidget()
        OrcamentoBloqueioWidget()
    }
}
