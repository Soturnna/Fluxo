import Foundation

/// Uma alteração que o agente propôs e que só acontece se você confirmar.
struct PendingAction: Identifiable {
    enum Kind {
        case planExpense(PlannedExpense)
        case removePlanned(PlannedExpense)
        case changeCategory(transaction: StoredTransaction, categoryId: String, applyToMerchant: Bool)
        case note(transaction: StoredTransaction, text: String)
        case budget(categoryId: String, limit: Decimal)
        case createCategory(name: String, kind: CategoryKind)
        case provisional(ProvisionalEntry)
    }

    enum Status: Equatable {
        case pending
        case done
        case cancelled
        case failed(String)
    }

    let id = UUID()
    let kind: Kind
    let title: String
    let details: [String]   // linhas mostradas no cartão (com nomes reais, só na tela)
    var status: Status = .pending
}

/// Resultado de uma ferramenta: o que volta para a IA e o que aparece na tela.
struct ToolOutcome {
    var response: [String: Any]
    var activity: String?
    var action: PendingAction?
}

/// As ferramentas do agente.
///
/// LEITURA (executam na hora): resumo do mês, buscar transações, listar
/// categorias, listar gastos previstos.
/// ALTERAÇÃO (viram proposta): prever gasto, remover previsto, trocar categoria,
/// anotar transação, definir orçamento, criar categoria.
///
/// Nenhuma ferramenta mexe no banco: não existe pagamento, transferência nem
/// qualquer chamada de escrita ao Pluggy. E toda alteração local precisa do seu toque.
@MainActor
enum AgentTools {

    // MARK: Declarações enviadas ao Gemini

