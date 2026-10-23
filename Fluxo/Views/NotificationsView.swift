import SwiftUI
import UIKit
import UserNotifications

/// Ajustes › Notificações.
///
/// Segue a regra do app: ligar uma proteção é livre; afrouxar pede Face ID.
/// Aqui, "afrouxar" é passar a mostrar valores nas notificações.
struct NotificationsView: View {
    @EnvironmentObject private var lock: AppLock
    @EnvironmentObject private var finance: FinanceStore

    @AppStorage(SettingsKey.notifyEnabled) private var enabled = false
    @AppStorage(SettingsKey.notifyBudgets) private var budgets = true
    @AppStorage(SettingsKey.notifyPlanned) private var planned = true
    @AppStorage(SettingsKey.notifyLarge) private var large = true
    @AppStorage(SettingsKey.notifyLargeThreshold) private var thresholdRaw = 200.0
    @AppStorage(SettingsKey.notifyWeekly) private var weekly = true
    @AppStorage(SettingsKey.notifyConnection) private var connection = true
    @AppStorage(SettingsKey.notifyShowValues) private var showValues = true

    @State private var status: UNAuthorizationStatus = .notDetermined
    @State private var backgroundAllowed = true
    @State private var threshold: Decimal = 200
    @State private var testSent = false

    private var authorized: Bool {
        status == .authorized || status == .provisional || status == .ephemeral
    }

    var body: some View {
        Form {
            mainSection
            if enabled && authorized {
                alertsSection
                privacySection
                testSection
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.ground.ignoresSafeArea())
        .navigationTitle("Notificações")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 84) }
        .task {
            threshold = Money.decimal(from: thresholdRaw)
            await refreshStatus()
        }
        // Voltando dos Ajustes do iPhone, a permissão pode ter mudado.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task { await refreshStatus() }
        }
        .onChange(of: [budgets, planned, large, weekly, connection, showValues]) { _, _ in reevaluate() }
        .onChange(of: threshold) { _, value in
            thresholdRaw = (value as NSDecimalNumber).doubleValue
            reevaluate()
        }
    }

    // MARK: Seções

    private var mainSection: some View {
        Section {
            if status == .denied {
                StatusBadge(text: "Bloqueadas nos Ajustes do iPhone", icon: "bell.slash", color: Theme.warning)
                Button("Abrir os Ajustes do iPhone") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            } else {
                Toggle(isOn: enabledBinding) {
                    SettingLabel(title: "Ativar notificações", icon: "bell.badge")
                }
            }
        } footer: {
            Text("Todas são locais: o próprio iPhone agenda e mostra. Nada passa por servidor, e nenhum dado sai do aparelho para isso.")
        }
    }

    private var alertsSection: some View {
        Section {
            Toggle(isOn: $budgets) {
                SettingLabel(title: "Orçamentos", detail: "Aos 90%, ao estourar e quando o ritmo do mês passa do limite", icon: "chart.pie", style: .neutral)
            }
            Toggle(isOn: $planned) {
                SettingLabel(title: "Gastos previstos", detail: "Às 9h do dia marcado", icon: "calendar", style: .neutral)
            }
            Toggle(isOn: $large) {
                SettingLabel(title: "Gasto alto", detail: "Quando um gasto passar do valor abaixo", icon: "exclamationmark.circle", style: .neutral)
            }
            if large {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Avisar a partir de")
                        .font(.footnote)
                        .foregroundStyle(Theme.inkSecondary)
                    CurrencyField(title: "Valor do gasto alto", value: $threshold)
                }
            }
            Toggle(isOn: $weekly) {
                SettingLabel(title: "Resumo semanal", detail: "Segunda, às 9h", icon: "calendar.badge.clock", style: .neutral)
            }
            Toggle(isOn: $connection) {
                SettingLabel(title: "Conexão expirando", detail: "7 dias e 1 dia antes de vencer", icon: "building.columns", style: .neutral)
            }
        } header: {
            Text("Alertas")
        } footer: {
            Text(backgroundAllowed
                 ? "Orçamentos e gasto alto dependem de dados novos do banco: chegam na hora quando você abre o app e, fora dele, quando o iOS libera uma checagem em segundo plano (algumas vezes por dia, só com o iPhone desbloqueado). Os demais têm hora marcada e chegam sempre."
                 : "A Atualização em 2º Plano está desligada para o Fluxo. Orçamentos e gasto alto só serão avisados quando você abrir o app. Para ligar: Ajustes do iPhone › Geral › Atualização em 2º Plano.")
        }
    }

    private var privacySection: some View {
        Section {
            Toggle(isOn: showValuesBinding) {
                SettingLabel(title: "Mostrar valores", detail: "Inclusive na tela bloqueada", icon: "eye", style: .neutral)
            }
        } header: {
            Text("Privacidade")
        } footer: {
            Text("Desligado, as notificações dizem só o que aconteceu, sem valores. Para ver valores só depois do Face ID: Ajustes do iPhone › Notificações › Fluxo › Mostrar Pré-visualizações › Quando Desbloqueado. Nomes de pessoas em Pix nunca aparecem.")
        }
    }

    private var testSection: some View {
        Section {
            Button {
                NotificationPlanner.post(.init(
                    id: "test-\(UUID().uuidString)",
                    title: "Notificação de teste",
                    body: "Se você está vendo isto, as notificações do Fluxo funcionam.",
                    tab: .settings
                ))
                testSent = true
            } label: {
                HStack {
                    Text("Enviar notificação de teste")
                    Spacer()
                    if testSent { Image(systemName: "checkmark").foregroundStyle(Theme.positive) }
                }
            }
        }
    }

    // MARK: Regras

    /// Ligar: pede a permissão do iOS. Desligar: apaga tudo o que estava agendado.
    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { enabled && authorized },
            set: { turnOn in
                if turnOn {
                    Task { @MainActor in
                        let granted = (try? await UNUserNotificationCenter.current()
                            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
                        enabled = granted
                        await refreshStatus()
                        if granted {
                            BackgroundRefresh.schedule()
                            await NotificationPlanner.evaluate(finance)
                        }
                    }
                } else {
                    enabled = false
                    BackgroundRefresh.cancel()
                    NotificationCleanup.removeAll()
                }
            }
        )
    }

    /// Mostrar valores é afrouxar a privacidade: pede Face ID. Esconder é livre.
    private var showValuesBinding: Binding<Bool> {
        Binding(
            get: { showValues },
            set: { newValue in
                if !newValue {
                    showValues = false
                } else {
                    Task { @MainActor in
                        if await lock.authenticate(reason: "Mostrar valores nas notificações") {
                            showValues = true
                        }
                    }
                }
            }
        )
    }

    private func reevaluate() {
        Task { await NotificationPlanner.evaluate(finance) }
    }

    @MainActor
    private func refreshStatus() async {
        status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        backgroundAllowed = UIApplication.shared.backgroundRefreshStatus == .available
    }
}
