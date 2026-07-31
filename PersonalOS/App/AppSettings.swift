import Foundation

/// UserDefaults keys + typed accessors (used outside SwiftUI views;
/// views bind with @AppStorage directly using the same keys).
enum AppSettings {
    static let mcpEnabledKey = "mcpEnabled"
    static let mcpPortKey = "mcpPort"

    static var mcpEnabled: Bool {
        UserDefaults.standard.bool(forKey: mcpEnabledKey)
    }

    static var mcpPort: Int {
        let value = UserDefaults.standard.integer(forKey: mcpPortKey)
        return value == 0 ? 4141 : value
    }
}
