import Foundation
import Testing
@testable import SquidCore

@Test(arguments: [
  ("v1.2.0", "1.2"),
  ("0.3.0-4-gabc123", "0.3.0"),
  ("1.0", "v1.0.0"),
])
func versionsDifferingOnlyInPrefixSuffixOrTrailingZerosAreEqual(a: String, b: String) {
  #expect(AppVersion(a) == AppVersion(b))
}

@Test(arguments: [
  ("0.9.9", "0.10.0"),
  ("1.2", "1.2.1"),
  ("0.3.0-4-gabc123", "v0.3.1"),
  ("dev", "0.0.1"),
])
func laterReleaseComparesGreater(older: String, newer: String) {
  #expect(AppVersion(older) < AppVersion(newer))
}

@Test
func releaseJSONFromGitHubDecodes() throws {
  let json = """
    {
      "tag_name": "v0.2.0",
      "html_url": "https://github.com/vokhactri/SquidManager/releases/tag/v0.2.0",
      "draft": false,
      "assets": [{
        "name": "SquidManager.zip",
        "browser_download_url": "https://github.com/vokhactri/SquidManager/releases/download/v0.2.0/SquidManager.zip",
        "digest": "sha256:ABCDEF"
      }]
    }
    """
  let release = try JSONDecoder().decode(GitHubRelease.self, from: Data(json.utf8))
  #expect(release.version == AppVersion("0.2"))
  #expect(release.displayVersion == "0.2.0")
  let asset = try #require(release.asset(named: "SquidManager.zip"))
  #expect(asset.sha256 == "abcdef")
  #expect(release.asset(named: "other.zip") == nil)
}
