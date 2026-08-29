import Foundation
import Testing
@testable import FappSwapCore

// The updater's decision logic: given the raw releases/latest JSON, is there
// something newer to install, and which asset is it? Everything network- and
// AppKit-shaped stays in the app target; this is the part that must never be
// wrong, because the installer swaps the app bundle on the strength of it.

// Real GitHub release-asset URLs, not https://example.com/... — since
// availableUpdate now rejects any asset URL that doesn't point at github.com,
// fixtures have to look like the real feed or they'd fail for the wrong reason.
private func releaseJSON(
    tag: String, assets: [String] = [], draft: Bool = false, prerelease: Bool = false
) -> Data {
    let assetJSON = assets.map {
        """
        {"name": "\($0)", "browser_download_url": "https://github.com/firatcansucu/fappswap/releases/download/\(tag)/\($0)"}
        """
    }.joined(separator: ",")
    return Data("""
        {"tag_name": "\(tag)", "draft": \(draft), "prerelease": \(prerelease),
         "html_url": "https://github.com/firatcansucu/fappswap/releases/tag/\(tag)", "assets": [\(assetJSON)]}
        """.utf8)
}

@Test func newerVersionWithMatchingAssetIsOffered() {
    let update = UpdateCheck.availableUpdate(
        currentVersion: "1.3",
        latestReleaseJSON: releaseJSON(tag: "v1.4", assets: ["fappswap-1.4.dmg", "fappswap-1.4.zip"]))
    #expect(update?.version == "1.4")
    #expect(update?.zipURL == URL(string: "https://github.com/firatcansucu/fappswap/releases/download/v1.4/fappswap-1.4.zip"))
}

@Test func sameVersionIsNotOffered() {
    #expect(UpdateCheck.availableUpdate(
        currentVersion: "1.4",
        latestReleaseJSON: releaseJSON(tag: "v1.4", assets: ["fappswap-1.4.zip"])) == nil)
}

@Test func olderVersionIsNotOffered() {
    // Rollbacks are done by hand, never pushed silently onto users.
    #expect(UpdateCheck.availableUpdate(
        currentVersion: "1.5",
        latestReleaseJSON: releaseJSON(tag: "v1.4", assets: ["fappswap-1.4.zip"])) == nil)
}

@Test func missingZipAssetIsNotOffered() {
    // A release without the updater zip (e.g. DMG-only) must not brick the flow.
    #expect(UpdateCheck.availableUpdate(
        currentVersion: "1.3",
        latestReleaseJSON: releaseJSON(tag: "v1.4", assets: ["fappswap-1.4.dmg"])) == nil)
}

@Test func draftAndPrereleaseAreNotOffered() {
    #expect(UpdateCheck.availableUpdate(
        currentVersion: "1.3",
        latestReleaseJSON: releaseJSON(tag: "v1.4", assets: ["fappswap-1.4.zip"], draft: true)) == nil)
    #expect(UpdateCheck.availableUpdate(
        currentVersion: "1.3",
        latestReleaseJSON: releaseJSON(tag: "v1.4", assets: ["fappswap-1.4.zip"], prerelease: true)) == nil)
}

@Test func malformedJSONIsNotOffered() {
    #expect(UpdateCheck.availableUpdate(
        currentVersion: "1.3", latestReleaseJSON: Data("not json".utf8)) == nil)
}

@Test func versionComparisonIsNumericPerComponent() {
    #expect(UpdateCheck.isNewer("1.10", than: "1.9"))       // not string comparison
    #expect(UpdateCheck.isNewer("2.0", than: "1.9"))
    #expect(UpdateCheck.isNewer("1.3.1", than: "1.3"))      // more components = patch release
    #expect(!UpdateCheck.isNewer("1.3", than: "1.3.1"))
    #expect(!UpdateCheck.isNewer("1.3", than: "1.3"))
    #expect(!UpdateCheck.isNewer("1.3.0", than: "1.3"))     // trailing zeros equal
    #expect(UpdateCheck.isNewer("v1.4", than: "1.3"))       // tag_name keeps its v
}

@Test func garbageVersionsAreNeverNewer() {
    // If either side doesn't parse, refuse the update rather than guessing.
    #expect(!UpdateCheck.isNewer("banana", than: "1.3"))
    #expect(!UpdateCheck.isNewer("1.4", than: "banana"))
}

// isTrustedUpdateURL is the gate between "whatever the JSON says" and "a URL
// the controller is allowed to download and swap the app bundle from."

@Test func trustedUpdateURLAcceptsGitHubReleaseHost() {
    #expect(UpdateCheck.isTrustedUpdateURL(URL(string:
        "https://github.com/firatcansucu/fappswap/releases/download/v1.4/fappswap-1.4.zip")!))
}

@Test func trustedUpdateURLAcceptsGitHubAPISubdomain() {
    #expect(UpdateCheck.isTrustedUpdateURL(URL(string:
        "https://api.github.com/repos/firatcansucu/fappswap/releases/latest")!))
}

@Test func trustedUpdateURLRejectsNonHTTPSSchemes() {
    #expect(!UpdateCheck.isTrustedUpdateURL(URL(string: "http://github.com/fappswap-1.4.zip")!))
    #expect(!UpdateCheck.isTrustedUpdateURL(URL(string: "file:///Applications/fappswap-1.4.zip")!))
}

@Test func trustedUpdateURLRejectsLookalikeHosts() {
    // "ends with github.com" is not the same test as "is github.com or a
    // subdomain of it" — these two must not slip through a naive suffix check.
    #expect(!UpdateCheck.isTrustedUpdateURL(URL(string: "https://evilgithub.com/fappswap-1.4.zip")!))
    #expect(!UpdateCheck.isTrustedUpdateURL(URL(string: "https://github.com.attacker.net/fappswap-1.4.zip")!))
}

@Test func trustedUpdateURLRejectsMissingHost() {
    var components = URLComponents()
    components.scheme = "https"
    components.path = "/fappswap-1.4.zip"
    #expect(!UpdateCheck.isTrustedUpdateURL(components.url!))
}

@Test func availableUpdateRejectsUntrustedAssetHost() {
    // Same rejection path as a missing asset or a draft release: nil, never a throw.
    let json = Data("""
        {"tag_name": "v1.4", "draft": false, "prerelease": false,
         "html_url": "https://github.com/firatcansucu/fappswap/releases/tag/v1.4",
         "assets": [{"name": "fappswap-1.4.zip",
                      "browser_download_url": "https://evilgithub.com/fappswap-1.4.zip"}]}
        """.utf8)
    #expect(UpdateCheck.availableUpdate(currentVersion: "1.3", latestReleaseJSON: json) == nil)
}
