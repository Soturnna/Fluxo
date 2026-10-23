import SwiftUI

/// Folha de edição: novo orçamento, limite de uma categoria ou limite geral.
struct BudgetEditorSheet: View {
    let target: BudgetEditorTarget
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                switch target {
                case .newBudget:
                    CategoryPicker(onSaved: { dismiss() })
                case .budget(let id):
                    CategoryLimitForm(categoryId: id, onDone: { dismiss() })
                case .monthlyLimit:
                    MonthlyLimitForm(onDone: { dismiss() })
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
        }
        .tint(Theme.link)
    }
}

/// Passo 1 do novo orçamento: escolher a categoria de gasto.
/// Ao lado de cada uma aparece a média de gasto dos últimos 3 meses.
private struct CategoryPicker: View {
    @EnvironmentObject private var store: FinanceStore
    @EnvironmentObject private var lock: AppLock
    let onSaved: () -> Void
    @State private var creating = false

    private var available: [Category] {
        let used = Set(store.userData.budgets.map(\.categoryId))
        return store.allCategories
            .filter { $0.kind == .expense && !used.contains($0.id) }
            .sorted { store.averageSpending(ofCategory: $0.id) > store.averageSpending(ofCategory: $1.id) }
    }

    var body: some View {
        List {
            Section {
                ForEach(available) { category in
                    NavigationLink {
                        CategoryLimitForm(categoryId: category.id, onDone: onSaved)
                    } label: {
                        HStack(spacing: 8) {
                            CategoryLabel(category: category)
                            let average = store.averageSpending(ofCategory: category.id)
                            if average > 0 {
                                MoneyText(value: average, font: .footnote)
                                    .foregroundStyle(Theme.inkSecondary)
                            }
                        }
                    }
                }
            } footer: {
                Text("O valor à direita é a sua média mensal nos últimos 3 meses.")
            }

            Section {
                Button {
                    creating = true
                } label: {
                    Label("Criar uma categoria nova", systemImage: "plus.circle")
                }
            }
        }
        .navigationTitle("Escolha a categoria")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $creating) {
            NavigationStack {
                CategoryEditorView(mode: .create)
            }
            .environmentObject(store)
            .environmentObject(lock)
        }
    }
}

/// Limite mensal de uma categoria.
private struct CategoryLimitForm: View {
    let categoryId: String
    let onDone: () -> Void
    @EnvironmentObject private var store: FinanceStore
    @State private var limit: Decimal = 0
    @State private var loaded = false

    private var category: Category? { store.category(withId: categoryId) }

    private var existing: Budget? {
        store.userData.budgets.first { $0.categoryId == categoryId }
    }

    var body: some View {
        Form {
            Section {
                if let category {
                    CategoryLabel(category: category)
                }
                CurrencyField(title: "Limite por mês", value: $limit)
            } header: {
                Text("Limite por mês")
            }

            let average = store.averageSpending(ofCategory: categoryId)
            if average > 0 {
                Section {
                    HStack {
                        Text("Média dos últimos 3 meses")
                        Spacer()
                        MoneyText(value: average, font: .body)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    Button("Usar a média como limite") { limit = average }
                } footer: {
                    Text("A média considera só gastos reais: o que é marcado como “Não conta” fica de fora.")
                }
            }

            Section {
                Button {
                    store.setBudget(categoryId: categoryId, limit: limit)
                    onDone()
                } label: {
                    Text("Salvar orçamento").frame(maxWidth: .infinity)
                }
                .disabled(limit <= 0)

                if existing != nil {
                    Button(role: .destructive) {
                        store.removeBudget(categoryId: categoryId)
                        onDone()
                    } label: {
                        Text("Remover orçamento").frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .navigationTitle(existing == nil ? "Novo orçamento" : "Editar orçamento")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            limit = existing?.limit ?? 0
        }
    }
}

/// Limite geral do mês (opcional).
private struct MonthlyLimitForm: View {
    let onDone: () -> Void
    @EnvironmentObject private var store: FinanceStore
    @State private var useSum = true
    @State private var limit: Decimal = 0
    @State private var loaded = false

    private var categoriesSum: Decimal {
        store.userData.budgets.reduce(Decimal(0)) { $0 + $1.limit }
    }

    var body: some View {
        Form {
            Section {
                Toggle("Usar a soma das categorias", isOn: $useSum)
                if useSum {
                    HStack {
                        Text("Soma atual")
                        Spacer()
                        MoneyText(value: categoriesSum, font: .body)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                } else {
                    CurrencyField(title: "Limite geral do mês", value: $limit)
                }
            } footer: {
                Text("O limite geral é o teto do mês inteiro, incluindo gastos em categorias sem orçamento.")
            }

            Section {
                Button {
                    store.setMonthlyLimit(useSum ? nil : limit)
                    onDone()
                } label: {
                    Text("Salvar").frame(maxWidth: .infinity)
                }
                .disabled(!useSum && limit <= 0)
            }
        }
        .navigationTitle("Limite geral")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let current = store.userData.monthlyLimit {
                useSum = false
                limit = current
            }
        }
    }
}
