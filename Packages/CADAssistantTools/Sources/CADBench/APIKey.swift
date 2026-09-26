import Foundation

public enum APIKey {
    static let appSuite = "com.example.3dmodeller"
    static let appDefaultsKey = "llmApiKey"

    public static func resolve(
        environment: [String: String], useAppKey: Bool, savedInApp: () -> String?
    ) throws(UsageError) -> String {
        if let key = environment["ANTHROPIC_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            return key
        }
        guard useAppKey else {
            throw UsageError("Set ANTHROPIC_API_KEY, or pass --app-key to use the key saved in the app's settings.")
        }
        guard let key = savedInApp()?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            throw UsageError("The app has no saved API key; add one in the app's Settings or set ANTHROPIC_API_KEY.")
        }
        return key
    }

    /// The key the app stores in its settings. The app is sandboxed, so its preferences usually live in its container.
    public static func savedInApp() -> String? {
        if let key = UserDefaults(suiteName: appSuite)?.string(forKey: appDefaultsKey), !key.isEmpty { return key }
        let container = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Containers/\(appSuite)/Data/Library/Preferences/\(appSuite).plist")
        guard let data = try? Data(contentsOf: container),
            let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return values[appDefaultsKey] as? String
    }
}
