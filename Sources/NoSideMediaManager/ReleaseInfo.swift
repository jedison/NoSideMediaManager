import Foundation

/// Resolves the release identity from the enclosing microMM app bundle.
/// The app's Info.plist is stamped from the shared release registry during a
/// distributable build, making the bundled CLI and macOS UI report one value.
public enum MMMReleaseInfo {
    public static func display(for executableURL: URL = URL(fileURLWithPath: CommandLine.arguments[0])) -> String {
        let info = executableURL
            .deletingLastPathComponent() // Contents/MacOS
            .deletingLastPathComponent() // Contents
            .appendingPathComponent("Info.plist")
        guard let values = NSDictionary(contentsOf: info) as? [String: Any],
              let version = values["CFBundleShortVersionString"] as? String,
              let build = values["CFBundleVersion"] as? String else {
            return sourceRegistryDisplay() ?? "development"
        }
        return "\(version) (build \(build))"
    }

    /// `swift run` is not inside an app bundle. During local development it
    /// therefore reads the same checked-in registry used by iOS and packaging.
    private static func sourceRegistryDisplay() -> String? {
        var directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        while true {
            let registry = directory.appendingPathComponent("release/NoSideMediaManagerRelease.xcconfig")
            if let text = try? String(contentsOf: registry),
               let version = setting("MMM_RELEASE_VERSION", in: text),
               let build = setting("MMM_RELEASE_BUILD", in: text) {
                return "\(version) (build \(build))"
            }
            let parent = directory.deletingLastPathComponent()
            guard parent.path != directory.path else { return nil }
            directory = parent
        }
    }

    private static func setting(_ key: String, in text: String) -> String? {
        text.split(whereSeparator: \.isNewline).first { $0.hasPrefix("\(key) = ") }
            .map { $0.replacingOccurrences(of: "\(key) = ", with: "").trimmingCharacters(in: .whitespaces) }
    }
}
