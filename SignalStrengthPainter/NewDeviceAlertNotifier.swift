import Foundation
import UserNotifications

/// Posts a local notification when `NetworkScanner` detects a never-
/// before-seen MAC address on a network the user has marked as trusted.
///
/// Why local-only: Wi-Fi Buddy has no backend — everything runs on-
/// device. The notification is scheduled via `UNUserNotificationCenter`
/// with a nil trigger so it fires immediately, and carries just enough
/// context (device type, vendor) for the user to tap into the Devices
/// tab and review. Zero personal data is embedded in the payload.
final class NewDeviceAlertNotifier {
    static let shared = NewDeviceAlertNotifier()

    private static let identifierPrefix = "wifibuddy.newdevice."

    private let notificationCenter: UNUserNotificationCenter

    init(notificationCenter: UNUserNotificationCenter = .current()) {
        self.notificationCenter = notificationCenter
    }

    /// Fire one notification per newly-discovered device, coalescing
    /// when the scan returns more than a couple of newcomers so we
    /// never dump five alerts onto a user at once.
    func postNewDeviceAlerts(_ devices: [DiscoveredDevice]) {
        guard !devices.isEmpty else { return }

        notificationCenter.getNotificationSettings { [weak self] settings in
            guard let self else { return }
            switch settings.authorizationStatus {
            case .notDetermined:
                // No prompt here — the first-survey completion path is
                // our canonical permission-request moment. Until the
                // user has opted in, we silently skip new-device
                // alerts rather than ambush them with a permission
                // sheet during a passive background scan.
                return
            case .denied:
                return
            case .authorized, .provisional, .ephemeral:
                DispatchQueue.main.async {
                    self.scheduleAlerts(for: devices)
                }
            @unknown default:
                return
            }
        }
    }

    private func scheduleAlerts(for devices: [DiscoveredDevice]) {
        // Single notification for >=3 new devices — anything more is
        // likely a whole-network re-scan anomaly, not a stranger joining.
        if devices.count >= 3 {
            let content = UNMutableNotificationContent()
            content.title = "\(devices.count) new devices on your Wi-Fi"
            content.body = "We saw several devices we haven't seen before. Open Devices to review."
            content.sound = .default
            content.threadIdentifier = "wifibuddy.newdevice"

            let request = UNNotificationRequest(
                identifier: Self.identifierPrefix + "batch." + UUID().uuidString,
                content: content,
                trigger: nil
            )
            notificationCenter.add(request, withCompletionHandler: nil)
            return
        }

        for device in devices {
            let content = UNMutableNotificationContent()
            content.title = "New device on your Wi-Fi"
            content.body = describe(device)
            content.sound = .default
            content.threadIdentifier = "wifibuddy.newdevice"

            let request = UNNotificationRequest(
                // Stable per-MAC identifier so repeated scans within
                // the same session don't fire duplicates before the
                // baseline has a chance to persist.
                identifier: Self.identifierPrefix + (device.macAddress?.lowercased() ?? device.ipAddress),
                content: content,
                trigger: nil
            )
            notificationCenter.add(request, withCompletionHandler: nil)
        }
    }

    /// Builds a one-line description that conveys "who" without
    /// leaking hostnames. We prefer the vendor-derived label over the
    /// Bonjour/hostname because the latter often contains the owner's
    /// real name (e.g., "Justins-MacBook-Pro"), which we shouldn't
    /// embed in lock-screen notifications.
    private func describe(_ device: DiscoveredDevice) -> String {
        let type = device.deviceType.shortName
        if let vendor = device.ouiVendor, !vendor.isEmpty {
            return "A \(vendor) \(type.lowercased()) just joined. Open Devices to review."
        }
        if let manufacturer = device.manufacturer, !manufacturer.isEmpty {
            return "A \(manufacturer) \(type.lowercased()) just joined. Open Devices to review."
        }
        return "An unknown \(type.lowercased()) just joined. Open Devices to review."
    }
}
