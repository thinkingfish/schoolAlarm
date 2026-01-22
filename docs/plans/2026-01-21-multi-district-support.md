# Multi-District Calendar Support Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Allow users to select from multiple school districts, each with its own calendar, school year dates, and timezone.

**Architecture:** Create a `District` model containing calendar configuration, bundle a JSON file of supported districts, add district selection UI (onboarding + settings), and make CalendarService district-aware with per-district caching.

**Tech Stack:** SwiftUI, Foundation, UserDefaults (persistence), Codable (JSON parsing)

---

## Task 1: Create District Model

**Files:**
- Create: `SchoolAlarm/Models/District.swift`

**Step 1: Write the model**

```swift
import Foundation

struct District: Identifiable, Codable, Hashable {
    let id: String                    // e.g., "sfusd"
    let name: String                  // e.g., "San Francisco Unified"
    let shortName: String             // e.g., "SFUSD"
    let calendarURL: String           // ICS feed URL
    let schoolYearStart: DateComponents  // e.g., month: 8, day: 18
    let schoolYearEnd: DateComponents    // e.g., month: 6, day: 3
    let timezone: String              // e.g., "America/Los_Angeles"
    let state: String                 // e.g., "CA"

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
```

**Step 2: Commit**

```bash
git add SchoolAlarm/Models/District.swift
git commit -m "feat: add District model for multi-district support"
```

---

## Task 2: Create Bundled Districts JSON

**Files:**
- Create: `SchoolAlarm/Resources/districts.json`

**Step 1: Create the JSON file with initial districts**

```json
[
  {
    "id": "sfusd",
    "name": "San Francisco Unified School District",
    "shortName": "SFUSD",
    "calendarURL": "https://calendar.google.com/calendar/ical/sfusd.edu_bqjal71qaoocvnuspm9vl4qnuo%40group.calendar.google.com/public/basic.ics",
    "schoolYearStart": { "month": 8, "day": 18 },
    "schoolYearEnd": { "month": 6, "day": 3 },
    "timezone": "America/Los_Angeles",
    "state": "CA"
  },
  {
    "id": "ousd",
    "name": "Oakland Unified School District",
    "shortName": "OUSD",
    "calendarURL": "https://calendar.google.com/calendar/ical/ousd.org_PLACEHOLDER%40group.calendar.google.com/public/basic.ics",
    "schoolYearStart": { "month": 8, "day": 12 },
    "schoolYearEnd": { "month": 6, "day": 6 },
    "timezone": "America/Los_Angeles",
    "state": "CA"
  },
  {
    "id": "lausd",
    "name": "Los Angeles Unified School District",
    "shortName": "LAUSD",
    "calendarURL": "https://calendar.google.com/calendar/ical/lausd.net_PLACEHOLDER%40group.calendar.google.com/public/basic.ics",
    "schoolYearStart": { "month": 8, "day": 12 },
    "schoolYearEnd": { "month": 6, "day": 10 },
    "timezone": "America/Los_Angeles",
    "state": "CA"
  }
]
```

**Note:** PLACEHOLDER URLs need to be replaced with actual ICS feed URLs after researching each district's public calendar.

**Step 2: Add to Xcode project**

Add `districts.json` to the SchoolAlarm target in Xcode (File > Add Files, ensure "Copy items if needed" is checked and target membership is set).

**Step 3: Commit**

```bash
git add SchoolAlarm/Resources/districts.json
git commit -m "feat: add bundled districts JSON with initial CA districts"
```

---

## Task 3: Create DistrictStore

**Files:**
- Create: `SchoolAlarm/Services/DistrictStore.swift`

**Step 1: Write the store**

```swift
import Foundation
import Combine

class DistrictStore: ObservableObject {
    @Published var districts: [District] = []
    @Published var selectedDistrict: District?

    private let selectedDistrictKey = "SelectedDistrictID"

    init() {
        loadDistricts()
        loadSelectedDistrict()
    }

    // MARK: - Loading

    private func loadDistricts() {
        guard let url = Bundle.main.url(forResource: "districts", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([District].self, from: data) else {
            print("Failed to load districts.json")
            return
        }
        districts = decoded.sorted { $0.name < $1.name }
    }

    private func loadSelectedDistrict() {
        guard let savedID = UserDefaults.standard.string(forKey: selectedDistrictKey),
              let district = districts.first(where: { $0.id == savedID }) else {
            return
        }
        selectedDistrict = district
    }

    // MARK: - Selection

    func selectDistrict(_ district: District) {
        selectedDistrict = district
        UserDefaults.standard.set(district.id, forKey: selectedDistrictKey)
    }

    var hasSelectedDistrict: Bool {
        selectedDistrict != nil
    }

    // MARK: - Filtering

    func districts(for state: String) -> [District] {
        districts.filter { $0.state == state }
    }

    var availableStates: [String] {
        Array(Set(districts.map { $0.state })).sorted()
    }
}
```

