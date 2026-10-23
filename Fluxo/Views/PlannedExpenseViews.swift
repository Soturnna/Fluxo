import SwiftUI

/// Folha para criar ou editar um gasto previsto.
struct PlannedExpenseEditor: View {
    let existing: PlannedExpense?
    @EnvironmentObject private var store: FinanceStore
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var amount: Decimal = 0
    @State private var date = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
    @State private var categoryId = ""
    @State private var loaded = false
    @State private var errorText: String?

    private var dateRange: ClosedRange<Date> {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .month, value: -1, to: .now) ?? .now
        let end = calendar.date(byAdding: .year, value: 2, to: .now) ?? .now
        return start...end
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("O que você vai comprar ou pagar", text: $title)
                        .textInputAutocapitalization(.sentences)
                    CurrencyField(title: "Valor", value: $amount)
                    DatePicker("Data", selection: $date, in: dateRange, displayedComponents: .date)
                        .environment(\.locale, .ptBR)
                } footer: {
                    if let errorText {
                        Label(errorText, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.danger)
                    } else {
                        Text("Um gasto previsto não mexe no banco: ele só entra na projeção do mês e no orçamento.")
                    }
                }

                Section {
                    NavigationLink {
                        CategoryChoiceList(selection: $categoryId)
                    } label: {
                        if let category = store.category(withId: categoryId) {
                            CategoryLabel(category: category)
                        } else {
                            Text("Sem categoria")
                                .foregroundStyle(Theme.inkSecondary)
                        }
                    }
                } header: {
                    Text("Categoria")
                }

                Section {
                    Button {
                        save()
                    } label: {
                        Text(existing == nil ? "Adicionar gasto previsto" : "Salvar").frame(maxWidth: .infinity)
                    }
                    .disabled(FinanceStore.sanitizedName(title, maxLength: 60) == nil || amount <= 0)

                    if let existing {
                        Button(role: .destructive) {
                            store.deletePlannedExpense(id: existing.id)
                            dismiss()
                        } label: {
                            Text("Excluir").frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.ground.ignoresSafeArea())
            .navigationTitle(existing == nil ? "Gasto previsto" : "Editar previsto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
            .onAppear(perform: loadIfNeeded)
        }
        .tint(Theme.link)
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        if let existing {
            title = existing.title
            amount = existing.amount
            date = existing.date
            categoryId = existing.categoryId ?? ""
        }
    }

    private func save() {
        let expense = PlannedExpense(
            id: existing?.id ?? UUID().uuidString,
            date: Calendar.current.startOfDay(for: date),
            title: title,
            amount: amount,
            categoryId: categoryId.isEmpty ? nil : categoryId,
            createdByAgent: existing?.createdByAgent ?? false
        )
        if store.savePlannedExpense(expense) {
            dismiss()
        } else {
            errorText = "Confira o nome, o valor e a data."
        }
    }
}

/// Linha de um gasto previsto (Início e Transações).
struct PlannedExpenseRow: View {
    let expense: PlannedExpense
    let category: Category?

    private var isPast: Bool {
        expense.date < Calendar.current.startOfDay(for: .now)
    }

    private var whenText: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(expense.date) { return "hoje" }
        if calendar.isDateInTomorrow(expense.date) { return "amanhã" }
        return expense.date.formatted(.dateTime.day().month(.abbreviated).locale(.ptBR))
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                Text(expense.date.formatted(.dateTime.day()))
                    .font(.rounded(.headline, weight: .semibold))
                Text(expense.date.formatted(.dateTime.month(.abbreviated).locale(.ptBR)).uppercased())
                    .font(.caption2.weight(.medium))
            }
            .foregroundStyle(Theme.forest)
            .frame(width: 40, height: 40)
            .background(Theme.lime.opacity(0.45), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(expense.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text([category?.name, whenText].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(1)
                    if isPast {
                        Pill(text: "Já aconteceu?", icon: "questionmark.circle", tint: Theme.warning)
                    } else {
                        Pill(text: "Previsto", icon: "calendar", tint: Theme.inkSecondary)
                    }
                }
            }

            Spacer(minLength: 8)

            SignedMoneyText(amount: -expense.amount)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Bloco "Próximos gastos" do Início.
struct UpcomingPlannedSection: View {
    @EnvironmentObject private var store: FinanceStore
    let onAdd: () -> Void
    let onSelect: (PlannedExpense) -> Void

    var body: some View {
        let items = Array(store.plannedExpenses().prefix(4))
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Próximos gastos")
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button(action: onAdd) {
                    Label("Adicionar", systemImage: "plus")
                        .font(.subheadline.weight(.medium))
                }
            }
            .padding(.horizontal, 4)

            if items.isEmpty {
                Text("Nada previsto. Adicione aqui ou peça ao agente: “dia 26 vou comprar um tênis de R$ 300”.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Divider().overlay(Theme.line) }
                        Button {
                            onSelect(item)
                        } label: {
                            PlannedExpenseRow(
                                expense: item,
                                category: item.categoryId.flatMap { store.category(withId: $0) }
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                        .strokeBorder(Theme.line, lineWidth: Theme.hairline)
                )
            }
        }
    }
}

/// Identifica o que abrir na folha de gasto previsto.
enum PlannedEditorTarget: Identifiable {
    case new
    case edit(PlannedExpense)

    var id: String {
        switch self {
        case .new: return "novo"
        case .edit(let expense): return expense.id
        }
    }

    var expense: PlannedExpense? {
        if case .edit(let expense) = self { return expense }
        return nil
    }
}
