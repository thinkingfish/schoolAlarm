import SwiftUI
import UserNotifications

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

                        #if DEBUG
                        Divider().background(Color.gray.opacity(0.3)).padding(.vertical, 8)

                        // Debug Test Alarm Section
                        DebugTestAlarmSection()
                            .environmentObject(alarmStore)
                        #endif
                    }
                    .padding(.horizontal)
                }
            }
            .navigationTitle("Wake Up for School")
            .navigationBarTitleDisplayMode(.large)
            .preferredColorScheme(.dark)
            .sheet(isPresented: $showingAddAlarm) {
                AlarmEditView(mode: .add)
            }
            .sheet(item: $selectedAlarm) { alarm in
                AlarmEditView(mode: .edit(alarm))
            }
            .sheet(isPresented: $showingAddWeeklyRule) {
                WeeklyRuleEditView(mode: .add, overrideStore: overrideStore) { rule in
                    overrideStore.addWeeklyRule(rule)
                    rescheduleAllAlarms()
                }
            }
            .sheet(item: $selectedWeeklyRule) { rule in
                WeeklyRuleEditView(mode: .edit(rule), overrideStore: overrideStore, onSave: { updatedRule in
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
            .onReceive(NotificationCenter.default.publisher(for: .alarmTriggered)) { _ in
                rescheduleAllAlarms()
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
                Text("Alarms Disabled")
                    .font(.title2)
                    .foregroundColor(.gray)
                    .padding(.vertical, 20)
            } else if let (nextDate, nextTime, layer) = nextAlarmInfo {
                Text("NEXT ALARM")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.gray)

                Text(formatDate(nextDate))
                    .font(.body)
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
                    .font(.body)
                    .foregroundColor(.orange)
                }
                .padding(.top, 4)
            } else {
                Text("No Upcoming Alarms")
                    .font(.title2)
                    .foregroundColor(.gray)
                    .padding(.vertical, 20)

                NavigationLink {
                    CalendarView()
                } label: {
                    HStack {
                        Image(systemName: "calendar")
                        Text("View Calendar")
                    }
                    .font(.body)
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
        let baseAlarm = alarmStore.alarms.first
        let schoolDays = calendarService.upcomingSchoolDays()

        for day in schoolDays {
            if let time = overrideStore.effectiveAlarmTime(for: day, baseAlarm: baseAlarm) {
                let layer = overrideStore.activeLayer(for: day)
                return (day, time, layer)
            }
        }
        return nil
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
            Text("Alarms Enabled")
                .font(.body)
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
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.orange)
                Spacer()
                if alarmStore.alarms.isEmpty {
                    Button {
                        showingAddAlarm = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundColor(.orange)
                    }
                }
            }

            if let alarm = alarmStore.alarms.first {
                BaseAlarmRow(alarm: alarm, onTap: { selectedAlarm = alarm })
                    .opacity(overrideStore.allAlarmsEnabled ? 1 : 0.5)
            } else {
                Text("Tap + to add a base alarm")
                    .font(.body)
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
                        .font(.body)
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
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)
                Spacer()
                Button {
                    showingAddRule = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
                .disabled(overrideStore.weeklyRules.count >= 5)
            }

            if overrideStore.weeklyRules.isEmpty {
                Text("No weekly rules set")
                    .font(.body)
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
                    .font(.body)
                    .foregroundColor(.white)

                Spacer()

                switch rule.action {
                case .disable:
                    Text("Disabled")
                        .font(.body)
                        .foregroundColor(.red)
                case .customTime:
                    Text(rule.action.timeString ?? "")
                        .font(.body)
                        .foregroundColor(.blue)
                }

                Image(systemName: "chevron.right")
                    .font(.subheadline)
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
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.green)
                Spacer()
                Button {
                    showingAddOverride = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(.green)
                }
            }

            if overrideStore.dateOverrides.isEmpty {
                Text("No one-time overrides set")
                    .font(.body)
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
                    .font(.body)
                    .foregroundColor(.white)

                Spacer()

                switch override.action {
                case .disable:
                    Text("Disabled")
                        .font(.body)
                        .foregroundColor(.red)
                case .customTime:
                    Text(override.action.timeString ?? "")
                        .font(.body)
                        .foregroundColor(.green)
                }

                Image(systemName: "chevron.right")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            .padding()
            .background(Color(white: 0.1))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG
// MARK: - Debug Test Alarm Section

struct DebugTestAlarmSection: View {
    @EnvironmentObject var alarmStore: AlarmStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var alarmCount: Int = 0
    @State private var testCount: Int = 0
    @State private var permissionStatus: String = "Tap to check"
    @State private var showingDebugCalendar = false

    private var soundName: String {
        alarmStore.alarms.first?.alarmSoundName ?? Alarm.BundledSound.funnyRing.rawValue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("DEBUG: TEST ALARMS")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.red)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(alarmCount) alarms")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Text("\(testCount) tests")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            Text("Fire test notification in:")
                .font(.caption)
                .foregroundColor(.gray)

            HStack(spacing: 12) {
                TestAlarmButton(label: "5s", delay: 5, soundName: soundName, onScheduled: updateCounts)
                TestAlarmButton(label: "10s", delay: 10, soundName: soundName, onScheduled: updateCounts)
                TestAlarmButton(label: "30s", delay: 30, soundName: soundName, onScheduled: updateCounts)
                TestAlarmButton(label: "1m", delay: 60, soundName: soundName, onScheduled: updateCounts)
            }

            Button {
                NotificationManager.shared.cancelTestNotifications()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    updateCounts()
                }
            } label: {
                HStack {
                    Spacer()
                    Text("Cancel Test Notifications")
                        .font(.subheadline)
                    Spacer()
                }
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.3))
                .cornerRadius(8)
            }
            .foregroundColor(.red)

            // Permission diagnostics button
            Button {
                checkPermissions()
            } label: {
                HStack {
                    Spacer()
                    Text("Check Permissions")
                        .font(.subheadline)
                    Spacer()
                }
                .padding(.vertical, 8)
                .background(Color.blue.opacity(0.3))
                .cornerRadius(8)
            }
            .foregroundColor(.blue)

            Text(permissionStatus)
                .font(.caption2)
                .foregroundColor(.gray)
                .fixedSize(horizontal: false, vertical: true)

            // Open Settings button
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                HStack {
                    Spacer()
                    Text("Open App Settings")
                        .font(.subheadline)
                    Spacer()
                }
                .padding(.vertical, 8)
                .background(Color.gray.opacity(0.3))
                .cornerRadius(8)
            }
            .foregroundColor(.white)

            // Debug calendar button
            Button {
                showingDebugCalendar = true
            } label: {
                HStack {
                    Spacer()
                    Text("View Debug Calendar")
                        .font(.subheadline)
                    Spacer()
                }
                .padding(.vertical, 8)
                .background(Color.purple.opacity(0.3))
                .cornerRadius(8)
            }
            .foregroundColor(.purple)
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.red.opacity(0.3), lineWidth: 1)
        )
        .onAppear {
            updateCounts()
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                updateCounts()
            }
        }
        .sheet(isPresented: $showingDebugCalendar) {
            DebugCalendarView()
        }
    }

    private func updateCounts() {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let tests = requests.filter { $0.identifier.hasPrefix("test_") || $0.identifier.hasPrefix("snooze_") }
            let alarms = requests.filter { !$0.identifier.hasPrefix("test_") && !$0.identifier.hasPrefix("snooze_") }

            DispatchQueue.main.async {
                testCount = tests.count
                alarmCount = alarms.count
            }
        }
    }

    private func checkPermissions() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                let auth = switch settings.authorizationStatus {
                case .notDetermined: "Not Determined"
                case .denied: "DENIED"
                case .authorized: "Authorized"
                case .provisional: "Provisional"
                case .ephemeral: "Ephemeral"
                @unknown default: "Unknown"
                }

                let lockScreen = switch settings.lockScreenSetting {
                case .notSupported: "N/A"
                case .disabled: "DISABLED"
                case .enabled: "Enabled"
                @unknown default: "Unknown"
                }

                let notifCenter = switch settings.notificationCenterSetting {
                case .notSupported: "N/A"
                case .disabled: "DISABLED"
                case .enabled: "Enabled"
                @unknown default: "Unknown"
                }

                let alert = switch settings.alertSetting {
                case .notSupported: "N/A"
                case .disabled: "DISABLED"
                case .enabled: "Enabled"
                @unknown default: "Unknown"
                }

                let sound = switch settings.soundSetting {
                case .notSupported: "N/A"
                case .disabled: "DISABLED"
                case .enabled: "Enabled"
                @unknown default: "Unknown"
                }

                let badge = switch settings.badgeSetting {
                case .notSupported: "N/A"
                case .disabled: "DISABLED"
                case .enabled: "Enabled"
                @unknown default: "Unknown"
                }

                let alertStyle = switch settings.alertStyle {
                case .none: "None"
                case .banner: "Banner"
                case .alert: "Alert"
                @unknown default: "Unknown"
                }

                let timeSensitive = switch settings.timeSensitiveSetting {
                case .notSupported: "N/A"
                case .disabled: "DISABLED"
                case .enabled: "Enabled"
                @unknown default: "Unknown"
                }

                permissionStatus = """
                Auth: \(auth) | Lock: \(lockScreen) | Center: \(notifCenter)
                Alert: \(alert) (\(alertStyle)) | Sound: \(sound) | Badge: \(badge)
                TimeSensitive: \(timeSensitive)
                """

                print("=== Notification Settings ===")
                print("Authorization: \(auth)")
                print("Lock Screen: \(lockScreen)")
                print("Notification Center: \(notifCenter)")
                print("Alert: \(alert)")
                print("Alert Style: \(alertStyle)")
                print("Sound: \(sound)")
                print("Badge: \(badge)")
                print("Time Sensitive: \(timeSensitive)")
                print("=============================")
            }
        }
    }
}

