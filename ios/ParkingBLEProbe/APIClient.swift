import Foundation
import Security
import UIKit
import Combine

/// Pilot API: POST JSON token + beacon_id; never calls the existing /open-gate endpoint.
/// Automatic POST is explicitly opt-in. No automatic retry in this test version.
final class APIClient: ObservableObject {
    static let shared = APIClient()

    private static let urlKey = "parking-api-endpoint"
    private static let enabledKey = "parking-api-auto"
    private static let lastKey = "parking-api-last-post-at"
    private static let keychainService = "com.parkingble.probe.pilot"
    private static let keychainAccount = "personal-token"
    private let minInterval: TimeInterval = 60
    private let session: URLSession

    @Published private(set) var endpoint: String
    @Published private(set) var hasToken: Bool
    @Published private(set) var autoPost: Bool
    @Published private(set) var networkStatus: String = "Запросов пока нет"

    private init() {
        endpoint = UserDefaults.standard.string(forKey: Self.urlKey) ?? ""
        autoPost = UserDefaults.standard.bool(forKey: Self.enabledKey)
        hasToken = Self.readToken() != nil
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 10
        config.waitsForConnectivity = false
        session = URLSession(configuration: config)
    }

    func save(endpoint newEndpoint: String, token newToken: String) {
        endpoint = newEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(endpoint, forKey: Self.urlKey)
        if !newToken.isEmpty {
            hasToken = Self.saveToken(newToken)
        }
        record("API_CONFIG_SAVED", "https=\(endpoint.hasPrefix("https://")) token=\(hasToken)")
    }

    func removeToken() {
        let query = Self.tokenQuery()
        SecItemDelete(query as CFDictionary)
        hasToken = false
        autoPost = false
        UserDefaults.standard.set(false, forKey: Self.enabledKey)
        record("API_TOKEN_REMOVED", "")
    }

    func setAutoPost(_ enabled: Bool) {
        autoPost = enabled
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        record("API_AUTO_POST", enabled ? "ON" : "OFF")
    }

    func submit(source: String, beaconId: String, event: String, manual: Bool = false) {
        if !manual && !autoPost { return }

        guard let url = URL(string: endpoint),
              url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil else {
            record("HTTP_CONFIG_ERROR", "Нужен полный HTTPS endpoint")
            return
        }
        guard let token = Self.readToken(), !token.isEmpty else {
            record("HTTP_CONFIG_ERROR", "Токен отсутствует")
            return
        }

        // A single cooldown is shared by the two beacon technologies for the pilot.
        // Persist it before sending, so a background relaunch cannot immediately duplicate.
        let now = Date().timeIntervalSince1970
        if !manual {
            let last = UserDefaults.standard.double(forKey: Self.lastKey)
            if now - last < minInterval {
                record("HTTP_SUPPRESSED", "cooldown_remaining=\(Int(minInterval - now + last))s source=\(source)")
                return
            }
            UserDefaults.standard.set(now, forKey: Self.lastKey)
        }

        let requestID = UUID().uuidString.lowercased()
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let payload: [String: String] = [
            "token": token,
            "beacon_id": beaconId,
            "source": source,
            "event": event,
            "request_id": requestID,
            "occurred_at": dateFormatter.string(from: Date())
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            record("HTTP_JSON_ERROR", "Не удалось сформировать запрос")
            return
        }

        let startedAt = ProcessInfo.processInfo.systemUptime
        record("HTTP_START", "source=\(source) id=\(beaconId) request_id=\(requestID)")

        // Request starts in an OS-delivered BLE/location callback on the main queue.
        // This is a finite extension, not a forever-running watchdog.
        var backgroundTask: UIBackgroundTaskIdentifier = .invalid
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "ParkingBeaconPOST") {
            if backgroundTask != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTask)
                backgroundTask = .invalid
            }
        }

        let task = session.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                let rtt = Int((ProcessInfo.processInfo.systemUptime - startedAt) * 1000)
                if let error = error {
                    self.record("HTTP_ERROR", "rtt_ms=\(rtt) error=\(error._code)")
                } else if let response = response as? HTTPURLResponse {
                    let result: String
                    if let data = data,
                       let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let status = object["status"] as? String {
                        result = String(status.prefix(40))
                    } else {
                        result = "unknown"
                    }
                    self.record("HTTP_RESPONSE", "http=\(response.statusCode) rtt_ms=\(rtt) status=\(result)")
                } else {
                    self.record("HTTP_NO_RESPONSE", "rtt_ms=\(rtt)")
                }
                if backgroundTask != .invalid {
                    UIApplication.shared.endBackgroundTask(backgroundTask)
                    backgroundTask = .invalid
                }
            }
        }
        task.resume()
    }

    private func record(_ event: String, _ details: String) {
        networkStatus = event + (details.isEmpty ? "" : " · " + details)
        BLEManager.shared.logExternal(event, details: details)
    }

    private static func tokenQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
    }
    private static func readToken() -> String? {
        var query = tokenQuery()
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    private static func saveToken(_ token: String) -> Bool {
        guard let data = token.data(using: .utf8) else { return false }
        let query = tokenQuery()
        let updates: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemUpdate(query as CFDictionary, updates as CFDictionary)
        if status == errSecSuccess { return true }
        if status == errSecItemNotFound {
            var insertion = query
            for (key, value) in updates { insertion[key] = value }
            return SecItemAdd(insertion as CFDictionary, nil) == errSecSuccess
        }
        return false
    }
}
