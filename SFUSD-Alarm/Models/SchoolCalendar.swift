import Foundation

struct SchoolCalendarEvent: Identifiable, Codable {
    var id: String
    var summary: String
    var startDate: Date
    var endDate: Date
    var isAllDay: Bool

    var isHoliday: Bool {
        let lowercased = summary.lowercased()
        return lowercased.contains("holiday") ||
               lowercased.contains("recess") ||
               lowercased.contains("break") ||
               lowercased.contains("no school") ||
               lowercased.contains("closed")
    }
}

struct SchoolCalendar: Codable {
    var events: [SchoolCalendarEvent]
    var lastUpdated: Date

    // School year dates for 2025-2026
    static let schoolYearStart = Calendar.current.date(from: DateComponents(year: 2025, month: 8, day: 18))!
    static let schoolYearEnd = Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 3))!

    init(events: [SchoolCalendarEvent] = [], lastUpdated: Date = Date()) {
        self.events = events
        self.lastUpdated = lastUpdated
    }

    func isSchoolDay(_ date: Date) -> Bool {
        let calendar = Calendar.current

        // Check if it's a weekend
        let weekday = calendar.component(.weekday, from: date)
        if weekday == 1 || weekday == 7 { // Sunday = 1, Saturday = 7
            return false
        }

        // Check if date is within school year
        let startOfDay = calendar.startOfDay(for: date)
        if startOfDay < Self.schoolYearStart || startOfDay > Self.schoolYearEnd {
            return false
        }

        // Check if it's a holiday or break
        for event in events {
            if event.isHoliday {
                let eventStart = calendar.startOfDay(for: event.startDate)
                let eventEnd = calendar.startOfDay(for: event.endDate)

                if startOfDay >= eventStart && startOfDay <= eventEnd {
                    return false
                }
            }
        }

        return true
    }

    func nextSchoolDay(after date: Date = Date()) -> Date? {
        let calendar = Calendar.current
        var currentDate = calendar.startOfDay(for: date)

        // If it's already past the alarm time today, start from tomorrow
        if date > currentDate {
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }

        // Look up to 366 days ahead (accounts for leap years)
        for _ in 0..<366 {
            if isSchoolDay(currentDate) {
                return currentDate
            }
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }

        return nil
    }

    func schoolDays(from startDate: Date, count: Int) -> [Date] {
        var schoolDays: [Date] = []
        let calendar = Calendar.current
        var currentDate = calendar.startOfDay(for: startDate)

        while schoolDays.count < count {
            if isSchoolDay(currentDate) {
                schoolDays.append(currentDate)
            }
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!

            // Safety limit
            if currentDate > Self.schoolYearEnd {
                break
            }
        }

        return schoolDays
    }

    func nonSchoolDays(in month: Date) -> [Date] {
        let calendar = Calendar.current
        let range = calendar.range(of: .day, in: .month, for: month)!
        let components = calendar.dateComponents([.year, .month], from: month)

        var nonSchoolDays: [Date] = []

        for day in range {
            var dayComponents = components
            dayComponents.day = day
            if let date = calendar.date(from: dayComponents), !isSchoolDay(date) {
                nonSchoolDays.append(date)
            }
        }

        return nonSchoolDays
    }
}
