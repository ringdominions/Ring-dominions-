/**
 * network.js — drop-in networking layer for Ring Dominion.
 *
 * Replaces the single-player `updateAI(dt)` + local physics in `updateCombat(dt)`
 * with a networked opponent. The rest of the game (poseFighter, HUD, hit VFX)
 * keeps reading `combat.p` / `combat.o` exactly as before — this module's job is
 * only to keep those two objects correctly filled from the network.
 *
 * Load Colyseus client via CDN before this file:
 *   <script src="https://cdnjs.cloudflare.com/ajax/libs/colyseus.js/0.16.0/colyseus.min.js"></script>
 */

const RingDominionNet = (() => {
  const SERVER_URL = window.RD_SERVER_URL || 'ws://localhost:2567';
  const INTERP_DELAY_MS = 100; // render remote player ~100ms behind "now" to smooth jitter
  const RECONCILE_EPSILON = 0.05; // world units of divergence before we correct

  let client = null;
  let room = null;
  let mySessionId = null;
  let inputSeq = 0;

  // Ring buffer of recently-sent inputs, for reconciliation replay.
  const pendingInputs = [];
  // Buffer of recent authoritative snapshots for the remote fighter, for interpolation.
  const remoteSnapshots = []; // [{ t, x, vx, hp, guard, sp, state, timer, block, combo }]

  let onStateReady = null; // callback(localFighterId, remoteFighterId) once both joined

  async function connect({ roomId, sessionToken, fighterId }) {
    client = new Colyseus.Client(SERVER_URL);
    room = roomId
      ? await client.reconnect(roomId, sessionToken)
      : await client.joinOrCreate('fight', { fighterId });

    mySessionId = room.sessionId;
    persistSession();

    room.onStateChange((state) => {
      const fighters = [...state.fighters.values()];
      const remote = fighters.find(f => f.sessionId !== mySessionId);
      const local = fighters.find(f => f.sessionId === mySessionId);
      if (!local || !remote) return;

      reconcileLocal(local);
      pushRemoteSnapshot(remote);

      if (onStateReady) { onStateReady(local.fighterId, remote.fighterId); onStateReady = null; }
    });

    room.onLeave((code) => {
      // consented leave (code 1000) vs. drop — the reconnect UI decision lives in game.js
      window.dispatchEvent(new CustomEvent('rd:disconnected', { detail: { code } }));
    });

    room.onError((code, message) => {
      console.error('Room error', code, message);
    });

    return room;
  }

  function persistSession() {
    // NOTE: do not use localStorage/sessionStorage inside an artifact context.
    // In a real deployed client (not the Claude artifact preview) this is fine;
    // here, keep the token in memory and pass it through your own app shell/router
    // if you need it to survive a full page reload.
    window.__rdSession = { roomId: room.id, sessionToken: room.reconnectionToken };
  }

  // ---- outgoing input: sent immediately, applied locally immediately (prediction) ----
  function sendInput(type, value) {
    if (!room) return;
    const seq = ++inputSeq;
    const msg = { type, value, seq };
    room.send('input', msg);
    pendingInputs.push({ ...msg, sentAt: performance.now() });
    if (pendingInputs.length > 240) pendingInputs.shift(); // ~8s at 30Hz, plenty
    return seq;
  }

  // ---- reconciliation for the LOCAL fighter ----
  // `localFighter` here is the same object your game already mutates in
  // updateCombat() for prediction (combat.p). We only correct it when the server
  // disagrees beyond epsilon — otherwise we leave client prediction alone so
  // input feels instant.
  function reconcileLocal(serverFighter) {
    // Drop acknowledged inputs.
    while (pendingInputs.length && pendingInputs[0].seq <= serverFighter.lastProcessedInputSeq) {
      pendingInputs.shift();
    }

    const local = window.combat && window.combat.p;
    if (!local) return;

    const divergence = Math.abs(local.x - serverFighter.x);
    const hpMismatch = local.hp !== serverFighter.hp;

    if (divergence > RECONCILE_EPSILON || hpMismatch) {
      // Snap authoritative fields the client can't safely predict (hp/guard/combo —
      // these depend on hit resolution, which only the server computes).
      local.x = serverFighter.x;
      local.vx = serverFighter.vx;
      local.hp = serverFighter.hp;
      local.guard = serverFighter.guard;
      local.sp = serverFighter.sp;
      local.combo = serverFighter.combo;
      // state/timer for attack animations are allowed to keep running locally
      // if already predicted correctly — only hard-override on bigger mismatches
      // (e.g. server says 'hurt' but we don't know it yet).
      if (serverFighter.state !== local.state && LOCKED_STATE(serverFighter.state)) {
        local.state = serverFighter.state;
        local.timer = serverFighter.timer;
      }
      // Replay of movement-only inputs since the correction point is intentionally
      // omitted here for simplicity — with input-delay (see architecture doc §6)
      // instead of pure client-side dead-reckoning, corrections this small are rare
      // and a snap is imperceptible. Add replay if playtesting shows rubber-banding.
    }
  }

  function LOCKED_STATE(s) { return s === 'hurt' || s === 'dizzy' || s === 'roped'; }

  // ---- interpolation for the REMOTE fighter ----
  function pushRemoteSnapshot(serverFighter) {
    remoteSnapshots.push({
      t: performance.now(),
      x: serverFighter.x, vx: serverFighter.vx,
      hp: serverFighter.hp, guard: serverFighter.guard, sp: serverFighter.sp,
      state: serverFighter.state, timer: serverFighter.timer,
      block: serverFighter.block, combo: serverFighter.combo,
    });
    // Keep ~1s of history — enough to interpolate at INTERP_DELAY_MS with margin.
    const cutoff = performance.now() - 1000;
    while (remoteSnapshots.length > 2 && remoteSnapshots[0].t < cutoff) remoteSnapshots.shift();
  }

  // Call this every render frame (from your existing animate() loop) to fill
  // combat.o with a smoothly interpolated remote state.
  function sampleRemote(targetObj) {
    if (remoteSnapshots.length < 2) {
      if (remoteSnapshots.length === 1) Object.assign(targetObj, remoteSnapshots[0]);
      return;
    }
    const renderTime = performance.now() - INTERP_DELAY_MS;
    let i = remoteSnapshots.length - 1;
    while (i > 0 && remoteSnapshots[i - 1].t > renderTime) i--;
    const a = remoteSnapshots[Math.max(0, i - 1)];
    const b = remoteSnapshots[i];
    const span = b.t - a.t || 1;
    const t = Math.max(0, Math.min(1, (renderTime - a.t) / span));

    targetObj.x = a.x + (b.x - a.x) * t;
    targetObj.vx = b.vx;
    targetObj.hp = b.hp; targetObj.guard = b.guard; targetObj.sp = b.sp;
    targetObj.combo = b.combo; targetObj.block = b.block;
    // Discrete fields (state/timer driving animation) snap to the latest sample —
    // interpolating "punch" and "idle" doesn't mean anything, only position does.
    targetObj.state = b.state;
    targetObj.timer = b.timer;
  }

  // ---- public API mirroring the existing input handlers (joystick, ctl-btn taps) ----
  return {
    connect,
    onReady(cb) { onStateReady = cb; },
    move(value) { sendInput('move', value); },
    punch() { sendInput('punch'); },
    kick() { sendInput('kick'); },
    blockStart() { sendInput('block_start'); },
    blockEnd() { sendInput('block_end'); },
    dodge() { sendInput('dodge'); },
    special() { sendInput('special'); },
    sampleRemote,
    get connected() { return !!room; },
    get sessionId() { return mySessionId; },
    disconnect() { room && room.leave(true); },
  };
})();

window.RingDominionNet = RingDominionNet;
