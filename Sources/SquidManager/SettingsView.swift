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
      // Grouped Forms draw text fields without a border, so they read as plain values.
      .textFieldStyle(.roundedBorder)
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

  // MARK: Internal

  var selectionDidChange: ((SettingsTab) -> Void)?

  override func viewWillAppear() {
    super.viewWillAppear()
    // Set before the first frame is drawn, so the window doesn't open in the default toolbar style and then switch.
    view.window?.toolbarStyle = .preference
    view.window?.titlebarSeparatorStyle = .line
  }

  override func viewDidAppear() {
    super.viewDidAppear()
    deselectFocusedText()
  }

  override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
    super.tabView(tabView, didSelect: tabViewItem)
    deselectFocusedText()
    // Loading the view selects the first tab before the saved one. Only report selections made once it's on screen.
    guard tabView.window != nil else { return }
    if let rawValue = tabViewItem?.identifier as? String, let tab = SettingsTab(rawValue: rawValue) {
      selectionDidChange?(tab)
    }
  }

  // MARK: Private

  /// NSTabView focuses the first key view of a tab, and when that is a text field it selects all of the text, which
  /// reads as highlighted. Keep the focus but drop the selection.
  private func deselectFocusedText() {
    guard let editor = view.window?.firstResponder as? NSTextView else { return }
    // The caret goes to the end of a field, or to the top of the template editor.
    let location = editor.isFieldEditor ? editor.string.utf16.count : 0
    editor.setSelectedRange(NSRange(location: location, length: 0))
    editor.scrollRangeToVisible(editor.selectedRange())
  }
}

// MARK: - FieldWidth

/// Text field widths sized to what goes in them. Fields in one group share a width so they line up.
private enum FieldWidth {
  /// Cache sizes such as "512 KB".
  static let short: CGFloat = 80
  /// Ports, hostnames, addresses, user names and file paths.
  static let medium: CGFloat = 200
  /// The user name and password side by side when adding a proxy user.
  static let credential: CGFloat = 120
}

// MARK: - FieldRow

/// A Form row whose field is only as wide as its values need. Grouped Forms ignore a frame set on a labeled field.
private struct FieldRow<Field: View>: View {
  init(_ title: String, width: CGFloat, @ViewBuilder field: () -> Field) {
    self.title = title
    self.width = width
    self.field = field()
  }

  let title: String
  let width: CGFloat
  @ViewBuilder let field: Field

  var body: some View {
    LabeledContent(title) {
      field.labelsHidden().frame(width: width)
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
    // Grouped Forms put footers 10pt in from the box edge and 10pt below it. Line the buttons up with the box edge,
    // and give them the same 20pt above as the Form leaves below them.
    .padding(.trailing, -10)
    .padding(.top, 10)
  }
}

// MARK: - GeneralTab

private struct GeneralTab: View {
  @EnvironmentObject var squid: SquidController

