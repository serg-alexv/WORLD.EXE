# WORLD.EXE — The Hollow Orbit

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

## Prototype scope

One deterministic mission; no combat, multiplayer, RF measurements or biological readings. Room rendering uses element bounding boxes. Room export is synchronous and needs physical-device performance testing. Real LiDAR, RoomPlan accuracy/export, background interruptions, permissions, thermal behavior and touch comfort require testing on a supported iPhone. There are no third-party models, game assets, analytics SDKs or backend services in this slice.

## Compact implementation

See [PERFORMANCE](docs/PERFORMANCE.md) for bounded pathfinding, binary saves, reusable render resources, mesh-copy bounds, verification and reproducible host benchmarks. Performance claims remain separate from physical-device measurements.
