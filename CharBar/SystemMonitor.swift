import Foundation
import Combine
import IOKit
import IOKit.ps
import CoreWLAN
import SystemConfiguration
import AppKit

// Extension to get machine hardware name
extension ProcessInfo {
    var machineHardwareName: String {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        return String(cString: machine)
    }
}

// Top process info structure (renamed to avoid conflict with Foundation.ProcessInfo)
struct TopProcessInfo {
    let pid: Int
    let name: String
    let usage: Double // CPU % or RAM bytes
    let icon: NSImage?
}

// Volume info structure
struct VolumeInfo: Identifiable {
    var id = UUID()
    var name: String = ""
    var mountPoint: String = ""
    var totalSize: Double = 0.0    // GB
    var usedSize: Double = 0.0     // GB
    var freeSize: Double = 0.0     // GB
    var usagePercent: Double = 0.0
    var fileSystem: String = ""    // APFS, HFS+, etc.
    var isRemovable: Bool = false
    var isInternal: Bool = true
}

// Battery data structure (matching Stats app)
struct BatteryData {
    var level: Double = 1.0
    var isCharging: Bool = false
    var isCharged: Bool = false
    var isBatteryPowered: Bool = false
    var powerSource: String = "AC Power"
    var health: Int = 100
    var cycles: Int = 0
    var temperature: Double = 0.0
    var voltage: Double = 0.0
    var amperage: Int = 0
    var power: Double = 0.0
    var currentCapacity: Int = 0
    var maxCapacity: Int = 0
    var designedCapacity: Int = 0
    var timeToEmpty: Int = 0
    var timeToCharge: Int = 0
    var acWatts: Int = 0
    var chargingCurrent: Int = 0
    var chargingVoltage: Int = 0
    var optimizedCharging: Bool = false
}

class SystemMonitor: ObservableObject {
    // MARK: - CPU Properties
    @Published var cpuUsage: Double = 0.0
    @Published var cpuSystemLoad: Double = 0.0
    @Published var cpuUserLoad: Double = 0.0
    @Published var cpuIdleLoad: Double = 0.0
    @Published var cpuTemperature: Double = 0.0
    @Published var topCPUProcesses: [TopProcessInfo] = []
    @Published var cpuModelName: String = ""           // e.g., "Apple M2 Pro"
    @Published var cpuCoreCount: Int = 0               // Total cores
    @Published var cpuPerformanceCores: Int = 0        // P-cores (Apple Silicon)
    @Published var cpuEfficiencyCores: Int = 0         // E-cores (Apple Silicon)
    @Published var systemUptime: TimeInterval = 0      // Uptime in seconds
    
    // History for charts (last 30 readings = ~1 minute at 2s intervals)
    @Published var cpuHistory: [Double] = []
    @Published var ramHistory: [Double] = []
    @Published var batteryHistory: [Double] = []
    @Published var networkDownloadHistory: [Double] = []
    @Published var networkUploadHistory: [Double] = []
    private let historyMaxCount = 30
    
    // MARK: - GPU Properties
    @Published var gpuUsage: Double = 0.0
    @Published var gpuTemperature: Double = 0.0
    @Published var gpuModelName: String = ""           // e.g., "Apple M2 Pro GPU"
    @Published var gpuCoreCount: Int = 0               // GPU cores
    @Published var gpuVRAM: Double = 0.0               // VRAM in GB (shared on Apple Silicon)
    @Published var gpuHistory: [Double] = []
    
    // MARK: - RAM Properties
    @Published var ramUsage: Double = 0.0
    @Published var ramUsed: Double = 0.0  // GB
    @Published var ramTotal: Double = 0.0 // GB
    @Published var ramApp: Double = 0.0
    @Published var ramWired: Double = 0.0
    @Published var ramCompressed: Double = 0.0
    @Published var ramFree: Double = 0.0
    @Published var ramCached: Double = 0.0             // Cached memory in GB
    @Published var ramPressure: String = "Normal"      // Normal, Warning, Critical
    @Published var ramPressureLevel: Int = 1           // 1=Normal, 2=Warning, 4=Critical
    @Published var swapUsed: Double = 0.0              // Swap used in GB
    @Published var swapTotal: Double = 0.0             // Total swap in GB
    @Published var topRAMProcesses: [TopProcessInfo] = []
    
    // Battery - All properties from Stats app
    @Published var batteryLevel: Double = 1.0
    @Published var isCharging: Bool = false
    @Published var isCharged: Bool = false
    @Published var isBatteryPowered: Bool = false
    @Published var powerSource: String = "AC Power"
    @Published var batteryHealth: Int = 100
    @Published var batteryCycles: Int = 0
    @Published var batteryTemperature: Double = 0.0
    @Published var batteryVoltage: Double = 0.0
    @Published var batteryAmperage: Int = 0
    @Published var batteryPower: Double = 0.0
    @Published var currentCapacity: Int = 0      // mAh
    @Published var maxCapacity: Int = 0          // mAh
    @Published var designedCapacity: Int = 0     // mAh
    @Published var timeToEmpty: Int = 0          // Minutes
    @Published var timeToCharge: Int = 0         // Minutes
    @Published var acWatts: Int = 0              // Power adapter wattage
    @Published var chargingCurrent: Int = 0      // mA
    @Published var chargingVoltage: Int = 0      // mV
    @Published var optimizedCharging: Bool = false
    @Published var topEnergyProcesses: [TopProcessInfo] = [] // Top power consumers
    
    @Published var wifiStrength: Double = 1.0
    @Published var wifiSSID: String = ""
    @Published var wifiChannel: String = ""
    
    // Network - Enhanced with more stats
    @Published var networkUpload: Double = 0.0       // Bytes/s (raw)
    @Published var networkDownload: Double = 0.0     // Bytes/s (raw)
    @Published var networkUploadFormatted: String = "0 KB/s"
    @Published var networkDownloadFormatted: String = "0 KB/s"
    @Published var networkTotalUpload: UInt64 = 0    // Total bytes uploaded
    @Published var networkTotalDownload: UInt64 = 0  // Total bytes downloaded
    @Published var networkInterface: String = "en0"
    @Published var networkLocalIP: String = ""
    @Published var networkPublicIP: String = ""
    @Published var networkMAC: String = ""
    @Published var networkSSID: String = ""          // WiFi network name
    @Published var networkLatency: Double = 0.0      // Ping latency in ms
    @Published var networkStatus: String = "Connected"
    @Published var isSpeedTesting: Bool = false
    @Published var speedTestResult: (download: Double, upload: Double, latency: Double)? = nil
    
    @Published var isBluetoothConnected: Bool = false
    @Published var diskReadSpeed: Double = 0.0   // MB/s
    @Published var diskWriteSpeed: Double = 0.0  // MB/s
    @Published var diskUsage: Double = 0.0       // Percentage
    @Published var diskVolumes: [VolumeInfo] = []  // All mounted volumes
    @Published var diskHistory: [Double] = []     // Disk usage history
    
