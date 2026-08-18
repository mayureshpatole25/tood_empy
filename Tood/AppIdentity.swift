import Foundation

/// Identity values that keep the personal edition independent from Renee's
/// Tood installation, local data, Keychain records, and update services.
enum AppIdentity {
    static let displayName = "Empy Tood"
    static let storageDirectory = "com.empy.EmpyTood"
    static let keychainService = "com.empy.EmpyTood"
}
