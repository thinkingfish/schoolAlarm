import Foundation
import Combine

@MainActor
class CalendarService: ObservableObject {
    @Published var calendar: SchoolCalendar = SchoolCalendar()
    @Published var isLoading: Bool = false
    @Published var error: String?
    @Published var lastRefresh: Date?

    private func cacheKey(for district: District) -> String {
        "CachedSchoolCalendar_\(district.id)"
    }

    private func lastRefreshKey(for district: District) -> String {
        "LastCalendarRefresh_\(district.id)"
    }

    init() {}

    func loadCalendar(for district: District) async {
        // Load from cache first
        loadCachedCalendar(for: district)

        // Check if we need to refresh (older than 24 hours)
        if shouldRefresh(for: district) {
            await refreshCalendar(for: district)
        }
    }

    func refreshCalendar(for district: District) async {
        isLoading = true
        error = nil

        do {
            guard let url = URL(string: district.calendarURL) else {
                throw CalendarError.invalidURL
            }

            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw CalendarError.networkError
            }

            guard let icsString = String(data: data, encoding: .utf8) else {
                throw CalendarError.parseError
            }

            let events = ICSParser.parse(icsString)
            calendar = SchoolCalendar(events: events, lastUpdated: Date(), districtId: district.id)

            // Cache the calendar
            saveCalendarToCache(for: district)

            lastRefresh = Date()
            UserDefaults.standard.set(lastRefresh, forKey: lastRefreshKey(for: district))

        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    private func loadCachedCalendar(for district: District) {
        let key = cacheKey(for: district)
        if let data = UserDefaults.standard.data(forKey: key),
           let cached = try? JSONDecoder().decode(SchoolCalendar.self, from: data) {
            calendar = cached
        } else {
            calendar = SchoolCalendar(districtId: district.id)
        }

        lastRefresh = UserDefaults.standard.object(forKey: lastRefreshKey(for: district)) as? Date
    }

    private func saveCalendarToCache(for district: District) {
        if let encoded = try? JSONEncoder().encode(calendar) {
            UserDefaults.standard.set(encoded, forKey: cacheKey(for: district))
        }
    }

    private func shouldRefresh(for district: District) -> Bool {
        guard let lastRefresh = UserDefaults.standard.object(forKey: lastRefreshKey(for: district)) as? Date else {
            return true
        }

        let hoursSinceRefresh = Date().timeIntervalSince(lastRefresh) / 3600
        return hoursSinceRefresh > 24
    }

    // MARK: - Convenience (require district)

    func isSchoolDay(_ date: Date, district: District) -> Bool {
        calendar.isSchoolDay(date, district: district)
    }

    func nextSchoolDay(district: District) -> Date? {
        calendar.nextSchoolDay(after: Date(), district: district)
    }

    func upcomingSchoolDays(count: Int = 60, district: District) -> [Date] {
        calendar.schoolDays(from: Date(), count: count, district: district)
    }

    /// Returns the next upcoming holiday event, if any
    func nextHoliday(district: District) -> SchoolCalendarEvent? {
        let now = Date()
        let cal = Calendar.current
        let currentYear = cal.component(.year, from: now)
        let month = cal.component(.month, from: now)
        let schoolYearStartYear = month >= 8 ? currentYear : currentYear - 1
        let schoolYearEnd = district.schoolYearEndDate(year: schoolYearStartYear)

        return calendar.events
            .filter { event in
                guard event.isHoliday && event.startDate <= schoolYearEnd else { return false }
                return event.startDate > now
            }
            .sorted { $0.startDate < $1.startDate }
            .first
    }
}

enum CalendarError: LocalizedError {
    case invalidURL
    case networkError
    case parseError

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid calendar URL"
        case .networkError:
            return "Failed to download calendar"
        case .parseError:
            return "Failed to parse calendar data"
        }
    }
}
