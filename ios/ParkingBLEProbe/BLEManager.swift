import Foundation
import Combine
import CoreBluetooth
import CoreLocation
import SwiftUI
import UIKit

/// Two independent iOS wake-up mechanisms:
/// 1) iBeacon region via Core Location with Always permission
/// 2) BLE GATT discovery + pending reconnect via Core Bluetooth restoration
/// No Bluetooth pairing is requested; beacon identifiers are not secrets.
final class BLEManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate, CLLocationManagerDelegate {
    static let shared = BLEManager()

    static let serviceUUID = CBUUID(string: "c6ec1c8d-e23a-4751-93f8-31d4d4a17b10")
    static let infoUUID = CBUUID(string: "c6ec1c8d-e23a-4751-93f8-31d4d4a17b11")
    static let beaconUUID = UUID(uuidString: "F47D8F33-25FA-4DC8-92CB-8BE1199A6410")!
    static let regionID = "parking-ibeacon-region-01"
    static let ibeaconId = "ibeacon:F47D8F33-25FA-4DC8-92CB-8BE1199A6410:1:1"
    private static let restoreID = "parking-ble-probe-central-v1"

    private static let gattEnabledKey = "pilot-gatt-enabled"
    private static let beaconEnabledKey = "pilot-ibeacon-enabled"
    private static let peripheralKey = "pilot-last-gatt-peripheral-uuid"

    @Published private(set) var bluetoothStatus = "Bluetooth: инициализация"
    @Published private(set) var gattStatus = "GATT выключен"
    @Published private(set) var beaconStatus = "iBeacon выключен"
    @Published private(set) var gattEnabled: Bool
    @Published private(set) var beaconEnabled: Bool
    @Published private(set) var gattConnections = 0
    @Published private(set) var beaconEntries = 0
    @Published private(set) var lastRSSI: Int?
    @Published private(set) var recentEvents: [String] = []

    private let location = CLLocationManager()
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var gattConnected = false
    private var infoReadForConnection = false
    private var knownGattId: String?

    private override init() {
        gattEnabled = UserDefaults.standard.bool(forKey: Self.gattEnabledKey)
        beaconEnabled = UserDefaults.standard.bool(forKey: Self.beaconEnabledKey)
        knownGattId = UserDefaults.standard.string(forKey: Self.peripheralKey)
        super.init()
        recentEvents = EventLog.shared.tail()
        location.delegate = self
        location.pausesLocationUpdatesAutomatically = true

        central = CBCentralManager(
            delegate: self,
            queue: .main,
            options: [
                CBCentralManagerOptionRestoreIdentifierKey: Self.restoreID,
                CBCentralManagerOptionShowPowerAlertKey: true
            ]
        )
        log("PILOT_INIT", details: "gatt=\(gattEnabled) ibeacon=\(beaconEnabled)")
        if beaconEnabled { configureBeaconMonitoring(prompt: false) }
    }

    func logExternal(_ event: String, details: String = "") {
        log(event, details: details)
    }

    private func log(_ event: String,
                     rssi: Int? = nil,
                     id: UUID? = nil,
                     details: String = "") {
        let rendered = EventLog.shared.append(event: event, rssi: rssi, peripheral: id, details: details)
        recentEvents.insert(rendered, at: 0)
        if recentEvents.count > 50 { recentEvents.removeLast(recentEvents.count - 50) }
    }

    func mark() { log("MANUAL_MARK") }

    func resetLog() {
        EventLog.shared.reset()
        recentEvents = EventLog.shared.tail()
        log("CSV_RESET")
    }

