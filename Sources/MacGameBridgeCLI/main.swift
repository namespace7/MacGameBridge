import Foundation

let command = CommandLine.arguments.dropFirst().first ?? "help"

switch command {
case "diagnostics":
    Diagnostics.run()
case "games":
    GameCatalog.printGames()
case "help", "--help", "-h":
    print("""
    MacGameBridge — Apple Silicon Windows gaming compatibility lab

    Usage:
      macgamebridge diagnostics   Inspect this Mac's gaming prerequisites
      macgamebridge games         List configured game test profiles
      macgamebridge help          Show this help

    This initial release only diagnoses the host. It does not install runtimes,
    modify system settings, download games, or bypass DRM/anti-cheat.
    """)
default:
    fputs("Unknown command: \(command)\nRun 'macgamebridge help'.\n", stderr)
    exit(2)
}
