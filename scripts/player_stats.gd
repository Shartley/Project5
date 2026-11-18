extends Node
## Session state. Call advance(delta) once per gameplay tick; UI only observes signals.
signal changed
signal leveled_up(level: int)
signal died
signal notice(message: String)

const STAT_NAMES := ["Strength", "Vitality", "Agility", "Perception", "Intelligence"]
const POTION_CAPS := {"health": 5, "mana": 3, "tonic": 3}
var level: int = 1
var xp: int = 0
var rank: String = "E"
var points: int = 0
var stats: Dictionary = {}
var hp: float = 100.0
var mp: float = 20.0
var fatigue: float = 0.0
var potions: Dictionary = {}
var return_stones: int = 2
var exhausted: bool = false
var dead: bool = false
var sprinting: bool = false
var awake_enemies: int = 0
var rest_time: float = 0.0
var healing_left: float = 0.0

func _init() -> void:
	reset()

func reset() -> void:
	level = 1
	xp = 0
	rank = "E"
	points = 0
	stats = {"Strength": 10, "Vitality": 10, "Agility": 10, "Perception": 10, "Intelligence": 10}
	hp = 100.0
	mp = 20.0
	fatigue = 0.0
	potions = {"health": 3, "mana": 1, "tonic": 1}
	return_stones = 2
	exhausted = false
	dead = false
	sprinting = false
	awake_enemies = 0
	rest_time = 0.0
	healing_left = 0.0
	changed.emit()

func bonus(stat: String) -> int:
	return maxi(0, int(stats.get(stat, 10)) - 10)

func max_hp() -> float:
	return 100.0 + 10.0 * bonus("Vitality")

func max_mp() -> float:
	return 20.0 + 2.0 * bonus("Intelligence")

func damage_multiplier() -> float:
	return 1.0 + 0.02 * bonus("Strength")

func dash_cooldown() -> float:
	return maxf(1.6, 4.0 * (1.0 - 0.01 * bonus("Agility")))

func fatigue_recovery() -> float:
	return 15.0 * (1.0 + 0.01 * bonus("Agility"))

func parry_window(mastered: bool = false) -> float:
	return 0.150 + 0.004 * bonus("Perception") + (0.020 if mastered else 0.0)

func crit_chance() -> float:
	return clampf(0.05 + 0.01 * bonus("Perception"), 0.0, 1.0)

func weak_points_visible() -> bool:
	return int(stats.Perception) >= 15

func shadow_multiplier() -> float:
	return 0.75 + 0.02 * bonus("Intelligence")

func extraction_bonus() -> float:
	return 0.01 * bonus("Intelligence")

func xp_cost() -> int:
	return roundi(50.0 * pow(level, 1.6))

func add_xp(amount: int) -> void:
	if amount <= 0 or level >= 50:
		return
	xp += amount
	while level < 50 and xp >= xp_cost():
		xp -= xp_cost()
		level += 1
		points += 5
		full_heal()
		leveled_up.emit(level)
	if level == 50:
		xp = 0
	changed.emit()

func grant_points(amount: int) -> void:
	points += maxi(0, amount)
	changed.emit()

func spend_point(stat: String) -> bool:
	if points <= 0 or not stats.has(stat):
		return false
	points -= 1
	stats[stat] += 1
	changed.emit()
	return true

func set_rank(value: String) -> void:
	if value in ["E", "D", "C"]:
		rank = value
		changed.emit()

func full_heal() -> void:
	hp = max_hp()
	changed.emit()

func apply_incoming_damage(amount: float) -> int:
	if dead or amount <= 0.0:
		return 0
	var multiplier := 1.0 - clampf(0.005 * bonus("Vitality"), 0.0, 1.0)
	if level >= 5 and hp < max_hp() * 0.3:
		multiplier *= 0.5
	var damage := maxi(0, roundi(amount * multiplier))
	hp = maxf(0.0, hp - damage)
	if hp <= 0.0:
		dead = true
		healing_left = 0.0
		sprinting = false
	changed.emit()
	if dead:
		died.emit()
	return damage

func restore_after_death() -> void:
	dead = false
	hp = max_hp()
	fatigue = 0.0
	exhausted = false
	healing_left = 0.0
	sprinting = false
	rest_time = 0.0
	changed.emit()

func try_spend_mp(amount: float) -> bool:
	if amount < 0.0 or mp < amount or dead:
		return false
	mp -= amount
	changed.emit()
	return true

func set_awake_enemy_count(count: int) -> void:
	awake_enemies = maxi(0, count)

func set_sprinting(value: bool) -> void:
	sprinting = value and not exhausted and not dead

func try_add_fatigue(amount: float, gated: bool = false) -> bool:
	if dead or (gated and exhausted) or amount < 0.0:
		return false
	fatigue = minf(100.0, fatigue + amount)
	rest_time = 0.0
	if fatigue >= 100.0:
		exhausted = true
		sprinting = false
	changed.emit()
	return true

func add_potion(kind: String, amount: int = 1) -> int:
	if not POTION_CAPS.has(kind) or amount <= 0:
		return 0
	var added := mini(amount, int(POTION_CAPS[kind]) - int(potions[kind]))
	potions[kind] += added
	changed.emit()
	return added

func use_potion(kind: String) -> bool:
	if dead or not potions.has(kind) or int(potions[kind]) <= 0:
		notice.emit("No %s potion available." % kind)
		return false
	if (kind == "health" and (hp >= max_hp() or healing_left > 0.0)) or (kind == "mana" and mp >= max_mp()) or (kind == "tonic" and fatigue <= 0.0):
		notice.emit("Potion not needed, or healing already active.")
		return false
	potions[kind] -= 1
	match kind:
		"health": healing_left = 2.0
		"mana": mp = minf(max_mp(), mp + 30.0)
		"tonic":
			fatigue = 0.0
			exhausted = false
	notice.emit("%s used." % kind.capitalize())
	changed.emit()
	return true

func advance(delta: float) -> void:
	if dead or delta <= 0.0:
		return
	var old := Vector3(hp, mp, fatigue)
	mp = minf(max_mp(), mp + delta * (0.3 if awake_enemies > 0 else 1.0))
	if healing_left > 0.0:
		var duration := minf(delta, healing_left)
		hp = minf(max_hp(), hp + duration * 25.0)
		healing_left = maxf(0.0, healing_left - delta)
	if sprinting and not exhausted:
		try_add_fatigue(5.0 * delta, true)
	else:
		var recovery_time := maxf(0.0, rest_time + delta - 1.0) - maxf(0.0, rest_time - 1.0)
		rest_time += delta
		fatigue = maxf(0.0, fatigue - recovery_time * fatigue_recovery())
	if exhausted and fatigue < 50.0:
		exhausted = false
	if old != Vector3(hp, mp, fatigue):
		changed.emit()
