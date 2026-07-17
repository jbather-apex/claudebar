import Foundation
import UserNotifications

/// Posts a macOS notification when a session starts waiting on the user.
/// Requires a real .app bundle; degrades to a no-op under `swift run`.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private var lastNotified: [String: Date] = [:]

    private var available: Bool { Bundle.main.bundleIdentifier != nil }

    func requestAuthorization() {
        guard available else {
            NSLog("ClaudeBar: no bundle identifier — notifications disabled (run the .app bundle)")
            return
        }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notifyAttention(session: ClaudeSession) {
        guard available else { return }
        // Debounce per session: one notification per waiting episode.
        if let last = lastNotified[session.sessionId],
           let since = session.waitingSince, last >= since {
            return
        }
        lastNotified[session.sessionId] = Date()

        let content = UNMutableNotificationContent()
        content.title = session.displayTitle
        content.subtitle = session.state == .needsPermission
            ? "Needs permission" : "Waiting for input"
        content.body = session.message ?? session.displayCwd
        content.sound = .default
        content.userInfo = ["pid": Int(session.pid ?? 0)]

        let request = UNNotificationRequest(
            identifier: "claudebar-\(session.sessionId)",
            content: content,
            trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // Show banners even while the app is "frontmost" (menu bar apps usually are not, but be safe).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    // Clicking the notification jumps to the session's terminal.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let pid = response.notification.request.content.userInfo["pid"] as? Int ?? 0
        if pid > 0 {
            TerminalJumper.jump(toPid: Int32(pid))
        }
        completionHandler()
    }
}
