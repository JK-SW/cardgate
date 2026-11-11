// Takes the screenshots for scripts/screenshots.sh: the ScreenshotTests UI test (sandboxed, so it
// cannot write files here) asks for each picture with a distributed notification; this captures
// the frontmost window of the app without its shadow and answers when the file is written.
// Usage: swift scripts/screenshot-server.swift <output directory> <app bundle>
import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 3 else { fatalError("usage: screenshot-server.swift <output directory> <app bundle>") }
let output = URL(filePath: arguments[1], directoryHint: .isDirectory)
let executable = URL(filePath: arguments[2]).appending(path: "Contents/MacOS/CardGate").path

let request = Notification.Name("io.github.jk-sw.cardgate.screenshots.request")
let done = Notification.Name("io.github.jk-sw.cardgate.screenshots.done")

/// The frontmost on-screen window of the process (the list is ordered front to back).
func frontWindow(pid: pid_t) -> Int? {
    let windows =
        CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        as? [[String: Any]] ?? []
    return windows.first {
        ($0[kCGWindowOwnerPID as String] as? Int) == Int(pid)
            && ($0[kCGWindowAlpha as String] as? Double ?? 0) > 0
            && ($0[kCGWindowLayer as String] as? Int ?? 0) < 25
    }?[kCGWindowNumber as String] as? Int
}

func capture(_ name: String) {
    let app = NSWorkspace.shared.runningApplications.last { $0.executableURL?.path == executable }
    guard let pid = app?.processIdentifier, let window = frontWindow(pid: pid) else {
        print("no window of the app for \(name)")
        return
    }
    let process = Process()
    process.executableURL = URL(filePath: "/usr/sbin/screencapture")
    process.arguments = ["-x", "-o", "-l", "\(window)", output.appending(path: "\(name).png").path]
    try? process.run()
    process.waitUntilExit()
    print("captured \(name)")
}

setvbuf(stdout, nil, _IOLBF, 0)  // the script waits for "ready" in the log
let center = DistributedNotificationCenter.default()
center.addObserver(forName: request, object: nil, queue: .main) { note in
    guard let name = note.object as? String, name.allSatisfy({ $0.isLetter || $0 == "-" }) else { return }
    capture(name)
    center.postNotificationName(done, object: name, userInfo: nil, deliverImmediately: true)
}
print("ready")
RunLoop.main.run()
