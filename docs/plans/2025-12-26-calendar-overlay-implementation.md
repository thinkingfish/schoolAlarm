# Calendar Overlay Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add user-configurable alarm overrides (weekly rules and one-time exceptions) that layer on top of the SFUSD school calendar with priority: one-time > weekly > base.

**Architecture:** Hybrid model where each layer independently contributes alarms. New `OverrideStore` manages rules/overrides with UserDefaults persistence. `NotificationManager` enhanced with override-aware scheduling and queue reliability (foreground/background refresh triggers).

**Tech Stack:** SwiftUI, UserDefaults, UNUserNotificationCenter, BGTaskScheduler

---

## Task 1: Data Models (OverrideAction, WeeklyRule, DateOverride)

**Files:**
- Create: `SFUSD-Alarm/Models/OverrideModels.swift`

**Step 1: Create the override models file**

```swift
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
```

**Step 2: Verify it compiles**

Run: `xcodebuild -scheme SFUSD-Alarm -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -20`

Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add SFUSD-Alarm/Models/OverrideModels.swift
git commit -m "feat: add OverrideAction, WeeklyRule, DateOverride models"
```

---

## Task 2: OverrideStore with Persistence

**Files:**
- Create: `SFUSD-Alarm/Models/OverrideStore.swift`

**Step 1: Create the OverrideStore class**

```swift
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
```

**Step 2: Verify it compiles**

Run: `xcodebuild -scheme SFUSD-Alarm -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -20`

Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add SFUSD-Alarm/Models/OverrideStore.swift
git commit -m "feat: add OverrideStore with persistence and resolution logic"
```

---

## Task 3: Integrate OverrideStore into App Environment

**Files:**
- Modify: `SFUSD-Alarm/App/SFUSD_AlarmApp.swift`

**Step 1: Add OverrideStore as StateObject and environment**

In `SFUSD_AlarmApp.swift`, add the highlighted changes:

```swift
import SwiftUI
import UserNotifications

@main
struct SFUSD_AlarmApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var alarmStore = AlarmStore()
    @StateObject private var calendarService = CalendarService()
    @StateObject private var overrideStore = OverrideStore()  // ADD THIS

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(alarmStore)
                .environmentObject(calendarService)
                .environmentObject(overrideStore)  // ADD THIS
                .onAppear {
                    NotificationManager.shared.requestAuthorization()
                    Task {
                        await calendarService.loadCalendar()
                    }
                }
        }
    }
}
```

**Step 2: Verify it compiles**

Run: `xcodebuild -scheme SFUSD-Alarm -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -20`

Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add SFUSD-Alarm/App/SFUSD_AlarmApp.swift
git commit -m "feat: inject OverrideStore into app environment"
```

---

## Task 4: Update NotificationManager for Override-Aware Scheduling

**Files:**
- Modify: `SFUSD-Alarm/Services/NotificationManager.swift`

**Step 1: Add new scheduling method that respects overrides**

Add this new method to `NotificationManager`:

```swift
/// Schedule alarms for upcoming school days, respecting overrides
/// - Parameters:
///   - baseAlarm: The base alarm (optional)
///   - schoolDays: List of upcoming school days
///   - overrideStore: The override store for resolution
func scheduleAlarmsWithOverrides(
    baseAlarm: Alarm?,
    on schoolDays: [Date],
    overrideStore: OverrideStore
) {
    // Cancel all existing alarm notifications first
    cancelAllNotifications()

    guard overrideStore.allAlarmsEnabled else {
        updatePendingCount()
        return
    }

    let center = UNUserNotificationCenter.current()
    let calendar = Calendar.current

    var scheduledCount = 0

    for schoolDay in schoolDays {
        guard scheduledCount < maxNotifications else { break }

        // Get effective alarm time using override resolution
        guard let alarmTime = overrideStore.effectiveAlarmTime(for: schoolDay, baseAlarm: baseAlarm) else {
            continue  // Skip this day (disabled or no alarm)
        }

        let dateComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: alarmTime)

        let content = UNMutableNotificationContent()
        content.title = baseAlarm?.label.isEmpty == false ? baseAlarm!.label : "School Day Alarm"
        content.body = "Time to get ready for school!"
        content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: "\(baseAlarm?.sound.systemSoundName ?? "alarm").caf"))
        content.badge = 1
        content.userInfo = [
            "alarmId": baseAlarm?.id.uuidString ?? "override",
            "schoolDay": schoolDay.timeIntervalSince1970
        ]

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        let identifier = "alarm_\(schoolDay.timeIntervalSince1970)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        center.add(request) { error in
            if let error = error {
                print("Failed to schedule notification: \(error)")
            }
        }

        scheduledCount += 1
    }

    updatePendingCount()
}
```

**Step 2: Add a rescheduleAll helper method**

```swift
/// Reschedule all alarms (call when any override or alarm changes)
func rescheduleAllAlarms(
    alarmStore: AlarmStore,
    calendarService: CalendarService,
    overrideStore: OverrideStore
) {
    let schoolDays = calendarService.upcomingSchoolDays()
    let baseAlarm = alarmStore.alarms.first  // Single base alarm model
    scheduleAlarmsWithOverrides(baseAlarm: baseAlarm, on: schoolDays, overrideStore: overrideStore)
}
```

**Step 3: Verify it compiles**

Run: `xcodebuild -scheme SFUSD-Alarm -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -20`

Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add SFUSD-Alarm/Services/NotificationManager.swift
git commit -m "feat: add override-aware notification scheduling"
```

