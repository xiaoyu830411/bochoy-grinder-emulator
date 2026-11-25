import Foundation
import CrystalCore

@MainActor
final class ConsoleOutput {
    private let humanHandle: FileHandle
    private let jsonHandle: FileHandle?
    private let ownsJSONHandle: Bool

    init(jsonLogPath: String?) throws {
        if jsonLogPath == "-" {
            humanHandle = .standardError
            jsonHandle = .standardOutput
            ownsJSONHandle = false
            return
        }
        humanHandle = .standardOutput
        if let jsonLogPath {
            let path = NSString(string: jsonLogPath).expandingTildeInPath
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            jsonHandle = handle
            ownsJSONHandle = true
        } else {
            jsonHandle = nil
            ownsJSONHandle = false
        }
    }

    func event(_ event: SimEvent) {
        write(EventLog.humanLine(event), to: humanHandle)
        if let jsonHandle {
            do {
                write(try EventLog.jsonLine(event), to: jsonHandle)
            } catch {
                write("JSON_LOG_ERROR \(error.localizedDescription)", to: .standardError)
            }
        }
    }

    func command(_ text: String) {
        write(text, to: humanHandle)
    }

    private func write(_ text: String, to handle: FileHandle) {
        guard let data = (text + "\n").data(using: .utf8) else { return }
        do {
            try handle.write(contentsOf: data)
        } catch {
            FileHandle.standardError.write(Data("OUTPUT_ERROR \(error.localizedDescription)\n".utf8))
        }
    }

    deinit {
        if ownsJSONHandle {
            try? jsonHandle?.close()
        }
    }
}
