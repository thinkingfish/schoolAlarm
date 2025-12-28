import SwiftUI
import UserNotifications
import BackgroundTasks

@main
struct SchoolAlarmApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var alarmStore = AlarmStore()
    @StateObject private var calendarService = CalendarService()
    @StateObject private var overrideStore = OverrideStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(alarmStore)
                .environmentObject(calendarService)
                .environmentObject(overrideStore)
                .onAppear {
                    NotificationManager.shared.requestAuthorization()
                    Task {
                        await calendarService.loadCalendar()
                    }
                }
                .onChange(of: scenePhase) { newPhase in
                    if newPhase == .active {
                        // Dismiss any delivered alarm notifications (stops sound)
                        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
                        UNUserNotificationCenter.current().setBadgeCount(0)
                        // Refresh pending notification count (notifications may have fired while backgrounded)
                        NotificationManager.shared.updatePendingCount()
                        rescheduleAlarms()
                    } else if newPhase == .background {
                        scheduleBackgroundRefresh()
                    }
                }
        }
    }

    private func rescheduleAlarms() {
        Task { @MainActor in
            NotificationManager.shared.rescheduleAllAlarms(
                alarmStore: alarmStore,
                calendarService: calendarService,
                overrideStore: overrideStore
            )
        }
    }

    private func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: AppDelegate.backgroundTaskIdentifier)
        // Schedule for when ~50% of notifications have been consumed (about 30 days)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 24 * 60 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("Could not schedule background refresh: \(error)")
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static let backgroundTaskIdentifier = "com.schoolalarm.refresh"

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        UNUserNotificationCenter.current().delegate = self

        // Register background task
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.backgroundTaskIdentifier, using: nil) { task in
            self.handleBackgroundRefresh(task: task as! BGAppRefreshTask)
        }

        return true
    }

    private func handleBackgroundRefresh(task: BGAppRefreshTask) {
        // Reschedule for next time
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 24 * 60 * 60)
        try? BGTaskScheduler.shared.submit(request)

        // Perform the refresh
        Task { @MainActor in
            let alarmStore = AlarmStore()
            let calendarService = CalendarService()
            let overrideStore = OverrideStore()

            await calendarService.loadCalendar()

            NotificationManager.shared.rescheduleAllAlarms(
                alarmStore: alarmStore,
                calendarService: calendarService,
                overrideStore: overrideStore
            )

            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }
    }

    // Handle notification when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }

    // Handle notification tap and actions
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        let title = response.notification.request.content.title

        // Cancel remaining chained notifications for this alarm
        if let schoolDayTimestamp = userInfo["schoolDay"] as? TimeInterval {
            NotificationManager.shared.cancelChainedNotifications(for: schoolDayTimestamp)
        }

        // Cancel remaining chained test notifications
        if let testTimestamp = userInfo["testTimestamp"] as? TimeInterval {
            NotificationManager.shared.cancelTestChain(testTimestamp: testTimestamp)
        }

        switch response.actionIdentifier {
        case NotificationManager.snoozeActionIdentifier:
            // Schedule snooze notification
            NotificationManager.shared.scheduleSnoozeFromNotification(userInfo: userInfo, title: title)

        case NotificationManager.dismissActionIdentifier, UNNotificationDismissActionIdentifier:
            // Just dismiss - chained notifications already cancelled above
            break

        case UNNotificationDefaultActionIdentifier:
            // User tapped the notification - open app
            if let alarmId = userInfo["alarmId"] as? String {
                NotificationCenter.default.post(name: .alarmTriggered, object: nil, userInfo: ["alarmId": alarmId])
            }

        default:
            break
        }

        completionHandler()
    }
}

extension Notification.Name {
    static let alarmTriggered = Notification.Name("alarmTriggered")
}