struct TestAlarmButton: View {
    let label: String
    let delay: TimeInterval
    let soundName: String
    let onScheduled: () -> Void

    var body: some View {
        Button {
            NotificationManager.shared.scheduleTestNotification(delaySeconds: delay, soundName: soundName)
            // Verify the notification was actually scheduled
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
                    let testRequests = requests.filter { $0.identifier.hasPrefix("test_") }
                    print("📋 Pending test notifications: \(testRequests.count)")
                    for req in testRequests {
                        if let trigger = req.trigger as? UNTimeIntervalNotificationTrigger {
                            print("   - \(req.identifier): fires in \(trigger.timeInterval)s")
                        }
                    }
                }
                onScheduled()
            }
        } label: {
            Text(label)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.red.opacity(0.6))
                .cornerRadius(8)
        }
    }
}

// MARK: - Debug Calendar View

struct DebugCalendarView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentMonth: Date = Date()
    @State private var notificationsByDate: [Date: [UNNotificationRequest]] = [:]
    @State private var totalCount: Int = 0

    private let calendar = Calendar.current
    private let daysOfWeek = ["S", "M", "T", "W", "T", "F", "S"]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 20) {
                    // Total count
                    Text("\(totalCount) total notifications scheduled")
                        .font(.headline)
                        .foregroundColor(.orange)
                        .padding(.top)

                    // Month navigation
                    HStack {
                        Button {
                            changeMonth(by: -1)
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.title2)
                                .foregroundColor(.purple)
                        }

                        Spacer()

                        Text(monthYearString)
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)

                        Spacer()

                        Button {
                            changeMonth(by: 1)
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.title2)
                                .foregroundColor(.purple)
                        }
                    }
                    .padding(.horizontal)

                    // Days of week header
                    HStack {
                        ForEach(Array(daysOfWeek.enumerated()), id: \.offset) { _, day in
                            Text(day)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.gray)
                                .frame(maxWidth: .infinity)
                        }
                    }

                    // Calendar grid
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                        ForEach(Array(daysInMonth.enumerated()), id: \.offset) { _, date in
                            if let date = date {
                                DebugDayCell(
                                    date: date,
                                    isToday: calendar.isDateInToday(date),
                                    isCurrentMonth: isInCurrentMonth(date),
                                    notificationCount: notificationsByDate[calendar.startOfDay(for: date)]?.count ?? 0
                                )
                            } else {
                                Color.clear
                                    .frame(width: 36, height: 50)
                            }
                        }
                    }
                    .padding(.horizontal, 8)

                    // Legend
                    VStack(alignment: .leading, spacing: 4) {
                        Text("NOTIFICATION COUNTS")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.gray)

                        HStack(spacing: 16) {
                            HStack(spacing: 4) {
                                Circle().fill(Color.green).frame(width: 10, height: 10)
                                Text("1-3")
                            }
                            HStack(spacing: 4) {
                                Circle().fill(Color.orange).frame(width: 10, height: 10)
                                Text("4-6")
                            }
                            HStack(spacing: 4) {
                                Circle().fill(Color.red).frame(width: 10, height: 10)
                                Text("7+")
                            }
                        }
                        .font(.caption)
                        .foregroundColor(.gray)
                    }
                    .padding(.top)

                    Spacer()

                    // Refresh button
                    Button {
                        refreshNotifications()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Refresh")
                        }
                        .font(.subheadline)
                        .foregroundColor(.purple)
                    }
                    .padding(.bottom)
                }
            }
            .navigationTitle("Debug Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                refreshNotifications()
            }
        }
    }

    private var monthYearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: currentMonth)
    }

    private var daysInMonth: [Date?] {
        var days: [Date?] = []

        let firstOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: currentMonth))!
        let firstWeekday = calendar.component(.weekday, from: firstOfMonth)

        for _ in 1..<firstWeekday {
            days.append(nil)
        }

        let range = calendar.range(of: .day, in: .month, for: currentMonth)!
        for day in range {
            var components = calendar.dateComponents([.year, .month], from: currentMonth)
            components.day = day
            if let date = calendar.date(from: components) {
                days.append(date)
            }
        }

        return days
    }

    private func changeMonth(by value: Int) {
        if let newMonth = calendar.date(byAdding: .month, value: value, to: currentMonth) {
            currentMonth = newMonth
        }
    }

    private func isInCurrentMonth(_ date: Date) -> Bool {
        calendar.isDate(date, equalTo: currentMonth, toGranularity: .month)
    }

    private func refreshNotifications() {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            var byDate: [Date: [UNNotificationRequest]] = [:]

            for request in requests {
                if let trigger = request.trigger as? UNCalendarNotificationTrigger,
                   let triggerDate = trigger.nextTriggerDate() {
                    let dayStart = calendar.startOfDay(for: triggerDate)
                    byDate[dayStart, default: []].append(request)
                }
            }

            DispatchQueue.main.async {
                notificationsByDate = byDate
                totalCount = requests.count
            }
        }
    }
}

struct DebugDayCell: View {
    let date: Date
    let isToday: Bool
    let isCurrentMonth: Bool
    let notificationCount: Int

    private var dayNumber: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                if isToday {
                    Circle()
                        .fill(Color.purple)
                        .frame(width: 32, height: 32)
                }

                Text(dayNumber)
                    .font(.system(size: 16, weight: isToday ? .bold : .regular))
                    .foregroundColor(textColor)
            }

            if notificationCount > 0 {
                Text("\(notificationCount)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(countColor)
            } else {
                Text(" ")
                    .font(.system(size: 10))
            }
        }
        .frame(height: 50)
    }

    private var textColor: Color {
        if isToday {
            return .white
        } else if !isCurrentMonth {
            return .gray.opacity(0.3)
        } else {
            return .white
        }
    }

    private var countColor: Color {
        if notificationCount >= 7 {
            return .red
        } else if notificationCount >= 4 {
            return .orange
        } else {
            return .green
        }
    }
}
#endif

#Preview {
    ContentView()
        .environmentObject(AlarmStore())
        .environmentObject(CalendarService())
        .environmentObject(OverrideStore())
}
