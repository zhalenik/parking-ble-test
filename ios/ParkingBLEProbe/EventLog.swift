import Foundation
import UIKit

/// CSV журнал для повторяемых испытаний. Время входа в радиозону не измеряется.
final class EventLog {
    static let shared = EventLog()
    let fileURL: URL
    private let formatter: ISO8601DateFormatter
    private let header = "timestamp_utc,uptime_s,app_state,event,rssi_dbm,peripheral_id,details\n"

    private init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = documents.appendingPathComponent("parking-ble-ios.csv")
        formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            try? header.write(to: fileURL, atomically: true, encoding: .utf8)
        }
        // Разрешаем доступ к журналу, когда телефон заблокирован
        // (после первого разблокирования после перезагрузки).
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: fileURL.path
        )
    }

    private func safe(_ string: String) -> String {
        let escaped = string.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"" + escaped + "\""
    }

    @discardableResult
    func append(event: String,
                rssi: Int? = nil,
                peripheral: UUID? = nil,
                details: String = "") -> String {
        let state: String
        switch UIApplication.shared.applicationState {
        case .active: state = "active"
        case .inactive: state = "inactive"
        case .background: state = "background"
        @unknown default: state = "unknown"
        }
        let stamp = formatter.string(from: Date())
        let uptime = String(format: "%.3f", ProcessInfo.processInfo.systemUptime)
        let line = [
            stamp,
            uptime,
            state,
            safe(event),
            rssi.map(String.init) ?? "",
            peripheral?.uuidString ?? "",
            safe(details)
        ].joined(separator: ",") + "\n"

        if let data = line.data(using: .utf8) {
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                do {
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                } catch {
                    NSLog("ParkingBLE CSV append error: %@", String(describing: error))
                }
            }
        }
        return stamp + "  " + event
            + (rssi.map { " (" + String($0) + " dBm)" } ?? "")
            + (details.isEmpty ? "" : " · " + details)
    }

    func tail(limit: Int = 35) -> [String] {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        return Array(content.split(separator: "\n").suffix(limit).reversed().map(String.init))
    }

    func reset() {
        try? header.write(to: fileURL, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: fileURL.path
        )
    }
}
