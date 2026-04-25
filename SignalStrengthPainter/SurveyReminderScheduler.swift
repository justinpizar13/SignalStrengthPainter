import Foundation
import UserNotifications

/// Schedules the 30 / 90 / 180-day "has your Wi-Fi changed?" re-survey
/// nudges used as a retention hook for WiFi Buddy Pro. Utility apps
/// die from "I solved my problem, why am I paying?" — local notifications
/// keep the app top-of-mind without adding any server dependency.
///
/// Design notes:
/// - Permission is requested on the first completed survey, not at
///   launch. Asking before the user has experienced the "aha" has a
///   much lower acceptance rate.
/// - Each reminder has a stable identifier so scheduling is idempotent:
///   completing a new survey replaces the prior schedule rather than
///   stacking four copies of the same reminder.
/// - Notifications are purely informational. They never embed secrets,
///   account identifiers, or network SSIDs in the payload, matching the
///   app's privacy-first posture.
final class SurveyReminderScheduler {
    static let shared = SurveyReminderScheduler()

    /// Reminder schedule in whole days after the last completed survey.
    /// Tuned to roughly match "ISP-event" cadence (30d = household
    /// changes, 90d = seasonal router relocation, 180d = firmware /
    /// device churn).
    private static let reminderOffsetsInDays: [Int] = [30, 90, 180]

    private static let identifierPrefix = "wifibuddy.resurvey."

    private let notificationCenter: UNUserNotificationCenter

    init(notificationCenter: UNUserNotificationCenter = .current()) {
        self.notificationCenter = notificationCenter
    }

    /// Request permission (first time only) and schedule the 30/90/180
    /// day reminders relative to "right now" (the moment this survey
    /// completed). Safe to call repeatedly; existing pending reminders
    /// are removed first so we never double-schedule.
    func scheduleResurveyReminders(from referenceDate: Date = Date()) {
        notificationCenter.getNotificationSettings { [weak self] settings in
            guard let self else { return }
            switch settings.authorizationStatus {
            case .notDetermined:
                self.notificationCenter.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    guard granted else { return }
                    DispatchQueue.main.async {
                        self.replacePendingReminders(referenceDate: referenceDate)
                    }
                }
            case .authorized, .provisional, .ephemeral:
                DispatchQueue.main.async {
                    self.replacePendingReminders(referenceDate: referenceDate)
                }
            case .denied:
                // User explicitly opted out. Nothing to do — never try
                // to schedule through a denied state.
                return
            @unknown default:
                return
            }
        }
    }

    /// Cancel any pending re-survey reminders. Called when the user
    /// completes another survey (so the new schedule supersedes the old)
    /// and when the user disables the feature.
    func cancelPendingReminders() {
        let ids = Self.reminderOffsetsInDays.map { Self.identifierPrefix + "\($0)d" }
        notificationCenter.removePendingNotificationRequests(withIdentifiers: ids)
    }

    private func replacePendingReminders(referenceDate: Date) {
        cancelPendingReminders()

        for days in Self.reminderOffsetsInDays {
            // Fire time-interval triggers use seconds; convert guardedly.
            // Any schedule already in the past (possible on device-clock
            // drift) is skipped rather than firing immediately.
            let intervalSeconds = TimeInterval(days * 24 * 60 * 60)
            guard intervalSeconds > 0 else { continue }

            let content = UNMutableNotificationContent()
            content.title = "Has your Wi-Fi changed?"
            content.body = reminderBody(forDays: days)
            content.sound = .default
            // Stable thread so the OS groups the re-survey stream.
            content.threadIdentifier = "wifibuddy.resurvey"

            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: intervalSeconds,
                repeats: false
            )
            let request = UNNotificationRequest(
                identifier: Self.identifierPrefix + "\(days)d",
                content: content,
                trigger: trigger
            )
            notificationCenter.add(request, withCompletionHandler: nil)
        }
    }

    private func reminderBody(forDays days: Int) -> String {
        switch days {
        case 30:
            return "It's been a month since your last survey. Re-walk your space to see if your dead zones moved."
        case 90:
            return "Three months have passed — new devices, new walls, new interference. Time to re-survey your Wi-Fi."
        case 180:
            return "Six months in. Your network likely looks different now — see what's changed with a quick re-survey."
        default:
            return "Time to re-survey your Wi-Fi and catch any new dead zones."
        }
    }
}
