import Foundation
import Testing
@testable import SquidCore

private let paths = SquidPaths(home: URL(fileURLWithPath: "/Users/test"), environment: [:])
private let ctx = SquidConfig.Context(paths: paths, hostname: "mac", authHelper: "/opt/squid/libexec/basic_ncsa_auth")

private func lines(_ conf: String) -> [String] {
  conf.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
}

@Test
func defaultSettingsFillEveryPlaceholder() throws {
  let conf = try SquidConfig.build(ProxySettings(), ctx)
  #expect(conf.range(of: #"%[A-Z_]+%"#, options: .regularExpression) == nil)
  let l = lines(conf)
  #expect(l.contains("http_port 3128"))
  #expect(l.contains("visible_hostname mac"))
  #expect(l.contains("cache deny all"))
  #expect(l.contains("forwarded_for delete"))
  #expect(l.contains("request_header_access Cache-Control deny all"))
  #expect(l.contains("access_log stdio:/Users/test/.config/squidmanager/logs/access.log"))
  #expect(!l.contains { $0.hasPrefix("auth_param") || $0.hasPrefix("cache_peer") })
}

@Test(arguments: [
  ([:], "/Users/test/.config/squidmanager"),
  (["XDG_CONFIG_HOME": "/xdg"], "/xdg/squidmanager"),
  (["XDG_CONFIG_HOME": "relative"], "/Users/test/.config/squidmanager"),
])
func configRootFollowsXDGConfigHome(environment: [String: String], expected: String) {
  let p = SquidPaths(home: URL(fileURLWithPath: "/Users/test"), environment: environment)
  #expect(p.root.path == expected)
  #expect(p.logs.path == expected + "/logs")
}

@Test
func clientsAndAuthAreAllowedBeforeDenyAll() throws {
  var s = ProxySettings()
  s.allowedClients = ["100.64.0.0/10", " 192.168.1.5 "]
  s.requireAuth = true
  s.listenAddress = "100.100.1.1"
  let l = lines(try SquidConfig.build(s, ctx))

  #expect(l.contains("http_port 100.100.1.1:3128"))
  #expect(l.contains("acl allowed_clients src 100.64.0.0/10"))
  #expect(l.contains("acl allowed_clients src 192.168.1.5"))
  #expect(l.contains("auth_param basic program /opt/squid/libexec/basic_ncsa_auth /Users/test/.config/squidmanager/passwd"))
  let clients = try #require(l.firstIndex(of: "http_access allow allowed_clients"))
  let auth = try #require(l.firstIndex(of: "http_access allow authenticated"))
  let deny = try #require(l.firstIndex(of: "http_access deny all"))
  #expect(clients < auth && auth < deny)
}

@Test
func authWithoutHelperFails() {
  var s = ProxySettings()
  s.requireAuth = true
  let noHelper = SquidConfig.Context(paths: paths, hostname: "mac", authHelper: nil)
  #expect(throws: SquidConfig.BuildError.missingAuthHelper) { try SquidConfig.build(s, noHelper) }
}

@Test
func entriesWithSpacesAreRejected() {
  var s = ProxySettings()
  s.allowedClients = ["10.0.0.1 http_access allow all"]
  #expect(throws: SquidConfig.BuildError.self) { try SquidConfig.build(s, ctx) }
}

@Test
func parentSplitsDirectHostsIntoAddressesAndDomains() throws {
  var s = ProxySettings()
  s.useParent = true
  s.parentHost = "upstream.example"
  s.parentPort = 8080
  s.parentUser = "bob"
  s.parentPassword = "secret"
  s.directHosts = [".corp.example", "10.0.0.0/8", "cafe.be"]
  let l = lines(try SquidConfig.build(s, ctx))

  #expect(l.contains("cache_peer upstream.example parent 8080 0 no-query no-digest default login=bob:secret"))
  #expect(l.contains("acl direct_ips dst 10.0.0.0/8"))
  #expect(l.contains("acl direct_domains dstdomain .corp.example"))
  #expect(l.contains("acl direct_domains dstdomain cafe.be"))
  let always = try #require(l.firstIndex(of: "always_direct allow direct_domains"))
  let never = try #require(l.firstIndex(of: "never_direct allow all"))
  #expect(always < never)
}

@Test
func diskCacheUsesCacheDir() throws {
  var s = ProxySettings()
  s.cacheSizeMB = 500
  let l = lines(try SquidConfig.build(s, ctx))
  #expect(l.contains("cache_dir ufs /Users/test/Library/Caches/SquidManager 500 16 256"))
  #expect(!l.contains("cache deny all"))
}

@Test(arguments: [
  ("10.0.0.0/255.255.0.0", "10.0.0.0/16"),
  ("100.112.190.51/255.255.255.255", "100.112.190.51/32"),
  ("192.168.1.0/24", "192.168.1.0/24"),
  ("10.0.0.0/255.0.255.0", "10.0.0.0/255.0.255.0"),
  ("example.com", "example.com"),
])
func netmaskToCIDR(input: String, expected: String) {
  #expect(ProxySettings.netmaskToCIDR(input) == expected)
}

