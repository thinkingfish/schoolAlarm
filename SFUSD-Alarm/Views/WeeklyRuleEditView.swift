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