---

## Task 5: WeeklyRuleEditView (Add/Edit Weekly Rule Sheet)

**Files:**
- Create: `SFUSD-Alarm/Views/WeeklyRuleEditView.swift`

**Step 1: Create the weekly rule edit view**

```swift
import SwiftUI

enum WeeklyRuleEditMode {
    case add
    case edit(WeeklyRule)

    var title: String {
        switch self {
        case .add: return "Add Weekly Rule"
        case .edit: return "Edit Weekly Rule"
        }
    }

    var rule: WeeklyRule? {
        switch self {
        case .add: return nil
        case .edit(let rule): return rule
        }
    }
}

struct WeeklyRuleEditView: View {
    let mode: WeeklyRuleEditMode
    var onSave: (WeeklyRule) -> Void
    var onDelete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var overrideStore: OverrideStore

    @State private var selectedWeekday: Int
    @State private var actionType: ActionType = .customTime
    @State private var selectedTime: Date

    enum ActionType {
        case disable
        case customTime
    }

    private let weekdays = [
        (2, "Monday"),
        (3, "Tuesday"),
        (4, "Wednesday"),
        (5, "Thursday"),
        (6, "Friday")
    ]

    init(mode: WeeklyRuleEditMode, onSave: @escaping (WeeklyRule) -> Void, onDelete: (() -> Void)? = nil) {
        self.mode = mode
        self.onSave = onSave
        self.onDelete = onDelete

        if let rule = mode.rule {
            _selectedWeekday = State(initialValue: rule.weekday)
            switch rule.action {
            case .disable:
                _actionType = State(initialValue: .disable)
                _selectedTime = State(initialValue: Calendar.current.date(from: DateComponents(hour: 7, minute: 0)) ?? Date())
            case .customTime(let time):
                _actionType = State(initialValue: .customTime)
                _selectedTime = State(initialValue: time)
            }
        } else {
            _selectedWeekday = State(initialValue: 2)  // Monday default
            _actionType = State(initialValue: .customTime)
            _selectedTime = State(initialValue: Calendar.current.date(from: DateComponents(hour: 7, minute: 45)) ?? Date())
        }
    }

    private var availableWeekdays: [(Int, String)] {
        if case .edit(let rule) = mode {
            // In edit mode, only show the current weekday
            return weekdays.filter { $0.0 == rule.weekday }
        }
        // In add mode, filter out weekdays that already have rules
        let existingWeekdays = Set(overrideStore.weeklyRules.map { $0.weekday })
        return weekdays.filter { !existingWeekdays.contains($0.0) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                List {
                    // Weekday picker (only in add mode or if editing)
                    if case .add = mode {
                        Section {
                            Picker("Day", selection: $selectedWeekday) {
                                ForEach(availableWeekdays, id: \.0) { weekday in
                                    Text(weekday.1).tag(weekday.0)
                                }
                            }
                            .pickerStyle(.menu)
                        } header: {
                            Text("WEEKDAY")
                                .foregroundColor(.blue)
                        }
                        .listRowBackground(Color(white: 0.15))
                    } else if case .edit(let rule) = mode {
                        Section {
                            Text(rule.weekdayName)
                                .foregroundColor(.white)
                        } header: {
                            Text("WEEKDAY")
                                .foregroundColor(.blue)
                        }
                        .listRowBackground(Color(white: 0.15))
                    }

                    // Action type
                    Section {
                        Picker("Action", selection: $actionType) {
                            Text("Custom Time").tag(ActionType.customTime)
                            Text("Disable Alarm").tag(ActionType.disable)
                        }
                        .pickerStyle(.segmented)
                    } header: {
                        Text("ACTION")
                            .foregroundColor(.blue)
                    }
                    .listRowBackground(Color(white: 0.15))

                    // Time picker (only if custom time)
                    if actionType == .customTime {
                        Section {
                            DatePicker("Time", selection: $selectedTime, displayedComponents: .hourAndMinute)
                                .datePickerStyle(.wheel)
                                .labelsHidden()
                                .frame(maxWidth: .infinity)
                        } header: {
                            Text("ALARM TIME")
                                .foregroundColor(.blue)
                        }
                        .listRowBackground(Color(white: 0.15))
                    }

                    // Delete button (edit mode only)
                    if case .edit = mode {
                        Section {
                            Button(role: .destructive) {
                                onDelete?()
                                dismiss()
                            } label: {
                                HStack {
                                    Spacer()
                                    Text("Delete Rule")
                                    Spacer()
                                }
                            }
                        }
                        .listRowBackground(Color(white: 0.15))
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveRule()
                    }
                    .fontWeight(.semibold)
                    .disabled(availableWeekdays.isEmpty && mode.rule == nil)
                }
            }
            .onAppear {
                // Set initial weekday if adding and current selection is not available
                if case .add = mode, !availableWeekdays.contains(where: { $0.0 == selectedWeekday }) {
                    selectedWeekday = availableWeekdays.first?.0 ?? 2
                }
            }
        }
    }

    private func saveRule() {
        let action: OverrideAction = actionType == .disable ? .disable : .customTime(selectedTime)

        var rule: WeeklyRule
        if let existingRule = mode.rule {
            rule = existingRule
            rule.action = action
        } else {
            rule = WeeklyRule(weekday: selectedWeekday, action: action)
        }

        onSave(rule)
        dismiss()
    }
}

#Preview {
    WeeklyRuleEditView(mode: .add, onSave: { _ in })
        .environmentObject(OverrideStore())
}
```

