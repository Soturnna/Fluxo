import SwiftUI
import UniformTypeIdentifiers

/// Importar a fatura exportada pelo banco (CSV ou OFX) e corrigir as faturas do app.
/// O arquivo é lido só na memória do iPhone: nada vai para a internet nem para a IA,
/// e o arquivo não fica guardado. Só as correções (id da compra → fatura) vão para o cofre.
struct BillImportSheet: View {
    let card: StoredAccount
    /// Arquivo já lido pela tela do cartão (o seletor abre lá, fora da folha).
    var initialFile: BillFile? = nil
    @EnvironmentObject private var store: FinanceStore
    @Environment(\.dismiss) private var dismiss

    enum Choice: String, CaseIterable, Identifiable {
        case keep = "Manter", next = "Próxima fatura", exclude = "Tirar (repetida)"
        var id: String { rawValue }
    }

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
            .onAppear {
                if file == nil, let initialFile {
                    file = initialFile
                    targetIndex = suggestedIndex(for: initialFile)
                    compute()
                }
            }
        }
    }

    // MARK: Telas

    private var intro: some View {
        Group {
            Section {
                Text("Use a fatura exportada pelo banco (OFX ou CSV) para conferir e corrigir as faturas do app.")
                    .font(.subheadline)
                    .padding(.vertical, 4)
            }
            if let error {
                Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.danger) }
            }
            BillIntakeSection(onFile: { use($0) }, onError: { error = $0 })
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
            LabeledContent("Soma das compras") { MoneyText(value: file.total, font: .body.weight(.semibold)) }
            if let bankTotal = file.bankTotal {
                LabeledContent("Total da fatura (banco)") { MoneyText(value: bankTotal, font: .body.weight(.semibold)) }
            }
        } footer: {
            Text("Juros, encargos e saldo anterior entram no total do banco, mas não aparecem como compra.")
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

    private func use(_ parsed: BillFile) {
        error = nil
        file = parsed
        targetIndex = suggestedIndex(for: parsed)
        compute()
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
        if let bankTotal = file?.bankTotal {
            store.saveBankBillTotal(bankTotal, cardId: card.id, dueMonth: result.target.due)
        }
        dismiss()
    }
}
