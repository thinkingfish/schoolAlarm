# AlarmKit Migration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace UNNotificationCenter-based alarms with iOS 26 AlarmKit for true system alarms.

**Architecture:** Keep existing CalendarService/OverrideStore logic for determining when alarms fire. Create new AlarmKitManager to schedule alarms via AlarmKit. Add minimal Widget Extension for required Live Activity. Remove NotificationManager and background refresh (no longer needed).

**Tech Stack:** Swift 6, AlarmKit, ActivityKit, SwiftUI, WidgetKit

---

## Task 1: Update Deployment Target to iOS 26

**Files:**
- Modify: `SchoolAlarm.xcodeproj/project.pbxproj`

**Step 1: Open Xcode project in worktree**

Open the `.xcodeproj` file in Xcode:
```
/Users/yao/workspace/SchoolAlarm/.worktrees/alarmkit-migration/SchoolAlarm.xcodeproj
```

**Step 2: Change deployment target**

In Xcode:
1. Select the project in the navigator
2. Select the "SchoolAlarm" target
3. Go to "General" tab
4. Change "Minimum Deployments" → iOS from 16.0 to 26.0

**Step 3: Verify project.pbxproj updated**

The file should now contain `IPHONEOS_DEPLOYMENT_TARGET = 26.0`

**Step 4: Commit**

```bash
cd /Users/yao/workspace/SchoolAlarm/.worktrees/alarmkit-migration
git add SchoolAlarm.xcodeproj/project.pbxproj
git commit -m "chore: update deployment target to iOS 26"
```

---

## Task 2: Add NSAlarmKitUsageDescription to Info.plist

**Files:**
- Modify: `SchoolAlarm/Info.plist`

**Step 1: Add the usage description**

Add this key-value pair to Info.plist (inside the `<dict>` element):

```xml
<key>NSAlarmKitUsageDescription</key>
<string>SchoolAlarm needs alarm access to wake you up on school days, even when your phone is on silent or Do Not Disturb.</string>
```

**Step 2: Verify the plist is valid**

Run:
```bash
plutil -lint SchoolAlarm/Info.plist
```

Expected: `SchoolAlarm/Info.plist: OK`

**Step 3: Commit**

```bash
git add SchoolAlarm/Info.plist
git commit -m "feat: add NSAlarmKitUsageDescription for AlarmKit"
```

---

## Task 3: Create Widget Extension Target

**Files:**
- Create: `SchoolAlarmWidgets/` directory with Widget Extension files

**Step 1: Add Widget Extension in Xcode**

