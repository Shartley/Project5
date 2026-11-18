extends RefCounted
## Rickey's enemy waves for a gate: each room's roster comes out of the dark one enemy at a
## time, never more than MAX_ACTIVE alive. A room is cleared when its whole roster is dead.
## The rosters are the GDD's (section 2.3). Room-to-room travel belongs to gate.gd (Samaii);
## until then the rooms play as waves in one arena.

signal spawn_requested(enemy_type: String, slot: int)
signal wave_started(index: int, title: String)
signal wave_cleared(index: int, title: String)
signal cleared

const MAX_ACTIVE := 6
const SPAWN_GAP := 1.6
const WAVE_PAUSE := 3.0

const WARREN := [
	{"title": "ROOM 1", "enemies": ["kobold", "kobold", "kobold", "goblin"]},
	{"title": "ROOM 2", "enemies": ["goblin", "goblin", "goblin", "kobold", "kobold"]},
	{"title": "BOSS / GOBLIN CHIEFTAIN", "enemies": ["chieftain"]},
]

var waves: Array = []
var wave: int = -1
var queue: Array[String] = []
var active: int = 0
var spawned_in_wave: int = 0
var timer: float = 0.0
var running: bool = false
var slot: int = 0


func start(rosters: Array) -> void:
	waves = rosters
	wave = -1
	active = 0
	slot = 0
	running = true
	_next_wave()


func stop() -> void:
	running = false
	queue.clear()
	active = 0


func advance(delta: float) -> void:
	if not running:
		return
	timer -= delta
	if timer <= 0.0 and not queue.is_empty() and active < MAX_ACTIVE:
		var enemy_type: String = queue.pop_front()
		active += 1
		spawned_in_wave += 1
		timer = SPAWN_GAP
		spawn_requested.emit(enemy_type, slot)
		slot += 1
	if queue.is_empty() and active == 0 and spawned_in_wave > 0:
		wave_cleared.emit(wave, title())
		_next_wave()


## Call when an enemy from this encounter dies or is removed.
func enemy_removed() -> void:
	active = maxi(0, active - 1)


## Extra enemies (the Chieftain's 2 Kobolds) join the current room straight away.
func add_reinforcements(types: Array) -> void:
	for enemy_type in types:
		queue.push_front(String(enemy_type))
	timer = minf(timer, 0.2)


func title() -> String:
	return String(waves[wave].title) if wave >= 0 and wave < waves.size() else ""


func _next_wave() -> void:
	wave += 1
	spawned_in_wave = 0
	if wave >= waves.size():
		running = false
		cleared.emit()
		return
	queue.assign(waves[wave].enemies)
	timer = WAVE_PAUSE
	wave_started.emit(wave, title())
