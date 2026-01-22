# Custom Alarm Sound Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Allow users to import a custom audio file as their alarm sound via the Files app.

**Architecture:** New `AlarmSound` enum wrapping bundled/custom cases, `CustomSoundManager` service for file operations, updated UI with document picker.

**Tech Stack:** SwiftUI, AVFoundation, UIDocumentPickerViewController, FileManager

---

### Task 1: Refactor AlarmSound enum in data model

**Files:**
- Modify: `SchoolAlarm/Models/Alarm.swift`

**Step 1: Rename legacy AlarmSound enum**

The existing `AlarmSound` enum (lines 75-100) is legacy. Rename it to avoid collision:

```swift
// Legacy enum kept for backwards compatibility with saved alarms
enum LegacyAlarmSound: String, Codable {
    case radar = "Radar"
    // ... rest unchanged
}
```

**Step 2: Create new AlarmSound enum**

Add after `BundledSound` enum:

```swift
/// Represents either a bundled sound or a user-imported custom sound
enum AlarmSound: Codable, Equatable, Hashable {
    case bundled(BundledSound)
    case custom(filename: String)

    var displayName: String {
        switch self {
        case .bundled(let sound): return sound.displayName
        case .custom(let filename):
            // Remove extension for display
            return (filename as NSString).deletingPathExtension
        }
    }

    var isCustom: Bool {
        if case .custom = self { return true }
        return false
    }
}
```

**Step 3: Update Alarm struct**

Replace `bundledSound` property with new `alarmSound` property:

```swift
// The selected alarm sound (defaults to funny_ring)
var alarmSound: AlarmSound = .bundled(.funnyRing)

var alarmSoundName: String {
    switch alarmSound {
    case .bundled(let sound):
        return "\(sound.rawValue).caf"
    case .custom(let filename):
        return filename
    }
}
```

Remove old `bundledSound` property.

**Step 4: Update legacy sound property reference**

Change line 11 from:
```swift
var sound: AlarmSound?
```
to:
```swift
var sound: LegacyAlarmSound?
```

**Step 5: Build and verify**

Run: `xcodebuild -scheme SchoolAlarm -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | grep -E "(error:|BUILD)"`

Expected: Build errors in AlarmEditView (will fix in Task 3)

**Step 6: Commit**

```bash
git add SchoolAlarm/Models/Alarm.swift
git commit -m "refactor: introduce AlarmSound enum for bundled/custom sounds"
```

---

### Task 2: Create CustomSoundManager service

**Files:**
- Create: `SchoolAlarm/Services/CustomSoundManager.swift`

**Step 1: Create the file with full implementation**

```swift
import Foundation
import AVFoundation

/// Manages custom alarm sound file import, storage, and retrieval
class CustomSoundManager {
    static let shared = CustomSoundManager()

    private let maxFileSize = 10 * 1024 * 1024  // 10MB
    private let soundsDirectoryName = "CustomSounds"

    private init() {
        createSoundsDirectoryIfNeeded()
    }

    // MARK: - Directory Management

    private var soundsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent(soundsDirectoryName)
    }

    private func createSoundsDirectoryIfNeeded() {
        try? FileManager.default.createDirectory(at: soundsDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Public Interface

    /// Returns URL of current custom sound, nil if none imported
    func customSoundURL() -> URL? {
        guard let filename = customSoundFilename() else { return nil }
        return soundsDirectory.appendingPathComponent(filename)
    }

    /// Returns filename of current custom sound, nil if none imported
    func customSoundFilename() -> String? {
        let contents = try? FileManager.default.contentsOfDirectory(at: soundsDirectory, includingPropertiesForKeys: nil)
        return contents?.first?.lastPathComponent
    }

    /// Import sound from document picker URL
    /// - Returns: filename on success
    /// - Throws: CustomSoundError on failure
    func importSound(from sourceURL: URL) async throws -> String {
        // Start accessing security-scoped resource
        guard sourceURL.startAccessingSecurityScopedResource() else {
            throw CustomSoundError.accessDenied
        }
        defer { sourceURL.stopAccessingSecurityScopedResource() }

        // Check file size
        let attributes = try FileManager.default.attributesOfItem(atPath: sourceURL.path)
        let fileSize = attributes[.size] as? Int ?? 0
        guard fileSize <= maxFileSize else {
            throw CustomSoundError.fileTooLarge
        }

        // Validate playability
        do {
            let player = try AVAudioPlayer(contentsOf: sourceURL)
            // Just creating player validates the file
            _ = player.duration
        } catch {
            throw CustomSoundError.notPlayable
        }

        // Delete existing custom sound
        deleteCustomSound()

        // Copy to app storage
        let filename = sourceURL.lastPathComponent
        let destinationURL = soundsDirectory.appendingPathComponent(filename)

        do {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        } catch {
            throw CustomSoundError.copyFailed
        }

        return filename
    }

    /// Delete current custom sound
    func deleteCustomSound() {
        guard let url = customSoundURL() else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

enum CustomSoundError: LocalizedError {
    case accessDenied
    case fileTooLarge
    case notPlayable
    case copyFailed

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Cannot access the selected file"
        case .fileTooLarge:
            return "File is too large (max 10MB)"
        case .notPlayable:
            return "Cannot play this audio file"
        case .copyFailed:
            return "Failed to save the sound"
        }
    }
}
```