1. In Xcode, File → New → Target
2. Select "Widget Extension"
3. Product Name: `SchoolAlarmWidgets`
4. **Uncheck** "Include Live Activity" (we'll add minimal version manually)
5. **Uncheck** "Include Configuration App Intent"
6. Finish

**Step 2: Delete auto-generated widget files**

Delete these auto-generated files (we only need Live Activity):
- `SchoolAlarmWidgets.swift` (the timeline widget)
- `AppIntent.swift` (if created)

Keep:
- `SchoolAlarmWidgetsBundle.swift`

**Step 3: Commit the new target**

```bash
git add SchoolAlarmWidgets/
git add SchoolAlarm.xcodeproj/
git commit -m "feat: add SchoolAlarmWidgets extension target"
```

---

## Task 4: Create AlarmAttributes for Live Activity

**Files:**
- Create: `SchoolAlarmWidgets/AlarmAttributes.swift`

**Step 1: Create the AlarmAttributes file**

Create `SchoolAlarmWidgets/AlarmAttributes.swift`:

```swift
import AlarmKit
import ActivityKit

/// Minimal AlarmAttributes for AlarmKit Live Activity
/// System provides default UI when we use EmptyView
struct SchoolAlarmAttributes: AlarmAttributes {
    /// Empty metadata - system handles countdown display
    nonisolated struct ContentState: AlarmMetadata {
        // No custom state needed for minimal implementation
    }
}
```

**Step 2: Verify it compiles**

Build the SchoolAlarmWidgets target in Xcode (Cmd+B with target selected).

**Step 3: Commit**

```bash
git add SchoolAlarmWidgets/AlarmAttributes.swift
git commit -m "feat: add SchoolAlarmAttributes for AlarmKit"
```

---

## Task 5: Create Live Activity Widget

**Files:**
- Create: `SchoolAlarmWidgets/SchoolAlarmLiveActivity.swift`
- Modify: `SchoolAlarmWidgets/SchoolAlarmWidgetsBundle.swift`

**Step 1: Create the Live Activity file**

Create `SchoolAlarmWidgets/SchoolAlarmLiveActivity.swift`:

```swift
import SwiftUI
import WidgetKit
import ActivityKit
import AlarmKit

/// Minimal Live Activity for AlarmKit
/// Uses EmptyView to let system provide default alarm UI
struct SchoolAlarmLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SchoolAlarmAttributes.self) { context in
            // Lock Screen presentation - system provides default
            EmptyView()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    EmptyView()
                }
                DynamicIslandExpandedRegion(.trailing) {
                    EmptyView()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    EmptyView()
                }
            } compactLeading: {
                EmptyView()
            } compactTrailing: {
                EmptyView()
            } minimal: {
                EmptyView()
            }
        }
    }
}
```

**Step 2: Update the Widget Bundle**

Replace contents of `SchoolAlarmWidgets/SchoolAlarmWidgetsBundle.swift`:

```swift
import SwiftUI
import WidgetKit

@main
struct SchoolAlarmWidgetsBundle: WidgetBundle {
    var body: some Widget {
        SchoolAlarmLiveActivity()
    }
}
```

**Step 3: Build and verify**

Build the SchoolAlarmWidgets target (Cmd+B).

**Step 4: Commit**

```bash
git add SchoolAlarmWidgets/
git commit -m "feat: add minimal Live Activity for AlarmKit"
```

---

## Task 6: Create AlarmKitManager

**Files:**
- Create: `SchoolAlarm/Services/AlarmKitManager.swift`

**Step 1: Create the AlarmKitManager file**

Create `SchoolAlarm/Services/AlarmKitManager.swift`:

```swift
import Foundation
import AlarmKit

/// Manages alarm scheduling via AlarmKit (iOS 26+)
/// Replaces NotificationManager for true system alarms
class AlarmKitManager: ObservableObject {
    static let shared = AlarmKitManager()

    private let alarmManager = AlarmManager.shared

    /// Track scheduled alarm IDs by date for cancellation
    private var scheduledAlarmsByDate: [Date: UUID] = [:]

    @Published var authorizationState: AlarmManager.AuthorizationState = .notDetermined

    private init() {
        updateAuthorizationState()
    }

    // MARK: - Authorization

    func updateAuthorizationState() {
        authorizationState = alarmManager.authorizationState
    }

    func requestAuthorization() async -> Bool {
        switch alarmManager.authorizationState {
        case .notDetermined:
            do {
                let state = try await alarmManager.requestAuthorization()
                await MainActor.run {
                    self.authorizationState = state
                }
                return state == .authorized
            } catch {
                print("AlarmKit authorization error: \(error)")
                return false
            }
        case .authorized:
            return true
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    // MARK: - Scheduling

    /// Schedule alarms for all upcoming school days
    /// - Parameters:
    ///   - schoolDays: List of upcoming school days from CalendarService
    ///   - overrideStore: Override store for effective time resolution
    ///   - baseAlarm: Base alarm configuration (sound, etc.)
    func scheduleAlarms(
        schoolDays: [Date],
        overrideStore: OverrideStore,
        baseAlarm: Alarm?
    ) async {
        // Cancel all existing alarms first
        await cancelAllAlarms()

        guard overrideStore.allAlarmsEnabled else { return }

        let calendar = Calendar.current
        let soundName = baseAlarm?.alarmSoundName ?? Alarm.BundledSound.funnyRing.rawValue

        for schoolDay in schoolDays {
            // Get effective alarm time using override resolution
            guard let alarmTime = overrideStore.effectiveAlarmTime(for: schoolDay, baseAlarm: baseAlarm) else {
                continue // Skip this day (disabled or no alarm)
            }

            // Combine school day date with alarm time
            let timeComponents = calendar.dateComponents([.hour, .minute], from: alarmTime)
            guard let alarmDateTime = calendar.date(
                bySettingHour: timeComponents.hour ?? 7,
                minute: timeComponents.minute ?? 0,
                second: 0,
                of: schoolDay
            ) else { continue }

            // Skip if alarm time has already passed
            if alarmDateTime <= Date() {
                continue
            }

            // Schedule the alarm
            await scheduleAlarm(for: alarmDateTime, soundName: soundName)
        }
    }

    /// Schedule a single alarm
    private func scheduleAlarm(for dateTime: Date, soundName: String) async {
        let alarmId = UUID()
        let dayStart = Calendar.current.startOfDay(for: dateTime)

        // Create alarm presentation
        let stopButton = AlarmButton(
            text: "Dismiss",
            textColor: .white,
            systemImageName: "xmark.circle"
        )

        let snoozeButton = AlarmButton(
            text: "Snooze",
            textColor: .white,
            systemImageName: "moon.zzz"
        )

        let alertPresentation = AlarmPresentation.Alert(
            title: "School Day Alarm",
            stopButton: stopButton,
            secondaryButton: snoozeButton,
            secondaryButtonBehavior: .snooze
        )

        let attributes = AlarmAttributes<SchoolAlarmAttributes.ContentState>(
            presentation: AlarmPresentation(alert: alertPresentation),
            tintColor: .orange
        )

        // 5-minute snooze duration
        let countdownDuration = Alarm.CountdownDuration(
            preAlert: nil,
            postAlert: TimeInterval(5 * 60)
        )

        // Fixed schedule for specific date/time
        let schedule = Alarm.Schedule.fixed(dateTime)

        // Sound from bundle
        let sound = AlertConfiguration.AlertSound.named(soundName)

        let configuration = AlarmManager.AlarmConfiguration(
            countdownDuration: countdownDuration,
            schedule: schedule,
            attributes: attributes,
            secondaryIntent: nil,
            sound: sound
        )

        do {
            try await alarmManager.schedule(id: alarmId, configuration: configuration)
            scheduledAlarmsByDate[dayStart] = alarmId
        } catch {
            print("Failed to schedule alarm for \(dateTime): \(error)")
        }
    }

    // MARK: - Cancellation

    /// Cancel all scheduled alarms
    func cancelAllAlarms() async {
        for (_, alarmId) in scheduledAlarmsByDate {
            try? await alarmManager.cancel(id: alarmId)
        }
        scheduledAlarmsByDate.removeAll()
    }

    /// Cancel alarm for a specific date
    func cancelAlarm(for date: Date) async {
        let dayStart = Calendar.current.startOfDay(for: date)
        guard let alarmId = scheduledAlarmsByDate[dayStart] else { return }

        try? await alarmManager.cancel(id: alarmId)
        scheduledAlarmsByDate.removeValue(forKey: dayStart)
    }

    // MARK: - Convenience

    /// Reschedule all alarms (call when any override or alarm changes)
    @MainActor
    func rescheduleAllAlarms(
        alarmStore: AlarmStore,
        calendarService: CalendarService,
        overrideStore: OverrideStore
    ) {
        let schoolDays = calendarService.upcomingSchoolDays()
        let baseAlarm = alarmStore.alarms.first

        Task {
            await scheduleAlarms(
                schoolDays: schoolDays,
                overrideStore: overrideStore,
                baseAlarm: baseAlarm
            )
        }
    }
}
```

**Step 2: Add SchoolAlarmAttributes import**

The main app target needs access to SchoolAlarmAttributes. Add the Widgets target's files to the main app target in Xcode:
1. Select `AlarmAttributes.swift` in the navigator
2. In the File Inspector, check "SchoolAlarm" under Target Membership

**Step 3: Build and verify**

Build the main SchoolAlarm target (Cmd+B).

**Step 4: Commit**

```bash
git add SchoolAlarm/Services/AlarmKitManager.swift
git add SchoolAlarm.xcodeproj/
git commit -m "feat: add AlarmKitManager for AlarmKit scheduling"
```

---

## Task 7: Update SchoolAlarmApp for AlarmKit Authorization

**Files:**
- Modify: `SchoolAlarm/App/SchoolAlarmApp.swift`

**Step 1: Replace NotificationManager with AlarmKitManager**

Update `SchoolAlarmApp.swift`:

```swift
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
                        await AlarmKitManager.shared.requestAuthorization()
                        await calendarService.loadCalendar()
                        rescheduleAlarms()
                    }
                }
                .onChange(of: scenePhase) { newPhase in
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
```

**Note:** We removed:
- `UIApplicationDelegateAdaptor` (no longer need notification delegate)
- `BackgroundTasks` import (no longer need background refresh)
- `AppDelegate` class entirely
- `Notification.Name.alarmTriggered` extension

**Step 2: Build and verify**

Build the main target (Cmd+B).

**Step 3: Commit**

```bash
git add SchoolAlarm/App/SchoolAlarmApp.swift
git commit -m "refactor: replace NotificationManager with AlarmKitManager in app entry"
```

---

## Task 8: Update ContentView to Use AlarmKitManager

**Files:**
- Modify: `SchoolAlarm/App/ContentView.swift`

**Step 1: Replace NotificationManager.rescheduleAllAlarms calls**

Find all occurrences of:
```swift
NotificationManager.shared.rescheduleAllAlarms(
    alarmStore: alarmStore,
    calendarService: calendarService,
    overrideStore: overrideStore
)
```

Replace with:
```swift
AlarmKitManager.shared.rescheduleAllAlarms(
    alarmStore: alarmStore,
    calendarService: calendarService,
    overrideStore: overrideStore
)
```

There are 2 occurrences (around lines 123 and 362).

**Step 2: Remove DEBUG notification testing code**

Remove the entire `#if DEBUG` section that contains:
- `NotificationManager.shared.cancelTestNotifications()`
- `NotificationManager.shared.scheduleTestNotification(...)`
- All test notification UI (TestNotificationButton, DebugNotificationSection, etc.)

This includes removing:
- `DebugNotificationSection` view
- `TestNotificationButton` view
- Notification count displays in calendar cells

**Step 3: Remove NotificationManager imports/references**

Remove any remaining references to `NotificationManager`.

**Step 4: Build and verify**

Build the main target (Cmd+B).

**Step 5: Commit**

```bash
git add SchoolAlarm/App/ContentView.swift
git commit -m "refactor: replace NotificationManager with AlarmKitManager in ContentView"
```

---

## Task 9: Remove DEBUG Notification Code from CalendarView

**Files:**
- Modify: `SchoolAlarm/Views/CalendarView.swift`

**Step 1: Remove notification count state and display**

Remove:
- `@State private var notificationCountsByDate: [Date: Int] = [:]`
- The `notificationCount` parameter from `DayCellWithOverride` calls
- The notification count display in day cells
- Any `#if DEBUG` blocks related to notification counts

**Step 2: Build and verify**

Build the main target (Cmd+B).

**Step 3: Commit**

```bash
git add SchoolAlarm/Views/CalendarView.swift
git commit -m "refactor: remove DEBUG notification count displays from CalendarView"
```

---

## Task 10: Delete NotificationManager.swift

**Files:**
- Delete: `SchoolAlarm/Services/NotificationManager.swift`

**Step 1: Remove the file**

```bash
rm SchoolAlarm/Services/NotificationManager.swift
```

**Step 2: Remove from Xcode project**

In Xcode, if the file still appears in the navigator (red), right-click and "Delete" to remove reference.

**Step 3: Build and verify**

Build the main target (Cmd+B). Fix any remaining compilation errors.

**Step 4: Commit**

```bash
git add -A
git commit -m "refactor: delete NotificationManager (replaced by AlarmKitManager)"
```

---

## Task 11: Remove Background Refresh from Info.plist

**Files:**
- Modify: `SchoolAlarm/Info.plist`

**Step 1: Remove background modes**

Remove these keys from Info.plist:
```xml
<key>UIBackgroundModes</key>
<array>
    <string>fetch</string>
</array>
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>com.schoolalarm.refresh</string>
</array>
```

AlarmKit doesn't need background refresh - alarms persist.

**Step 2: Verify plist**

```bash
plutil -lint SchoolAlarm/Info.plist
```

**Step 3: Commit**

```bash
git add SchoolAlarm/Info.plist
git commit -m "chore: remove background refresh (AlarmKit doesn't need it)"
```

---

## Task 12: Update README

**Files:**
- Modify: `README.md`

**Step 1: Update requirements section**

Change:
```markdown
## Requirements

- iOS 16.0+
- iPhone or iPad
```

To:
```markdown
## Requirements

- iOS 26.0+
- iPhone or iPad
```

**Step 2: Remove iOS Limitations section**

Delete the entire "## iOS Limitations" section since AlarmKit removes these limitations.

**Step 3: Update Features section**

Remove mention of "Chained Notifications" - replace with:
```markdown
- **True System Alarms**: Uses iOS 26 AlarmKit for alarms that break through DND and silent mode
```

**Step 4: Remove notification-related configuration instructions**

Simplify the Configuration section - remove DND workarounds, notification permission mentions.

**Step 5: Commit**

```bash
git add README.md
git commit -m "docs: update README for AlarmKit (iOS 26)"
```

---

## Task 13: Test on Device

**Files:** None (manual testing)

**Step 1: Build and run on iOS 26 device**

1. Connect iOS 26 device
2. Select device in Xcode
3. Build and Run (Cmd+R)

**Step 2: Test authorization flow**

- App should prompt for AlarmKit permission on first launch
- Grant permission

**Step 3: Test alarm scheduling**

1. Create a base alarm for a few minutes from now
2. Verify alarm appears in system Settings → Clock/Alarms
3. Let alarm fire - verify it plays sound and shows on Lock Screen

**Step 4: Test override system**

1. Add a weekly override for today
2. Verify the override time is used instead of base time

**Step 5: Commit any fixes**

If fixes needed, commit them appropriately.

---

## Task 14: Final Cleanup and Merge

**Step 1: Review all changes**

```bash
git log --oneline main..alarmkit-migration
git diff main..alarmkit-migration --stat
```

**Step 2: Squash or rebase if desired**

Optional: clean up commit history if needed.

**Step 3: Merge to main**

```bash
cd /Users/yao/workspace/SchoolAlarm
git checkout main
git merge alarmkit-migration
```

**Step 4: Remove worktree**

```bash
git worktree remove .worktrees/alarmkit-migration
git branch -d alarmkit-migration
```

---

## Summary

| Task | Description | Files |
|------|-------------|-------|
| 1 | Update deployment target to iOS 26 | project.pbxproj |
| 2 | Add NSAlarmKitUsageDescription | Info.plist |
| 3 | Create Widget Extension target | SchoolAlarmWidgets/ |
| 4 | Create AlarmAttributes | AlarmAttributes.swift |
| 5 | Create Live Activity | SchoolAlarmLiveActivity.swift |
| 6 | Create AlarmKitManager | AlarmKitManager.swift |
| 7 | Update app entry point | SchoolAlarmApp.swift |
| 8 | Update ContentView | ContentView.swift |
| 9 | Remove DEBUG code from CalendarView | CalendarView.swift |
| 10 | Delete NotificationManager | NotificationManager.swift |
| 11 | Remove background refresh | Info.plist |
| 12 | Update README | README.md |
| 13 | Test on device | — |
| 14 | Merge to main | — |
