import AppKit
import SquidCore

extension SquidController {

  enum Activity: Equatable {
    case starting
    case stopping
    case restarting
    case rotatingLogs
    /// Flushing stops and starts squid when it was running.
    case flushingCache(restartsSquid: Bool)

    var label: String {
      switch self {
      case .starting: "Starting"
      case .stopping: "Stopping"
      case .restarting: "Restarting"
      case .rotatingLogs: "Rotating logs"
      case .flushingCache: "Flushing cache"
      }
    }
  }

  /// The state shown in the menu bar icon and the status line of the menu.
  enum Phase: Equatable {
    case stopped
    case starting
    case running
    case stopping
    case restarting
    /// launchd has the job loaded but squid exited with an error. launchd starts it again after ThrottleInterval.
    case crashed

    // MARK: Lifecycle

    init(activity: Activity?, status: LaunchAgent.Status) {
      switch activity {
      case .starting:
        self = .starting
        return

      case .stopping:
        self = .stopping
        return

      case .restarting, .flushingCache(restartsSquid: true):
        self = .restarting
        return

      case .rotatingLogs, .flushingCache(restartsSquid: false), nil:
        break
      }
      if status.running {
        self = .running
      } else if !status.loaded || status.lastExitCode == 0 {
        self = .stopped
      } else if status.lastExitCode == nil {
        // Loaded with no pid and no exit code yet: launchd is about to spawn squid.
        self = .starting
      } else {
        self = .crashed
      }
    }

    // MARK: Internal

    var title: String {
      switch self {
      case .stopped: "Stopped"
      case .starting: "Starting"
      case .running: "Running"
      case .stopping: "Stopping"
      case .restarting: "Restarting"
      case .crashed: "Crashed, launchd will retry"
      }
    }

    /// True while squid is on its way up or down. The menu bar icon pulses in these phases.
    var isChanging: Bool {
      switch self {
      case .starting, .stopping, .restarting: true
      case .stopped, .running, .crashed: false
      }
    }

    var color: NSColor {
      switch self {
      case .running: .systemGreen
      case .starting, .stopping, .restarting: .systemYellow
      case .crashed: .systemRed
      case .stopped: .systemGray
      }
    }
  }
}
