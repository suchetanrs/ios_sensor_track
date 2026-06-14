import Foundation
import UserNotifications
import CoreLocation

/// Stores the GitHub token in the device Keychain (not in UserDefaults / plain files).
enum Keychain {
    private static let service = "com.example.vaultsync"
    private static let account = "github-token"

    static func set(_ token: String) {
        delete()
        guard !token.isEmpty else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(token.utf8),
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func get() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        if SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
           let data = out as? Data {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum Notifier {
    static func requestAuth() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

/// Uses a low-power background location session to keep the app alive so the 30s
/// timer keeps firing while the app is backgrounded. Requires "Always" permission
/// and the `location` background mode (set in project.yml).
final class LocationKeepAlive: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        manager.distanceFilter = 3000
        manager.pausesLocationUpdatesAutomatically = false
        manager.activityType = .other
    }

    func requestAuth() {
        manager.requestWhenInUseAuthorization()
        manager.requestAlwaysAuthorization()
    }

    func start() {
        manager.allowsBackgroundLocationUpdates = true
        manager.startUpdatingLocation()
    }

    func stop() {
        manager.allowsBackgroundLocationUpdates = false
        manager.stopUpdatingLocation()
    }

    // We don't use the location data itself — these just keep the session running.
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {}
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
