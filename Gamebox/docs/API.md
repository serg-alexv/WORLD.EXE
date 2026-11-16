# Local protocol v1

Every privileged request uses `Authorization: Bearer <token>`; tokens never belong in URLs or logs. Mutations use `Content-Type: application/json`. The expected Host is the actual 127.0.0.1 listener and port. No browser CORS origin is admitted. No arbitrary names, emails, profiles, GPS or text payloads are accepted.

| Route | Authority | Contract |
|---|---|---|
| GET /healthz | Local | Readiness only; no player or credential details |
| GET /v1/status | Operator | Aggregate counts, limits and control revision |
| POST /v1/control | Operator | `{expectedRevision, commandID, mode}`; mode running/paused/draining |
| POST /v1/rooms | Operator | Empty object; creates a bounded synthetic arena |
| DELETE /v1/rooms/{roomID} | Operator | Invalidates room sessions and invitations |
| POST /v1/rooms/{roomID}/invitations | Operator | Empty object; single-use admission, at most 60 seconds |
| POST /v1/rooms/{roomID}/join | Admission | `{invitation, consent:{multiplayer:true, spatialSharing:false}}` |
| POST /v1/rooms/{roomID}/inputs | Room player | `{seq,kind,vector?}`; move/fire/reload; increasing integer sequence |
| GET /v1/rooms/{roomID}/snapshot | Room player | Authoritative local metre coordinates, health/ammo/ack, synthetic obstacles |
| GET /v1/rooms/{roomID}/events | Room player | Authenticated SSE snapshot stream; one stream per player |
| POST /v1/rooms/{roomID}/signals | Operator | Synthetic adapter only, exact event contract below |
| DELETE /v1/session | Player | Revokes presence and token, closes its stream on the next pump |

Move vectors are ground-plane inputs, with length at most one; the server converts them into a bounded per-tick displacement. Fire vectors provide a direction, never a client-reported hit. One accepted input per tick is allowed. Invalid inputs do not consume sequence numbers or partially mutate state. Cooperative humans cannot damage each other. These are intentionally small reference mechanics; no competitive ranking or cheat-resistance certification is claimed.

Example **synthetic** signal shape (times are Unix milliseconds supplied at runtime):

```json
{"schemaVersion":1,"eventID":"unique-game-event","source":"synthetic","observedAt":100000,"expiresAt":110000,"kind":"pressure","intensity":2}
```

`kind` is pressure or supply; intensity is an integer 0–3. Events older than 60 seconds, more than one second in the future, expired events, excess fields, unapproved sources, duplicate live IDs and capacity overflow are rejected. Pressure is temporary; supply is an immediate bounded ammunition change. The deduplication horizon is the live event TTL, not indefinite event-history storage.

## Unimplemented production contracts

Internet transport, third-party identity/age assurance, matchmaking, durable rooms, multi-worker/global idempotency, geographic routing, reconnect/resume, host migration, native iOS encoding/decoding conformance, shared AR frame qualification, UDP/QUIC transport, billing, moderation and cloud deployment are not implemented by this API. Do not expose the reference listener through a tunnel or reverse proxy and label it production.
