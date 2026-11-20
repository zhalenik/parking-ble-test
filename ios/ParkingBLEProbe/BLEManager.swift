import Foundation
import CoreBluetooth
import SwiftUI
import UIKit

/// Тестовый BLE central. Для работы в фоне требуется UIBackgroundModes/bluetooth-central.
/// iOS сама выбирает периоды сканирования: задержка обнаружения не гарантирована.
final class BLEManager: NSObject, ObservableObject, CBCentralManagerDelegate {
    static let shared = BLEManager()

    static let serviceUUID = CBUUID(string: "c6ec1c8d-e23a-4751-93f8-31d4d4a17b10")
    private static let restorationID = "parking-ble-probe-central-v1"
    private static let enabledKey = "parking-ble-scan-enabled"

    @Published private(set) var bluetoothStatus = "Инициализация Bluetooth…"
    @Published private(set) var scanEnabled = false
    @Published private(set) var scanActive = false
    @Published private(set) var lastRSSI: Int?
    @Published private(set) var discoveries = 0
    @Published private(set) var lastDiscovery = "Пока нет"
    @Published private(set) var recentEvents: [String] = []

    private var central: CBCentralManager!
    private var knownIDs = Set<UUID>()
    private var lastRSSILogged: [UUID: TimeInterval] = [:]

    private override init() {
        scanEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        super.init()
        recentEvents = EventLog.shared.tail()
        central = CBCentralManager(
            delegate: self,
            queue: .main,
            options: [
                CBCentralManagerOptionRestoreIdentifierKey: Self.restorationID,
                CBCentralManagerOptionShowPowerAlertKey: true
            ]
        )
        note("APP_INIT", details: "saved_enabled=\(scanEnabled)")
    }

    private func note(_ event: String, rssi: Int? = nil, id: UUID? = nil, details: String = "") {
        let display = EventLog.shared.append(event: event, rssi: rssi, peripheral: id, details: details)
        recentEvents.insert(display, at: 0)
        if recentEvents.count > 35 {
            recentEvents.removeLast(recentEvents.count - 35)
        }
    }

    func start() {
        scanEnabled = true
        UserDefaults.standard.set(true, forKey: Self.enabledKey)
        note("USER_START")
        ensureScanning()
    }

    func stop() {
        scanEnabled = false
        UserDefaults.standard.set(false, forKey: Self.enabledKey)
        if central.isScanning {
            central.stopScan()
        }
        scanActive = false
        note("USER_STOP")
    }

    /// Создаёт временную отметку для ручного теста, например перед подходом к маяку.
    func mark() {
        note("MANUAL_MARK", details: "Отметка для сопоставления с наблюдением")
    }

    func resetLog() {
        EventLog.shared.reset()
        recentEvents = EventLog.shared.tail()
        note("CSV_RESET")
    }

    func recordScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active: note("APP_ACTIVE")
        case .inactive: note("APP_INACTIVE")
        case .background: note("APP_BACKGROUND")
        @unknown default: note("APP_UNKNOWN_PHASE")
        }
        if phase == .active && scanEnabled {
            ensureScanning()
        }
    }

    private func ensureScanning() {
        guard scanEnabled else { return }
        guard central.state == .poweredOn else {
            note("SCAN_WAIT_BLUETOOTH", details: bluetoothStatus)
            return
        }
        guard !central.isScanning else {
            scanActive = true
            return
        }
        knownIDs.removeAll()
        lastRSSILogged.removeAll()
        // CoreBluetooth требует service UUID для фонового сканирования.
        // В фоне iOS игнорирует allowDuplicates и может доставлять события с задержкой.
        central.scanForPeripherals(
            withServices: [Self.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        scanActive = central.isScanning
        note("SCAN_START", details: "UUID=\(Self.serviceUUID.uuidString)")
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: bluetoothStatus = "Bluetooth включён"
        case .poweredOff: bluetoothStatus = "Bluetooth выключен"
        case .unauthorized: bluetoothStatus = "Нет разрешения Bluetooth"
        case .unsupported: bluetoothStatus = "BLE не поддерживается"
        case .resetting: bluetoothStatus = "Bluetooth перезапускается"
        case .unknown: bluetoothStatus = "Состояние Bluetooth неизвестно"
        @unknown default: bluetoothStatus = "Неизвестное состояние"
        }
        scanActive = central.isScanning
        note("BLE_STATE", details: bluetoothStatus)
        if central.state == .poweredOn {
            ensureScanning()
        }
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        let restored = (dict[CBCentralManagerRestoredStateScanServicesKey] as? [CBUUID]) ?? []
        note("IOS_STATE_RESTORED", details: "services=\(restored.map(\.uuidString).joined(separator: ";"))")
        if !scanEnabled && central.isScanning {
            central.stopScan()
        }
        scanActive = central.isScanning
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        guard scanEnabled else { return }
        let uuid = peripheral.identifier
        let value = RSSI.intValue
        let now = ProcessInfo.processInfo.systemUptime
        lastRSSI = value
        lastDiscovery = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        discoveries += 1

        if knownIDs.insert(uuid).inserted {
            note("DISCOVER_FIRST", rssi: value, id: uuid)
        } else {
            let previous = lastRSSILogged[uuid] ?? 0
            // В активном окне не записываем каждый рекламный пакет:
            // один RSSI SAMPLE в секунду. В фоне сохраняем все доставленные колбэки.
            if UIApplication.shared.applicationState != .active || now - previous >= 1.0 {
                note("DISCOVER_REPEAT", rssi: value, id: uuid)
            }
        }
        lastRSSILogged[uuid] = now
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral, error: Error?) {
        note("BLE_CONNECT_FAIL", id: peripheral.identifier,
             details: error.map(String.init(describing:)) ?? "")
    }
}
