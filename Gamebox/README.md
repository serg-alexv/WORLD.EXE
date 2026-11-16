# WORLD.EXE Gamebox — executable control-plane and combat reference

**Qualification: local reference implementation. Not production-ready, not a new TestFlight release, and not a physical AR shooter acceptance.** The delivered mobile baseline remains Fusion 0.4.0 (8.1). This package does not modify the iOS app or its private feed module.

This slice implements a configurable, dependency-free Node service: authoritative flat-floor 3D combat, cooperative human players versus deterministic bots, bounded synthetic event ingestion, authenticated HTTP commands and server-sent snapshots, one-use room admission, consent revocation, admission limits, leases, and persistent operator pause/drain controls. The game simulation uses local metre coordinates, not geographic locations. AI here means deterministic game-agent decisions; no cloud LLM or dating provider is connected.

## Run the verified path

Use Node 22.16+ or Node 24. No npm installation is required.

```sh
cd Gamebox
npm test
node tools/worldctl.mjs validate
node tools/worldctl.mjs demo
node tools/worldctl.mjs benchmark --rooms 32 --players 8 --ticks 200
node tools/worldctl.mjs capacity --mau 1000000 --peak-fraction 0.02 --players 32
```

`demo` is a headless, in-process exercise. The test suite separately exercises two independent HTTP clients and the SSE stream. Neither is an iPhone playtest. Benchmark output reports its synthetic workload and exclusions; it must not be described as production CCU capacity.

## One-operator controls

```sh
node tools/worldctl.mjs serve --state-dir /private/worldexe-ops/gamebox-runtime
# In another terminal, with the same state directory and configuration:
node tools/worldctl.mjs status --state-dir /private/worldexe-ops/gamebox-runtime
node tools/worldctl.mjs resume --state-dir /private/worldexe-ops/gamebox-runtime
node tools/worldctl.mjs drain --state-dir /private/worldexe-ops/gamebox-runtime
node tools/worldctl.mjs pause --state-dir /private/worldexe-ops/gamebox-runtime
```

On WD use `C:\Users\wheel\WORLD.EXE-ops\gamebox-runtime`. The default is the user's private `.worldexe-gamebox` directory outside the repository. A local operator token is generated only when `serve` is explicitly run and no existing token/environment value is present. It is stored privately and never printed. On Windows, protect that directory using the owner's NTFS ACLs; POSIX mode bits are not a Windows ACL guarantee. Do not put tokens, private feedback, captures or exports into Git or CI artifacts.

A fresh service starts **paused**. `resume` opens local admissions. `drain` blocks new rooms/admissions while existing sessions continue. `pause` freezes simulation and rejects inputs/signals. Controls use a revision precondition and idempotency ID, persist before acknowledgement, and survive an ordinary restart. Match/session state is deliberately ephemeral: restart terminates rooms and invalidates player tokens. The state-file writer uses an exclusive lock; after a crash, verify no writer exists before an operator removes a stale lock. No automatic lock stealing.

## Configuration boundaries

`config/demo.json` is the validated runtime manifest. Adjust tick rate, room/player limits, bot count, leases, the synthetic source switch and loopback port. Invalid or extra fields fail validation. The snapshot of the App Store identity is an isolation guard, not a mechanism for modifying Apple resources.

The only implemented connector is **synthetic**. Hornet, Grindr, private-vault routing, raw-mesh upload, geographic coordinates, non-player targeting, cloud inference and automatic deployment are explicitly blocked. Setting those booleans to true is rejected; it does not create a licensed API integration. A real provider adapter requires documented provider permission, consent and an independent data-boundary review before implementation.

See [architecture](docs/ARCHITECTURE.md), [API contract](docs/API.md), [acceptance gates](docs/ACCEPTANCE.md) and [operations](docs/OPERATIONS.md).
