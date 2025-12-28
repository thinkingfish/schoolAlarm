import Foundation
import UserNotifications
import AVFoundation

class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    @Published var isAuthorized: Bool = false
    @Published var pendingNotificationCount: Int = 0

    private let maxNotifications = 60 // iOS limit is 64, leave some buffer
    private let notificationsPerAlarm = 3 // Chain 3 notifications for ~90 seconds of sound
    private let chainIntervalSeconds: TimeInterval = 30 // Seconds between chained notifications
    private let snoozeMinutes = 5
    #if DEBUG
    private let testSnoozeSeconds: TimeInterval = 15
    #endif

    // Audio player for sound preview
    private var previewPlayer: AVAudioPlayer?

    // Notification category and action identifiers
    static let alarmCategoryIdentifier = "ALARM_CATEGORY"
    #if DEBUG
    static let testAlarmCategoryIdentifier = "TEST_ALARM_CATEGORY"
    #endif
    static let snoozeActionIdentifier = "SNOOZE_ACTION"
    static let dismissActionIdentifier = "DISMISS_ACTION"

    private init() {
        checkAuthorizationStatus()
        registerNotificationCategory()
    }

    private func registerNotificationCategory() {
        let snoozeAction = UNNotificationAction(
            identifier: Self.snoozeActionIdentifier,
            title: "Snooze (5 min)",
            options: []
        )

        let dismissAction = UNNotificationAction(
            identifier: Self.dismissActionIdentifier,
            title: "Dismiss",
            options: [.destructive]
        )

        let alarmCategory = UNNotificationCategory(
            identifier: Self.alarmCategoryIdentifier,
            actions: [snoozeAction, dismissAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        #if DEBUG
        let testSnoozeAction = UNNotificationAction(
            identifier: Self.snoozeActionIdentifier,
            title: "Snooze (15 sec)",
            options: []
        )

        let testAlarmCategory = UNNotificationCategory(
            identifier: Self.testAlarmCategoryIdentifier,
            actions: [testSnoozeAction, dismissAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        UNUserNotificationCenter.current().setNotificationCategories([alarmCategory, testAlarmCategory])
        #else
        UNUserNotificationCenter.current().setNotificationCategories([alarmCategory])
        #endif
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, error in
            DispatchQueue.main.async {
                self?.isAuthorized = granted
                if let error = error {
                    print("Notification authorization error: \(error)")
                } else {
                    print("Notification authorization granted: \(granted)")
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
            content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: "\(alarm.alarmSoundName).caf"))
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

    /// Cancel alarm notifications but preserve snooze notifications
    private func cancelAlarmNotificationsPreservingSnooze(completion: @escaping () -> Void) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            // Cancel all notifications EXCEPT snooze notifications (preserve user's snooze)
            let nonSnoozeIdentifiers = requests
                .filter { !$0.identifier.hasPrefix("snooze_") }
                .map { $0.identifier }
            center.removePendingNotificationRequests(withIdentifiers: nonSnoozeIdentifiers)
            DispatchQueue.main.async {
                completion()
            }
        }
    }

    /// Schedule alarms for upcoming school days, respecting overrides
    /// Schedules chained notifications (3 per alarm, 30s apart) for ~90 seconds of sound
    /// - Parameters:
    ///   - baseAlarm: The base alarm (optional)
    ///   - schoolDays: List of upcoming school days
    ///   - overrideStore: The override store for resolution
    func scheduleAlarmsWithOverrides(
        baseAlarm: Alarm?,
        on schoolDays: [Date],
        overrideStore: OverrideStore
    ) {
        // Cancel all existing alarm notifications first, then schedule new ones
        cancelAlarmNotificationsPreservingSnooze { [weak self] in
            self?.doScheduleAlarmsWithOverrides(baseAlarm: baseAlarm, on: schoolDays, overrideStore: overrideStore)
        }
    }

    private func doScheduleAlarmsWithOverrides(
        baseAlarm: Alarm?,
        on schoolDays: [Date],
        overrideStore: OverrideStore
    ) {

        guard overrideStore.allAlarmsEnabled else {
            updatePendingCount()
            return
        }

        let center = UNUserNotificationCenter.current()

        // Calculate max school days we can schedule (each day uses notificationsPerAlarm slots)
        let maxDays = maxNotifications / notificationsPerAlarm
        var scheduledDays = 0

        for schoolDay in schoolDays {
            guard scheduledDays < maxDays else { break }

            // Get effective alarm time using override resolution
            guard let alarmTime = overrideStore.effectiveAlarmTime(for: schoolDay, baseAlarm: baseAlarm) else {
                continue  // Skip this day (disabled or no alarm)
            }

            let soundName = baseAlarm?.alarmSoundName ?? Alarm.BundledSound.funnyRing.rawValue
            let alarmLabel = baseAlarm?.label.isEmpty == false ? baseAlarm!.label : "School Day Alarm"
            let schoolDayTimestamp = schoolDay.timeIntervalSince1970

            // Schedule chained notifications
            for chainIndex in 0..<notificationsPerAlarm {
                let chainedTime = alarmTime.addingTimeInterval(Double(chainIndex) * chainIntervalSeconds)

                let content = UNMutableNotificationContent()
                content.title = alarmLabel
                content.body = chainIndex == 0 ? "Time to get ready for school!" : "Still time to wake up!"
                content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: "\(soundName).caf"))
                content.badge = 1
                content.categoryIdentifier = Self.alarmCategoryIdentifier
                // Note: .timeSensitive requires paid Apple Developer account entitlement
                // content.interruptionLevel = .timeSensitive
                content.userInfo = [
                    "alarmId": baseAlarm?.id.uuidString ?? "override",
                    "schoolDay": schoolDayTimestamp,
                    "chainIndex": chainIndex,
                    "soundName": soundName,
                    "snoozeEnabled": baseAlarm?.snoozeEnabled ?? true
                ]

                let trigger = UNCalendarNotificationTrigger(
                    dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: chainedTime),
                    repeats: false
                )
                let identifier = "alarm_\(schoolDayTimestamp)_chain\(chainIndex)"
                let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

                center.add(request) { error in
                    if let error = error {
                        print("Failed to schedule notification: \(error)")
                    }
                }
            }

            scheduledDays += 1
        }

        updatePendingCount()
    }

    /// Reschedule all alarms (call when any override or alarm changes)
    @MainActor
    func rescheduleAllAlarms(
        alarmStore: AlarmStore,
        calendarService: CalendarService,
        overrideStore: OverrideStore
    ) {
        let schoolDays = calendarService.upcomingSchoolDays()
        let baseAlarm = alarmStore.alarms.first  // Single base alarm model
        scheduleAlarmsWithOverrides(baseAlarm: baseAlarm, on: schoolDays, overrideStore: overrideStore)
    }

    func updatePendingCount() {
        UNUserNotificationCenter.current().getPendingNotificationRequests { [weak self] requests in
            DispatchQueue.main.async {
                self?.pendingNotificationCount = requests.count
            }
        }
    }

    func snoozeAlarm(_ alarm: Alarm) {
        let center = UNUserNotificationCenter.current()

        let content = UNMutableNotificationContent()
        content.title = alarm.label.isEmpty ? "School Day Alarm" : alarm.label
        content.body = "Snooze ended - Time to get up!"
        content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: "\(alarm.alarmSoundName).caf"))
        content.badge = 1
        content.categoryIdentifier = Self.alarmCategoryIdentifier
        content.userInfo = [
            "alarmId": alarm.id.uuidString,
            "isSnooze": true,
            "soundName": alarm.alarmSoundName,
            "snoozeEnabled": alarm.snoozeEnabled
        ]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(snoozeMinutes * 60), repeats: false)
        let identifier = "\(alarm.id.uuidString)_snooze_\(Date().timeIntervalSince1970)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        center.add(request)
    }

    /// Schedule a snooze notification from notification userInfo (used by notification action handler)
    func scheduleSnoozeFromNotification(userInfo: [AnyHashable: Any], title: String) {
        guard let snoozeEnabled = userInfo["snoozeEnabled"] as? Bool, snoozeEnabled else {
            return // Snooze not enabled for this alarm
        }

        let center = UNUserNotificationCenter.current()
        let soundName = userInfo["soundName"] as? String ?? Alarm.BundledSound.funnyRing.rawValue

        // Check if this is a test notification (DEBUG only)
        #if DEBUG
        let isTest = userInfo["isTest"] as? Bool ?? false
        let snoozeInterval: TimeInterval = isTest ? testSnoozeSeconds : TimeInterval(snoozeMinutes * 60)
        let snoozeBody = isTest ? "Test snooze ended!" : "Snooze ended - Time to get up!"
        let categoryId = isTest ? Self.testAlarmCategoryIdentifier : Self.alarmCategoryIdentifier
        #else
        let snoozeInterval: TimeInterval = TimeInterval(snoozeMinutes * 60)
        let snoozeBody = "Snooze ended - Time to get up!"
        let categoryId = Self.alarmCategoryIdentifier
        #endif

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = snoozeBody
        content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: "\(soundName).caf"))
        content.badge = 1
        content.categoryIdentifier = categoryId
        // Note: .timeSensitive requires paid Apple Developer account entitlement
        // content.interruptionLevel = .timeSensitive
        content.userInfo = userInfo // Preserve original userInfo for subsequent snoozes

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: snoozeInterval, repeats: false)
        let identifier = "snooze_\(Date().timeIntervalSince1970)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        center.add(request) { error in
            if let error = error {
                print("Failed to schedule snooze: \(error)")
            } else {
                print("✅ Snooze scheduled: \(snoozeInterval)s from now")
            }
        }
    }

    /// Cancel remaining chained notifications for a specific school day
    func cancelChainedNotifications(for schoolDayTimestamp: TimeInterval) {
        let center = UNUserNotificationCenter.current()
        var identifiersToRemove: [String] = []

        for chainIndex in 0..<notificationsPerAlarm {
            identifiersToRemove.append("alarm_\(schoolDayTimestamp)_chain\(chainIndex)")
        }

        center.removePendingNotificationRequests(withIdentifiers: identifiersToRemove)
    }

    func playPreviewSound(for sound: Alarm.BundledSound) {
        // Stop any currently playing preview
        stopPreviewSound()

        guard let soundURL = Bundle.main.url(forResource: sound.rawValue, withExtension: "caf") else {
            // Fallback to default alert sound
            AudioServicesPlayAlertSound(SystemSoundID(1005))
            return
        }

        do {
            previewPlayer = try AVAudioPlayer(contentsOf: soundURL)
            previewPlayer?.play()
        } catch {
            print("Failed to play preview sound: \(error)")
        }
    }

    func stopPreviewSound() {
        previewPlayer?.stop()
        previewPlayer = nil
    }

    #if DEBUG
    /// Cancel only test notifications (preserves real scheduled alarms)
    func cancelTestNotifications() {
        let center = UNUserNotificationCenter.current()

        center.getPendingNotificationRequests { [weak self] requests in
            let testIdentifiers = requests
                .filter { $0.identifier.hasPrefix("test_") || $0.identifier.hasPrefix("snooze_") }
                .map { $0.identifier }

            center.removePendingNotificationRequests(withIdentifiers: testIdentifiers)
            print("Cancelled \(testIdentifiers.count) test notifications")
            self?.updatePendingCount()
        }
    }

    /// Schedule chained test notifications (same as real alarms - 3 notifications, 30s apart)
    func scheduleTestNotification(delaySeconds: TimeInterval, soundName: String = Alarm.BundledSound.funnyRing.rawValue) {
        let center = UNUserNotificationCenter.current()
        let testTimestamp = Date().timeIntervalSince1970

        // Schedule chained notifications just like real alarms
        for chainIndex in 0..<notificationsPerAlarm {
            let chainedDelay = delaySeconds + (Double(chainIndex) * chainIntervalSeconds)

            let content = UNMutableNotificationContent()
            content.title = "Test Alarm"
            content.body = chainIndex == 0 ? "This is a test notification!" : "Still ringing! (\(chainIndex + 1)/\(notificationsPerAlarm))"
            content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: "\(soundName).caf"))
            content.badge = 1
            content.categoryIdentifier = Self.testAlarmCategoryIdentifier
            // Note: .timeSensitive requires paid Apple Developer account entitlement
            // content.interruptionLevel = .timeSensitive
            content.userInfo = [
                "alarmId": "test",
                "isTest": true,
                "soundName": soundName,
                "snoozeEnabled": true,
                "testTimestamp": testTimestamp,
                "chainIndex": chainIndex
            ]

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: chainedDelay, repeats: false)
            let identifier = "test_\(testTimestamp)_chain\(chainIndex)"
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

            center.add(request) { error in
                if let error = error {
                    print("Failed to schedule test notification chain \(chainIndex): \(error)")
                } else if chainIndex == 0 {
                    let fireDate = Date().addingTimeInterval(delaySeconds)
                    let formatter = DateFormatter()
                    formatter.dateFormat = "HH:mm:ss"
                    print("✅ Test alarm scheduled (3 chained notifications, 30s apart)")
                    print("   First fire: \(formatter.string(from: fireDate)) (\(delaySeconds)s from now)")
                    print("   Sound: \(soundName).caf")
                    print("   Total duration: ~\(self.notificationsPerAlarm * Int(self.chainIntervalSeconds))s")
                }
            }
        }

        updatePendingCount()
    }

    /// Cancel chained test notifications for a specific test
    func cancelTestChain(testTimestamp: TimeInterval) {
        let center = UNUserNotificationCenter.current()
        var identifiersToRemove: [String] = []

        for chainIndex in 0..<notificationsPerAlarm {
            identifiersToRemove.append("test_\(testTimestamp)_chain\(chainIndex)")
        }

        center.removePendingNotificationRequests(withIdentifiers: identifiersToRemove)
    }

    /// Get pending notification counts grouped by date
    func getPendingNotificationsByDate(completion: @escaping ([Date: Int]) -> Void) {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            var countsByDate: [Date: Int] = [:]
            let calendar = Calendar.current

            for request in requests {
                if let trigger = request.trigger as? UNCalendarNotificationTrigger,
                   let triggerDate = trigger.nextTriggerDate() {
                    let dayStart = calendar.startOfDay(for: triggerDate)
                    countsByDate[dayStart, default: 0] += 1
                }
            }

            DispatchQueue.main.async {
                completion(countsByDate)
            }
        }
    }
    #endif
}
