# Ring Dominion — PvP Multiplayer Conversion

Reality check on scope first: this is a 1v1, 2-fighter, single-arena game with a small,
well-defined state (`x, vx, hp, guard, sp, state, timer, block, combo`). That's a *good*
netcode target — don't reach for rollback netcode or a full ECS. Colyseus with
server-authoritative simulation + client-side prediction is the right amount of machinery
for an MVP that can later scale.

---

## 1. Architecture Overview

```
┌─────────────┐        WebSocket (Colyseus protocol)        ┌──────────────────┐
│   Browser    │◄────────────────────────────────────────►│   Game Server     │
│  (Three.js   │   joins room, sends inputs, receives       │   (Node.js +      │
│   renderer)  │   authoritative state patches @ 20-30Hz    │    Colyseus)      │
└─────────────┘                                              └────────┬─────────┘
                                                                       │
                                                              ┌────────▼─────────┐
                                                              │  Matchmaker /     │
                                                              │  Lobby service    │
                                                              │  (Colyseus        │
                                                              │  matchMaker API)  │
                                                              └────────┬─────────┘
                                                                       │
                                                    ┌──────────────────▼──────────────────┐
                                                    │  Redis (presence, room registry,     │
                                                    │  matchmaking queue, rank data)        │
                                                    └──────────────────┬──────────────────┘
                                                                       │
                                                              ┌────────▼─────────┐
                                                              │  Postgres         │
                                                              │  (accounts, ELO,  │
                                                              │  match history)    │
                                                              └───────────────────┘
```

- **One process type does double duty in the MVP**: a Node/Colyseus server hosts both the
  matchmaker (via Colyseus's built-in `matchMaker` API) and the fight rooms themselves.
  Split them into separate services later, not on day one.
- **Redis** backs Colyseus's presence/driver so multiple server instances can share
  room state and matchmaking queues — this is what makes horizontal scaling possible
  without a rewrite.
- **Postgres** is off the hot path entirely — it's only touched at match start (load
  profile/rank) and match end (write result). Never in the per-tick loop.

---

## 2. Multiplayer Roadmap (realistic order)

| Phase | Goal | Cut from MVP |
|---|---|---|
| **0. Extract the sim** | Pull `updateCombat`, `applyDamage`, `updateFightHUD`'s data deps into a pure module with no DOM/Three.js calls, usable both client and server. This is the single highest-leverage step — skip it and you'll duplicate combat logic and it *will* drift. | — |
| **1. Local 2-player over Colyseus (LAN test)** | One room, two clients, server runs the extracted sim authoritatively, replaces `updateAI(dt)` with a second real input stream. | Matchmaking, ranking |
| **2. Client-side prediction + reconciliation** | Client applies its own inputs immediately (feels instant), replays on correction. Opponent is interpolated from snapshots. | Rollback, lag comp for hit reg |
| **3. Reconnect** | Colyseus `allowReconnection`, session token survives refresh/network blip, grace window ~20s. | Reconnect mid-combo-freeze polish |
| **4. Matchmaking + ranking** | Simple queue matching by rank proximity + wait-time widening. ELO/Glicko-lite. | Skill-based regional routing |
| **5. Anti-cheat basics** | Server-authoritative damage/HP (already true by construction), input-rate limiting, sanity bounds, no client-reported state trusted. | Full replay-based fraud detection |
| **6. Scale out** | Multiple server processes behind Redis presence, room sharding, autoscaling on room count. | Multi-region |

Don't build phase 4+ before phase 1–3 work over a real network with induced latency —
test with Chrome DevTools throttling (150ms+ RTT) early, not at the end.

---

## 3. Networking Model

**Server-authoritative simulation, client-side prediction for the local player,
interpolation for the remote player. Inputs over the wire, not raw state.**

Why this over alternatives:
- **Full client-authoritative (send state, not inputs)** — trivial to cheat (client just
  sets `hp: 0` on the opponent), rejected outright by your anti-cheat requirement.
- **Lockstep** — both clients simulate identically off synced inputs, no server sim
  needed. Works, but any desync (float drift, timing) breaks the match with no
  authority to correct it, and it doesn't give you a natural anti-cheat backstop. Also
  couples the two clients' frame timing tightly — worse for mobile with variable frame
  rates.
- **Full rollback (GGPO-style)** — best *feel* for a fighting game, but real
  implementation cost (deterministic sim, state snapshrun/replay every frame,
  input delay tuning) is high for an MVP and Colyseus doesn't give you this for free.
  Revisit only if this ships and player feedback specifically calls out input feel.

