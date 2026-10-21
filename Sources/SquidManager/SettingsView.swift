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

  /// Grouped Forms scroll, so they have no fitting height to size the window from. Each tab gets a fixed one.
  fileprivate var contentHeight: CGFloat {
    switch self {
    case .general: 362
    case .access: 520
    case .parent: 440
    case .cache: 320
    case .template: 443
    case .advanced: 320
    case .about: 420
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
      SettingsTabs(selection: $tab, squid: squid, updater: updater)
        .frame(height: tab.contentHeight)
      if squid.needsRestart {
        HStack {
          Text("Changes take effect after squid restarts.").foregroundStyle(.secondary)
          Spacer()
          Button("Restart Squid") { Task { await squid.restart() } }
            .disabled(squid.activity != nil)
        }
        .padding(12)
      }
    }
    .frame(width: 580)
    .navigationTitle(tab.title)
  }

  // MARK: Private

  @AppStorage(SettingsTab.defaultsKey) private var tab = SettingsTab.general
}

// MARK: - SettingsTabs

/// An NSTabViewController in toolbar style, so switching tabs doesn't rebuild the toolbar like SwiftUI's TabView does.
private struct SettingsTabs: NSViewControllerRepresentable {

  // MARK: Internal

  @Binding var selection: SettingsTab

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

// MARK: - SettingsTabsController

private final class SettingsTabsController: NSTabViewController {
  var selectionDidChange: ((SettingsTab) -> Void)?

  override func viewWillAppear() {
    super.viewWillAppear()
    // Set before the first frame is drawn, so the window doesn't open in the default toolbar style and then switch.
    view.window?.toolbarStyle = .preference
    view.window?.titlebarSeparatorStyle = .line
  }

  override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
    super.tabView(tabView, didSelect: tabViewItem)
    if let rawValue = tabViewItem?.identifier as? String, let tab = SettingsTab(rawValue: rawValue) {
      selectionDidChange?(tab)
    }
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
      } footer: {
        Text("""
          Squid runs as a launchd agent. It starts again after a crash and at every login \
          until you press Stop, whether or not this app is open. Keeping the Mac awake stops \
          idle sleep only. Closing a laptop lid still sleeps the Mac unless it has power and an external display.
          """)
        .font(.caption).foregroundStyle(.secondary)
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
      } footer: {
        Text("A host (100.64.1.2), a subnet (10.0.0.0/8) or \"all\". localhost is always allowed.")
          .font(.caption).foregroundStyle(.secondary)
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
      } footer: {
        Text("Clients in the list above skip the password. Adding or removing users takes effect without a restart.")
          .font(.caption).foregroundStyle(.secondary)
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
        Text(
          "0 MB turns caching off, which is what you want for a plain residential proxy. Sizes use squid units such as \"4 MB\" or \"512 KB\"."
        )
        .font(.caption).foregroundStyle(.secondary)
      }
      Section {
        Button("Flush Cache") { Task { await squid.flushCache() } }
          .disabled(squid.activity != nil)
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
          .frame(height: 250)
      } footer: {
        Text("squid.conf is generated from this template. Placeholders like %HTTP_PORT% come from the other tabs.")
          .font(.caption).foregroundStyle(.secondary)
      }
      Section {
        Button("Reset to Default") { squid.settings.template = SquidConfig.defaultTemplate }
          .disabled(squid.settings.template == SquidConfig.defaultTemplate)
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
