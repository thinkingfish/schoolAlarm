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
