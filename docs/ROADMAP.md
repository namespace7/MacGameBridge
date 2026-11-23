# Roadmap

## M0 — Repository and host baseline
- [x] Swift package skeleton
- [x] Read-only host diagnostics command
- [x] Initial game profile catalog
- [ ] Verify Rosetta x86-64 execution after installation
- [ ] Record current exact free disk space

## M1 — Diagnostics hardening
- [ ] Parse free storage into structured output
- [ ] Detect Metal/GPU information
- [ ] Emit machine-readable JSON report
- [ ] Add unit tests

## M2 — Runtime discovery
- [ ] Detect installed Wine/CrossOver/GPTK tools
- [ ] Report versions and paths
- [ ] No automatic installation yet

## M2.4 — Runtime selection integration
- [x] Shared host capability detection with injectable system probes
- [x] Diagnostics reuses the shared host detection
- [x] Read-only integration service wiring discovery to the pure selector
- [x] `runtimes --select` and `runtimes --select --json` CLI commands
- [x] Host detection, selection integration, and report JSON tests
- [x] Architecture documentation

## M3 — Isolated game environments
- [ ] Define bottle/prefix model
- [ ] Runtime adapter protocol
- [ ] Safe launch configuration
- [ ] Per-game logs

## M4 — Compatibility database
- [ ] Versioned test records
- [ ] Offline/online split
- [ ] Evidence and reproducibility fields

## M5 — Benchmarking
- [ ] FPS/frame-time capture where available
- [ ] Memory and process metrics
- [ ] Repeatable test protocol

## M6 — SwiftUI desktop interface
- [ ] Library view
- [ ] Per-game settings
- [ ] Diagnostics and compatibility reports
