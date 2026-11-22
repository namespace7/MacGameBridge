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
case "games":
    GameCatalog.printGames()
case "help", "--help", "-h":
    print("""
    MacGameBridge — Apple Silicon Windows gaming compatibility lab

    Usage:
      macgamebridge diagnostics          Inspect this Mac
      macgamebridge diagnostics --json   Emit machine-readable JSON
      macgamebridge games                List configured game profiles
      macgamebridge help                 Show this help

    Diagnostics are read-only. Runtime detection does not prove that a runtime
    can launch a particular game. No games, runtimes, or drivers are installed.
    """)
default:
    fputs("Unknown command: \(command)\nRun 'macgamebridge help'.\n", stderr)
    exit(2)
}
