extends SceneTree
const Stats = preload("res://scripts/player_stats.gd")
const ProgressModel = preload("res://scripts/progress.gd")
const Workout = preload("res://scripts/models/workout.gd")
const Practice = preload("res://scripts/models/practice.gd")
const Penalty = preload("res://scripts/models/penalty.gd")
const Gestures = preload("res://scripts/models/gesture_detector.gd")
var checks: int = 0
var session_stats: Node
var session_progress: Node
var failures: Array[String] = []
var scene_flow_completed: bool = false
var xr_ui_completed: bool = false

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: ", message)

func near(actual: float, expected: float, message: String) -> void:
	check(absf(actual - expected) < 0.0001, "%s (got %.6f, expected %.6f)" % [message, actual, expected])

func run() -> void:
	session_stats = root.get_node("PlayerStats")
	session_progress = root.get_node("Progress")
	test_stats()
	test_progress()
	test_workout()
	test_gestures()
	test_penalty()
	test_practice()
	test_resources()
	await test_xr_adapter()
	await test_scene_flow()
	check(scene_flow_completed, "Scene-flow test reached completion without a runtime error")
	await test_xr_ui()
	check(xr_ui_completed, "XR UI test reached completion without a runtime error")
	print("ROCKY TESTS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func test_stats() -> void:
	var stats := Stats.new()
	check(stats.level == 1 and stats.rank == "E" and stats.points == 0, "Starting progression")
	check(stats.potions == {"health": 3, "mana": 1, "tonic": 1} and stats.return_stones == 2, "Starting inventory")
	check(not stats.spend_point("Strength"), "Cannot spend without points")
	stats.hp = 15
	stats.add_xp(49)
	check(stats.level == 1 and stats.xp == 49, "Below XP threshold")
	stats.add_xp(1)
	check(stats.level == 2 and stats.xp == 0 and stats.points == 5 and stats.hp == 100, "Exact XP threshold gives points and full HP")
	stats.reset()
	stats.add_xp(203)
	check(stats.level == 3 and stats.xp == 1 and stats.points == 10, "Overflow through two levels")
	stats.add_xp(2000000000)
	check(stats.level == 50 and stats.xp == 0 and stats.points == 245, "Level cap and one reward per level")
	stats.add_xp(50)
	check(stats.points == 245, "No reward after cap")
	stats.reset()
	stats.grant_points(5)
	for stat: String in stats.STAT_NAMES: check(stats.spend_point(stat), "Spend one " + stat)
	near(stats.damage_multiplier(), 1.02, "Strength uses points above 10")
	near(stats.max_hp(), 110, "Vitality HP")
	near(stats.max_mp(), 22, "Intelligence MP")
	near(stats.hp, 100, "Raising maximum doesn't refill HP")
	near(stats.mp, 20, "Raising maximum doesn't refill MP")
	near(stats.dash_cooldown(), 3.96, "Agility cooldown")
	near(stats.fatigue_recovery(), 15.15, "Agility recovery")
	near(stats.parry_window(true), 0.174, "Perception and mastery combine")
	near(stats.crit_chance(), 0.06, "Perception crit")
	near(stats.shadow_multiplier(), 0.77, "Intelligence shadow scaling")
	near(stats.extraction_bonus(), 0.01, "Intelligence extraction bonus")
	stats.stats.Perception = 15
	check(stats.weak_points_visible(), "Weak points at Perception 15")
	stats.stats.Perception = 14
	check(not stats.weak_points_visible(), "Weak points hidden below 15")
	stats.stats.Agility = 500
	near(stats.dash_cooldown(), 1.6, "Cooldown floor")
	stats.reset()
	stats.level = 5
	stats.hp = 30
	check(stats.apply_incoming_damage(10) == 10, "30 percent is not below threshold")
	check(stats.apply_incoming_damage(10) == 5, "Level 5 low HP protection")
	stats.level = 4
	check(stats.apply_incoming_damage(10) == 10, "No low HP protection at Level 4")
	stats.reset()
	stats.stats.Vitality = 30
	check(stats.apply_incoming_damage(100) == 90, "Vitality reduces incoming damage once")
	var death_count := [0]
	stats.died.connect(func(): death_count[0] += 1)
	stats.apply_incoming_damage(1000)
	stats.apply_incoming_damage(1000)
	check(death_count[0] == 1, "Death emitted once")
	stats.restore_after_death()
	check(not stats.dead and stats.hp == 300 and stats.fatigue == 0, "Respawn restores derived HP and fatigue")
	stats.reset()
	stats.try_spend_mp(20)
	stats.advance(2)
	near(stats.mp, 2, "Resting mana recovery")
	stats.set_awake_enemy_count(2)
	stats.advance(10)
	near(stats.mp, 5, "Awake mana recovery")
	check(not stats.try_spend_mp(6), "Insufficient MP is atomic")
	stats.reset()
	stats.try_add_fatigue(100)
	check(stats.exhausted and not stats.try_add_fatigue(15, true), "Fatigue cap locks gated actions")
	stats.advance(1)
	near(stats.fatigue, 100, "One second rest delay")
	stats.advance(1)
	near(stats.fatigue, 85, "Base recovery rate")
	stats.fatigue = 50
	stats.advance(0)
	check(stats.exhausted, "Lock persists at exactly 50")
	stats.advance(0.01)
	check(not stats.exhausted, "Lock releases below 50")
	stats.reset()
	stats.set_sprinting(true)
	stats.advance(2)
	near(stats.fatigue, 10, "Sprint fatigue per second")
	stats.set_sprinting(false)
	stats.advance(1.5)
	near(stats.fatigue, 2.5, "Partial tick after rest delay")
	stats.reset()
	check(not stats.use_potion("health") and stats.potions.health == 3, "No consumption at full HP")
	stats.hp = 10
	check(stats.use_potion("health"), "Start healing")
	check(not stats.use_potion("health") and stats.potions.health == 2, "Reject overlapping health potion")
	stats.advance(1)
	near(stats.hp, 35, "First half of health potion")
	stats.advance(1)
	near(stats.hp, 60, "Full health potion")
	stats.mp = 0
	check(stats.use_potion("mana") and stats.mp == 20, "Mana caps at max")
	check(not stats.use_potion("mana"), "Empty inventory")
	stats.try_add_fatigue(100)
	check(stats.use_potion("tonic") and not stats.exhausted and stats.fatigue == 0, "Tonic clears lock")
	check(stats.add_potion("health", 20) == 3 and stats.potions.health == 5, "Health carry cap")
	stats.use_potion("health")
	stats.apply_incoming_damage(1000)
	check(stats.healing_left == 0, "Death cancels healing")
	stats.free()

func test_progress() -> void:
	var stats := Stats.new()
	var progress := ProgressModel.new()
	progress.stats_service = stats
	check(progress.unlocked_types == ["goblin"], "Goblin initially unlocked")
	check(not progress.complete_workout(), "Cannot claim unstarted workout")
	check(progress.start_workout(), "Start workout")
	stats.hp = 10
	stats.mp = 0
	check(progress.complete_workout() and progress.portals_open, "Workout opens portals")
	check(stats.points == 3 and stats.hp == 100 and stats.mp == 0, "Workout rewards HP and 3 points")
	check(not progress.complete_workout() and not progress.start_workout() and stats.points == 3, "Workout reward once per session")
	progress.register_gate_clear("warren")
	progress.register_gate_clear("warren")
	check(progress.unlocked_types.size() == 3 and stats.rank == "D", "Warren unlock is idempotent")
	progress.register_stored_shadow_type("spitter")
	check("spitter" in progress.unlocked_types, "Stored shadows join training catalog")
	progress.register_stored_shadow_type("centipede")
	check("centipede" not in progress.unlocked_types, "Centipede cannot be stored")
	progress.register_gate_clear("nest")
	check(stats.rank == "C" and progress.unlocked_types.size() == 6, "Nest unlock deduplicates shadow types")
	check(progress.award_mastery("goblin"), "Mastery awarded")
	check(not progress.award_mastery("goblin") and stats.points == 4, "Mastery gives only one point")
	progress.reset()
	stats.reset()
	progress.start_workout()
	progress.abandon_workout()
	check(progress.resolve_penalty(true), "Resolve penalty survival")
	check(stats.level == 2 and stats.points == 5 and progress.portals_open, "50 XP survival can level up but grants no workout points")
	check(not progress.resolve_penalty(true), "Penalty survival reward only once")
	progress.reset()
	stats.reset()
	progress.start_workout()
	progress.abandon_workout()
	progress.resolve_penalty(false)
	check(stats.level == 1 and stats.points == 0 and progress.portals_open, "Penalty death opens portals with no XP")
	progress.free()
	stats.free()

func test_workout() -> void:
	var workout := Workout.new()
	workout.start()
	check(not workout.submit("squat"), "Workout input too early")
	workout.advance(1.45)
	check(workout.submit("squat"), "Accept exact early beat boundary")
	check(not workout.submit("squat"), "Only one rep per beat")
	workout.advance(1.0)
	check(not workout.submit("punch"), "Wrong workout action")
	var sequence: Array[String] = []
	workout.start()
	for i in range(30):
		sequence.append(workout.action())
		workout.advance(workout.next_beat - workout.elapsed)
		check(workout.submit(workout.action()), "Rep %d counts" % (i + 1))
		workout.advance(0.8)
	check(not workout.active and workout.reps == 30, "Complete all 30 reps")
	check(sequence.slice(0, 5).count("squat") == 5 and sequence.slice(5, 15).count("punch") == 10 and sequence.slice(15, 20).count("squat") == 5 and sequence.slice(20, 30).count("punch") == 10, "Exact workout order")
	workout.start()
	workout.advance(3.3)
	check(workout.reps == 0 and workout.active, "Missed beats don't advance reps or fail workout")

func test_gestures() -> void:
	var detector := Gestures.new()
	var found: Array[String] = []
	detector.gesture.connect(func(kind: String): found.append(kind))
	check(detector.calibrate(1.7), "Standing-height calibration")
	detector.sample(0, Vector3(0, 1.7, 0), Vector3.ZERO, Vector3.ZERO, true, false, false)
	detector.sample(0.1, Vector3(0, 1.3, 0), Vector3.ZERO, Vector3.ZERO, true, false, false)
	detector.sample(0.5, Vector3(0, 1.7, 0), Vector3.ZERO, Vector3.ZERO, true, false, false)
	check(found.is_empty(), "Reject too-fast squat")
	detector.sample(1, Vector3(0, 1.3, 0), Vector3.ZERO, Vector3.ZERO, true, false, false)
	detector.sample(2, Vector3(0, 1.7, 0), Vector3.ZERO, Vector3.ZERO, true, false, false)
	detector.sample(2.1, Vector3(0, 1.7, 0), Vector3.ZERO, Vector3.ZERO, true, false, false)
	check(found == ["squat"], "Full squat once")
	detector.clear_history()
	detector.sample(3, Vector3(0, 1.7, 0), Vector3.ZERO, Vector3.ZERO, true, false, false)
	detector.sample(3.1, Vector3(0, 1.7, 0), Vector3(0, 0, -0.3), Vector3.ZERO, true, true, false)
	detector.sample(3.2, Vector3(0, 1.7, 0), Vector3(0, 0, -0.6), Vector3.ZERO, true, true, false)
	check(found.count("punch") == 1, "Fast target strike counts once until withdrawal")
	detector.sample(3.3, Vector3(0, 1.7, 0), Vector3.ZERO, Vector3.ZERO, false, false, false)
	detector.sample(3.4, Vector3(0, 1.7, 0), Vector3(8, 0, 0), Vector3.ZERO, true, true, false)
	check(found.count("punch") == 1, "Tracking reacquisition cannot create a fast strike")

func test_penalty() -> void:
	var penalty := Penalty.new()
	var spawned := [0]
	var finished := [0]
	penalty.spawn_requested.connect(func(): spawned[0] += 1)
	penalty.finished.connect(func(): finished[0] += 1)
	penalty.start()
	penalty.advance(14.999)
	check(spawned[0] == 0, "No enemy before 15 seconds")
	penalty.advance(0.0011)
	check(spawned[0] == 1, "First enemy at 15 seconds")
	penalty.advance(90)
	check(spawned[0] == 4 and penalty.alive == 4, "Four alive cap across skipped opportunities")
	penalty.enemy_removed()
	penalty.advance(15)
	check(spawned[0] == 5 and penalty.alive == 4, "Spawn replacement at next interval")
	penalty.advance(180)
	penalty.advance(180)
	check(finished[0] == 1 and penalty.elapsed == 180, "Survival resolves once at 180")

func test_practice() -> void:
	check(Practice.grade_attempt(1, 0.15, [0.84], false) == "Too early.", "Early defense grade")
	check(Practice.grade_attempt(1, 0.15, [], false) == "Too late.", "Missed defense grade")
	check(Practice.grade_attempt(1, 0.15, [0.8, 0.9], true) == "Perfect.", "Successful later parry beats early attempt")
	var practice := Practice.new()
	var results: Array[String] = []
	practice.round_completed.connect(func(_perfect: int, _total: int, enemy_type: String): results.append(enemy_type))
	practice.configure(["goblin"], 1.0)
	for i in range(10): practice.record(i, "Perfect." if i < 6 else "Too late.")
	check(results == [""], "6/10 doesn't master")
	check(not practice.record(9, "Perfect."), "Duplicate attack IDs rejected")
	for i in range(10, 20): practice.record(i, "Perfect." if i < 17 else "Too late.")
	check(results[-1] == "goblin" and practice.grades.is_empty(), "7/10 grants mastery and starts next round")
	practice.configure(["goblin", "goblin"], 1.0)
	for i in range(10): practice.record(i, "Perfect.")
	check(results[-1] == "goblin", "Same-type pair eligible")
	practice.configure(["goblin", "kobold"], 1.0)
	for i in range(10): practice.record(i, "Perfect.")
	check(results[-1] == "", "Mixed types ineligible")
	practice.configure(["goblin"], 0.5)
	for i in range(10): practice.record(i, "Perfect.")
	check(results[-1] == "", "Slower speed ineligible")

func test_resources() -> void:
	for id in ["kobold", "goblin", "chieftain", "lizardman", "spitter", "kasaka", "centipede"]:
		var data: Resource = load("res://resources/enemies/%s.tres" % id)
		check(data != null and data.id == id and data.windup > 0, "Enemy resource " + id)
	var map: OpenXRActionMap = load("res://resources/quest_actions.tres")
	check(map != null and map.action_sets.size() == 1, "OpenXR action map loads")
	check(map.interaction_profiles[0].get_binding_count() == 16, "All Quest bindings present")
	for action: OpenXRAction in map.action_sets[0].actions:
		check(not action.toplevel_paths.is_empty(), "XR action has hand paths: " + action.resource_name)

func test_xr_adapter() -> void:
	var rig = load("res://scripts/player_rig.gd").new()
	rig.xr = true
	rig.simulated = true
	root.add_child(rig)
	var stats := Stats.new()
	var intents: Array[String] = []
	rig.intent.connect(func(id: String): intents.append(id))
	var head_pose := Transform3D(Basis.IDENTITY, Vector3(0, 1.7, 0))
	var left_pose := Transform3D(Basis.IDENTITY, Vector3(-0.3, 1.3, -0.3))
	var right_pose := Transform3D(Basis.IDENTITY, Vector3(0.3, 1.3, -0.3))
	rig.feed_simulated_pose(head_pose, left_pose, right_pose, true)
	rig.update_xr(0.1, stats)
	check(rig.valid_tracking, "XR rig accepts valid simulated tracking")
	near(rig.right_speed, 0, "First tracked sample has no false velocity")
	right_pose.origin.z -= 0.3
	rig.feed_simulated_pose(head_pose, left_pose, right_pose, true, {"right_grip_value": 1.0})
	rig.update_xr(0.1, stats)
	near(rig.right_speed, 3, "Controller velocity measured in tracking space")
	check(rig.is_blocking, "Grip routes to defense state")
	rig.global_position = Vector3(100, 0, 100)
	rig.update_xr(0.1, stats)
	near(rig.right_speed, 0, "World movement cannot become controller velocity")
	rig.feed_simulated_pose(head_pose, left_pose, right_pose, false)
	rig.update_xr(0.1, stats)
	check(not rig.valid_tracking and rig.right_speed == 0, "Tracking loss clears velocity")
	right_pose.origin.z -= 4
	rig.feed_simulated_pose(head_pose, left_pose, right_pose, true)
	rig.update_xr(0.1, stats)
	near(rig.right_speed, 0, "Reacquisition ignores tracking jump")
	rig.bottle_kind = "health"
	left_pose.origin = Vector3(0, 1.53, 0.02)
	rig.feed_simulated_pose(head_pose, left_pose, right_pose, true, {"left_grip_value": 1.0})
	rig.update_xr(0.1, stats)
	rig.update_xr(0.1, stats)
	check(intents.count("drink_health") == 1, "Bottle at mouth emits one potion intent")
	rig._xr_button("stats")
	check(intents[-1] == "stats", "X button routes to status intent")
	rig.feed_simulated_pose(head_pose, left_pose, right_pose, true, {"move": Vector2(0, 1)})
	rig.in_hub = true
	rig.update_xr(0.1, stats)
	check(rig.movement_input == Vector2.ZERO, "Hub disables stick movement")
	rig.in_hub = false
	rig.update_xr(0.1, stats)
	check(rig.movement_input == Vector2(0, -1), "OpenXR forward maps to negative Z")
	rig.queue_free()
	stats.free()
	await process_frame

func test_scene_flow() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var game = scene.instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	await process_frame
	check(game.room == "hub" and game.menu_open, "F5 opens hub with instructions")
	game.set_menu("")
	game.start_workout()
	for i in range(30): game.workout.submit(game.workout.action(), true)
	check(session_progress.portals_open and session_stats.points == 3, "Workout model routes completion to shared state")
	game.start_training(["goblin"], 0.5)
	check(game.enemies.size() == 1 and session_stats.points == 3, "Room swap preserves progression")
	var enemy = game.enemies[0]
	enemy.begin_attack(0, game.practice.speed, 90, Vector3.ZERO)
	near(enemy.impact_at, 1.6, "50 percent doubles wind-up")
	game.player.place_at(Vector3(0, 0.05, 0))
	enemy.position = Vector3(0, 0, -1)
	enemy.begin_attack(0, 1.0, 91, Vector3.ZERO)
	enemy.attempts.assign([0.65])
	game.resolve_attack(enemy)
	check(game.last_grade == "Perfect.", "Exact parry-window start accepted through combat adapter")
	near(session_stats.hp, 100, "Practice never harms player")
	game.start_training(["goblin"], 1.0)
	enemy = game.enemies[0]
	game.player.place_at(Vector3(0, 0.05, 0))
	enemy.position = Vector3(0, 0, -1)
	enemy.begin_attack(0, 1.0, 92, Vector3.ZERO)
	enemy.attempts.assign([0.8])
	game.resolve_attack(enemy)
	check(game.last_grade == "Perfect.", "Exact impact boundary accepted")
	game.debug_command("reset")
	game.start_workout()
	game.handle_ui("abandon", null)
	check(game.room == "penalty" and session_progress.workout_state == "penalty", "Abandon enters Penalty Zone")
	game.penalty.advance(180)
	await process_frame
	check(game.room == "hub" and session_progress.portals_open and session_stats.level == 2, "Survival returns to hub and grants XP")
	game.debug_command("reset")
	check(session_stats.level == 1 and session_progress.workout_state == "available" and session_progress.mastered_types.is_empty(), "Debug reset clears all state")
	game.start_workout()
	game.handle_ui("abandon", null)
	session_stats.apply_incoming_damage(200)
	await process_frame
	check(game.room == "hub" and session_progress.portals_open and session_stats.level == 1 and session_stats.hp == 100, "Penalty death returns alive with no XP")
	game.queue_free()
	await process_frame
	scene_flow_completed = true

func test_xr_ui() -> void:
	# Exercise the actual world UI without enabling headset rendering.
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.remove_child(game.player)
	game.player.queue_free()
	var rig = load("res://scripts/player_rig.gd").new()
	rig.xr = true
	rig.simulated = true
	game.player = rig
	game.add_child(rig)
	rig.intent.connect(game.handle_intent)
	var head_pose := Transform3D(Basis.IDENTITY, Vector3(0, 1.7, 0))
	var hand_pose := Transform3D(Basis.IDENTITY, Vector3(0.3, 1.3, -0.3))
	rig.feed_simulated_pose(head_pose, hand_pose, hand_pose, true)
	rig.update_xr(0.1, session_stats)
	game.ui.get_parent().remove_child(game.ui)
	game.xr_enabled = true
	game.setup_xr_ui()
	game.set_menu("stats")
	session_stats.grant_points(1)
	for i in range(4): await process_frame
	check(game.xr_panel.visible and game.xr_view.size == Vector2i(1280, 720), "World menu viewport and panel created")
	var button: Button = game.ui.stat_buttons.Strength
	var position := button.get_global_rect().get_center()
	var panel_size: Vector2 = game.xr_panel.mesh.size
	var point: Vector3 = game.xr_panel.to_global(Vector3((position.x / 1280.0 - 0.5) * panel_size.x, (0.5 - position.y / 720.0) * panel_size.y, 0))
	hand_pose.basis = Basis.looking_at(point - hand_pose.origin)
	var strength_before: int = session_stats.stats.Strength
	for pressed in [0.0, 1.0, 0.0]:
		rig.feed_simulated_pose(head_pose, hand_pose, hand_pose, true, {"right_trigger_value": pressed})
		rig.update_xr(0.1, session_stats)
		game.update_xr_ui()
		await process_frame
	check(session_stats.stats.Strength == strength_before + 1, "XR ray/trigger clicks shared stat button")
	game.set_menu("")
	check(not game.xr_panel.visible, "World menu hides on close")
	game.queue_free()
	await process_frame
	xr_ui_completed = true
