# Custom Alarm Sound Design

## Goal

Allow users to import their own audio file as an alarm ringtone via the Files app.

## Constraints

- **Source:** Files app (UIDocumentPicker)
- **File size:** Max 10MB
- **Duration:** No limit (alarm stops when user dismisses/snoozes)
- **Quantity:** Single custom sound slot (importing new replaces old)
- **Formats:** Accept common formats as-is (mp3, m4a, wav, aiff, caf) - no conversion

## Data Model

### New AlarmSound Enum

Replace `BundledSound` usage with a new type that supports both:

```swift
enum AlarmSound: Codable, Equatable {
    case bundled(BundledSound)
    case custom(filename: String)

    var displayName: String {
        switch self {
        case .bundled(let sound): return sound.displayName
        case .custom(let filename): return filename
        }
    }
}
```

### Storage Location

Custom sound file stored in `Application Support/CustomSounds/` (or `Library/Sounds/` if AlarmKit requires it). Only one file at a time - importing new deletes old.

### Migration

Existing alarms using `bundledSound: BundledSound` need migration to new `sound: AlarmSound` property.

## UI Changes

### Sound Picker (AlarmEditView)

Current inline Picker expands to show:

1. All bundled sounds (Funny Ring, Click Ring, etc.)
2. Separator
3. "Custom..." option - opens file picker
4. Current custom sound name (if one exists, shows with checkmark if selected)

### Import Flow

1. User taps "Custom..."
2. `UIDocumentPickerViewController` opens
3. User selects audio file
4. App validates:
   - File size ≤ 10MB
   - Playable by AVAudioPlayer
5. If valid: copy to app storage, select it, play preview
6. If invalid: show alert with reason

### Preview Behavior

- Bundled: play from app bundle (existing)
- Custom: play from app's documents directory

## CustomSoundManager Service

New service to handle file operations:

```swift
class CustomSoundManager {
    static let shared = CustomSoundManager()

    private let maxFileSize = 10 * 1024 * 1024  // 10MB

    /// Returns URL of current custom sound, nil if none
    func customSoundURL() -> URL?

    /// Returns filename of current custom sound, nil if none
    func customSoundFilename() -> String?

    /// Import sound from document picker URL
    func importSound(from sourceURL: URL) async throws -> String

    /// Delete current custom sound
    func deleteCustomSound()
}

enum CustomSoundError: LocalizedError {
    case fileTooLarge
    case notPlayable
    case copyFailed
}
```

Key behaviors:
- Uses security-scoped resource access for Files app URLs
- Validates before copying (fail fast)
- Old sound deleted only after new one successfully copied
- Preserves original filename for display

## AlarmKit Integration

Current code uses `.sound(.named(soundName))` which loads from app bundle.

For custom sounds:
- Store in `Library/Sounds/` directory (standard iOS location for custom notification sounds)
- Use same `.sound(.named(filename))` API

```swift
private func scheduleAlarm(for dateTime: Date, sound: AlarmSound) async {
    let soundConfig: AlarmConfiguration.Sound

    switch sound {
    case .bundled(let bundled):
        soundConfig = .named(bundled.rawValue + ".caf")
    case .custom(let filename):
        soundConfig = .named(filename)
    }
    // ... rest of scheduling
}
```

Note: Exact directory may need adjustment based on AlarmKit testing.

## Files to Change

1. **Alarm.swift** - New `AlarmSound` enum, update `Alarm` struct
2. **AlarmEditView.swift** - Custom option in picker, document picker sheet, updated preview
3. **CustomSoundManager.swift** (new) - File import/validation/storage
4. **AlarmKitManager.swift** - Handle `AlarmSound` type when scheduling

## Manual Testing Checklist

- [ ] Import valid audio file (mp3, m4a, wav)
- [ ] Reject file > 10MB with friendly error
- [ ] Reject unplayable file with friendly error
- [ ] Preview plays for bundled sounds
- [ ] Preview plays for custom sound
- [ ] Alarm fires with custom sound
- [ ] Replacing custom sound works (old deleted)
- [ ] Existing alarms migrate correctly
- [ ] Deleting custom sound falls back gracefully
