import Foundation
import CrystalCore
import CrystalWeb

struct AppOptions {
    var scenario: Scenario
    var jsonLogPath: String?
    var webEndpoint: WebEndpoint?
    var webToken: String?

    static let usage = """
    Usage:
      bochoy-grinder-emulator [--scenario <file.json>] [--name <CRYSTAL-XXXX>] [--json-log <file.jsonl|->] [--web <host:port>]
      bochoy-grinder-emulator --permission-probe
      bochoy-grinder-emulator --version

    Options:
      --scenario       Load a version-1 JSON scenario (defaults to built-in normal behavior).
      --name          Override the advertised name; suffix must be four uppercase hex digits.
      --json-log      Append structured events to a JSON Lines file, or use '-' for stdout.
      --web           Start same-process HTTP/SSE control on <host:port> (default disabled).
                      Non-loopback binding requires CRYSTAL_WEB_TOKEN.
      --permission-probe  Verify Bluetooth authorization/service publication/advertising, then exit.
      --version       Print the release version and exit without starting services.
      --help          Show this help.
    """

    static func parse(_ arguments: [String]) throws -> AppOptions {
        var scenarioPath: String?
        var jsonLogPath: String?
        var deviceName: String?
        var webAddress: String?
        var index = 1
        while index < arguments.count {
            let argument = arguments[index]
            func value() throws -> String {
                index += 1
                guard index < arguments.count else { throw OptionError.missingValue(argument) }
                return arguments[index]
            }
            switch argument {
            case "--scenario": scenarioPath = try value()
            case "--name": deviceName = try value()
            case "--json-log": jsonLogPath = try value()
            case "--web": webAddress = try value()
            default: throw OptionError.unknownArgument(argument)
            }
            index += 1
        }

        var scenario: Scenario
        if let scenarioPath {
            scenario = try Scenario.load(from: URL(fileURLWithPath: NSString(string: scenarioPath).expandingTildeInPath))
        } else {
            scenario = .default
        }
        if let deviceName {
            scenario.deviceName = deviceName
        }
        scenario = try scenario.validated()
        let endpoint = try webAddress.map(WebEndpoint.parse)
        let token = ProcessInfo.processInfo.environment["CRYSTAL_WEB_TOKEN"]
        if let endpoint {
            try WebSecurityPolicy(bindHost: endpoint.host, token: token).validateConfiguration()
        }
        return AppOptions(
            scenario: scenario,
            jsonLogPath: jsonLogPath,
            webEndpoint: endpoint,
            webToken: token
        )
    }
}

enum OptionError: Error, LocalizedError {
    case missingValue(String)
    case unknownArgument(String)

    var errorDescription: String? {
        switch self {
        case .missingValue(let option): return "Missing value for \(option)"
        case .unknownArgument(let argument): return "Unknown argument: \(argument)"
        }
    }
}
