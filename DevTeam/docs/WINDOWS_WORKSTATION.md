# Laptop as the control workstation

Use native PowerShell, Git, GitHub CLI, Node and Python for orchestration and portable tests. Use the existing WSL distribution only for workloads that actually need Linux; do not start Docker or multiple local models merely to create a dashboard of processes. Private model state, provider sessions, correspondence and execution receipts belong under `WORLD.EXE-ops`, never the repository or its source snapshots.

The initial inspected WD machine has Windows 11 Pro, approximately 16 GiB RAM and Intel integrated graphics. Treat free memory as a changing measurement. Run one model at a time and retain the current two-thread/one-small-GGUF ceiling until a real memory/latency measurement supports a change. Avoid global package upgrades, Defender exclusions, disk repartitioning or shared WSL memory changes as prerequisites.

Xcode remains a macOS dependency. The Windows laptop is the control plane; the existing app-specific GitHub macOS workflow compiles, tests and signs iOS artifacts. A Windows Swift or Node test is not an iOS build, and an iOS Simulator run is not a physical-device measurement. Keep the app identity `org.worldexe.prototype`, Apple app `6834963735`, and the existing protected signing environment. Never borrow or alter Rhea resources.

## Operator sequence

`doctor` → immutable source task → proposal → independent review → portable tests → native CI → inspected artifact → explicitly authorized TestFlight release → Apple processing and exact group availability check → physical-device playtest.

Only the last independent checks establish device behavior and availability. Source recovery is not validation, and no part of this sequence establishes a real outside-player review by itself.

## Recovery

The existing five-minute code-only snapshots preserve approved source, not credentials or runtime state. Export private receipts separately through an authorized private backup route; do not add them to Git to make recovery convenient. Rebuild CLI tools from pinned manifests, verify model/binary hashes, and reauthenticate using normal provider login. Never reconstruct sessions by extracting browser cookies.

Official references: Microsoft Windows developer tools and Task Scheduler 2.0 documentation; Apple Xcode SDK/system requirements; GitHub Copilot CLI permission controls; Gemini CLI policy/headless documentation; Hugging Face cache verification; llama.cpp upstream CLI documentation.
