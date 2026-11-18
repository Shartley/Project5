extends RefCounted
signal spawn_requested
signal finished
const DURATION := 180.0
const SPAWN_INTERVAL := 15.0
var elapsed: float = 0.0
var next_spawn: float = SPAWN_INTERVAL
var alive: int = 0
var active: bool = false

func start() -> void:
	elapsed = 0.0
	next_spawn = SPAWN_INTERVAL
	alive = 0
	active = true

func advance(delta: float) -> void:
	if not active:
		return
	elapsed = minf(DURATION, elapsed + delta)
	while next_spawn <= elapsed and next_spawn < DURATION:
		if alive < 4:
			alive += 1
			spawn_requested.emit()
		next_spawn += SPAWN_INTERVAL
	if elapsed >= DURATION:
		active = false
		finished.emit()

func enemy_removed() -> void:
	alive = maxi(0, alive - 1)
