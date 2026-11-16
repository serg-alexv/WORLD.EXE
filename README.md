# WORLD.EXE — Fusion demo

**0.5.0 Arena candidate:** native synthetic tabletop combat, optional local AR mesh occlusion, explicit two-player pairing, and a bounded [development team](DevTeam/README.md). See [Arena acceptance](docs/ARENA_DEMO.md). This source is not a TestFlight availability receipt. The delivered 0.4.0 (8.1) baseline is preserved.

**0.4.0 delivered feature set:** one launcher for Training/Signal Siege, CONTACT, spatial sensors, optional local GGUF and the authenticated personal-feed workspace. See [FUSION_DEMO](docs/FUSION_DEMO.md) for the current build boundary and phone acceptance. Actual TestFlight availability is established by the release receipt, not this source heading.

The integrated personal workspace is a separate Swift module and encrypted vault **in the same app process/container**, not an OS sandbox. No private-record route to game, NPC, inference, scores or sensor journals is connected. The independently buildable PersonalFeed app below remains available as a source target; it is not the distribution identity for the combined release. Hornet/Grindr live APIs are not connected.


## Gamebox control-plane development

The [Gamebox reference service](Gamebox/README.md) adds configurable authoritative tactical rooms, deterministic bots, authenticated HTTP/SSE, synthetic event ingestion, and persistent pause/drain controls. It is a **local headless backend**, not a replacement TestFlight release and not yet connected to the native AR renderer. The delivered Fusion 0.4.0 (8.1) remains the baseline.

Live Hornet/Grindr integrations remain disabled. Private Feed records, precise locations, real people and raw room meshes cannot enter this service. Provider permission, independently assessed consent/data rights, native-client wiring, physical-device testing, internet transport and production qualification remain explicit gates. See [architecture](Gamebox/docs/ARCHITECTURE.md), [API](Gamebox/docs/API.md), [acceptance](Gamebox/docs/ACCEPTANCE.md), and [operations](Gamebox/docs/OPERATIONS.md).

## Independent product boundaries

| Product | Build entrypoint | Data boundary |
| --- | --- | --- |
| WORLD.EXE game / sensors | `project.yml`, scheme `WorldEXE` | `WorldCore`, `EvidenceCore`, `LocalLlama`; existing game identity |
| Personal Feed demo | `PersonalClient/project.yml`, scheme `PersonalFeed` | `FeedDomain`, `FeedAdapters`, `FeedStore`; independent app/container/key |

The [personal-client refactor](docs/PERSONAL_FEED.md) adds an isolated native demo for explicit personal-data import and user-owned HTTPS feeds. It does not connect a live Hornet account or reuse private records in the game. PersonalClient does not share an App Group, model runtime, observations or leaderboards with WORLD.EXE. `bash scripts/personal_feed_ci.sh` validates its own source/storage/UI/device target without signing or changing the published game.

The sections below describe the existing WORLD.EXE game, not the personal client.

**0.2.0 source milestone:** paired researcher/operator mission and actual local GGUF inference.
See [CONTACT_TESTBED](docs/CONTACT_TESTBED.md) for the agreed gameplay, room/AR coordinate contract, pairing, model setup and hardware acceptance.

On one phone: **КОНТАКТ · вдвоём → Демонстрация / один экран**. Switch roles to inspect three symbols, power/tune nodes, stabilize them and extract the capsule. This is clearly marked simulation.

On two phones: researcher makes a fresh Room scan, explicitly consents to geometry sharing and hosts a local pair; operator joins using the displayed code and researcher confirmation. Both continue, then researcher places the capsule in AR on a safe horizontal surface. Only the researcher needs LiDAR. Archived room JSON is not treated as a live AR map.

**GGUF · интеллект:** import a trusted full GGUF or explicitly download the pinned Qwen3 0.6B Q8_0 (~640 MB, Wi-Fi), load it into memory and request a local reply. Stop, unload and delete are separate controls. There is no cloud inference fallback. In-game model advice cannot execute a game command. Default model is optional; weights are never in git or the IPA.

## Build
macOS/Xcode 26.3 + XcodeGen + CMake:
```sh
bash scripts/prepare_llama.sh
bash scripts/build_and_test.sh
```
`bash scripts/llama_smoke.sh` downloads the pinned model for a real native-bridge inference/cancellation/unload test with network denied during execution. Models are excluded from CI artifacts. Existing training/compact core tests remain enabled.

Release status is established by the GitHub release receipt and App Store Connect, not by this source milestone description. Physical paired networking, AR alignment/occlusion and iPhone Metal performance must be tested on actual devices.

