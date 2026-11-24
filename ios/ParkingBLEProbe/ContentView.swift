import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject private var ble: BLEManager
    @EnvironmentObject private var api: APIClient
    @State private var endpointInput = ""
    @State private var tokenInput = ""
    @State private var showResetConfirmation = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Два независимых способа пробуждения iPhone. Никакого Bluetooth-сопряжения пользователю не требуется.")
                        .font(.subheadline).foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("1. iBeacon · Core Location")
                            .font(.headline)
                        Text(ble.beaconStatus).font(.subheadline)
                        Text("Входов в регион: \(ble.beaconEntries)")
                            .font(.caption).monospacedDigit()
                        Button {
                            ble.beaconEnabled ? ble.stopBeaconMonitoring() : ble.startBeaconMonitoring()
                        } label: {
                            Label(ble.beaconEnabled ? "Остановить iBeacon" : "Включить мониторинг iBeacon",
                                  systemImage: ble.beaconEnabled ? "stop.circle" : "location.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        Text("Для пробуждения через Core Location после долгого ожидания требуется разрешение геолокации «Всегда».")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .cardStyle()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("2. GATT · Core Bluetooth")
                            .font(.headline)
                        Text(ble.bluetoothStatus).font(.subheadline)
                        Text(ble.gattStatus).font(.subheadline).foregroundStyle(.secondary)
                        Text("Подключений: \(ble.gattConnections)")
                            .font(.caption).monospacedDigit()
                        if let rssi = ble.lastRSSI {
                            Text("RSSI: \(rssi) dBm").font(.caption).monospacedDigit()
                        }
                        Button {
                            ble.gattEnabled ? ble.stopGatt() : ble.startGatt()
                        } label: {
                            Label(ble.gattEnabled ? "Остановить GATT" : "Включить GATT reconnect",
                                  systemImage: ble.gattEnabled ? "stop.circle" : "antenna.radiowaves.left.and.right")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        Button("Забыть сохранённый GATT и искать заново") {
                            ble.forgetGattAndRescan()
                        }
                        .font(.caption)
                        Text("iOS сохраняет запрос подключения. Вдали от маяка ожидаем reconnect без таймеров и постоянной работы приложения.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .cardStyle()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("3. Тестовый HTTPS API")
                            .font(.headline)
                        TextField("https://example.ru/api/mobile/beacon-event", text: $endpointInput)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .textFieldStyle(.roundedBorder)
                        SecureField("Персональный токен (пусто = не менять)", text: $tokenInput)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textFieldStyle(.roundedBorder)
                        HStack {
                            Button("Сохранить адрес и токен") {
                                api.save(endpoint: endpointInput, token: tokenInput)
                                tokenInput = ""
                            }
                            .buttonStyle(.bordered)
                            Spacer()
                            Text(api.hasToken ? "Токен в Keychain" : "Нет токена")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Toggle("Автоматически отправлять POST", isOn: Binding(
                            get: { api.autoPost },
                            set: { api.setAutoPost($0) }
                        ))
                        Text("Изначально выключено. Одна отправка при входе в iBeacon-регион или новом GATT-подключении. Общий cooldown 60 с, без автоматических повторов.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Отправить ручной TEST POST") {
                            api.submit(source: "manual", beaconId: "test:manual",
                                       event: "test", manual: true)
                        }
                        .buttonStyle(.bordered)
                        Text(api.networkStatus)
                            .font(.caption).foregroundStyle(.secondary)
                        Button(role: .destructive) {
                            api.removeToken()
                        } label: { Text("Удалить сохранённый токен").font(.caption) }
                    }
                    .cardStyle()

                    HStack {
                        Button {
                            ble.mark()
                        } label: {
                            Label("Отметка", systemImage: "mappin.and.ellipse")
                        }
                        .buttonStyle(.bordered)

                        Spacer()

                        ShareLink(item: EventLog.shared.fileURL) {
                            Label("Экспорт CSV", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.bordered)
                    }
                    Button("Открыть настройки разрешений iOS") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(.caption)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Журнал").font(.headline)
                        ForEach(Array(ble.recentEvents.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 10, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                            Divider()
                        }
                    }
                    .cardStyle()

                    Text("Это диагностическая версия. Не подключайте POST к действующей команде ворот до проверки сервера в режиме без физических действий. iOS не гарантирует задержки пробуждения.")
                        .font(.footnote).foregroundStyle(.secondary)

                    Button(role: .destructive) { showResetConfirmation = true } label: {
                        Text("Очистить журнал").font(.caption)
                    }
                }
                .padding()
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Parking BLE Probe 2")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Удалить записи журнала?", isPresented: $showResetConfirmation) {
                Button("Очистить", role: .destructive) { ble.resetLog() }
            }
            .onAppear { endpointInput = api.endpoint }
        }
    }
}

private struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 15))
    }
}

private extension View {
    func cardStyle() -> some View { modifier(CardStyle()) }
}
