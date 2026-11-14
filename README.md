# WORLD.EXE — The Hollow Orbit

A native iOS 18+ exploration prototype using SwiftUI, SceneKit, ARKit and RoomPlan. Bundle: `org.worldexe.prototype`. Xcode scheme: `WorldEXE`. Swift language mode: 5. No external dependencies or network services.

## Play

Choose **Training**, then **Begin expedition**. Training is explicitly simulated and works without camera access, including on the iOS simulator. The fixed sector has seed 731, ten blocking pillars, three amber relics, a teal squad marker and a landing pad at grid (4,8).

Tap an open tile to preview its shortest route. Teal route dots fit your remaining action points; amber dots exceed them. **Confirm Move** animates the squad along the route. Each tile costs 1 AP. On an amber relic tile, **Recover** costs 1 AP. **End Turn** restores 6 AP with no turn limit. Recover all three relics, return to the landing pad and **Extract** for 1 AP. Replay begins another expedition. Reset returns to the briefing. The help button explains controls and sensors. Camera zoom and reset do not affect mission state.

Commands persist a validated, versioned Codable mission in local UserDefaults. A move commits its destination before animation, so leaving mid-animation restores the destination. Invalid or incompatible saves reset safely to a briefing. UI tests pass `-ui-testing` to disable mission persistence for that process.

## Sensors

**LiDAR** independently checks ARKit mesh support and requests camera permission only on Start. It displays real ARMeshAnchor wireframes over the live camera. Pause, mode changes and app inactivity release the session. The display is capped at 128 mesh chunks and skips oversized chunks. It does not save LiDAR meshes. Unsupported and denied states leave Training available.

**Room scan** independently checks RoomCaptureSession support. Start runs RoomCaptureView; Stop ends capture and lets its view delegate receive a processed CapturedRoom. There is no custom or assumed Done button. The most recent completed room remains available across mode changes and relaunches. The isometric archive uses the original column-major transforms and meter dimensions for walls, doors, windows, openings and furniture. Zero-thickness surfaces receive a 2 cm display thickness. Estimated room geometry is labeled separately and does not become simulated mission terrain.

Room archives live under the app's Application Support/WorldEXE-Room directory, excluded from backups. JSON contains RoomPlan's encoded CapturedRoom; USDZ uses parametric export. Share opens the native share sheet. Reset scan deletes the local archive and exports, independently of training. Geometry stays local unless the user shares it. Export/permission/session errors are visible, with session diagnostics in OSLog under `org.worldexe.prototype`.

## Build and validation

On macOS with Xcode 26.3, an iOS 18+ simulator runtime and XcodeGen installed:

```sh
swift test --package-path WorldCore
bash scripts/build_and_test.sh
```

Optional explicit destination:

```sh
DESTINATION='platform=iOS Simulator,name=iPhone 17' bash scripts/build_and_test.sh
```

The script generates the Xcode project and runs scheme WorldEXE's UI tests. Pure Swift package tests cover shortest paths, obstacle detours, unreachable/blocked/out-of-bounds destinations, AP accounting and atomic rejection, mission completion/extraction gates, reset and Codable validation. UI smoke tests cover training, help, turn controls and reset without asserting sensor hardware.

No builds or tests were executed by the text-only code generation session. macOS CI must validate compilation and simulator behavior. Verify actual camera permission flows, LiDAR mesh rendering, RoomPlan processing/export, interruptions, mode changes, background cleanup, and share-sheet behavior separately on supported physical devices. A simulator build does not verify sensors.

## Scope and limitations

This slice has one deterministic mission, unlimited turns, no combat and one retained room archive. Captured-room rendering uses bounding boxes for RoomPlan elements rather than detailed USDZ meshes. Room capture/export are bounded to 512 display elements; parametric USDZ generation runs synchronously after processing and can briefly occupy the main thread. Very large rooms and tablet orientation changes need physical-device review. SceneKit is accepted here as a prototype dependency. The app has no production icon assets yet.

Compile-sensitive integration points for the supervisor are RoomCaptureViewDelegate processing callbacks, RoomCaptureSessionDelegate SDK annotations, ARKit mesh-buffer conversion, and XcodeGen's local package linkage. Swift 5 mode avoids Swift 6 strict-concurrency enforcement while UI state changes remain on the main queue. No GitHub workflow files are changed.
