import Foundation

// MARK: - InterfaceAddress

struct InterfaceAddress: Hashable {
  var interface: String
  var address: String
}

/// IPv4 addresses of this Mac other than loopback, so the user knows what to point clients at.
func localIPv4Addresses() -> [InterfaceAddress] {
  var result = [InterfaceAddress]()
  var head: UnsafeMutablePointer<ifaddrs>?
  guard getifaddrs(&head) == 0, let first = head else { return [] }
  defer { freeifaddrs(head) }

  for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
    let ifa = ptr.pointee
    guard
      let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
      (ifa.ifa_flags & UInt32(IFF_UP)) != 0,
      (ifa.ifa_flags & UInt32(IFF_LOOPBACK)) == 0
    else { continue }
    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
    guard
      getnameinfo(
        addr,
        socklen_t(addr.pointee.sa_len),
        &host,
        socklen_t(host.count),
        nil,
        0,
        NI_NUMERICHOST
      ) == 0
    else { continue }
    result.append(InterfaceAddress(
      interface: String(cString: ifa.ifa_name),
      address: String(cChars: host)
    ))
  }
  return result
}

extension String {
  /// Decodes a NUL-terminated C buffer filled in by calls such as `getnameinfo` or `proc_pidpath`.
  init(cChars buffer: [CChar]) {
    self.init(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
  }
}
