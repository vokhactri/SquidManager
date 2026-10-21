import SwiftUI

struct UpdateBanner: View {

  // MARK: Internal

  @ObservedObject var updater: Updater

  var body: some View {
    switch updater.state {
    case .available, .installing, .failed:
      HStack(alignment: .center, spacing: 12) {
        if updater.state == .installing {
          ProgressView().controlSize(.small)
        } else {
          Image(systemName: icon)
            .foregroundStyle(hasFailed ? Color.orange : Color.secondary)
        }
        VStack(alignment: .leading, spacing: 4) {
          details
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        action.fixedSize()
      }
      .padding(12)
      .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

    case .idle, .checking, .upToDate:
      EmptyView()
    }
  }

  // MARK: Private

  private var hasFailed: Bool {
    if case .failed = updater.state { return true }
    return false
  }

  private var icon: String {
    hasFailed ? "exclamationmark.triangle" : "arrow.down.circle"
  }

  @ViewBuilder
  private var details: some View {
    switch updater.state {
    case .available(let release):
      Text("Version \(release.displayVersion) is available")
        .fontWeight(.medium)
      Link("Release Notes", destination: release.pageURL)
        .font(.caption)

    case .installing:
      Text("Updating SquidManager…").fontWeight(.medium)
      Text("The app will restart automatically.")
        .font(.caption).foregroundStyle(.secondary)

    case .failed(let message):
      Text("Update failed").fontWeight(.medium)
      Text(message)
        .font(.caption).foregroundStyle(.secondary)
        .textSelection(.enabled)

    case .idle, .checking, .upToDate:
      EmptyView()
    }
  }

  @ViewBuilder
  private var action: some View {
    switch updater.state {
    case .available(let release):
      Button("Update and Restart") { Task { await updater.install(release) } }

    case .installing:
      Button("Updating…") { }
        .disabled(true)

    case .failed:
      Button("Try Again") { Task { await updater.retry() } }

    case .idle, .checking, .upToDate:
      EmptyView()
    }
  }
}