    static var declarations: [[String: Any]] {
        func string(_ description: String, enumValues: [String]? = nil) -> [String: Any] {
            var schema: [String: Any] = ["type": "STRING", "description": description]
            if let enumValues { schema["enum"] = enumValues }
            return schema
        }
        func number(_ description: String) -> [String: Any] {
            ["type": "NUMBER", "description": description]
        }
        func object(_ properties: [String: Any], required: [String] = []) -> [String: Any] {
            var schema: [String: Any] = ["type": "OBJECT", "properties": properties]
            if !required.isEmpty { schema["required"] = required }
            return schema
        }

        return [
            [
                "name": "resumo_mes",
                "description": "Resumo financeiro de um mês: saldo em conta, gasto total, entradas, gasto por categoria (com participação e orçamentos), maiores gastos, ritmo e projeção do mês, comparação com o mês anterior (inteiro e até o mesmo dia) e histórico de 6 meses.",
                "parameters": object(["mes": string("Mês no formato AAAA-MM. Use o mês atual se o usuário não disser.")], required: ["mes"])
            ],
            [
                "name": "buscar_transacoes",
                "description": "Busca transações reais (já aconteceram) com filtros. Sem datas, procura nos últimos 90 dias.",
                "parameters": object([
                    "texto": string("Trecho do nome da loja, descrição ou pessoa (ex.: iFood, Pessoa 2)."),
                    "categoria": string("Nome de uma categoria existente."),
                    "data_inicio": string("Data inicial AAAA-MM-DD."),
                    "data_fim": string("Data final AAAA-MM-DD."),
                    "tipo": string("Filtrar por direção.", enumValues: ["saida", "entrada", "todas"]),
                    "limite": number("Máximo de resultados (até 50; padrão 25).")
                ])
            ],
            [
                "name": "carteira_investimentos",
                "description": "Investimentos do usuário vindos do Open Finance: total, divisão por tipo e cada aplicação (tipo, taxa, saldo, vencimento, rendimento no último mês).",
                "parameters": object([:])
            ],
            [
                "name": "perfil_investidor",
                "description": "Situação para investir: perfil do questionário, cartão em dia, reserva de emergência (atual e meta de 6 meses de gastos), sobra média mensal e o plano em ordem calculado pelo app. Só totais.",
                "parameters": object([:])
            ],
            [
                "name": "listar_categorias",
                "description": "Lista as categorias existentes e o tipo de cada uma (gasto, renda ou não conta).",
                "parameters": object([:])
            ],
            [
                "name": "listar_gastos_previstos",
                "description": "Lista os gastos futuros já previstos pelo usuário.",
                "parameters": object([:])
            ],
            [
                "name": "prever_gasto",
                "description": "Propõe registrar um gasto futuro (ex.: 'dia 26 vou comprar um tênis de 300'). O usuário confirma no app.",
                "parameters": object([
                    "data": string("Data do gasto AAAA-MM-DD."),
                    "descricao": string("O que será comprado ou pago, curto."),
                    "valor": number("Valor em reais, positivo."),
                    "categoria": string("Nome de uma categoria de gasto existente (opcional).")
                ], required: ["data", "descricao", "valor"])
            ],
            [
                "name": "remover_gasto_previsto",
                "description": "Propõe remover um gasto previsto. O usuário confirma no app.",
                "parameters": object(["ref": string("Referência do previsto, como p1.")], required: ["ref"])
            ],
            [
                "name": "alterar_categoria",
                "description": "Propõe trocar a categoria de uma transação. Opcionalmente cria regra para o estabelecimento. O usuário confirma no app.",
                "parameters": object([
                    "ref": string("Referência da transação, como t3."),
                    "categoria": string("Nome de uma categoria existente."),
                    "aplicar_ao_estabelecimento": ["type": "BOOLEAN", "description": "Se true, vale também para as outras transações do mesmo estabelecimento e as futuras."]
                ], required: ["ref", "categoria"])
            ],
            [
                "name": "anotar_transacao",
                "description": "Propõe salvar uma nota curta numa transação. O usuário confirma no app.",
                "parameters": object([
                    "ref": string("Referência da transação, como t3."),
                    "nota": string("Texto da nota, até 200 caracteres.")
                ], required: ["ref", "nota"])
            ],
            [
                "name": "definir_orcamento",
                "description": "Propõe criar ou alterar o limite mensal de uma categoria de gasto. O usuário confirma no app.",
                "parameters": object([
                    "categoria": string("Nome de uma categoria de gasto existente."),
                    "limite": number("Limite mensal em reais, positivo.")
                ], required: ["categoria", "limite"])
            ],
            [
                "name": "registrar_lancamento",
                "description": "Propõe registrar algo que o usuário acabou de fazer e o banco ainda não mostra (Pix enviado ou recebido, compra, boleto). Fica provisório até o banco confirmar e, se for pela conta, já entra no saldo estimado. O usuário confirma no app.",
                "parameters": object([
                    "data_hora": string("Quando aconteceu, AAAA-MM-DDTHH:MM. Sem hora, use AAAA-MM-DD. Se o usuário não disser, omita (vale agora)."),
                    "descricao": string("O que foi, curto (ex.: Pix enviado, Mercado, Conta de luz)."),
                    "pessoa_ou_loja": string("Quem recebeu ou pagou (opcional). Use os rótulos Pessoa N como estão."),
                    "valor": number("Valor em reais, positivo."),
                    "tipo": string("Direção do dinheiro.", enumValues: ["saida", "entrada"]),
                    "meio": string("Por onde passou: conta (Pix, débito, boleto) ou cartão de crédito.", enumValues: ["conta", "cartao_credito"])
                ], required: ["descricao", "valor", "tipo"])
            ],
            [
                "name": "criar_categoria",
                "description": "Propõe criar uma categoria nova. O usuário confirma no app.",
                "parameters": object([
                    "nome": string("Nome da categoria, até 30 caracteres."),
                    "tipo": string("Papel da categoria.", enumValues: ["gasto", "renda", "nao_conta"])
                ], required: ["nome", "tipo"])
            ]
        ]
    }

    // MARK: Execução

    static func execute(name: String, args: [String: Any], store: FinanceStore, privacy: PrivacyFilter) -> ToolOutcome {
        switch name {
        case "resumo_mes": return monthSummary(args, store, privacy)
        case "buscar_transacoes": return search(args, store, privacy)
        case "listar_categorias": return listCategories(store)
        case "carteira_investimentos": return portfolio(store)
        case "perfil_investidor": return investorProfile(store)
        case "listar_gastos_previstos": return listPlanned(store, privacy)
        case "prever_gasto": return proposePlan(args, store)
        case "remover_gasto_previsto": return proposeRemovePlanned(args, store, privacy)
        case "alterar_categoria": return proposeCategoryChange(args, store, privacy)
        case "anotar_transacao": return proposeNote(args, store, privacy)
        case "definir_orcamento": return proposeBudget(args, store)
        case "criar_categoria": return proposeCategory(args, store)
        case "registrar_lancamento": return proposeProvisional(args, privacy)
        default: return failure("Ferramenta desconhecida.")
        }
    }

