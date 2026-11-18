extends RefCounted
signal rep_completed(count: int)
signal finished
var active: bool = false
var reps: int = 0
var elapsed: float = 0.0
var next_beat: float = 1.6
var accepted_beat: bool = false
var feedback: String = "Get ready"

func start() -> void:
	active = true
	reps = 0
	elapsed = 0.0
	next_beat = 1.6
	accepted_beat = false
	feedback = "Get ready"

func action() -> String:
	return "squat" if reps < 5 or (reps >= 15 and reps < 20) else "punch"

func advance(delta: float) -> void:
	if not active:
		return
	elapsed += delta
	while elapsed > next_beat + 0.15 + 0.000001:
		if not accepted_beat:
			feedback = "Missed - try the next beat"
		next_beat += 0.8
		accepted_beat = false

func submit(kind: String, gesture: bool = false) -> bool:
	if not active or kind != action():
		return false
	if not gesture and (accepted_beat or absf(elapsed - next_beat) > 0.150001):
		feedback = "Wait for the beat"
		return false
	accepted_beat = true
	reps += 1
	feedback = "Good rep!"
	rep_completed.emit(reps)
	if reps >= 30:
		active = false
		finished.emit()
	return true
