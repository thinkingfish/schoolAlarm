import Foundation
import AlarmKit
import SwiftUI

/// Manages alarm scheduling via AlarmKit (iOS 26+)
/// Replaces NotificationManager for true system alarms
class AlarmKitManager: ObservableObject {
    static let shared = AlarmKitManager()

    private let alarmManager = AlarmManager.shared

    /// Track scheduled alarm IDs by date for cancellation
    private var scheduledAlarmsByDate: [Date: UUID] = [:]

    @Published var authorizationState: AlarmManager.AuthorizationState = .notDetermined

    private init() {
        updateAuthorizationState()
    }

    // MARK: - Authorization

    func updateAuthorizationState() {
        authorizationState = alarmManager.authorizationState
    }

    func requestAuthorization() async -> Bool {
        switch alarmManager.authorizationState {
        case .notDetermined:
            do {
                let state = try await alarmManager.requestAuthorization()
                await MainActor.run {
                    self.authorizationState = state
                }
                return state == .authorized
            } catch {
                print("AlarmKit authorization error: \(error)")
                return false
            }
        case .authorized:
            return true
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    // MARK: - Scheduling

    /// Schedule alarms for all upcoming school days
    /// - Parameters:
    ///   - schoolDays: List of upcoming school days from CalendarService
    ///   - overrideStore: Override store for effective time resolution
    ///   - baseAlarm: Base alarm configuration (sound, etc.)
    func scheduleAlarms(
        schoolDays: [Date],
        overrideStore: OverrideStore,
        baseAlarm: Alarm?
    ) async {
        // Cancel all existing alarms first (including orphaned ones)
        await cancelAllAlarms()

        guard overrideStore.allAlarmsEnabled else { return }

        let calendar = Calendar.current
        let soundName = baseAlarm?.alarmSoundName ?? "funny_ring.caf"

        for schoolDay in schoolDays {
            // Get effective alarm time using override resolution
            guard let alarmTime = overrideStore.effectiveAlarmTime(for: schoolDay, baseAlarm: baseAlarm) else {
                continue // Skip this day (disabled or no alarm)
            }

            // Combine school day date with alarm time
            let timeComponents = calendar.dateComponents([.hour, .minute], from: alarmTime)
            guard let alarmDateTime = calendar.date(
                bySettingHour: timeComponents.hour ?? 7,
                minute: timeComponents.minute ?? 0,
                second: 0,
                of: schoolDay
            ) else { continue }

            // Skip if alarm time has already passed
            if alarmDateTime <= Date() {
                continue
            }

            // Schedule the alarm
            await scheduleAlarm(for: alarmDateTime, soundName: soundName)
        }
    }

    /// Schedule a single alarm
    private func scheduleAlarm(for dateTime: Date, soundName: String) async {
        let alarmId = UUID()
        let dayStart = Calendar.current.startOfDay(for: dateTime)

        // Create alarm attributes with presentation
        let alert = AlarmPresentation.Alert(
            title: "School Day Alarm",
            stopButton: AlarmButton(text: "Dismiss", textColor: .white, systemImageName: "xmark.circle"),
            secondaryButton: AlarmButton(text: "Snooze", textColor: .white, systemImageName: "moon.zzz"),
            secondaryButtonBehavior: .countdown
        )
        let presentation = AlarmPresentation(alert: alert, countdown: nil, paused: nil)
        let attributes = AlarmAttributes<SchoolAlarmContentState>(
            presentation: presentation,
            metadata: nil,
            tintColor: .orange
        )

        // Create alarm configuration
        let configuration: AlarmManager.AlarmConfiguration<SchoolAlarmContentState> = .alarm(
            schedule: .fixed(dateTime),
            attributes: attributes,
            stopIntent: nil,
            secondaryIntent: nil,
            sound: .named(soundName)
        )

        do {
            _ = try await alarmManager.schedule(id: alarmId, configuration: configuration) as AlarmKit.Alarm
            scheduledAlarmsByDate[dayStart] = alarmId
        } catch {
            print("Failed to schedule alarm for \(dateTime): \(error)")
        }
    }

    // MARK: - Cancellation

    /// Cancel all scheduled alarms from AlarmKit (both tracked and orphaned from previous sessions)
    func cancelAllAlarms() async {
        // Query all alarms from AlarmKit system and cancel them
        do {
            let allAlarms = try alarmManager.alarms
            for alarm in allAlarms {
                try? alarmManager.cancel(id: alarm.id)
            }
        } catch {
            print("Error fetching alarms to cancel: \(error)")
        }
        scheduledAlarmsByDate.removeAll()
    }

    /// Cancel alarm for a specific date
    func cancelAlarm(for date: Date) {
        let dayStart = Calendar.current.startOfDay(for: date)
        guard let alarmId = scheduledAlarmsByDate[dayStart] else { return }

        try? alarmManager.cancel(id: alarmId)
        scheduledAlarmsByDate.removeValue(forKey: dayStart)
    }

    // MARK: - Convenience

    /// Reschedule all alarms (call when any override or alarm changes)
    @MainActor
    func rescheduleAllAlarms(
        alarmStore: AlarmStore,
        calendarService: CalendarService,
        overrideStore: OverrideStore,
        district: District
    ) {
        // Clean up past one-time overrides
        overrideStore.cleanupPastOverrides()

        let schoolDays = calendarService.upcomingSchoolDays(district: district)
        let baseAlarm = alarmStore.alarms.first

        Task {
            await scheduleAlarms(
                schoolDays: schoolDays,
                overrideStore: overrideStore,
                baseAlarm: baseAlarm
            )
        }
    }
}