    // MARK: Leitura

    private static func monthSummary(_ args: [String: Any], _ store: FinanceStore, _ privacy: PrivacyFilter) -> ToolOutcome {
        guard let month = parseMonth(args["mes"] as? String) else { return failure("Mês inválido. Use AAAA-MM.") }
        let totals = store.totals(inMonthOf: month)
        let spending = store.spendingByCategory(inMonthOf: month)
        let budgets = Dictionary(uniqueKeysWithValues: store.userData.budgets.map { ($0.categoryId, $0.limit) })

        let byCategory: [[String: Any]] = spending
            .sorted { $0.value > $1.value }
            .prefix(12)
            .map { entry in
                var row: [String: Any] = [
                    "categoria": store.category(withId: entry.key)?.name ?? "Outros",
                    "gasto": money(entry.value),
                    "participacao_percentual": percent(entry.value, of: totals.spent)
                ]
                if let limit = budgets[entry.key] {
                    row["orcamento"] = money(limit)
                    row["percentual_usado"] = percent(entry.value, of: limit)
                }
                return row
            }

        let biggest: [[String: Any]] = store.transactions(inMonthOf: month)
            .filter { store.isExpense($0) }
            .sorted { $0.amount < $1.amount }
            .prefix(5)
            .map { transactionRow($0, store, privacy) }

        var response: [String: Any] = [
            "mes": monthString(month),
            "gasto_total": money(totals.spent),
            "entradas": money(totals.income),
            "gastos_previstos_pendentes": money(store.pendingPlannedTotal(inMonthOf: month)),
            "por_categoria": byCategory,
            "maiores_gastos": biggest
        ]
        if let balance = store.bankBalance { response["saldo_em_conta"] = money(balance) }
        if let bankAt = store.bankDataAt {
            // Horário local (São Paulo), escrito por extenso para não haver confusão de fuso.
            response["saldo_buscado_no_banco_em"] = bankAt.formatted(
                .dateTime.day(.twoDigits).month(.twoDigits).year().hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(.ptBR)
            )
        }
        if let limit = store.userData.effectiveMonthlyLimit { response["limite_do_mes"] = money(limit) }

        // O que você registrou e o banco ainda não mostrou.
        let pending = store.pendingProvisionals
        if !pending.isEmpty {
            response["lancamentos_aguardando_banco"] = pending.prefix(10).map { item -> [String: Any] in
                var row: [String: Any] = [
                    "data_hora": dayFormatter("yyyy-MM-dd'T'HH:mm").string(from: item.date),
                    "descricao": privacy.safeText(item.title),
                    "valor": money(item.amount),
                    "meio": item.method == .account ? "conta" : "cartao_credito"
                ]
                if let name = item.counterparty { row["pessoa_ou_loja"] = privacy.safeName(name) }
                return row
            }
        }
        if let estimate = store.estimatedBalance { response["saldo_estimado_agora"] = money(estimate.value) }

        // Cartão de crédito, separado da conta.
        if let card = store.creditCards.first {
            let summary = store.cardSummary(card)
            var cardInfo: [String: Any] = [
                "fatura_atual": money(summary.openBill),
                "proximas_faturas": money(summary.futureBills),
                "total_no_cartao": money(summary.totalUsed),
                "gasto_no_cartao_no_mes": money(store.totals(inMonthOf: month, origin: .card).spent),
                "bloqueado": card.isCardBlocked,
                "dia_de_fechamento": summary.schedule.closeDay
            ]
            if let due = summary.schedule.open?.due { cardInfo["vencimento_fatura_atual"] = dayString(due) }
            if let close = summary.nextClose { cardInfo["fechamento_fatura_atual"] = dayString(close) }
            if let unpaid = summary.schedule.closedUnpaid {
                cardInfo["fatura_fechada_a_pagar"] = ["valor": money(unpaid.total), "vencimento": dayString(unpaid.due)]
            }
            cardInfo["proximas_por_mes"] = summary.schedule.upcoming.prefix(6).map {
                ["vencimento": dayString($0.due), "valor": money($0.total)]
            }
            if let percent = summary.usedPercent { cardInfo["limite_usado_percentual"] = percent }
            if let available = summary.available { cardInfo["limite_disponivel"] = money(available) }
            // Diferença entre o total do banco e a soma das faturas montadas no app.
            if abs(summary.unmatched) >= 1 { cardInfo["diferenca_nao_explicada_nas_faturas"] = money(summary.unmatched) }
            response["cartao_credito"] = cardInfo
        }

        // Projeção do saldo da conta nos próximos 30 dias.
        if FinanceStore.isCurrentMonth(month), let projection = store.projectCashFlow() {
            var info: [String: Any] = [
                "saldo_minimo": money(projection.minBalance),
                "dia_do_minimo": dayString(projection.minDate),
                "saldo_em_30_dias": money(projection.endBalance),
                "fica_negativo": projection.goesNegative
            ]
            if let first = projection.firstNegative { info["primeiro_dia_negativo"] = dayString(first) }
            if let suggestion = projection.suggestion { info["sugestao_do_app"] = privacy.safeText(suggestion) }
            response["projecao_30_dias"] = info
        }

        // Recorrentes confirmados (assinaturas, contas fixas, salário).
        let recurring = store.detectRecurring().filter { !$0.isCandidate }
        if !recurring.isEmpty {
            response["recorrentes"] = recurring.prefix(15).map { item -> [String: Any] in
                var row: [String: Any] = [
                    "nome": privacy.safeTitle(for: item.sample),
                    "valor": money(item.amount),
                    "proxima_data": dayString(item.nextDate),
                    "meio": item.origin == .account ? "conta" : "cartao"
                ]
                if item.varies { row["valor_varia"] = true }
                if let before = item.priceIncrease { row["subiu_de"] = money(-before) }
                return row
            }
        }

        // Ritmo do mês: média por dia e, no mês atual, projeção linear até o fim.
        let calendar = Calendar.current
        let elapsed = max(store.elapsedDays(inMonthOf: month), 1)
        let isCurrent = FinanceStore.isCurrentMonth(month)
        let dailyAverage = totals.spent / Decimal(elapsed)
        response["quantidade_de_gastos"] = store.transactions(inMonthOf: month).filter { store.isExpense($0) }.count
        response["media_por_dia"] = money(dailyAverage)
        if isCurrent {
            response["dias_decorridos"] = elapsed
            response["dias_restantes"] = store.daysLeft(inMonthOf: month)
            response["projecao_linear_fim_do_mes"] = money(dailyAverage * Decimal(FinanceStore.daysInMonth(month)))
        }

        // Comparação com o mês anterior: inteiro e até o mesmo dia (justa no mês em andamento).
        if let previous = calendar.date(byAdding: .month, value: -1, to: month) {
            let previousTotals = store.totals(inMonthOf: previous)
            var comparison: [String: Any] = [
                "mes": monthString(previous),
                "gasto_total": money(previousTotals.spent),
                "entradas": money(previousTotals.income)
            ]
            if isCurrent {
                comparison["gasto_ate_o_mesmo_dia"] = money(store.spent(inMonthOf: previous, upToDay: elapsed))
            }
            response["mes_anterior"] = comparison
        }

        // Histórico curto, só com totais (nenhuma transação individual).
        response["historico_6_meses"] = (0..<6).reversed().compactMap { offset -> [String: Any]? in
            guard let target = calendar.date(byAdding: .month, value: -offset, to: month) else { return nil }
            let monthTotals = store.totals(inMonthOf: target)
            return ["mes": monthString(target), "gastos": money(monthTotals.spent), "entradas": money(monthTotals.income)]
        }

        let label = month.formatted(.dateTime.month(.wide).year().locale(.ptBR))
        return ToolOutcome(response: response, activity: "Consultou o resumo de \(label)")
    }

