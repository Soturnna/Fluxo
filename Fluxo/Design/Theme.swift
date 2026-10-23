import SwiftUI

/// Identidade visual do Fluxo em um só lugar.
/// Cada cor tem um papel fixo; nenhuma cor é usada para dois significados.
enum Theme {
    // Fundos e superfícies
    static let ground = Color(hex: 0xF3F4EE)          // fundo das telas
    static let surface = Color.white                    // cartões de conteúdo
    static let line = Color(hex: 0xDFE3D8)              // bordas finas e divisórias
    static let track = Color(hex: 0xE8EBE3)             // trilho de barras e fundos neutros

    // Texto (todos com contraste acima de 4,5:1 sobre o fundo)
    static let ink = Color(hex: 0x101A13)
    static let inkSecondary = Color(hex: 0x4A554D)
    static let inkTertiary = Color(hex: 0x636C65)

    // Marca
    static let forest = Color(hex: 0x142A1C)            // cartões de destaque e bloqueio
    static let onForestSecondary = Color(hex: 0xC9D3CB) // texto secundário sobre o verde-escuro
    static let lime = Color(hex: 0xC8F03C)              // agente e ação principal (sempre com texto escuro)

    // Estados (sempre acompanhados de ícone e texto, nunca só a cor)
    static let positive = Color(hex: 0x1F7A3A)
    static let link = Color(hex: 0x2C6B3F)
    static let warning = Color(hex: 0x7A4A00)
    static let danger = Color(hex: 0xA63A1C)
    static let dangerSoft = Color(hex: 0xFBE4DE)

    // Medidas
    static let cardRadius: CGFloat = 20
    static let hairline: CGFloat = 0.75
}

extension Color {
    /// Cria uma cor a partir de um hexadecimal, por exemplo `Color(hex: 0xC8F03C)`.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

extension Font {
    /// SF Pro Rounded, ligada ao Dynamic Type. Usada em títulos e valores.
    static func rounded(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .rounded, weight: weight)
    }
}

extension View {
    /// Liquid Glass só na camada de navegação (iOS 26+).
    /// Em versões anteriores, ou com "Reduzir transparência", cai para um material padrão.
    @ViewBuilder
    func fluxoGlass<S: Shape>(in shape: S) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
        #else
        self.background(.ultraThinMaterial, in: shape)
        #endif
    }

    /// Cartão branco com borda finíssima: a superfície padrão de conteúdo.
    /// A separação do fundo vem do tom, não de contornos grossos.
    func card(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(Theme.line, lineWidth: Theme.hairline)
            )
    }

    /// Sombra suave das peças flutuantes (barra de abas e botão do agente).
    func floatingShadow() -> some View {
        self.shadow(color: Theme.ink.opacity(0.08), radius: 18, x: 0, y: 6)
    }
}

/// Botão principal: fundo verde-lima com texto escuro.
/// Com "Reduzir movimento" ativo, o toque não encolhe o botão.
struct LimeButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(Theme.ink)
            .background(Theme.lime, in: Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.5)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
