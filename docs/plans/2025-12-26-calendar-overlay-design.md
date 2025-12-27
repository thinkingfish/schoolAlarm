# Calendar Overlay Feature Design

## Overview

Add user-configurable alarm overrides that layer on top of the SFUSD school calendar. Users can disable or reschedule alarms for specific dates (one-time) or weekday patterns (recurring), with a priority system that respects user intent.

## Priority Model (Hybrid)

For any given school day, alarm resolution follows this order:

1. **One-time override** for that specific date (highest priority)
2. **Weekly rule** for that weekday
3. **Base alarm** (lowest priority)

Each layer can independently contribute alarms. Base is optional — users can run with only weekly rules (e.g., custody schedules).

A **master toggle** ("All Alarms Enabled") can disable all notifications regardless of layer configuration.

## Data Model

```swift
// One-time override for a specific date
struct DateOverride: Codable, Identifiable {
    var id: UUID
    var date: Date           // The specific date (day precision)
    var action: OverrideAction
}

// Weekly recurring rule
struct WeeklyRule: Codable, Identifiable {
    var id: UUID
    var weekday: Int         // 1=Sunday ... 7=Saturday
    var action: OverrideAction
}

// What the override does
enum OverrideAction: Codable {
    case disable             // Skip alarm entirely
    case customTime(Date)    // Alarm at this time (hour/minute only)
}
```

**Storage:** New `OverrideStore` class using UserDefaults, following existing `AlarmStore` pattern.

- `"WeeklyRules"` — JSON-encoded `[WeeklyRule]`
- `"DateOverrides"` — JSON-encoded `[DateOverride]`
- `"AllAlarmsEnabled"` — Bool (master toggle state)

**Auto-cleanup:** On app launch, purge `DateOverride` entries for past dates. Weekly rules persist indefinitely.

## Color Theme

- **Orange** — Base layer (school calendar default)
- **Blue** — Weekly rule overrides
- **Green** — One-time overrides

These colors apply consistently across main view, calendar view, and the "Next Alarm" display.

## Main View Layout

```
┌─────────────────────────────────────┐
│  NEXT ALARM                         │
│  Monday, January 6                  │
│  ┌─────────────────────────────────┐│
│  │         7:45 AM                 ││  ← background = active rule color
│  └─────────────────────────────────┘│
│                                     │
│  [Calendar icon] View Calendar      │
│                                     │
│                                     │  ← extra spacing
├─────────────────────────────────────┤
│  All Alarms Enabled           [━━●] │  ← master toggle
├─────────────────────────────────────┤
│  BASE ALARM                    [+]  │  ← orange section
│  ┌─────────────────────────────────┐│
│  │ 7:00 AM        School morning   ││
│  │ ○ Enabled              Edit ›   ││
│  └─────────────────────────────────┘│
├─────────────────────────────────────┤
│  WEEKLY RULES                  [+]  │  ← blue section
│  ┌─────────────────────────────────┐│
│  │ Every Tuesday      7:45 AM      ││
│  └─────────────────────────────────┘│
├─────────────────────────────────────┤
│  ONE-TIME OVERRIDES            [+]  │  ← green section
│  ┌─────────────────────────────────┐│
│  │ Thu, Jan 15        Disabled     ││
│  └─────────────────────────────────┘│
└─────────────────────────────────────┘
```

**Interactions:**

- `[+]` buttons open add sheet (weekday picker or date picker + action selector)
- Swipe left on any rule/override to delete
- Tap row to edit (same sheet, pre-populated)
- Master toggle off: "Next Alarm" shows "All alarms disabled", sections grayed out

## Calendar View

**Day cell visual indicators:**

- **Orange ring** — School day, base alarm applies
- **Blue ring** — School day, weekly rule applies
- **Green ring** — School day, one-time override applies
- **Strikethrough + muted** — Disabled (color matches the disabling rule)
- **Gray/no ring** — Weekend or holiday

**Tap interaction:**

- Tap school day → sheet with "Set Custom Time" / "Disable This Day" buttons
- If one-time override exists → also show "Remove Override" option
- Tap non-school day → info toast "No school this day"

## Notification Scheduling

**Updated scheduling logic:**

For each upcoming school day (up to 60):

```
1. If master toggle off → skip all
2. Check DateOverride for this date
   → .disable: skip
   → .customTime: schedule at that time
3. Else check WeeklyRule for this weekday
   → .disable: skip
   → .customTime: schedule at that time
4. Else check base alarm
   → enabled: schedule at base time
   → disabled/missing: skip
```

**Rescheduling triggers:**

- Master toggle changed
- Base alarm changed
- Weekly rule added/edited/deleted
- One-time override added/edited/deleted
- Calendar refreshed
- App enters foreground
- User taps notification
- Background app refresh

## Queue Reliability

**Problem:** iOS limits pending notifications to 64. Queue depletes over time if user doesn't interact with app.

**Solution:** Multiple rescheduling triggers + smart background refresh.

**Background refresh scheduling:**

```swift
func scheduleBackgroundRefresh(scheduledSchoolDays: [Date]) {
    // No school days = summer break, skip refresh
    guard scheduledSchoolDays.count > 0 else { return }

    let request = BGAppRefreshTaskRequest(identifier: "com.app.alarmRefresh")

    // Refresh at queue midpoint
    let halfwayIndex = scheduledSchoolDays.count / 2
    guard halfwayIndex > 0 else { return }

    request.earliestBeginDate = scheduledSchoolDays[halfwayIndex]
    try? BGTaskScheduler.shared.submit(request)
}
```

**Behavior:**

- During school year: Refresh at ~50% queue depletion
- End of school year: Queue shrinks, fewer refreshes
- Summer: No background refreshes
- Next year: User opens app → foreground trigger reschedules

**Required:**

- Enable `UIBackgroundModes` → `fetch` in Info.plist
- Register task with `BGTaskScheduler`

## Edge Cases

| Scenario | Behavior |
|----------|----------|
| Duplicate weekly rule (same weekday) | Block creation, open existing rule for edit |
| Override on non-school day | Tap shows info toast, no action allowed |
| Weekly rule on holiday week | Rule ignored for that week (auto from scheduling logic) |
| Override for today, alarm already fired | Allowed — doesn't affect past |
| Calendar refresh removes a school day | Auto-purge orphaned overrides for that date |
| No base alarm exists | Weekly rules and one-time overrides still function independently |
| All layers disabled/empty | No alarms scheduled |

## Environment Integration

`OverrideStore` added as `@EnvironmentObject` alongside existing:

- `AlarmStore`
- `CalendarService`
- `NotificationManager`

## Files to Modify

**New files:**

- `Models/OverrideStore.swift` — WeeklyRule, DateOverride, OverrideAction, OverrideStore
- `Views/WeeklyRuleEditView.swift` — Add/edit weekly rule sheet
- `Views/DateOverrideEditView.swift` — Add/edit one-time override sheet

**Modified files:**

- `Services/NotificationManager.swift` — Override-aware scheduling logic, queue refill triggers
- `App/ContentView.swift` — New main view layout with sections
- `Views/CalendarView.swift` — Override indicators, tap-to-override interaction
- `App/SFUSD_AlarmApp.swift` — OverrideStore injection, background task registration
- `Info.plist` — Background fetch capability