**Step 2: Build and verify**

Run: `xcodebuild -scheme SchoolAlarm -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | grep -E "(error:|BUILD)"`

Expected: Still build errors from Task 1 (AlarmEditView)

**Step 3: Commit**

```bash
git add SchoolAlarm/Services/CustomSoundManager.swift
git commit -m "feat: add CustomSoundManager for importing user sounds"
```

---

### Task 3: Update AlarmEditView for custom sounds

**Files:**
- Modify: `SchoolAlarm/Views/AlarmEditView.swift`

**Step 1: Update state property type**

Change:
```swift
@State private var selectedSound: Alarm.BundledSound
```
to:
```swift
@State private var selectedSound: AlarmSound
```

**Step 2: Add new state properties**

After `audioPlayer`:
```swift
@State private var showingFilePicker = false
@State private var importError: String?
@State private var showingImportError = false
```

**Step 3: Update initializer**

Change:
```swift
_selectedSound = State(initialValue: alarm.bundledSound)
```
to:
```swift
_selectedSound = State(initialValue: alarm.alarmSound)
```

**Step 4: Replace sound picker section**

Replace the sound picker HStack (lines 94-107) with:

```swift
// Sound picker - navigates to full sound selection
NavigationLink {
    SoundSelectionView(selectedSound: $selectedSound)
} label: {
    HStack {
        Text("Sound")
        Spacer()
        Text(selectedSound.displayName)
            .foregroundColor(.gray)
    }
}
.listRowBackground(Color(white: 0.15))
```

**Step 5: Update playPreviewSound function**

Replace the function with:
```swift
private func playPreviewSound(_ sound: AlarmSound) {
    audioPlayer?.stop()

    let url: URL?
    switch sound {
    case .bundled(let bundled):
        url = Bundle.main.url(forResource: bundled.rawValue, withExtension: "caf")
    case .custom:
        url = CustomSoundManager.shared.customSoundURL()
    }

    guard let url else { return }

    do {
        audioPlayer = try AVAudioPlayer(contentsOf: url)
        audioPlayer?.play()
    } catch {
        print("Failed to play preview sound: \(error)")
    }
}
```

**Step 6: Update saveAlarm function**

Change:
```swift
alarm.bundledSound = selectedSound
```
to:
```swift
alarm.alarmSound = selectedSound
```

**Step 7: Build and verify**

Run: `xcodebuild -scheme SchoolAlarm -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | grep -E "(error:|BUILD)"`

Expected: Build error - SoundSelectionView doesn't exist yet

**Step 8: Commit**

```bash
git add SchoolAlarm/Views/AlarmEditView.swift
git commit -m "feat: update AlarmEditView for custom sound selection"
```

---

### Task 4: Create SoundSelectionView

**Files:**
- Create: `SchoolAlarm/Views/SoundSelectionView.swift`

**Step 1: Create the view**

