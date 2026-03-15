import Foundation

enum BuildInfo {
    private static let fallbackVersion = "0.1.0"
    private static let fallbackBuild = "1"

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? fallbackVersion
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? fallbackBuild
    }

    static var displayVersion: String {
        "\(version) (\(build))"
    }
}
