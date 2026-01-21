import SwiftUI
import AlarmKit

@main
struct SchoolAlarmApp: App {
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
                    Task {
                        _ = await AlarmKitManager.shared.requestAuthorization()
                        await calendarService.loadCalendar()
                        rescheduleAlarms()
                    }
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        rescheduleAlarms()
                    }
                }
        }
    }

    private func rescheduleAlarms() {
        AlarmKitManager.shared.rescheduleAllAlarms(
            alarmStore: alarmStore,
            calendarService: calendarService,
            overrideStore: overrideStore
        )
    }
}
