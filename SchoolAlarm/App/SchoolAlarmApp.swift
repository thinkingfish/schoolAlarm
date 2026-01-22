import SwiftUI
import AlarmKit

@main
struct SchoolAlarmApp: App {
    @StateObject private var alarmStore = AlarmStore()
    @StateObject private var calendarService = CalendarService()
    @StateObject private var overrideStore = OverrideStore()
    @StateObject private var districtStore = DistrictStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if districtStore.hasSelectedDistrict {
                    ContentView()
                        .environmentObject(alarmStore)
                        .environmentObject(calendarService)
                        .environmentObject(overrideStore)
                        .environmentObject(districtStore)
                        .onAppear {
                            Task {
                                _ = await AlarmKitManager.shared.requestAuthorization()
                                if let district = districtStore.selectedDistrict {
                                    await calendarService.loadCalendar(for: district)
                                }
                                rescheduleAlarms()
                            }
                        }
                        .onChange(of: scenePhase) { _, newPhase in
                            if newPhase == .active {
                                rescheduleAlarms()
                            }
                        }
                } else {
                    OnboardingView {
                        // District selected, app will re-render showing ContentView
                    }
                    .environmentObject(districtStore)
                }
            }
        }
    }

    private func rescheduleAlarms() {
        guard let district = districtStore.selectedDistrict else { return }
        AlarmKitManager.shared.rescheduleAllAlarms(
            alarmStore: alarmStore,
            calendarService: calendarService,
            overrideStore: overrideStore,
            district: district
        )
    }
}