    func recordScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active: log("APP_ACTIVE")
        case .inactive: log("APP_INACTIVE")
        case .background: log("APP_BACKGROUND")
        @unknown default: log("APP_UNKNOWN_PHASE")
        }
        // Do not restart GATT discovery on every foreground transition.
        // A pending CoreBluetooth connect is a persistent OS operation.
        if phase == .active && beaconEnabled {
            log("IBEACON_MONITOR_STATUS",
                details: "authorized=\(location.authorizationStatus.rawValue) regions=\(location.monitoredRegions.count)")
        }
    }

    // MARK: iBeacon (Core Location)

    private func beaconRegion() -> CLBeaconRegion {
        let region = CLBeaconRegion(uuid: Self.beaconUUID,
                                    major: 1, minor: 1,
                                    identifier: Self.regionID)
        region.notifyOnEntry = true
        region.notifyOnExit = true
        return region
    }

    func startBeaconMonitoring() {
        beaconEnabled = true
        UserDefaults.standard.set(true, forKey: Self.beaconEnabledKey)
        log("IBEACON_ENABLE")
        configureBeaconMonitoring(prompt: true)
    }

    func stopBeaconMonitoring() {
        beaconEnabled = false
        UserDefaults.standard.set(false, forKey: Self.beaconEnabledKey)
        for region in location.monitoredRegions where region.identifier == Self.regionID {
            location.stopMonitoring(for: region)
        }
        beaconStatus = "iBeacon выключен"
        log("IBEACON_STOP")
    }

    private func configureBeaconMonitoring(prompt: Bool) {
        guard beaconEnabled else { return }
        guard CLLocationManager.isMonitoringAvailable(for: CLBeaconRegion.self) else {
            beaconStatus = "Мониторинг iBeacon недоступен"
            log("IBEACON_UNAVAILABLE")
            return
        }
        if location.authorizationStatus != .authorizedAlways {
            beaconStatus = "Нужно разрешение геолокации «Всегда»"
            log("IBEACON_NEEDS_ALWAYS", details: "auth=\(location.authorizationStatus.rawValue)")
            if prompt { location.requestAlwaysAuthorization() }
            return
        }
        guard !location.monitoredRegions.contains(where: {$0.identifier == Self.regionID}) else {
            beaconStatus = "iBeacon мониторинг зарегистрирован"
            return
        }
        location.startMonitoring(for: beaconRegion())
        beaconStatus = "Регистрация iBeacon мониторинга…"
        log("IBEACON_MONITOR_START", details: Self.ibeaconId)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        log("LOCATION_AUTH", details: "status=\(manager.authorizationStatus.rawValue)")
        if beaconEnabled { configureBeaconMonitoring(prompt: false) }
    }

    func locationManager(_ manager: CLLocationManager, didStartMonitoringFor region: CLRegion) {
        guard region.identifier == Self.regionID else { return }
        beaconStatus = "iBeacon мониторинг активен"
        log("IBEACON_MONITOR_READY")
        // State checks are informational only. They do NOT trigger automatic POST,
        // avoiding an opening solely because the app was just started at the gate.
        manager.requestState(for: region)
    }

    func locationManager(_ manager: CLLocationManager,
                         didDetermineState state: CLRegionState,
                         for region: CLRegion) {
        guard region.identifier == Self.regionID else { return }
        let value: String
        switch state {
        case .inside: value = "INSIDE"
        case .outside: value = "OUTSIDE"
        case .unknown: value = "UNKNOWN"
        @unknown default: value = "UNKNOWN"
        }
        log("IBEACON_STATE", details: value)
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard beaconEnabled && region.identifier == Self.regionID else { return }
        beaconEntries += 1
        log("IBEACON_ENTER", details: Self.ibeaconId)
        APIClient.shared.submit(source: "ibeacon", beaconId: Self.ibeaconId, event: "enter")
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard beaconEnabled && region.identifier == Self.regionID else { return }
        log("IBEACON_EXIT", details: Self.ibeaconId)
    }

    func locationManager(_ manager: CLLocationManager,
                         monitoringDidFailFor region: CLRegion?,
                         withError error: Error) {
        beaconStatus = "Ошибка мониторинга iBeacon"
        log("IBEACON_MONITOR_ERROR", details: "code=\((error as NSError).code)")
    }

    // MARK: Core Bluetooth GATT + pending reconnect

    func startGatt() {
        gattEnabled = true
        UserDefaults.standard.set(true, forKey: Self.gattEnabledKey)
        log("GATT_ENABLE")
        ensureGatt()
    }

    func stopGatt() {
        gattEnabled = false
        UserDefaults.standard.set(false, forKey: Self.gattEnabledKey)
        central.stopScan()
        if let p = peripheral {
            central.cancelPeripheralConnection(p)
        }
        peripheral = nil
        gattConnected = false
        infoReadForConnection = false
        gattStatus = "GATT выключен"
        log("GATT_STOP")
    }

    func forgetGattAndRescan() {
        if let p = peripheral { central.cancelPeripheralConnection(p) }
        central.stopScan()
        peripheral = nil
        gattConnected = false
        infoReadForConnection = false
        knownGattId = nil
        UserDefaults.standard.removeObject(forKey: Self.peripheralKey)
        log("GATT_FORGET_DEVICE")
        if gattEnabled { ensureGatt() }
    }

    private func ensureGatt() {
        guard gattEnabled else { return }
        guard central.state == .poweredOn else {
            gattStatus = "GATT ожидает включения Bluetooth"
            return
        }
        if let p = peripheral {
            if p.state == .disconnected {
                log("GATT_PENDING_CONNECT", id: p.identifier)
                central.connect(p, options: nil)
                gattStatus = "Ожидает BLE-подключения (iOS)"
            } else if p.state == .connected {
                gattStatus = "GATT подключён"
            } else {
                gattStatus = "Ожидает BLE-подключения (iOS)"
            }
            return
        }
        if let saved = knownGattId,
           let identifier = UUID(uuidString: saved) {
            let recovered = central.retrievePeripherals(withIdentifiers: [identifier])
            if let p = recovered.first {
                peripheral = p
                p.delegate = self
                log("GATT_RETRIEVE_SAVED", id: p.identifier)
                ensureGatt()
                return
            }
        }
        if !central.isScanning {
            central.scanForPeripherals(withServices: [Self.serviceUUID], options: nil)
            log("GATT_SCAN_START", details: Self.serviceUUID.uuidString)
        }
        gattStatus = "Поиск маяка GATT"
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: bluetoothStatus = "Bluetooth включён"
        case .poweredOff: bluetoothStatus = "Bluetooth выключен"
        case .unauthorized: bluetoothStatus = "Bluetooth не разрешён"
        case .unsupported: bluetoothStatus = "BLE не поддерживается"
        case .resetting: bluetoothStatus = "Bluetooth перезапускается"
        case .unknown: bluetoothStatus = "Bluetooth неизвестен"
        @unknown default: bluetoothStatus = "Bluetooth неизвестен"
        }
        log("BLE_STATE", details: bluetoothStatus)
        if central.state == .poweredOn { ensureGatt() }
    }

    func centralManager(_ central: CBCentralManager, willRestoreState state: [String: Any]) {
        let restored = state[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
        log("GATT_STATE_RESTORED",
            details: "peripherals=\(restored.count)")
        if !gattEnabled {
            for p in restored { central.cancelPeripheralConnection(p) }
            central.stopScan()
            return
        }
        if let p = restored.first {
            peripheral = p
            p.delegate = self
            knownGattId = p.identifier.uuidString
            UserDefaults.standard.set(knownGattId, forKey: Self.peripheralKey)
            if p.state == .connected {
                gattConnected = true
                p.discoverServices([Self.serviceUUID])
            } else if p.state == .disconnected {
                ensureGatt()
            }
            gattStatus = "GATT восстановлен из iOS"
        } else {
            ensureGatt()
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover found: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        guard gattEnabled && peripheral == nil else { return }
        peripheral = found
        found.delegate = self
        knownGattId = found.identifier.uuidString
        UserDefaults.standard.set(knownGattId, forKey: Self.peripheralKey)
        lastRSSI = RSSI.intValue
        central.stopScan()
        gattStatus = "Подключение к GATT…"
        log("GATT_DISCOVERED", rssi: RSSI.intValue, id: found.identifier)
        central.connect(found, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect p: CBPeripheral) {
        guard gattEnabled else {
            central.cancelPeripheralConnection(p)
            return
        }
        peripheral = p
        p.delegate = self
        gattConnected = true
        infoReadForConnection = false
        gattConnections += 1
        gattStatus = "GATT подключён, читаем ID"
        log("GATT_CONNECTED", id: p.identifier)
        p.discoverServices([Self.serviceUUID])
        p.readRSSI()
    }

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            log("GATT_SERVICES_ERROR", details: "\(error.localizedDescription)")
            return
        }
        guard let service = p.services?.first(where: {$0.uuid == Self.serviceUUID}) else {
            log("GATT_SERVICE_MISSING", id: p.identifier)
            return
        }
        p.discoverCharacteristics([Self.infoUUID], for: service)
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            log("GATT_CHAR_ERROR", details: "\(error.localizedDescription)")
            return
        }
        guard let char = service.characteristics?.first(where: {$0.uuid == Self.infoUUID}) else {
            log("GATT_CHAR_MISSING")
            return
        }
        p.readValue(for: char)
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard gattEnabled && characteristic.uuid == Self.infoUUID && !infoReadForConnection else { return }
        if let error = error {
            log("GATT_READ_ERROR", details: "\(error.localizedDescription)")
            return
        }
        guard let bytes = characteristic.value,
              let beaconId = String(data: bytes, encoding: .utf8),
              beaconId.hasPrefix("gatt:"),
              beaconId.count <= 80 else {
            log("GATT_BAD_BEACON_ID", id: p.identifier)
            return
        }
        infoReadForConnection = true
        gattStatus = "GATT подключён: \(beaconId)"
        log("GATT_ID_READ", id: p.identifier, details: beaconId)
        // One POST attempt per new GATT connection (subject to shared 60s cooldown).
        APIClient.shared.submit(source: "gatt", beaconId: beaconId, event: "connected")
    }

    func peripheral(_ p: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        if error == nil {
            lastRSSI = RSSI.intValue
            log("GATT_RSSI", rssi: RSSI.intValue, id: p.identifier)
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        gattConnected = false
        infoReadForConnection = false
        gattStatus = "GATT отключён"
        log("GATT_DISCONNECTED", id: p.identifier,
            details: error.map { "code=\(($0 as NSError).code)" } ?? "normal")
        // This call can remain pending while the client is away.
        if gattEnabled {
            central.connect(p, options: nil)
            gattStatus = "Ожидает переподключения (iOS)"
            log("GATT_PENDING_RECONNECT", id: p.identifier)
        }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        gattConnected = false
        gattStatus = "GATT: ошибка подключения"
        log("GATT_CONNECT_FAILED", id: p.identifier,
            details: error.map { "code=\(($0 as NSError).code)" } ?? "")
        // No continuous retry timer. User can explicitly forget/re-scan if needed.
    }
}
