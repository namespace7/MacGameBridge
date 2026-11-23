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
    if arguments.contains("--select") {
        let report = RuntimeSelectionIntegration.collect()
        if arguments.contains("--json") {
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(report)
                print(String(decoding: data, as: UTF8.self))
            } catch {
                fputs("Could not encode runtime selection report: \(error)\n", stderr)
                exit(1)
            }
        } else {
            RuntimeSelectionIntegration.printHumanReadable(report)
        }
    } else if arguments.contains("--providers") {
        let report = RuntimeScanner.scan(paths: .current)
        if arguments.contains("--json") {
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(report)
                print(String(decoding: data, as: UTF8.self))
            } catch {
                fputs("Could not encode runtime provider report: \(error)\n", stderr)
                exit(1)
            }
        } else {
            printProviderReport(report)
        }
    } else {
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
    }
case "environments":
    do {
        let output = try EnvironmentCLI.run(Array(arguments.dropFirst()))
        print(output, terminator: "")
    } catch let error as EnvironmentCLIError {
        fputs("\(error.description)\n", stderr)
        exit(error.exitCode)
    } catch {
        fputs("Error: \(error)\n", stderr)
        exit(1)
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
      macgamebridge runtimes --providers Discover and validate runtime providers
      macgamebridge runtimes --providers --json
                                         Emit provider report as JSON
      macgamebridge runtimes --select    Discover runtimes and select the best eligible one
      macgamebridge runtimes --select --json
                                         Emit structured selection report as JSON
      macgamebridge environments list [--json]
                                         List recorded environments
      macgamebridge environments create --game <id> --name <name> --prefix <path> [--json]
                                         Save planned environment metadata only
      macgamebridge environments show <id> [--json]
                                         Show one environment record
      macgamebridge environments validate <id> [--json]
                                         Read-only metadata validation
      macgamebridge games                List configured game profiles
      macgamebridge help                 Show this help

    Discovery, selection, and environment validation are read-only. No runtime or
    game binary is launched. Finding a runtime does not prove that it can launch
    a particular game. Creating an environment saves metadata only; it does not
    create a prefix. MacGameBridge does not install software, modify bottles,
    download games, or bypass DRM/anti-cheat.
    """)
default:
    fputs("Unknown command: \(command)\nRun 'macgamebridge help'.\n", stderr)
    exit(2)
}

// MARK: - Provider report printing

private func printProviderReport(_ report: RuntimeProviderReport) {
    print("MacGameBridge — Runtime providers")
    print(String(repeating: "=", count: 38))
    print("Mode: read-only; no runtime was launched or modified.\n")

    guard !report.installations.isEmpty else {
        print("No providers detected.")
        return
    }

    for installation in report.installations {
        print("\(installation.displayName) [\(installation.provider.rawValue)]")
        print("  Status: \(installation.status.rawValue)")

        if let bundle = installation.bundleURL {
            print("  Bundle: \(bundle.path)")
        }
        if let wine = installation.wineExecutableURL {
            print("  Wine:   \(wine.path)")
        }
        if let server = installation.wineserverExecutableURL {
            print("  Server: \(server.path)")
        }
        if let version = installation.version {
            print("  Version: \(version)")
        }
        print("  Architecture: \(installation.architecture.displayName)")

        for item in installation.evidence {
            print("  Evidence: \(item)")
        }
        print("")
    }

    print("Important: validation inspects file metadata without running any")
    print("binary. A validated runtime may still not launch a particular game.")
}