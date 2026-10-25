import WidgetKit
import SwiftUI

/// ETAPA 1 — widget de TESTE TÉCNICO: confirma que o iloader instala o widget e que
/// a pasta compartilhada funciona. Mostra só o horário da última abertura do app.
struct TestEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetShared.Snapshot?
    let group: String?
}

struct TestProvider: TimelineProvider {
    func placeholder(in context: Context) -> TestEntry {
        TestEntry(date: .now, snapshot: .init(updatedAt: .now, note: "Teste"), group: "group")
    }

    func getSnapshot(in context: Context, completion: @escaping (TestEntry) -> Void) {
        completion(current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TestEntry>) -> Void) {
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now
        completion(Timeline(entries: [current()], policy: .after(next)))
    }

    private func current() -> TestEntry {
        TestEntry(date: .now, snapshot: WidgetShared.read(), group: WidgetShared.container()?.group)
    }
}

struct TestWidgetView: View {
    let entry: TestEntry
    private let lime = Color(red: 0.78, green: 0.94, blue: 0.24)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(lime)
                Text("Fluxo").font(.headline)
            }
            Spacer(minLength: 0)
            if let snapshot = entry.snapshot {
                Text("App aberto às").font(.caption2).foregroundStyle(.secondary)
                Text(snapshot.updatedAt, style: .time).font(.title3.bold())
                Text("Widget funcionando").font(.caption2).foregroundStyle(.secondary)
            } else if entry.group == nil {
                Text("Sem pasta compartilhada").font(.caption.bold())
                Text("O instalador não liberou o App Group.").font(.caption2).foregroundStyle(.secondary)
            } else {
                Text("Abra o Fluxo uma vez").font(.caption.bold())
                Text("para o widget receber dados.").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(for: .widget) { Color(red: 0.08, green: 0.12, blue: 0.10) }
        .foregroundStyle(.white)
    }
}

struct FluxoTestWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FluxoTestWidget", provider: TestProvider()) { entry in
            TestWidgetView(entry: entry)
        }
        .configurationDisplayName("Fluxo (teste)")
        .description("Teste técnico: mostra quando o app foi aberto. Sem dados financeiros.")
        .supportedFamilies([.systemSmall])
    }
}

@main
struct FluxoWidgetBundle: WidgetBundle {
    var body: some Widget {
        FluxoTestWidget()
    }
}
