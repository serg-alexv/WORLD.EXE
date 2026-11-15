# WORLD.EXE — CONTACT testbed

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

**Training → Signal Siege** adds an original 7×7 tactical challenge: four AP per turn,
cover and line of sight, deterministic sentry patrol/fire, a forecasted hazard, relay
recovery and extraction, victory/defeat and replay. Its top-10 rankings stay on this
device, separated by seed and difficulty, with validated versioned command receipts
and duplicate-session protection. Mica's fictional NPC panel uses scripted offline
dialogue until a GGUF is explicitly loaded and requested through the existing Qwen
setup. See [rules, persistence and validation limits](docs/SIGNAL_SIEGE.md).

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

## Prototype scope

The exploration expedition, CONTACT and Signal Siege are distinct simulated mission modes. Signal Siege adds deterministic tactical combat; no game state establishes RF measurements or biological readings. Room rendering uses element bounding boxes. Room export is synchronous and needs physical-device performance testing. Real LiDAR, RoomPlan accuracy/export, background interruptions, permissions, thermal behavior and touch comfort require testing on a supported iPhone. Optional GGUF weights are installed explicitly; no model weights, third-party game assets, analytics SDKs or ranking backend are bundled.

## Compact implementation

See [PERFORMANCE](docs/PERFORMANCE.md) for bounded pathfinding, binary saves, reusable render resources, mesh-copy bounds, verification and reproducible host benchmarks. Performance claims remain separate from physical-device measurements.