    private static func search(_ args: [String: Any], _ store: FinanceStore, _ privacy: PrivacyFilter) -> ToolOutcome {
        let calendar = Calendar.current
        let end = parseDay(args["data_fim"] as? String).flatMap { calendar.date(byAdding: .day, value: 1, to: $0) } ?? .distantFuture
        let start = parseDay(args["data_inicio"] as? String)
            ?? calendar.date(byAdding: .day, value: -90, to: .now) ?? .distantPast
        let direction = args["tipo"] as? String ?? "todas"
        let limit = min(max(Int(args["limite"] as? Double ?? 25), 1), 50)

        var categoryId: String?
        if let name = args["categoria"] as? String, !name.isEmpty {
            guard let category = findCategory(named: name, store) else {
                return failure("Categoria não encontrada. Use listar_categorias.")
            }
            categoryId = category.id
        }
        let text = (args["texto"] as? String).map { privacy.resolveAlias($0) } ?? ""

        let results = store.transactions.filter { item in
            guard item.date >= start && item.date < end else { return false }
            if direction == "saida" && item.amount >= 0 { return false }
            if direction == "entrada" && item.amount <= 0 { return false }
            if let categoryId, store.category(for: item).id != categoryId { return false }
            if !text.isEmpty
                && !item.title.localizedStandardContains(text)
                && !item.description.localizedStandardContains(text) { return false }
            return true
        }

        let rows = results.prefix(limit).map { transactionRow($0, store, privacy) }
        let total = results.reduce(Decimal(0)) { $0 + $1.amount }
        return ToolOutcome(
            response: [
                "quantidade_encontrada": results.count,
                "soma_dos_valores": money(total),
                "transacoes": Array(rows),
                "observacao": "Valores negativos são saídas."
            ],
            activity: "Consultou \(results.count) \(results.count == 1 ? "transação" : "transações")"
        )
    }

