import SwiftUI

struct ContentView: View {
    @EnvironmentObject var alarmStore: AlarmStore
    @EnvironmentObject var calendarService: CalendarService
    @State private var showingAddAlarm = false
    @State private var selectedAlarm: Alarm?
    @State private var isEditing = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Next school day info
                    NextSchoolDayBanner()
                        .environmentObject(calendarService)

                    if alarmStore.alarms.isEmpty {
                        EmptyStateView(showingAddAlarm: $showingAddAlarm)
                    } else {
                        AlarmListView(
                            alarms: $alarmStore.alarms,
                            isEditing: $isEditing,
                            selectedAlarm: $selectedAlarm
                        )
                    }
                }
            }
            .navigationTitle("Alarm")
            .navigationBarTitleDisplayMode(.large)
            .preferredColorScheme(.dark)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(isEditing ? "Done" : "Edit") {
                        withAnimation {
                            isEditing.toggle()
                        }
                    }
                    .disabled(alarmStore.alarms.isEmpty)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAddAlarm = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddAlarm) {
                AlarmEditView(mode: .add)
            }
            .sheet(item: $selectedAlarm) { alarm in
                AlarmEditView(mode: .edit(alarm))
            }
        }
    }
}

struct NextSchoolDayBanner: View {
    @EnvironmentObject var calendarService: CalendarService

    var body: some View {
        VStack(spacing: 4) {
            if calendarService.isLoading {
                HStack {
                    ProgressView()
                        .tint(.orange)
                    Text("Loading calendar...")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .padding(.vertical, 8)
            } else if let nextSchoolDay = calendarService.nextSchoolDay() {
                let isToday = Calendar.current.isDateInToday(nextSchoolDay)
                let isTomorrow = Calendar.current.isDateInTomorrow(nextSchoolDay)

                HStack {
                    Image(systemName: "calendar")
                        .foregroundColor(.orange)

                    if isToday {
                        Text("Today is a school day")
                            .font(.subheadline)
                            .foregroundColor(.white)
                    } else if isTomorrow {
                        Text("Tomorrow is a school day")
                            .font(.subheadline)
                            .foregroundColor(.white)
                    } else {
                        Text("Next school day: \(nextSchoolDay, formatter: dateFormatter)")
                            .font(.subheadline)
                            .foregroundColor(.white)
                    }

                    Spacer()

                    NavigationLink {
                        CalendarView()
                    } label: {
                        Text("View Calendar")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            } else {
                HStack {
                    Image(systemName: "sun.max.fill")
                        .foregroundColor(.yellow)
                    Text("No school - Summer break!")
                        .font(.subheadline)
                        .foregroundColor(.white)
                }
                .padding(.vertical, 8)
            }
        }
        .background(Color(white: 0.1))
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter
    }
}

struct EmptyStateView: View {
    @Binding var showingAddAlarm: Bool

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "alarm")
                .font(.system(size: 60))
                .foregroundColor(.gray)

            Text("No Alarms")
                .font(.title2)
                .foregroundColor(.white)

            Text("Add an alarm to wake up on school days")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)

            Button {
                showingAddAlarm = true
            } label: {
                Text("Add Alarm")
                    .font(.headline)
                    .foregroundColor(.black)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.orange)
                    .cornerRadius(10)
            }

            Spacer()
        }
        .padding()
    }
}

struct AlarmListView: View {
    @Binding var alarms: [Alarm]
    @Binding var isEditing: Bool
    @Binding var selectedAlarm: Alarm?
    @EnvironmentObject var alarmStore: AlarmStore
    @EnvironmentObject var calendarService: CalendarService

    var body: some View {
        List {
            ForEach(alarms) { alarm in
                AlarmRow(
                    alarm: alarm,
                    isEditing: isEditing,
                    onToggle: {
                        alarmStore.toggleAlarm(alarm)
                        rescheduleAlarm(alarm)
                    },
                    onTap: {
                        if isEditing {
                            selectedAlarm = alarm
                        }
                    }
                )
                .listRowBackground(Color(white: 0.1))
            }
            .onDelete(perform: deleteAlarms)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func deleteAlarms(at offsets: IndexSet) {
        for index in offsets {
            alarmStore.deleteAlarm(alarms[index])
        }
    }

    private func rescheduleAlarm(_ alarm: Alarm) {
        let schoolDays = calendarService.upcomingSchoolDays()
        NotificationManager.shared.scheduleAlarms(for: alarm, on: schoolDays)
    }
}

struct AlarmRow: View {
    let alarm: Alarm
    let isEditing: Bool
    let onToggle: () -> Void
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                if isEditing {
                    Image(systemName: "minus.circle.fill")
                        .foregroundColor(.red)
                        .font(.title2)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(alarm.timeString)
                            .font(.system(size: 56, weight: .light))
                            .foregroundColor(alarm.isEnabled ? .white : .gray)

                        Text(alarm.periodString)
                            .font(.system(size: 24, weight: .light))
                            .foregroundColor(alarm.isEnabled ? .white : .gray)
                    }

                    HStack {
                        Text(alarm.label.isEmpty ? "Alarm" : alarm.label)
                            .font(.subheadline)
                            .foregroundColor(alarm.isEnabled ? .white : .gray)

                        Text("School Days")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2))
                            .cornerRadius(4)
                    }
                }

                Spacer()

                if !isEditing {
                    Toggle("", isOn: Binding(
                        get: { alarm.isEnabled },
                        set: { _ in onToggle() }
                    ))
                    .labelsHidden()
                    .tint(.orange)
                }
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ContentView()
        .environmentObject(AlarmStore())
        .environmentObject(CalendarService())
}