```swift
import SwiftUI
import AVFoundation

struct SoundSelectionView: View {
    @Binding var selectedSound: AlarmSound
    @Environment(\.dismiss) private var dismiss

    @State private var audioPlayer: AVAudioPlayer?
    @State private var showingFilePicker = false
    @State private var importError: String?
    @State private var showingImportError = false

    private var customFilename: String? {
        CustomSoundManager.shared.customSoundFilename()
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            List {
                // Bundled sounds section
                Section {
                    ForEach(Alarm.BundledSound.allCases, id: \.self) { sound in
                        Button {
                            selectedSound = .bundled(sound)
                            playSound(.bundled(sound))
                        } label: {
                            HStack {
                                Text(sound.displayName)
                                    .foregroundColor(.white)
                                Spacer()
                                if case .bundled(let selected) = selectedSound, selected == sound {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                        .listRowBackground(Color(white: 0.15))
                    }
                }

                // Custom sound section
                Section {
                    // Import button
                    Button {
                        showingFilePicker = true
                    } label: {
                        HStack {
                            Text("Choose from Files...")
                                .foregroundColor(.orange)
                            Spacer()
                        }
                    }
                    .listRowBackground(Color(white: 0.15))

                    // Show current custom sound if exists
                    if let filename = customFilename {
                        Button {
                            selectedSound = .custom(filename: filename)
                            playSound(.custom(filename: filename))
                        } label: {
                            HStack {
                                Text((filename as NSString).deletingPathExtension)
                                    .foregroundColor(.white)
                                Spacer()
                                if case .custom = selectedSound {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                        .listRowBackground(Color(white: 0.15))
                    }
                } header: {
                    Text("Custom")
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Sound")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .alert("Import Failed", isPresented: $showingImportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "Unknown error")
        }
    }

    private func playSound(_ sound: AlarmSound) {
        audioPlayer?.stop()

        let url: URL?
        switch sound {
        case .bundled(let bundled):
            url = Bundle.main.url(forResource: bundled.rawValue, withExtension: "caf")
        case .custom:
            url = CustomSoundManager.shared.customSoundURL()
        }

        guard let url else { return }

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.play()
        } catch {
            print("Failed to play sound: \(error)")
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task {
                do {
                    let filename = try await CustomSoundManager.shared.importSound(from: url)
                    await MainActor.run {
                        selectedSound = .custom(filename: filename)
                        playSound(.custom(filename: filename))
                    }
                } catch {
                    await MainActor.run {
                        importError = error.localizedDescription
                        showingImportError = true
                    }
                }
            }
        case .failure(let error):
            importError = error.localizedDescription
            showingImportError = true
        }
    }
}

#Preview {
    NavigationStack {
        SoundSelectionView(selectedSound: .constant(.bundled(.funnyRing)))
    }
}
```

**Step 2: Build and verify**

Run: `xcodebuild -scheme SchoolAlarm -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | grep -E "(error:|BUILD)"`

Expected: Build errors in AlarmKitManager (uses old property name)

**Step 3: Commit**

```bash
git add SchoolAlarm/Views/SoundSelectionView.swift
git commit -m "feat: add SoundSelectionView with custom sound import"
```

---

### Task 5: Update AlarmKitManager for AlarmSound

**Files:**
- Modify: `SchoolAlarm/Services/AlarmKitManager.swift`

**Step 1: Update scheduleAlarms method**

Change line 67 from:
```swift
let soundName = baseAlarm?.alarmSoundName ?? Alarm.BundledSound.funnyRing.rawValue
```
to:
```swift
let soundName = baseAlarm?.alarmSoundName ?? "funny_ring.caf"
```

**Step 2: Build and verify**

Run: `xcodebuild -scheme SchoolAlarm -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | grep -E "(error:|BUILD)"`

Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add SchoolAlarm/Services/AlarmKitManager.swift
git commit -m "fix: update AlarmKitManager for new AlarmSound type"
```

---

### Task 6: Test and verify feature

**Manual testing checklist:**

1. Build and run on simulator
2. Test bundled sounds - select, preview, save
3. Test custom sound import - select file, preview, save
4. Test validation - file > 10MB should error
5. Test replacement - import new custom replaces old

**Step 1: Run and test manually**

**Step 2: Commit any fixes**

---

### Task 7: Update preview providers

**Files:**
- Verify all previews build correctly

**Step 1: Build**

Run: `xcodebuild -scheme SchoolAlarm -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`

**Step 2: Commit if needed**