**Step 2: Verify it compiles**

Run: `xcodebuild -scheme SFUSD-Alarm -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -20`

Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add SFUSD-Alarm/Views/WeeklyRuleEditView.swift
git commit -m "feat: add WeeklyRuleEditView for creating/editing weekly rules"
```

---

## Task 6: DateOverrideEditView (Add/Edit One-Time Override Sheet)

**Files:**
- Create: `SFUSD-Alarm/Views/DateOverrideEditView.swift`

**Step 1: Create the date override edit view**

```swift
import SwiftUI

enum DateOverrideEditMode {
    case add
    case addForDate(Date)
    case edit(DateOverride)

    var title: String {
        switch self {
        case .add, .addForDate: return "Add Override"
        case .edit: return "Edit Override"
        }
    }

    var override: DateOverride? {
        switch self {
        case .add, .addForDate: return nil
        case .edit(let override): return override
        }
    }

    var preselectedDate: Date? {
        switch self {
        case .addForDate(let date): return date
        default: return nil
        }
    }
}

struct DateOverrideEditView: View {
    let mode: DateOverrideEditMode
    var onSave: (DateOverride) -> Void
    var onDelete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var calendarService: CalendarService

    @State private var selectedDate: Date
    @State private var actionType: ActionType = .customTime
    @State private var selectedTime: Date

    enum ActionType {
        case disable
        case customTime
    }

    init(mode: DateOverrideEditMode, onSave: @escaping (DateOverride) -> Void, onDelete: (() -> Void)? = nil) {
        self.mode = mode
        self.onSave = onSave
        self.onDelete = onDelete

        if let override = mode.override {
            _selectedDate = State(initialValue: override.date)
            switch override.action {
            case .disable:
                _actionType = State(initialValue: .disable)
                _selectedTime = State(initialValue: Calendar.current.date(from: DateComponents(hour: 7, minute: 0)) ?? Date())
            case .customTime(let time):
                _actionType = State(initialValue: .customTime)
                _selectedTime = State(initialValue: time)
            }
        } else if let preselected = mode.preselectedDate {
            _selectedDate = State(initialValue: preselected)
            _actionType = State(initialValue: .customTime)
            _selectedTime = State(initialValue: Calendar.current.date(from: DateComponents(hour: 7, minute: 45)) ?? Date())
        } else {
            // Default to next school day
            _selectedDate = State(initialValue: Date())
            _actionType = State(initialValue: .customTime)
            _selectedTime = State(initialValue: Calendar.current.date(from: DateComponents(hour: 7, minute: 45)) ?? Date())
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                List {
                    // Date picker (only in add mode)
                    if mode.override == nil && mode.preselectedDate == nil {
                        Section {
                            DatePicker(
                                "Date",
                                selection: $selectedDate,
                                in: Date()...,
                                displayedComponents: .date
                            )
                            .datePickerStyle(.graphical)
                            .tint(.green)
                        } header: {
                            Text("DATE")
                                .foregroundColor(.green)
                        }
                        .listRowBackground(Color(white: 0.15))
                    } else {
                        Section {
                            HStack {
                                Text("Date")
                                Spacer()
                                Text(dateString)
                                    .foregroundColor(.gray)
                            }
                        } header: {
                            Text("DATE")
                                .foregroundColor(.green)
                        }
                        .listRowBackground(Color(white: 0.15))
                    }

                    // Action type
                    Section {
                        Picker("Action", selection: $actionType) {
                            Text("Custom Time").tag(ActionType.customTime)
                            Text("Disable Alarm").tag(ActionType.disable)
                        }
                        .pickerStyle(.segmented)
                    } header: {
                        Text("ACTION")
                            .foregroundColor(.green)
                    }
                    .listRowBackground(Color(white: 0.15))

                    // Time picker (only if custom time)
                    if actionType == .customTime {
                        Section {
                            DatePicker("Time", selection: $selectedTime, displayedComponents: .hourAndMinute)
                                .datePickerStyle(.wheel)
                                .labelsHidden()
                                .frame(maxWidth: .infinity)
                        } header: {
                            Text("ALARM TIME")
                                .foregroundColor(.green)
                        }
                        .listRowBackground(Color(white: 0.15))
                    }

                    // School day warning
                    if !isSchoolDay {
                        Section {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.yellow)
                                Text("This is not a school day. Override will have no effect.")
                                    .font(.caption)
                                    .foregroundColor(.yellow)
                            }
                        }
                        .listRowBackground(Color.yellow.opacity(0.1))
                    }

                    // Delete button (edit mode only)
                    if case .edit = mode {
                        Section {
                            Button(role: .destructive) {
                                onDelete?()
                                dismiss()
                            } label: {
                                HStack {
                                    Spacer()
                                    Text("Delete Override")
                                    Spacer()
                                }
                            }
                        }
                        .listRowBackground(Color(white: 0.15))
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveOverride()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d, yyyy"
        return formatter.string(from: selectedDate)
    }

    private var isSchoolDay: Bool {
        calendarService.isSchoolDay(selectedDate)
    }

    private func saveOverride() {
        let action: OverrideAction = actionType == .disable ? .disable : .customTime(selectedTime)

        var override: DateOverride
        if let existingOverride = mode.override {
            override = existingOverride
            override.action = action
        } else {
            override = DateOverride(date: selectedDate, action: action)
        }

        onSave(override)
        dismiss()
    }
}

#Preview {
    DateOverrideEditView(mode: .add, onSave: { _ in })
        .environmentObject(CalendarService())
}
```

**Step 2: Verify it compiles**

Run: `xcodebuild -scheme SFUSD-Alarm -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -20`

Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add SFUSD-Alarm/Views/DateOverrideEditView.swift
git commit -m "feat: add DateOverrideEditView for creating/editing one-time overrides"
```

