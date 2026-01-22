import SwiftUI

struct DistrictSelectionView: View {
    @EnvironmentObject var districtStore: DistrictStore
    @Environment(\.dismiss) private var dismiss

    let onSelect: ((District) -> Void)?

    @State private var searchText = ""

    init(onSelect: ((District) -> Void)? = nil) {
        self.onSelect = onSelect
    }

    var filteredDistricts: [District] {
        if searchText.isEmpty {
            return districtStore.districts
        }
        return districtStore.districts.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.shortName.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        List {
            Section {
                ForEach(filteredDistricts) { district in
                    Button {
                        districtStore.selectDistrict(district)
                        onSelect?(district)
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(district.shortName)
                                    .font(.headline)
                                Text(district.name)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if districtStore.selectedDistrict?.id == district.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            } header: {
                Text("\(filteredDistricts.count) districts")
            }
        }
        .searchable(text: $searchText, prompt: "Search districts")
        .navigationTitle("Select District")
        .navigationBarTitleDisplayMode(.inline)
    }
}
