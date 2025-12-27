import Foundation
import Combine

class OverrideStore: ObservableObject {
    @Published var weeklyRules: [WeeklyRule] = []
    @Published var dateOverrides: [DateOverride] = []
    @Published var allAlarmsEnabled: Bool = true

    private let weeklyRulesKey = "WeeklyRules"
    private let dateOverridesKey = "DateOverrides"
    private let allAlarmsEnabledKey = "AllAlarmsEnabled"

    init() {
        load()
    }

    // MARK: - Persistence

    func load() {
        if let data = UserDefaults.standard.data(forKey: weeklyRulesKey),
           let decoded = try? JSONDecoder().decode([WeeklyRule].self, from: data) {
            weeklyRules = decoded
        }

        if let data = UserDefaults.standard.data(forKey: dateOverridesKey),
           let decoded = try? JSONDecoder().decode([DateOverride].self, from: data) {
            dateOverrides = decoded
        }

        allAlarmsEnabled = UserDefaults.standard.object(forKey: allAlarmsEnabledKey) as? Bool ?? true

        // Auto-cleanup past date overrides
        cleanupPastOverrides()
    }

    func save() {
        if let encoded = try? JSONEncoder().encode(weeklyRules) {
            UserDefaults.standard.set(encoded, forKey: weeklyRulesKey)
        }
        if let encoded = try? JSONEncoder().encode(dateOverrides) {
            UserDefaults.standard.set(encoded, forKey: dateOverridesKey)
        }
        UserDefaults.standard.set(allAlarmsEnabled, forKey: allAlarmsEnabledKey)
    }

    private func cleanupPastOverrides() {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let beforeCount = dateOverrides.count
        dateOverrides.removeAll { $0.date < startOfToday }
        if dateOverrides.count != beforeCount {
            save()
        }
    }

    // MARK: - Weekly Rules CRUD

    func addWeeklyRule(_ rule: WeeklyRule) {
        // Prevent duplicates for same weekday
        guard !weeklyRules.contains(where: { $0.weekday == rule.weekday }) else { return }
        weeklyRules.append(rule)
        weeklyRules.sort { $0.weekday < $1.weekday }
        save()
    }

    func updateWeeklyRule(_ rule: WeeklyRule) {
        if let index = weeklyRules.firstIndex(where: { $0.id == rule.id }) {
            weeklyRules[index] = rule
            save()
        }
    }

    func deleteWeeklyRule(_ rule: WeeklyRule) {
        weeklyRules.removeAll { $0.id == rule.id }
        save()
    }

    func weeklyRule(for weekday: Int) -> WeeklyRule? {
        weeklyRules.first { $0.weekday == weekday }
    }

    // MARK: - Date Overrides CRUD

    func addDateOverride(_ override: DateOverride) {
        // Prevent duplicates for same date
        let startOfDay = Calendar.current.startOfDay(for: override.date)
        guard !dateOverrides.contains(where: {
            Calendar.current.isDate($0.date, inSameDayAs: startOfDay)
        }) else { return }

        var newOverride = override
        newOverride.date = startOfDay
        dateOverrides.append(newOverride)
        dateOverrides.sort { $0.date < $1.date }
        save()
    }

    func updateDateOverride(_ override: DateOverride) {
        if let index = dateOverrides.firstIndex(where: { $0.id == override.id }) {
            dateOverrides[index] = override
            save()
        }
    }

    func deleteDateOverride(_ override: DateOverride) {
        dateOverrides.removeAll { $0.id == override.id }
        save()
    }

    func dateOverride(for date: Date) -> DateOverride? {
        let startOfDay = Calendar.current.startOfDay(for: date)
        return dateOverrides.first { Calendar.current.isDate($0.date, inSameDayAs: startOfDay) }
    }

    // MARK: - Master Toggle

    func setAllAlarmsEnabled(_ enabled: Bool) {
        allAlarmsEnabled = enabled
        save()
    }

    // MARK: - Resolution

    /// Returns the effective action for a given date (one-time > weekly > nil)
    func effectiveAction(for date: Date) -> OverrideAction? {
        // Priority 1: One-time override
        if let dateOverride = dateOverride(for: date) {
            return dateOverride.action
        }

        // Priority 2: Weekly rule
        let weekday = Calendar.current.component(.weekday, from: date)
        if let weeklyRule = weeklyRule(for: weekday) {
            return weeklyRule.action
        }

        // Priority 3: No override
        return nil
    }

    /// Returns the effective alarm time for a date, or nil if alarm should be skipped
    /// - Parameters:
    ///   - date: The school day to check
    ///   - baseAlarm: The base alarm (optional in hybrid model)
    /// - Returns: The time to schedule the alarm, or nil if disabled/no alarm
    func effectiveAlarmTime(for date: Date, baseAlarm: Alarm?) -> Date? {
        guard allAlarmsEnabled else { return nil }

        let action = effectiveAction(for: date)

        switch action {
        case .disable:
            return nil
        case .customTime(let time):
            // Combine date with custom time
            let calendar = Calendar.current
            var components = calendar.dateComponents([.year, .month, .day], from: date)
            components.hour = calendar.component(.hour, from: time)
            components.minute = calendar.component(.minute, from: time)
            return calendar.date(from: components)
        case nil:
            // Fall back to base alarm
            guard let alarm = baseAlarm, alarm.isEnabled else { return nil }
            let calendar = Calendar.current
            var components = calendar.dateComponents([.year, .month, .day], from: date)
            components.hour = alarm.hour
            components.minute = alarm.minute
            return calendar.date(from: components)
        }
    }

    /// Determines which layer is active for a given date (for color coding)
    func activeLayer(for date: Date) -> AlarmLayer {
        if let _ = dateOverride(for: date) {
            return .oneTime
        }
        let weekday = Calendar.current.component(.weekday, from: date)
        if let _ = weeklyRule(for: weekday) {
            return .weekly
        }
        return .base
    }
}

/// Which layer is providing the alarm for color-coding purposes
enum AlarmLayer {
    case base      // Orange
    case weekly    // Blue
    case oneTime   // Green

    var color: String {
        switch self {
        case .base: return "orange"
        case .weekly: return "blue"
        case .oneTime: return "green"
        }
    }
}
