# AlarmKit Migration Design

**Date:** 2026-01-20
**Status:** Approved

## Overview

Migrate SchoolAlarm from UNNotificationCenter-based alarms to iOS 26's AlarmKit framework. This enables true system alarms that break through DND/silent mode, display on Lock Screen/Dynamic Island, and removes the 64-notification limit.

## Decisions

| Decision | Choice |
|----------|--------|
| iOS target | iOS 26+ only (drop iOS 16-25) |
| Scheduling model | Calendar-driven (keep existing logic) |
| Live Activity | Minimal (system fallback UI) |

## Architecture

### What Changes

- **Delete:** `NotificationManager.swift` — replaced by `AlarmKitManager`
- **Add:** `AlarmKitManager.swift` — new AlarmKit scheduling service
- **Add:** Widget Extension target with minimal `AlarmAttributes`
- **Modify:** `Info.plist` — add `NSAlarmKitUsageDescription`, deployment target iOS 26
- **Modify:** `SchoolAlarmApp.swift` — AlarmKit authorization instead of notification permission
- **Modify:** `ContentView.swift` — call `AlarmKitManager` instead of `NotificationManager`
- **Remove:** `#if DEBUG` notification count displays (no longer relevant)
- **Update:** `README.md` — remove iOS limitations section

### What Stays the Same

- `CalendarService.swift` — SFUSD calendar fetching/parsing
- `OverrideStore.swift` — layered override logic (base → weekly → date)
- `OverrideModels.swift` — `WeeklyRule`, `DateOverride`, `OverrideAction`
- `Alarm.swift` / `AlarmStore.swift` — base alarm model and persistence
- All edit views (`AlarmEditView`, `WeeklyRuleEditView`, `DateOverrideEditView`)
- `CalendarView.swift` (except debug notification counts)
- Sound files (`.caf` files work with AlarmKit)

## New Components

### AlarmKitManager

```swift
import AlarmKit

class AlarmKitManager {
    static let shared = AlarmKitManager()
    private let alarmManager = AlarmManager.shared

    // Track scheduled alarm IDs by date (for cancellation/updates)
    private var scheduledAlarms: [Date: UUID] = [:]

    func requestAuthorization() async -> Bool
    func scheduleAlarms(
        schoolDays: [Date],
        overrideStore: OverrideStore,
        baseAlarm: Alarm?
    ) async
    func cancelAllAlarms() async
    func cancelAlarm(for date: Date) async
}
```

**Scheduling logic:**
1. Cancel all existing alarms
2. For each upcoming school day (from `CalendarService`):
   - Call `overrideStore.effectiveAlarmTime(for: date, baseAlarm:)`
   - If returns `nil` → skip (alarm disabled for that day)
   - If returns a time → schedule AlarmKit alarm with `Alarm.Schedule.fixed(datetime)`
3. Store the alarm UUID keyed by date for later cancellation

**Sound mapping:**
- Use `AlertConfiguration.AlertSound.named("funny_ring")` etc.
- Existing `.caf` files in bundle work as-is

### Widget Extension (Minimal Live Activity)

**New target:** `SchoolAlarmWidgets`

```swift
// AlarmAttributes.swift
import AlarmKit
import ActivityKit

struct SchoolAlarmAttributes: AlarmAttributes {
    struct ContentState: AlarmMetadata { }
}

// SchoolAlarmWidgetBundle.swift
@main
struct SchoolAlarmWidgetBundle: WidgetBundle {
    var body: some Widget {
        SchoolAlarmLiveActivity()
    }
}

// SchoolAlarmLiveActivity.swift
struct SchoolAlarmLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SchoolAlarmAttributes.self) { context in
            EmptyView()  // System provides default
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { }
                DynamicIslandExpandedRegion(.trailing) { }
                DynamicIslandExpandedRegion(.bottom) { }
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

## Data Flow

```
User sets alarm → AlarmStore saves config
                          ↓
CalendarService provides upcoming school days
                          ↓
OverrideStore computes effective time per day
                          ↓
AlarmKitManager schedules AlarmKit alarms (one per school day)
                          ↓
AlarmKit handles Lock Screen, Dynamic Island, sound playback
```

## Benefits Over Previous Implementation

| Before (Notifications) | After (AlarmKit) |
|------------------------|------------------|
| 64 notification limit (~20 school days) | Unlimited alarms |
| 30-second sound limit (chained 3x) | Full alarm sound playback |
| DND can silence | Breaks through DND |
| Long-press for snooze/dismiss | Native alarm UI buttons |
| No Lock Screen presence | Lock Screen + Dynamic Island |
| Background refresh to reschedule | Schedule entire year at once |

## Implementation Order

1. Add Widget Extension target with minimal AlarmAttributes
2. Add `NSAlarmKitUsageDescription` to Info.plist
3. Create `AlarmKitManager.swift`
4. Update `SchoolAlarmApp.swift` for AlarmKit authorization
5. Update `ContentView.swift` to use AlarmKitManager
6. Delete `NotificationManager.swift`
7. Remove `#if DEBUG` notification count code
8. Update README.md
9. Test on device

## References

- [WWDC 2025: Wake up to the AlarmKit API](https://developer.apple.com/videos/play/wwdc2025/230/)
- [AlarmKit Documentation](https://developer.apple.com/documentation/AlarmKit)
- [MacRumors: iOS 26 Third-Party Alarm Apps](https://www.macrumors.com/2025/06/11/ios-26-third-party-alarm-apps/)
