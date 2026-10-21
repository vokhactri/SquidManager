import Foundation
import ServiceManagement
import SquidCore

@MainActor
final class SquidController: ObservableObject {

  // MARK: Lifecycle

  init() {
    if
      let data = UserDefaults.standard.data(forKey: defaultsKey),
      let saved = try? JSONDecoder().decode(ProxySettings.self, from: data)
    {
      settings = saved
    } else if
      let old = UserDefaults.standard.persistentDomain(forName: "com.mac.adg.SquidMan"),
      let imported = ProxySettings.importingSquidMan(old)
    {
      settings = imported
    } else {
      settings = ProxySettings()
    }
    if let data = UserDefaults.standard.data(forKey: "appliedSettings") {
      appliedSettings = try? JSONDecoder().decode(ProxySettings.self, from: data)
    }
    appliedSquid = UserDefaults.standard.string(forKey: "appliedSquid")
    save()
    loadUsers()
    timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
      Task { @MainActor in await self?.refresh() }
    }
    Task { await refresh() }
  }

  // MARK: Internal

  struct Failure: LocalizedError {
    init(_ message: String) {
      errorDescription = message
    }

    var errorDescription: String?
  }

  @Published private(set) var status = LaunchAgent.Status(loaded: false)
  /// What the app is doing to squid right now. Nil when idle.
  @Published private(set) var activity: Activity?
  @Published var lastError: String?
  @Published private(set) var users = [String]()
  /// Settings squid was last started with, to tell the user a restart is pending.
  @Published private(set) var appliedSettings: ProxySettings?
  /// Real path of the squid binary that is running, such as `.../Cellar/squid/7.7/sbin/squid`.
  @Published private(set) var appliedSquid: String?
  /// Real path that `squidBinary` points at now. After `brew upgrade squid` it differs from `appliedSquid`.
  @Published private(set) var currentSquid: String?
  let paths = SquidPaths()

  @Published var settings: ProxySettings {
    didSet { save() }
  }

  var phase: Phase {
    Phase(activity: activity, status: status)
  }

  var needsRestart: Bool {
    status.running && appliedSettings != nil && appliedSettings != settings
  }

  /// The version squid would start with now, when it differs from the running one.
  var squidUpgrade: String? {
    guard status.running, let applied = appliedSquid, let current = currentSquid, applied != current else {
      return nil
    }
    return Self.homebrewVersion(current) ?? current
  }

  /// The squid the user chose in Settings, or the detected one when they haven't chosen.
  var squidBinary: String? {
    let custom = settings.squidPath.trimmingCharacters(in: .whitespaces)
    guard custom.isEmpty else { return FileManager.default.isExecutableFile(atPath: custom) ? custom : nil }
    return detectedSquid
  }

  /// squid in a usual install location, or on the login shell's PATH.
  var detectedSquid: String? {
    Self.installPaths.first { FileManager.default.isExecutableFile(atPath: $0) } ?? Self.shellSquid
  }

  /// `basic_ncsa_auth` sits in `libexec` next to the real (symlink-resolved) `sbin/squid`.
  var authHelper: String? {
    guard let squid = squidBinary else { return nil }
    let real = URL(fileURLWithPath: squid).resolvingSymlinksInPath()
    let helper = real.deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("libexec/basic_ncsa_auth").path
    return FileManager.default.isExecutableFile(atPath: helper) ? helper : nil
  }

  var opensAtLogin: Bool {
    get { SMAppService.mainApp.status == .enabled }
    set {
      do {
        if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
      } catch {
        lastError = "Could not change the login item: \(error.localizedDescription)"
      }
      objectWillChange.send()
    }
  }

  /// The visible hostname squid uses when the setting is empty.
  var defaultHostname: String {
    let host = ProcessInfo.processInfo.hostName.filter { !$0.isWhitespace }
    return host.isEmpty ? "localhost" : host
  }

  /// `/opt/homebrew/Cellar/squid/7.7/sbin/squid` gives `7.7`.
  static func homebrewVersion(_ path: String) -> String? {
    let parts = path.split(separator: "/")
    guard let i = parts.firstIndex(of: "Cellar"), i + 2 < parts.count else { return nil }
    return String(parts[i + 2])
  }

  func refresh() async {
    let r = await Shell.run("/bin/launchctl", ["print", "gui/\(uid)/\(LaunchAgent.label)"])
    let new = LaunchAgent.parseStatus(r.output, exitCode: r.status)
    if new != status { status = new }

    let current = squidBinary.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }
    if current != currentSquid { currentSquid = current }
    // Squid started by an older SquidManager build has no record, so ask the kernel which binary it runs.
    if appliedSquid == nil, let pid = status.pid, let running = Self.executablePath(pid: pid) {
      setAppliedSquid(running)
    }
  }

  func start() async {
    await refresh()
    guard !status.running else { return }
    await perform(.starting) { try await self.startSquid() }
  }

  func stop() async {
    await perform(.stopping) { try await self.stopSquid() }
  }

  func restart() async {
    await perform(.restarting) {
      try await self.stopSquid()
      try await self.startSquid()
    }
  }

  func rotateLogs() async {
    guard let squid = squidBinary else { return }
    await perform(.rotatingLogs) {
      let r = await Shell.run(squid, ["-k", "rotate", "-f", self.paths.config.path])
      if !r.ok { throw Failure(r.output) }
    }
  }

  func flushCache() async {
    let wasRunning = status.running
    await perform(.flushingCache(restartsSquid: wasRunning)) {
      if wasRunning { try await self.stopSquid() }
      try? FileManager.default.removeItem(at: self.paths.cache)
      if wasRunning { try await self.startSquid() }
    }
  }

  /// Writes squid.conf, validates it and returns its path.
  @discardableResult
  func writeConfig() throws -> URL {
    try createDirectories()
    let conf = try SquidConfig.build(settings, .init(
      paths: paths,
      hostname: defaultHostname,
      authHelper: authHelper
    ))
    try writePrivate(conf, to: paths.config)
    return paths.config
  }

  func logTail(lines: Int = 12) -> String {
    [paths.stderrLog, paths.cacheLog].map { url in
      let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
      return text.split(separator: "\n").suffix(lines / 2).joined(separator: "\n")
    }.filter { !$0.isEmpty }.joined(separator: "\n")
  }

  /// Adds or updates a user. basic_ncsa_auth rereads the file when it changes, so no restart is needed.
  func setUser(_ name: String, password: String) async throws {
    guard PasswdFile.isValidUser(name) else {
      throw Failure("User names cannot be empty or contain spaces or colons.")
    }
    guard !password.isEmpty else { throw Failure("Password cannot be empty.") }
    let r = await Shell.run("/usr/bin/openssl", ["passwd", "-apr1", "-stdin"], stdin: password)
    let hash = r.output.trimmingCharacters(in: .whitespacesAndNewlines)
    guard r.ok, hash.hasPrefix("$apr1$") else { throw Failure("Hashing failed: \(r.output)") }
    try updatePasswd { $0.set(user: name, hash: hash) }
  }

  func removeUser(_ name: String) throws {
    try updatePasswd { $0.remove(user: name) }
  }

  // MARK: Private

  /// Homebrew on Apple silicon and on Intel, a source build, and MacPorts.
  private static let installPaths = [
    "/opt/homebrew/sbin/squid",
    "/usr/local/sbin/squid",
    "/usr/local/squid/sbin/squid",
    "/opt/local/sbin/squid",
  ]

  /// An app opened from Finder gets a PATH without Homebrew or MacPorts, so ask the login shell.
  /// Looked up once, because it starts a shell.
  private static let shellSquid: String? = {
    let shell = Process()
    shell.executableURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh")
    shell.arguments = ["-lc", "command -v squid"]
    let output = Pipe()
    shell.standardOutput = output
    shell.standardError = FileHandle.nullDevice
    guard (try? shell.run()) != nil else { return nil }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    shell.waitUntilExit()
    let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    return FileManager.default.isExecutableFile(atPath: path) ? path : nil
  }()

  private let defaultsKey = "settings"
  private var timer: Timer?
  private let uid = getuid()

  private static func executablePath(pid: Int32) -> String? {
    var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
    guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
    return String(cChars: buffer)
  }

  private func save() {
    if let data = try? JSONEncoder().encode(settings) {
      UserDefaults.standard.set(data, forKey: defaultsKey)
    }
  }

  private func setAppliedSquid(_ path: String?) {
    appliedSquid = path
    UserDefaults.standard.set(path, forKey: "appliedSquid")
  }

  private func perform(_ next: Activity, _ work: @escaping () async throws -> Void) async {
    guard activity == nil else { return }
    activity = next
    lastError = nil
    do {
      try await work()
    } catch {
      lastError = error.localizedDescription
    }
    await refresh()
    activity = nil
  }

  private func startSquid() async throws {
    guard let squid = squidBinary else {
      throw Failure("Squid is not installed. Install it with:\n  brew install squid")
    }
    if settings.requireAuth, users.isEmpty {
      throw Failure("Authentication is on but there are no users. Add one under Settings > Access.")
    }
    try writeConfig()

    let parse = await Shell.run(squid, ["-k", "parse", "-f", paths.config.path])
    if !parse.ok {
      throw Failure("squid.conf is invalid:\n" + importantLines(parse.output))
    }

    let lsof = await Shell.run("/usr/sbin/lsof", ["-nP", "-iTCP:\(settings.port)", "-sTCP:LISTEN", "-Fc"])
    if lsof.ok, let owner = lsof.output.split(separator: "\n").first(where: { $0.hasPrefix("c") }) {
      throw Failure("Port \(settings.port) is already used by \"\(owner.dropFirst())\". "
        + "If that is the old SquidMan, stop it first or pick another port.")
    }

    if
      settings.cacheSizeMB > 0,
      !FileManager.default.fileExists(atPath: paths.cache.appendingPathComponent("00").path)
    {
      let z = await Shell.run(squid, ["-N", "-z", "-f", paths.config.path])
      if !z.ok { throw Failure("Could not create the cache directory:\n" + importantLines(z.output)) }
    }

    let plistURL = LaunchAgent.plistURL()
    try FileManager.default.createDirectory(
      at: plistURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try LaunchAgent.plistData(squid: squid, paths: paths, keepAwake: settings.keepAwake)
      .write(to: plistURL)

    // A job that is still unloading makes bootstrap fail with EIO, so retry briefly.
    var boot = ShellResult(status: -1, output: "")
    for _ in 0..<10 {
      boot = await Shell.run("/bin/launchctl", ["bootstrap", "gui/\(uid)", plistURL.path])
      if boot.ok { break }
      try await Task.sleep(for: .milliseconds(500))
    }
    if !boot.ok { throw Failure("launchctl bootstrap failed:\n\(boot.output)") }

    for _ in 0..<10 {
      try await Task.sleep(for: .milliseconds(300))
      await refresh()
      if status.running { break }
    }
    // Squid exits within a second or two when it cannot bind or read its files.
    try await Task.sleep(for: .seconds(1))
    await refresh()
    guard status.running else {
      throw Failure("Squid did not stay running. Last log lines:\n" + logTail())
    }
    appliedSettings = settings
    UserDefaults.standard.set(try? JSONEncoder().encode(settings), forKey: "appliedSettings")
    setAppliedSquid(URL(fileURLWithPath: squid).resolvingSymlinksInPath().path)
  }

  private func stopSquid() async throws {
    _ = await Shell.run("/bin/launchctl", ["bootout", "gui/\(uid)/\(LaunchAgent.label)"])
    try? FileManager.default.removeItem(at: LaunchAgent.plistURL())
    for _ in 0..<20 {
      await refresh()
      if !status.loaded { break }
      try await Task.sleep(for: .milliseconds(250))
    }
    try? FileManager.default.removeItem(at: paths.pidFile)
    appliedSettings = nil
    UserDefaults.standard.removeObject(forKey: "appliedSettings")
    setAppliedSquid(nil)
  }

  private func importantLines(_ output: String) -> String {
    let lines = output.split(separator: "\n")
    let bad = lines.filter { $0.contains("FATAL") || $0.contains("ERROR") || $0.contains("Bungled") }
    return (bad.isEmpty ? Array(lines.suffix(10)) : bad).joined(separator: "\n")
  }

  private func writePrivate(_ text: String, to url: URL) throws {
    try Data(text.utf8).write(to: url, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
  }

  /// Creates the data directories, plus a `.gitignore` for logs unless the user already has one.
  private func createDirectories() throws {
    let fm = FileManager.default
    for dir in [paths.root, paths.logs, paths.cache] {
      try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    if !fm.fileExists(atPath: paths.gitignore.path) {
      try Data(SquidPaths.gitignoreText.utf8).write(to: paths.gitignore)
    }
  }

  private func loadUsers() {
    users = PasswdFile((try? String(contentsOf: paths.passwd, encoding: .utf8)) ?? "").users
  }

  private func updatePasswd(_ change: (inout PasswdFile) -> Void) throws {
    try createDirectories()
    var file = PasswdFile((try? String(contentsOf: paths.passwd, encoding: .utf8)) ?? "")
    change(&file)
    try writePrivate(file.text, to: paths.passwd)
    users = file.users
  }

}
