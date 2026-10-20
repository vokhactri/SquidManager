import Foundation

// MARK: - ProxySettings

public struct ProxySettings: Codable, Equatable, Sendable {

  // MARK: Lifecycle

  public init() { }

  /// Decode key by key so settings saved by an older build still load after new fields appear.
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let d = ProxySettings()
    func get<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
      (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
    }
    port = get(.port, d.port)
    listenAddress = get(.listenAddress, d.listenAddress)
    visibleHostname = get(.visibleHostname, d.visibleHostname)
    allowedClients = get(.allowedClients, d.allowedClients)
    requireAuth = get(.requireAuth, d.requireAuth)
    anonymize = get(.anonymize, d.anonymize)
    logRequests = get(.logRequests, d.logRequests)
    keepAwake = get(.keepAwake, d.keepAwake)
    cacheSizeMB = get(.cacheSizeMB, d.cacheSizeMB)
    maxObjectSize = get(.maxObjectSize, d.maxObjectSize)
    memoryCacheSize = get(.memoryCacheSize, d.memoryCacheSize)
    memoryMaxObjectSize = get(.memoryMaxObjectSize, d.memoryMaxObjectSize)
    useParent = get(.useParent, d.useParent)
    parentHost = get(.parentHost, d.parentHost)
    parentPort = get(.parentPort, d.parentPort)
    parentUser = get(.parentUser, d.parentUser)
    parentPassword = get(.parentPassword, d.parentPassword)
    directHosts = get(.directHosts, d.directHosts)
    dnsServers = get(.dnsServers, d.dnsServers)
    squidPath = get(.squidPath, d.squidPath)
    template = get(.template, d.template)
  }

  // MARK: Public

  public var port = 3128
  /// Empty means listen on every interface.
  public var listenAddress = ""
  public var visibleHostname = ""

  public var allowedClients = [String]()
  public var requireAuth = false
  public var anonymize = true
  public var logRequests = true
  public var keepAwake = true

  public var cacheSizeMB = 0
  public var maxObjectSize = "4 MB"
  public var memoryCacheSize = "64 MB"
  public var memoryMaxObjectSize = "512 KB"

  public var useParent = false
  public var parentHost = ""
  public var parentPort = 3128
  public var parentUser = ""
  public var parentPassword = ""
  public var directHosts = [String]()

  public var dnsServers = ""
  public var squidPath = ""
  public var template = SquidConfig.defaultTemplate

}

extension ProxySettings {
  /// Builds settings from the preferences of the original SquidMan (domain `com.mac.adg.SquidMan`).
  public static func importingSquidMan(_ prefs: [String: Any]) -> ProxySettings? {
    let values = (prefs["default"] as? [String: Any]) ?? prefs
    guard values["Port"] != nil || values["Clients"] != nil else { return nil }

    var s = ProxySettings()
    if let port = values["Port"] as? Int ?? Int(values["Port"] as? String ?? "") {
      s.port = port
    }
    s.allowedClients = (values["Clients"] as? [String] ?? []).map(netmaskToCIDR)
    s.directHosts = values["No Proxy"] as? [String] ?? []
    s.visibleHostname = values["Visible Hostname"] as? String ?? ""
    s.useParent = values["Use Parent"] as? Bool ?? false
    s.parentHost = values["Parent Name"] as? String ?? ""
    if let p = values["Parent Port"] as? Int ?? Int(values["Parent Port"] as? String ?? "") {
      s.parentPort = p
    }
    s.parentUser = values["User Name"] as? String ?? ""
    return s
  }

  /// Turns `10.0.0.0/255.255.0.0` into `10.0.0.0/16`. Other input comes back unchanged.
  public static func netmaskToCIDR(_ entry: String) -> String {
    let parts = entry.split(separator: "/", maxSplits: 1).map(String.init)
    guard parts.count == 2 else { return entry }
    let octets = parts[1].split(separator: ".").compactMap { UInt8($0) }
    guard octets.count == 4 else { return entry }
    let mask = octets.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
    let bits = mask.nonzeroBitCount
    // Reject non-contiguous masks such as 255.0.255.0.
    guard bits == 0 || mask == UInt32.max << (32 - bits) else { return entry }
    return "\(parts[0])/\(bits)"
  }
}
