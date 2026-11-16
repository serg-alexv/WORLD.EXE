# Observations, technical telemetry and gameplay

## Dependency boundary

`EvidenceCore` is a Foundation-only SwiftPM target, independent of `WorldCore`, ARKit, RoomPlan and any model runtime. Authoritative gameplay never reads or mutates this journal. App adapters append three distinct record types. Generated text remains an advisory interpretation in the UI and has no sensor-record representation.

| Lane | Actual contents | Not included |
| --- | --- | --- |
| Observations | RoomPlan element-count summaries; ARKit mesh-chunk counts and tracking estimates; source, origin, capture ID and timing | Raw/calibrated ranging claims, scores, fictional nodes, LLM text |
| Telemetry | Native inference token count, whole-request duration and outcome, model digest; requested backend; local transport byte counts; thermal/memory/background events; capture duration | Prompt/response text, packet contents, peer identity, invented FPS, RAM, RTT or actual GPU utilization |
| Gameplay | Training state-change events; CONTACT accepted/rejected commands, virtual placement and peer state; revision and score | Physical-world claims and mutation of sensor archives |

Room geometry and full RoomPlan JSON/USDZ remain in independent sensor archives. The new journal stores bounded metadata, not another mesh or camera-frame copy. `restoredArchive` keeps the original processing date; it is not a fresh scan. `peerReport` identifies a remote assertion, not a locally verified observation. New CONTACT capture provenance fields are optional for compatibility with existing packets. Synthetic demo geometry is not accepted as a real-room welcome packet.

`estimate` is explicit. This prototype does not expose a calibrated physical-measurement record. UUIDs, schema checks and source tags establish application provenance, not cryptographic proof of the external world.

## Time and measurement semantics

Every record has a fresh ID, local journal session, increasing sequence, UTC wall date and `elapsedSeconds` from the start of that journal. Sequence and monotonic elapsed time determine local order; changing the wall clock does not reorder records. `sensorElapsedSeconds`, when present, is relative to the observer's first AR frame, not raw system uptime, UTC or a synchronized peer clock. Raw monotonic origins are not exported.

The privacy manifest declares SystemBootTime reason `35F9.1` for measuring intervals between app events. Only such intervals are logged/exported. See Apple's required-reason API documentation: https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype

Inference duration includes native prompt evaluation and decoding. Tokens per whole-request second are not decode-only speed or first-token latency. Missing/failed native counters remain null rather than fabricated zeros. `requestedBackend = metal` is not proof of Metal execution: `confirmedBackend` stays null until actual backend instrumentation exists. Local packet acceptance is not remote delivery or round-trip time. RAM, frame rate and GPU utilization are not measured by this patch.

## Retention and privacy

There are 128 entries per lane in fixed-capacity rings; oldest records are evicted with per-lane counters. App writes are debounced to once per second on a serial utility queue with atomic file replacement. Current and one previous launch are kept locally and excluded from backups. Abrupt termination can lose the final pending second. No automatic upload, no journal transmission to a game peer.

The recording toggle does not pause gameplay. Clearing one current journal does not reset missions, delete a room or remove GGUF weights. Previous-session exports remain separate. Explicit export creates `observations.json`, `telemetry.json`, `gameplay.json` and `session.json`; the last is an envelope with separate arrays, schema and eviction counts. Camera frames, audio, prompts and generated prose are never journal fields.

## Acceptance tests

Portable tests validate lane/type mismatches, source/payload agreement, archive and peer provenance, rejection of fictional/model-as-sensor data, finite/ranged metrics, null/zero duration behavior, bounded retention and ring order, duplicate sequence/session rejection, scoped clearing, relative clocks, schema decoding and byte limits. App unit tests exercise actual controllers, separate exports, demo packet rejection and independence of journal clearing/recording from mission state. UI tests cover discoverability, separate lanes and preserving the played turn after a journal clear. Python guards verify module dependencies, absence of model text from the telemetry sink, the privacy declaration and test-target registration.

Existing full gameplay, CONTACT, native GGUF network-denied smoke, GGUF UI and signed-release identity tests remain enabled. Simulator validation does not establish physical sensor accuracy, actual GPU execution or a successful two-phone session. Test fresh scanning, archive restore, real inference logging, local networking, background behavior and explicit sharing on device.