@Test
func importsOriginalSquidManPreferences() throws {
  let prefs: [String: Any] = [
    "Port": 1080,
    "default": [
      "Port": 1080,
      "Clients": ["100.112.190.51/255.255.255.255"],
      "No Proxy": [".local"],
      "Parent Name": "",
      "Parent Port": "",
      "Use Parent": false,
      "Visible Hostname": "",
    ] as [String: Any],
  ]
  let s = try #require(ProxySettings.importingSquidMan(prefs))
  #expect(s.port == 1080)
  #expect(s.allowedClients == ["100.112.190.51/32"])
  #expect(s.directHosts == [".local"])
  #expect(s.parentPort == 3128)
  #expect(ProxySettings.importingSquidMan([:]) == nil)
}

@Test
func settingsMissingNewFieldsStillDecode() throws {
  let json = #"{"port": 9999, "allowedClients": ["1.2.3.4"]}"#
  let s = try JSONDecoder().decode(ProxySettings.self, from: Data(json.utf8))
  #expect(s.port == 9999)
  #expect(s.allowedClients == ["1.2.3.4"])
  #expect(s.anonymize == true)
  #expect(s.template == SquidConfig.defaultTemplate)
}

@Test
func launchAgentWrapsSquidInCaffeinate() {
  let awake = LaunchAgent.plist(squid: "/opt/homebrew/sbin/squid", paths: paths, keepAwake: true)
  #expect(awake["ProgramArguments"] as? [String] == [
    "/usr/bin/caffeinate",
    "-i",
    "-s",
    "/opt/homebrew/sbin/squid",
    "-N",
    "-f",
    "/Users/test/.config/squidmanager/squid.conf",
  ])
  let plain = LaunchAgent.plist(squid: "/s", paths: paths, keepAwake: false)
  #expect((plain["ProgramArguments"] as? [String])?.first == "/s")
}

@Test
func parsesLaunchctlPrint() {
  let running = """
    gui/501/com.squidmanager.squid = {
    \tstate = running
    \tpid = 4242
    \tlast exit code = (never exited)
    }
    """
  #expect(LaunchAgent.parseStatus(running, exitCode: 0) == .init(loaded: true, pid: 4242))

  let crashed = "\tstate = spawn scheduled\n\tlast exit code = 1: Operation not permitted\n"
  #expect(LaunchAgent.parseStatus(crashed, exitCode: 0) == .init(loaded: true, pid: nil, lastExitCode: 1))
  #expect(LaunchAgent.parseStatus("Could not find service", exitCode: 113) == .init(loaded: false))
}

@Test
func passwdFileReplacesAndRemovesUsers() {
  var f = PasswdFile("alice:$apr1$a\nbob:$apr1$b\n")
  f.set(user: "alice", hash: "$apr1$new")
  f.set(user: "carol", hash: "$apr1$c")
  f.remove(user: "bob")
  #expect(f.text == "alice:$apr1$new\ncarol:$apr1$c\n")
  #expect(!PasswdFile.isValidUser("a:b"))
  #expect(!PasswdFile.isValidUser("a b"))
}

/// Runs the real squid parser over generated configs when squid is installed.
@Test(.enabled(if: FileManager.default.isExecutableFile(atPath: "/opt/homebrew/sbin/squid")))
func squidAcceptsGeneratedConfig() throws {
  let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  let p = SquidPaths(home: tmp, environment: [:])
  for dir in [p.root, p.logs, p.cache] {
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  }
  defer { try? FileManager.default.removeItem(at: tmp) }

  var s = ProxySettings()
  s.allowedClients = ["100.64.0.0/10"]
  s.requireAuth = true
  s.useParent = true
  s.parentHost = "127.0.0.1"
  s.directHosts = [".example.com", "10.0.0.0/8"]
  s.cacheSizeMB = 100
  s.dnsServers = "1.1.1.1, 8.8.8.8"
  let conf = try SquidConfig.build(s, .init(
    paths: p,
    hostname: "mac",
    authHelper: "/opt/homebrew/opt/squid/libexec/basic_ncsa_auth"
  ))
  try conf.write(to: p.config, atomically: true, encoding: .utf8)

  let proc = Process()
  proc.executableURL = URL(fileURLWithPath: "/opt/homebrew/sbin/squid")
  proc.arguments = ["-k", "parse", "-f", p.config.path]
  let pipe = Pipe()
  proc.standardOutput = pipe
  proc.standardError = pipe
  try proc.run()
  let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
  proc.waitUntilExit()

  #expect(proc.terminationStatus == 0, "\(output)")
  // Squid warns about `via off` on purpose: hiding the proxy is the point of the anonymize option.
  let complaints = output.split(separator: "\n").filter {
    ($0.contains("WARNING") || $0.contains("ERROR") || $0.contains("FATAL"))
      && !$0.contains("HTTP requires the use of Via")
  }
  #expect(complaints.isEmpty, "\(complaints.joined(separator: "\n"))")
}