**Step 2: Commit**

```bash
git add SchoolAlarm/Services/DistrictStore.swift
git commit -m "feat: add DistrictStore for loading and selecting districts"
```

---

## Task 4: Update SchoolCalendar to Use District

**Files:**
- Modify: `SchoolAlarm/Models/SchoolCalendar.swift`

**Step 1: Remove hardcoded school year dates and add district parameter**

Replace the static properties and update `isSchoolDay`:

```swift
import Foundation

struct SchoolCalendarEvent: Identifiable, Codable {
    // ... (unchanged)
}

struct SchoolCalendar: Codable {
    var events: [SchoolCalendarEvent]
    var lastUpdated: Date
    var districtId: String?  // Track which district this calendar is for

    // Remove these static properties:
    // static let schoolYearStart = ...
    // static let schoolYearEnd = ...

    init(events: [SchoolCalendarEvent] = [], lastUpdated: Date = Date(), districtId: String? = nil) {
        self.events = events
        self.lastUpdated = lastUpdated
        self.districtId = districtId
    }

    func isSchoolDay(_ date: Date, district: District) -> Bool {
        let calendar = Calendar.current

        // Check if it's a weekend
        let weekday = calendar.component(.weekday, from: date)
        if weekday == 1 || weekday == 7 {
            return false
        }

        // Determine current school year
        let currentYear = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)

        // If we're in Jan-Jul, we're in the second half of the school year (started previous year)
        // If we're in Aug-Dec, we're in the first half of the school year (started this year)
        let schoolYearStartYear = month >= 8 ? currentYear : currentYear - 1

        let schoolYearStart = district.schoolYearStartDate(year: schoolYearStartYear)
        let schoolYearEnd = district.schoolYearEndDate(year: schoolYearStartYear)

        // Check if date is within school year
        let startOfDay = calendar.startOfDay(for: date)
        if startOfDay < schoolYearStart || startOfDay > schoolYearEnd {
            return false
        }

        // Check if it's a holiday or break (unchanged logic)
        for event in events {
            if event.isHoliday {
                let eventStart = calendar.startOfDay(for: event.startDate)
                let eventEnd = calendar.startOfDay(for: event.endDate)

                if event.isAllDay {
                    if startOfDay >= eventStart && startOfDay < eventEnd {
                        return false
                    }
                } else {
                    if startOfDay >= eventStart && startOfDay <= eventEnd {
                        return false
                    }
                }
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

        let currentYear = calendar.component(.year, from: startDate)
        let month = calendar.component(.month, from: startDate)
        let schoolYearStartYear = month >= 8 ? currentYear : currentYear - 1
        let schoolYearEnd = district.schoolYearEndDate(year: schoolYearStartYear)

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
```

**Step 2: Run build to verify compilation**

Run: `xcodebuild -scheme SchoolAlarm -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | head -50`

