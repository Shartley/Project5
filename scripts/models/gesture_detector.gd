extends RefCounted
## All samples are tracking-space poses. World locomotion never enters this detector.
signal gesture(kind: String)
var standing_height: float = 1.7
var squat_started: float = -1.0
var squat_armed: bool = true
var last_time: float = -1.0
var last_left: Vector3
var last_right: Vector3
var punch_armed: Array[bool] = [true, true]

func calibrate(height: float) -> bool:
	if height < 0.5 or height > 2.5:
		return false
	standing_height = height
	clear_history()
	return true

func clear_history() -> void:
	squat_started = -1.0
	squat_armed = false
	last_time = -1.0
	punch_armed = [false, false]

func sample(time: float, head: Vector3, left: Vector3, right: Vector3, valid: bool, left_target: bool, right_target: bool) -> void:
	if not valid:
		clear_history()
		return
	if head.y >= standing_height * 0.95:
		if squat_started >= 0.0 and time - squat_started >= 0.8:
			gesture.emit("squat")
		squat_started = -1.0
		squat_armed = true
	elif head.y < standing_height * 0.8 and squat_armed:
		squat_started = time
		squat_armed = false
	var dt := time - last_time
	if not left_target: punch_armed[0] = true
	if not right_target: punch_armed[1] = true
	if last_time >= 0.0 and dt > 0.0001 and dt < 0.2:
		var positions := [left, right]
		var previous := [last_left, last_right]
		var contacts := [left_target, right_target]
		for i in range(2):
			if not contacts[i]:
				punch_armed[i] = true
			elif punch_armed[i] and positions[i].distance_to(previous[i]) / dt >= 2.5:
				punch_armed[i] = false
				gesture.emit("punch")
	last_time = time
	last_left = left
	last_right = right
