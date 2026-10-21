import SwiftUI

struct StatusView: View {

  // MARK: Internal

  @EnvironmentObject var squid: SquidController
  @EnvironmentObject var updater: Updater

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(spacing: 12) {
        Circle()
          .fill(statusColor)
          .frame(width: 14, height: 14)
        VStack(alignment: .leading, spacing: 2) {
          Text(statusTitle)
            .font(.title2.weight(.semibold))
          Text(subtitle).font(.callout).foregroundStyle(.secondary)
        }
        Spacer()
        if let activity = squid.activity {
          ProgressView().controlSize(.small)
          Text("\(activity.label)…").foregroundStyle(.secondary)
        } else {
          Button(squid.status.running ? "Stop" : "Start") {
            Task { squid.status.running ? await squid.stop() : await squid.start() }
          }
          .controlSize(.large)
          .keyboardShortcut(.defaultAction)
        }
      }

      if squid.needsRestart {
        HStack {
          Image(systemName: "arrow.triangle.2.circlepath")
          Text("Settings changed since squid started.")
          Spacer()
          Button("Restart Now") { Task { await squid.restart() } }
        }
        .padding(10)
        .background(.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
      }

      if let version = squid.squidUpgrade {
        HStack {
          Image(systemName: "arrow.up.circle")
          Text("Squid was upgraded to \(version).")
          Spacer()
          Button("Restart Now") { Task { await squid.restart() } }
        }
        .padding(10)
        .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
      }

      UpdateBanner(updater: updater)

      if let error = squid.lastError {
        VStack(alignment: .leading, spacing: 6) {
          HStack {
            Label("Error", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
            Spacer()
            Button("Dismiss") { squid.lastError = nil }.buttonStyle(.link)
          }
          ScrollView {
            Text(error)
              .font(.system(.caption, design: .monospaced))
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          .frame(maxHeight: 140)
        }
        .padding(10)
        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
      }

      GroupBox("Point clients at") {
        VStack(alignment: .leading, spacing: 6) {
          ForEach(localIPv4Addresses(), id: \.self) { a in
            HStack {
              Text(verbatim: "\(a.address):\(squid.settings.port)")
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
              Text(a.interface.hasPrefix("utun") ? "\(a.interface), VPN" : a.interface)
                .font(.caption).foregroundStyle(.secondary)
              Spacer()
              Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("\(a.address):\(squid.settings.port)", forType: .string)
              } label: { Image(systemName: "doc.on.doc") }
                .buttonStyle(.borderless)
                .help("Copy")
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(4)
      }

      GroupBox("Who can connect") {
        VStack(alignment: .leading, spacing: 4) {
          Text("This Mac (\(Text(verbatim: "localhost").monospaced()))")
          if !squid.settings.allowedClients.isEmpty {
            let clients = squid.settings.allowedClients.joined(separator: ", ")
            Text("Without a password: \(Text(verbatim: clients).monospaced())")
          }
          if squid.settings.requireAuth {
            let n = squid.users.count
            Text("Anyone with a user name and password (\(n) user\(n == 1 ? "" : "s"))")
          }
          if squid.settings.allowedClients.isEmpty, !squid.settings.requireAuth {
            Text("Nobody else. Add clients or users in Settings > Access.")
          }
        }
        // The window sizes to its content. Without this, SwiftUI cuts each line short.
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(4)
      }

      HStack {
        Button("Settings") { bringAppForward()
          openSettings()
        }
        Button("Logs") { openWindow(id: "logs") }
        Spacer()
        Text("Squid keeps running when this app quits.")
          .font(.caption).foregroundStyle(.secondary)
      }
    }
    .padding(20)
    .frame(width: 520)
  }

  // MARK: Private

  @Environment(\.openWindow) private var openWindow
  @Environment(\.openSettings) private var openSettings

  private var statusColor: Color {
    squid.phase == .stopped ? .secondary.opacity(0.4) : Color(nsColor: squid.phase.color)
  }

  private var statusTitle: String {
    if let activity = squid.activity { return "Squid is \(activity.label.lowercased())…" }
    return squid.status.running ? "Squid is running" : "Squid is stopped"
  }

  private var subtitle: String {
    if !squid.status.running {
      if squid.squidBinary == nil { return "Squid not found. Run: brew install squid" }
      if let code = squid.status.lastExitCode, squid.status.loaded, code != 0 {
        return "Exited with code \(code); launchd will retry"
      }
      return "Port \(squid.settings.port)"
    }
    var parts = ["Port \(squid.settings.port)"]
    if let pid = squid.status.pid { parts.append("pid \(pid)") }
    if squid.settings.keepAwake { parts.append("keeping the Mac awake") }
    return parts.joined(separator: " · ")
  }
}