---

## Task 7: Redesign ContentView Main Layout

**Files:**
- Modify: `SFUSD-Alarm/App/ContentView.swift`

**Step 1: Replace ContentView with the new layered design**

This is a significant rewrite. Replace the entire file:

```swift
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var alarmStore: AlarmStore
    @EnvironmentObject var calendarService: CalendarService
    @EnvironmentObject var overrideStore: OverrideStore

    @State private var showingAddAlarm = false
    @State private var showingAddWeeklyRule = false
    @State private var showingAddDateOverride = false
    @State private var selectedAlarm: Alarm?
    @State private var selectedWeeklyRule: WeeklyRule?
    @State private var selectedDateOverride: DateOverride?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        // Next Alarm Section
                        NextAlarmSection()
                            .environmentObject(calendarService)
                            .environmentObject(overrideStore)
                            .environmentObject(alarmStore)

                        // Extra spacing before master toggle
                        Spacer().frame(height: 24)

                        // Master Toggle
                        MasterToggleSection()
                            .environmentObject(overrideStore)

                        Divider().background(Color.gray.opacity(0.3)).padding(.vertical, 8)

                        // Base Alarm Section
                        BaseAlarmSection(
                            showingAddAlarm: $showingAddAlarm,
                            selectedAlarm: $selectedAlarm
                        )
                        .environmentObject(alarmStore)
                        .environmentObject(overrideStore)

                        Divider().background(Color.gray.opacity(0.3)).padding(.vertical, 8)

                        // Weekly Rules Section
                        WeeklyRulesSection(
                            showingAddRule: $showingAddWeeklyRule,
                            selectedRule: $selectedWeeklyRule
                        )
                        .environmentObject(overrideStore)

                        Divider().background(Color.gray.opacity(0.3)).padding(.vertical, 8)

                        // One-Time Overrides Section
                        DateOverridesSection(
                            showingAddOverride: $showingAddDateOverride,
                            selectedOverride: $selectedDateOverride
                        )
                        .environmentObject(overrideStore)

                        Spacer().frame(height: 40)
                    }
                    .padding(.horizontal)
                }
            }
            .navigationTitle("Alarm")
            .navigationBarTitleDisplayMode(.large)
            .preferredColorScheme(.dark)
            .sheet(isPresented: $showingAddAlarm) {
                AlarmEditView(mode: .add)
            }
            .sheet(item: $selectedAlarm) { alarm in
                AlarmEditView(mode: .edit(alarm))
            }
            .sheet(isPresented: $showingAddWeeklyRule) {
                WeeklyRuleEditView(mode: .add) { rule in
                    overrideStore.addWeeklyRule(rule)
                    rescheduleAllAlarms()
                }
            }
            .sheet(item: $selectedWeeklyRule) { rule in
                WeeklyRuleEditView(mode: .edit(rule), onSave: { updatedRule in
                    overrideStore.updateWeeklyRule(updatedRule)
                    rescheduleAllAlarms()
                }, onDelete: {
                    overrideStore.deleteWeeklyRule(rule)
                    rescheduleAllAlarms()
                })
            }
            .sheet(isPresented: $showingAddDateOverride) {
                DateOverrideEditView(mode: .add) { override in
                    overrideStore.addDateOverride(override)
                    rescheduleAllAlarms()
                }
            }
            .sheet(item: $selectedDateOverride) { override in
                DateOverrideEditView(mode: .edit(override), onSave: { updatedOverride in
                    overrideStore.updateDateOverride(updatedOverride)
                    rescheduleAllAlarms()
                }, onDelete: {
                    overrideStore.deleteDateOverride(override)
                    rescheduleAllAlarms()
                })
            }
        }
    }

    private func rescheduleAllAlarms() {
        NotificationManager.shared.rescheduleAllAlarms(
            alarmStore: alarmStore,
            calendarService: calendarService,
            overrideStore: overrideStore
        )
    }
}

// MARK: - Next Alarm Section

struct NextAlarmSection: View {
    @EnvironmentObject var calendarService: CalendarService
    @EnvironmentObject var overrideStore: OverrideStore
    @EnvironmentObject var alarmStore: AlarmStore

    var body: some View {
        VStack(spacing: 12) {
            if !overrideStore.allAlarmsEnabled {
                // All alarms disabled
                Text("All Alarms Disabled")
                    .font(.headline)
                    .foregroundColor(.gray)
                    .padding(.vertical, 20)
            } else if let (nextDate, nextTime, layer) = nextAlarmInfo {
                Text("NEXT ALARM")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.gray)

                Text(formatDate(nextDate))
                    .font(.subheadline)
                    .foregroundColor(.white)

                Text(formatTime(nextTime))
                    .font(.system(size: 48, weight: .light))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
                    .background(layerColor(layer).opacity(0.3))
                    .cornerRadius(12)

                NavigationLink {
                    CalendarView()
                } label: {
                    HStack {
                        Image(systemName: "calendar")
                        Text("View Calendar")
                    }
                    .font(.subheadline)
                    .foregroundColor(.orange)
                }
                .padding(.top, 4)
            } else {
                Text("No Upcoming Alarms")
                    .font(.headline)
                    .foregroundColor(.gray)
                    .padding(.vertical, 20)

                NavigationLink {
                    CalendarView()
                } label: {
                    HStack {
                        Image(systemName: "calendar")
                        Text("View Calendar")
                    }
                    .font(.subheadline)
                    .foregroundColor(.orange)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color(white: 0.1))
        .cornerRadius(12)
    }

    private var nextAlarmInfo: (Date, Date, AlarmLayer)? {
        guard let nextSchoolDay = calendarService.nextSchoolDay() else { return nil }

        let baseAlarm = alarmStore.alarms.first
        guard let alarmTime = overrideStore.effectiveAlarmTime(for: nextSchoolDay, baseAlarm: baseAlarm) else {
            // This day is disabled, find the next non-disabled school day
            let schoolDays = calendarService.upcomingSchoolDays()
            for day in schoolDays {
                if let time = overrideStore.effectiveAlarmTime(for: day, baseAlarm: baseAlarm) {
                    let layer = overrideStore.activeLayer(for: day)
                    return (day, time, layer)
                }
            }
            return nil
        }

        let layer = overrideStore.activeLayer(for: nextSchoolDay)
        return (nextSchoolDay, alarmTime, layer)
    }

    private func formatDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInTomorrow(date) {
            return "Tomorrow"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE, MMM d"
            return formatter.string(from: date)
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    private func layerColor(_ layer: AlarmLayer) -> Color {
        switch layer {
        case .base: return .orange
        case .weekly: return .blue
        case .oneTime: return .green
        }
    }
}

// MARK: - Master Toggle Section

struct MasterToggleSection: View {
    @EnvironmentObject var overrideStore: OverrideStore

    var body: some View {
        HStack {
            Text("All Alarms Enabled")
                .foregroundColor(.white)
            Spacer()
            Toggle("", isOn: Binding(
                get: { overrideStore.allAlarmsEnabled },
                set: { overrideStore.setAllAlarmsEnabled($0) }
            ))
            .labelsHidden()
            .tint(.orange)
        }
        .padding()
        .background(Color(white: 0.1))
        .cornerRadius(12)
    }
}

// MARK: - Base Alarm Section

struct BaseAlarmSection: View {
    @Binding var showingAddAlarm: Bool
    @Binding var selectedAlarm: Alarm?
    @EnvironmentObject var alarmStore: AlarmStore
    @EnvironmentObject var overrideStore: OverrideStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("BASE ALARM")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.orange)
                Spacer()
                if alarmStore.alarms.isEmpty {
                    Button {
                        showingAddAlarm = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.orange)
                    }
                }
            }

            if let alarm = alarmStore.alarms.first {
                BaseAlarmRow(alarm: alarm, onTap: { selectedAlarm = alarm })
                    .opacity(overrideStore.allAlarmsEnabled ? 1 : 0.5)
            } else {
                Text("Tap + to add a base alarm")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .padding(.vertical, 8)
            }
        }
    }
}

struct BaseAlarmRow: View {
    let alarm: Alarm
    let onTap: () -> Void
    @EnvironmentObject var alarmStore: AlarmStore
    @EnvironmentObject var calendarService: CalendarService
    @EnvironmentObject var overrideStore: OverrideStore

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(alarm.timeString)
                            .font(.system(size: 48, weight: .light))
                            .foregroundColor(alarm.isEnabled ? .white : .gray)
                        Text(alarm.periodString)
                            .font(.system(size: 20, weight: .light))
                            .foregroundColor(alarm.isEnabled ? .white : .gray)
                    }

                    Text(alarm.label.isEmpty ? "School Day Alarm" : alarm.label)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { alarm.isEnabled },
                    set: { _ in
                        alarmStore.toggleAlarm(alarm)
                        rescheduleAllAlarms()
                    }
                ))
                .labelsHidden()
                .tint(.orange)
            }
            .padding()
            .background(Color(white: 0.1))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    private func rescheduleAllAlarms() {
        NotificationManager.shared.rescheduleAllAlarms(
            alarmStore: alarmStore,
            calendarService: calendarService,
            overrideStore: overrideStore
        )
    }
}

// MARK: - Weekly Rules Section

struct WeeklyRulesSection: View {
    @Binding var showingAddRule: Bool
    @Binding var selectedRule: WeeklyRule?
    @EnvironmentObject var overrideStore: OverrideStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("WEEKLY RULES")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)
                Spacer()
                Button {
                    showingAddRule = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.blue)
                }
                .disabled(overrideStore.weeklyRules.count >= 5)  // Max 5 weekdays
            }

            if overrideStore.weeklyRules.isEmpty {
                Text("No weekly rules set")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .padding(.vertical, 8)
            } else {
                ForEach(overrideStore.weeklyRules) { rule in
                    WeeklyRuleRow(rule: rule, onTap: { selectedRule = rule })
                        .opacity(overrideStore.allAlarmsEnabled ? 1 : 0.5)
                }
            }
        }
    }
}

struct WeeklyRuleRow: View {
    let rule: WeeklyRule
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Text("Every \(rule.weekdayName)")
                    .foregroundColor(.white)

                Spacer()

                switch rule.action {
                case .disable:
                    Text("Disabled")
                        .foregroundColor(.red)
                case .customTime:
                    Text(rule.action.timeString ?? "")
                        .foregroundColor(.blue)
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .padding()
            .background(Color(white: 0.1))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Date Overrides Section

struct DateOverridesSection: View {
    @Binding var showingAddOverride: Bool
    @Binding var selectedOverride: DateOverride?
    @EnvironmentObject var overrideStore: OverrideStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("ONE-TIME OVERRIDES")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.green)
                Spacer()
                Button {
                    showingAddOverride = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.green)
                }
            }

            if overrideStore.dateOverrides.isEmpty {
                Text("No one-time overrides set")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .padding(.vertical, 8)
            } else {
                ForEach(overrideStore.dateOverrides) { override in
                    DateOverrideRow(override: override, onTap: { selectedOverride = override })
                        .opacity(overrideStore.allAlarmsEnabled ? 1 : 0.5)
                }
            }
        }
    }
}

struct DateOverrideRow: View {
    let override: DateOverride
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Text(override.dateString)
                    .foregroundColor(.white)

                Spacer()

                switch override.action {
                case .disable:
                    Text("Disabled")
                        .foregroundColor(.red)
                case .customTime:
                    Text(override.action.timeString ?? "")
                        .foregroundColor(.green)
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .padding()
            .background(Color(white: 0.1))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ContentView()
        .environmentObject(AlarmStore())
        .environmentObject(CalendarService())
        .environmentObject(OverrideStore())
}
```

