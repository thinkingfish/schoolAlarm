import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var districtStore: DistrictStore
    let onComplete: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.orange)

                Text("Welcome to SchoolAlarm")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Select your school district to get started")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Spacer()

                NavigationLink {
                    DistrictSelectionView { _ in
                        onComplete()
                    }
                    .environmentObject(districtStore)
                } label: {
                    Text("Choose District")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.orange)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 48)
            }
        }
    }
}
