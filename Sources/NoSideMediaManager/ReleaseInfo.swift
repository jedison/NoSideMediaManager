import Foundation

/// Build-local release information generated automatically during a build.
/// This follows the Upgrade and Walletize `*BuildInfo.plist` pattern.
public enum MMMBuildInfo {
    public static func display(in bundle: Bundle = .main) -> String {
        display(
            info: bundle.infoDictionary,
            buildInfo: bundle.url(forResource: "MMMBuildInfo", withExtension: "plist").flatMap { NSDictionary(contentsOf: $0) as? [String: Any] }
        )
    }

    public static func display(for executableURL: URL = URL(fileURLWithPath: CommandLine.arguments[0])) -> String {
        let contents = executableURL.deletingLastPathComponent().deletingLastPathComponent()
        let info = NSDictionary(contentsOf: contents.appendingPathComponent("Info.plist")) as? [String: Any]
        let buildInfo = NSDictionary(contentsOf: contents.appendingPathComponent("Resources/MMMBuildInfo.plist")) as? [String: Any]
        return display(info: info, buildInfo: buildInfo)
    }

    public static func display(info: [String: Any]?, buildInfo: [String: Any]?) -> String {
        let version = buildInfo?["version"] as? String ?? info?["CFBundleShortVersionString"] as? String ?? "—"
        let bundleBuild = buildInfo?["bundleBuild"] as? String ?? info?["CFBundleVersion"] as? String ?? "—"
        guard let sequence = buildInfo?["sequence"] as? String,
              let timestamp = buildInfo?["timestamp"] as? String else {
            return "v\(version) (\(bundleBuild))"
        }
        if bundleBuild == sequence {
            return "v\(version) (build \(sequence)) • \(timestamp)"
        }
        return "v\(version) (\(bundleBuild)) • build \(sequence) • \(timestamp)"
    }
}
