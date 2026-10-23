import SwiftUI

/// Conversa com o agente.
struct AgentView: View {
    @EnvironmentObject private var store: FinanceStore
    @EnvironmentObject private var agent: AgentEngine
    @EnvironmentObject private var audit: AuditLog
    @Environment(\.dismiss) private var dismiss

    @State private var input = ""
    @FocusState private var inputFocused: Bool

    private let suggestions = [
        "Analise meu mês",
        "Quais foram meus maiores gastos?",
        "Dia 26 vou comprar um tênis de R$ 300",
        "Como estão meus orçamentos?"
    ]

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if agent.entries.isEmpty {
                            welcome
                        }
                        ForEach(agent.entries) { entry in
                            entryView(entry)
                                .id(entry.id)
                        }
                        if agent.isThinking {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Pensando…")
                                    .font(.footnote)
                                    .foregroundStyle(Theme.inkSecondary)
                            }
                            .id("pensando")
                        }
                    }
                    .padding(16)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: agent.entries.count) { _, _ in
                    guard let last = agent.entries.last else { return }
                    // Resposta longa (com gráficos): rola até o começo dela, para ler de cima.
                    var anchor = UnitPoint.bottom
                    if case .answer = last { anchor = .top }
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(last.id, anchor: anchor) }
                }
            }
            .background(Theme.ground.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) { composer }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "chevron.down") }
                        .accessibilityLabel("Fechar o agente")
                }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text("Agente Fluxo")
                            .font(.headline)
                        Text("Não move dinheiro · você confirma cada mudança")
                            .font(.caption2)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { agent.reset() } label: { Image(systemName: "square.and.pencil") }
                        .disabled(agent.entries.isEmpty || agent.isThinking)
                        .accessibilityLabel("Nova conversa")
                }
            }
        }
        .tint(Theme.link)
    }

    // MARK: Boas-vindas

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                AppMark(size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pergunte sobre seu dinheiro")
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                    Text("Também posso prever gastos, trocar categorias, anotar transações e criar orçamentos. Você confirma cada mudança.")
                        .font(.footnote)
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if agent.hasKey {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button {
                            submit(suggestion)
                        } label: {
                            Text(suggestion)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Theme.ink)
                                .padding(.horizontal, 14)
                                .frame(minHeight: 40)
                                .background(Theme.surface, in: Capsule())
                                .overlay(Capsule().strokeBorder(Theme.line, lineWidth: Theme.hairline))
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                StatusBadge(text: "Cadastre a chave do Gemini em Ajustes para começar", icon: "key", color: Theme.warning)
            }
        }
        .card()
    }

    // MARK: Itens da conversa

    @ViewBuilder
    private func entryView(_ entry: AgentEngine.Entry) -> some View {
        switch entry {
        case .user(_, let text):
            HStack {
                Spacer(minLength: 48)
                Text(text)
                    .font(.body)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Theme.forest, in: UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 20, bottomTrailingRadius: 6, topTrailingRadius: 20, style: .continuous))
            }
        case .answer(_, let answer):
            AgentAnswerView(answer: answer, suggestionsEnabled: !agent.isThinking && agent.hasKey) { suggestion in
                submit(suggestion.prompt, display: suggestion.display)
            }
        case .activity(_, let text):
            Label(text, systemImage: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(Theme.inkSecondary)
                .padding(.horizontal, 4)
        case .action(let action):
            ActionCard(action: action) {
                agent.confirm(action.id, store: store)
            } onCancel: {
                agent.cancel(action.id)
            }
        case .error(_, let text):
            Label(text, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.danger)
                .padding(.horizontal, 4)
        }
    }

    // MARK: Campo de mensagem

    private var composer: some View {
        VStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Pergunte ou peça algo", text: $input, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($inputFocused)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(Theme.line, lineWidth: 1)
                    )
                    .disabled(!agent.hasKey)

                Button {
                    submit(input)
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 46, height: 46)
                        .background(Theme.lime, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || agent.isThinking || !agent.hasKey)
                .opacity(input.trimmingCharacters(in: .whitespaces).isEmpty || agent.isThinking ? 0.5 : 1)
                .accessibilityLabel("Enviar")
            }
            Text("Nomes de pessoas e números de documentos são filtrados antes do envio.")
                .font(.caption2)
                .foregroundStyle(Theme.inkSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(Theme.ground)
    }

    private func submit(_ text: String, display: String? = nil) {
        let message = text
        input = ""
        inputFocused = false
        Task { await agent.send(message, display: display, store: store, audit: audit) }
    }
}

/// Cartão de proposta: o que o agente quer mudar, com Confirmar e Cancelar.
private struct ActionCard: View {
    let action: PendingAction
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.lime)
                    .frame(width: 26, height: 26)
                    .background(Theme.ink, in: Circle())
                    .accessibilityHidden(true)
                Text(action.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                statusBadge
            }

            VStack(alignment: .leading, spacing: 3) {
                ForEach(action.details, id: \.self) { line in
                    Text(line)
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSecondary)
                }
            }

            if action.status == .pending {
                HStack(spacing: 10) {
                    Button(action: onConfirm) {
                        Text("Confirmar").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(LimeButtonStyle())

                    Button(action: onCancel) {
                        Text("Cancelar")
                            .font(.body.weight(.medium))
                            .foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .overlay(Capsule().strokeBorder(Theme.ink.opacity(0.25), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .card(padding: 14)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch action.status {
        case .pending:
            StatusBadge(text: "Aguardando você", icon: "hand.raised", color: Theme.warning)
        case .done:
            StatusBadge(text: "Feito", icon: "checkmark", color: Theme.positive)
        case .cancelled:
            StatusBadge(text: "Cancelado", icon: "xmark", color: Theme.inkSecondary)
        case .failed(let reason):
            StatusBadge(text: reason, icon: "exclamationmark.triangle", color: Theme.danger)
        }
    }
}
