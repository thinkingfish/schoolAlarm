import Foundation
import Combine

@MainActor
class CalendarService: ObservableObject {
    @Published var calendar: SchoolCalendar = SchoolCalendar()
    @Published var isLoading: Bool = false
    @Published var error: String?
    @Published var lastRefresh: Date?

    private let calendarURL = "https://calendar.google.com/calendar/ical/sfusd.edu_bqjal71qaoocvnuspm9vl4qnuo%40group.calendar.google.com/public/basic.ics"
    private let cacheKey = "CachedSchoolCalendar"
    private let lastRefreshKey = "LastCalendarRefresh"

    init() {
        loadCachedCalendar()
    }

    func loadCalendar() async {
        // Load from cache first
        loadCachedCalendar()

        // Check if we need to refresh (older than 24 hours)
        if shouldRefresh() {
            await refreshCalendar()
        }
    }

    func refreshCalendar() async {
        isLoading = true
        error = nil

        do {
            guard let url = URL(string: calendarURL) else {
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
            calendar = SchoolCalendar(events: events, lastUpdated: Date())

            // Cache the calendar
            saveCalendarToCache()

            lastRefresh = Date()
            UserDefaults.standard.set(lastRefresh, forKey: lastRefreshKey)

        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    private func loadCachedCalendar() {
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let cached = try? JSONDecoder().decode(SchoolCalendar.self, from: data) {
            calendar = cached
        }

        lastRefresh = UserDefaults.standard.object(forKey: lastRefreshKey) as? Date
    }

    private func saveCalendarToCache() {
        if let encoded = try? JSONEncoder().encode(calendar) {
            UserDefaults.standard.set(encoded, forKey: cacheKey)
        }
    }

    private func shouldRefresh() -> Bool {
        guard let lastRefresh = lastRefresh else {
            return true
        }

        let hoursSinceRefresh = Date().timeIntervalSince(lastRefresh) / 3600
        return hoursSinceRefresh > 24
    }

    func isSchoolDay(_ date: Date) -> Bool {
        calendar.isSchoolDay(date)
    }

    func nextSchoolDay() -> Date? {
        calendar.nextSchoolDay(after: Date())
    }

    func upcomingSchoolDays(count: Int = 60) -> [Date] {
        calendar.schoolDays(from: Date(), count: count)
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
