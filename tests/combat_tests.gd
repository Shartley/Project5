extends SceneTree
## Rickey's combat and enemy checks (GDD 2.1 and 2.2). Run headless:
##   godot --headless --xr-mode off --script res://tests/combat_tests.gd
## Prints "COMBAT TESTS: N checks, M failures" and exits nonzero on failure.

const Rules = preload("res://scripts/models/combat_rules.gd")
const Encounter = preload("res://scripts/models/encounter.gd")

var checks := 0
var failures: Array[String] = []


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		print("FAIL: ", label)


func _initialize() -> void:
	test_damage()
	test_attacks()
	test_enemy_rules()
	test_encounter()
	await test_scene()
	print("COMBAT TESTS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func test_damage() -> void:
	check(Rules.damage(10, 1.0, 1.0, "torso", false, 0) == 10, "Light torso hit with the Rusty Dagger is 10")
	check(Rules.damage(10, 1.2, 1.0, "torso", false, 0) == 12, "Heavy swing is x1.2")
	check(Rules.damage(10, 1.0, 1.0, "head", false, 0) == 20, "Head is x2")
	check(Rules.damage(10, 1.0, 1.0, "limb", false, 0) == 6, "Limb is x0.6")
	check(Rules.damage(10, 1.0, 1.0, "weak_point", false, 0) == 25, "Boss weak point is x2.5")
	check(Rules.damage(10, 1.0, 1.0, "torso", true, 0) == 15, "Crit is x1.5")
	check(Rules.damage(10, 1.0, 1.1, "torso", false, 0) == 11, "Strength 15 adds 10%")
	check(Rules.damage(10, 1.0, 1.0, "limb", false, 3) == 3, "Armor is subtracted after multipliers")
	check(Rules.damage(10, 0.2, 1.0, "limb", false, 3) == 0, "Damage never goes below 0")
	check(Rules.damage(14, 1.2, 1.0, "head", true, 0) == 50, "Steel Dagger heavy head crit: 14 x 1.2 x 2 x 1.5 = 50")


func test_attacks() -> void:
	check(is_equal_approx(Rules.attack_length(false), 0.45), "Light attack lasts 0.45 s")
	check(is_equal_approx(Rules.attack_length(true), 0.6), "Heavy attack lasts 0.6 s")
	check(not Rules.attack_active(false, 0.05), "Light attack is not active during its 0.1 s wind-up")
	check(Rules.attack_active(false, 0.2), "Light attack is active at 0.2 s")
	check(not Rules.attack_active(false, 0.3), "Light attack is no longer active at 0.3 s")
	check(Rules.attack_active(true, 0.28), "Heavy attack is still active at 0.28 s")
	check(is_equal_approx(Rules.vr_swing(1.5), 0.0), "VR swing is 0 at 1.5 m/s")
	check(is_equal_approx(Rules.vr_swing(5.0), 1.0), "VR swing is 1 at 5 m/s")
	check(is_equal_approx(Rules.vr_swing(20.0), 1.2), "VR swing caps at 1.2")
	check(Rules.zone_for_height(1.2, 1.3) == "head", "Top fifth of the body is the head")
	check(Rules.zone_for_height(0.8, 1.3) == "torso", "Middle of the body is the torso")
	check(Rules.zone_for_height(0.3, 1.3) == "limb", "Low hits are limbs")


func test_enemy_rules() -> void:
	check(Rules.staggers(10, 40, false), "A Goblin staggers at 10 damage (25% of 40)")
	check(not Rules.staggers(9, 40, false), "9 damage does not stagger a Goblin")
	check(not Rules.staggers(200, 300, true), "Bosses never stagger")
	check(is_equal_approx(Rules.windup_time(1.0, 300, 300, true), 1.0), "Chieftain winds up for 1.0 s at full HP")
	check(is_equal_approx(Rules.windup_time(1.0, 150, 300, true), 0.7), "Chieftain winds up for 0.7 s at half HP")
	check(is_equal_approx(Rules.windup_time(0.8, 10, 40, false), 0.8), "Regular enemies never speed up")
	check(Rules.kill_xp(25, "E") == 25, "A Goblin is worth 25 XP in a rank E gate")
	check(Rules.kill_xp(30, "D") == 90, "Rank D gates triple XP")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var health := 0
	var mana := 0
	for i in range(2000):
		for kind in Rules.roll_drops(rng, false):
			if kind == "health":
				health += 1
			else:
				mana += 1
	check(health > 330 and health < 470, "About 20%% of regular enemies drop a health potion (%d / 2000)" % health)
	check(mana > 140 and mana < 260, "About 10%% drop a mana potion (%d / 2000)" % mana)
	check(Rules.roll_drops(rng, true) == ["health", "health"], "Bosses drop 2 health potions")


func test_encounter() -> void:
	var e := Encounter.new()
	var spawned: Array[String] = []
	var cleared_waves: Array[int] = []
	var done := [false]
	e.spawn_requested.connect(func(t: String, _slot: int): spawned.append(t))
	e.wave_cleared.connect(func(i: int, _title: String): cleared_waves.append(i))
	e.cleared.connect(func(): done[0] = true)
	e.start(Encounter.WARREN)
	e.advance(Encounter.WAVE_PAUSE - 0.1)
	check(spawned.is_empty(), "Nothing spawns during the pause before a room")
	e.advance(0.2)
	check(spawned == ["kobold"], "Room 1 starts with its first Kobold")
	e.advance(Encounter.SPAWN_GAP * 0.5)
	check(spawned.size() == 1, "Enemies come one at a time")
	for i in range(6):
		e.advance(Encounter.SPAWN_GAP)
	check(spawned == ["kobold", "kobold", "kobold", "goblin"], "Room 1 is 3 Kobolds and 1 Goblin")
	for i in range(4):
		e.enemy_removed()
	e.advance(0.01)
	check(cleared_waves == [0], "Killing all of Room 1 clears it")
	for i in range(20):
		e.advance(Encounter.SPAWN_GAP + 0.01)
	check(spawned.size() == 9, "Room 2 sends its 5 enemies")
	check(spawned.slice(4) == ["goblin", "goblin", "goblin", "kobold", "kobold"], "Room 2 is 3 Goblins and 2 Kobolds")
	for i in range(5):
		e.enemy_removed()
	e.advance(0.01)
	for i in range(4):
		e.advance(Encounter.SPAWN_GAP)
	check(spawned.back() == "chieftain", "The boss room is the Goblin Chieftain")
	e.add_reinforcements(["kobold", "kobold"])
	e.advance(0.3)
	e.advance(Encounter.SPAWN_GAP)
	check(spawned.slice(-2) == ["kobold", "kobold"], "The Chieftain's 2 Kobolds join the fight")
	for i in range(3):
		e.enemy_removed()
	e.advance(0.01)
	check(done[0] and not e.running, "Killing the boss and its Kobolds clears the gate")
	var cap := Encounter.new()
	var count := [0]
	cap.spawn_requested.connect(func(_t: String, _s: int): count[0] += 1)
	cap.start([{"title": "BIG", "enemies": ["goblin", "goblin", "goblin", "goblin", "goblin", "goblin", "goblin", "goblin"]}])
	for i in range(40):
		cap.advance(Encounter.SPAWN_GAP)
	check(count[0] == Encounter.MAX_ACTIVE, "Never more than 6 active enemies")


func test_scene() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	await process_frame
	game.set_menu("")
	root.get_node("Progress").portals_open = true
	game.change_room("warren")
	check(game.room == "warren" and game.encounter.running, "Entering the Warren starts its encounter")
	game.encounter.advance(Encounter.WAVE_PAUSE + 0.1)
	check(game.enemies.size() == 1, "The first enemy appears in the Warren")
	var enemy = game.enemies[0]
	var xp_before: int = root.get_node("PlayerStats").xp
	game.hit_enemy(enemy, 10.0, enemy.global_position + Vector3(0, enemy.body_height * 0.6, 0))
	check(enemy.state == "dying" and not game.enemies.has(enemy), "A killing blow starts the death and frees the slot")
	check(root.get_node("PlayerStats").xp == xp_before + 15 or root.get_node("PlayerStats").level > 1, "A Kobold kill gives 15 XP in a rank E gate")
	check(game.encounter.active == 0, "The encounter counts the kill")
	game.change_room("hub")
	check(not game.encounter.running, "Leaving the Warren stops its encounter")
	game.queue_free()
	await process_frame
