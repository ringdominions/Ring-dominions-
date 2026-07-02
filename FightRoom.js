const { Room } = require('colyseus');
const { FightRoomState, FighterState } = require('../schema/FightState');

const TICK_RATE = 30; // Hz — server sim tick. Render stays 60fps client-side via interpolation.
const TICK_MS = 1000 / TICK_RATE;
const ARENA_EDGE = 4.3;
const ROUND_TIME = 60;
const MAX_INPUTS_PER_TICK = 4; // basic rate limit — see anti-cheat notes

// Ported 1:1 from the single-player game's RANGE table / attack durations.
const RANGE = { punch: 1.3, kick: 1.55, special: 1.9 };
const ATTACK_DURATION = { punch: 0.32, kick: 0.44, special: 0.7 };
const LOCKED_STATES = new Set(['hurt', 'dizzy', 'roped']);

function makeFighter(sessionId, fighterId) {
  const f = new FighterState();
  f.sessionId = sessionId;
  f.fighterId = fighterId;
  f.x = sessionId === '__p1__' ? -1.6 : 1.6; // placeholder, real value set on join
  f.hp = f.hpMax = 100;
  f.guard = f.guardMax = 100;
  return f;
}

class FightRoom extends Room {
  onCreate(options) {
    this.setState(new FightRoomState());
    this.maxClients = 2;

    // Per-session pending input queue — filled by onMessage, drained each tick.
    this.inputQueues = new Map();     // sessionId -> [{type, payload, seq, clientTs}]
    this.orderedSessionIds = [];      // stable [p1SessionId, p2SessionId]

    this.onMessage('input', (client, msg) => this.handleInput(client, msg));

    this.setSimulationInterval(() => this.tick(TICK_MS / 1000), TICK_MS);
  }

  onJoin(client, options) {
    const fighterId = options.fighterId || 'rex';
    const fighter = makeFighter(client.sessionId, fighterId);
    fighter.x = this.orderedSessionIds.length === 0 ? -1.6 : 1.6;

    this.state.fighters.set(client.sessionId, fighter);
    this.inputQueues.set(client.sessionId, []);
    this.orderedSessionIds.push(client.sessionId);

    if (this.orderedSessionIds.length === 2) {
      this.state.match.phase = 'countdown';
      this.state.match.timeLeft = ROUND_TIME;
      this.clock.setTimeout(() => { this.state.match.phase = 'active'; }, 2000);
    }
  }

  async onLeave(client, consented) {
    const fighter = this.state.fighters.get(client.sessionId);
    if (fighter) fighter.connected = false;

    if (consented) {
      this.handleForfeit(client.sessionId);
      return;
    }

    // Freeze the match clock while we wait for reconnection.
    const wasActive = this.state.match.phase === 'active';
    if (wasActive) this.state.match.phase = 'paused_disconnect';

    try {
      const newClient = await this.allowReconnection(client, 20 /* seconds grace */);
      if (fighter) fighter.connected = true;
      if (wasActive) this.state.match.phase = 'active';
    } catch (e) {
      this.handleForfeit(client.sessionId);
    }
  }

  handleForfeit(disconnectedSessionId) {
    if (this.state.match.phase === 'match_over') return;
    const opponentId = this.orderedSessionIds.find(id => id !== disconnectedSessionId);
    this.state.match.phase = 'match_over';
    this.state.match.winnerSessionId = opponentId || '';
    // TODO: write match result to Postgres (rank delta, history) here — off the hot path,
    // this only fires once per match.
  }

  handleInput(client, msg) {
    const queue = this.inputQueues.get(client.sessionId);
    if (!queue) return;

    // --- basic anti-cheat: rate limit + sequence validation, per requirements doc §Anti-Cheat ---
    if (queue.length >= MAX_INPUTS_PER_TICK) return; // drop excess, don't queue unbounded
    if (typeof msg.seq !== 'number') return;
    const fighter = this.state.fighters.get(client.sessionId);
    if (!fighter || msg.seq <= fighter.lastProcessedInputSeq) return; // stale/replayed, reject

    const validTypes = new Set(['move', 'punch', 'kick', 'block_start', 'block_end', 'dodge', 'special']);
    if (!validTypes.has(msg.type)) return;
    if (msg.type === 'move' && (typeof msg.value !== 'number' || msg.value < -1 || msg.value > 1)) return;

    queue.push({ type: msg.type, value: msg.value, seq: msg.seq });
  }

  tick(dt) {
    if (this.state.match.phase !== 'active') return;

    this.state.match.timeLeft = Math.max(0, this.state.match.timeLeft - dt);

    for (const sessionId of this.orderedSessionIds) {
      this.drainInputs(sessionId, dt);
    }

    for (const sessionId of this.orderedSessionIds) {
      this.updateFighterPhysics(sessionId, dt);
    }

    this.resolveAttacks(dt);

    if (this.state.match.timeLeft <= 0) {
      this.endRoundByTimeout();
    }
  }

