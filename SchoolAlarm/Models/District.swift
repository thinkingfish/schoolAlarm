import Foundation

struct District: Identifiable, Codable, Hashable {
    let id: String                    // e.g., "sfusd"
    let name: String                  // e.g., "San Francisco Unified School District"
    let shortName: String             // e.g., "SFUSD"
    let calendarURL: String           // ICS feed URL
    let schoolYearStart: DateComponents  // e.g., month: 8, day: 18
    let schoolYearEnd: DateComponents    // e.g., month: 6, day: 3
    let timezone: String              // e.g., "America/Los_Angeles"

    /// Resolves school year start for a given year
    func schoolYearStartDate(year: Int) -> Date {
        var components = schoolYearStart
        components.year = year
        let tz = TimeZone(identifier: timezone) ?? .current
        var calendar = Calendar.current
        calendar.timeZone = tz
        return calendar.date(from: components) ?? Date()
    }

    /// Resolves school year end for a given year (typically year + 1)
    func schoolYearEndDate(year: Int) -> Date {
        var components = schoolYearEnd
        components.year = year + 1  // School year spans two calendar years
        let tz = TimeZone(identifier: timezone) ?? .current
        var calendar = Calendar.current
        calendar.timeZone = tz
        return calendar.date(from: components) ?? Date()
    }
}
