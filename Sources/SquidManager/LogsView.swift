import AppKit
import Combine
import SwiftUI

// MARK: - LogsView

struct LogsView: View {

  // MARK: Internal

  enum Source: String, CaseIterable, Identifiable {
    case access = "Access"
    case cache = "Cache"
    case launchd = "launchd Output"
    case config = "squid.conf"

    var id: Self {
      self
    }
  }

  @EnvironmentObject var squid: SquidController

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Picker("Log", selection: $state.source) {
          ForEach(Source.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 420)
        Spacer()
        Button("Rotate Logs") { Task { await squid.rotateLogs() } }
          .disabled(!squid.status.running)
          .help("Squid renames the current logs to .0, .1, … and opens new ones.")
        Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: {
          Image(systemName: "folder")
        }
        .help("Show in Finder")
      }
      .padding(10)
      Divider()
      LogTextView(text: state.text)
    }
    .onAppear { reload(force: true) }
    .onChange(of: state.source) { reload(force: true) }
    .onReceive(timer) { _ in reload(force: false) }
  }

  /// Reads at most the last `maxBytes` of a file so huge access logs stay responsive.
  static func tail(of url: URL, maxBytes: UInt64) -> String? {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
    defer { try? handle.close() }
    let size = (try? handle.seekToEnd()) ?? 0
    let start = size > maxBytes ? size - maxBytes : 0
    try? handle.seek(toOffset: start)
    let data = (try? handle.readToEnd()) ?? Data()
    var s = String(decoding: data, as: UTF8.self)
    if start > 0, let nl = s.firstIndex(of: "\n") { s = String(s[s.index(after: nl)...]) }
    return s
  }

  // MARK: Private

  @StateObject private var state = LogsState()

  private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

  private var url: URL {
    switch state.source {
    case .access: squid.paths.accessLog
    case .cache: squid.paths.cacheLog
    case .launchd: squid.paths.stderrLog
    case .config: squid.paths.config
    }
  }

  private func reload(force: Bool) {
    let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
    let stamp = attrs?[.modificationDate] as? Date
    guard force || stamp != state.lastStamp else { return }
    state.lastStamp = stamp
    state.text = Self.tail(of: url, maxBytes: 512 * 1024) ?? "(\(url.lastPathComponent) does not exist yet)"
  }

}

// MARK: - LogsState

/// The macOS 27 SDK makes @State a macro whose plugin ships only with Xcode,
/// so view-local state lives in small ObservableObjects to keep Command Line Tools builds working.
final class LogsState: ObservableObject {
  @Published var source = LogsView.Source.access
  @Published var text = ""
  var lastStamp: Date?
}

// MARK: - LogTextView

/// NSTextView handles multi-megabyte text far better than SwiftUI's Text.
struct LogTextView: NSViewRepresentable {
  var text: String

  func makeNSView(context _: Context) -> NSScrollView {
    let scroll = NSTextView.scrollableTextView()
    let tv = scroll.documentView as! NSTextView
    tv.isEditable = false
    tv.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
    tv.textContainerInset = NSSize(width: 6, height: 6)
    return scroll
  }

  func updateNSView(_ scroll: NSScrollView, context _: Context) {
    let tv = scroll.documentView as! NSTextView
    guard tv.string != text else { return }
    // Follow new lines only if the user was already at the bottom.
    let atBottom = scroll.documentVisibleRect.maxY >= tv.bounds.height - 20
    tv.string = text
    if atBottom { tv.scrollToEndOfDocument(nil) }
  }
}
