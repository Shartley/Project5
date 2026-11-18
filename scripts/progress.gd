extends Node
## Shared progress, deliberately independent of production gate/extraction scenes.
signal changed
signal reward(message: String)
var workout_state: String = "available"
var portals_open: bool = false
var cleared_gates: Array[String] = []
var unlocked_types: Array[String] = ["goblin"]
var stored_shadow_types: Array[String] = []
var mastered_types: Array[String] = []
var stats_service: Node

func _ready() -> void:
	if stats_service == null:
		stats_service = get_node_or_null("/root/PlayerStats")

func reset() -> void:
	workout_state = "available"
	portals_open = false
	cleared_gates.clear()
	unlocked_types.assign(["goblin"])
	stored_shadow_types.clear()
	mastered_types.clear()
	changed.emit()

func start_workout() -> bool:
	if workout_state != "available":
		return false
	workout_state = "active"
	changed.emit()
	return true

func complete_workout() -> bool:
	if workout_state != "active":
		return false
	workout_state = "completed"
	portals_open = true
	stats_service.grant_points(3)
	stats_service.full_heal()
	changed.emit()
	reward.emit("WORKOUT COMPLETE  /  +3 points  /  HP restored")
	return true

func abandon_workout() -> bool:
	if workout_state != "active":
		return false
	workout_state = "penalty"
	changed.emit()
	return true

func resolve_penalty(survived: bool) -> bool:
	if workout_state != "penalty":
		return false
	workout_state = "resolved"
	portals_open = true
	if survived:
		stats_service.add_xp(50)
	changed.emit()
	reward.emit("PENALTY SURVIVED  /  +50 XP" if survived else "PENALTY ENDED  /  Portals unlocked")
	return true

func register_gate_clear(gate_id: String) -> void:
	if gate_id in cleared_gates or gate_id not in ["warren", "nest"]:
		return
	cleared_gates.append(gate_id)
	var types: Array = ["kobold", "goblin", "chieftain"] if gate_id == "warren" else ["lizardman", "spitter", "kasaka"]
	for enemy_type: String in types:
		if enemy_type not in unlocked_types:
			unlocked_types.append(enemy_type)
	stats_service.set_rank("C" if "nest" in cleared_gates else "D")
	changed.emit()

func register_stored_shadow_type(enemy_type: String) -> void:
	if enemy_type not in ["kobold", "goblin", "chieftain", "lizardman", "spitter", "kasaka"]:
		return
	if enemy_type not in stored_shadow_types:
		stored_shadow_types.append(enemy_type)
	if enemy_type not in unlocked_types:
		unlocked_types.append(enemy_type)
	changed.emit()

func award_mastery(enemy_type: String) -> bool:
	if enemy_type not in unlocked_types or enemy_type in mastered_types:
		return false
	mastered_types.append(enemy_type)
	stats_service.grant_points(1)
	changed.emit()
	reward.emit("MASTERED: %s  /  +1 point  /  +20 ms parry window" % enemy_type.capitalize())
	return true

func is_mastered(enemy_type: String) -> bool:
	return enemy_type in mastered_types
