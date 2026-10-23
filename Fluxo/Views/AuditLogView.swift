import SwiftUI

/// Mostra exatamente o que saiu do iPhone para o Gemini.
struct AuditLogView: View {
    @EnvironmentObject private var audit: AuditLog
    @State private var confirmClear = false

    var body: some View {
        List {
            if audit.entries.isEmpty {
                Text("Nada foi enviado ao Gemini ainda.")
                    .foregroundStyle(Theme.inkSecondary)
            } else {
                Section {
                    ForEach(audit.entries) { entry in
                        DisclosureGroup {
                            Text(entry.content)
                                .font(.caption.monospaced())
                                .foregroundStyle(Theme.inkSecondary)
                                .textSelection(.enabled)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.kind == .question ? "Sua pergunta" : "Dados de ferramenta")
                                    .font(.subheadline.weight(.medium))
                                Text(entry.date.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(.ptBR)))
                                    .font(.caption)
                                    .foregroundStyle(Theme.inkSecondary)
                            }
                        }
                    }
                } footer: {
                    Text("Os 100 envios mais recentes, guardados cifrados neste iPhone. Confira: não há CPF, número de conta nem nomes de pessoas.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.ground.ignoresSafeArea())
        .navigationTitle("Registro")
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 84) }
        .toolbar {
            if !audit.entries.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button("Apagar") { confirmClear = true }
                }
            }
        }
        .confirmationDialog("Apagar o registro?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Apagar registro", role: .destructive) { audit.clear() }
            Button("Cancelar", role: .cancel) {}
        }
    }
}
