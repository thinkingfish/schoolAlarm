import Foundation
import Combine

class DistrictStore: ObservableObject {
    @Published var districts: [District] = []
    @Published var selectedDistrict: District?

    private let selectedDistrictKey = "SelectedDistrictID"

    init() {
        loadDistricts()
        loadSelectedDistrict()
    }

    // MARK: - Loading

    private func loadDistricts() {
        guard let url = Bundle.main.url(forResource: "districts", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([District].self, from: data) else {
            print("Failed to load districts.json")
            return
        }
        districts = decoded.sorted { $0.name < $1.name }
    }

    private func loadSelectedDistrict() {
        guard let savedID = UserDefaults.standard.string(forKey: selectedDistrictKey),
              let district = districts.first(where: { $0.id == savedID }) else {
            return
        }
        selectedDistrict = district
    }

    // MARK: - Selection

    func selectDistrict(_ district: District) {
        selectedDistrict = district
        UserDefaults.standard.set(district.id, forKey: selectedDistrictKey)
    }

    var hasSelectedDistrict: Bool {
        selectedDistrict != nil
    }
}
