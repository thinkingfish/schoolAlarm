import SwiftUI

enum AlarmEditMode: Identifiable {
    case add
    case edit(Alarm)

    var id: String {
        switch self {
        case .add: return "add"
        case .edit(let alarm): return alarm.id.uuidString
        }
    }

    var alarm: Alarm? {
        switch self {
        case .add: return nil
        case .edit(let alarm): return alarm
        }
    }

    var title: String {
        switch self {
        case .add: return "Add Alarm"
        case .edit: return "Edit Alarm"
        }
    }
}

struct AlarmEditView: View {
    let mode: AlarmEditMode

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var alarmStore: AlarmStore
    @EnvironmentObject var calendarService: CalendarService
    @EnvironmentObject var overrideStore: OverrideStore
    @EnvironmentObject var districtStore: DistrictStore

    private var district: District {
        districtStore.selectedDistrict!
    }

    @State private var selectedTime: Date
    @State private var label: String
    @State private var snoozeEnabled: Bool
    @State private var selectedSound: Alarm.AlarmSound

    @State private var showingDeleteConfirmation = false
    @AppStorage("easterEggUnlocked") private var easterEggUnlocked = false

    init(mode: AlarmEditMode) {
        self.mode = mode

        let alarm = mode.alarm ?? Alarm.defaultAlarm()
        _selectedTime = State(initialValue: alarm.time)
        _label = State(initialValue: alarm.label)
        _snoozeEnabled = State(initialValue: alarm.snoozeEnabled)
        _selectedSound = State(initialValue: alarm.alarmSound)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Time picker
                    DatePicker("", selection: $selectedTime, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .colorScheme(.dark)
                        .padding(.top)

                    // Settings list
                    List {
                        // Repeat - shows "School Days" (not editable, it's the core feature)
                        HStack {
                            Text("Repeat")
                            Spacer()
                            Text("School Days")
                                .foregroundColor(.gray)
                        }
                        .listRowBackground(Color(white: 0.15))

                        // Label
                        HStack {
                            Text("Label")
                            Spacer()
                            TextField("Alarm", text: $label)
                                .multilineTextAlignment(.trailing)
                                .foregroundColor(.gray)
                        }
                        .listRowBackground(Color(white: 0.15))

                        // Sound picker - navigates to full sound selection
                        NavigationLink {
                            SoundSelectionView(selectedSound: $selectedSound, easterEggUnlocked: easterEggUnlocked)
                        } label: {
                            HStack {
                                Text("Sound")
                                Spacer()
                                Text(selectedSound.displayName)
                                    .foregroundColor(.gray)
                            }
                        }
                        .listRowBackground(Color(white: 0.15))

                        // Snooze
                        Toggle("Snooze", isOn: $snoozeEnabled)
                            .tint(.orange)
                            .listRowBackground(Color(white: 0.15))

                        // Delete button (only in edit mode)
                        if case .edit = mode {
                            Section {
                                Button(role: .destructive) {
                                    showingDeleteConfirmation = true
                                } label: {
                                    HStack {
                                        Spacer()
                                        Text("Delete Alarm")
                                        Spacer()
                                    }
                                }
                                .listRowBackground(Color(white: 0.15))
                            }
                        }

                        // Easter egg: invisible double-tap area
                        if !easterEggUnlocked {
                            Section {
                                Color.clear
                                    .frame(height: 44)
                                    .contentShape(Rectangle())
                                    .onTapGesture(count: 2) {
                                        unlockEasterEgg()
                                    }
                                    .listRowBackground(Color.clear)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
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
                        saveAlarm()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .alert("Delete Alarm", isPresented: $showingDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    deleteAlarm()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to delete this alarm?")
            }
        }
    }

    private func saveAlarm() {
        var alarm: Alarm

        if case .edit(let existingAlarm) = mode {
            alarm = existingAlarm
        } else {
            alarm = Alarm.defaultAlarm()
        }

        alarm.time = selectedTime
        alarm.label = label
        alarm.snoozeEnabled = snoozeEnabled
        alarm.alarmSound = selectedSound
        alarm.isEnabled = true

        if case .edit = mode {
            alarmStore.updateAlarm(alarm)
        } else {
            alarmStore.addAlarm(alarm)
        }

        // Schedule alarms via AlarmKit
        AlarmKitManager.shared.rescheduleAllAlarms(
            alarmStore: alarmStore,
            calendarService: calendarService,
            overrideStore: overrideStore,
            district: district
        )
    }

    private func deleteAlarm() {
        if case .edit(let alarm) = mode {
            alarmStore.deleteAlarm(alarm)
        }
    }

    private func unlockEasterEgg() {
        // Provide haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        // Unlock the easter egg
        easterEggUnlocked = true
    }
}

#Preview {
    AlarmEditView(mode: .add)
        .environmentObject(AlarmStore())
        .environmentObject(CalendarService())
        .environmentObject(OverrideStore())
        .environmentObject(DistrictStore())
}
