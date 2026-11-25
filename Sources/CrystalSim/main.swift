import Darwin
import Foundation

setbuf(stdout, nil)
setbuf(stderr, nil)

let arguments = CommandLine.arguments
if arguments.count == 2 && arguments[1] == "--version" {
    print("bochoy-grinder-emulator \(AppVersion.current)")
    exit(0)
}

if arguments.contains("--help") {
    print(AppOptions.usage)
    exit(0)
}

if arguments.contains("--permission-probe") {
    guard arguments.count == 2 else {
        FileHandle.standardError.write(Data("ERROR: --permission-probe cannot be combined with other options\n\n\(AppOptions.usage)\n".utf8))
        exit(1)
    }
    let probe = PermissionProbe()
    RunLoop.main.run()
    _ = probe
} else {
    do {
        let options = try AppOptions.parse(arguments)
        let app = try AppController(options: options)
        app.start()
        RunLoop.main.run()
    } catch {
        FileHandle.standardError.write(Data("ERROR: \(error.localizedDescription)\n\n\(AppOptions.usage)\n".utf8))
        exit(1)
    }
}
