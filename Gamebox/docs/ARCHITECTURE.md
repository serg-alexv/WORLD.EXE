# Gamebox architecture and reconciliation

## Product contract

WORLD.EXE becomes a gamebox for original, opt-in, local-spatial cooperative/tactical games. The unit of play is a match; the unit of online scaling is an authoritative match shard. One operator controls policy and deployment gates, not every individual simulation. Players and fictional NPCs are game actors. Non-participants, dating profiles and people inferred from app proximity never become shooter targets.

## Existing implementation retained

The Fusion source at `26fadfb9aa57f121c6139d27db001ab206ea94e8` already contains Training/Signal Siege, CONTACT researcher/operator pairing, RoomPlan/LiDAR views, optional local GGUF inference and a separately modeled encrypted personal-feed workspace. `ContactPeer` currently allows one selected peer, requires invitation/host acceptance and encrypted Multipeer Connectivity. It is a two-device prototype, not an arbitrary-size mesh. The personal feed is a separate module/vault within the same app container/process, not an OS security sandbox. No route from that vault into game state or inference has been added.

The historical README's “no combat, multiplayer” text describes the original training slice, not every later Fusion feature. Physical paired AR, user comfort and outside-player experience still need their own evidence. Prior CI receipts do not prove those gates.

## New executable boundary

`source → strict SignalPipe → normalized game signal → authoritative room → snapshots`

`authenticated admission + explicit consent → ephemeral player session → validated input → authoritative combat`

`operator credential → revisioned control → running / draining / paused`

Signals use an exact allowlist of numeric/enumerated fields and expire quickly. There is no arbitrary URL fetching, raw text execution or pass-through object merge. Tokens are random, stored as hashes in the active host, expire, and are scoped to a room. A client cannot choose another actor ID, submit coordinates, damage/health or replay an old input. Shot origin, movement speed, ammunition, cooldown, collision and damage are owned by the server. The current game is cooperative: humans cannot damage humans.

The local transport binds only to 127.0.0.1, checks Host, rejects browser Origin requests, caps requests/bodies/connections/streams, and closes revoked or backpressured streams. This is a development transport, NOT an internet-facing gateway. HTTP+SSE is a contract/test harness; regional low-latency transport remains a future qualification item.

## AR and networking separation

Three spaces must not be conflated: device-local AR coordinates, a versioned shared-match frame, and geographic coordinates. The new arena implements only local-match metre coordinates. Existing CONTACT's transform checks and explicit geometry consent remain separate. The next native integration must bind a validated room frame and tracking epoch to the authoritative snapshot. Tracking loss, frame disagreement or unsafe movement must pause physical play. No raw camera or room geometry is uploaded by this backend.

ARKit collaborative mapping exchanges spatial information; it does not supply global matchmaking, cheat prevention or a million-player authority. Current Apple documentation limits the older Multipeer browser/session cohort to eight including the local peer and marks that API deprecated in favor of Network framework. Preserve the working paired prototype; place any new transport behind an explicit interface and qualify it on two physical phones before generalization.

## AI boundary

The deterministic director makes bounded move/fire/reload choices over game state. Existing native Qwen/GGUF can later provide bounded narrative or proposed tactical intent, but is NOT connected to this backend. No LLM belongs in the authoritative frame loop. Imported text is data, never operator or agent instructions. A future model must receive only approved game-state fields; outputs must pass enumerated intent validation, latency/token quotas and a deterministic fallback. No cloud request can currently be made by this package.

## Provider integration

“Visible in an app” is not an export/API authorization. Hornet's published service terms require express written permission for automated access. We have not verified a public, licensed live gameplay stream. Beta testing status is not treated here as an API grant. Provider access stays disabled until a documented authorized surface, permitted purposes, all necessary subject consent, retention/deletion rules and a tested revocation path exist. A user's personal archive may contain other people's information: importing it into the private workspace does not authorize multiplayer redistribution.

Do not triangulate users, copy profiles/photos/messages, infer orientation, send raw provider records to NPC models, repurpose private feedback as content or bypass login/PIN/MFA. Future partner integration should supply purpose-built game-safe events for participating users, not a feed of bystanders. Even aggregation requires a privacy assessment; a numeric threshold alone is not a proof of anonymity.

## Scaling path — design, not deployed infrastructure

Start with this bounded process and a two-phone native acceptance. Introduce a managed identity gateway and authoritative match allocation for a small approved online pilot; only then move to regional shards, managed persistence, shared admission/rate budgets, durable event delivery, health-based routing, load shedding and independently tested recovery. The operator needs an authenticated control surface, a proven rollback, incident runbooks, cost controls and restore drills before public scale.

No Kubernetes cluster, cloud account, managed service or paid capacity has been created. A million monthly users is not a million simultaneous players. For an ASSUMED 2% peak concurrency, 1,000,000 monthly users gives 20,000 concurrent players; at 32 per match this means at least 625 full match slots, or 813 slots with 30% headroom. Occupancy, traffic, bot density, latency and hosting cost need measurement. `worldctl capacity` makes assumptions explicit and reports measured production capacity as null.

## Primary references checked 2026-11-16

- Apple, Creating a collaborative session: https://developer.apple.com/documentation/arkit/creating-a-collaborative-session
- Apple, maximumNumberOfPeers: https://developer.apple.com/documentation/multipeerconnectivity/mcbrowserviewcontroller/maximumnumberofpeers
- Hornet/HornetX published Terms of Service: https://hornetx.com/pt/terms-of-service (English text; section 4(n) on automated access).
- Hornet, requesting personal data: https://hornetnetworks.zendesk.com/hc/en-us/articles/31333277569810-How-do-I-request-a-copy-of-my-personal-data

These references describe platform/provider boundaries, not permission granted to WORLD.EXE.
