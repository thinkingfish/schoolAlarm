import SwiftUI

// MARK: - School Day Date Picker

struct SchoolDayDatePicker: View {
    @Binding var selectedDate: Date
    @EnvironmentObject var calendarService: CalendarService

    @State private var currentMonth: Date

    private let calendar = Calendar.current
    private let daysOfWeek = ["S", "M", "T", "W", "T", "F", "S"]

    init(selectedDate: Binding<Date>) {
        self._selectedDate = selectedDate
        self._currentMonth = State(initialValue: selectedDate.wrappedValue)
    }

    var body: some View {
        VStack(spacing: 12) {
            // Month navigation
            HStack {
                Button {
                    changeMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body)
                        .foregroundColor(.green)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)

                Spacer()

                Text(monthYearString)
                    .font(.headline)
                    .foregroundColor(.white)

                Spacer()

                Button {
                    changeMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.body)
                        .foregroundColor(.green)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
            }

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
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 6) {
                ForEach(Array(daysInMonth.enumerated()), id: \.offset) { _, date in
                    if let date = date {
                        SchoolDayCell(
                            date: date,
                            isSchoolDay: calendarService.isSchoolDay(date),
                            isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                            isToday: calendar.isDateInToday(date),
                            isCurrentMonth: isInCurrentMonth(date),
                            isPast: isPastDate(date),
                            onTap: {
                                selectedDate = date
                            }
                        )
                    } else {
                        Color.clear
                            .frame(width: 32, height: 36)
                    }
                }
            }
        }
        .onChange(of: selectedDate) { newDate in
            // If selected date is in a different month, update the view
            if !calendar.isDate(newDate, equalTo: currentMonth, toGranularity: .month) {
                currentMonth = newDate
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

    private func changeMonth(by value: Int) {
        if let newMonth = calendar.date(byAdding: .month, value: value, to: currentMonth) {
            currentMonth = newMonth
        }
    }

    private func isInCurrentMonth(_ date: Date) -> Bool {
        calendar.isDate(date, equalTo: currentMonth, toGranularity: .month)
    }

    private func isPastDate(_ date: Date) -> Bool {
        calendar.startOfDay(for: date) < calendar.startOfDay(for: Date())
    }
}

struct SchoolDayCell: View {
    let date: Date
    let isSchoolDay: Bool
    let isSelected: Bool
    let isToday: Bool
    let isCurrentMonth: Bool
    let isPast: Bool
    let onTap: () -> Void

    private var dayNumber: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }

    private var isSelectable: Bool {
        isSchoolDay && isCurrentMonth && !isPast
    }

    var body: some View {
        Button(action: onTap) {
            ZStack {
                // Selected indicator
                if isSelected && isSelectable {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 32, height: 32)
                } else if isToday {
                    Circle()
                        .stroke(Color.green.opacity(0.5), lineWidth: 1)
                        .frame(width: 32, height: 32)
                }

                Text(dayNumber)
                    .font(.system(size: 15, weight: isSelected || isToday ? .semibold : .regular))
                    .foregroundColor(textColor)
            }
            .frame(height: 36)
        }
        .buttonStyle(.plain)
        .disabled(!isSelectable)
    }

    private var textColor: Color {
        if isSelected && isSelectable {
            return .white
        } else if !isCurrentMonth || isPast {
            return .gray.opacity(0.3)
        } else if isSchoolDay {
            return .white
        } else {
            return .gray.opacity(0.4)
        }
    }
}

// MARK: - Date Override Edit Mode

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
                            SchoolDayDatePicker(selectedDate: $selectedDate)
                                .padding(.vertical, 8)
                        } header: {
                            Text("DATE (SCHOOL DAYS ONLY)")
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
            .onAppear {
                // Ensure selected date is a school day when adding new override
                if mode.override == nil && mode.preselectedDate == nil {
                    if !calendarService.isSchoolDay(selectedDate) {
                        selectedDate = findNextSchoolDay(from: selectedDate)
                    }
                }
            }
        }
    }

    private func findNextSchoolDay(from date: Date) -> Date {
        var candidate = date
        let calendar = Calendar.current
        // Look up to 365 days ahead
        for _ in 0..<365 {
            if calendarService.isSchoolDay(candidate) {
                return candidate
            }
            candidate = calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate
        }
        return date  // Fallback to original if no school day found
    }

    private var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d, yyyy"
        return formatter.string(from: selectedDate)
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