    private static func investorProfile(_ store: FinanceStore) -> ToolOutcome {
        let readiness = store.investReadiness()
        var response: [String: Any] = [
            "cartao": [
                "situacao": { () -> String in
                    switch readiness.cardState {
                    case .ok: return "em_dia"
                    case .warning: return "fatura_a_pagar"
                    case .pending: return "pendente"
                    case .unknown: return "sem_dados"
                    }
                }(),
                "detalhe": readiness.cardDetail
            ],
            "reserva_atual_renda_fixa": money(readiness.reserveCurrent),
            "reserva_meta_6_meses": money(readiness.reserveTarget),
            "gasto_medio_mensal": money(readiness.averageSpending),
            "carteira_total": money(store.investedTotal),
            "plano_do_app": store.investmentPlan().map { ["passo": $0.title, "detalhe": $0.detail] }
        ]
        if let surplus = readiness.monthlySurplus { response["sobra_media_mensal"] = money(surplus) }
        if let profile = store.userData.investorProfile {
            response["perfil"] = [
                "tipo": profile.label,
                "objetivo": profile.objectiveLabel,
                "prazo": profile.horizonLabel,
                "reacao_a_queda_de_20": InvestorProfile.questions[2].options[min(max(profile.reaction, 0), 2)],
                "experiencia": InvestorProfile.questions[3].options[min(max(profile.experience, 0), 2)]
            ]
        } else {
            response["perfil"] = "nao_respondido"
        }
        return ToolOutcome(response: response, activity: "Consultou sua situação para investir")
    }

    private static func portfolio(_ store: FinanceStore) -> ToolOutcome {
        let items: [[String: Any]] = store.activeInvestments.prefix(30).map { item in
            var row: [String: Any] = [
                "nome": privacy_safe(item.name),
                "tipo": item.kindLabel,
                "saldo": money(item.balance)
            ]
            if let rate = item.rateLabel { row["taxa"] = rate }
            if let due = item.dueDate { row["vencimento"] = dayString(due) }
            if let month = item.lastMonthRate { row["rendimento_ultimo_mes_percentual"] = (month * 100).rounded() / 100 }
            if let year = item.lastTwelveMonthsRate { row["rendimento_12_meses_percentual"] = (year * 100).rounded() / 100 }
            return row
        }
        var response: [String: Any] = [
            "total_investido": money(store.investedTotal),
            "por_tipo": store.investmentAllocation.map { ["tipo": $0.label, "valor": money($0.value)] },
            "aplicacoes_ativas": items,
            "resgatados": store.withdrawnInvestments.count
        ]
        if let profit = store.investmentsLastMonthProfit { response["rendimento_aproximado_ultimo_mes"] = money(profit) }
        return ToolOutcome(response: response, activity: "Consultou seus investimentos")
    }

    /// Nomes de investimentos não têm dados pessoais, mas passam pela mesma
    /// limpeza de números longos e marcações.
    private static func privacy_safe(_ text: String) -> String {
        PrivacyFilter.neutralizeMarkers(PrivacyFilter.maskNumbers(text))
    }

