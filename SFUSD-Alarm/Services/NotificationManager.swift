import Foundation
import UserNotifications
import AVFoundation

class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    @Published var isAuthorized: Bool = false
    @Published var pendingNotificationCount: Int = 0

    private let maxNotifications = 60 // iOS limit is 64, leave some buffer

    private init() {
        checkAuthorizationStatus()
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, error in
            DispatchQueue.main.async {
                self?.isAuthorized = granted
                if let error = error {
                    print("Notification authorization error: \(error)")
                }
            }
        }
    }

    func checkAuthorizationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                self?.isAuthorized = settings.authorizationStatus == .authorized
            }
        }
    }

    func scheduleAlarms(for alarm: Alarm, on schoolDays: [Date]) {
        guard alarm.isEnabled else {
            cancelNotifications(for: alarm)
            return
        }

        // Cancel existing notifications for this alarm first
        cancelNotifications(for: alarm)

        let center = UNUserNotificationCenter.current()
        let calendar = Calendar.current

        // Schedule notifications for upcoming school days (up to maxNotifications)
        let daysToSchedule = Array(schoolDays.prefix(maxNotifications))

        for schoolDay in daysToSchedule {
            var dateComponents = calendar.dateComponents([.year, .month, .day], from: schoolDay)
            dateComponents.hour = alarm.hour
            dateComponents.minute = alarm.minute

            let content = UNMutableNotificationContent()
            content.title = alarm.label.isEmpty ? "School Day Alarm" : alarm.label
            content.body = "Time to get ready for school!"
            content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: "\(alarm.sound.systemSoundName).caf"))
            content.badge = 1
            content.userInfo = ["alarmId": alarm.id.uuidString]

            // Use calendar-based trigger for exact date/time
            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)

            let identifier = "\(alarm.id.uuidString)_\(schoolDay.timeIntervalSince1970)"
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

            center.add(request) { error in
                if let error = error {
                    print("Failed to schedule notification: \(error)")
                }
            }
        }

        updatePendingCount()
    }

    func cancelNotifications(for alarm: Alarm) {
        let center = UNUserNotificationCenter.current()

        center.getPendingNotificationRequests { requests in
            let identifiersToRemove = requests
                .filter { $0.identifier.hasPrefix(alarm.id.uuidString) }
                .map { $0.identifier }

            center.removePendingNotificationRequests(withIdentifiers: identifiersToRemove)
            self.updatePendingCount()
        }
    }

    func cancelAllNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        updatePendingCount()
    }

    func updatePendingCount() {
        UNUserNotificationCenter.current().getPendingNotificationRequests { [weak self] requests in
            DispatchQueue.main.async {
                self?.pendingNotificationCount = requests.count
            }
        }
    }

    func snoozeAlarm(_ alarm: Alarm, minutes: Int = 9) {
        let center = UNUserNotificationCenter.current()

        let content = UNMutableNotificationContent()
        content.title = alarm.label.isEmpty ? "School Day Alarm" : alarm.label
        content.body = "Snooze ended - Time to get up!"
        content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: "\(alarm.sound.systemSoundName).caf"))
        content.badge = 1
        content.userInfo = ["alarmId": alarm.id.uuidString, "isSnooze": true]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(minutes * 60), repeats: false)
        let identifier = "\(alarm.id.uuidString)_snooze_\(Date().timeIntervalSince1970)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        center.add(request)
    }

    func playPreviewSound(for sound: AlarmSound) {
        // Try to play the system sound
        let soundName = sound.systemSoundName
        if let soundURL = Bundle.main.url(forResource: soundName, withExtension: "caf") {
            var soundID: SystemSoundID = 0
            AudioServicesCreateSystemSoundID(soundURL as CFURL, &soundID)
            AudioServicesPlaySystemSound(soundID)
        } else {
            // Fallback to default alert sound
            AudioServicesPlayAlertSound(SystemSoundID(1005))
        }
    }
}
