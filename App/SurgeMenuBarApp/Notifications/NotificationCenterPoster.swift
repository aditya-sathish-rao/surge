import Foundation
import UserNotifications

/// Posts the alerts the planner chose and asks for permission once.
///
/// Notifications are local: nothing here talks to a network. An alert never carries prompt or
/// response content, only the model, workspace name and state.
@MainActor
final class NotificationCenterPoster: NSObject, UNUserNotificationCenterDelegate {
    private var hasRequestedAuthorization = false

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorization() async {
        guard !hasRequestedAuthorization else { return }
        hasRequestedAuthorization = true
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    func post(_ alert: AgentAlert) {
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        content.interruptionLevel = Self.interruptionLevel(alert.level)
        content.sound = alert.level == .passive ? nil : .default
        let request = UNNotificationRequest(identifier: alert.identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        notification.request.content.interruptionLevel == .passive ? [.list] : [.banner, .list, .sound]
    }

    private static func interruptionLevel(_ level: AlertLevel) -> UNNotificationInterruptionLevel {
        switch level {
        case .active: .active
        case .timeSensitive: .timeSensitive
        case .passive: .passive
        }
    }
}
