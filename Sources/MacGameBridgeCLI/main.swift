import Foundation
import MacGameBridgeCore

let arguments = Array(CommandLine.arguments.dropFirst())
let command = arguments.first ?? "help"

switch command {
case "diagnostics":
    let report = Diagnostics.collect()
    if arguments.contains("--json") {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(report)
            print(String(decoding: data, as: UTF8.self))
        } catch {
            fputs("Could not encode diagnostics: \(error)\n", stderr)
            exit(1)
        }
    } else {
        Diagnostics.printHumanReadable(report)
    }
case "runtimes":
    let report = RuntimeDiscovery.discover(paths: .current)
    if arguments.contains("--json") {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(report)
            print(String(decoding: data, as: UTF8.self))
        } catch {
            fputs("Could not encode runtime discovery: \(error)\n", stderr)
            exit(1)
        }
    } else {
        RuntimeDiscovery.printHumanReadable(report)
    }
case "games":
    GameCatalog.printGames()
case "help", "--help", "-h":
    print("""
    MacGameBridge — Apple Silicon Windows gaming compatibility lab

    Usage:
      macgamebridge diagnostics          Inspect this Mac
      macgamebridge diagnostics --json   Emit host diagnostics as JSON
      macgamebridge runtimes             Discover compatibility runtimes
      macgamebridge runtimes --json      Emit runtime inventory as JSON
      macgamebridge games                List configured game profiles
      macgamebridge help                 Show this help

    Discovery is read-only. Finding a runtime does not prove that it can launch
    a particular game. MacGameBridge does not install software, modify bottles,
    download games, or bypass DRM/anti-cheat.
    """)
default:
    fputs("Unknown command: \(command)\nRun 'macgamebridge help'.\n", stderr)
    exit(2)
}