  var body: some View {
    Form {
      FieldRow("HTTP port", width: FieldWidth.medium) {
        TextField("HTTP port", value: $squid.settings.port, format: .number.grouping(.never))
      }
      FieldRow("Listen address", width: FieldWidth.medium) {
        TextField("Listen address", text: $squid.settings.listenAddress, prompt: Text("0.0.0.0"))
      }
      FieldRow("Visible hostname", width: FieldWidth.medium) {
        TextField("Visible hostname", text: $squid.settings.visibleHostname, prompt: Text(squid.defaultHostname))
      }
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
        LabeledContent("New user") {
          HStack {
            TextField("User", text: $form.newUser, prompt: Text("User"))
              .frame(width: FieldWidth.credential)
            SecureField("Password", text: $form.newPassword, prompt: Text("Password"))
              .frame(width: FieldWidth.credential)
            Button("Add / Update") { addUser() }
              .disabled(form.newUser.isEmpty || form.newPassword.isEmpty)
            Button("Remove", action: removeUser)
              .disabled(form.selectedUser == nil)
          }
          .labelsHidden()
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
        FieldRow("Host", width: FieldWidth.medium) {
          TextField("Host", text: $squid.settings.parentHost, prompt: Text("proxy.example.com"))
        }
        FieldRow("Port", width: FieldWidth.medium) {
          TextField("Port", value: $squid.settings.parentPort, format: .number.grouping(.never))
        }
        FieldRow("User", width: FieldWidth.medium) {
          TextField("User", text: $squid.settings.parentUser)
        }
        FieldRow("Password", width: FieldWidth.medium) {
          SecureField("Password", text: $squid.settings.parentPassword)
        }
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
        FieldRow("Disk cache (MB)", width: FieldWidth.short) {
          TextField("Disk cache (MB)", value: $squid.settings.cacheSizeMB, format: .number.grouping(.never))
        }
        FieldRow("Largest object on disk", width: FieldWidth.short) {
          TextField("Largest object on disk", text: $squid.settings.maxObjectSize)
        }
        FieldRow("Memory cache", width: FieldWidth.short) {
          TextField("Memory cache", text: $squid.settings.memoryCacheSize)
        }
        FieldRow("Largest object in memory", width: FieldWidth.short) {
          TextField("Largest object in memory", text: $squid.settings.memoryMaxObjectSize)
        }
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
      LabeledContent("squid binary") {
        HStack {
          if let path = squid.squidBinary {
            Text(path).foregroundStyle(.secondary).textSelection(.enabled)
              .lineLimit(1).truncationMode(.middle)
              // Without a cap, a long path pushes the buttons onto a second line.
              .frame(maxWidth: FieldWidth.medium, alignment: .trailing)
              .help(path)
          } else {
            Text("Not found").foregroundStyle(.red)
          }
          if !squid.settings.squidPath.isEmpty {
            Button("Use Detected") { squid.settings.squidPath = "" }
              .disabled(squid.detectedSquid == nil)
          }
          Button("Choose…", action: chooseSquid)
        }
      }
      FieldRow("DNS servers", width: FieldWidth.medium) {
        TextField("DNS servers", text: $squid.settings.dnsServers, prompt: Text("1.1.1.1 8.8.8.8"))
      }
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

  private func chooseSquid() {
    let start = squid.squidBinary ?? squid.detectedSquid ?? "/opt/homebrew/sbin/squid"
    guard let path = SquidPicker().choose(startingAt: URL(fileURLWithPath: start).deletingLastPathComponent()) else {
      return
    }
    // Picking the detected squid goes back to detecting, so a reinstall elsewhere is still found.
    squid.settings.squidPath = path == squid.detectedSquid ? "" : path
  }

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

// MARK: - SquidPicker

/// An open panel that only lets the user pick executable files. ⌘⇧G in the panel takes a typed path.
private final class SquidPicker: NSObject, NSOpenSavePanelDelegate {
  func choose(startingAt directory: URL) -> String? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = false
    panel.directoryURL = directory
    panel.delegate = self
    guard panel.runModal() == .OK else { return nil }
    return panel.url?.path
  }

  func panel(_: Any, shouldEnable url: URL) -> Bool {
    // Directories pass too, since they have the execute bit, so the user can still browse into them.
    FileManager.default.isExecutableFile(atPath: url.path)
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
        switch updater.state {
        case .available, .installing, .failed:
          UpdateBanner(updater: updater)

        case .idle, .checking, .upToDate:
          HStack {
            status
            Spacer()
            Button("Check Now") { Task { await updater.check() } }
              .disabled(updater.state == .checking)
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

    case .available, .installing, .failed:
      EmptyView()
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
    LabeledContent("New entry") {
      HStack {
        TextField("New entry", text: $form.draft, prompt: Text(placeholder))
          .labelsHidden()
          .frame(width: FieldWidth.medium)
          .onSubmit(add)
        Button("Add", action: add).disabled(form.draft.trimmingCharacters(in: .whitespaces).isEmpty)
        Button("Remove") {
          items.removeAll { $0 == form.selection }
          form.selection = nil
        }
        .disabled(form.selection == nil)
      }
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
