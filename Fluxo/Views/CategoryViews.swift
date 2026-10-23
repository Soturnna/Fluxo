import SwiftUI

// MARK: - Gerenciar categorias

/// Lista de categorias (prontas e suas), agrupadas por tipo.
struct CategoriesView: View {
    @EnvironmentObject private var store: FinanceStore
    @EnvironmentObject private var lock: AppLock
    @State private var creating = false

    var body: some View {
        List {
            ForEach(CategoryKind.allCases) { kind in
                let items = store.allCategories.filter { $0.kind == kind }
                if !items.isEmpty {
                    Section {
                        ForEach(items) { category in
                            NavigationLink {
                                CategoryEditorView(mode: .edit(category))
                            } label: {
                                CategoryLabel(category: category, detail: countText(for: category))
                            }
                        }
                    } header: {
                        Text(kind == .transfer ? "Não contam nos totais" : (kind == .income ? "Renda" : "Gastos"))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.ground.ignoresSafeArea())
        .navigationTitle("Categorias")
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 84) }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    creating = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Nova categoria")
            }
        }
        .sheet(isPresented: $creating) {
            NavigationStack {
                CategoryEditorView(mode: .create)
            }
            .environmentObject(store)
            .environmentObject(lock)
        }
    }

    private func countText(for category: Category) -> String {
        let count = store.transactionCount(inCategory: category.id)
        return count == 1 ? "1 transação" : "\(count) transações"
    }
}

/// Ícone + nome de uma categoria, com um detalhe opcional à direita.
struct CategoryLabel: View {
    let category: Category
    var detail: String? = nil
    var selected = false

    var body: some View {
        HStack(spacing: 12) {
            IconTile(systemName: category.icon, style: category.kind == .transfer ? .neutral : .security)
            Text(category.name)
                .foregroundStyle(Theme.ink)
            if !category.isBuiltIn {
                Pill(text: "sua", icon: "person", tint: Theme.inkSecondary)
            }
            Spacer(minLength: 8)
            if let detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSecondary)
            }
            if selected {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.link)
                    .accessibilityLabel("Selecionada")
            }
        }
    }
}

// MARK: - Criar ou editar uma categoria

struct CategoryEditorView: View {
    enum Mode {
        case create
        case edit(Category)
    }

    let mode: Mode
    /// Chamado com a categoria criada (usado ao criar a partir de uma transação).
    var onCreated: ((Category) -> Void)? = nil

    @EnvironmentObject private var store: FinanceStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var icon = "ellipsis"
    @State private var kind: CategoryKind = .expense
    @State private var loaded = false
    @State private var errorText: String?
    @State private var confirmDelete = false

    private var editing: Category? {
        if case .edit(let category) = mode { return category }
        return nil
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 6)

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    IconTile(systemName: icon, style: kind == .transfer ? .neutral : .security, size: 40)
                    TextField("Nome da categoria", text: $name)
                        .font(.headline)
                        .textInputAutocapitalization(.sentences)
                        .submitLabel(.done)
                }
            } footer: {
                if let errorText {
                    Label(errorText, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.danger)
                }
            }

            Section {
                Picker("Tipo", selection: $kind) {
                    ForEach(CategoryKind.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Tipo")
            } footer: {
                Text(kind.explanation)
            }

            Section {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(Category.iconChoices, id: \.self) { symbol in
                        Button {
                            icon = symbol
                        } label: {
                            Image(systemName: symbol)
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(icon == symbol ? Theme.ink : Theme.inkSecondary)
                                .frame(width: 44, height: 44)
                                .background(icon == symbol ? Theme.lime.opacity(0.55) : Theme.track,
                                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(symbol)
                        .accessibilityAddTraits(icon == symbol ? .isSelected : [])
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Ícone")
            }

            Section {
                Button {
                    save()
                } label: {
                    Text(editing == nil ? "Criar categoria" : "Salvar alterações")
                        .frame(maxWidth: .infinity)
                }
                .disabled(FinanceStore.sanitizedName(name) == nil)

                if let editing, editing.isBuiltIn {
                    Button("Restaurar nome e ícone originais") {
                        store.resetBuiltInCategory(id: editing.id)
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
                }

                if let editing, !editing.isBuiltIn {
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Text("Excluir categoria").frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.ground.ignoresSafeArea())
        .navigationTitle(editing == nil ? "Nova categoria" : "Editar categoria")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if editing == nil {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
        }
        .confirmationDialog("Excluir esta categoria?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Excluir", role: .destructive) {
                if let editing { store.deleteCustomCategory(id: editing.id) }
                dismiss()
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("As transações dela voltam para a categoria automática, e o orçamento dela é removido.")
        }
        .onAppear(perform: loadIfNeeded)
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        if let editing {
            name = editing.name
            icon = editing.icon
            kind = editing.kind
        }
    }

    private func save() {
        if let editing {
            if store.updateCategory(id: editing.id, name: name, icon: icon, kind: kind) {
                dismiss()
            } else {
                errorText = "Já existe uma categoria com esse nome."
            }
        } else if let created = store.createCategory(name: name, icon: icon, kind: kind) {
            onCreated?(created)
            dismiss()
        } else {
            errorText = "Já existe uma categoria com esse nome."
        }
    }
}

// MARK: - Escolher a categoria de uma transação

struct CategoryChoiceList: View {
    @Binding var selection: String
    @EnvironmentObject private var store: FinanceStore
    @EnvironmentObject private var lock: AppLock
    @Environment(\.dismiss) private var dismiss
    @State private var creating = false

    var body: some View {
        List {
            Section {
                Button {
                    creating = true
                } label: {
                    Label("Nova categoria", systemImage: "plus.circle")
                }
            }
            ForEach(CategoryKind.allCases) { kind in
                let items = store.allCategories.filter { $0.kind == kind }
                if !items.isEmpty {
                    Section {
                        ForEach(items) { category in
                            Button {
                                selection = category.id
                                dismiss()
                            } label: {
                                CategoryLabel(category: category, selected: category.id == selection)
                            }
                        }
                    } header: {
                        Text(kind == .transfer ? "Não contam nos totais" : (kind == .income ? "Renda" : "Gastos"))
                    }
                }
            }
        }
        .navigationTitle("Categoria")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $creating) {
            NavigationStack {
                CategoryEditorView(mode: .create, onCreated: { created in
                    selection = created.id
                })
            }
            .environmentObject(store)
            .environmentObject(lock)
        }
    }
}
