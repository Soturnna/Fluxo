import SwiftUI

/// Conexões do Open Finance: situação de cada banco e sincronização.
struct ConnectionsView: View {
    @EnvironmentObject private var store: FinanceStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                infoCard

                if !store.isConfigured {
                    notConfiguredCard
                } else {
                    stateBanner
                    ForEach(store.connections) { connection in
                        ConnectionCard(
                            connection: connection,
                            storedCount: store.storedTransactionCount(forItem: connection.id)
                        )
                    }
                    nextBankUpdate
                    syncButton
                }

                Link(destination: URL(string: "https://meu.pluggy.ai")!) {
                    HStack(spacing: 6) {
                        Text("Gerenciar bancos no Meu Pluggy")
                        Image(systemName: "arrow.up.right")
                            .imageScale(.small)
                    }
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity, minHeight: 44)
                }

                Text("O Meu Pluggy busca os dados no banco sozinho, 1 vez por dia, e não aceita busca manual. “Sincronizar” traz o que ele já buscou. Para revogar um acesso, remova o banco no Meu Pluggy.")
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSecondary)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .background(Theme.ground.ignoresSafeArea())
        .navigationTitle("Conexões")
        .navigationBarTitleDisplayMode(.large)
        .task { await store.sync() }
        .refreshable { await store.sync() }
    }

    private var infoCard: some View {
        HStack(alignment: .top, spacing: 12) {
            IconTile(systemName: "checkmark.shield", style: .security, size: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text("Open Finance via Meu Pluggy")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text("Você autoriza cada banco no Meu Pluggy. O Fluxo só lê os dados e nunca vê a senha do seu banco.")
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .card(padding: 14)
    }

    private var notConfiguredCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            StatusBadge(text: "Credenciais pendentes", icon: "exclamationmark.circle", color: Theme.warning)
            Text("Cadastre o Client ID, o Client Secret e os IDs das conexões para o Fluxo ler seus bancos.")
                .font(.subheadline)
                .foregroundStyle(Theme.inkSecondary)
            NavigationLink {
                CredentialsView(kind: .pluggy)
            } label: {
                Text("Cadastrar credenciais")
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(LimeButtonStyle())
        }
        .card()
    }

    @ViewBuilder
    private var stateBanner: some View {
        switch store.state {
        case .loading:
            HStack(spacing: 8) {
                ProgressView()
                Text("Sincronizando com o Pluggy…")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSecondary)
            }
            .padding(.horizontal, 4)
        case .failed(let message):
            StatusBadge(text: message, icon: "exclamationmark.triangle.fill", color: Theme.danger)
                .padding(.horizontal, 4)
        case .loaded(let date):
            Text("Sincronizado \(date.formatted(Date.RelativeFormatStyle(presentation: .named, locale: .ptBR)))")
                .font(.footnote)
                .foregroundStyle(Theme.inkTertiary)
                .padding(.horizontal, 4)
        case .idle:
            EmptyView()
        }
    }

    /// Quando o banco manda dados novos: a próxima busca automática do Pluggy.
    @ViewBuilder
    private var nextBankUpdate: some View {
        if let next = store.connections.compactMap({ $0.item?.nextAutoSyncAt }).filter({ $0 > .now }).min() {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(Theme.inkSecondary)
                Text("Dados novos do banco: \(FinanceStore.bankTimeLabel(next)), na busca automática do Meu Pluggy.")
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 4)
        }
    }

    private var syncButton: some View {
        Button {
            Task { await store.sync() }
        } label: {
            Label("Sincronizar com o Pluggy", systemImage: "arrow.triangle.2.circlepath")
                .font(.body.weight(.medium))
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, minHeight: 48)
                .overlay(Capsule().strokeBorder(Theme.ink.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(store.state == .loading)
    }
}

/// Cartão de uma conexão: banco, situação, autorização e contas.
private struct ConnectionCard: View {
    let connection: FinanceStore.Connection
    let storedCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Text(connection.initials)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 40, height: 40)
                    .background(Theme.track, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(connection.institution)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                        Spacer(minLength: 8)
                        healthBadge
                    }
                    Text(syncLine)
                        .font(.footnote)
                        .foregroundStyle(Theme.inkSecondary)
                    if let consent = consentLine {
                        Text(consent)
                            .font(.footnote)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }
            }

            if !connection.accounts.isEmpty {
                Divider().overlay(Theme.line)
                VStack(spacing: 10) {
                    ForEach(connection.accounts) { account in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(kindLabel(account))
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.ink)
                                Text(account.marketingName ?? account.name)
                                    .font(.caption)
                                    .foregroundStyle(Theme.inkTertiary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            MoneyText(value: account.balance, font: .rounded(.subheadline, weight: .semibold))
                                .foregroundStyle(Theme.ink)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }

            StatusBadge(
                text: storedCount == 1 ? "1 transação guardada neste iPhone" : "\(storedCount) transações guardadas neste iPhone",
                icon: "lock.fill"
            )
        }
        .card()
    }

    private func kindLabel(_ account: PluggyAccount) -> String {
        if account.isCreditCard { return "Cartão de crédito" }
        return account.subtype == "SAVINGS_ACCOUNT" ? "Poupança" : "Conta"
    }

    @ViewBuilder
    private var healthBadge: some View {
        switch connection.health {
        case .ok:
            StatusBadge(text: "Ativa", icon: "checkmark", color: Theme.positive)
        case .syncing:
            StatusBadge(text: "Atualizando", icon: "arrow.triangle.2.circlepath", color: Theme.inkSecondary)
        case .attention(let text):
            StatusBadge(text: text, icon: "clock", color: Theme.warning)
        case .failed(let text):
            StatusBadge(text: text, icon: "exclamationmark.triangle", color: Theme.danger)
        }
    }

    private var syncLine: String {
        var parts = [connection.accountsSummary]
        if let last = connection.item?.lastUpdatedAt {
            parts.append("dados do banco de \(FinanceStore.bankTimeLabel(last))")
        }
        if let next = connection.item?.nextAutoSyncAt, next > .now {
            parts.append("próxima busca \(FinanceStore.bankTimeLabel(next))")
        }
        return parts.joined(separator: " · ")
    }

    private var consentLine: String? {
        guard let expires = connection.item?.consentExpiresAt else { return nil }
        return "Autorização válida até \(expires.formatted(.dateTime.day(.twoDigits).month(.twoDigits).year().locale(.ptBR)))"
    }
}

extension Locale {
    static let ptBR = Locale(identifier: "pt_BR")
}
