import ClaudeStatusCore
import Foundation
import os
import UserNotifications

/// Needs a real app bundle: `UNUserNotificationCenter.current()` crashes in a bare executable.
final class UserNotificationsNotifier: NSObject, Notifying, UNUserNotificationCenterDelegate, @unchecked Sendable {
    private static let log = Logger(subsystem: "local.ClaudeStatus", category: "notifications")

    func activate() {
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func deliver(_ notifications: [AppNotification]) async {
        let center = UNUserNotificationCenter.current()
        for notification in notifications {
            let content = UNMutableNotificationContent()
            content.title = notification.title
            content.body = notification.body
            if notification.sound { content.sound = .default }

            var trigger: UNNotificationTrigger?
            if let fireAt = notification.fireAt, fireAt.timeIntervalSinceNow > 1 {
                trigger = UNTimeIntervalNotificationTrigger(timeInterval: fireAt.timeIntervalSinceNow, repeats: false)
            }
            do {
                try await center.add(UNNotificationRequest(identifier: notification.key, content: content, trigger: trigger))
                Self.log.info("sent \(notification.key, privacy: .public)")
            } catch {
                Self.log.error("\(notification.key, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // Show banners even while the panel is open.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}
