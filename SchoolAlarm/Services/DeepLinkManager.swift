import Foundation
import UserNotifications

enum DeepLink: Equatable {
    case calendar
}

/// Manages deep linking from notifications
@MainActor
class DeepLinkManager: NSObject, ObservableObject {
    static let shared = DeepLinkManager()

    @Published var pendingDeepLink: DeepLink?

    override private init() {
        super.init()
    }

    func setupNotificationDelegate() {
        UNUserNotificationCenter.current().delegate = self
    }
}

extension DeepLinkManager: UNUserNotificationCenterDelegate {
    // Handle notification when app is in foreground
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    // Handle notification tap
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let identifier = response.notification.request.identifier

        await MainActor.run {
            if identifier == "holiday-reminder" {
                pendingDeepLink = .calendar
            }
        }
    }
}
