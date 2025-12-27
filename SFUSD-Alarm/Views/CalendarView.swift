import SwiftUI

struct CalendarView: View {
    @EnvironmentObject var calendarService: CalendarService
    @EnvironmentObject var overrideStore: OverrideStore
    @EnvironmentObject var alarmStore: AlarmStore

    @State private var currentMonth: Date = Date()
    @State private var selectedDateForOverride: Date?

    private let calendar = Calendar.current
    private let daysOfWeek = ["S", "M", "T", "W", "T", "F", "S"]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 20) {
                // Month navigation
                HStack {
                    Button {
                        changeMonth(by: -1)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.title2)
                            .foregroundColor(.orange)
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
                            .foregroundColor(.orange)
                    }
                }
                .padding(.horizontal)

                // Days of week header
                HStack {
                    ForEach(daysOfWeek, id: \.self) { day in
                        Text(day)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity)
                    }
                }

                // Calendar grid
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                    ForEach(daysInMonth, id: \.self) { date in
                        if let date = date {
                            DayCellWithOverride(
                                date: date,
                                isSchoolDay: calendarService.isSchoolDay(date),
                                isToday: calendar.isDateInToday(date),
                                isCurrentMonth: isInCurrentMonth(date),
                                activeLayer: overrideStore.activeLayer(for: date),
                                isDisabled: isDateDisabled(date),
                                onTap: {
                                    if calendarService.isSchoolDay(date) {
                                        selectedDateForOverride = date
                                    }
                                }
                            )
                        } else {
                            Text("")
                                .frame(height: 40)
                        }
                    }
                }
                .padding(.horizontal, 8)

                // Legend
                HStack(spacing: 16) {
                    LegendItem(color: .orange, text: "Base")
                    LegendItem(color: .blue, text: "Weekly")
                    LegendItem(color: .green, text: "One-Time")
                    LegendItem(color: .gray, text: "No School")
                }
                .padding(.top)

                // Upcoming holidays
                UpcomingHolidaysSection(events: upcomingHolidays)

                Spacer()

                // Refresh button
                Button {
                    Task {
                        await calendarService.refreshCalendar()
                    }
                } label: {
                    HStack {
                        if calendarService.isLoading {
                            ProgressView()
                                .tint(.orange)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text("Refresh Calendar")
                    }
                    .font(.subheadline)
                    .foregroundColor(.orange)
                }
                .disabled(calendarService.isLoading)
                .padding(.bottom)

                if let lastRefresh = calendarService.lastRefresh {
                    Text("Last updated: \(lastRefresh, formatter: lastUpdatedFormatter)")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .padding(.bottom)
                }
            }
        }
        .navigationTitle("School Calendar")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .sheet(item: $selectedDateForOverride) { date in
            let existingOverride = overrideStore.dateOverride(for: date)
            if let override = existingOverride {
                DateOverrideEditView(
                    mode: .edit(override),
                    onSave: { updatedOverride in
                        overrideStore.updateDateOverride(updatedOverride)
                        rescheduleAllAlarms()
                    },
                    onDelete: {
                        overrideStore.deleteDateOverride(override)
                        rescheduleAllAlarms()
                    }
                )
            } else {
                DateOverrideEditView(
                    mode: .addForDate(date),
                    onSave: { newOverride in
                        overrideStore.addDateOverride(newOverride)
                        rescheduleAllAlarms()
                    }
                )
            }
        }
    }

    private func isDateDisabled(_ date: Date) -> Bool {
        guard calendarService.isSchoolDay(date) else { return false }
        let baseAlarm = alarmStore.alarms.first
        return overrideStore.effectiveAlarmTime(for: date, baseAlarm: baseAlarm) == nil
    }

    private func rescheduleAllAlarms() {
        NotificationManager.shared.rescheduleAllAlarms(
            alarmStore: alarmStore,
            calendarService: calendarService,
            overrideStore: overrideStore
        )
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

        // Add empty cells for days before the first of the month
        for _ in 1..<firstWeekday {
            days.append(nil)
        }

        // Add days of the month
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

    private var upcomingHolidays: [SchoolCalendarEvent] {
        let now = Date()
        return calendarService.calendar.events
            .filter { $0.isHoliday && $0.startDate >= now }
            .sorted { $0.startDate < $1.startDate }
            .prefix(5)
            .map { $0 }
    }

    private func changeMonth(by value: Int) {
        if let newMonth = calendar.date(byAdding: .month, value: value, to: currentMonth) {
            currentMonth = newMonth
        }
    }

    private func isInCurrentMonth(_ date: Date) -> Bool {
        calendar.isDate(date, equalTo: currentMonth, toGranularity: .month)
    }

    private var lastUpdatedFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }
}

// Make Date conform to Identifiable for sheet binding
extension Date: Identifiable {
    public var id: TimeInterval { timeIntervalSince1970 }
}

struct DayCellWithOverride: View {
    let date: Date
    let isSchoolDay: Bool
    let isToday: Bool
    let isCurrentMonth: Bool
    let activeLayer: AlarmLayer
    let isDisabled: Bool
    let onTap: () -> Void

    private var dayNumber: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }

    var body: some View {
        Button(action: onTap) {
            ZStack {
                // Ring for school days
                if isSchoolDay && isCurrentMonth {
                    Circle()
                        .stroke(ringColor, lineWidth: 2)
                        .frame(width: 36, height: 36)
                        .opacity(isDisabled ? 0.4 : 1.0)
                }

                // Today indicator (filled circle)
                if isToday {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 32, height: 32)
                }

                Text(dayNumber)
                    .font(.system(size: 16, weight: isToday ? .bold : .regular))
                    .foregroundColor(textColor)
                    .strikethrough(isDisabled && isSchoolDay && isCurrentMonth, color: .red)
            }
            .frame(height: 40)
        }
        .buttonStyle(.plain)
        .disabled(!isSchoolDay)
    }

    private var ringColor: Color {
        if isDisabled {
            return .red.opacity(0.5)
        }
        switch activeLayer {
        case .base: return .orange
        case .weekly: return .blue
        case .oneTime: return .green
        }
    }

    private var textColor: Color {
        if isToday {
            return .black
        } else if !isCurrentMonth {
            return .gray.opacity(0.5)
        } else if isSchoolDay {
            if isDisabled {
                return .gray
            }
            switch activeLayer {
            case .base: return .orange
            case .weekly: return .blue
            case .oneTime: return .green
            }
        } else {
            return .gray
        }
    }
}

struct LegendItem: View {
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            Text(text)
                .font(.caption)
                .foregroundColor(.gray)
        }
    }
}

struct UpcomingHolidaysSection: View {
    let events: [SchoolCalendarEvent]

    var body: some View {
        if !events.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("UPCOMING DAYS OFF")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.gray)
                    .padding(.horizontal)

                VStack(spacing: 0) {
                    ForEach(events) { event in
                        HStack {
                            Text(event.summary)
                                .font(.subheadline)
                                .foregroundColor(.white)
                                .lineLimit(1)

                            Spacer()

                            Text(formatDate(event.startDate))
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)

                        if event.id != events.last?.id {
                            Divider()
                                .background(Color.gray.opacity(0.3))
                        }
                    }
                }
                .background(Color(white: 0.15))
                .cornerRadius(10)
                .padding(.horizontal)
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}

#Preview {
    NavigationStack {
        CalendarView()
            .environmentObject(CalendarService())
            .environmentObject(OverrideStore())
            .environmentObject(AlarmStore())
    }
}