    private static func listCategories(_ store: FinanceStore) -> ToolOutcome {
        let rows = store.allCategories.map { ["nome": $0.name, "tipo": kindCode($0.kind)] }
        return ToolOutcome(response: ["categorias": rows], activity: "Consultou as categorias")
    }

    private static func listPlanned(_ store: FinanceStore, _ privacy: PrivacyFilter) -> ToolOutcome {
        let rows: [[String: Any]] = store.plannedExpenses(fromDaysAgo: 31).map { item in
            [
                "ref": privacy.ref(for: item),
                "data": dayString(item.date),
                "descricao": privacy.safeText(item.title),
                "valor": money(item.amount),
                "categoria": item.categoryId.flatMap { store.category(withId: $0)?.name } ?? "sem categoria"
            ]
        }
        return ToolOutcome(response: ["gastos_previstos": rows], activity: "Consultou os gastos previstos")
    }

    // MARK: Alteração (propostas)

    private static func proposePlan(_ args: [String: Any], _ store: FinanceStore) -> ToolOutcome {
        guard let date = parseDay(args["data"] as? String), FinanceStore.isReasonablePlanDate(date) else {
            return failure("Data inválida. Use AAAA-MM-DD, entre 1 mês atrás e 2 anos à frente.")
        }
        guard let title = FinanceStore.sanitizedName(args["descricao"] as? String ?? "", maxLength: 60) else {
            return failure("Descrição vazia.")
        }
        guard let amount = parseAmount(args["valor"]) else { return failure("Valor inválido.") }

        var categoryId: String?
        if let name = args["categoria"] as? String, !name.isEmpty {
            guard let category = findCategory(named: name, store), category.kind == .expense else {
                return failure("Categoria de gasto não encontrada. Use listar_categorias.")
            }
            categoryId = category.id
        }

        let expense = PlannedExpense(date: date, title: title, amount: amount, categoryId: categoryId, createdByAgent: true)
        var details = [
            title,
            "\(brl(amount)) em \(date.formatted(.dateTime.day().month(.wide).year().locale(.ptBR)))"
        ]
        if let categoryId, let category = store.category(withId: categoryId) { details.append("Categoria: \(category.name)") }
        return proposal(PendingAction(kind: .planExpense(expense), title: "Prever gasto", details: details))
    }

    private static func proposeRemovePlanned(_ args: [String: Any], _ store: FinanceStore, _ privacy: PrivacyFilter) -> ToolOutcome {
        guard let ref = args["ref"] as? String,
              let id = privacy.plannedRefs[ref],
              let expense = store.userData.plannedExpenses.first(where: { $0.id == id })
        else { return failure("Referência de previsto desconhecida. Use listar_gastos_previstos.") }
        let details = [expense.title, "\(brl(expense.amount)) em \(expense.date.formatted(.dateTime.day().month(.wide).locale(.ptBR)))"]
        return proposal(PendingAction(kind: .removePlanned(expense), title: "Remover gasto previsto", details: details))
    }

    private static func proposeCategoryChange(_ args: [String: Any], _ store: FinanceStore, _ privacy: PrivacyFilter) -> ToolOutcome {
        guard let transaction = findTransaction(args["ref"], store, privacy) else {
            return failure("Referência de transação desconhecida. Busque a transação antes.")
        }
        guard let name = args["categoria"] as? String, let category = findCategory(named: name, store) else {
            return failure("Categoria não encontrada. Use listar_categorias.")
        }
        let applyToMerchant = args["aplicar_ao_estabelecimento"] as? Bool ?? false
        var details = [
            "\(transaction.title) · \(brl(abs(transaction.amount)))",
            "De \(store.category(for: transaction).name) para \(category.name)"
        ]
        if applyToMerchant { details.append("Vale também para as outras de “\(transaction.title)” e as próximas") }
        return proposal(PendingAction(
            kind: .changeCategory(transaction: transaction, categoryId: category.id, applyToMerchant: applyToMerchant),
            title: "Trocar categoria",
            details: details
        ))
    }