## Existing training and sensors

A native iOS 18+ exploration prototype: original procedural 3D graphics, a complete tactical training mission, and separate real spatial-sensing modes. Built with SwiftUI, SceneKit, ARKit and RoomPlan. Bundle identifier: `org.worldexe.prototype`; Xcode scheme: `WorldEXE`.

## Play the expedition

Open **Training → Begin expedition**. Tap an open tile to preview a route, or use **Plot** to select an affordable waypoint toward the next objective. **Confirm Move** advances the squad. Teal route markers fit the remaining action points; amber markers exceed them.

Movement costs one AP per tile. Recover each of the three amber relics for one AP, return to the teal landing pad, then **Extract** for one AP. **End Turn** restores six AP. There is no turn limit. The success screen offers replay; Reset returns to the briefing. Zoom changes the camera, not the mission.

Training is explicitly simulated and needs neither a camera nor LiDAR. Progress uses a validated 19-byte binary payload with a version and corruption checksum; existing JSON saves migrate on read. A destination is committed before its movement animation; interrupted animations do not lose the move. Invalid saves return to a fresh briefing.

## Scan the real room

**LiDAR** checks actual ARKit scene-reconstruction support before enabling Start. It displays mesh-anchor wireframes over the camera, capped at 128 chunks. Pause, leaving the mode, and app inactivity stop the live session. It does not save LiDAR meshes.

**Room scan** uses RoomPlan with explicit Start, Stop and Reset controls. A completed capture can be inspected through an orthographic camera and shared as JSON, metadata and USDZ. Floors, walls, openings and furniture retain their estimated meter dimensions and transforms. Zero-thickness surfaces receive a 2 cm rendering thickness, not a fabricated measurement.

Room archives are local and excluded from backups. Each capture is written into its own directory; an atomic manifest publishes the completed archive only after its files exist. Failure retains the previous archive. Per-capture delegate tokens reject obsolete callbacks after reset or replacement. Metadata records the source, units and processing time.

Camera permission is requested only when starting a sensor mode. Denied or unavailable sensors do not block Training. Captured rooms and game terrain remain separate: this version does **not** infer a playable tactical map from a room scan.

## Build and validate

On a Mac with Xcode 26.3 and XcodeGen:

```sh
bash scripts/build_and_test.sh
```

The entrypoint runs `scripts/ci.sh`: core tests, project generation, an available iOS 18+ simulator, UI tests, an unsigned device compilation, screenshots and validation receipts. `WorldEXE.xcodeproj` is generated from `project.yml`. The icon is original and reproducibly generated without external assets.

The pure Swift tests cover shortest paths, blocked/unreachable/out-of-bounds destinations, AP costs, atomic rejection, the full mission, extraction gates, reset and save validation. UI tests cover help/reset and a complete mission through the real on-screen controls, with retained screenshots. CI stages have separate statuses and bounded simulator/test execution.

GitHub Actions retains logs, `.xcresult`, screenshots, the generated Xcode project, a simulator app, and a clearly labeled **unsigned** device app. Only a successful receipt for the relevant commit establishes those checks passed. Simulator evidence does not validate physical sensors or human comfort.

## Distribution

The manual **TestFlight release** workflow is restricted to main and runs validation before signing. It requires app-specific Apple registration/profile and protected environment credentials; it creates an ephemeral signing keychain and verifies the exported archive. `upload=true` explicitly requests uploading. Apple processing and TestFlight group access must be checked afterward.

Current Apple provisioning observations and the exact permission gate are in [DEPLOYMENT_STATUS](docs/DEPLOYMENT_STATUS.md). Source code, an unsigned app, and an accepted upload are not interchangeable with an available TestFlight build. Rhea RF Spanner is independent and must not be modified.

## Original training slice (historical scope)

This paragraph describes the original training slice, not the later CONTACT, Signal Siege, or Gamebox modules: one deterministic mission; no combat, multiplayer, RF measurements or biological readings. Room rendering uses element bounding boxes. Room export is synchronous and needs physical-device performance testing. Real LiDAR, RoomPlan accuracy/export, background interruptions, permissions, thermal behavior and touch comfort require testing on a supported iPhone. There are no third-party models, game assets, analytics SDKs or backend services in this slice.

## Compact implementation

See [PERFORMANCE](docs/PERFORMANCE.md) for bounded pathfinding, binary saves, reusable render resources, mesh-copy bounds, verification and reproducible host benchmarks. Performance claims remain separate from physical-device measurements.