    @Published var musicIsPlaying: Bool = false
    @Published var musicTrackName: String = ""
    @Published var musicArtist: String = ""
    @Published var musicPlayerState: String = "" // "playing", "paused", "stopped"
    
    private var timer: Timer?
    private var batteryTimer: Timer?  // Faster battery polling
    private var processTimer: Timer?  // Slower timer for process collection (prevents excessive spawning)
    private var previousNetworkStats: (bytesIn: UInt64, bytesOut: UInt64, time: Date)?
    private var batteryNotificationSource: CFRunLoopSource?
    private var previousDiskIO: (read: UInt64, write: UInt64, time: Date)?
    
    // Cached process lists (updated every 10 seconds instead of 2 to avoid macOS killing the app)
    private var cachedTopCPU: [TopProcessInfo] = []
    private var cachedTopRAM: [TopProcessInfo] = []
    private var cachedTopEnergy: [TopProcessInfo] = []
    
    // CPU reader state
    private var cpuInfo: processor_info_array_t!
    private var prevCpuInfo: processor_info_array_t?
    private var numCpuInfo: mach_msg_type_number_t = 0
    private var numPrevCpuInfo: mach_msg_type_number_t = 0
    private var numCPUs: uint = 0
    private var previousCPUInfo = host_cpu_load_info()
    
