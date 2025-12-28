import SwiftUI

struct CalendarView: View {
    @EnvironmentObject var calendarService: CalendarService
    @EnvironmentObject var overrideStore: OverrideStore
    @EnvironmentObject var alarmStore: AlarmStore

    @State private var currentMonth: Date = Date()
    @State private var selectedDateForOverride: IdentifiableDate?
    #if DEBUG
    @State private var notificationCountsByDate: [Date: Int] = [:]
    #endif

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
                    ForEach(Array(daysInMonth.enumerated()), id: \.offset) { index, date in
                        if let date = date {
                            #if DEBUG
                            DayCellWithOverride(
                                date: date,
                                isSchoolDay: calendarService.isSchoolDay(date),
                                isToday: calendar.isDateInToday(date),
                                isCurrentMonth: isInCurrentMonth(date),
                                activeLayer: overrideStore.activeLayer(for: date),
                                isDisabled: isDateDisabled(date),
                                notificationCount: notificationCountsByDate[calendar.startOfDay(for: date)] ?? 0,
                                onTap: {
                                    if calendarService.isSchoolDay(date) {
                                        selectedDateForOverride = IdentifiableDate(date: date)
                                    }
                                }
                            )
                            #else
                            DayCellWithOverride(
                                date: date,
                                isSchoolDay: calendarService.isSchoolDay(date),
                                isToday: calendar.isDateInToday(date),
                                isCurrentMonth: isInCurrentMonth(date),
                                activeLayer: overrideStore.activeLayer(for: date),
                                isDisabled: isDateDisabled(date),
                                onTap: {
                                    if calendarService.isSchoolDay(date) {
                                        selectedDateForOverride = IdentifiableDate(date: date)
                                    }
                                }
                            )
                            #endif
                        } else {
                            Color.clear
                                .frame(width: 36, height: 40)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 50, coordinateSpace: .local)
                        .onEnded { value in
                            let horizontalDistance = value.translation.width
                            let verticalDistance = abs(value.translation.height)

                            // Only trigger if horizontal swipe is dominant
                            if abs(horizontalDistance) > verticalDistance {
                                if horizontalDistance > 0 {
                                    changeMonth(by: -1)
                                } else {
                                    changeMonth(by: 1)
                                }
                            }
                        }
                )

                // Legend
                HStack(spacing: 16) {
                    LegendItem(color: .orange, text: "Base", style: .base)
                    LegendItem(color: .blue, text: "Weekly", style: .weekly)
                    LegendItem(color: .green, text: "One-Time", style: .oneTime)
                    LegendItem(color: .gray, text: "No School", style: .noSchool)
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
        .navigationTitle("SFUSD Calendar (2025-2026)")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .sheet(item: $selectedDateForOverride) { identifiableDate in
            let date = identifiableDate.date
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
        #if DEBUG
        .onAppear {
            refreshNotificationCounts()
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Text("\(notificationCountsByDate.values.reduce(0, +)) notifs")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        #endif
    }

    #if DEBUG
    private func refreshNotificationCounts() {
        NotificationManager.shared.getPendingNotificationsByDate { counts in
            notificationCountsByDate = counts
        }
    }
    #endif

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
        let schoolYearEnd = SchoolCalendar.schoolYearEnd
        return calendarService.calendar.events
            .filter { event in
                guard event.isHoliday && event.startDate <= schoolYearEnd else { return false }
                // Include if event hasn't ended yet (covers both upcoming and ongoing)
                return event.endDate > now
            }
            .sorted { $0.startDate < $1.startDate }
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

// Wrapper for Date to use with sheet(item:) binding
struct IdentifiableDate: Identifiable {
    let date: Date
    var id: TimeInterval { date.timeIntervalSince1970 }
}

struct DayCellWithOverride: View {
    let date: Date
    let isSchoolDay: Bool
    let isToday: Bool
    let isCurrentMonth: Bool
    let activeLayer: AlarmLayer
    let isDisabled: Bool
    #if DEBUG
    var notificationCount: Int = 0
    #endif
    let onTap: () -> Void

    private var dayNumber: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                ZStack {
                    // Ring(s) for school days
                    if isSchoolDay && isCurrentMonth {
                        // Outer ring (always present for school days)
                        Circle()
                            .stroke(ringColor, lineWidth: 2)
                            .frame(width: 36, height: 36)
                            .opacity(isDisabled ? 0.4 : 1.0)

                        // Inner ring for weekly (double ring pattern)
                        if activeLayer == .weekly && !isDisabled {
                            Circle()
                                .stroke(ringColor, lineWidth: 2)
                                .frame(width: 28, height: 28)
                        }

                        // Solid filled center for one-time overrides
                        if activeLayer == .oneTime && !isDisabled {
                            Circle()
                                .fill(ringColor)
                                .frame(width: 32, height: 32)
                        }
                    }

                    // Today indicator (filled circle)
                    if isToday {
                        Circle()
                            .fill(isSchoolDay ? Color.orange : Color(white: 0.85))
                            .frame(width: 32, height: 32)
                    }

                    Text(dayNumber)
                        .font(.system(size: 16, weight: isToday ? .bold : .regular))
                        .foregroundColor(textColor)
                        .strikethrough(isDisabled && isSchoolDay && isCurrentMonth, color: .red)
                }

                #if DEBUG
                if notificationCount > 0 {
                    Text("\(notificationCount)")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.orange)
                } else {
                    Text(" ")
                        .font(.system(size: 8))
                }
                #endif
            }
            .frame(height: 50)
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
            return .white
        } else if !isCurrentMonth {
            return .gray.opacity(0.5)
        } else if isSchoolDay {
            if isDisabled {
                return .gray
            }
            switch activeLayer {
            case .base: return .orange
            case .weekly: return .blue
            case .oneTime: return .white  // White text on solid green background
            }
        } else {
            return .gray
        }
    }
}

