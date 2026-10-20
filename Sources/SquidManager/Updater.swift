import AppKit
import CryptoKit
import Foundation
import SquidCore

// MARK: - Updater

/// Installs new releases from GitHub. The app is signed ad hoc, so there is no Sparkle feed:
/// the updater reads the latest release, downloads `SquidManager.zip`, checks its SHA-256 against
/// the digest GitHub reports, and swaps the new bundle in place of the running one.
/// Squid runs under launchd, so relaunching the app does not interrupt the proxy.
@MainActor
final class Updater: ObservableObject {

  // MARK: Lifecycle

  init() {
    installsAutomatically = UserDefaults.standard.object(forKey: Self.autoInstallKey) as? Bool ?? true
  }

  // MARK: Internal

  enum State: Equatable {
    case idle
    case checking
    case upToDate
    case available(GitHubRelease)
    case installing
    case failed(String)
  }

  struct Failure: LocalizedError {
    init(_ message: String) {
      errorDescription = message
    }

    var errorDescription: String?
  }

  static let author = "Tri Vo Khac"
  static let repository = "vokhactri/SquidManager"
  static let releasesURL = URL(string: "https://github.com/\(repository)/releases")!
  static let assetName = "SquidManager.zip"
  /// Passed to the relaunched app so it starts in the menu bar without opening a window.
  static let backgroundArgument = "--background"

  static var currentVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
  }

  @Published private(set) var state = State.idle

  /// Reports whether relaunching now would interrupt the user. Set by the app.
  var isBusy: () -> Bool = { false }

  @Published var installsAutomatically: Bool {
    didSet { UserDefaults.standard.set(installsAutomatically, forKey: Self.autoInstallKey) }
  }

  var available: GitHubRelease? {
    if case .available(let release) = state { return release }
    return nil
  }

  static func fetchLatest() async throws -> GitHubRelease {
    var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!)
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue("SquidManager/\(currentVersion)", forHTTPHeaderField: "User-Agent")
    let (data, response) = try await URLSession.shared.data(for: request)
    let code = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard code == 200 else {
      throw Failure(code == 404 ? "No releases published yet." : "GitHub answered HTTP \(code).")
    }
    return try JSONDecoder().decode(GitHubRelease.self, from: data)
  }

  /// Replaces the running app bundle with the one from `release` and returns its location.
  /// The running process keeps working from the old binary until it exits.
  static func install(_ release: GitHubRelease) async throws -> URL {
    let app = Bundle.main.bundleURL
    guard app.pathExtension == "app" else {
      throw Failure("Not running from an app bundle, so there is nothing to replace.")
    }
    guard let asset = release.asset(named: assetName) else {
      throw Failure("Release \(release.tagName) has no \(assetName).")
    }

    let (download, response) = try await URLSession.shared.download(from: asset.downloadURL)
    defer { try? FileManager.default.removeItem(at: download) }
    let code = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard code == 200 else { throw Failure("Downloading \(assetName) failed with HTTP \(code).") }

    if let expected = asset.sha256 {
      let data = try Data(contentsOf: download)
      let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
      guard actual == expected else { throw Failure("\(assetName) does not match the SHA-256 GitHub reports.") }
    }

    // Unpack on the same volume as the app so the swap below is a rename, not a copy.
    let staging = try FileManager.default.url(
      for: .itemReplacementDirectory,
      in: .userDomainMask,
      appropriateFor: app,
      create: true
    )
    defer { try? FileManager.default.removeItem(at: staging) }
    let unzip = await Shell.run("/usr/bin/ditto", ["-x", "-k", download.path, staging.path], timeout: 120)
    guard unzip.ok else { throw Failure("Could not unpack \(assetName): \(unzip.output)") }

    let new = staging.appendingPathComponent(app.lastPathComponent)
    guard Bundle(url: new)?.bundleIdentifier == Bundle.main.bundleIdentifier else {
      throw Failure("\(assetName) does not contain \(app.lastPathComponent).")
    }
    let verify = await Shell.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", new.path])
    guard verify.ok else { throw Failure("The downloaded app fails its signature check: \(verify.output)") }

    return try FileManager.default.replaceItemAt(app, withItemAt: new) ?? app
  }

  /// Checks GitHub ten seconds after launch and then every six hours.
  func start() {
    guard timer == nil else { return }
    // A minute is short enough to install soon after the user closes the last window,
    // and only every sixth hour reaches the network.
    timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
      Task { @MainActor in await self?.tick() }
    }
    Task {
      // Give the menu bar and squid's status a moment before going to the network.
      try? await Task.sleep(for: .seconds(10))
      await tick()
    }
  }

  /// Checks for a release the user asked about, so failures are shown.
  func check() async {
    guard state != .checking, state != .installing else { return }
    state = .checking
    do {
      let latest = try await Self.fetchLatest()
      state = latest.version > AppVersion(Self.currentVersion) ? .available(latest) : .upToDate
    } catch {
      state = .failed(error.localizedDescription)
    }
  }

  /// Installs `release`, then quits and opens the new copy.
  func install(_ release: GitHubRelease, relaunchInBackground: Bool = false) async {
    guard state != .installing else { return }
    state = .installing
    do {
      let app = try await Self.install(release)
      relaunch(app, inBackground: relaunchInBackground)
    } catch {
      state = .failed(error.localizedDescription)
    }
  }

  // MARK: Private

  private static let autoInstallKey = "installUpdatesAutomatically"

  private static let checkInterval: TimeInterval = 6 * 60 * 60

  private var timer: Timer?
  private var lastCheck = Date.distantPast

  private func tick() async {
    if available == nil, Date.now.timeIntervalSince(lastCheck) >= Self.checkInterval {
      lastCheck = .now
      // A failed scheduled check stays quiet. The next one may succeed.
      let previous = state
      await check()
      if case .failed = state { state = previous }
    }
    if let release = available, installsAutomatically, !isBusy() {
      await install(release, relaunchInBackground: true)
    }
  }

  private func relaunch(_ app: URL, inBackground: Bool) {
    // A detached shell waits for this process to exit, then opens the new bundle.
    // -n launches this exact copy even if another copy with the same bundle ID is running.
    let args = inBackground ? " --args \(Self.backgroundArgument)" : ""
    let script = "while /bin/kill -0 \(getpid()) 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open -n \"$0\"\(args)"
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/sh")
    p.arguments = ["-c", script, app.path]
    do {
      try p.run()
    } catch {
      state = .failed("Installed, but could not relaunch: \(error.localizedDescription). Quit and reopen the app.")
      return
    }
    NSApp.terminate(nil)
  }
}
