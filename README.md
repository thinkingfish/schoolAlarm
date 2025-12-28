# SchoolAlarm

A smart alarm clock app for SFUSD (San Francisco Unified School District) families. The app automatically schedules alarms only on school days by syncing with the official SFUSD calendar.

## Features

- **Smart School Day Detection**: Automatically fetches and parses the SFUSD calendar to determine school days
- **Layered Override System**:
  - Base alarm time (applies to all school days)
  - Weekly rules (e.g., "7:30 AM every Wednesday")
  - One-time date overrides (e.g., "skip alarm on Dec 20")
- **Chained Notifications**: Each alarm fires 3 notifications 30 seconds apart (~90 seconds total) to help heavy sleepers
- **Snooze Support**: 5-minute snooze for real alarms (15 seconds in debug builds for testing)
- **Custom Alarm Sounds**: Bundled sounds including kid-friendly options
- **Background Refresh**: Automatically reschedules notifications when needed

## Requirements

- iOS 16.0+
- iPhone or iPad

## Configuration

### System Settings (iOS Settings App)

For the alarm to work reliably, configure these settings:

1. **Settings > SchoolAlarm > Notifications**:
   - Allow Notifications: **ON**
   - Lock Screen: **ON**
   - Notification Center: **ON**
   - Banners: **ON**
   - Sounds: **ON**
   - Badges: **ON**
   - Show Previews: **Always** (recommended)

2. **Settings > Focus > Do Not Disturb** (if using DND overnight):
   - Add SchoolAlarm to "Allowed Apps" so alarms can break through DND
   - Alternatively, set DND to end before your earliest alarm time

3. **Settings > Display & Brightness > Auto-Lock**:
   - Not required for alarms to work, but note that notification sounds are limited to ~30 seconds by iOS

### App Settings

1. **Create a base alarm**: Set your default wake-up time that applies to all school days
2. **Add weekly rules** (optional): Override the base time for specific days of the week
3. **Add one-time overrides** (optional): Skip or change alarm time for specific dates

## iOS Limitations

Due to iOS restrictions on third-party apps:

- **Notification Sound Duration**: Each notification sound is limited to ~30 seconds. The app works around this by chaining 3 notifications 30 seconds apart.
- **Action Buttons**: Snooze/Dismiss buttons require a **long-press** on the notification to reveal. This is an iOS design decision that cannot be changed.
- **64 Notification Limit**: iOS allows a maximum of 64 scheduled notifications. With 3 notifications per alarm, this means ~20 school days can be scheduled ahead. The app uses background refresh to reschedule as needed.
- **No Full-Screen Alarm**: Unlike Apple's Clock app, third-party apps cannot display a full-screen alarm interface on the lock screen.

## Calendar Source

The app fetches the school calendar from:
```
https://www.sfusd.edu/calendars/export/ical/custom-type-id-3836
```

This is the official SFUSD "School Day" calendar. The app caches the calendar locally and refreshes it when the app is opened.

## Project Structure

```
SchoolAlarm/
├── App/
│   ├── SchoolAlarmApp.swift    # App entry point, background refresh
│   └── ContentView.swift       # Main UI with alarm list
├── Models/
│   ├── Alarm.swift             # Alarm model and AlarmStore
│   ├── OverrideModels.swift    # Weekly rules and date overrides
│   ├── OverrideStore.swift     # Override management
│   └── SchoolCalendar.swift    # Calendar data model
├── Views/
│   ├── AlarmEditView.swift     # Edit alarm time/sound/label
│   ├── CalendarView.swift      # Monthly calendar with override indicators
│   ├── WeeklyRuleEditView.swift    # Edit weekly override rules
│   └── DateOverrideEditView.swift  # Edit one-time date overrides
├── Services/
│   ├── CalendarService.swift   # Fetches and parses SFUSD calendar
│   └── NotificationManager.swift   # Schedules iOS notifications
├── Utilities/
│   └── ICSParser.swift         # Parses ICS calendar format
└── Resources/
    ├── Assets.xcassets         # App icons and colors
    ├── funny_ring.caf          # Alarm sounds
    ├── click_ring.caf
    ├── kid_shouting_1.caf
    └── kid_shouting_2.caf
```

## Building

1. Open `SchoolAlarm.xcodeproj` in Xcode
2. Select your development team in Signing & Capabilities
3. Build and run on your device (notifications don't work reliably in Simulator)

## Debug Features

Debug builds include a test section at the bottom of the main screen:
- Schedule test notifications at various delays
- View pending notification counts
- Check notification permission status
- Cancel test notifications

These features are compiled out in Release builds.

## License

Private project for personal use.