Expected: Compilation errors in CalendarService (expected - we'll fix in next task)

**Step 3: Commit**

```bash
git add SchoolAlarm/Models/SchoolCalendar.swift
git commit -m "refactor: make SchoolCalendar district-aware with dynamic school year dates"
```

---

## Task 5: Update CalendarService for Multi-District

**Files:**
- Modify: `SchoolAlarm/Services/CalendarService.swift`

**Step 1: Update CalendarService to accept district and cache per-district**

```swift
import Foundation
import Combine

@MainActor
class CalendarService: ObservableObject {
    @Published var calendar: SchoolCalendar = SchoolCalendar()
    @Published var isLoading: Bool = false
    @Published var error: String?
    @Published var lastRefresh: Date?

    private var currentDistrict: District?

    private func cacheKey(for district: District) -> String {
        "CachedSchoolCalendar_\(district.id)"
    }

    private func lastRefreshKey(for district: District) -> String {
        "LastCalendarRefresh_\(district.id)"
    }

    init() {}

    func loadCalendar(for district: District) async {
        currentDistrict = district

        // Load from cache first
        loadCachedCalendar(for: district)

        // Check if we need to refresh
        if shouldRefresh(for: district) {
            await refreshCalendar(for: district)
        }
    }

    func refreshCalendar(for district: District) async {
        currentDistrict = district
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
```

**Step 2: Commit**

```bash
git add SchoolAlarm/Services/CalendarService.swift
git commit -m "refactor: update CalendarService for multi-district with per-district caching"
```

---

## Task 6: Create District Selection View

**Files:**
- Create: `SchoolAlarm/Views/DistrictSelectionView.swift`

**Step 1: Write the selection view**

```swift
import SwiftUI

struct DistrictSelectionView: View {
    @EnvironmentObject var districtStore: DistrictStore
    @Environment(\.dismiss) private var dismiss

    let onSelect: ((District) -> Void)?

    @State private var searchText = ""
    @State private var selectedState: String?

    init(onSelect: ((District) -> Void)? = nil) {
        self.onSelect = onSelect
    }

    var filteredDistricts: [District] {
        var result = districtStore.districts

        if let state = selectedState {
            result = result.filter { $0.state == state }
        }

        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.shortName.localizedCaseInsensitiveContains(searchText)
            }
        }

        return result
    }

    var body: some View {
        List {
            // State filter
            if districtStore.availableStates.count > 1 {
                Section {
                    Picker("State", selection: $selectedState) {
                        Text("All States").tag(nil as String?)
                        ForEach(districtStore.availableStates, id: \.self) { state in
                            Text(state).tag(state as String?)
                        }
                    }
                }
            }

            // Districts
            Section {
                ForEach(filteredDistricts) { district in
                    Button {
                        districtStore.selectDistrict(district)
                        onSelect?(district)
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(district.shortName)
                                    .font(.headline)
                                Text(district.name)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if districtStore.selectedDistrict?.id == district.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            } header: {
                Text("\(filteredDistricts.count) districts")
            }
        }
        .searchable(text: $searchText, prompt: "Search districts")
        .navigationTitle("Select District")
        .navigationBarTitleDisplayMode(.inline)
    }
}
```

**Step 2: Commit**

```bash
git add SchoolAlarm/Views/DistrictSelectionView.swift
git commit -m "feat: add DistrictSelectionView for district selection"
```

---

## Task 7: Create Onboarding View

**Files:**
- Create: `SchoolAlarm/Views/OnboardingView.swift`

**Step 1: Write the onboarding view**

```swift
import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var districtStore: DistrictStore
    let onComplete: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.orange)

                Text("Welcome to SchoolAlarm")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Select your school district to get started")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Spacer()

                NavigationLink {
                    DistrictSelectionView { _ in
                        onComplete()
                    }
                    .environmentObject(districtStore)
                } label: {
                    Text("Choose District")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.orange)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 48)
            }
        }
    }
}
```

**Step 2: Commit**

```bash
git add SchoolAlarm/Views/OnboardingView.swift
git commit -m "feat: add OnboardingView for first-launch district selection"
```

---

## Task 8: Update SchoolAlarmApp for District Flow

**Files:**
- Modify: `SchoolAlarm/App/SchoolAlarmApp.swift`

**Step 1: Add DistrictStore and onboarding flow**

```swift
import SwiftUI
import AlarmKit

@main
struct SchoolAlarmApp: App {
    @StateObject private var alarmStore = AlarmStore()
    @StateObject private var calendarService = CalendarService()
    @StateObject private var overrideStore = OverrideStore()
    @StateObject private var districtStore = DistrictStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if districtStore.hasSelectedDistrict {
                    ContentView()
                        .environmentObject(alarmStore)
                        .environmentObject(calendarService)
                        .environmentObject(overrideStore)
                        .environmentObject(districtStore)
                        .onAppear {
                            Task {
                                _ = await AlarmKitManager.shared.requestAuthorization()
                                if let district = districtStore.selectedDistrict {
                                    await calendarService.loadCalendar(for: district)
                                }
                                rescheduleAlarms()
                            }
                        }
                        .onChange(of: scenePhase) { _, newPhase in
                            if newPhase == .active {
                                rescheduleAlarms()
                            }
                        }
                } else {
                    OnboardingView {
                        // District selected, app will re-render showing ContentView
                    }
                    .environmentObject(districtStore)
                }
            }
        }
    }

    private func rescheduleAlarms() {
        guard let district = districtStore.selectedDistrict else { return }
        AlarmKitManager.shared.rescheduleAllAlarms(
            alarmStore: alarmStore,
            calendarService: calendarService,
            overrideStore: overrideStore,
            district: district
        )
    }
}
```

**Step 2: Commit**

```bash
git add SchoolAlarm/App/SchoolAlarmApp.swift
git commit -m "feat: add onboarding flow and district store to app entry"
```

---

## Task 9: Update AlarmKitManager for District

**Files:**
- Modify: `SchoolAlarm/Services/AlarmKitManager.swift`

**Step 1: Update rescheduleAllAlarms to accept district**

Update the method signature and usage:

```swift
@MainActor
func rescheduleAllAlarms(
    alarmStore: AlarmStore,
    calendarService: CalendarService,
    overrideStore: OverrideStore,
    district: District
) {
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
```

**Step 2: Commit**

```bash
git add SchoolAlarm/Services/AlarmKitManager.swift
git commit -m "refactor: update AlarmKitManager to accept district parameter"
```

---

## Task 10: Update CalendarView for District

**Files:**
- Modify: `SchoolAlarm/Views/CalendarView.swift`

**Step 1: Update to use selected district**

Add `@EnvironmentObject var districtStore: DistrictStore` and update all calendar calls:

- Change `calendarService.isSchoolDay(date)` to `calendarService.isSchoolDay(date, district: districtStore.selectedDistrict!)`
- Update navigation title to use `districtStore.selectedDistrict?.shortName ?? "Calendar"`
- Update any other calendar-related calls

**Step 2: Commit**

```bash
git add SchoolAlarm/Views/CalendarView.swift
git commit -m "refactor: update CalendarView to use selected district"
```

---

## Task 11: Update ContentView for District

**Files:**
- Modify: `SchoolAlarm/App/ContentView.swift`

**Step 1: Pass districtStore to child views**

Ensure DistrictStore is passed to CalendarView and any other views that need it:

```swift
.environmentObject(districtStore)
```

**Step 2: Commit**

```bash
git add SchoolAlarm/App/ContentView.swift
git commit -m "refactor: pass districtStore to child views in ContentView"
```

---

## Task 12: Add District Settings in Settings View

**Files:**
- Modify: `SchoolAlarm/Views/SettingsView.swift` (or create if doesn't exist)

**Step 1: Add district change option**

Add a navigation link to DistrictSelectionView in settings so users can change their district:

```swift
Section("School District") {
    NavigationLink {
        DistrictSelectionView { district in
            Task {
                await calendarService.loadCalendar(for: district)
            }
        }
        .environmentObject(districtStore)
    } label: {
        HStack {
            Text("District")
            Spacer()
            Text(districtStore.selectedDistrict?.shortName ?? "None")
                .foregroundStyle(.secondary)
        }
    }
}
```

**Step 2: Commit**

```bash
git add SchoolAlarm/Views/SettingsView.swift
git commit -m "feat: add district change option in settings"
```

---

## Task 13: Research and Add Real District Calendar URLs

**Files:**
- Modify: `SchoolAlarm/Resources/districts.json`

**Step 1: Research public calendar URLs**

For each district (OUSD, LAUSD, etc.):
1. Search for "[district name] school calendar ICS" or visit their website
2. Find their public Google Calendar or ICS feed
3. Verify the URL works by testing in a browser

**Step 2: Update districts.json with real URLs**

Replace PLACEHOLDER URLs with actual working ICS feeds.

**Step 3: Add more Bay Area districts**

Consider adding:
- Berkeley Unified (BUSD)
- San Jose Unified (SJUSD)
- Fremont Unified (FUSD)
- Palo Alto Unified (PAUSD)

**Step 4: Commit**

```bash
git add SchoolAlarm/Resources/districts.json
git commit -m "feat: add real calendar URLs for multiple CA school districts"
```

---

## Task 14: Test and Verify

**Step 1: Build and run**

```bash
xcodebuild -scheme SchoolAlarm -destination 'platform=iOS Simulator,name=iPhone 16' build
```

**Step 2: Manual testing checklist**

- [ ] Fresh install shows onboarding
- [ ] Can select a district from the list
- [ ] Calendar loads for selected district
- [ ] School days display correctly
- [ ] Can change district in settings
- [ ] Changing district reloads calendar
- [ ] Alarms schedule correctly for selected district
- [ ] Cache works per-district (switch districts, switch back, calendar loads from cache)

**Step 3: Commit any fixes**

---

## Task 15: Update README

**Files:**
- Modify: `README.md`

**Step 1: Document multi-district support**

Add section explaining:
- Supported districts
- How to request a new district be added
- How district calendars work

**Step 2: Commit**

```bash
git add README.md
git commit -m "docs: update README with multi-district support info"
```

---

## Summary

This plan adds:
1. **District model** with configurable calendar URL, school year dates, timezone
2. **Bundled districts.json** with initial CA school districts
3. **DistrictStore** for loading districts and persisting user selection
4. **Onboarding flow** for first-launch district selection
5. **District selection UI** with search and state filtering
6. **Per-district caching** so switching districts doesn't re-download
7. **Settings integration** to change district after initial setup

The architecture allows easy addition of new districts by simply adding entries to `districts.json`.
