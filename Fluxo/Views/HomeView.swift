import SwiftUI

/// Tela inicial: saldo real das contas (via Meu Pluggy) e atalhos.
/// Transações e orçamentos entram na Parte 3.
struct HomeView: View {
    @EnvironmentObject private var lock: AppLock
    @EnvironmentObject private var store: ConnectionsStore
    @AppStorage(SettingsKey.profileName) private var name = "Marcos"

    let openAgent: () -> Void
    let openSettings: () -> Void

    private var monthLabel: String {
        Date.now
            .formatted(.dateTime.month(.wide).year().locale(.ptBR))
            .uppercased()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                balanceCard
                agentCard
                if !store.isConfigured && store.state == .idle {
                    EmptyStateView(
                        systemName: "building.columns",
                        title: "Conecte seus bancos",
                        message: "Cadastre as credenciais do Meu Pluggy em Ajustes para ver seus saldos aqui.",
                        actionTitle: "Ir para Ajustes",
                        action: openSettings
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .background(Theme.ground.ignoresSafeArea())
        .refreshable { await store.refresh() }
        .task {
            if store.state == .idle { await store.refresh() }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(monthLabel)
                    .tracking(0.4)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.inkTertiary)
                Text("Olá, \(name)")
                    .font(.rounded(.title2, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer()
            Button {
                lock.valuesHidden.toggle()
            } label: {
                Image(systemName: lock.valuesHidden ? "eye.slash" : "eye")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 44, height: 44)
                    .background(Theme.surface, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.line, lineWidth: Theme.hairline))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(lock.valuesHidden ? "Mostrar valores" : "Ocultar valores")
            .sensoryFeedback(.selection, trigger: lock.valuesHidden)
        }
        .padding(.horizontal, 4)
    }

    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Saldo em conta")
                .font(.subheadline)
                .foregroundStyle(Theme.onForestSecondary)
            MoneyText(value: store.bankBalance, font: .rounded(.largeTitle, weight: .bold))
                .foregroundStyle(.white)
            HStack(spacing: 6) {
                if store.state == .loading {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(Theme.onForestSecondary)
                }
                Text(balanceCaption)
            }
            .font(.footnote)
            .foregroundStyle(Theme.onForestSecondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.forest, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var balanceCaption: String {
        switch store.state {
        case .loading:
            return "Atualizando…"
        case .failed(let message):
            return message
        case .loaded:
            var parts: [String] = []
            let accounts = store.bankAccountCount
            parts.append(accounts == 1 ? "1 conta" : "\(accounts) contas")
            if store.cardCount > 0 {
                parts.append(store.cardCount == 1 ? "1 cartão" : "\(store.cardCount) cartões")
            }
            return parts.joined(separator: " · ")
        case .idle:
            return "Nenhum banco conectado ainda"
        }
    }

    private var agentCard: some View {
        Button(action: openAgent) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.lime)
                    .frame(width: 34, height: 34)
                    .background(Theme.ink, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Agente Fluxo")
                        .font(.subheadline.weight(.semibold))
                    Text("Em breve: pergunte sobre seus gastos.")
                        .font(.footnote)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(Theme.ink)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.lime, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
