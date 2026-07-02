const { Schema, type, MapSchema } = require('@colyseus/schema');

/**
 * Mirrors the shape of `combat.p` / `combat.o` in the original single-player
 * game (x, vx, hp, guard, sp, state, timer, block, combo). Keeping the field
 * names identical means the client's existing poseFighter()/HUD code can keep
 * reading this object with zero changes once it's fed from the network layer
 * instead of local AI/physics.
 */
class FighterState extends Schema {
  constructor() {
    super();
    this.sessionId = '';
    this.fighterId = '';   // which roster character (e.g. 'rex', 'kage')
    this.x = 0;
    this.vx = 0;
    this.hp = 100;
    this.hpMax = 100;
    this.guard = 100;
    this.guardMax = 100;
    this.sp = 0;
    this.state = 'idle';   // idle | walk | punch | kick | special | block-hold | dodge | hurt | dizzy | roped
    this.timer = 0;
    this.block = false;
    this.combo = 0;
    this.lastProcessedInputSeq = 0; // for client reconciliation
    this.connected = true;
  }
}
type('string')(FighterState.prototype, 'sessionId');
type('string')(FighterState.prototype, 'fighterId');
type('number')(FighterState.prototype, 'x');
type('number')(FighterState.prototype, 'vx');
type('number')(FighterState.prototype, 'hp');
type('number')(FighterState.prototype, 'hpMax');
type('number')(FighterState.prototype, 'guard');
type('number')(FighterState.prototype, 'guardMax');
type('number')(FighterState.prototype, 'sp');
type('string')(FighterState.prototype, 'state');
type('number')(FighterState.prototype, 'timer');
type('boolean')(FighterState.prototype, 'block');
type('number')(FighterState.prototype, 'combo');
type('number')(FighterState.prototype, 'lastProcessedInputSeq');
type('boolean')(FighterState.prototype, 'connected');

class MatchState extends Schema {
  constructor() {
    super();
    this.phase = 'waiting';   // waiting | countdown | active | round_over | match_over
    this.timeLeft = 60;
    this.round = 1;
    this.winnerSessionId = '';
  }
}
type('string')(MatchState.prototype, 'phase');
type('number')(MatchState.prototype, 'timeLeft');
type('number')(MatchState.prototype, 'round');
type('string')(MatchState.prototype, 'winnerSessionId');

class FightRoomState extends Schema {
  constructor() {
    super();
    this.match = new MatchState();
    this.fighters = new MapSchema(); // sessionId -> FighterState
  }
}
type(MatchState)(FightRoomState.prototype, 'match');
type({ map: FighterState })(FightRoomState.prototype, 'fighters');

module.exports = { FighterState, MatchState, FightRoomState };