    private static func proposeNote(_ args: [String: Any], _ store: FinanceStore, _ privacy: PrivacyFilter) -> ToolOutcome {
        guard let transaction = findTransaction(args["ref"], store, privacy) else {
            return failure("Referência de transação desconhecida. Busque a transação antes.")
        }
        guard let text = FinanceStore.sanitizedName(args["nota"] as? String ?? "", maxLength: 200) else {
            return failure("Nota vazia.")
        }
        let shown = privacy.reveal(text)
        return proposal(PendingAction(
            kind: .note(transaction: transaction, text: shown),
            title: "Anotar transação",
            details: ["\(transaction.title) · \(brl(abs(transaction.amount)))", "“\(shown)”"]
        ))
    }

    private static func proposeBudget(_ args: [String: Any], _ store: FinanceStore) -> ToolOutcome {
        guard let name = args["categoria"] as? String,
              let category = findCategory(named: name, store), category.kind == .expense
        else { return failure("Categoria de gasto não encontrada. Use listar_categorias.") }
        guard let limit = parseAmount(args["limite"]) else { return failure("Limite inválido.") }
        let current = store.userData.budgets.first { $0.categoryId == category.id }?.limit
        var details = ["\(category.name): \(brl(limit)) por mês"]
        if let current { details.append("Antes: \(brl(current))") }
        return proposal(PendingAction(kind: .budget(categoryId: category.id, limit: limit), title: "Definir orçamento", details: details))
    }

    private static func proposeCategory(_ args: [String: Any], _ store: FinanceStore) -> ToolOutcome {
        guard let name = FinanceStore.sanitizedName(args["nome"] as? String ?? "") else { return failure("Nome vazio.") }
        guard store.isNameAvailable(name, excluding: nil) else { return failure("Já existe uma categoria com esse nome.") }
        let kind: CategoryKind
        switch args["tipo"] as? String {
        case "renda": kind = .income
        case "nao_conta": kind = .transfer
        default: kind = .expense
        }
        return proposal(PendingAction(kind: .createCategory(name: name, kind: kind), title: "Criar categoria", details: ["\(name) · \(kind.label)"]))
    }

    private static func proposeProvisional(_ args: [String: Any], _ privacy: PrivacyFilter) -> ToolOutcome {
        guard let amount = parseAmount(args["valor"]) else { return failure("Valor inválido.") }
        guard let title = FinanceStore.sanitizedName(privacy.reveal(args["descricao"] as? String ?? ""), maxLength: 60) else {
            return failure("Descrição vazia.")
        }
        var date = Date.now
        if let text = args["data_hora"] as? String, !text.isEmpty {
            // Só o dia: se for hoje, vale agora; senão, meio-dia daquele dia.
            let dayOnly = parseDay(text).map { Calendar.current.isDateInToday($0) ? Date.now : $0.addingTimeInterval(12 * 3600) }
            guard let parsed = parseDateTime(text) ?? dayOnly, FinanceStore.isReasonableProvisionalDate(parsed) else {
                return failure("Data inválida. Use AAAA-MM-DDTHH:MM, de até 60 dias atrás.")
            }
            date = parsed
        }
        let counterparty = (args["pessoa_ou_loja"] as? String).map { privacy.reveal(privacy.resolveAlias($0)) }
            .flatMap { FinanceStore.sanitizedName($0, maxLength: 60) }
        let isIncome = (args["tipo"] as? String) == "entrada"
        let method: ProvisionalEntry.Method = (args["meio"] as? String) == "cartao_credito" ? .creditCard : .account

        let entry = ProvisionalEntry(date: date, title: title, counterparty: counterparty,
                                     amount: isIncome ? amount : -amount, method: method, source: .agent)
        let when = FinanceStore.bankTimeLabel(date)
        return proposal(PendingAction(
            kind: .provisional(entry),
            title: "Registrar lançamento",
            details: [
                entry.displayTitle,
                "\(isIncome ? "+" : "−")\(brl(amount)) · \(when) · \(method.label)",
                "Fica aguardando o banco confirmar"
            ]
        ))
    }

    static func parseDateTime(_ text: String) -> Date? {
        dayFormatter("yyyy-MM-dd'T'HH:mm").date(from: String(text.prefix(16)))
    }

    // MARK: Executar uma proposta confirmada

