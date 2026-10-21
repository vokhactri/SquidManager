import SquidCore
import SwiftUI

// MARK: - SettingsTab

enum SettingsTab: String, CaseIterable {
  case general
  case access
  case parent
  case cache
  case template
  case advanced
  case about

  // MARK: Internal

  /// The menu writes here before opening Settings, so About in the menu lands on the About tab.
  static let defaultsKey = "settingsTab"

  var title: String {
    switch self {
    case .general: "General"
    case .access: "Access"
    case .parent: "Parent"
    case .cache: "Cache"
    case .template: "Template"
    case .advanced: "Advanced"
    case .about: "About"
    }
  }

  // MARK: Fileprivate

  fileprivate var systemImage: String {
    switch self {
    case .general: "gearshape"
    case .access: "person.2"
    case .parent: "arrow.up.forward.circle"
    case .cache: "internaldrive"
    case .template: "doc.text"
    case .advanced: "wrench.and.screwdriver"
    case .about: "info.circle"
    }
  }
}

// MARK: - SettingsView

struct SettingsView: View {

  // MARK: Internal

  @EnvironmentObject var squid: SquidController

  /// The tabs observe this. SettingsView only hands it on, so it doesn't subscribe.
  let updater: Updater

  var body: some View {
    VStack(spacing: 0) {
      SettingsTabs(selection: $tab, heights: heights, squid: squid, updater: updater)
        .frame(height: heights.values[tab] ?? 400)
      if squid.needsRestart {
        Divider()
        HStack {
          Text("Changes take effect after squid restarts.").foregroundStyle(.secondary)
          Spacer()
          Button("Restart Squid") { Task { await squid.restart() } }
            .disabled(squid.activity != nil)
        }
        .padding(20)
      }
    }
    .frame(width: 580)
    .navigationTitle(tab.title)
  }

  // MARK: Private

  @AppStorage(SettingsTab.defaultsKey) private var tab = SettingsTab.general
  @StateObject private var heights = TabHeights()
}

// MARK: - SettingsTabs

/// An NSTabViewController in toolbar style, so switching tabs doesn't rebuild the toolbar like SwiftUI's TabView does.
private struct SettingsTabs: NSViewControllerRepresentable {

  // MARK: Internal

  @Binding var selection: SettingsTab

  let heights: TabHeights
  let squid: SquidController
  let updater: Updater

  func makeNSViewController(context: Context) -> SettingsTabsController {
    let controller = SettingsTabsController()
    controller.tabStyle = .toolbar
    controller.transitionOptions = []
    controller.tabViewItems = SettingsTab.allCases.map(item)
    updateNSViewController(controller, context: context)
    return controller
  }

  func updateNSViewController(_ controller: SettingsTabsController, context _: Context) {
    controller.selectionDidChange = { tab in
      if selection != tab { selection = tab }
    }
    let index = SettingsTab.allCases.firstIndex(of: selection) ?? 0
    if controller.selectedTabViewItemIndex != index {
      controller.selectedTabViewItemIndex = index
    }
  }

  // MARK: Private

  private func item(_ tab: SettingsTab) -> NSTabViewItem {
    let controller = NSHostingController(rootView: content(tab)
      .onScrollGeometryChange(for: CGFloat.self) { geometry in
        geometry.contentSize.height + geometry.contentInsets.top + geometry.contentInsets.bottom
      } action: { _, height in
        heights.values[tab] = height
      }
      .environmentObject(squid)
      .environmentObject(updater))
    // SettingsView owns the window size. The hosting controller would otherwise push its own size constraints.
    controller.sizingOptions = []
    let item = NSTabViewItem(viewController: controller)
    item.identifier = tab.rawValue
    item.label = tab.title
    item.image = NSImage(systemSymbolName: tab.systemImage, accessibilityDescription: tab.title)
    return item
  }

  @ViewBuilder
  private func content(_ tab: SettingsTab) -> some View {
    switch tab {
    case .general: GeneralTab()
    case .access: AccessTab()
    case .parent: ParentTab()
    case .cache: CacheTab()
    case .template: TemplateTab()
    case .advanced: AdvancedTab()
    case .about: AboutTab()
    }
  }
}

// MARK: - TabHeights

/// Each tab's Form content height, measured once the tab loads, so the window fits the tab without scrolling.
private final class TabHeights: ObservableObject {
  @Published var values = [SettingsTab: CGFloat]()
}

// MARK: - SettingsTabsController

private final class SettingsTabsController: NSTabViewController {
  var selectionDidChange: ((SettingsTab) -> Void)?

  override func viewWillAppear() {
    super.viewWillAppear()
    // Set before the first frame is drawn, so the window doesn't open in the default toolbar style and then switch.
    view.window?.toolbarStyle = .preference
    view.window?.titlebarSeparatorStyle = .line
  }

  override func viewDidAppear() {
    super.viewDidAppear()
    view.window?.makeFirstResponder(nil)
  }

