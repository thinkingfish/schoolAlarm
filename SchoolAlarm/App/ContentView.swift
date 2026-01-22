import SwiftUI

struct ContentView: View {
    @EnvironmentObject var alarmStore: AlarmStore
    @EnvironmentObject var calendarService: CalendarService
    @EnvironmentObject var overrideStore: OverrideStore
    @EnvironmentObject var districtStore: DistrictStore

    private var district: District {
        districtStore.selectedDistrict!
    }

    @State private var showingAddAlarm = false
    @State private var showingAddWeeklyRule = false
    @State private var showingAddDateOverride = false
    @State private var selectedAlarm: Alarm?
    @State private var selectedWeeklyRule: WeeklyRule?
    @State private var selectedDateOverride: DateOverride?
    @State private var showingDistrictSelection = false

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
                            .environmentObject(districtStore)

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
                        .environmentObject(calendarService)
                        .environmentObject(districtStore)

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
            .navigationTitle("Wake Up for School")
            .navigationBarTitleDisplayMode(.large)
            .preferredColorScheme(.dark)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingDistrictSelection = true
                    } label: {
                        HStack(spacing: 4) {
                            Text(district.shortName)
                                .font(.subheadline)
                            Image(systemName: "chevron.down")
                                .font(.caption)
                        }
                        .foregroundColor(.orange)
                    }
                }
            }
            .sheet(isPresented: $showingDistrictSelection) {
                NavigationStack {
                    DistrictSelectionView { newDistrict in
                        Task {
                            await calendarService.loadCalendar(for: newDistrict)
                            rescheduleAllAlarms()
                        }
                    }
                    .environmentObject(districtStore)
                }
            }
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
        }
    }

    private func rescheduleAllAlarms() {
        AlarmKitManager.shared.rescheduleAllAlarms(
            alarmStore: alarmStore,
            calendarService: calendarService,
            overrideStore: overrideStore,
            district: district
        )
    }
}

// MARK: - Next Alarm Section

struct NextAlarmSection: View {
    @EnvironmentObject var calendarService: CalendarService
    @EnvironmentObject var overrideStore: OverrideStore
    @EnvironmentObject var alarmStore: AlarmStore
    @EnvironmentObject var districtStore: DistrictStore

    private var district: District {
        districtStore.selectedDistrict!
    }

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
        let schoolDays = calendarService.upcomingSchoolDays(district: district)
        let now = Date()
        let calendar = Calendar.current

        for day in schoolDays {
            if let time = overrideStore.effectiveAlarmTime(for: day, baseAlarm: baseAlarm) {
                // Combine the school day date with the alarm time
                let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
                if let alarmDateTime = calendar.date(bySettingHour: timeComponents.hour ?? 0,
                                                      minute: timeComponents.minute ?? 0,
                                                      second: 0,
                                                      of: day) {
                    // Skip if this alarm time has already passed
                    if alarmDateTime <= now {
                        continue
                    }
                }

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
    @EnvironmentObject var districtStore: DistrictStore

    private var district: District {
        districtStore.selectedDistrict!
    }

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
        AlarmKitManager.shared.rescheduleAllAlarms(
            alarmStore: alarmStore,
            calendarService: calendarService,
            overrideStore: overrideStore,
            district: district
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

#Preview {
    ContentView()
        .environmentObject(AlarmStore())
        .environmentObject(CalendarService())
        .environmentObject(OverrideStore())
        .environmentObject(DistrictStore())
}