**Step 2: Verify it compiles**

Run: `xcodebuild -scheme SFUSD-Alarm -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -20`

Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add SFUSD-Alarm/App/ContentView.swift
git commit -m "feat: redesign ContentView with layered alarm sections"
```

---

## Task 8: Update AlarmEditView for Single Base Alarm

**Files:**
- Modify: `SFUSD-Alarm/Views/AlarmEditView.swift`

**Step 1: Add reschedule call with overrides**

Update the `saveAlarm()` method to use the new scheduling:

```swift
private func saveAlarm() {
    var alarm: Alarm

    if case .edit(let existingAlarm) = mode {
        alarm = existingAlarm
    } else {
        alarm = Alarm.defaultAlarm()
    }

    alarm.time = selectedTime
    alarm.label = label
    alarm.sound = sound
    alarm.snoozeEnabled = snoozeEnabled
    alarm.isEnabled = true

    if case .edit = mode {
        alarmStore.updateAlarm(alarm)
    } else {
        alarmStore.addAlarm(alarm)
    }

    // Schedule notifications using new override-aware method
    // Note: We need overrideStore here, add it as @EnvironmentObject
    NotificationManager.shared.rescheduleAllAlarms(
        alarmStore: alarmStore,
        calendarService: calendarService,
        overrideStore: overrideStore
    )
}
```

Also add `@EnvironmentObject var overrideStore: OverrideStore` to the view.

**Step 2: Verify it compiles**

Run: `xcodebuild -scheme SFUSD-Alarm -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -20`

Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add SFUSD-Alarm/Views/AlarmEditView.swift
git commit -m "feat: update AlarmEditView to use override-aware scheduling"
```

