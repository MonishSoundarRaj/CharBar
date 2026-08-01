import Foundation
import Combine
import ServiceManagement

class LaunchAtLogin: ObservableObject {
    @Published var isEnabled: Bool = false
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        self.isEnabled = SMAppService.mainApp.status == .enabled
        
        // Observe changes to isEnabled
        $isEnabled
            .dropFirst() // Skip initial value
            .sink { [weak self] newValue in
                self?.updateLoginItem(newValue)
            }
            .store(in: &cancellables)
    }
    
    private func updateLoginItem(_ enable: Bool) {
        do {
            if enable {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
        }
    }
}
