extends RefCounted
## Rickey's Attack/Combat and Enemies numbers (GDD 2.1 and 2.2) as pure functions, so the
## keyboard path, the VR path and the tests all use one calculation.

const RUSTY_DAGGER := 10.0
const STEEL_DAGGER := 14.0
## Player attacks: swing multiplier and timings in seconds (wind-up, active, recovery).
const LIGHT := {"swing": 1.0, "windup": 0.1, "active": 0.15, "recovery": 0.2}
const HEAVY := {"swing": 1.2, "windup": 0.1, "active": 0.2, "recovery": 0.3}
const HEAVY_HOLD := 0.5
const ZONES := {"head": 2.0, "torso": 1.0, "limb": 0.6, "weak_point": 2.5}
const CRIT_MULTIPLIER := 1.5
const STAGGER_SHARE := 0.25
const STAGGER_TIME := 0.5
const STUN_TIME := 1.5
const RECOVER_TIME := 1.0
const TOKEN_RETRY := 2.0
const CIRCLE_DISTANCE := 3.0
const ATTACK_TOKENS := 2
const MAX_ACTIVE := 6
const BODY_STAYS := 6.0
const BOSS_ENRAGED_WINDUP := 0.7
const GATE_RANK_XP := {"E": 1, "D": 3}


## Damage = base x swing x strength x zone x crit - armor, rounded, never below 0.
static func damage(base: float, swing: float, strength_multiplier: float, zone: String, crit: bool, armor: float) -> int:
	var raw := base * swing * strength_multiplier * float(ZONES.get(zone, 1.0)) * (CRIT_MULTIPLIER if crit else 1.0)
	return maxi(0, roundi(raw - armor))


## Which zone a hit lands in, from how high on the body it struck (0 = feet, 1 = top of head).
static func zone_for_height(hit_height: float, body_height: float) -> String:
	var t := hit_height / maxf(body_height, 0.01)
	if t >= 0.8:
		return "head"
	if t >= 0.4:
		return "torso"
	return "limb"


## VR swing strength from blade speed in m/s: (speed - 1.5) / 3.5, from 0 to 1.2.
static func vr_swing(blade_speed: float) -> float:
	return clampf((blade_speed - 1.5) / 3.5, 0.0, 1.2)


static func attack_profile(heavy: bool) -> Dictionary:
	return HEAVY if heavy else LIGHT


static func attack_length(heavy: bool) -> float:
	var p := attack_profile(heavy)
	return float(p.windup) + float(p.active) + float(p.recovery)


## True while the attack can connect: after its wind-up and until its active time ends.
static func attack_active(heavy: bool, elapsed: float) -> bool:
	var p := attack_profile(heavy)
	return elapsed >= float(p.windup) and elapsed <= float(p.windup) + float(p.active)


static func staggers(damage_dealt: float, max_hp: float, boss: bool) -> bool:
	return not boss and damage_dealt >= max_hp * STAGGER_SHARE


## Wind-up time; a boss below half HP winds up faster.
static func windup_time(base_windup: float, hp: float, max_hp: float, boss: bool) -> float:
	return BOSS_ENRAGED_WINDUP if boss and hp <= max_hp * 0.5 else base_windup


static func kill_xp(base_xp: int, gate_rank: String) -> int:
	return base_xp * int(GATE_RANK_XP.get(gate_rank, 1))


## Potions dropped on death: bosses drop 2 health potions; others 20% health, 10% mana.
static func roll_drops(rng: RandomNumberGenerator, boss: bool) -> Array[String]:
	var drops: Array[String] = []
	if boss:
		drops.append("health")
		drops.append("health")
		return drops
	if rng.randf() < 0.2:
		drops.append("health")
	if rng.randf() < 0.1:
		drops.append("mana")
	return drops