---

## Task 9: Update CalendarView with Override Indicators

**Files:**
- Modify: `SFUSD-Alarm/Views/CalendarView.swift`

**Step 1: Add override store and tap-to-add functionality**

Add override indicators to day cells and tap interaction. Key changes:

1. Add `@EnvironmentObject var overrideStore: OverrideStore`
2. Add `@EnvironmentObject var alarmStore: AlarmStore`
3. Update `DayCell` to show override colors
4. Add tap gesture to open override sheet

This is a significant update to the file. The key additions:

```swift
// In DayCell, update textColor and add ring indicator:
private var ringColor: Color? {
    guard isSchoolDay else { return nil }
    switch activeLayer {
    case .base: return .orange
    case .weekly: return .blue
    case .oneTime: return .green
    }
}

// Add state for showing override sheet
@State private var selectedDateForOverride: Date?
@State private var showingOverrideSheet = false
```

**Step 2: Verify it compiles**

Run: `xcodebuild -scheme SFUSD-Alarm -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -20`

Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add SFUSD-Alarm/Views/CalendarView.swift
git commit -m "feat: add override indicators and tap-to-add to CalendarView"
```

---

## Task 10: Add Queue Reliability - Foreground Refresh

**Files:**
- Modify: `SFUSD-Alarm/App/SFUSD_AlarmApp.swift`

**Step 1: Add foreground refresh trigger**

Update the app to reschedule alarms when entering foreground:

```swift
@main
struct SFUSD_AlarmApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var alarmStore = AlarmStore()
    @StateObject private var calendarService = CalendarService()
    @StateObject private var overrideStore = OverrideStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(alarmStore)
                .environmentObject(calendarService)
                .environmentObject(overrideStore)
                .onAppear {
                    NotificationManager.shared.requestAuthorization()
                    Task {
                        await calendarService.loadCalendar()
                        rescheduleAlarms()
                    }
                }
                .onChange(of: scenePhase) { oldPhase, newPhase in
                    if newPhase == .active {
                        // Reschedule when app comes to foreground
                        rescheduleAlarms()
                    }
                }
        }
    }

    private func rescheduleAlarms() {
        NotificationManager.shared.rescheduleAllAlarms(
            alarmStore: alarmStore,
            calendarService: calendarService,
            overrideStore: overrideStore
        )
    }
}
```

**Step 2: Verify it compiles**

Run: `xcodebuild -scheme SFUSD-Alarm -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -20`

Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add SFUSD-Alarm/App/SFUSD_AlarmApp.swift
git commit -m "feat: add foreground refresh trigger for notification queue"
```

