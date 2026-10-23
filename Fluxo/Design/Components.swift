import SwiftUI

/// As duas ondas do símbolo do Fluxo, desenhadas como forma vetorial.
/// Mesmo traçado do ícone (design/icon.svg), em proporções de 0 a 1.
struct FlowMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height

        func wave(atY y: CGFloat) {
            let start = CGPoint(x: rect.minX + w * 0.192, y: y)
            let middle = CGPoint(x: rect.minX + w * 0.5, y: y)
            let end = CGPoint(x: rect.minX + w * 0.808, y: y)
            let dx = w * 0.103, dy = h * 0.117
            path.move(to: start)
            path.addCurve(to: middle,
                          control1: CGPoint(x: start.x + dx, y: y - dy),
                          control2: CGPoint(x: middle.x - dx, y: y - dy))
            path.addCurve(to: end,
                          control1: CGPoint(x: middle.x + dx, y: y + dy),
                          control2: CGPoint(x: end.x - dx, y: y + dy))
        }

        wave(atY: rect.minY + h * 0.40)
        wave(atY: rect.minY + h * 0.64)
        return path
    }
}

/// O símbolo do app: ondas escuras sobre um quadrado verde-lima.
struct AppMark: View {
    var size: CGFloat = 88

    var body: some View {
        FlowMark()
            .stroke(Theme.ink, style: StrokeStyle(lineWidth: size * 0.075, lineCap: .round, lineJoin: .round))
            .frame(width: size * 0.62, height: size * 0.62)
            .frame(width: size, height: size)
            .background(Theme.lime, in: RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Ícone em um quadrado suave, no estilo dos Ajustes do iOS.
/// Fundo claro e traço médio: leve, sem blocos escuros pesando a lista.
struct IconTile: View {
    enum Style {
        case security   // verde da marca
        case agent      // verde-lima do agente
        case neutral    // cinza
        case danger     // vermelho

        var background: Color {
            switch self {
            case .security: return Theme.forest.opacity(0.08)
            case .agent: return Theme.lime.opacity(0.55)
            case .neutral: return Theme.track
            case .danger: return Theme.dangerSoft
            }
        }

        var foreground: Color {
            switch self {
            case .security: return Theme.forest
            case .agent: return Theme.ink
            case .neutral: return Theme.inkSecondary
            case .danger: return Theme.danger
            }
        }
    }

    let systemName: String
    var style: Style = .security
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.5, weight: .medium))
            .foregroundStyle(style.foreground)
            .frame(width: size, height: size)
            .background(style.background, in: RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Rótulo padrão de uma linha de ajuste: ícone, título e, se houver, um detalhe.
struct SettingLabel: View {
    let title: String
    var detail: String? = nil
    let icon: String
    var style: IconTile.Style = .security

    var body: some View {
        HStack(spacing: 12) {
            IconTile(systemName: icon, style: style)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .foregroundStyle(style == .danger ? Theme.danger : Theme.ink)
                if let detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
        }
    }
}

/// Selo de situação discreto: ícone pequeno + texto curto, sempre em uma linha.
struct StatusBadge: View {
    let text: String
    let icon: String
    var color: Color = Theme.inkSecondary

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .imageScale(.small)
            Text(text)
        }
        .font(.footnote)
        .foregroundStyle(color)
        .lineLimit(1)
        .fixedSize()
    }
}

/// Estado vazio: explica o que vai aparecer ali e, se houver, o próximo passo.
struct EmptyStateView: View {
    let systemName: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemName)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Theme.forest)
                .frame(width: 52, height: 52)
                .background(Theme.lime.opacity(0.55), in: Circle())
                .accessibilityHidden(true)
                .padding(.bottom, 2)
            Text(title)
                .font(.rounded(.headline, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(LimeButtonStyle())
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .card(padding: 22)
    }
}

/// Valor em reais que respeita o botão de ocultar valores.
/// O VoiceOver também não lê o número quando ele está oculto.
struct MoneyText: View {
    @EnvironmentObject private var lock: AppLock
    let value: Decimal?
    var font: Font = .rounded(.largeTitle, weight: .bold)

    var body: some View {
        Text(display)
            .font(font)
            .monospacedDigit()
            .contentTransition(.numericText())
            .accessibilityLabel(lock.valuesHidden ? "Valor oculto" : display)
    }

    private var display: String {
        if lock.valuesHidden { return "R$ ••••" }
        guard let value else { return "R$ —" }
        return value.formatted(.currency(code: "BRL").locale(Locale(identifier: "pt_BR")))
    }
}

/// Estrutura comum das telas principais: título grande e espaço para a barra flutuante.
struct Screen<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.rounded(.largeTitle, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 4)
                    .accessibilityAddTraits(.isHeader)
                content
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .background(Theme.ground.ignoresSafeArea())
    }
}
