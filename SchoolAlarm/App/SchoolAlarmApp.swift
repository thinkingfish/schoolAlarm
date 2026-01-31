import SwiftUI
import AlarmKit
import UserNotifications

@main
struct SchoolAlarmApp: App {
    @StateObject private var alarmStore = AlarmStore()
    @StateObject private var calendarService = CalendarService()
    @StateObject private var overrideStore = OverrideStore()
    @StateObject private var districtStore = DistrictStore()
    @StateObject private var deepLinkManager = DeepLinkManager.shared
    @Environment(\.scenePhase) private var scenePhase

    /// Track last reschedule to avoid redundant work
    @AppStorage("lastAlarmReschedule") private var lastRescheduleTimestamp: Double = 0

    init() {
        DeepLinkManager.shared.setupNotificationDelegate()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if districtStore.hasSelectedDistrict {
                    ContentView()
                        .environmentObject(alarmStore)
                        .environmentObject(calendarService)
                        .environmentObject(overrideStore)
                        .environmentObject(districtStore)
                        .environmentObject(deepLinkManager)
                        .onAppear {
                            Task {
                                _ = await AlarmKitManager.shared.requestAuthorization()
                                if let district = districtStore.selectedDistrict {
                                    await calendarService.loadCalendar(for: district)
                                    scheduleHolidayReminder(district: district)
                                }
                                rescheduleAlarmsIfNeeded(force: true)
                            }
                        }
                        .onChange(of: scenePhase) { _, newPhase in
                            if newPhase == .active {
                                clearBadgeCount()
                                rescheduleAlarmsIfNeeded(force: false)
                            }
                        }
                } else {
                    OnboardingView {
                        // District selected, app will re-render showing ContentView
                    }
                    .environmentObject(districtStore)
                }
            }
        }
    }

    /// Reschedule alarms only if needed (throttled to reduce memory churn)
    /// - Parameter force: If true, always reschedule (used on cold start)
    private func rescheduleAlarmsIfNeeded(force: Bool) {
        guard let district = districtStore.selectedDistrict else { return }

        let now = Date()
        let lastReschedule = Date(timeIntervalSince1970: lastRescheduleTimestamp)

        // Skip if we rescheduled recently (within 1 hour) and it's the same day
        if !force {
            let hoursSinceReschedule = now.timeIntervalSince(lastReschedule) / 3600
            let calendar = Calendar.current
            let sameDay = calendar.isDate(now, inSameDayAs: lastReschedule)

            if hoursSinceReschedule < 1 && sameDay {
                return
            }
        }

        lastRescheduleTimestamp = now.timeIntervalSince1970

        AlarmKitManager.shared.rescheduleAllAlarms(
            alarmStore: alarmStore,
            calendarService: calendarService,
            overrideStore: overrideStore,
            district: district
        )
    }

    private func clearBadgeCount() {
        Task {
            try? await UNUserNotificationCenter.current().setBadgeCount(0)
        }
    }

    private func scheduleHolidayReminder(district: District) {
        guard let holiday = calendarService.nextHoliday(district: district) else { return }

        // Format the date
        let dateString = Formatters.monthDay.string(from: holiday.startDate)

        // Create notification content
        let content = UNMutableNotificationContent()
        content.title = "Upcoming School Holiday"
        content.body = "Reminder: \(dateString) is \(holiday.summary), no school!"
        content.sound = .default

        // Schedule for 9 AM on the day before the holiday
        let calendar = Calendar.current
        guard let reminderDate = calendar.date(byAdding: .day, value: -1, to: holiday.startDate) else { return }
        var components = calendar.dateComponents([.year, .month, .day], from: reminderDate)
        components.hour = 9
        components.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: "holiday-reminder",
            content: content,
            trigger: trigger
        )

        // Remove any existing reminder and schedule new one
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["holiday-reminder"])
        center.add(request) { error in
            if let error {
                print("Failed to schedule holiday reminder: \(error)")
            }
        }
    }
}
