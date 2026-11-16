# Compact core — bounded data, measured trade-offs

This pass preserves mission rules and public coordinates. It does not quantize RoomPlan measurements or invent device performance.

## Representation

| Item | Payload | Scope |
|---|---:|---|
| Blocked-cell mask | 16 bytes | Two UInt64 words covering 81 cells |
| BFS scratch | 162 bytes | 81 UInt8 predecessors plus 81 UInt8 queue entries |
| Mission save | 19 bytes | Versioned little-endian record, including CRC32 |

These are payload sizes, not total heap usage or app RSS. The returned route, framework objects, stack/register overhead and allocator metadata are separate. Swift temporary storage may use stack or heap; no zero-heap promise is made.

The BFS has O(V+E) time with V=81, uses no visited hash table or path-prefix queue, preserves N/E/S/W tie-breaking, initializes its entire temporary buffer, and never lets pointers escape. The parent sentinel also tracks visitation. Coordinates are range-checked before integer indexing. Extra blocked cells outside the sector are ignored, matching the reference behavior.

Save layout: `WE` (2), version (1), phase (1), cell index (1), three relic bits (1), AP (1), UInt64 turn (8), CRC32 (4). Legacy JSON saves migrate on read. CRC32 detects accidental corruption, not tampering/authenticity. The full representable turn counter is retained; there is no lossy truncation.

## Rendering and sensor copies

Route calculation is memoized by start/goal. Preview markers use a lazily grown reusable pool and two shared geometries rather than rebuilding nodes/materials on each update. Exhaustive path tests establish a maximum of 16 markers for the current map; unused markers are retained, trading a small bounded footprint for lower allocation churn. ARKit vertex copies cover only the referenced vertex range; index and vertex buffers are checked before copying. SceneKit/Metal total memory and peak temporary copies still require device profiling.

## Verification and reproducibility

Six compact-core tests add exhaustive comparison of all 6,561 cell pairs, 2,000 deterministic extra-obstacle queries, mask boundaries, invalid coordinates, whole-mission binary round trips, all 152 single-bit corruptions of a 19-byte record, legacy JSON and maximum turn-counter checks.

An isolated Linux x86_64 / Swift 6.2.1 kernel harness passed 8,561 equivalence cases under AddressSanitizer (exit 0). Its preliminary timings are not claims about an iPhone. The repository harness runs independently on CI using the actual current core: `bash scripts/benchmark_core.sh`. It alternates implementation order, warms both kernels, checks results, reports seven-trial medians for `-O` and `-Osize`, records binary section sizes, and preserves compressed compiler-generated assembly. Shared-CI timings are informational, not pass thresholds.

Release app targets use `-Osize`, whole-module optimization and dead-code stripping. No `-Ounchecked`, disabled validation, handwritten assembly, model download or extra dependency was introduced. The benchmark explicitly exposes the speed/size trade-off instead of claiming every compiler setting improves both.

Physical-device allocation profiling, frame-time percentiles, temperature, battery consumption, and real LiDAR/RoomPlan tests remain separate acceptance gates.
