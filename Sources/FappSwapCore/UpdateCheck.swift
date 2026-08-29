import Foundation

/// A newer release on GitHub, reduced to what the installer needs.
public struct AvailableUpdate: Equatable {
    public let version: String
    public let zipURL: URL
    public let releasePageURL: URL?

    public init(version: String, zipURL: URL, releasePageURL: URL?) {
        self.version = version
        self.zipURL = zipURL
        self.releasePageURL = releasePageURL
    }
}

/// Decides whether the `releases/latest` JSON describes something newer than
/// the running version, and which asset to download. Pure logic — no network,
/// no AppKit — so the decision that triggers a bundle swap is fully tested.
///
/// Every failure mode returns nil rather than throwing: to the app, "the JSON
/// was garbage" and "there is no update" call for the same behaviour, silence.
public enum UpdateCheck {
    private struct Release: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: String
        }
        let tag_name: String
        let draft: Bool
        let prerelease: Bool
        let html_url: String?
        let assets: [Asset]
    }

    public static func availableUpdate(
        currentVersion: String, latestReleaseJSON: Data
    ) -> AvailableUpdate? {
        guard let release = try? JSONDecoder().decode(Release.self, from: latestReleaseJSON),
              !release.draft, !release.prerelease,
              isNewer(release.tag_name, than: currentVersion)
        else { return nil }

        let version = normalized(release.tag_name)
        // The release pipeline names the updater asset fappswap-<version>.zip;
        // anything else (the DMG, future extras) is not ours to install.
        guard let asset = release.assets.first(where: { $0.name == "fappswap-\(version).zip" }),
              let zipURL = URL(string: asset.browser_download_url),
              isTrustedUpdateURL(zipURL)
        else { return nil }

        return AvailableUpdate(
            version: version,
            zipURL: zipURL,
            releasePageURL: release.html_url.flatMap(URL.init(string:)))
    }

    /// Whether `url` is a URL the controller may download from and, on
    /// success, install: it downloads whatever this accepts, verifies its
    /// signature, and writes it over the running app bundle in /Applications.
    /// `browser_download_url` comes straight out of the JSON a compromised or
    /// spoofed feed controls, so it gets no benefit of the doubt — scheme
    /// must be exactly `https`, and the host must be `github.com` or a
    /// subdomain of it (release assets live under github.com; the API feed
    /// itself is served from api.github.com).
    ///
    /// A plain "hasSuffix github.com" check would also pass evilgithub.com
    /// and github.com.attacker.net, so the match has to be host-component
    /// equality or a dot-anchored suffix, never raw string containment.
    public static func isTrustedUpdateURL(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
        return host == "github.com" || host.hasSuffix(".github.com")
    }

    /// Numeric per-component comparison; a "v" prefix is tolerated because
    /// tag_name carries one. Unparseable versions are never newer — refusing
    /// an update is recoverable, installing garbage is not.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard let a = components(candidate), let b = components(current) else { return false }
        let count = max(a.count, b.count)
        for i in 0..<count {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private static func normalized(_ version: String) -> String {
        version.hasPrefix("v") ? String(version.dropFirst()) : version
    }

    private static func components(_ version: String) -> [Int]? {
        let parts = normalized(version).split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty else { return nil }
        var result: [Int] = []
        for part in parts {
            guard let n = Int(part), n >= 0 else { return nil }
            result.append(n)
        }
        return result
    }
}