---

## Task 11: Add Queue Reliability - Notification Tap Refresh

**Files:**
- Modify: `SFUSD-Alarm/App/SFUSD_AlarmApp.swift`

**Step 1: Update AppDelegate to trigger reschedule on notification tap**

The AppDelegate needs access to the stores. Update to use a shared coordinator or notification:

```swift
// In AppDelegate, post a notification that the app can observe
func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
    let userInfo = response.notification.request.content.userInfo
    if let alarmId = userInfo["alarmId"] as? String {
        NotificationCenter.default.post(name: .alarmTriggered, object: nil, userInfo: ["alarmId": alarmId])
    }
    // Post reschedule notification
    NotificationCenter.default.post(name: .rescheduleAlarms, object: nil)
    completionHandler()
}

// Add extension
extension Notification.Name {
    static let rescheduleAlarms = Notification.Name("rescheduleAlarms")
}
```

Then in ContentView or App, observe this notification and reschedule.

**Step 2: Verify it compiles**

Run: `xcodebuild -scheme SFUSD-Alarm -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -20`

Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add SFUSD-Alarm/App/SFUSD_AlarmApp.swift
git commit -m "feat: add notification tap trigger for queue refresh"
```

---

## Task 12: Add Background App Refresh

**Files:**
- Modify: `SFUSD-Alarm/Info.plist` (add UIBackgroundModes)
- Modify: `SFUSD-Alarm/App/SFUSD_AlarmApp.swift`
- Modify: `SFUSD-Alarm/Services/NotificationManager.swift`

**Step 1: Enable background fetch in Info.plist**

Add to Info.plist:
```xml
<key>UIBackgroundModes</key>
<array>
    <string>fetch</string>
