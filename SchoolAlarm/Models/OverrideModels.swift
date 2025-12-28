import Foundation

/// What an override does to the alarm
enum OverrideAction: Codable, Equatable {
    case disable
    case customTime(Date)

    /// Extract hour/minute from customTime for display
    var hour: Int? {
        guard case .customTime(let date) = self else { return nil }
        return Calendar.current.component(.hour, from: date)
    }

    var minute: Int? {
        guard case .customTime(let date) = self else { return nil }
        return Calendar.current.component(.minute, from: date)
    }

    var timeString: String? {
        guard case .customTime(let date) = self else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}

/// Weekly recurring rule (e.g., "every Tuesday at 7:45 AM")
struct WeeklyRule: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var weekday: Int  // 1=Sunday, 2=Monday, ... 7=Saturday
    var action: OverrideAction

    var weekdayName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        var components = DateComponents()
        components.weekday = weekday
        let date = Calendar.current.nextDate(after: Date(), matching: components, matchingPolicy: .nextTime)!
        return formatter.string(from: date)
    }

    var shortWeekdayName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        var components = DateComponents()
        components.weekday = weekday
        let date = Calendar.current.nextDate(after: Date(), matching: components, matchingPolicy: .nextTime)!
        return formatter.string(from: date)
    }
}

/// One-time override for a specific date
struct DateOverride: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var date: Date  // Day precision (start of day)
    var action: OverrideAction

    var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: date)
    }
}
