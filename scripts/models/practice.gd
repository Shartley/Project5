extends RefCounted
signal graded(grade: String)
signal round_completed(perfect: int, total: int, mastered_type: String)
var selected: Array[String] = ["goblin"]
var speed: float = 1.0
var grades: Array[String] = []
var last_report: String = "Complete 10 attacks to see your parry rate."
var seen_attacks: Dictionary = {}
var round_number: int = 1

func configure(types: Array[String], multiplier: float) -> void:
	selected = types.duplicate()
	speed = multiplier
	grades.clear()
	seen_attacks.clear()
	round_number = 1
	last_report = "Complete 10 attacks to see your parry rate."

static func grade_attempt(impact_time: float, window: float, attempts: Array[float], successful: bool) -> String:
	if successful:
		return "Perfect."
	for time in attempts:
		if time < impact_time - window - 0.000001:
			return "Too early."
	return "Too late."

func record(attack_id: int, grade: String) -> bool:
	if seen_attacks.has(attack_id):
		return false
	seen_attacks[attack_id] = true
	grades.append(grade)
	graded.emit(grade)
	if grades.size() == 10:
		var perfect := grades.count("Perfect.")
		var single_type := not selected.is_empty()
		for enemy_type in selected:
			single_type = single_type and enemy_type == selected[0]
		var mastery := selected[0] if single_type and is_equal_approx(speed, 1.0) and perfect >= 7 else ""
		last_report = "ROUND %d  /  %d of 10 Perfect  /  %d%%" % [round_number, perfect, perfect * 10]
		round_completed.emit(perfect, 10, mastery)
		grades.clear()
		round_number += 1
	return true
