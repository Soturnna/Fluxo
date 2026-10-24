import SwiftUI

/// Investimentos › Explorar: antes de investir, perfil, plano, mercado e simulador.
///
/// O plano é calculado no iPhone, por regras em ordem de prioridade. O agente
/// entra para conversar sobre ele; recebe só totais, nunca transações.
/// Nada aqui é recomendação de compra de um ativo específico.
struct InvestExploreView: View {
    @EnvironmentObject private var store: FinanceStore
    @EnvironmentObject private var lock: AppLock
    let askAgent: (String) -> Void
    let openSettings: () -> Void

    @State private var showQuiz = false
    @State private var listing: BrapiClient.Listing = .gainers
    @State private var quotes: [MarketQuote] = []
    @State private var marketError: String?
    @State private var loadingMarket = false
    @State private var monthly: Double = 100
    @State private var rate: Double = 10

    private static let market = BrapiClient()

    var body: some View {
        let readiness = store.investReadiness()
        VStack(alignment: .leading, spacing: 12) {
            readinessCard(readiness)
            profileCard
            planCard
            marketSection
            simulatorCard
            Text("Informação educativa, não é recomendação de investimento. O agente explica e compara; a decisão é sua.")
                .font(.caption)
                .foregroundStyle(Theme.inkTertiary)
                .padding(.horizontal, 4)
        }
        .sheet(isPresented: $showQuiz) {
            InvestorQuizSheet()
                .environmentObject(store)
        }
        .task(id: listing) { await loadMarket() }
    }

    // MARK: Antes de investir