    /// Chamado só quando você toca em "Confirmar". Valida tudo de novo, porque
    /// os dados podem ter mudado entre a proposta e a confirmação.
    static func apply(_ action: PendingAction, store: FinanceStore) -> PendingAction.Status {
        switch action.kind {
        case .planExpense(let expense):
            return store.savePlannedExpense(expense) ? .done : .failed("Dados inválidos.")
        case .removePlanned(let expense):
            store.deletePlannedExpense(id: expense.id)
            return .done
        case .changeCategory(let transaction, let categoryId, let applyToMerchant):
            guard store.category(withId: categoryId) != nil else { return .failed("A categoria não existe mais.") }
            store.assignCategory(categoryId, to: transaction, applyToSameTitle: applyToMerchant)
            return .done
        case .note(let transaction, let text):
            store.setNote(text, for: transaction.id)
            return .done
        case .budget(let categoryId, let limit):
            guard store.category(withId: categoryId)?.kind == .expense else { return .failed("A categoria não é de gasto.") }
            store.setBudget(categoryId: categoryId, limit: limit)
            return .done
        case .createCategory(let name, let kind):
            return store.createCategory(name: name, icon: "ellipsis", kind: kind) == nil ? .failed("Nome já usado.") : .done
        case .provisional(let entry):
            return store.saveProvisional(entry) ? .done : .failed("Dados inválidos.")
        }
    }

    // MARK: Apoio

    private static func proposal(_ action: PendingAction) -> ToolOutcome {
        ToolOutcome(
            response: [
                "status": "proposta_exibida",
                "mensagem": "A proposta foi mostrada ao usuário e só será aplicada se ele tocar em Confirmar no app. Não diga que já foi feito."
            ],
            action: action
        )
    }

    private static func failure(_ message: String) -> ToolOutcome {
        ToolOutcome(response: ["erro": message])
    }

    private static func transactionRow(_ item: StoredTransaction, _ store: FinanceStore, _ privacy: PrivacyFilter) -> [String: Any] {
        var row: [String: Any] = [
            "ref": privacy.ref(for: item),
            "data": dayString(item.date),
            "descricao": privacy.safeTitle(for: item),
            "valor": money(item.amount),
            "categoria": store.category(for: item).name
        ]
        if item.isPending { row["pendente"] = true }
        if let installment = item.installment { row["parcela"] = installment }
        if let note = store.note(for: item) { row["nota"] = privacy.safeText(note) }
        return row
    }

    private static func findTransaction(_ ref: Any?, _ store: FinanceStore, _ privacy: PrivacyFilter) -> StoredTransaction? {
        guard let ref = ref as? String, let id = privacy.transactionRefs[ref] else { return nil }
        return store.transactions.first { $0.id == id }
    }

    private static func findCategory(named name: String, _ store: FinanceStore) -> Category? {
        let key = FinanceStore.ruleKey(name)
        return store.allCategories.first { FinanceStore.ruleKey($0.name) == key }
    }

    private static func parseAmount(_ value: Any?) -> Decimal? {
        let number: Double?
        if let double = value as? Double { number = double }
        else if let int = value as? Int { number = Double(int) }
        else { number = nil }
        guard let number, number.isFinite, number > 0, number < 10_000_000 else { return nil }
        return Money.decimal(from: number)
    }

    private static func dayFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = format
        return formatter
    }

    static func parseDay(_ text: String?) -> Date? {
        guard let text else { return nil }
        return dayFormatter("yyyy-MM-dd").date(from: text)
    }

    static func parseMonth(_ text: String?) -> Date? {
        guard let text else { return nil }
        return dayFormatter("yyyy-MM").date(from: text)
    }

    static func dayString(_ date: Date) -> String {
        dayFormatter("yyyy-MM-dd").string(from: date)
    }

    static func monthString(_ date: Date) -> String {
        dayFormatter("yyyy-MM").string(from: date)
    }

    /// Dinheiro vai como número com 2 casas (ex.: -58.9), nunca como texto formatado.
    private static func money(_ value: Decimal) -> Double {
        ((value as NSDecimalNumber).doubleValue * 100).rounded() / 100
    }

    private static func percent(_ value: Decimal, of limit: Decimal) -> Int {
        guard limit > 0 else { return 0 }
        return Int(((value as NSDecimalNumber).doubleValue / (limit as NSDecimalNumber).doubleValue * 100).rounded())
    }

    private static func kindCode(_ kind: CategoryKind) -> String {
        switch kind {
        case .expense: return "gasto"
        case .income: return "renda"
        case .transfer: return "nao_conta"
        }
    }

    static func brl(_ value: Decimal) -> String {
        value.formatted(.currency(code: "BRL").locale(.ptBR))
    }
}