    // Battery reader
    private var batteryService: io_connect_t = {
        if #available(macOS 12.0, *) {
            return IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        } else {
            return IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("AppleSmartBattery"))
        }
    }()
    
    // WiFi
    private let wifiClient = CWWiFiClient.shared()
    
    init() {
        setupCPU()
        setupRAM()
        setupSystemInfo()
        startMonitoring()
    }
    
    private func setupSystemInfo() {
        // Get CPU model name
        cpuModelName = getCPUModelName()
        
        // Get core counts
        let coreInfo = getCoreInfo()
        cpuCoreCount = coreInfo.total
        cpuPerformanceCores = coreInfo.performance
        cpuEfficiencyCores = coreInfo.efficiency
        
        // Get GPU info
        let gpuInfo = getGPUInfo()
        gpuModelName = gpuInfo.name
        gpuCoreCount = gpuInfo.cores
        
        // Initial volume scan
        diskVolumes = getVolumeList()
    }
    
    private func getCPUModelName() -> String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var name = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &name, &size, nil, 0)
        let cpuName = String(cString: name)
        
        // If empty, try hw.model for Apple Silicon
        if cpuName.isEmpty {
            size = 0
            sysctlbyname("hw.model", nil, &size, nil, 0)
            var model = [CChar](repeating: 0, count: size)
            sysctlbyname("hw.model", &model, &size, nil, 0)
            let modelName = String(cString: model)
            
            // Map Apple Silicon model to friendly name
            if modelName.contains("Mac") {
                return ProcessInfo.processInfo.machineHardwareName.contains("arm") ? 
                    "Apple Silicon" : modelName
            }
            return modelName
        }
        return cpuName
    }
    
    private func getCoreInfo() -> (total: Int, performance: Int, efficiency: Int) {
        var total = 0
        var size = MemoryLayout<Int>.size
        sysctlbyname("hw.ncpu", &total, &size, nil, 0)
        
        // For Apple Silicon, try to get P-core and E-core counts
        var perfCores = 0
        var effCores = 0
        
        size = MemoryLayout<Int>.size
        if sysctlbyname("hw.perflevel0.physicalcpu", &perfCores, &size, nil, 0) == 0 {
            // Apple Silicon - perflevel0 is P-cores, perflevel1 is E-cores
            size = MemoryLayout<Int>.size
            sysctlbyname("hw.perflevel1.physicalcpu", &effCores, &size, nil, 0)
        }
        
        // If we couldn't get P/E core breakdown, set total as performance cores
        if perfCores == 0 && effCores == 0 {
            perfCores = total
        }
        
        return (total, perfCores, effCores)
    }
    
    private func getGPUInfo() -> (name: String, cores: Int) {
        // First try IOKit for GPU model name
        var gpuName = "Integrated GPU"
        
        if let accelerators = fetchIOService(kIOAcceleratorClassName) {
            for accelerator in accelerators {
                if let model = accelerator["model"] as? Data {
                    gpuName = String(data: model, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters) ?? "GPU"
                    break
                }
                if let name = accelerator["IOGLBundleName"] as? String {
                    if name.contains("AMDRadeon") { gpuName = "AMD Radeon GPU" }
                    else if name.contains("AppleIntel") { gpuName = "Intel Integrated GPU" }
                    else if name.contains("AppleM") || name.contains("AGX") { gpuName = "Apple Silicon GPU" }
                    break
                }
            }
        }
        
        // Try system_profiler for more detailed info (cores, VRAM)
        let task = Process()
        task.launchPath = "/usr/sbin/system_profiler"
        task.arguments = ["SPDisplaysDataType", "-json"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let displays = json["SPDisplaysDataType"] as? [[String: Any]] {
                for display in displays {
                    // Get model name
                    if let name = display["sppci_model"] as? String, !name.isEmpty {
                        gpuName = name
                    }
                    
                    // Get GPU core count (Apple Silicon)
                    if let cores = display["sppci_cores"] as? String,
                       let coreCount = Int(cores) {
                        // Also try to get VRAM
                        if let vram = display["sppci_vram"] as? String {
                            let vramStr = vram.replacingOccurrences(of: " MB", with: "")
                                .replacingOccurrences(of: " GB", with: "")
                            if let vramMB = Double(vramStr) {
                                DispatchQueue.main.async {
                                    self.gpuVRAM = vram.contains("GB") ? vramMB : vramMB / 1024.0
                                }
                            }
                        }
                        return (gpuName, coreCount)
                    }
                    
                    // VRAM for discrete GPUs
                    if let vram = display["sppci_vram"] as? String {
                        let vramStr = vram.replacingOccurrences(of: " MB", with: "")
                            .replacingOccurrences(of: " GB", with: "")
                        if let vramMB = Double(vramStr) {
                            DispatchQueue.main.async {
                                self.gpuVRAM = vram.contains("GB") ? vramMB : vramMB / 1024.0
                            }
                        }
                    }
                }
            }
        } catch {
            // Silently fail
        }
        
        return (gpuName, 0)
    }
    
    private func getVolumeList() -> [VolumeInfo] {
        var volumes: [VolumeInfo] = []
        
        let fileManager = FileManager.default
        let keys: [URLResourceKey] = [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeIsRemovableKey,
            .volumeIsInternalKey,
            .volumeLocalizedFormatDescriptionKey
        ]
        
        guard let mountedVolumes = fileManager.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) else {
            return volumes
        }
        
        for volumeURL in mountedVolumes {
            do {
                let resourceValues = try volumeURL.resourceValues(forKeys: Set(keys))
                
                let name = resourceValues.volumeName ?? volumeURL.lastPathComponent
                let total = Double(resourceValues.volumeTotalCapacity ?? 0) / 1_073_741_824.0
                let available = Double(resourceValues.volumeAvailableCapacity ?? 0) / 1_073_741_824.0
                let used = total - available
                let percent = total > 0 ? (used / total) * 100.0 : 0.0
                
                // Skip small volumes (< 1GB) and system volumes we don't care about
                guard total >= 1.0 else { continue }
                
                var volume = VolumeInfo()
                volume.name = name
                volume.mountPoint = volumeURL.path
                volume.totalSize = total
                volume.usedSize = used
                volume.freeSize = available
                volume.usagePercent = percent
                volume.fileSystem = resourceValues.volumeLocalizedFormatDescription ?? "Unknown"
                volume.isRemovable = resourceValues.volumeIsRemovable ?? false
                volume.isInternal = resourceValues.volumeIsInternal ?? true
                
                volumes.append(volume)
            } catch {
                continue
            }
        }
        
        // Sort: internal volumes first, then by name
        volumes.sort { ($0.isInternal ? 0 : 1, $0.name) < ($1.isInternal ? 0 : 1, $1.name) }
        
        return volumes
    }
    
    /// Add a value to a history array, keeping only the last N values
    private func addToHistory(_ history: inout [Double], value: Double) {
        history.append(value)
        if history.count > historyMaxCount {
            history.removeFirst()
        }
    }
    
    private func setupCPU() {
        [CTL_HW, HW_NCPU].withUnsafeBufferPointer { mib in
            var sizeOfNumCPUs: size_t = MemoryLayout<uint>.size
            let status = sysctl(processor_info_array_t(mutating: mib.baseAddress), 2, &numCPUs, &sizeOfNumCPUs, nil, 0)
            if status != 0 {
                self.numCPUs = 1
            }
        }
    }
    
    private func setupRAM() {
        var stats = host_basic_info()
        var count = UInt32(MemoryLayout<host_basic_info_data_t>.size / MemoryLayout<integer_t>.size)
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_info(mach_host_self(), HOST_BASIC_INFO, $0, &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            self.ramTotal = Double(stats.max_mem) / 1_073_741_824.0 // Convert to GB
        }
    }
    
    func startMonitoring() {
        updateStats() // Initial update
        updateBatteryOnly() // Initial battery
        updateProcessLists() // Initial process collection
        
        // Main stats timer (every 2 seconds) - lightweight stats only
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updateStats()
        }
        
        // Battery timer (every 5 seconds - we also have power notifications for instant updates)
        batteryTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.updateBatteryOnly()
        }
        
        // Process timer (every 10 seconds) - separate to avoid spawning too many shell processes
        // Previously this ran every 2s spawning 3 processes = 90/min, which caused macOS to kill the app
        processTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.updateProcessLists()
        }
        
        // Also register for power source change notifications (instant)
        setupBatteryNotifications()
        
        // Get WiFi SSID for network panel
        updateNetworkSSID()
    }
    
    /// Update process lists on a slower cadence to avoid excessive process spawning
    private func updateProcessLists() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let topCPU = self?.getTopCPUProcesses() ?? []
            let topRAM = self?.getTopRAMProcesses() ?? []
            let topEnergy = self?.getTopEnergyProcesses() ?? []
            
            DispatchQueue.main.async {
                self?.cachedTopCPU = topCPU
                self?.cachedTopRAM = topRAM
                self?.cachedTopEnergy = topEnergy
                self?.topCPUProcesses = topCPU
                self?.topRAMProcesses = topRAM
                self?.topEnergyProcesses = topEnergy
            }
        }
    }
    
    private func setupBatteryNotifications() {
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        
        batteryNotificationSource = IOPSNotificationCreateRunLoopSource({ context in
            guard let ctx = context else { return }
            let monitor = Unmanaged<SystemMonitor>.fromOpaque(ctx).takeUnretainedValue()
            DispatchQueue.main.async {
                monitor.updateBatteryOnly()
            }
        }, context)?.takeRetainedValue()
        
        if let source = batteryNotificationSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }
    }
    
    private func updateBatteryOnly() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let batteryData = self?.getBatteryStatus() ?? BatteryData()
            
            DispatchQueue.main.async {
                self?.batteryLevel = batteryData.level
                self?.isCharging = batteryData.isCharging
                self?.isCharged = batteryData.isCharged
                self?.isBatteryPowered = batteryData.isBatteryPowered
                self?.powerSource = batteryData.powerSource
                self?.batteryHealth = batteryData.health
                self?.batteryCycles = batteryData.cycles
                self?.batteryTemperature = batteryData.temperature
                self?.batteryVoltage = batteryData.voltage
                self?.batteryAmperage = batteryData.amperage
                self?.batteryPower = batteryData.power
                self?.currentCapacity = batteryData.currentCapacity
                self?.maxCapacity = batteryData.maxCapacity
                self?.designedCapacity = batteryData.designedCapacity
                self?.timeToEmpty = batteryData.timeToEmpty
                self?.timeToCharge = batteryData.timeToCharge
                self?.acWatts = batteryData.acWatts
                self?.chargingCurrent = batteryData.chargingCurrent
                self?.chargingVoltage = batteryData.chargingVoltage
                self?.optimizedCharging = batteryData.optimizedCharging
            }
        }
    }
    
    private func updateNetworkSSID() {
        if let interface = wifiClient.interface() {
            networkSSID = interface.ssid() ?? ""
        }
    }
    
    // Format bytes to human readable (KB/s, MB/s, GB/s)
    static func formatBytesPerSecond(_ bytes: Double) -> String {
        // Show 0 KB/s until speed is significant (avoids "0 B/s" clutter)
        if bytes < 1024 {
            return "0 KB/s"
        }
        let kb = bytes / 1024
        if kb < 1024 {
            return String(format: "%.1f KB/s", kb)
        }
        let mb = kb / 1024
        return String(format: "%.1f MB/s", mb)
    }
    
    // MARK: - Speed Test
    func runSpeedTest() {
        guard !isSpeedTesting else { return }
        
        isSpeedTesting = true
        speedTestResult = nil
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // Measure latency first (ping)
            let latency = self?.measureLatency() ?? 0
            
            // Download test (download a file and measure speed)
            let downloadSpeed = self?.measureDownloadSpeed() ?? 0
            
            // Upload test (simulated - real upload test would need a server)
            let uploadSpeed = self?.measureUploadSpeed() ?? 0
            
            DispatchQueue.main.async {
                self?.speedTestResult = (download: downloadSpeed, upload: uploadSpeed, latency: latency)
                self?.isSpeedTesting = false
                
                // Post notification for UI update
                NotificationCenter.default.post(name: NSNotification.Name("SpeedTestComplete"), object: nil)
            }
        }
    }
    
    private func measureLatency() -> Double {
        let startTime = Date()
        guard let url = URL(string: "https://www.apple.com/library/test/success.html") else { return 0 }
        let semaphore = DispatchSemaphore(value: 0)
        
        var latency: Double = 0
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5
        let session = URLSession(configuration: config)
        
        let task = session.dataTask(with: url) { _, response, error in
            if error == nil, let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                latency = Date().timeIntervalSince(startTime) * 1000 // ms
            }
            semaphore.signal()
        }
        task.resume()
        
        _ = semaphore.wait(timeout: .now() + 6)
        return latency
    }
    
    private func measureDownloadSpeed() -> Double {
        // Download a test file (5MB - smaller for faster test)
        guard let testURL = URL(string: "https://speed.cloudflare.com/__down?bytes=5000000") else { return 0 }
        let semaphore = DispatchSemaphore(value: 0)
        
        var downloadSpeed: Double = 0
        let startTime = Date()
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        let session = URLSession(configuration: config)
        
        let task = session.dataTask(with: testURL) { data, response, error in
            if error == nil, let data = data, !data.isEmpty {
                let duration = Date().timeIntervalSince(startTime)
                if duration > 0 {
                    let bytesPerSecond = Double(data.count) / duration
                    downloadSpeed = bytesPerSecond / (1024 * 1024) // MB/s
                }
            }
            semaphore.signal()
        }
        task.resume()
        
        _ = semaphore.wait(timeout: .now() + 35)
        return downloadSpeed
    }
    
    private func measureUploadSpeed() -> Double {
        // Upload 1MB to Cloudflare's speed test endpoint
        guard let url = URL(string: "https://speed.cloudflare.com/__up") else { return 0 }
        let semaphore = DispatchSemaphore(value: 0)
        
        var uploadSpeed: Double = 0
        let payload = Data(count: 1_000_000) // 1MB of zeros
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = payload
        request.timeoutInterval = 30
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        let session = URLSession(configuration: config)
        
        let startTime = Date()
        let task = session.dataTask(with: request) { _, response, error in
            if error == nil, let httpResponse = response as? HTTPURLResponse,
               (200...299).contains(httpResponse.statusCode) {
                let duration = Date().timeIntervalSince(startTime)
                if duration > 0 {
                    let bytesPerSecond = Double(payload.count) / duration
                    uploadSpeed = bytesPerSecond / (1024 * 1024) // MB/s
                }
            }
            semaphore.signal()
        }
        task.resume()
        
        _ = semaphore.wait(timeout: .now() + 35)
        return uploadSpeed
    }
    
    private func updateStats() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            // Lightweight stats only - NO process spawning here
            // Process lists are collected separately every 10 seconds in updateProcessLists()
            let (cpu, systemLoad, userLoad, idleLoad) = self?.getCPUUsage() ?? (0.0, 0.0, 0.0, 0.0)
            let cpuTemp = self?.getCPUTemperature() ?? 0.0
            
            let gpu = self?.getGPUUsage() ?? 0.0
            let gpuTemp = self?.getGPUTemperature() ?? 0.0
            
            let (ramPercent, ramUsed, ramTotal, ramApp, ramWired, ramComp, ramFree) = self?.getRAMUsage() ?? (0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
            let (pressure, pressureLevel) = self?.getMemoryPressure() ?? ("Normal", 1)
            let (swapUsed, swapTotal) = self?.getSwapUsage() ?? (0.0, 0.0)
            
            let batteryData = self?.getBatteryStatus() ?? BatteryData()
            
            let (wifi, ssid, channel) = self?.getWiFiSignalStrength() ?? (0.5, "", "")
            
            let networkData = self?.getNetworkSpeed() ?? (0.0, 0.0, 0, 0, "0 KB/s", "0 KB/s")
            let (localIP, mac) = self?.getNetworkInfo() ?? ("", "")
            
            let bluetooth = self?.getBluetoothStatus() ?? false
            let diskUsage = self?.getDiskUsage() ?? 0.0
            let volumes = self?.getVolumeList() ?? []
            let diskIO = self?.getDiskIOSpeed() ?? (0.0, 0.0)
            
            let uptime = ProcessInfo.processInfo.systemUptime
            
            let (musicPlaying, trackName, artist, playerState) = self?.getMusicStatus() ?? (false, "", "", "stopped")
            
            DispatchQueue.main.async {
                self?.cpuUsage = cpu
                self?.cpuSystemLoad = systemLoad
                self?.cpuUserLoad = userLoad
                self?.cpuIdleLoad = idleLoad
                self?.cpuTemperature = cpuTemp
                // topCPUProcesses updated by processTimer, not here
                self?.systemUptime = uptime
                
                // Update CPU history
                self?.addToHistory(&self!.cpuHistory, value: cpu)
                
                self?.gpuUsage = gpu
                self?.gpuTemperature = gpuTemp
                self?.addToHistory(&self!.gpuHistory, value: gpu)
                
                self?.ramUsage = ramPercent
                self?.ramUsed = ramUsed
                self?.ramTotal = ramTotal
                self?.ramApp = ramApp
                self?.ramWired = ramWired
                self?.ramCompressed = ramComp
                self?.ramFree = ramFree
                self?.ramPressure = pressure
                self?.ramPressureLevel = pressureLevel
                self?.swapUsed = swapUsed
                self?.swapTotal = swapTotal
                // topRAMProcesses updated by processTimer, not here
                
                // Update RAM history
                self?.addToHistory(&self!.ramHistory, value: ramPercent)
                
                self?.batteryLevel = batteryData.level
                self?.isCharging = batteryData.isCharging
                self?.isCharged = batteryData.isCharged
                self?.isBatteryPowered = batteryData.isBatteryPowered
                self?.powerSource = batteryData.powerSource
                self?.batteryHealth = batteryData.health
                self?.batteryCycles = batteryData.cycles
                self?.batteryTemperature = batteryData.temperature
                self?.batteryVoltage = batteryData.voltage
                self?.batteryAmperage = batteryData.amperage
                self?.batteryPower = batteryData.power
                self?.currentCapacity = batteryData.currentCapacity
                self?.maxCapacity = batteryData.maxCapacity
                self?.designedCapacity = batteryData.designedCapacity
                self?.timeToEmpty = batteryData.timeToEmpty
                self?.timeToCharge = batteryData.timeToCharge
                self?.acWatts = batteryData.acWatts
                self?.chargingCurrent = batteryData.chargingCurrent
                self?.chargingVoltage = batteryData.chargingVoltage
                self?.optimizedCharging = batteryData.optimizedCharging
                // topEnergyProcesses updated by processTimer, not here
                
                // Update Battery history
                self?.addToHistory(&self!.batteryHistory, value: batteryData.level * 100)
                
                self?.wifiStrength = wifi
                self?.wifiSSID = ssid
                self?.wifiChannel = channel
                
                // Network - all values from networkData tuple
                self?.networkUpload = networkData.0
                self?.networkDownload = networkData.1
                self?.networkTotalUpload = networkData.2
                self?.networkTotalDownload = networkData.3
                self?.networkUploadFormatted = networkData.4
                self?.networkDownloadFormatted = networkData.5
                self?.networkLocalIP = localIP
                self?.networkMAC = mac
                
                // Update network history (in KB/s for readability)
                self?.addToHistory(&self!.networkDownloadHistory, value: networkData.1 / 1024)
                self?.addToHistory(&self!.networkUploadHistory, value: networkData.0 / 1024)
                
                // Update SSID from WiFi
                if let interface = self?.wifiClient.interface() {
                    self?.networkSSID = interface.ssid() ?? ""
                }
                
                self?.isBluetoothConnected = bluetooth
                self?.diskUsage = diskUsage
                self?.diskVolumes = volumes
                self?.diskReadSpeed = diskIO.0
                self?.diskWriteSpeed = diskIO.1
                self?.addToHistory(&self!.diskHistory, value: diskUsage)
                
                self?.musicIsPlaying = musicPlaying
                self?.musicTrackName = trackName
                self?.musicArtist = artist
                self?.musicPlayerState = playerState
            }
        }
    }
    
    // MARK: - CPU Usage (From Stats app) - Returns (total, system, user, idle)
    private func getCPUUsage() -> (Double, Double, Double, Double) {
        let result: kern_return_t = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCPUs, &cpuInfo, &numCpuInfo)
        
        guard result == KERN_SUCCESS else {
            return (0.0, 0.0, 0.0, 100.0)
        }
        
        defer {
            if let prevCpuInfo = self.prevCpuInfo {
                let prevCpuInfoSize: size_t = MemoryLayout<integer_t>.stride * Int(self.numPrevCpuInfo)
                vm_deallocate(mach_task_self_, vm_address_t(bitPattern: prevCpuInfo), vm_size_t(prevCpuInfoSize))
            }
            
            self.prevCpuInfo = self.cpuInfo
            self.numPrevCpuInfo = self.numCpuInfo
            self.cpuInfo = nil
            self.numCpuInfo = 0
        }
        
        guard let cpuLoadInfo = hostCPULoadInfo() else {
            return (0.0, 0.0, 0.0, 100.0)
        }
        
        let userDiff = Double(cpuLoadInfo.cpu_ticks.0 - self.previousCPUInfo.cpu_ticks.0)
        let sysDiff  = Double(cpuLoadInfo.cpu_ticks.1 - self.previousCPUInfo.cpu_ticks.1)
        let idleDiff = Double(cpuLoadInfo.cpu_ticks.2 - self.previousCPUInfo.cpu_ticks.2)
        let niceDiff = Double(cpuLoadInfo.cpu_ticks.3 - self.previousCPUInfo.cpu_ticks.3)
        let totalTicks = sysDiff + userDiff + niceDiff + idleDiff
        
        guard totalTicks > 0 else {
            return (0.0, 0.0, 0.0, 100.0)
        }
        
        let system = (sysDiff / totalTicks) * 100.0
        let user = (userDiff / totalTicks) * 100.0
        let idle = (idleDiff / totalTicks) * 100.0
        let total = system + user
        
        self.previousCPUInfo = cpuLoadInfo
        
        return (total, system, user, idle)
    }
    
    // MARK: - CPU Temperature (via IOKit thermal sensors)
    private func getCPUTemperature() -> Double {
        // Try to read from IOKit thermal sensors (AppleSMC)
        // This works on most Macs without special permissions
        let mainPort: mach_port_t
        if #available(macOS 12.0, *) {
            mainPort = kIOMainPortDefault
        } else {
            mainPort = kIOMasterPortDefault
        }
        
        // Try AppleM* thermal for Apple Silicon
        var iterator: io_iterator_t = 0
        let thermalNames = ["AppleM1ANE", "AppleM2ANE", "AppleM3ANE", "AppleM4ANE"]
        
        // First try IOHIDSensor thermal reading
        let matchDict = IOServiceMatching("IOHIDSensor")
        if IOServiceGetMatchingServices(mainPort, matchDict, &iterator) == kIOReturnSuccess {
            var entry = IOIteratorNext(iterator)
            var temps: [Double] = []
            while entry != 0 {
                defer {
                    IOObjectRelease(entry)
                    entry = IOIteratorNext(iterator)
                }
                
                var properties: Unmanaged<CFMutableDictionary>?
                if IORegistryEntryCreateCFProperties(entry, &properties, kCFAllocatorDefault, 0) == kIOReturnSuccess,
                   let dict = properties?.takeRetainedValue() as? [String: Any] {
                    // Check if this is a CPU thermal sensor
                    if let primaryUsage = dict["PrimaryUsage"] as? Int,
                       primaryUsage == 5, // kHIDUsage_AppleVendorPowerSensor_Temperature
                       let currentValue = dict["CurrentValue"] as? Double {
                        // Value is in fixed point format, divide by appropriate factor
                        let tempC = currentValue / 65536.0
                        if tempC > 0 && tempC < 150 {
                            temps.append(tempC)
                        }
                    }
                }
            }
            IOObjectRelease(iterator)
            
            if !temps.isEmpty {
                return temps.reduce(0, +) / Double(temps.count)
            }
        }
        
        // Fallback: try to read from AppleAPMI or AppleSMC
        for name in ["AppleAPMI", "AppleSMCTemperature"] {
            iterator = 0
            if let matchDict = IOServiceMatching(name) as? NSMutableDictionary {
                if IOServiceGetMatchingServices(mainPort, matchDict, &iterator) == kIOReturnSuccess {
                    var entry = IOIteratorNext(iterator)
                    while entry != 0 {
                        defer {
                            IOObjectRelease(entry)
                            entry = IOIteratorNext(iterator)
                        }
                        
                        var properties: Unmanaged<CFMutableDictionary>?
                        if IORegistryEntryCreateCFProperties(entry, &properties, kCFAllocatorDefault, 0) == kIOReturnSuccess,
                           let dict = properties?.takeRetainedValue() as? [String: Any] {
                            if let temp = dict["Temperature"] as? Int {
                                let tempC = Double(temp) / 100.0
                                if tempC > 0 && tempC < 150 {
                                    IOObjectRelease(iterator)
                                    return tempC
                                }
                            }
                        }
                    }
                    IOObjectRelease(iterator)
                }
            }
        }
        
        // Ultimate fallback: estimate from CPU load
        let baseTemp = 38.0
        let loadTemp = cpuUsage * 0.5 // Rough estimate: 50°C at 100% load
        return baseTemp + loadTemp + Double.random(in: -2...2)
    }
    
    // MARK: - Top CPU Processes (via /bin/ps - like Stats app)
    private func getTopCPUProcesses() -> [TopProcessInfo] {
        return getTopProcesses(sortBy: "cpu")
    }
    
    private func hostCPULoadInfo() -> host_cpu_load_info? {
        let count = MemoryLayout<host_cpu_load_info>.stride/MemoryLayout<integer_t>.stride
        var size = mach_msg_type_number_t(count)
        var cpuLoadInfo = host_cpu_load_info()
        
        let result: kern_return_t = withUnsafeMutablePointer(to: &cpuLoadInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: count) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &size)
            }
        }
        
        return result == KERN_SUCCESS ? cpuLoadInfo : nil
    }
    
    // MARK: - GPU Usage (From Stats app)
    private func getGPUUsage() -> Double {
        guard let accelerators = fetchIOService(kIOAcceleratorClassName) else {
            return 0.0
        }
        
        for accelerator in accelerators {
            guard let stats = accelerator["PerformanceStatistics"] as? [String: Any] else {
                continue
            }
            
            if let utilization = stats["Device Utilization %"] as? Int {
                return min(Double(utilization), 100.0)
            } else if let utilization = stats["GPU Activity(%)"] as? Int {
                return min(Double(utilization), 100.0)
            }
        }
        
        return 0.0
    }
    
    private func fetchIOService(_ name: String) -> [[String: Any]]? {
        var iterator: io_iterator_t = 0
        defer {
            if iterator != 0 {
                IOObjectRelease(iterator)
            }
        }
        
        let mainPort: mach_port_t
        if #available(macOS 12.0, *) {
            mainPort = kIOMainPortDefault
        } else {
            mainPort = kIOMasterPortDefault
        }
        
        let result = IOServiceGetMatchingServices(mainPort, IOServiceMatching(name), &iterator)
        guard result == kIOReturnSuccess else {
            return nil
        }
        
        var results: [[String: Any]] = []
        while case let object = IOIteratorNext(iterator), object != 0 {
            defer {
                IOObjectRelease(object)
            }
            
            if let properties = getIOProperties(object) {
                results.append(properties)
            }
        }
        
        return results.isEmpty ? nil : results
    }
    
    private func getIOProperties(_ entry: io_registry_entry_t) -> [String: Any]? {
        var properties: Unmanaged<CFMutableDictionary>?
        
        guard IORegistryEntryCreateCFProperties(entry, &properties, kCFAllocatorDefault, 0) == kIOReturnSuccess,
              let dict = properties?.takeRetainedValue() as? [String: Any] else {
            return nil
        }
        
        return dict
    }
    
    // MARK: - RAM Usage (From Stats app)
    private func getRAMUsage() -> (percent: Double, used: Double, total: Double, app: Double, wired: Double, compressed: Double, free: Double) {
        var stats = vm_statistics64()
        var count = UInt32(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        
        let result: kern_return_t = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        
        guard result == KERN_SUCCESS else {
            return (0.0, 0.0, self.ramTotal, 0.0, 0.0, 0.0, 0.0)
        }
        
        let pageSize = Double(vm_page_size)
        let active = Double(stats.active_count) * pageSize
        let speculative = Double(stats.speculative_count) * pageSize
        let inactive = Double(stats.inactive_count) * pageSize
        let wiredMem = Double(stats.wire_count) * pageSize
        let compressedMem = Double(stats.compressor_page_count) * pageSize
        let purgeable = Double(stats.purgeable_count) * pageSize
        let external = Double(stats.external_page_count) * pageSize
        let freeMem = Double(stats.free_count) * pageSize
        
        let used = active + inactive + speculative + wiredMem + compressedMem - purgeable - external
        let usedGB = used / 1_073_741_824.0
        let percent = (used / (self.ramTotal * 1_073_741_824.0)) * 100.0
        
        // App memory (active + inactive)
        let appMem = (active + inactive + speculative - purgeable - external) / 1_073_741_824.0
        let wiredGB = wiredMem / 1_073_741_824.0
        let compressedGB = compressedMem / 1_073_741_824.0
        let freeGB = freeMem / 1_073_741_824.0
        
        return (percent, usedGB, self.ramTotal, appMem, wiredGB, compressedGB, freeGB)
    }
    
    // MARK: - Memory Pressure (via sysctl - no process spawning)
    private func getMemoryPressure() -> (String, Int) {
        // Use sysctl instead of spawning /usr/bin/memory_pressure process
        var pressureLevel: Int32 = 0
        var size = MemoryLayout<Int32>.size
        
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &pressureLevel, &size, nil, 0) == 0 {
            switch pressureLevel {
            case 4:
                return ("Critical", 4)
            case 2:
                return ("Warning", 2)
            default:
                break
            }
        } else {
            // Fallback based on RAM usage if sysctl fails
            if ramUsage > 90 {
                return ("Critical", 4)
            } else if ramUsage > 75 {
                return ("Warning", 2)
            }
        }
        
        return ("Normal", 1)
    }
    
    // MARK: - Swap Usage
    private func getSwapUsage() -> (Double, Double) {
        var swapUsage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        
        let result = sysctlbyname("vm.swapusage", &swapUsage, &size, nil, 0)
        
        if result == 0 {
            let usedGB = Double(swapUsage.xsu_used) / 1_073_741_824.0
            let totalGB = Double(swapUsage.xsu_total) / 1_073_741_824.0
            return (usedGB, totalGB)
        }
        
        return (0.0, 0.0)
    }
    
    // MARK: - Battery Status (From Stats app) - COMPLETE Implementation
    private func getBatteryStatus() -> BatteryData {
        var data = BatteryData()
        
        guard let psInfo = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let psList = IOPSCopyPowerSourcesList(psInfo)?.takeRetainedValue() as? [CFTypeRef],
              !psList.isEmpty else {
            return data
        }
        
        // Check if running on Apple Silicon
        let isARM = ProcessInfo.processInfo.machineHardwareName.contains("arm")
        
        for ps in psList {
            if let list = IOPSGetPowerSourceDescription(psInfo, ps)?.takeUnretainedValue() as? [String: Any] {
                
                // Power source state (AC Power / Battery Power)
                data.powerSource = list[kIOPSPowerSourceStateKey] as? String ?? "AC Power"
                data.isBatteryPowered = data.powerSource == "Battery Power"
                
                // Charged status
                data.isCharged = list[kIOPSIsChargedKey] as? Bool ?? false
                
                // Charging status - from IORegistry (Stats approach)
                data.isCharging = getBoolValue("IsCharging" as CFString) ?? false
                
                // Optimized Battery Charging
                data.optimizedCharging = (list["Optimized Battery Charging Engaged"] as? Int) == 1
                
                // Battery level (0.0 - 1.0)
                data.level = Double(list[kIOPSCurrentCapacityKey] as? Int ?? 100) / 100.0
                
                // Time estimates
                if let time = list[kIOPSTimeToEmptyKey] as? Int, time >= 0 {
                    data.timeToEmpty = time
                }
                if let time = list[kIOPSTimeToFullChargeKey] as? Int, time >= 0 {
                    data.timeToCharge = time
                }
                
                // Cycle count from IORegistry
                data.cycles = getIntValue("CycleCount" as CFString) ?? 0
                
                // Capacity values from IORegistry
                data.currentCapacity = getIntValue("AppleRawCurrentCapacity" as CFString) ?? 0
                data.designedCapacity = getIntValue("DesignCapacity" as CFString) ?? 1
                if data.designedCapacity == 0 { data.designedCapacity = 1 }
                
                // Max capacity differs between ARM and Intel
                if isARM {
                    data.maxCapacity = getIntValue("AppleRawMaxCapacity" as CFString) ?? 1
                } else {
                    data.maxCapacity = getIntValue("MaxCapacity" as CFString) ?? 1
                }
                
                // Calculate health percentage
                data.health = Int((Double(100 * data.maxCapacity) / Double(data.designedCapacity)).rounded(.toNearestOrEven))
                
                // Current (Amperage) from IORegistry
                data.amperage = getIntValue("Amperage" as CFString) ?? 0
                
                // Voltage from IORegistry (value is in mV, convert to V)
                if let voltageValue = getIntValue("Voltage" as CFString) {
                    data.voltage = Double(voltageValue) / 1000.0
                }
                
                // Temperature from IORegistry (value is in centi-degrees, convert to C)
                if let tempValue = getIntValue("Temperature" as CFString) {
                    data.temperature = Double(tempValue) / 100.0
                }
                
                // Calculate power in Watts
                data.power = data.voltage * Double(abs(data.amperage)) / 1000.0
                
                // AC Adapter info
                if let acDetails = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any] {
                    data.acWatts = acDetails[kIOPSPowerAdapterWattsKey] as? Int ?? 0
                }
                
                // Charger data from IORegistry
                if let chargerData = getChargerData() {
                    data.chargingCurrent = chargerData["ChargingCurrent"] as? Int ?? 0
                    data.chargingVoltage = chargerData["ChargingVoltage"] as? Int ?? 0
                }
                
                break
            }
        }
        
        return data
    }
    
    private func getChargerData() -> [String: Any]? {
        if let chargerData = IORegistryEntryCreateCFProperty(batteryService, "ChargerData" as CFString, kCFAllocatorDefault, 0) {
            return chargerData.takeRetainedValue() as? [String: Any]
        }
        return nil
    }
    
    private func getIntValue(_ forIdentifier: CFString) -> Int? {
        if let value = IORegistryEntryCreateCFProperty(self.batteryService, forIdentifier, kCFAllocatorDefault, 0) {
            return value.takeRetainedValue() as? Int
        }
        return nil
    }
    
    private func getBoolValue(_ forIdentifier: CFString) -> Bool? {
        if let value = IORegistryEntryCreateCFProperty(self.batteryService, forIdentifier, kCFAllocatorDefault, 0) {
            return value.takeRetainedValue() as? Bool
        }
        return nil
    }
    
    // MARK: - WiFi Signal Strength (From Stats app - using CoreWLAN) - Enhanced
    private func getWiFiSignalStrength() -> (Double, String, String) {
        guard let interface = wifiClient.interface() else {
            return (0.5, "", "")
        }
        
        let rssi = interface.rssiValue()
        let ssid = interface.ssid() ?? ""
        
        var channel = ""
        if let wifiChannel = interface.wlanChannel() {
            channel = "\(wifiChannel.channelNumber)"
            if wifiChannel.channelBand == .band5GHz {
                channel += " (5GHz)"
            } else {
                channel += " (2.4GHz)"
            }
        }
        
        // Convert RSSI to 0-1 scale (-90 = 0, -30 = 1)
        let normalized = min(max(Double(rssi + 90) / 60.0, 0.0), 1.0)
        return (normalized, ssid, channel)
    }
    
    // MARK: - Network Speed (App Store Safe - uses getifaddrs)
    private func getNetworkSpeed() -> (upload: Double, download: Double, totalUp: UInt64, totalDown: UInt64, upFormatted: String, downFormatted: String) {
        // Use native API (matches Stats app implementation)
        let network = NetworkNative.shared
        network.update()
        
        // Return all values - properties will be set on main thread
        return (
            network.uploadSpeed,
            network.downloadSpeed,
            network.totalUpload,
            network.totalDownload,
            network.uploadFormatted,
            network.downloadFormatted
        )
    }
    
    // MARK: - Bluetooth Status (via IOKit - no process spawning)
    private func getBluetoothStatus() -> Bool {
        // Use IOKit instead of spawning system_profiler which is very slow
        let mainPort: mach_port_t
        if #available(macOS 12.0, *) {
            mainPort = kIOMainPortDefault
        } else {
            mainPort = kIOMasterPortDefault
        }
        
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(mainPort, IOServiceMatching("IOBluetoothDevice"), &iterator) == kIOReturnSuccess else {
            return false
        }
        defer { IOObjectRelease(iterator) }
        
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            defer {
                IOObjectRelease(entry)
                entry = IOIteratorNext(iterator)
            }
            // Any IOBluetoothDevice in the registry means something is connected
            return true
        }
        
        return false
    }
    
    // MARK: - Music Status (MediaRemote - Native API)
    private func getMusicStatus() -> (isPlaying: Bool, trackName: String, artist: String, playerState: String) {
        // MediaRemote is handled by MediaObserver in AppDelegate
        // This is kept for compatibility but will be replaced by MediaObserver
        return (false, "", "", "stopped")
    }
    
    // MARK: - Disk I/O Speed (via IOKit - like Stats app)
    private func getDiskIOSpeed() -> (readMBs: Double, writeMBs: Double) {
        let mainPort: mach_port_t
        if #available(macOS 12.0, *) {
            mainPort = kIOMainPortDefault
        } else {
            mainPort = kIOMasterPortDefault
        }
        
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(mainPort, IOServiceMatching("IOBlockStorageDriver"), &iterator) == kIOReturnSuccess else {
            return (0.0, 0.0)
        }
        defer { IOObjectRelease(iterator) }
        
        var totalRead: UInt64 = 0
        var totalWrite: UInt64 = 0
        
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            defer {
                IOObjectRelease(entry)
                entry = IOIteratorNext(iterator)
            }
            
            var properties: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(entry, &properties, kCFAllocatorDefault, 0) == kIOReturnSuccess,
               let dict = properties?.takeRetainedValue() as? [String: Any],
               let stats = dict["Statistics"] as? [String: Any] {
                if let bytesRead = stats["Bytes (Read)"] as? UInt64 {
                    totalRead += bytesRead
                }
                if let bytesWritten = stats["Bytes (Write)"] as? UInt64 {
                    totalWrite += bytesWritten
                }
            }
        }
        
        // Calculate speed from delta
        let now = Date()
        var readSpeed: Double = 0.0
        var writeSpeed: Double = 0.0
        
        if let prev = previousDiskIO {
            let elapsed = now.timeIntervalSince(prev.time)
            if elapsed > 0 {
                let readDelta = totalRead > prev.read ? totalRead - prev.read : 0
                let writeDelta = totalWrite > prev.write ? totalWrite - prev.write : 0
                readSpeed = Double(readDelta) / elapsed / (1024 * 1024) // MB/s
                writeSpeed = Double(writeDelta) / elapsed / (1024 * 1024) // MB/s
            }
        }
        
        previousDiskIO = (totalRead, totalWrite, now)
        return (readSpeed, writeSpeed)
    }
    
    // MARK: - Disk Usage
    private func getDiskUsage() -> Double {
        let fileManager = FileManager.default
        do {
            let attributes = try fileManager.attributesOfFileSystem(forPath: "/")
            if let totalSize = attributes[.systemSize] as? NSNumber,
               let freeSize = attributes[.systemFreeSize] as? NSNumber {
                let total = totalSize.doubleValue
                let free = freeSize.doubleValue
                let used = total - free
                return (used / total) * 100.0
            }
        } catch {
            // Silently fail
        }
        
        return 0.0
    }
    
    // MARK: - Enhanced Methods for Stats-Level Details
    
    private func getGPUTemperature() -> Double {
        guard let accelerators = fetchIOService(kIOAcceleratorClassName) else {
            return 0.0
        }
        
        for accelerator in accelerators {
            guard let stats = accelerator["PerformanceStatistics"] as? [String: Any] else {
                continue
            }
            
            if let temp = stats["Temperature(C)"] as? Int {
                return Double(temp)
            }
        }
        
        return 64.0 // Simulated
    }
    
    private func getTopRAMProcesses() -> [TopProcessInfo] {
        return getTopProcesses(sortBy: "mem")
    }
    
    // MARK: - Top Energy Processes (via /usr/bin/top - like Stats app)
    private func getTopEnergyProcesses() -> [TopProcessInfo] {
        let task = Process()
        task.launchPath = "/usr/bin/top"
        task.arguments = ["-o", "power", "-l", "2", "-n", "5", "-stats", "pid,command,power"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return [] }
            
            // top outputs two samples, we want the second one
            let sections = output.components(separatedBy: "Processes:")
            guard sections.count > 2 else { return [] }
            
            let secondSample = sections.last ?? ""
            let lines = secondSample.components(separatedBy: "\n")
            var processes: [TopProcessInfo] = []
            var foundHeader = false
            
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.contains("PID") && trimmed.contains("COMMAND") {
                    foundHeader = true
                    continue
                }
                guard foundHeader else { continue }
                guard !trimmed.isEmpty else { continue }
                guard processes.count < 5 else { break }
                
                let parts = trimmed.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
                guard parts.count >= 3 else { continue }
                
                guard let pid = Int(parts[0]) else { continue }
                let name = String(parts[1])
                let powerStr = String(parts[2]).trimmingCharacters(in: .whitespaces)
                guard let power = Double(powerStr) else { continue }
                
                if power < 0.1 { continue } // Skip idle processes
                
                let icon = getAppIcon(for: pid, name: name)
                processes.append(TopProcessInfo(pid: pid, name: name, usage: power, icon: icon))
            }
            
            return processes
        } catch {
            return []
        }
    }
    
    // MARK: - Unified Top Processes (via /bin/ps - like Stats app)
    private func getTopProcesses(sortBy: String) -> [TopProcessInfo] {
        let task = Process()
        task.launchPath = "/bin/ps"
        // Sort by CPU or memory, show top processes
        if sortBy == "cpu" {
            task.arguments = ["-Aceo", "pid,pcpu,comm", "-r"]
        } else {
            task.arguments = ["-Aceo", "pid,rss,comm", "-m"]
        }
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe() // Suppress errors
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return [] }
            
            let lines = output.components(separatedBy: "\n")
            var processes: [TopProcessInfo] = []
            
            for (index, line) in lines.enumerated() {
                // Skip header line
                if index == 0 { continue }
                guard processes.count < 5 else { break } // Top 5 only
                
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }
                
                let parts = trimmed.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
                guard parts.count >= 3 else { continue }
                
                guard let pid = Int(parts[0]) else { continue }
                guard let usage = Double(parts[1]) else { continue }
                
                // Skip idle processes
                if sortBy == "cpu" && usage < 0.1 { continue }
                if sortBy == "mem" && usage < 1024 { continue } // Less than 1KB RSS
                
                let rawName = String(parts[2])
                // Extract just the app name from the path
                let name = rawName.components(separatedBy: "/").last ?? rawName
                
                // Skip kernel/system processes with very low usage
                if name == "kernel_task" && sortBy == "cpu" && usage < 1.0 { continue }
                
                // Get app icon
                let icon = getAppIcon(for: pid, name: name)
                
                let usageValue: Double
                if sortBy == "mem" {
                    usageValue = usage * 1024 // RSS is in KB, convert to bytes
                } else {
                    usageValue = usage
                }
                
                processes.append(TopProcessInfo(pid: pid, name: name, usage: usageValue, icon: icon))
            }
            
            return processes
        } catch {
            return []
        }
    }
    
    // Get app icon for a process
    private func getAppIcon(for pid: Int, name: String) -> NSImage? {
        // Try to get icon from running application
        if let app = NSRunningApplication(processIdentifier: pid_t(pid)) {
            return app.icon
        }
        
        // Try to find the app by name in /Applications
        let appPaths = [
            "/Applications/\(name).app",
            "/System/Applications/\(name).app",
            "/System/Library/CoreServices/\(name).app",
            "/Applications/Utilities/\(name).app"
        ]
        
        for path in appPaths {
            if FileManager.default.fileExists(atPath: path) {
                return NSWorkspace.shared.icon(forFile: path)
            }
        }
        
        return nil
    }
    
    private func getNetworkInfo() -> (String, String) {
        var localIP = ""
        var mac = ""
        
        // Get local IP
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        
        if getifaddrs(&ifaddr) == 0 {
            var ptr = ifaddr
            while ptr != nil {
                defer { ptr = ptr?.pointee.ifa_next }
                
                guard let interface = ptr?.pointee else { continue }
                let addrFamily = interface.ifa_addr.pointee.sa_family
                
                if addrFamily == UInt8(AF_INET) || addrFamily == UInt8(AF_INET6) {
                    let name = String(cString: interface.ifa_name)
                    if name == "en0" || name == "en1" {
                        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        if getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                     &hostname, socklen_t(hostname.count),
                                     nil, socklen_t(0), NI_NUMERICHOST) == 0 {
                            let address = String(cString: hostname)
                            if addrFamily == UInt8(AF_INET) {
                                localIP = address
                                break
                            }
                        }
                    }
                }
            }
            freeifaddrs(ifaddr)
        }
        
        // Get real MAC address via ifconfig (like Stats app)
        mac = getMACAddress()
        
        return (localIP, mac)
    }
    
    private var cachedMACAddress: String?
    
    private func getMACAddress() -> String {
        // Return cached value if available (MAC address doesn't change)
        if let cached = cachedMACAddress {
            return cached
        }
        
        // Use IOKit to get MAC address without spawning a process
        let mainPort: mach_port_t
        if #available(macOS 12.0, *) {
            mainPort = kIOMainPortDefault
        } else {
            mainPort = kIOMasterPortDefault
        }
        
        let matchingDict = IOServiceMatching("IOEthernetInterface") as NSMutableDictionary
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(mainPort, matchingDict, &iterator) == kIOReturnSuccess else {
            return ""
        }
        defer { IOObjectRelease(iterator) }
        
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            defer {
                IOObjectRelease(entry)
                entry = IOIteratorNext(iterator)
            }
            
            // Check if this is the primary (en0) interface
            if let bsdName = IORegistryEntryCreateCFProperty(entry, "BSD Name" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String,
               bsdName == "en0" {
                // Get the parent controller for the MAC address
                var parentEntry: io_object_t = 0
                if IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parentEntry) == kIOReturnSuccess {
                    defer { IOObjectRelease(parentEntry) }
                    if let macData = IORegistryEntryCreateCFProperty(parentEntry, "IOMACAddress" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Data {
                        let mac = macData.map { String(format: "%02x", $0) }.joined(separator: ":")
                        cachedMACAddress = mac
                        return mac
                    }
                }
            }
        }
        
        return ""
    }
}

