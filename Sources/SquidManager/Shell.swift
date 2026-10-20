import Foundation

// MARK: - ShellResult

struct ShellResult {
  var status: Int32
  var output: String

  var ok: Bool {
    status == 0
  }
}

// MARK: - Shell

enum Shell {
  /// Runs a program off the main thread and returns its combined stdout and stderr.
  /// The program gets SIGTERM if it outlives `timeout` or the calling task is cancelled,
  /// so a hung `launchctl` cannot leave the app stuck in a busy state.
  static func run(
    _ path: String,
    _ args: [String],
    stdin: String? = nil,
    timeout: TimeInterval = 30
  ) async -> ShellResult {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    let out = Pipe()
    p.standardOutput = out
    p.standardError = out
    let input = Pipe()
    p.standardInput = input

    return await withTaskCancellationHandler {
      await withCheckedContinuation { cont in
        // Reading the pipe blocks, so it runs on a GCD thread instead of the cooperative pool.
        DispatchQueue.global().async {
          do {
            try p.run()
          } catch {
            cont.resume(returning: ShellResult(status: -1, output: "\(path): \(error.localizedDescription)"))
            return
          }
          let watchdog = DispatchWorkItem { if p.isRunning { p.terminate() } }
          DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)

          if let stdin { input.fileHandleForWriting.write(Data(stdin.utf8)) }
          try? input.fileHandleForWriting.close()
          let data = out.fileHandleForReading.readDataToEndOfFile()
          p.waitUntilExit()
          watchdog.cancel()

          var output = String(decoding: data, as: UTF8.self)
          if p.terminationReason == .uncaughtSignal {
            output += "\n\(path) was killed by signal \(p.terminationStatus)."
          }
          cont.resume(returning: ShellResult(status: p.terminationStatus, output: output))
        }
      }
    } onCancel: {
      // terminate() raises an exception on a process that has not launched.
      if p.isRunning { p.terminate() }
    }
  }
}
