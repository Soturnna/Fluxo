import SwiftUI
import UniformTypeIdentifiers

/// Importar a fatura exportada pelo banco (CSV ou OFX) e corrigir as faturas do app.
/// O arquivo é lido só na memória do iPhone: nada vai para a internet nem para a IA,
/// e o arquivo não fica guardado. Só as correções (id da compra → fatura) vão para o cofre.
struct BillImportSheet: View {
    let card: StoredAccount
    @EnvironmentObject private var store: FinanceStore
    @Environment(\.dismiss) private var dismiss

    enum Choice: String, CaseIterable, Identifiable {
        case keep = "Manter", next = "Próxima fatura", exclude = "Tirar (repetida)"
        var id: String { rawValue }
    }

    @State private var picking = false
    @State private var file: BillFile?
    @State private var targetIndex = 0
    @State private var result: BillReconciliation?
    @State private var choices: [String: Choice] = [:]
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                if let file {
                    loaded(file)
                } else {
                    intro
                }
            }
            .navigationTitle("Importar fatura")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                if result != nil {
                    ToolbarItem(placement: .confirmationAction) { Button("Aplicar") { apply() }.bold() }
                }
            }
            .fileImporter(isPresented: $picking, allowedContentTypes: [.commaSeparatedText, .text, .data]) { outcome in
                if case .success(let url) = outcome { load(url) }
            }
        }
    }

    // MARK: Telas

    private var intro: some View {
        Group {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Use a fatura exportada pelo banco para conferir e corrigir as faturas do app.")
                    Text("No Nubank: abra a fatura e procure a opção de exportar (CSV ou OFX). Salve o arquivo no app Arquivos.")
                        .foregroundStyle(Theme.inkSecondary)
                }
                .font(.subheadline)
                .padding(.vertical, 4)
                Button("Escolher arquivo") { picking = true }
                    .bold()
            } footer: {
                Text("O arquivo é lido só neste iPhone e descartado em seguida. Nada vai para a internet nem para o agente.")
            }
            if let error {
                Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.danger) }
            }
        }
    }

    @ViewBuilder
    private func loaded(_ file: BillFile) -> some View {
        let schedule = store.cardSchedule(card)
        Section {
            Picker("Esta é a fatura de", selection: $targetIndex) {
                ForEach(schedule.cycles.filter { (-3...3).contains($0.index) }) { cycle in
                    Text(cycleLabel(cycle)).tag(cycle.index)
                }
            }
            .onChange(of: targetIndex) { _, _ in compute() }
            LabeledContent("Compras no arquivo", value: "\(file.lines.count)")
            LabeledContent("Total do arquivo") { MoneyText(value: file.total, font: .body.weight(.semibold)) }
        } footer: {
            Text("Confira se o total bate com o da fatura no app do banco.")
        }

        if let result {
            Section("Resultado") {
                LabeledContent("Compras encontradas", value: "\(result.matchedCount)")
                LabeledContent("Mudam de fatura", value: "\(result.moves.count)")
                LabeledContent("Fatura no app depois") {
                    MoneyText(value: result.totalAfter(removing: removedIds), font: .body.weight(.semibold))
                }
            }

            if !result.moves.isEmpty {
                Section {
                    ForEach(result.moves) { move in
                        row(move.transaction, detail: "estava em " + (move.from.map(monthName) ?? "nenhuma fatura"))
                    }
                } header: {
                    Text("Vão para esta fatura")
                }
            }

            if !result.extras.isEmpty {
                Section {
                    ForEach(result.extras) { extra in
                        VStack(alignment: .leading, spacing: 6) {
                            row(extra.transaction, detail: (extra.looksDuplicated ? "parece repetida · " : "") +
                                "em " + (extra.from.map(monthName) ?? "nenhuma fatura"))
                            Picker("O que fazer", selection: binding(for: extra)) {
                                ForEach(options(for: extra)) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                } header: {
                    Text("No app, mas não no arquivo")
                } footer: {
                    Text("Repetidas saem das faturas. As outras podem ir para a próxima fatura ou ficar onde estão.")
                }
            }

            if !result.missing.isEmpty {
                Section {
                    ForEach(result.missing) { line in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(line.title).font(.subheadline).lineLimit(1)
                                Text(line.date.formatted(.dateTime.day(.twoDigits).month(.twoDigits).locale(.ptBR)) +
                                     (line.installment.map { " · parcela \($0)" } ?? ""))
                                    .font(.caption).foregroundStyle(Theme.inkSecondary)
                            }
                            Spacer()
                            MoneyText(value: -line.amount, font: .subheadline)
                        }
                    }
                } header: {
                    Text("No arquivo, mas não chegou pelo Open Finance")
                } footer: {
                    Text("O banco ainda não mandou estas compras. Elas contam no total acima e devem aparecer numa próxima atualização.")
                }
            }
        }
    }

    private func row(_ item: StoredTransaction, detail: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.subheadline).lineLimit(1)
                Text(item.date.formatted(.dateTime.day(.twoDigits).month(.twoDigits).locale(.ptBR)) +
                     (item.installment.map { " · parcela \($0)" } ?? "") + " · " + detail)
                    .font(.caption).foregroundStyle(Theme.inkSecondary)
            }
            Spacer()
            MoneyText(value: -item.amount, font: .subheadline)
        }
    }

    // MARK: Lógica

    private var removedIds: Set<String> {
        Set(choices.filter { $0.value != .keep }.map(\.key))
    }

    private func options(for extra: BillReconciliation.Extra) -> [Choice] {
        let inTarget = extra.from.map { Calendar.current.isDate($0, equalTo: result?.target.due ?? .distantPast, toGranularity: .month) } ?? false
        return inTarget ? Choice.allCases : [.keep, .exclude]
    }

    private func binding(for extra: BillReconciliation.Extra) -> Binding<Choice> {
        Binding(get: { choices[extra.id] ?? .keep }, set: { choices[extra.id] = $0 })
    }

    private func cycleLabel(_ cycle: FinanceStore.BillCycle) -> String {
        let state = cycle.index == 0 ? " · aberta" : (cycle.index < 0 ? " · fechada" : "")
        return "\(cycle.monthName) (vence \(cycle.due.formatted(.dateTime.day(.twoDigits).month(.twoDigits).locale(.ptBR))))\(state)"
    }

    private func monthName(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).locale(.ptBR))
    }

    private func load(_ url: URL) {
        error = nil
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard size <= BillFileParser.maxBytes else { throw BillImportError.tooLarge }
            let data = try Data(contentsOf: url, options: .uncached)
            let parsed = try BillFileParser.parse(data: data, fileName: url.lastPathComponent)
            file = parsed
            targetIndex = suggestedIndex(for: parsed)
            compute()
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? BillImportError.unreadable.errorDescription
        }
    }

    /// Pelo vencimento no nome do arquivo; sem ele, a fatura aberta.
    private func suggestedIndex(for file: BillFile) -> Int {
        guard let date = file.nameDate else { return 0 }
        return store.cardSchedule(card).cycles.first {
            Calendar.current.isDate($0.due, equalTo: date, toGranularity: .month)
        }?.index ?? 0
    }

    private func compute() {
        guard let file else { return }
        result = store.reconcile(file, card: card, targetIndex: targetIndex)
        var defaults: [String: Choice] = [:]
        for extra in result?.extras ?? [] {
            defaults[extra.id] = extra.looksDuplicated ? .exclude : (options(for: extra).contains(.next) ? .next : .keep)
        }
        choices = defaults
    }

    private func apply() {
        guard let result else { return }
        var shifts = result.baseShifts
        for extra in result.extras {
            switch choices[extra.id] ?? .keep {
            case .keep: break
            case .next: if let shift = result.nextShifts[extra.id] { shifts[extra.id] = shift }
            case .exclude: shifts[extra.id] = UserData.billExcluded
            }
        }
        store.applyCardBillShifts(shifts)
        dismiss()
    }
}
