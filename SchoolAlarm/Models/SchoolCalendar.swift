import Foundation

struct SchoolCalendarEvent: Identifiable, Codable {
    var id: String
    var summary: String
    var startDate: Date
    var endDate: Date
    var isAllDay: Bool

    /// Returns true if this event closes school (must be all-day + holiday keywords)
    var isHoliday: Bool {
        guard isAllDay else { return false }
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
    var districtId: String?

    init(events: [SchoolCalendarEvent] = [], lastUpdated: Date = Date(), districtId: String? = nil) {
        self.events = events
        self.lastUpdated = lastUpdated
        self.districtId = districtId
    }

    /// Determines the school year start year for a given date
    /// If month >= 8 (Aug-Dec), we're in first half of school year starting this year
    /// If month < 8 (Jan-Jul), we're in second half of school year that started last year
    private func schoolYearStartYear(for date: Date) -> Int {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        return month >= 8 ? year : year - 1
    }

    func isSchoolDay(_ date: Date, district: District) -> Bool {
        let calendar = Calendar.current

        // Check if it's a weekend
        let weekday = calendar.component(.weekday, from: date)
        if weekday == 1 || weekday == 7 {
            return false
        }

        // Get school year boundaries for this date
        let startYear = schoolYearStartYear(for: date)
        let schoolYearStart = district.schoolYearStartDate(year: startYear)
        let schoolYearEnd = district.schoolYearEndDate(year: startYear)

        // Check if date is within school year
        let startOfDay = calendar.startOfDay(for: date)
        if startOfDay < schoolYearStart || startOfDay > schoolYearEnd {
            return false
        }

        // Check if it's a holiday or break
        for event in events where event.isHoliday {
            let eventStart = calendar.startOfDay(for: event.startDate)
            let eventEnd = calendar.startOfDay(for: event.endDate)

            if startOfDay >= eventStart && startOfDay < eventEnd {
                return false
            }
        }

        return true
    }

    func nextSchoolDay(after date: Date = Date(), district: District) -> Date? {
        let calendar = Calendar.current
        var currentDate = calendar.startOfDay(for: date)

        if date > currentDate {
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }

        for _ in 0..<366 {
            if isSchoolDay(currentDate, district: district) {
                return currentDate
            }
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }

        return nil
    }

    func schoolDays(from startDate: Date, count: Int, district: District) -> [Date] {
        var schoolDays: [Date] = []
        let calendar = Calendar.current
        var currentDate = calendar.startOfDay(for: startDate)

        let startYear = schoolYearStartYear(for: startDate)
        let schoolYearEnd = district.schoolYearEndDate(year: startYear)

        while schoolDays.count < count {
            if isSchoolDay(currentDate, district: district) {
                schoolDays.append(currentDate)
            }
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!

            if currentDate > schoolYearEnd {
                break
            }
        }

        return schoolDays
    }

    func nonSchoolDays(in month: Date, district: District) -> [Date] {
        let calendar = Calendar.current
        let range = calendar.range(of: .day, in: .month, for: month)!
        let components = calendar.dateComponents([.year, .month], from: month)

        var nonSchoolDays: [Date] = []

        for day in range {
            var dayComponents = components
            dayComponents.day = day
            if let date = calendar.date(from: dayComponents), !isSchoolDay(date, district: district) {
                nonSchoolDays.append(date)
            }
        }

        return nonSchoolDays
    }
}
