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
                                rescheduleAlarms()
                            }
                        }
                        .onChange(of: scenePhase) { _, newPhase in
                            if newPhase == .active {
                                clearBadgeCount()
                                rescheduleAlarms()
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

    private func rescheduleAlarms() {
        guard let district = districtStore.selectedDistrict else { return }
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
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let dateString = formatter.string(from: holiday.startDate)

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