  drainInputs(sessionId, dt) {
    const fighter = this.state.fighters.get(sessionId);
    const queue = this.inputQueues.get(sessionId);
    if (!fighter || !queue) return;

    fighter._moveInput = fighter._moveInput || 0;

    while (queue.length) {
      const input = queue.shift();
      fighter.lastProcessedInputSeq = input.seq;

      // Server re-validates legality server-side — never trusts that the client
      // only sent this because its own cooldown/sp UI allowed it.
      const locked = LOCKED_STATES.has(fighter.state);
      if (locked) continue;

      switch (input.type) {
        case 'move':
          fighter._moveInput = input.value;
          break;
        case 'block_start':
          fighter.block = true;
          break;
        case 'block_end':
          fighter.block = false;
          break;
        case 'punch':
        case 'kick':
          if (fighter.timer <= 0) this.startAttack(fighter, input.type);
          break;
        case 'special':
          if (fighter.timer <= 0 && fighter.sp >= 100) {
            fighter.sp = 0;
            this.startAttack(fighter, 'special');
          }
          break;
        case 'dodge':
          if (fighter.timer <= 0) {
            fighter.state = 'dodge';
            fighter.timer = 0.32;
          }
          break;
      }
    }
  }

  startAttack(fighter, type) {
    fighter.state = type;
    fighter.timer = ATTACK_DURATION[type];
    fighter._attackType = type;
    fighter._attackLanded = false;
  }

  updateFighterPhysics(sessionId, dt) {
    const fighter = this.state.fighters.get(sessionId);
    if (!fighter) return;

    if (!fighter.block && fighter.guard < fighter.guardMax) {
      fighter.guard = Math.min(fighter.guardMax, fighter.guard + dt * 14);
    }

    const locked = LOCKED_STATES.has(fighter.state);
    if (fighter.timer > 0) {
      fighter.timer = Math.max(0, fighter.timer - dt);
      if (fighter.timer === 0 && !locked) fighter.state = 'idle';
    } else if (!locked) {
      const moveInput = fighter._moveInput || 0;
      let targetV = 0;
      if (Math.abs(moveInput) > 0.1 && !fighter.block) {
        targetV = moveInput * 0.045 * 60; // same coefficients as the client sim
        fighter.state = 'walk';
      } else {
        fighter.state = 'idle';
      }
      fighter.vx += (targetV - fighter.vx) * Math.min(1, dt * 8);
      fighter.x = Math.max(-ARENA_EDGE, Math.min(ARENA_EDGE, fighter.x + fighter.vx * dt));
    } else {
      fighter.vx *= 0.8;
    }
  }

  resolveAttacks(dt) {
    const [aId, bId] = this.orderedSessionIds;
    if (!aId || !bId) return;
    const a = this.state.fighters.get(aId);
    const b = this.state.fighters.get(bId);
    if (!a || !b) return;

    for (const [attacker, defender] of [[a, b], [b, a]]) {
      const type = attacker._attackType;
      if (!type || attacker._attackLanded) continue;
      const dur = ATTACK_DURATION[type];
      if (attacker.timer > dur * 0.5) continue; // mid-swing point, matches client's midPoint=0.5

      attacker._attackLanded = true;
      const dist = Math.abs(attacker.x - defender.x);

      // --- lag compensation: rewind the defender's effective position by half the
      // attacker's measured RTT (capped) before the range check, per architecture doc §6 ---
      const rewind = Math.min(0.12, (attacker._rttMs || 0) / 2000); // seconds, capped 120ms
      const compensatedDist = Math.max(0, dist - Math.abs(defender.vx) * rewind);

      if (compensatedDist <= RANGE[type] + 0.15) {
        this.applyDamage(attacker, defender, type);
      }
    }
  }

  applyDamage(attacker, defender, type) {
    const dmg = { punch: 6, kick: 9, special: 22 }[type];
    const blocked = defender.block;

    if (blocked) {
      defender.guard = Math.max(0, defender.guard - dmg * 1.4);
      if (defender.guard <= 0) {
        defender.state = 'dizzy';
        defender.timer = 1.1;
        defender.block = false;
      }
    } else {
      defender.hp = Math.max(0, defender.hp - dmg);
      defender.state = 'hurt';
      defender.timer = 0.28;
      attacker.combo = (attacker.combo || 0) + 1;
    }

    attacker.sp = Math.min(100, attacker.sp + (type === 'special' ? 0 : type === 'kick' ? 14 : 9));

    if (defender.hp <= 0) this.endRoundByKO(attacker.sessionId);
  }

  endRoundByKO(winnerSessionId) {
    this.state.match.phase = 'match_over';
    this.state.match.winnerSessionId = winnerSessionId;
    // TODO: persist result + rank delta to Postgres.
  }

  endRoundByTimeout() {
    const [aId, bId] = this.orderedSessionIds;
    const a = this.state.fighters.get(aId);
    const b = this.state.fighters.get(bId);
    const winnerSessionId = a.hp >= b.hp ? aId : bId;
    this.endRoundByKO(winnerSessionId);
  }
}

module.exports = { FightRoom };
