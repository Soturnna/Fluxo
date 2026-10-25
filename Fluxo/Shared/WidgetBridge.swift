import Foundation
import WidgetKit

/// Lado do app: grava o resumo do widget e pede para o iOS redesenhá-lo.
@MainActor
enum WidgetBridge {
    /// Último resultado, para o diagnóstico em Ajustes.
    private(set) static var lastGroup: String?
    private(set) static var lastAttemptAt: Date?

    /// ETAPA 1: só o horário (nenhum dado financeiro).
    static func refreshTest() {
        lastAttemptAt = .now
        lastGroup = WidgetShared.write(.init(updatedAt: .now, note: "Teste"))
        WidgetCenter.shared.reloadAllTimelines()
    }
}
