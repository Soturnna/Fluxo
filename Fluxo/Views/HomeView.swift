import SwiftUI

/// Tela inicial. Nesta parte ainda não há dados: os blocos mostram o estado vazio.
struct HomeView: View {
    @EnvironmentObject private var lock: AppLock
    @AppStorage(SettingsKey.profileName) private var name = "Marcos"

    let openAgent: () -> Void
    let openSettings: () -> Void

    private var monthLabel: String {
        Date.now
            .formatted(.dateTime.month(.wide).year().locale(Locale(identifier: "pt_BR")))
            .uppercased()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                balanceCard
                agentCard
                EmptyStateView(
                    systemName: "building.columns",
                    title: "Conecte seus bancos",
                    message: "Cadastre as credenciais do Meu Pluggy em Ajustes. Na próxima etapa, contas e transações aparecem aqui.",
                    actionTitle: "Ir para Ajustes",
                    action: openSettings
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .background(Theme.ground.ignoresSafeArea())
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(monthLabel)
                    .tracking(0.5)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.inkTertiary)
                Text("Olá, \(name)")
                    .font(.rounded(.title, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer()
            Button {
                lock.valuesHidden.toggle()
            } label: {
                Image(systemName: lock.valuesHidden ? "eye.slash" : "eye")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 44, height: 44)
                    .background(Theme.surface, in: Circle())
                    .overlay(Circle().stroke(Theme.line, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(lock.valuesHidden ? "Mostrar valores" : "Ocultar valores")
            .sensoryFeedback(.selection, trigger: lock.valuesHidden)
        }
        .padding(.horizontal, 4)
    }

    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Saldo consolidado")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.onForestSecondary)
            MoneyText(value: nil, font: .rounded(.largeTitle, weight: .heavy))
                .foregroundStyle(.white)
            Label("Nenhum banco conectado ainda", systemImage: "link.badge.plus")
                .font(.footnote)
                .foregroundStyle(Theme.onForestSecondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.forest, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var agentCard: some View {
        Button(action: openAgent) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.lime)
                    .frame(width: 36, height: 36)
                    .background(Theme.ink, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("AGENTE FLUXO")
                        .tracking(0.6)
                        .font(.caption.weight(.bold))
                    Text("Em breve: pergunte sobre seus gastos em linguagem natural.")
                        .font(.subheadline.weight(.medium))
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.ink)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.lime, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
