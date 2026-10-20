import AppKit
import Combine

// MARK: - MenuBarIcon

/// Draws the shared SVG as a template image: full while squid runs, dimmed while it is stopped,
/// and fading in and out while it starts, stops or restarts.
@MainActor
final class MenuBarIcon: ObservableObject {

  // MARK: Lifecycle

  init(_ squid: SquidController) {
    frames = Self.levels.map { Self.render(fraction: $0) }
    image = frames[frames.count - 1]
    // @Published emits before the property changes, so build the phase from the emitted values.
    observation = squid.$activity.combineLatest(squid.$status)
      .map { SquidController.Phase(activity: $0, status: $1) }
      .removeDuplicates()
      .sink { [weak self] phase in
        MainActor.assumeIsolated { self?.show(phase) }
      }
  }

  // MARK: Internal

  @Published private(set) var image: NSImage

  // MARK: Private

  /// Opacity steps from dim to full. The pulse walks up and back down, one step per tick.
  private static let levels: [CGFloat] = [0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1]
  private static let stoppedLevel = 1

  /// `Bundle.module` looks for the resource bundle at the root of the .app, where codesign forbids it,
  /// and then at the absolute `.build` path of the machine that compiled the app. build-app.sh puts the
  /// bundle in Contents/Resources, so look there first and fall back to `Bundle.module` for `swift run`.
  private static let resources = Bundle.main.url(forResource: "SquidManager_SquidManager", withExtension: "bundle")
    .flatMap(Bundle.init(url:)) ?? Bundle.module

  private let frames: [NSImage]
  private var observation: AnyCancellable?
  private var timer: Timer?
  private var tick = 0

  private static func render(fraction: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
      guard
        let url = resources.url(forResource: "squid", withExtension: "svg"),
        let squid = NSImage(contentsOf: url)
      else { return false }
      squid.draw(in: rect, from: .zero, operation: .sourceOver, fraction: fraction)
      return true
    }
    image.isTemplate = true
    return image
  }

  private func show(_ phase: SquidController.Phase) {
    timer?.invalidate()
    timer = nil
    if phase.isChanging {
      tick = 0
      let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
        MainActor.assumeIsolated { self?.advance(phase) }
      }
      // Common modes keep the pulse going while the menu is open.
      RunLoop.main.add(timer, forMode: .common)
      self.timer = timer
      advance(phase)
    } else {
      let frame = phase == .running ? frames[frames.count - 1] : frames[Self.stoppedLevel]
      setImage(frame, phase)
    }
  }

  private func advance(_ phase: SquidController.Phase) {
    // 0 1 2 … 7 6 5 … 1, then again: a triangle wave over the frames.
    let period = 2 * (frames.count - 1)
    let step = tick % period
    tick += 1
    setImage(frames[step < frames.count ? step : period - step], phase)
  }

  private func setImage(_ frame: NSImage, _ phase: SquidController.Phase) {
    frame.accessibilityDescription = "Squid: \(phase.title)"
    image = frame
  }
}

// MARK: - StatusDot

/// The colored dot next to the status line in the menu.
enum StatusDot {
  static func image(_ color: NSColor) -> NSImage {
    let image = NSImage(size: NSSize(width: 10, height: 10), flipped: false) { rect in
      color.setFill()
      NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
      return true
    }
    image.isTemplate = false
    return image
  }
}
