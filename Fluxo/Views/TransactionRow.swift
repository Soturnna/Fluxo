import SwiftUI

/// Valor com sinal (−R$ 58,90 / +R$ 150,00) que respeita o botão de ocultar valores.
struct SignedMoneyText: View {
    @EnvironmentObject private var lock: AppLock
    let amount: Decimal
    var muted = false

    var body: some View {
        Text(display)
            .font(.rounded(.subheadline, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
            .accessibilityLabel(lock.valuesHidden ? "Valor oculto" : spoken)
    }

    private var formatted: String {
        abs(amount).formatted(.currency(code: "BRL").locale(.ptBR))
    }

    private var display: String {
        if lock.valuesHidden { return "R$ ••••" }
        if muted { return formatted }
        return amount < 0 ? "−\(formatted)" : "+\(formatted)"
    }

    private var spoken: String {
        amount < 0 ? "saída de \(formatted)" : "entrada de \(formatted)"
    }

    private var color: Color {
        if muted || lock.valuesHidden { return Theme.inkSecondary }
        return amount < 0 ? Theme.ink : Theme.positive
    }
}

/// Uma linha de transação: ícone da categoria, título, detalhes e valor.
struct TransactionRow: View {
    let transaction: StoredTransaction
    let accountName: String?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            IconTile(
                systemName: transaction.group.icon,
                style: transaction.isInternalMovement ? .neutral : .security,
                size: 36
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(transaction.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(transaction.isInternalMovement ? Theme.inkSecondary : Theme.ink)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
                if hasBadges {
                    HStack(spacing: 6) {
                        if transaction.isPending {
                            Pill(text: "Pendente", icon: "clock", tint: Theme.warning)
                        }
                        if let installment = transaction.installment {
                            Pill(text: "Parcela \(installment)", icon: "square.stack", tint: Theme.inkSecondary)
                        }
                        if transaction.isInternalMovement {
                            Pill(text: "Não conta nos gastos", icon: "arrow.left.arrow.right", tint: Theme.inkSecondary)
                        }
                    }
                }
            }

            Spacer(minLength: 8)

            SignedMoneyText(amount: transaction.amount, muted: transaction.isInternalMovement)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        var parts = [transaction.group.label]
        if let accountName { parts.append(accountName) }
        return parts.joined(separator: " · ")
    }

    private var hasBadges: Bool {
        transaction.isPending || transaction.installment != nil || transaction.isInternalMovement
    }
}

/// Etiqueta pequena com ícone e texto (nunca só cor).
struct Pill: View {
    let text: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .imageScale(.small)
            Text(text)
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(Theme.track, in: Capsule())
        .lineLimit(1)
    }
}

/// Agrupa transações por dia, do mais recente para o mais antigo.
struct DaySection: Identifiable {
    let day: Date
    let items: [StoredTransaction]
    var id: Date { day }

    var title: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Hoje" }
        if calendar.isDateInYesterday(day) { return "Ontem" }
        return day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).locale(.ptBR))
    }

    static func make(from transactions: [StoredTransaction]) -> [DaySection] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: transactions) { calendar.startOfDay(for: $0.date) }
        return grouped
            .map { DaySection(day: $0.key, items: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.day > $1.day }
    }
}
