import SwiftUI

struct SoundPickerView: View {
    @Binding var selectedSound: AlarmSound
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                List {
                    Section(header: Text("RINGTONES")) {
                        ForEach(AlarmSound.allCases) { sound in
                            Button {
                                selectedSound = sound
                                NotificationManager.shared.playPreviewSound(for: sound)
                            } label: {
                                HStack {
                                    Text(sound.rawValue)
                                        .foregroundColor(.white)

                                    Spacer()

                                    if sound == selectedSound {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.orange)
                                    }
                                }
                            }
                            .listRowBackground(Color(white: 0.15))
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Sound")
            .navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    SoundPickerView(selectedSound: .constant(.radar))
}
