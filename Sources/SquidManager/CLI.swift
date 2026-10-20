// The commands print their results to stdout. That is their output, not logging.
// swiftlint:disable no_direct_standard_out_logs

import Foundation
import SquidCore

// MARK: - Entry

/// Lets the app double as a command-line tool, handy when managing the proxy Mac over SSH:
///   SquidManager.app/Contents/MacOS/SquidManager status
@main
enum Entry {
  static func main() {
    guard let command = CommandLine.arguments.dropFirst().first, CLI.commands[command] != nil else {
      SquidManagerApp.main()
      return
    }
    Task { @MainActor in exit(await CLI.run(command)) }
    dispatchMain()
  }
}

// MARK: - CLI

@MainActor
enum CLI {

  // MARK: Internal

  static let commands: [String: String] = [
    "status": "Show whether squid is running and where clients should connect",
    "start": "Write squid.conf and start squid under launchd",
    "stop": "Stop squid and remove the launchd agent",
    "restart": "Stop, then start with the current settings",
    "rotate": "Rotate squid's log files",
    "update": "Install the latest release from GitHub; reopen the app afterward",
    "help": "Show this help",
  ]

  static func run(_ command: String) async -> Int32 {
    if command == "update" { return await update() }
    let squid = SquidController()
    await squid.refresh()
    switch command {
    case "start": await squid.start()

    case "stop": await squid.stop()

    case "restart": await squid.restart()

    case "rotate": await squid.rotateLogs()

    case "help":
      print("Usage: SquidManager <command>\n")
      for (name, text) in commands.sorted(by: { $0.key < $1.key }) {
        print("  \(name.padding(toLength: 9, withPad: " ", startingAt: 0))\(text)")
      }
      return 0

    default: break
    }

    if let error = squid.lastError {
      FileHandle.standardError.write(Data("error: \(error)\n".utf8))
      return 1
    }
    let s = squid.settings
    if squid.status.running {
      print("running  pid \(squid.status.pid ?? 0)  port \(s.port)")
      for a in localIPv4Addresses() { print("  \(a.address):\(s.port)  (\(a.interface))") }
      if squid.needsRestart { print("settings changed since start; run `restart` to apply") }
      if let version = squid.squidUpgrade { print("squid \(version) is installed; run `restart` to use it") }
    } else {
      print("stopped")
    }
    return 0
  }

  // MARK: Private

  private static func update() async -> Int32 {
    do {
      let release = try await Updater.fetchLatest()
      guard release.version > AppVersion(Updater.currentVersion) else {
        print("SquidManager \(Updater.currentVersion) is up to date (latest release \(release.tagName))")
        return 0
      }
      let app = try await Updater.install(release)
      print("Installed SquidManager \(release.displayVersion) at \(app.path)")
      print("A running copy of the app keeps the old version until it is reopened.")
      return 0
    } catch {
      FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
      return 1
    }
  }
}