  override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
    super.tabView(tabView, didSelect: tabViewItem)
    // NSTabView focuses the first text field of the new tab and selects its text. Leave nothing focused instead.
    tabView.window?.makeFirstResponder(nil)
    if let rawValue = tabViewItem?.identifier as? String, let tab = SettingsTab(rawValue: rawValue) {
      selectionDidChange?(tab)
    }
  }
}

// MARK: - SectionButtons

/// Buttons in a grouped Form section footer, right-aligned with the section's box.
private struct SectionButtons<Content: View>: View {
  @ViewBuilder let content: Content

  var body: some View {
    HStack {
      Spacer()
      content
    }
    // Grouped Forms inset footers to line up with the row text. Undo that so the buttons line up with the box edge.
    .padding(.trailing, -10)
  }
}

// MARK: - GeneralTab

private struct GeneralTab: View {
  @EnvironmentObject var squid: SquidController

  var body: some View {
    Form {
      TextField("HTTP port", value: $squid.settings.port, format: .number.grouping(.never))
      TextField("Listen address", text: $squid.settings.listenAddress, prompt: Text("All interfaces"))
      TextField("Visible hostname", text: $squid.settings.visibleHostname, prompt: Text("This Mac's hostname"))
      Section {
        Toggle("Hide proxy headers (Via, X-Forwarded-For, Cache-Control)", isOn: $squid.settings.anonymize)
        Toggle("Log every request to access.log", isOn: $squid.settings.logRequests)
        Toggle("Keep the Mac awake while squid runs", isOn: $squid.settings.keepAwake)
        Toggle("Open SquidManager at login", isOn: Binding(
          get: { squid.opensAtLogin },
          set: { squid.opensAtLogin = $0 }
        ))
      }
    }
    .formStyle(.grouped)
  }
}

// MARK: - AccessTab

private struct AccessTab: View {

  // MARK: Internal

  @EnvironmentObject var squid: SquidController

  var body: some View {
    Form {
      Section {
        StringListEditor(items: $squid.settings.allowedClients, placeholder: "192.168.1.0/24")
      } header: {
        Text("Clients allowed without a password")
      }

      Section {
        Toggle("Require a user name and password from other clients", isOn: $squid.settings.requireAuth)
        List(selection: $form.selectedUser) {
          ForEach(squid.users, id: \.self) { Text($0) }
        }
        .frame(height: 90)
        HStack {
          TextField("User", text: $form.newUser)
          SecureField("Password", text: $form.newPassword)
          Button("Add / Update") { addUser() }
            .disabled(form.newUser.isEmpty || form.newPassword.isEmpty)
          Button("Remove", action: removeUser)
            .disabled(form.selectedUser == nil)
        }
        if let error = form.error { Text(error).foregroundStyle(.red).font(.caption) }
      } header: {
        Text("Proxy users")
      }
    }
    .formStyle(.grouped)
  }

  // MARK: Private

  @StateObject private var form = UserForm()

  private func addUser() {
    Task {
      do {
        try await squid.setUser(form.newUser, password: form.newPassword)
        form.newUser = ""
        form.newPassword = ""
        form.error = nil
      } catch {
        form.error = error.localizedDescription
      }
    }
  }

  private func removeUser() {
    guard let user = form.selectedUser else { return }
    do {
      try squid.removeUser(user)
      form.selectedUser = nil
      form.error = nil
    } catch {
      form.error = error.localizedDescription
    }
  }
}

// MARK: - ParentTab

private struct ParentTab: View {
  @EnvironmentObject var squid: SquidController

  var body: some View {
    Form {
      Toggle("Forward requests through a parent proxy", isOn: $squid.settings.useParent)
      Group {
        TextField("Host", text: $squid.settings.parentHost)
        TextField("Port", value: $squid.settings.parentPort, format: .number.grouping(.never))
        TextField("User", text: $squid.settings.parentUser, prompt: Text("Optional"))
        SecureField("Password", text: $squid.settings.parentPassword, prompt: Text("Optional"))
        Section("Go direct for these hosts and domains") {
          StringListEditor(items: $squid.settings.directHosts, placeholder: ".example.com")
        }
      }
      .disabled(!squid.settings.useParent)
    }
    .formStyle(.grouped)
  }
}

// MARK: - CacheTab

private struct CacheTab: View {
  @EnvironmentObject var squid: SquidController

  var body: some View {
    Form {
      Section {
        TextField("Disk cache (MB)", value: $squid.settings.cacheSizeMB, format: .number.grouping(.never))
        TextField("Largest object on disk", text: $squid.settings.maxObjectSize)
        TextField("Memory cache", text: $squid.settings.memoryCacheSize)
        TextField("Largest object in memory", text: $squid.settings.memoryMaxObjectSize)
      } footer: {
        SectionButtons {
          Button("Flush Cache") { Task { await squid.flushCache() } }
            .disabled(squid.activity != nil)
        }
      }
    }
    .formStyle(.grouped)
  }
}

// MARK: - TemplateTab

private struct TemplateTab: View {
  @EnvironmentObject var squid: SquidController

