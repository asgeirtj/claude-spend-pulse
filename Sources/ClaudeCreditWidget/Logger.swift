import Foundation
import os.log

enum WidgetLog {
    private static let osLog = OSLog(subsystem: "com.arpan.ClaudeCreditWidget", category: "main")
    private static let queue = DispatchQueue(label: "com.arpan.ClaudeCreditWidget.log")

    static let logFileURL: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/ClaudeCreditWidget", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("widget.log")
    }()

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func log(_ message: String, file: String = #fileID, line: Int = #line) {
        let timestamp = isoFormatter.string(from: Date())
        let shortFile = (file as NSString).lastPathComponent
        let entry = "[\(timestamp)] [\(shortFile):\(line)] \(message)\n"
        os_log("%{public}@", log: osLog, type: .info, message)
        queue.async {
            let data = Data(entry.utf8)
            if FileManager.default.fileExists(atPath: logFileURL.path) {
                if let handle = try? FileHandle(forWritingTo: logFileURL) {
                    defer { try? handle.close() }
                    do {
                        try handle.seekToEnd()
                        try handle.write(contentsOf: data)
                    } catch {
                        // give up silently — better than crashing
                    }
                }
            } else {
                try? data.write(to: logFileURL)
            }
        }
    }
}