    private func readinessCard(_ r: FinanceStore.InvestReadiness) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Antes de investir")
                    .font(.callout.weight(.semibold))
                Text("Calculado com os seus dados, aqui no iPhone")
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
            }

            checkRow(state: r.cardState, title: "Cartão em dia", detail: r.cardDetail)

            HStack(alignment: .top, spacing: 10) {
                stateIcon(r.reserveDone ? .ok : (r.reserveTarget > 0 ? .warning : .unknown))
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Text("Reserva de emergência").font(.subheadline.weight(.semibold))
                        if r.reserveTarget > 0 {
                            Text("· \(Int((r.reserveFraction * 100).rounded()))%")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(r.reserveDone ? Theme.positive : Theme.warning)
                        }
                    }
                    if r.reserveTarget > 0 {
                        ProgressBar(fraction: r.reserveFraction, fill: r.reserveDone ? Theme.positive : Theme.warning,
                                    track: Theme.track, height: 8)
                        HStack(spacing: 4) {
                            MoneyText(value: r.reserveCurrent, font: .footnote)
                            Text("de")
                            MoneyText(value: r.reserveTarget, font: .footnote)
                            Text("(6 meses dos seus gastos)")
                        }
                        .font(.footnote)
                        .foregroundStyle(Theme.inkSecondary)
                    } else {
                        Text("Ainda sem meses completos para calcular.")
                            .font(.footnote)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }
            }

            if let surplus = r.monthlySurplus {
                HStack(alignment: .top, spacing: 10) {
                    stateIcon(surplus > 0 ? .ok : .pending)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sobra no mês").font(.subheadline.weight(.semibold))
                        HStack(spacing: 4) {
                            Text("Média dos últimos 3 meses:")
                            SignedMoneyText(amount: surplus, font: .footnote.weight(.semibold))
                        }
                        .font(.footnote)
                        .foregroundStyle(Theme.inkSecondary)
                    }
                }
            }
        }
        .card(padding: 16)
    }

    private func checkRow(state: FinanceStore.InvestReadiness.State, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            stateIcon(state)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func stateIcon(_ state: FinanceStore.InvestReadiness.State) -> some View {
        let (icon, color): (String, Color) = {
            switch state {
            case .ok: return ("checkmark", Theme.positive)
            case .warning: return ("minus", Theme.warning)
            case .pending: return ("xmark", Theme.danger)
            case .unknown: return ("questionmark", Theme.inkSecondary)
            }
        }()
        return Image(systemName: icon)
            .font(.caption.weight(.bold))
            .foregroundStyle(color)
            .frame(width: 24, height: 24)
            .background(color.opacity(0.12), in: Circle())
            .accessibilityHidden(true)
    }

    // MARK: Perfil

    private var profileCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Seu perfil de investidor")
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
                if let profile = store.userData.investorProfile {
                    Text(profile.label).font(.callout.weight(.semibold))
                    Text("Objetivo: \(profile.objectiveLabel.lowercased()) · Prazo: \(profile.horizonLabel.lowercased())")
                        .font(.caption)
                        .foregroundStyle(Theme.inkSecondary)
                } else {
                    Text("Ainda não definido").font(.callout.weight(.semibold))
                    Text("4 perguntas rápidas, guardadas só no iPhone")
                        .font(.caption)
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            Spacer()
            Button(store.userData.investorProfile == nil ? "Responder" : "Refazer") { showQuiz = true }
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
        }
        .card(padding: 16)
    }

    // MARK: Plano

    private var planCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.lime)
                    .frame(width: 30, height: 30)
                    .background(Theme.ink, in: Circle())
                    .accessibilityHidden(true)
                Text("Seu plano, em ordem")
                    .font(.callout.weight(.semibold))
            }
            ForEach(Array(store.investmentPlan().enumerated()), id: \.element.id) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.caption.weight(.bold))
                        .frame(width: 22, height: 22)
                        .background(Theme.lime.opacity(0.6), in: Circle())
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 5 }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.title).font(.subheadline.weight(.semibold))
                        Text(lock.valuesHidden ? "Toque no olho do Início para ver os valores." : step.detail)
                            .font(.footnote)
                            .foregroundStyle(Theme.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Button {
                askAgent("Monte comigo um plano de investimento para o meu perfil e a minha situação atual. Use perfil_investidor e explique cada passo e os riscos.")
            } label: {
                Text("Conversar com o agente sobre o plano")
                    .frame(maxWidth: .infinity, minHeight: 46)
            }
            .buttonStyle(LimeButtonStyle())
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(Theme.lime, lineWidth: 1.5)
        )
    }

    // MARK: Mercado

    private var marketSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Mercado agora").font(.headline)
                Spacer()
                Text("atraso de até 30 min")
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
            }
            .padding(.horizontal, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(BrapiClient.Listing.allCases) { option in
                        Button { listing = option } label: {
                            Text(option.label)
                                .font(.footnote.weight(listing == option ? .semibold : .medium))
                                .foregroundStyle(listing == option ? .white : Theme.ink)
                                .padding(.horizontal, 12)
                                .frame(minHeight: 36)
                                .background(listing == option ? Theme.forest : Theme.surface, in: Capsule())
                                .overlay(Capsule().strokeBorder(Theme.line, lineWidth: listing == option ? 0 : Theme.hairline))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !BrapiClient.hasToken {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Para ver cotações, cadastre a chave gratuita do brapi.dev (plano Free). Só códigos de ativos saem do iPhone.")
                        .font(.footnote)
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Cadastrar chave", action: openSettings)
                        .font(.subheadline.weight(.semibold))
                }
                .card(padding: 16)
            } else if let marketError {
                Label(marketError, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(Theme.warning)
                    .card(padding: 14)
            } else if loadingMarket && quotes.isEmpty {
                ProgressView().frame(maxWidth: .infinity, minHeight: 80)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(quotes.enumerated()), id: \.element.id) { index, quote in
                        if index > 0 { Divider().overlay(Theme.line) }
                        Button { askAgent(prompt(for: quote)) } label: { QuoteRow(quote: quote) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                        .strokeBorder(Theme.line, lineWidth: Theme.hairline)
                )
                Text("Toque num ativo para o agente explicar o que ele é, os riscos e se combina com o seu perfil.")
                    .font(.caption)
                    .foregroundStyle(Theme.inkTertiary)
                    .padding(.horizontal, 4)
            }
        }
    }

    private func prompt(for quote: MarketQuote) -> String {
        var data = "\(quote.ticker) (\(quote.name), \(quote.kindLabel)"
        if let sector = quote.sector { data += ", setor \(sector)" }
        data += ")"
        if let price = quote.price { data += ", preço \(ChartFormat.brl(price))" }
        if let change = quote.changePercent {
            data += ", variação hoje \(change.formatted(.number.precision(.fractionLength(2)).locale(.ptBR)))%"
        }
        return "Me explique o ativo \(data), segundo o brapi. O que ele é, como costuma render, quais os riscos e se combina com o meu perfil (use perfil_investidor). Sem recomendar compra."
    }

    @MainActor
    private func loadMarket() async {
        guard BrapiClient.hasToken else { return }
        loadingMarket = true
        marketError = nil
        defer { loadingMarket = false }
        do {
            quotes = try await Self.market.list(listing)
        } catch is CancellationError {
            return
        } catch {
            quotes = []
            marketError = (error as? LocalizedError)?.errorDescription ?? "Não foi possível carregar o mercado."
        }
    }

    // MARK: Simulador

    private var simulatorCard: some View {
        let r = pow(1 + rate / 100, 1.0 / 12) - 1
        let total = r > 0 ? monthly * ((pow(1 + r, 12) - 1) / r) : monthly * 12
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Simulador de renda mensal").font(.callout.weight(.semibold))
                Text("Uma conta, não uma promessa: o rendimento real varia")
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
            }
            stepper("Aporte por mês", value: ChartFormat.brl(monthly),
                    minus: { monthly = max(10, monthly - 10) }, plus: { monthly = min(10_000, monthly + 10) })
            stepper("Rendimento ao ano", value: "\(Int(rate))%",
                    minus: { rate = max(1, rate - 1) }, plus: { rate = min(30, rate + 1) })
            HStack(spacing: 8) {
                result("Em 12 meses, acumulado", ChartFormat.brl(total), color: Theme.ink)
                result("Renda por mês, depois", ChartFormat.brl(total * r), color: Theme.positive)
            }
        }
        .card(padding: 16)
    }

    private func stepper(_ title: String, value: String, minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Text(title).font(.subheadline)
            Spacer()
            Button(action: minus) { Image(systemName: "minus").frame(width: 44, height: 44) }
                .background(Theme.ground, in: Circle())
                .accessibilityLabel("Diminuir \(title.lowercased())")
            Text(value)
                .font(.callout.weight(.semibold).monospacedDigit())
                .frame(minWidth: 84)
            Button(action: plus) { Image(systemName: "plus").frame(width: 44, height: 44) }
                .background(Theme.ground, in: Circle())
                .accessibilityLabel("Aumentar \(title.lowercased())")
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.ink)
    }

    private func result(_ title: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(Theme.inkSecondary)
            Text(value).font(.rounded(.title3, weight: .bold)).foregroundStyle(color)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.ground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct QuoteRow: View {
    let quote: MarketQuote

    var body: some View {
        HStack(spacing: 12) {
            Text(String(quote.ticker.prefix(4)))
                .font(.caption2.weight(.bold))
                .foregroundStyle(Theme.inkSecondary)
                .frame(width: 44, height: 36)
                .background(Theme.track, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(quote.ticker).font(.subheadline.weight(.semibold))
                HStack(spacing: 6) {
                    Text(quote.paysMonthly ? "FII · renda mensal" : quote.kindLabel)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.link)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Theme.link.opacity(0.10), in: Capsule())
                    Text(quote.name)
                        .font(.caption)
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 2) {
                if let price = quote.price {
                    Text(ChartFormat.brl(price)).font(.subheadline.weight(.semibold))
                }
                if let change = quote.changePercent {
                    Text("\(change >= 0 ? "▲" : "▼") \(abs(change).formatted(.number.precision(.fractionLength(2)).locale(.ptBR)))%")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(change >= 0 ? Theme.positive : Theme.danger)
                }
            }
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Pede ao agente uma explicação sobre este ativo")
    }
}

/// Questionário de perfil (4 perguntas). As respostas ficam no cofre.
struct InvestorQuizSheet: View {
    @EnvironmentObject private var store: FinanceStore
    @Environment(\.dismiss) private var dismiss
    @State private var answers: [Int] = [-1, -1, -1, -1]

    var body: some View {
        NavigationStack {
            Form {
                ForEach(Array(InvestorProfile.questions.enumerated()), id: \.offset) { index, question in
                    Section(question.title) {
                        ForEach(Array(question.options.enumerated()), id: \.offset) { optionIndex, option in
                            Button {
                                answers[index] = optionIndex
                            } label: {
                                HStack {
                                    Text(option).foregroundStyle(Theme.ink)
                                    Spacer()
                                    if answers[index] == optionIndex {
                                        Image(systemName: "checkmark").foregroundStyle(Theme.link)
                                    }
                                }
                            }
                        }
                    }
                }
                Section {
                } footer: {
                    Text("Serve para o plano e o agente ajustarem as sugestões. Fica só no iPhone, no cofre cifrado.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.ground.ignoresSafeArea())
            .navigationTitle("Perfil de investidor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") {
                        store.saveInvestorProfile(InvestorProfile(objective: answers[0], horizon: answers[1],
                                                                  reaction: answers[2], experience: answers[3]))
                        dismiss()
                    }
                    .disabled(answers.contains(-1))
                }
            }
            .onAppear {
                if let saved = store.userData.investorProfile { answers = saved.answers }
            }
        }
    }
}
