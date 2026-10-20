import Foundation

// MARK: - AppVersion

/// The numeric part of a version string, which is all the updater compares.
/// `v1.2.0` and `1.2` are equal. A local build past a tag, such as `0.3.0-4-gabc123`, counts as `0.3.0`,
/// so it is not offered the release it was built from.
public struct AppVersion: Comparable, Sendable {

  // MARK: Lifecycle

  public init(_ string: String) {
    let digits = string.drop { $0 == "v" }.prefix { ($0.isASCII && $0.isNumber) || $0 == "." }
    let parts = digits.split(separator: ".").compactMap { Int($0) }
    components = Array(parts.reversed().drop { $0 == 0 }.reversed())
  }

  // MARK: Public

  public let components: [Int]

  public static func <(lhs: AppVersion, rhs: AppVersion) -> Bool {
    lhs.components.lexicographicallyPrecedes(rhs.components)
  }
}

// MARK: - GitHubRelease

/// The fields the updater reads from `GET /repos/{owner}/{repo}/releases/latest`.
public struct GitHubRelease: Decodable, Equatable, Sendable {

  // MARK: Public

  public struct Asset: Decodable, Equatable, Sendable {
    public var name: String
    public var downloadURL: URL
    /// `sha256:<hex>`. GitHub fills it in for assets uploaded since mid-2025.
    public var digest: String?

    /// The hex SHA-256 from `digest`, or nil when GitHub gave none or used another algorithm.
    public var sha256: String? {
      guard let digest, digest.hasPrefix("sha256:") else { return nil }
      return String(digest.dropFirst("sha256:".count)).lowercased()
    }

    enum CodingKeys: String, CodingKey {
      case name
      case downloadURL = "browser_download_url"
      case digest
    }

  }

  public var tagName: String
  public var pageURL: URL
  public var assets: [Asset]

  public var version: AppVersion {
    AppVersion(tagName)
  }

  /// The tag without its leading `v`, for display.
  public var displayVersion: String {
    tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
  }

  public func asset(named name: String) -> Asset? {
    assets.first { $0.name == name }
  }

  // MARK: Internal

  enum CodingKeys: String, CodingKey {
    case tagName = "tag_name"
    case pageURL = "html_url"
    case assets
  }

}