enum LegendStyle {
    case base       // Single ring
    case weekly     // Double ring
    case oneTime    // Ring with filled center
    case noSchool   // Solid fill
}

struct LegendItem: View {
    let color: Color
    let text: String
    var style: LegendStyle = .noSchool

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                switch style {
                case .base:
                    // Single ring
                    Circle()
                        .stroke(color, lineWidth: 1.5)
                        .frame(width: 12, height: 12)
                case .weekly:
                    // Double ring
                    Circle()
                        .stroke(color, lineWidth: 1.5)
                        .frame(width: 12, height: 12)
                    Circle()
                        .stroke(color, lineWidth: 1.5)
                        .frame(width: 7, height: 7)
                case .oneTime:
                    // Solid filled circle
                    Circle()
                        .fill(color)
                        .frame(width: 12, height: 12)
                case .noSchool:
                    // Solid fill
                    Circle()
                        .fill(color)
                        .frame(width: 10, height: 10)
                }
            }
            .frame(width: 14, height: 14)
            Text(text)
                .font(.caption)
                .foregroundColor(.gray)
        }
    }
}

struct UpcomingHolidaysSection: View {
    let events: [SchoolCalendarEvent]

    private let calendar = Calendar.current

    var body: some View {
        if !events.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("UPCOMING SCHOOL HOLIDAYS")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.gray)
                    .padding(.horizontal)

                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(events) { event in
                            HStack {
                                Text(event.summary)
                                    .font(.subheadline)
                                    .foregroundColor(.white)
                                    .lineLimit(1)

                                Spacer()

                                Text(formatDateRange(event))
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
                }
                .frame(maxHeight: 200)
                .background(Color(white: 0.15))
                .cornerRadius(10)
                .padding(.horizontal)
            }
        }
    }

    private func formatDateRange(_ event: SchoolCalendarEvent) -> String {
        let startFormatter = DateFormatter()
        startFormatter.dateFormat = "MMM d"

        // For all-day events, end date is exclusive, so subtract one day for display
        let displayEndDate: Date
        if event.isAllDay {
            displayEndDate = calendar.date(byAdding: .day, value: -1, to: event.endDate) ?? event.endDate
        } else {
            displayEndDate = event.endDate
        }

        // Check if it's a single day event
        let startDay = calendar.startOfDay(for: event.startDate)
        let endDay = calendar.startOfDay(for: displayEndDate)

        if startDay == endDay {
            return startFormatter.string(from: event.startDate)
        } else {
            // Multi-day event - show range
            let endFormatter = DateFormatter()

            // If same month, only show day for end date
            if calendar.component(.month, from: event.startDate) == calendar.component(.month, from: displayEndDate) {
                endFormatter.dateFormat = "d"
            } else {
                endFormatter.dateFormat = "MMM d"
            }

            return "\(startFormatter.string(from: event.startDate)) - \(endFormatter.string(from: displayEndDate))"
        }
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
