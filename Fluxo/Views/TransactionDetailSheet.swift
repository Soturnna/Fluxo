import SwiftUI

/// Detalhes de uma transação e troca de categoria.
struct TransactionDetailSheet: View {
    let transaction: StoredTransaction
    @EnvironmentObject private var store: FinanceStore
    @EnvironmentObject private var lock: AppLock
    @Environment(\.dismiss) private var dismiss

    @State private var selectedId = ""
    @State private var applyToSameTitle = true
    @State private var loaded = false

    private var current: Category { store.category(for: transaction) }
    private var selected: Category { store.category(withId: selectedId) ?? current }
    private var sameTitleCount: Int { store.sameTitleCount(as: transaction) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        SignedMoneyText(
                            amount: transaction.amount,
                            muted: selected.kind == .transfer,
                            font: .rounded(.title, weight: .bold)
                        )
                        Text(transaction.title)
                            .font(.headline)
                            .foregroundStyle(Theme.ink)
                        if transaction.title != transaction.description {
                            Text(transaction.description)
                                .font(.footnote)
                                .foregroundStyle(Theme.inkSecondary)
                        }
                    }
                    .padding(.vertical, 4)
                    detailRow("Data", transaction.date.formatted(.dateTime.day().month(.wide).year().locale(.ptBR)))
                    if let account = store.account(withId: transaction.accountId) {
                        detailRow("Conta", account.displayName)
                    }
                    if transaction.isPending {
                        detailRow("Situação", "Pendente")
                    }
                    if let installment = transaction.installment {
                        detailRow("Parcela", installment)
                    }
                }

                Section {
                    NavigationLink {
                        CategoryChoiceList(selection: $selectedId)
                    } label: {
                        CategoryLabel(category: selected)
                    }
                    if sameTitleCount > 0 {
                        Toggle(isOn: $applyToSameTitle) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Aplicar a “\(transaction.title)”")
                                Text(sameTitleCount == 1
                                     ? "Mais 1 transação e as próximas"
                                     : "Mais \(sameTitleCount) transações e as próximas")
                                    .font(.footnote)
                                    .foregroundStyle(Theme.inkSecondary)
                            }
                        }
                    }
                } header: {
                    Text("Categoria")
                } footer: {
                    Text("Categoria informada pelo banco: \(transaction.rawCategory ?? "não informada").")
                }

                Section {
                    Button {
                        store.assignCategory(
                            selected.id,
                            to: transaction,
                            applyToSameTitle: applyToSameTitle && sameTitleCount > 0
                        )
                        dismiss()
                    } label: {
                        Text("Salvar").frame(maxWidth: .infinity)
                    }
                    .disabled(selected.id == current.id && !(applyToSameTitle && sameTitleCount > 0))
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.ground.ignoresSafeArea())
            .navigationTitle("Transação")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar") { dismiss() }
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                selectedId = current.id
            }
        }
        .tint(Theme.link)
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(Theme.inkSecondary)
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }
}