**What you're actually building**: the server runs the same `updateCombat(dt)` you
already have, on a fixed tick (e.g. 30Hz using Colyseus's `setSimulationInterval`),
driven by buffered inputs from both clients. Each client:
- Applies its *own* inputs locally the instant they happen (prediction) so punches feel
  instant, not "send and wait."
- Receives authoritative snapshots and reconciles: if the server's version of "you"
  diverges from what you predicted, snap/interpolate to the correction.
- Renders the *opponent* from interpolated snapshots only (no prediction needed there —
  you don't control them, so there's nothing to predict), buffered ~100ms behind
  "now" to smooth jitter.

---

## 4. Server Stack

- **Node.js + Colyseus** (your stated preference, and it's the right call here —
  Colyseus gives you rooms, state sync via schema diffing, matchmaker API, and
  reconnection support out of the box, instead of hand-rolling a WebSocket protocol).
- **@colyseus/schema** for the synced state — binary delta encoding, only changed
  fields go over the wire each tick. This matters a lot on mobile data.
- **Redis** via `@colyseus/redis-driver` + `@colyseus/redis-presence` once you run more
  than one server process (needed for phase 6, harmless to add early).
- **Postgres** (or any relational store) for accounts, rank, match history — accessed
  only outside the hot path.
- **uWebSockets.js transport** (`@colyseus/uwebsockets-transport`) instead of the
  default Express/ws transport once you care about latency/throughput — drop-in swap,
  meaningfully lower overhead per connection.

---

## 5. Synchronization Method

- **Tick rate**: server sim at 20–30Hz (fighting-game-relevant precision without
  overloading mobile connections). Render at 60fps client-side regardless — interpolate
  between the last two authoritative ticks for smooth motion between snapshots.
- **State sync**: Colyseus schema (`@colyseus/schema`) — define `FighterState`
  (x, vx, hp, guard, sp, state, timer, block, combo) ×2 and `MatchState` (timeLeft,
  round, phase). Colyseus diffs and sends only what changed, per client, automatically.
- **Input sync**: client sends discrete input messages (`move`, `punch`, `kick`,
  `block_start`, `block_end`, `dodge`, `special`), each tagged with a client-generated
  sequence number and the client's local timestamp — not continuous state. Server
  timestamps on arrival and applies at the next tick.
- **Reconciliation**: client keeps a short ring buffer of its own recent inputs +
  predicted states. On each authoritative snapshot, compare to the buffered predicted
  state at that sequence number; if it diverges beyond a small epsilon, snap to server
  state and replay buffered inputs since that point.

---

## 6. Lag Compensation

Fighting games live or die on hit-confirm feel, so this deserves specific treatment
beyond generic interpolation:

- **Favor the attacker, bounded**: when resolving whether a punch/kick/special landed,
  the server can rewind the *defender's* position by the attacker's measured RTT/2 (up
  to a cap, e.g. 120ms) when checking `distanceP2O() <= RANGE[state]`, similar to
  hitscan lag comp in shooters. Cap it hard — uncapped rewind is exploitable and feels
  awful for the defender ("shot behind cover").
- **Input delay over rewind for the common case**: simpler and often *better feeling*
  for a slower-paced (non-frame-perfect) fighter than yours — buffer local input by a
  small fixed delay (e.g. 2–3 ticks, ~66–100ms) before applying it even locally, so both
  players' actions land against roughly the same world-state on the server. Start here;
  add defender-rewind only if playtesting shows attacker inputs feel unresponsive at
  higher pings.
- **Never trust client-reported hit results.** The client can render its own hit
  animations optimistically, but `applyDamage` and `finishRound` only ever execute
  server-side, from the server's own `distanceP2O()` check. This is also your primary
  anti-cheat lever (see below) — it falls out of doing lag comp correctly.

---

## 7. State Management

- **Server**: single source of truth. One `FightRoom` instance per match holds the
  authoritative `MatchState`. No shared mutable state across rooms — each room is
  independent, which is exactly what makes horizontal scaling trivial (spread rooms
  across processes/machines, no cross-room coordination needed for a 1v1 game).
- **Client**: three separate concerns, don't conflate them —
  1. **Predicted local state** — used for immediate rendering of your own fighter.
  2. **Authoritative snapshot buffer** — last N server states, used for reconciliation
     and for rendering the opponent (interpolated).
  3. **Presentation state** — the existing `poseFighter()` / Three.js layer, which
     should keep reading from a single `combat.p` / `combat.o`-shaped object like today;
     only *how that object gets filled* changes (prediction+reconciliation instead of
     local AI/physics).
- Keep the render layer (`poseFighter`, HUD updates) completely unaware of networking —
  it already reads plain `{x, state, timer, hp, guard, block}` objects, which is exactly
  the shape both predicted-local and interpolated-remote state should keep producing.
  This is why extracting the sim (Phase 0) pays off: everything downstream of it stays
  unchanged.

---

## Matchmaking Flow

```
Client: "find match" ──► POST/WS to matchmaker
                             │
                             ▼
                    Add {playerId, rank, ts} to Redis sorted-set queue
                             │
                    ┌────────┴────────┐
                    │  Matcher loop    │  (runs every ~1s, or event-driven)
                    │  - pop lowest ts │
                    │  - find nearest  │
                    │    rank within   │
                    │    widening      │
                    │    window        │
                    └────────┬────────┘
                             │ match found
                             ▼
              colyseus matchMaker.createRoom('fight', {p1, p2})
                             │
                             ▼
        Both clients get {roomId, sessionToken} ──► connect via room.join()
```

- **Rank-proximity widening**: start matching within ±50 rank points, widen by ~25
  every 5s unmatched, cap at "match anyone" after ~30s — standard, avoids both unfair
  matches and long queues.
- **ELO/Glicko-lite** is enough; don't build a full Glicko-2 with rating deviation
  decay for an MVP — simple ELO (`K=32`, adjust on win/loss) gets you a working ladder.
- Ticket/token handed to the client on match so `room.join()` isn't guessable/spoofable
  — this is also your reconnection credential (see below).

---

## Reconnect System

Colyseus has this largely built in — use it rather than hand-rolling:

```js
// server: on client disconnect
async onLeave(client, consented) {
  if (consented) return; // deliberate leave, don't hold the seat
  try {
    this.state.getFighter(client.sessionId).connected = false;
    const reconnection = await this.allowReconnection(client, 20 /* seconds */);
    this.state.getFighter(client.sessionId).connected = true;
  } catch (e) {
    // grace period expired — treat as forfeit
    this.handleForfeit(client.sessionId);
  }
}
```

- **Freeze combat, don't forfeit immediately** — pause `combat.timeLeft` countdown
  while a player is in the reconnection grace window so a dropped connection doesn't
  cost them the round on top of the disconnect.
- **Client persists `{roomId, sessionId, reconnectionToken}`** (memory + `sessionStorage`
  equivalent — not literal `localStorage`/`sessionStorage` inside a Colyseus room, but
  your app shell can hold it) and calls `client.reconnect(roomId, sessionId)` on
  reload/network-recovery.
- **Forfeit after grace period** — write the match result, release the room, refund/adjust
  rank per your rules (e.g. no rank loss for the disconnector's opponent beyond normal win).

---

## Anti-Cheat Basics (realistic for MVP, not exhaustive)

1. **Server owns all outcomes.** Damage, HP, KO, round results are computed only from
   server-side `distanceP2O()`/state, never from a client-sent "I hit you" message.
   This single rule kills the large majority of naive cheats.
2. **Input validation, not just relay.** Reject/clamp inputs that imply impossible
   values — move input outside `[-1,1]`, action requests during `LOCKED_STATES`,
   special-move requests when `sp < 100` server-side (not just client-side gating).
3. **Rate limiting per connection.** Cap input messages/sec (e.g. 60) — catches input
   spam/macro abuse without needing behavioral heuristics.
4. **Sequence numbers on inputs**, monotonically increasing per client — reject
   replayed/out-of-order packets outright.
5. **Server-side timers for cooldowns/specials**, mirrored from but not trusted from the
   client's `sp`/`timer` fields — the client's copy is for prediction/rendering only.
6. This gets you real coverage against the common cheats (damage/HP hacks, speed hacks,
   cooldown skips) without building a behavioral-analysis pipeline — that's a
   post-launch investment, not an MVP one.

---

## Deployment Recommendations

- **Colyseus Cloud** or a plain **Docker container behind a Node process on
  Fly.io/Render/a small VPS** for MVP — don't stand up Kubernetes for a 1v1 fighting
  game on day one.
- **Sticky routing by room, not by player** — Colyseus's matchmaker already returns a
  specific room's process/port; make sure your load balancer/proxy (nginx, or the
  platform's) supports WebSocket upgrade and doesn't round-robin an established
  connection.
- **TLS-terminated `wss://`** even for the MVP — plain `ws://` will get blocked/flagged
  by mobile browsers and networks increasingly often.
- **Static frontend (the HTML/Three.js client) on a CDN** (Cloudflare Pages, Netlify,
  S3+CloudFront) — fully decoupled from the game server, scales independently and free.
- **Deploy server instances close to your player base first** (single region) —
  multi-region matchmaking is a phase-6+ problem, not MVP.

---

## Scaling Strategy

- **Rooms are the unit of scale** — each `FightRoom` is independent (1v1, no shared
  world state), so scaling out is "run more Colyseus processes, share presence via
  Redis" — no sharding logic to write yourself.
- **Colyseus `@colyseus/redis-presence` + `@colyseus/redis-driver`** let multiple
  server processes/machines share the matchmaker's view of available rooms — add this
  the moment you run more than one instance, not before.
- **Horizontal autoscaling on concurrent-room count**, not CPU alone — a fight room is
  cheap CPU-wise per room but you'll hit connection/socket limits per process before
  CPU limits typically.
- **Postgres read replicas** only once match-history/profile reads under matchmaking
  load actually show up as a bottleneck — premature to add for MVP traffic.
- **Regional server pools** behind a matchmaker that picks the lowest-latency pool per
  player (measured via a quick ping-probe on matchmaking start) — this is the first
  真正 scale step worth doing after single-region works, since latency (not player
  count) is what breaks fighting-game feel first.

---

## What NOT to build for the MVP

- Rollback netcode — input-delay + server authority is enough for this game's pace.
- Full ECS / ticked ordering framework — you have two fighters, not a battle royale.
- Regional matchmaking — single region first.
- Behavioral anti-cheat / ML fraud detection — server authority covers the realistic
  threat model for launch.
- Kubernetes — one good Colyseus process (or a few, behind Redis presence) is plenty
  until you have real concurrent-match numbers to justify it.