</array>
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>com.sfusd.alarm.refresh</string>
</array>
```

**Step 2: Register and handle background task**

In AppDelegate:
```swift
import BackgroundTasks

func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    UNUserNotificationCenter.current().delegate = self

    // Register background task
    BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.sfusd.alarm.refresh", using: nil) { task in
        self.handleAppRefresh(task: task as! BGAppRefreshTask)
    }

    return true
}

func handleAppRefresh(task: BGAppRefreshTask) {
    // Schedule next refresh
    scheduleAppRefresh()

    // Post notification to reschedule alarms
    NotificationCenter.default.post(name: .rescheduleAlarms, object: nil)

    task.setTaskCompleted(success: true)
}

func scheduleAppRefresh() {
    let request = BGAppRefreshTaskRequest(identifier: "com.sfusd.alarm.refresh")
    // Schedule for when queue is ~50% depleted (roughly 30 school days out)
    request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 24 * 60 * 60)

    do {
        try BGTaskScheduler.shared.submit(request)
    } catch {
        print("Could not schedule app refresh: \(error)")
    }
}
```

**Step 3: Add smart refresh scheduling to NotificationManager**

```swift
func scheduleBackgroundRefresh(scheduledSchoolDays: [Date]) {
    guard scheduledSchoolDays.count > 0 else { return }

    let halfwayIndex = scheduledSchoolDays.count / 2
    guard halfwayIndex > 0 else { return }

    let request = BGAppRefreshTaskRequest(identifier: "com.sfusd.alarm.refresh")
    request.earliestBeginDate = scheduledSchoolDays[halfwayIndex]

    try? BGTaskScheduler.shared.submit(request)
}
```

**Step 4: Verify it compiles**

Run: `xcodebuild -scheme SFUSD-Alarm -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -20`

Expected: BUILD SUCCEEDED

**Step 5: Commit**

```bash
git add SFUSD-Alarm/Info.plist SFUSD-Alarm/App/SFUSD_AlarmApp.swift SFUSD-Alarm/Services/NotificationManager.swift
git commit -m "feat: add background app refresh for queue reliability"
```

---

## Task 13: Update Legend Colors in CalendarView

**Files:**
- Modify: `SFUSD-Alarm/Views/CalendarView.swift`

**Step 1: Update legend to reflect new color scheme**

```swift
// Legend
HStack(spacing: 20) {
    LegendItem(color: .orange, text: "Base Alarm")
    LegendItem(color: .blue, text: "Weekly Rule")
    LegendItem(color: .green, text: "One-Time")
    LegendItem(color: .gray, text: "No School")
}
.padding(.top)
```

**Step 2: Verify it compiles**

Run: `xcodebuild -scheme SFUSD-Alarm -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -20`

Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add SFUSD-Alarm/Views/CalendarView.swift
git commit -m "feat: update CalendarView legend with override colors"
```

---

## Task 14: Final Integration Test

**Step 1: Build and run the app**

Run: `xcodebuild -scheme SFUSD-Alarm -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -30`

Expected: BUILD SUCCEEDED

**Step 2: Manual testing checklist**

1. [ ] App launches without crash
2. [ ] Can create base alarm
3. [ ] Can add weekly rule (e.g., Tuesday at 7:45 AM)
4. [ ] Can add one-time override (e.g., disable Jan 15)
5. [ ] Next Alarm section shows correct time and color
6. [ ] Calendar view shows correct color indicators
7. [ ] Tapping calendar day opens override sheet
8. [ ] Master toggle disables all alarms
9. [ ] Deleting rules/overrides works
10. [ ] App reschedules on foreground

**Step 3: Commit if all tests pass**

```bash
git add -A
git commit -m "feat: complete calendar overlay feature implementation"
```

---

## Summary

**Files Created:**
- `SFUSD-Alarm/Models/OverrideModels.swift`
- `SFUSD-Alarm/Models/OverrideStore.swift`
- `SFUSD-Alarm/Views/WeeklyRuleEditView.swift`
- `SFUSD-Alarm/Views/DateOverrideEditView.swift`

**Files Modified:**
- `SFUSD-Alarm/App/SFUSD_AlarmApp.swift`
- `SFUSD-Alarm/App/ContentView.swift`
- `SFUSD-Alarm/Views/AlarmEditView.swift`
- `SFUSD-Alarm/Views/CalendarView.swift`
- `SFUSD-Alarm/Services/NotificationManager.swift`
- `SFUSD-Alarm/Info.plist`

**Total Tasks:** 14
**Estimated Commits:** 14
