import SwiftUI
import PhotosUI

/// Registrar um lançamento antes de o banco mandar: digitando ou lendo um print.
struct ProvisionalEditorSheet: View {
    @EnvironmentObject private var store: FinanceStore
    @Environment(\.dismiss) private var dismiss

    /// Print já escolhido em outro lugar (ex.: no agente): é lido ao abrir.
    var initialPhoto: PhotosPickerItem? = nil
    var onSaved: (ProvisionalEntry) -> Void = { _ in }

    @State private var isIncome = false
    @State private var amount: Decimal = 0
    @State private var title = ""
    @State private var counterparty = ""
    @State private var date = Date.now
    @State private var method: ProvisionalEntry.Method = .account
    @State private var source: ProvisionalEntry.Source = .manual

    @State private var photo: PhotosPickerItem?
    @State private var reading = false
    @State private var readMessage: String?
    @State private var readLines: [String] = []
    @State private var saveError: String?

    private var dateRange: ClosedRange<Date> {
        Date.now.addingTimeInterval(-60 * 86_400)...Date.now.addingTimeInterval(86_400)
    }

    private var canSave: Bool {
        amount > 0 && !title.trimmingCharacters(in: .whitespaces).isEmpty && !reading
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PhotosPicker(selection: $photo, matching: .images) {
                        HStack {
                            Label("Ler de um print", systemImage: "text.viewfinder")
                            Spacer()
                            if reading { ProgressView() }
                        }
                    }
                    if let readMessage {
                        Text(readMessage)
                            .font(.footnote)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                } footer: {
                    Text("O print é lido aqui no iPhone. A imagem não é guardada nem enviada a ninguém, nem à IA.")
                }

                Section {
                    Picker("Tipo", selection: $isIncome) {
                        Text("Saída").tag(false)
                        Text("Entrada").tag(true)
                    }
                    .pickerStyle(.segmented)
                    CurrencyField(title: "Valor", value: $amount)
                    TextField("Descrição (ex.: Pix enviado)", text: $title)
                    TextField("Pessoa ou estabelecimento (opcional)", text: $counterparty)
                    DatePicker("Quando", selection: $date, in: dateRange, displayedComponents: [.date, .hourAndMinute])
                    Picker("Por onde", selection: $method) {
                        Text("Conta (Pix, débito, boleto)").tag(ProvisionalEntry.Method.account)
                        Text("Cartão de crédito").tag(ProvisionalEntry.Method.creditCard)
                    }
                } header: {
                    Text("Lançamento")
                } footer: {
                    Text("Fica como provisório até o banco confirmar, na próxima busca do Meu Pluggy. Os da conta já entram no saldo estimado; os do cartão vão para a fatura e não mexem no saldo.")
                }

                if !readLines.isEmpty {
                    Section {
                        DisclosureGroup("Texto lido do print") {
                            Text(readLines.joined(separator: "\n"))
                                .font(.caption.monospaced())
                                .foregroundStyle(Theme.inkSecondary)
                                .textSelection(.enabled)
                        }
                    }
                }

                if let saveError {
                    Section {
                        Label(saveError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.danger)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.ground.ignoresSafeArea())
            .navigationTitle("Registrar lançamento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar", action: save)
                        .disabled(!canSave)
                }
            }
            .onChange(of: photo) { _, item in
                guard let item else { return }
                Task { await read(item) }
            }
            .task {
                if let initialPhoto, photo == nil { photo = initialPhoto }
            }
        }
    }

    // MARK: Leitura do print

    @MainActor
    private func read(_ item: PhotosPickerItem) async {
        reading = true
        readMessage = nil
        defer { reading = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data)
            else {
                readMessage = "Não consegui abrir essa imagem."
                return
            }
            let draft = try await ReceiptReader.read(image)
            apply(draft)
        } catch {
            readMessage = "Não consegui ler esse print. Preencha abaixo."
        }
    }

    private func apply(_ draft: ReceiptDraft) {
        source = .screenshot
        readLines = draft.lines
        isIncome = draft.isIncome
        title = draft.title
        if let value = draft.amount { amount = value }
        counterparty = draft.counterparty ?? ""
        if let when = draft.date, FinanceStore.isReasonableProvisionalDate(when) { date = when }
        method = .account

        var found: [String] = []
        if draft.amount != nil { found.append("o valor") }
        if draft.date != nil { found.append("a data") }
        if draft.counterparty != nil { found.append("o nome") }
        readMessage = found.isEmpty
            ? "Não achei valor nem data no print. Preencha abaixo."
            : "Li \(ListFormatter.localizedString(byJoining: found)). Confira antes de salvar."
    }

    // MARK: Salvar

    private func save() {
        let name = counterparty.trimmingCharacters(in: .whitespaces)
        let entry = ProvisionalEntry(
            date: date,
            title: title.trimmingCharacters(in: .whitespaces),
            counterparty: name.isEmpty ? nil : name,
            amount: isIncome ? amount : -amount,
            method: method,
            source: source
        )
        if store.saveProvisional(entry) {
            onSaved(entry)
            dismiss()
        } else {
            saveError = "Confira o valor (maior que zero) e a data (até 60 dias atrás)."
        }
    }
}

/// Início: lançamentos que o banco ainda não confirmou.
struct ProvisionalSection: View {
    @EnvironmentObject private var store: FinanceStore
    let onAdd: () -> Void

    var body: some View {
        let items = store.pendingProvisionals
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Aguardando o banco")
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button(action: onAdd) {
                    Label("Registrar", systemImage: "plus")
                        .font(.subheadline.weight(.medium))
                }
            }
            .padding(.horizontal, 4)

            if items.isEmpty {
                Text("Fez um Pix ou uma compra agora? Registre aqui, com um print ou digitando, e o saldo estimado já desconta. Quando o banco confirmar, sai daqui sozinho.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(items.prefix(6).enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Divider().overlay(Theme.line) }
                        ProvisionalRow(entry: item)
                            .contextMenu {
                                Button(role: .destructive) {
                                    store.deleteProvisional(id: item.id)
                                } label: {
                                    Label("Remover", systemImage: "trash")
                                }
                            }
                    }
                }
                .padding(.horizontal, 14)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                        .strokeBorder(Theme.line, lineWidth: Theme.hairline)
                )
                Text("Toque e segure um item para remover.")
                    .font(.caption)
                    .foregroundStyle(Theme.inkTertiary)
                    .padding(.horizontal, 4)
            }
        }
    }
}

struct ProvisionalRow: View {
    let entry: ProvisionalEntry

    private var icon: String {
        switch entry.source {
        case .screenshot: return "text.viewfinder"
        case .applePay: return "wave.3.right"
        case .manual: return "square.and.pencil"
        case .agent: return "sparkles"
        }
    }

    /// Há mais de 5 dias sem aparecer no banco: vale conferir.
    private var isStale: Bool {
        entry.date < Date.now.addingTimeInterval(-5 * 86_400)
    }

    var body: some View {
        HStack(spacing: 12) {
            IconTile(systemName: icon, style: .neutral, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayTitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text("\(FinanceStore.bankTimeLabel(entry.date)) · \(entry.method.label)")
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
                if isStale {
                    Label("Ainda não apareceu no banco", systemImage: "exclamationmark.circle")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Theme.warning)
                }
            }
            Spacer(minLength: 8)
            SignedMoneyText(amount: entry.amount, muted: false)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}
