import Foundation
import SystemConfiguration

/// Native Network Monitor using getifaddrs (App Store Safe - No Shell Commands)
/// This reads network byte counts directly from the kernel, avoiding sandbox restrictions.
/// Implementation matches Stats app for reliability.
class NetworkNative {
    
    /// Shared instance for stateful tracking
    static let shared = NetworkNative()
    
    // Previous readings for speed calculation
    private var previousDownload: Int64 = 0
    private var previousUpload: Int64 = 0
    private var lastReadTime: Date?
    
    // Current calculated speeds (bytes per second)
    private(set) var downloadSpeed: Double = 0
    private(set) var uploadSpeed: Double = 0
    
    // Total bytes
    private(set) var totalDownload: UInt64 = 0
    private(set) var totalUpload: UInt64 = 0
    
    // Primary network interface (usually en0 for Wi-Fi)
    var primaryInterface: String {
        if let global = SCDynamicStoreCopyValue(nil, "State:/Network/Global/IPv4" as CFString),
           let dict = global as? [String: Any],
           let name = dict["PrimaryInterface"] as? String {
            return name
        }
        return "en0" // Fallback to en0
    }
    
    private init() {}
    
    /// Read current bandwidth bytes from the primary interface
    /// This matches the Stats app's readInterfaceBandwidth() implementation
    func readBandwidth() -> (download: Int64, upload: Int64) {
        var interfaceAddresses: UnsafeMutablePointer<ifaddrs>?
        var totalUpload: Int64 = 0
        var totalDownload: Int64 = 0
        
        guard getifaddrs(&interfaceAddresses) == 0 else {
            return (0, 0)
        }
        defer { freeifaddrs(interfaceAddresses) }
        
        let targetInterface = primaryInterface
        var pointer = interfaceAddresses
        
        while pointer != nil {
            defer { pointer = pointer?.pointee.ifa_next }
            guard let ptr = pointer else { break }
            
            let name = String(cString: ptr.pointee.ifa_name)
            
            // Only read from primary interface (like Stats app)
            if name == targetInterface {
                if let bytes = getBytesInfo(ptr) {
                    totalDownload += bytes.download
                    totalUpload += bytes.upload
                }
            }
        }
        
        return (totalDownload, totalUpload)
    }
    
    /// Get bytes info using the exact Stats app approach
    private func getBytesInfo(_ pointer: UnsafeMutablePointer<ifaddrs>) -> (upload: Int64, download: Int64)? {
        let addr = pointer.pointee.ifa_addr.pointee
        
        guard addr.sa_family == UInt8(AF_LINK) else {
            return nil
        }
        
        // Use unsafeBitCast exactly like Stats app does
        let data: UnsafeMutablePointer<if_data>? = unsafeBitCast(
            pointer.pointee.ifa_data,
            to: UnsafeMutablePointer<if_data>.self
        )
        
        return (
            upload: Int64(data?.pointee.ifi_obytes ?? 0),
            download: Int64(data?.pointee.ifi_ibytes ?? 0)
        )
    }
    
    /// Update network speed (call this periodically - every 1-2 seconds)
    /// This calculates the difference from last reading
    func update() {
        let (currentDownload, currentUpload) = readBandwidth()
        let now = Date()
        
        // Store totals
        totalDownload = UInt64(max(0, currentDownload))
        totalUpload = UInt64(max(0, currentUpload))
        
        // Calculate speed if we have previous readings
        if let lastTime = lastReadTime, previousDownload > 0 {
            let timeDiff = now.timeIntervalSince(lastTime)
            
            // Need at least 0.5 seconds between readings for accuracy
            if timeDiff >= 0.5 {
                let downloadDiff = currentDownload - previousDownload
                let uploadDiff = currentUpload - previousUpload
                
                // Convert to bytes per second
                // Prevent negative values (can happen on network reset)
                if downloadDiff >= 0 {
                    downloadSpeed = Double(downloadDiff) / timeDiff
                }
                if uploadDiff >= 0 {
                    uploadSpeed = Double(uploadDiff) / timeDiff
                }
                
                // Save for next calculation
                previousDownload = currentDownload
                previousUpload = currentUpload
                lastReadTime = now
            }
        } else {
            // First reading - just save baseline
            previousDownload = currentDownload
            previousUpload = currentUpload
            lastReadTime = now
            downloadSpeed = 0
            uploadSpeed = 0
        }
    }
    
    /// Format bytes per second to human-readable string
    /// Always shows KB/s or MB/s for consistent width (no B/s)
    static func formatSpeed(_ bytesPerSecond: Double) -> String {
        let kb = bytesPerSecond / 1024
        
        // Always show at least KB/s (never B/s) for consistent text width
        if kb < 1000 {
            // Format as XX.X KB/s (always 2 digits before decimal for consistency)
            return String(format: "%.1f KB", kb)
        }
        
        let mb = kb / 1024
        if mb < 1000 {
            return String(format: "%.1f MB", mb)
        }
        
        let gb = mb / 1024
        return String(format: "%.1f GB", gb)
    }
    
    /// Short format for menubar / floating bar — always ≤5 chars, always includes unit
    /// Examples: "0K", "3.4K", "156K", "2.4M", "156M"
    static func formatSpeedShort(_ bytesPerSecond: Double) -> String {
        let kb = bytesPerSecond / 1024
        if kb < 1   { return "0K" }
        if kb < 10  { return String(format: "%.1fK", kb) }   // "3.4K"
        if kb < 1000 { return String(format: "%.0fK", kb) }  // "156K"
        let mb = kb / 1024
        if mb < 10  { return String(format: "%.1fM", mb) }   // "2.4M"
        if mb < 1000 { return String(format: "%.0fM", mb) }  // "156M"
        let gb = mb / 1024
        return String(format: "%.1fG", gb)                   // "1.2G"
    }
    
    /// Get formatted download speed (for dropdown)
    var downloadFormatted: String {
        return NetworkNative.formatSpeed(downloadSpeed)
    }
    
    /// Get formatted upload speed (for dropdown)
    var uploadFormatted: String {
        return NetworkNative.formatSpeed(uploadSpeed)
    }
    
    /// Get short download speed (for menubar - compact)
    var downloadShort: String {
        return NetworkNative.formatSpeedShort(downloadSpeed)
    }
    
    /// Get short upload speed (for menubar - compact)  
    var uploadShort: String {
        return NetworkNative.formatSpeedShort(uploadSpeed)
    }
}
