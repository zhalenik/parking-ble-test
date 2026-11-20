import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var ble: BLEManager
    @State private var showResetConfirmation = false

    private var isReady: Bool {
        ble.bluetoothStatus == "Bluetooth включён"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    statusCard

                    VStack(alignment: .leading, spacing: 7) {
                        Text("Измерение сигнала")
                            .font(.headline)
                        HStack(alignment: .firstTextBaseline) {
                            Text(ble.lastRSSI.map { "\($0) dBm" } ?? "— dBm")
                                .font(.system(size: 34, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                            Spacer()
                            Text("Обнаружений: \(ble.discoveries)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text("Последнее событие: \(ble.lastDiscovery)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Сигнал можно сравнивать между подходами, но RSSI не является точным расстоянием.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .cardStyle()

                    VStack(spacing: 10) {
                        Button {
                            ble.scanEnabled ? ble.stop() : ble.start()
                        } label: {
                            Label(ble.scanEnabled ? "Остановить BLE-сканирование" : "Запустить BLE-сканирование",
                                  systemImage: ble.scanEnabled ? "stop.circle.fill" : "dot.radiowaves.left.and.right")
                                .frame(maxWidth: .infinity)
                                .padding(6)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!isReady && !ble.scanEnabled)

                        HStack {
                            Button {
                                ble.mark()
                            } label: {
                                Label("Поставить метку", systemImage: "mappin.and.ellipse")
                            }
                            .buttonStyle(.bordered)

                            Spacer()

                            ShareLink(item: EventLog.shared.fileURL) {
                                Label("Экспорт CSV", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(.bordered)
                        }

                        Button(role: .destructive) {
                            showResetConfirmation = true
                        } label: {
                            Text("Очистить журнал")
                                .font(.caption)
                        }
                        .padding(.top, 2)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Журнал BLE")
                            .font(.headline)
                        Text("Новые события сверху. Журнал сохраняется при выключении экрана.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(Array(ble.recentEvents.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 11, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                            Divider()
                        }
                    }
                    .cardStyle()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Как проверить")
                            .font(.headline)
                        Text("1. Включите сканирование и подтвердите разрешение Bluetooth.")
                        Text("2. Дождитесь DISCOVER_FIRST рядом с ESP32-C3.")
                        Text("3. Удалитесь от маяка, подождите, заблокируйте iPhone и снова приблизьтесь.")
                        Text("4. Разблокируйте iPhone и экспортируйте CSV.")
                        Text("Сканирование в фоне ограничено iOS. Повторное событие при новом подходе не гарантируется: iOS может объединять BLE-пакеты.")
                        Text("Принудительно закрытое свайпом приложение может не пробуждаться. Отдельную функцию открытия шлагбаума этот прототип не содержит.")
                            .foregroundStyle(.secondary)
                    }
                    .font(.footnote)
                    .cardStyle()

                    Text("BLE Service UUID: \(BLEManager.serviceUUID.uuidString)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .padding()
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Parking BLE Probe")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Удалить все записи BLE?", isPresented: $showResetConfirmation,
                                titleVisibility: .visible) {
                Button("Очистить журнал", role: .destructive) { ble.resetLog() }
            }
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.title2)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text(ble.bluetoothStatus)
                        .font(.headline)
                    Text(ble.scanEnabled
                         ? (ble.scanActive ? "Сканирование зарегистрировано" : "Ожидаем Bluetooth")
                         : "BLE-сканирование остановлено")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if ble.scanEnabled {
                Text("После блокировки экрана система может уменьшить частоту поиска маяков.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .cardStyle()
    }
}

private struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(15)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 15))
    }
}

private extension View {
    func cardStyle() -> some View { modifier(CardStyle()) }
}
