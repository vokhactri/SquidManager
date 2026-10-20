import Foundation

// MARK: - LaunchAgent

/// The launchd job that keeps squid alive whether or not the app is open.
public enum LaunchAgent {
  public struct Status: Equatable, Sendable {
    public init(loaded: Bool, pid: Int32? = nil, lastExitCode: Int? = nil) {
      self.loaded = loaded
      self.pid = pid
      self.lastExitCode = lastExitCode
    }

    public var loaded: Bool
    public var pid: Int32?
    public var lastExitCode: Int?

    public var running: Bool {
      pid != nil
    }
  }

  public static let label = "com.squidmanager.squid"

  public static func plistURL(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
    home.appendingPathComponent("Library/LaunchAgents/\(label).plist")
  }

  public static func plist(squid: String, paths: SquidPaths, keepAwake: Bool) -> [String: Any] {
    // -N keeps squid in the foreground so launchd supervises the real process.
    var args = [squid, "-N", "-f", paths.config.path]
    if keepAwake {
      // caffeinate holds a no-idle-sleep assertion for as long as squid runs.
      args = ["/usr/bin/caffeinate", "-i", "-s"] + args
    }
    return [
      "Label": label,
      "ProgramArguments": args,
      "RunAtLoad": true,
      // Restart after a crash, but stay down after a clean `squid -k shutdown`.
      "KeepAlive": ["SuccessfulExit": false],
      "ThrottleInterval": 10,
      "StandardOutPath": paths.stderrLog.path,
      "StandardErrorPath": paths.stderrLog.path,
    ]
  }

  public static func plistData(squid: String, paths: SquidPaths, keepAwake: Bool) throws -> Data {
    try PropertyListSerialization.data(
      fromPropertyList: plist(squid: squid, paths: paths, keepAwake: keepAwake),
      format: .xml,
      options: 0
    )
  }

  /// Parses `launchctl print gui/<uid>/<label>` output.
  public static func parseStatus(_ output: String, exitCode: Int32) -> Status {
    guard exitCode == 0 else { return Status(loaded: false, pid: nil, lastExitCode: nil) }
    var pid: Int32?
    var lastExit: Int?
    for line in output.split(separator: "\n") {
      let t = line.trimmingCharacters(in: .whitespaces)
      if t.hasPrefix("pid = ") {
        pid = Int32(t.dropFirst(6))
      } else if t.hasPrefix("last exit code = ") {
        lastExit = Int(t.dropFirst(17).prefix { $0 == "-" || $0.isNumber })
      }
    }
    return Status(loaded: true, pid: pid, lastExitCode: lastExit)
  }
}

// MARK: - PasswdFile

/// An htpasswd-style file read by squid's `basic_ncsa_auth` helper.
public struct PasswdFile: Equatable, Sendable {

  // MARK: Lifecycle

  public init(_ text: String = "") {
    for line in text.split(separator: "\n") {
      let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
      if parts.count == 2, !parts[0].isEmpty { entries.append((parts[0], parts[1])) }
    }
  }

  // MARK: Public

  public private(set) var entries = [(user: String, hash: String)]()

  public var users: [String] {
    entries.map(\.user)
  }

  public var text: String {
    entries.map { "\($0.user):\($0.hash)\n" }.joined()
  }

  public static func isValidUser(_ name: String) -> Bool {
    !name.isEmpty && !name.contains(":") && !name.contains(where: \.isWhitespace)
  }

  public static func ==(a: PasswdFile, b: PasswdFile) -> Bool {
    a.text == b.text
  }

  public mutating func set(user: String, hash: String) {
    if let i = entries.firstIndex(where: { $0.user == user }) {
      entries[i].hash = hash
    } else {
      entries.append((user, hash))
    }
  }

  public mutating func remove(user: String) {
    entries.removeAll { $0.user == user }
  }

}
