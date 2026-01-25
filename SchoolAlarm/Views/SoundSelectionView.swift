import SwiftUI
import AVFoundation

struct SoundSelectionView: View {
    @Binding var selectedSound: Alarm.AlarmSound
    let easterEggUnlocked: Bool

    @Environment(\.dismiss) private var dismiss

    @State private var audioPlayer: AVAudioPlayer?
    @State private var currentlyPlayingSound: Alarm.AlarmSound?
    @State private var showingFilePicker = false
    @State private var importError: String?
    @State private var showingImportError = false

    private var customFilename: String? {
        CustomSoundManager.shared.customSoundFilename()
    }

    private var availableBundledSounds: [Alarm.BundledSound] {
        Alarm.BundledSound.allCases.filter { sound in
            // Hide kid shouting sounds unless easter egg is unlocked
            if sound == .kidShouting1 || sound == .kidShouting2 {
                return easterEggUnlocked
            }
            return true
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            List {
                // Bundled sounds section
                Section {
                    ForEach(availableBundledSounds, id: \.self) { sound in
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

    private func playSound(_ sound: Alarm.AlarmSound) {
        // If already playing this sound, restart it from the beginning
        if currentlyPlayingSound == sound, let player = audioPlayer {
            player.currentTime = 0
            player.play()
            return
        }

        // Stop current player and create new one for different sound
        audioPlayer?.stop()
        currentlyPlayingSound = sound

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
            currentlyPlayingSound = nil
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
        SoundSelectionView(selectedSound: .constant(.bundled(.funnyRing)), easterEggUnlocked: false)
    }
}