  var body: some View {
    Form {
      Section {
        TextEditor(text: $squid.settings.template)
          .font(.system(.body, design: .monospaced))
          .scrollContentBackground(.hidden)
          .frame(height: 320)
      } footer: {
        SectionButtons {
          Button("Reset to Default") { squid.settings.template = SquidConfig.defaultTemplate }
            .disabled(squid.settings.template == SquidConfig.defaultTemplate)
        }
      }
    }
    .formStyle(.grouped)
  }
}

// MARK: - AdvancedTab

private struct AdvancedTab: View {

  // MARK: Internal

  @EnvironmentObject var squid: SquidController

  var body: some View {
    Form {
      TextField(
        "squid binary",
        text: $squid.settings.squidPath,
        prompt: Text(squid.squidBinary ?? "/opt/homebrew/sbin/squid")
      )
      TextField("DNS servers", text: $squid.settings.dnsServers, prompt: Text("System default"))
      Section("Files") {
        fileRow("Config and users", squid.paths.root)
        fileRow("Logs", squid.paths.logs)
        fileRow("Cache", squid.paths.cache)
        fileRow("launchd agent", LaunchAgent.plistURL().deletingLastPathComponent())
      }
    }
    .formStyle(.grouped)
  }

  // MARK: Private

  private func fileRow(_ title: String, _ url: URL) -> some View {
    HStack {
      Text(title)
      Spacer()
      Text(url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
        .foregroundStyle(.secondary).textSelection(.enabled)
      Button { NSWorkspace.shared.open(url) } label: { Image(systemName: "folder") }
        .buttonStyle(.borderless)
    }
  }
}

// MARK: - AboutTab

private struct AboutTab: View {

  // MARK: Internal

  @EnvironmentObject var updater: Updater

  var body: some View {
    Form {
      Section {
        HStack(spacing: 16) {
          Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .frame(width: 64, height: 64)
          VStack(alignment: .leading, spacing: 4) {
            Text("SquidManager").font(.title2.weight(.semibold))
            Text("Version \(Updater.currentVersion)").foregroundStyle(.secondary).textSelection(.enabled)
            Text("By \(Updater.author)")
          }
        }
        LabeledContent("Releases") {
          Link(
            Updater.releasesURL.absoluteString.replacingOccurrences(of: "https://", with: ""),
            destination: Updater.releasesURL
          )
        }
      }

      Section {
        Toggle("Install updates automatically", isOn: $updater.installsAutomatically)
        HStack {
          status
          Spacer()
          if let release = updater.available {
            Link("Release Notes", destination: release.pageURL)
            Button("Install and Relaunch") { Task { await updater.install(release) } }
          } else {
            Button("Check Now") { Task { await updater.check() } }
              .disabled(updater.state == .checking || updater.state == .installing)
          }
        }
      } header: {
        Text("Updates")
      }

      Section {
        Text("Copyright © 2026 \(Updater.author). MIT License. Squid is GPL-2.0 and installed separately.")
          .font(.caption).foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
  }

  // MARK: Private

  @ViewBuilder
  private var status: some View {
    switch updater.state {
    case .idle:
      Text("Not checked yet").foregroundStyle(.secondary)

    case .checking:
      HStack { ProgressView().controlSize(.small)
        Text("Checking…")
      }

    case .upToDate:
      Text("SquidManager is up to date")

    case .available(let release):
      Text("Version \(release.displayVersion) is available")

    case .installing:
      HStack { ProgressView().controlSize(.small)
        Text("Installing…")
      }

    case .failed(let message):
      Text(message).foregroundStyle(.red).textSelection(.enabled)
    }
  }
}

// MARK: - StringListEditor

struct StringListEditor: View {

  // MARK: Internal

  @Binding var items: [String]

  var placeholder: String

  var body: some View {
    List(selection: $form.selection) {
      ForEach(items, id: \.self) { Text($0).font(.system(.body, design: .monospaced)) }
    }
    .frame(height: 100)
    HStack {
      TextField("New entry", text: $form.draft, prompt: Text(placeholder))
        .onSubmit(add)
      Button("Add", action: add).disabled(form.draft.trimmingCharacters(in: .whitespaces).isEmpty)
      Button("Remove") {
        items.removeAll { $0 == form.selection }
        form.selection = nil
      }
      .disabled(form.selection == nil)
    }
  }

  // MARK: Private

  @StateObject private var form = ListForm()

  private func add() {
    let entry = form.draft.trimmingCharacters(in: .whitespaces)
    guard !entry.isEmpty, !entry.contains(where: \.isWhitespace), !items.contains(entry) else { return }
    items.append(entry)
    form.draft = ""
  }
}

// MARK: - UserForm

/// Not @State: on the macOS 27 SDK that is a macro whose plugin ships only with Xcode.
final class UserForm: ObservableObject {
  @Published var newUser = ""
  @Published var newPassword = ""
  @Published var selectedUser: String?
  @Published var error: String?
}

// MARK: - ListForm

final class ListForm: ObservableObject {
  @Published var draft = ""
  @Published var selection: String?
}
