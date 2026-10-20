import SwiftUI

// MARK: - SquidManagerApp

struct SquidManagerApp: App {

  // MARK: Lifecycle

  init() {
    let squid = SquidController()
    _squid = StateObject(wrappedValue: squid)
    _menuBarIcon = StateObject(wrappedValue: MenuBarIcon(squid))
    let updater = Updater()
    // An automatic update relaunches the app, so wait while the user has a window open or squid is changing state.
    updater.isBusy = { [weak squid] in squid?.activity != nil || NSApp.hasVisibleTitledWindow }
    updater.start()
    _updater = StateObject(wrappedValue: updater)
  }

  // MARK: Internal

  var body: some Scene {
    Window("SquidManager", id: "main") {
      StatusView().environmentObject(squid).environmentObject(updater)
    }
    .windowResizability(.contentSize)

    Window("Squid Logs", id: "logs") {
      LogsView().environmentObject(squid)
    }
    .defaultSize(width: 860, height: 520)

    Settings {
      SettingsView().environmentObject(squid).environmentObject(updater)
    }

    MenuBarExtra {
      MenuContent().environmentObject(squid).environmentObject(updater)
    } label: {
      Image(nsImage: menuBarIcon.image)
    }
  }

  // MARK: Private

  @NSApplicationDelegateAdaptor private var delegate: AppDelegate
  @StateObject private var squid: SquidController
  @StateObject private var menuBarIcon: MenuBarIcon
  @StateObject private var updater: Updater

}

// MARK: - MenuContent

struct MenuContent: View {

  // MARK: Internal

  @EnvironmentObject var squid: SquidController
  @EnvironmentObject var updater: Updater

  var body: some View {
    // A disabled button renders as a gray menu item. The dot keeps its color.
    Button { } label: {
      Label {
        Text(squid.phase.title)
      } icon: {
        Image(nsImage: StatusDot.image(squid.phase.color)).renderingMode(.original)
      }
      .labelStyle(.titleAndIcon)
    }
    .disabled(true)
    Divider()
    if squid.activity == nil {
      if squid.status.running {
        if let version = squid.squidUpgrade {
          Button("Restart to Use Squid \(version)") { Task { await squid.restart() } }
        } else if squid.needsRestart {
          Button("Restart to Apply Changes") { Task { await squid.restart() } }
        }
        Button("Stop") { Task { await squid.stop() } }
      } else {
        Button("Start") { Task { await squid.start() } }
      }
      Divider()
    }
    if let release = updater.available {
      Button("Update to SquidManager \(release.displayVersion)") { Task { await updater.install(release) } }
      Divider()
    }
    Button("Open SquidManager") { show("main") }
    Button("Logs") { show("logs") }
    // Not SettingsLink. A gesture attached to it never fires inside a menu, so it could not bring the app forward.
    Button("Settings…") { showSettings(.general) }
    Button("About SquidManager") { showSettings(.about) }
    Divider()
    Button("Quit SquidManager") { NSApp.terminate(nil) }
      .help("Squid keeps running after the app quits.")
  }

  // MARK: Private

  @Environment(\.openWindow) private var openWindow
  @Environment(\.openSettings) private var openSettings

  private func show(_ id: String) {
    bringAppForward()
    openWindow(id: id)
  }

  private func showSettings(_ tab: SettingsTab) {
    UserDefaults.standard.set(tab.rawValue, forKey: SettingsTab.defaultsKey)
    bringAppForward()
    openSettings()
  }
}

/// Show the app in the Dock and app switcher while a window is open.
@MainActor
func bringAppForward() {
  if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
  NSApp.activate()
}

// MARK: - AppDelegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

  // MARK: Internal

  func applicationDidFinishLaunching(_: Notification) {
    for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.willCloseNotification] {
      observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
        // willClose fires while the window is still visible, so check on the next turn.
        DispatchQueue.main.async {
          self?.updateActivationPolicy()
          self?.focusMainWindowIfNeeded()
        }
      })
    }

    // Opening at login should only add the menu bar icon, not pop a window.
    let event = NSAppleEventManager.shared().currentAppleEvent
    let loginLaunch = event?.eventID == kAEOpenApplication
      && event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    // The same goes for a relaunch after an automatic update.
    if loginLaunch || CommandLine.arguments.contains(Updater.backgroundArgument) {
      DispatchQueue.main.async {
        NSApp.windows.filter { $0.identifier?.rawValue == "main" }.forEach { $0.close() }
        NSApp.setActivationPolicy(.accessory)
      }
    } else {
      shouldFocusMainWindow = true
      DispatchQueue.main.async { self.focusMainWindowIfNeeded() }
    }
  }

  func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
    shouldFocusMainWindow = true
    bringAppForward()
    DispatchQueue.main.async { self.focusMainWindowIfNeeded() }
    return true
  }

  // MARK: Private

  private var observers = [NSObjectProtocol]()
  private var hasShownWindow = false
  private var shouldFocusMainWindow = false

  private func focusMainWindowIfNeeded() {
    guard
      shouldFocusMainWindow,
      let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" && $0.isVisible })
    else { return }
    shouldFocusMainWindow = false
    hasShownWindow = true
    bringAppForward()
    window.makeKeyAndOrderFront(nil)
  }

  private func updateActivationPolicy() {
    if NSApp.hasVisibleTitledWindow {
      hasShownWindow = true
      if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
    } else if hasShownWindow, !shouldFocusMainWindow, NSApp.activationPolicy() == .regular {
      NSApp.setActivationPolicy(.accessory)
    }
  }
}

extension NSApplication {
  /// The menu bar icon and its menu are untitled windows, so this counts only titled ones.
  var hasVisibleTitledWindow: Bool {
    windows.contains { $0.isVisible && $0.styleMask.contains(.titled) }
  }
}
