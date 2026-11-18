extends Node3D
const StatsScript = preload("res://scripts/player_stats.gd")
const World = preload("res://scripts/world_builder.gd")
const Rig = preload("res://scripts/player_rig.gd")
const UI = preload("res://scripts/system_ui.gd")
const Enemy = preload("res://scripts/test_enemy.gd")
const Workout = preload("res://scripts/models/workout.gd")
const Practice = preload("res://scripts/models/practice.gd")
const Penalty = preload("res://scripts/models/penalty.gd")
const Gestures = preload("res://scripts/models/gesture_detector.gd")
const Audio = preload("res://scripts/system_audio.gd")
const DUNGEON_ENVIRONMENT = preload("res://assets/environment/black_hall.tres")
const Rules = preload("res://scripts/models/combat_rules.gd")
const Encounter = preload("res://scripts/models/encounter.gd")
const XR_PANEL_SIZE := Vector2(1.0, 0.5625)
const XR_PANEL_DISTANCE := 0.75
var room: String = "hub"
var player: CharacterBody3D
var world: Node3D
var ui: Control
var audio: Node
var workout := Workout.new()
var practice := Practice.new()
var penalty := Penalty.new()
var gestures := Gestures.new()
var enemies: Array[CharacterBody3D] = []
var now: float = 0.0
var next_attack_id: int = 0
var last_grade: String = "Watch the wind-up"
var menu_open: bool = false
var xr_enabled: bool = false
var simulated_xr: bool = false
var test_modified: bool = false
var awake_override: bool = false
var swing_hit: bool = false
var heart_at: float = 0.0
var beat_index: int = -1
var pending_return: bool = false
var xr_view: SubViewport
var xr_panel: MeshInstance3D
var xr_feedback: Label3D
var xr_pointer: MeshInstance3D
var xr_pressed: bool = false
var xr_previous_poke: bool = false
var lunge_samples: Array = []
var xr_hit_at: float = 0.0
var xr_error: String = ""
var xr_scroll_at: float = 0.0
var xr_wall_time: float = 0.0
var xr_was_tracked: bool = false
var world_environment: WorldEnvironment
var hub_environment: Environment
var sun: DirectionalLight3D
var player_light: OmniLight3D
var encounter := Encounter.new()
var rng := RandomNumberGenerator.new()
## Rank of the gate being played; sets kill XP (E x1, D x3).
var gate_rank: String = "E"

func _ready() -> void:
	preload("res://scripts/input_bindings.gd").install()
	var args := OS.get_cmdline_user_args()
	simulated_xr = "--simulate-xr" in args
	var xr_requested := "--xr" in args or OS.get_name() == "Android"
	if xr_requested:
		var interface := XRServer.find_interface("OpenXR")
		xr_enabled = interface != null and (interface.is_initialized() or interface.initialize())
		if xr_enabled:
			get_viewport().use_xr = true
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
			Engine.physics_ticks_per_second = 72
		else:
			xr_error = "OpenXR unavailable. Start Quest Link or connect your headset. Desktop controls are active."
	setup_environment()
	player = Rig.new()
	player.xr = xr_enabled
	add_child(player)
	player.intent.connect(handle_intent)
	player.recentered.connect(func(): gestures.clear_history(); lunge_samples.clear())
	audio = Audio.new()
	add_child(audio)
	ui = UI.new()
	ui.game = self
	if xr_enabled:
		setup_xr_ui()
	else:
		var canvas := CanvasLayer.new()
		add_child(canvas)
		canvas.add_child(ui)
	ui.action.connect(handle_ui)
	if OS.has_feature("web"):
		var browser_input := preload("res://scripts/browser_input.gd").new()
		add_child(browser_input)
		browser_input.pause_requested.connect(func():
			if not menu_open: set_menu("pause")
		)
	if xr_enabled:
		var interface := XRServer.find_interface("OpenXR")
		if interface and interface.has_signal("session_visible"):
			interface.connect("session_visible", func(): set_menu("pause"))
	PlayerStats.died.connect(on_death)
	PlayerStats.notice.connect(ui.notify)
	PlayerStats.leveled_up.connect(func(level: int): ui.notify("LEVEL %d  /  +5 POINTS  /  HP RESTORED" % level); audio.play_cue("reward"))
	Progress.reward.connect(func(message: String): ui.notify(message); audio.play_cue("reward"))
	Progress.changed.connect(func(): if is_instance_valid(world): world.set_portal_open(Progress.portals_open))
	workout.finished.connect(finish_workout)
	workout.rep_completed.connect(func(_count: int): audio.play_cue("good"))
	gestures.gesture.connect(func(kind: String): workout.submit(kind, true))
	penalty.spawn_requested.connect(spawn_centipede)
	encounter.spawn_requested.connect(spawn_from_dark)
	encounter.wave_started.connect(func(_index: int, title: String): ui.notify("GOBLIN WARREN  /  %s" % title); audio.play_cue("warning"))
	encounter.wave_cleared.connect(func(_index: int, title: String): ui.notify("%s CLEARED" % title); audio.play_cue("good"))
	encounter.cleared.connect(finish_warren)
	penalty.finished.connect(func(): finish_penalty(true))
	practice.round_completed.connect(func(_perfect: int, _total: int, enemy_type: String):
		if not enemy_type.is_empty(): Progress.award_mastery(enemy_type)
		ui.notify(practice.last_report)
	)
	change_room("hub")
	set_menu("welcome")
	if not xr_error.is_empty():
		ui.notify(xr_error)
	if "--smoke" in args:
		set_menu("")
		print("SMOKE: main scene ready; mode=", "XR" if xr_enabled else "desktop")

func setup_environment() -> void:
	var environment := WorldEnvironment.new()
	var data := Environment.new()
	data.background_mode = Environment.BG_COLOR
	data.background_color = Color("101e30")
	data.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	data.ambient_light_color = Color("bcc9df")
	data.ambient_light_energy = 0.7
	data.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.environment = data
	add_child(environment)
	world_environment = environment
	hub_environment = data
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -25, 0)
	sun.light_energy = 1.0
	add_child(sun)

## The hub keeps its bright System look; dungeon rooms use the dark Black Hall fog and a dim,
## cool light from above so the crystals do most of the lighting.
func apply_room_mood(kind: String) -> void:
	if not is_instance_valid(world_environment):
		return
	var dungeon := kind != "hub"
	world_environment.environment = DUNGEON_ENVIRONMENT if dungeon else hub_environment
	sun.rotation_degrees = Vector3(-78, -25, 0) if dungeon else Vector3(-50, -25, 0)
	sun.light_energy = 0.5 if dungeon else 1.0
	sun.light_color = Color(0.74, 0.78, 0.86) if dungeon else Color.WHITE
	sun.shadow_enabled = dungeon
	# A dim light carried with the player so enemies walking toward you are not black silhouettes.
	if not is_instance_valid(player_light) and is_instance_valid(player) and is_instance_valid(player.camera):
		player_light = OmniLight3D.new()
		player_light.position = Vector3(0, 0.35, 0.25)
		player_light.light_color = Color(0.75, 0.82, 1.0)
		player_light.light_energy = 0.7
		player_light.omni_range = 7.0
		player_light.omni_attenuation = 1.4
		player_light.light_specular = 0.8
		player.camera.add_child(player_light)
	if is_instance_valid(player_light):
		player_light.visible = dungeon

func change_room(kind: String) -> void:
	clear_enemies()
	if is_instance_valid(world):
		remove_child(world)
		world.queue_free()
	room = kind
	world = World.new()
	world.name = "Content"
	add_child(world)
	world.build(kind)
	apply_room_mood(kind)
	world.set_portal_open(Progress.portals_open)
	player.in_hub = kind == "hub"
	player.place_at(Vector3(0, 0.05, 1.9 if kind == "hub" else (7.5 if kind == "warren" else 2.5)))
	if kind == "hub" and is_instance_valid(world.portal):
		var entrance: Area3D = world.portal.get_node("EnterArea")
		entrance.collision_mask = 4  # the player rig's layer
		entrance.body_entered.connect(_on_hub_portal_entered)
	if kind == "warren":
		gate_rank = "E"
		encounter.start(Encounter.WARREN)
	PlayerStats.set_sprinting(false)
	PlayerStats.set_awake_enemy_count(0)
	gestures.clear_history()
	lunge_samples.clear()
	if xr_enabled:
		xr_feedback = World.label(world, "", Vector3(0, 2.3, -1.5), 30, World.BLUE)
		xr_feedback.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	set_menu("")

func clear_enemies() -> void:
	for enemy in enemies:
		if is_instance_valid(enemy):
			enemy.get_parent().remove_child(enemy)
			enemy.queue_free()
	enemies.clear()
	encounter.stop()
	PlayerStats.set_awake_enemy_count(0)

func set_menu(id: String) -> void:
	menu_open = not id.is_empty()
	player.controls_enabled = not menu_open
	PlayerStats.set_sprinting(false)
	ui.show_page(id)
	if xr_enabled:
		xr_panel.visible = menu_open
		if menu_open:
			xr_panel.global_transform = player.camera.global_transform
			xr_panel.global_position = player.camera.to_global(Vector3(0, 0, -XR_PANEL_DISTANCE))
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if menu_open else Input.MOUSE_MODE_CAPTURED
		if not menu_open:
			get_viewport().gui_release_focus()
	gestures.clear_history()
	lunge_samples.clear()
	player.reset_pose_history()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.echo:
		return
	for id in ["pause_game", "stats", "test_panel"]:
		if event.is_action_pressed(id):
			handle_intent(id)
			get_viewport().set_input_as_handled()
			return
	if menu_open or xr_enabled:
		return
	for id in ["interact", "health_potion", "mana_potion", "tonic_potion", "squat", "punch_left", "punch_right", "attack", "block"]:
		if event.is_action_pressed(id):
			handle_intent(id)
	if event.is_action_released("attack"):
		handle_intent("attack_release")

func handle_intent(id: String) -> void:
	match id:
		"pause_game": set_menu("pause" if OS.has_feature("web") else ("" if menu_open else "pause"))
		"stats": set_menu("" if ui.page == "stats" else "stats")
		"test_panel":
			if OS.is_debug_build(): set_menu("" if ui.page == "debug" else "debug")
		_:
			if menu_open: return
			match id:
				"interact":
					if room == "hub" and Progress.workout_state == "available":
						if player.global_position.distance_to(Vector3.ZERO) < 1.7 or xr_enabled:
							start_workout()
						else: ui.notify("Walk onto the blue workout pad, then press E.")
					elif room == "hub": ui.notify("Portals unlocked. Walk into the portal to enter the Goblin Warren.")
				"squat":
					if workout.active: workout.submit("squat")
					else: player.dash(PlayerStats)
				"punch_left", "punch_right": workout.submit("punch")
				"attack":
					# Light attack on a click, heavy when held 0.5 s and released (GDD 2.1).
					if not workout.active and player.swing_time < 0.0: player.charge = 0.0
				"attack_release":
					if player.charge >= 0.0:
						var heavy: bool = player.charge >= Rules.HEAVY_HOLD
						if player.start_swing(heavy): swing_hit = false
				"block": record_defense_attempt()
				"health_potion", "drink_health": PlayerStats.use_potion("health")
				"mana_potion", "drink_mana": PlayerStats.use_potion("mana")
				"tonic_potion", "drink_tonic": PlayerStats.use_potion("tonic")

func handle_ui(id: String, payload: Variant) -> void:
	match id:
		"close": set_menu("")
		"stats": set_menu("stats")
		"debug_page": set_menu("debug")
		"workout": start_workout()
		"abandon":
			if Progress.abandon_workout():
				workout.active = false
				start_penalty()
		"training":
			change_room("training")
			set_menu("training")
		"configure":
			clear_enemies()
			set_menu("training")
		"start_training": start_training(payload.types, payload.speed)
		"hub": change_room("hub")
		"potion":
			if xr_enabled:
				player.bottle_kind = payload
				set_menu("")
				ui.notify("Hold left grip and bring the bottle to your mouth.")
			else:
				PlayerStats.use_potion(payload)
		"debug":
			if OS.is_debug_build(): debug_command(payload)

func start_workout() -> void:
	if xr_enabled and not player.valid_tracking:
		ui.notify("Restore headset and controller tracking before starting the workout.")
		return
	if not Progress.start_workout():
		return
	player.place_at(Vector3(0, 0.05, 0.6))
	workout.start()
	beat_index = -1
	set_menu("")
	if xr_enabled:
		gestures.calibrate(player.camera.position.y)
		for i in range(world.punch_targets.size()):
			var target: Node3D = world.punch_targets[i]
			target.global_position = player.camera.to_global(Vector3(-0.3 if i == 0 else 0.3, -0.3, -0.55))
	ui.notify("Daily quest: 5 squats / 10 punches / 5 squats / 10 punches")

func finish_workout() -> void:
	Progress.complete_workout()
	for target in world.punch_targets:
		target.visible = false

func start_penalty() -> void:
	change_room("penalty")
	penalty.start()
	ui.notify("Survive 3 minutes. First Centipede in 15 seconds.")

func finish_penalty(survived: bool) -> void:
	if pending_return:
		return
	pending_return = true
	penalty.active = false
	Progress.resolve_penalty(survived)
	call_deferred("return_from_penalty")

func return_from_penalty() -> void:
	if PlayerStats.dead:
		PlayerStats.restore_after_death()
	change_room("hub")
	pending_return = false

func on_death() -> void:
	if room == "penalty":
		finish_penalty(false)
	else:
		call_deferred("respawn")

func respawn() -> void:
	PlayerStats.restore_after_death()
	change_room("hub")

func start_training(types: Array, speed: float) -> void:
	if types.is_empty() or types.size() > 2 or speed not in [1.0, 0.75, 0.5]:
		return
	var selected: Array[String] = []
	for enemy_type: String in types:
		if enemy_type not in Progress.unlocked_types: return
		selected.append(enemy_type)
	change_room("training")
	practice.configure(selected, speed)
	last_grade = "Watch the wind-up"
	for i in range(types.size()):
		spawn_enemy(types[i], Vector3(-0.9 if i == 0 and types.size() == 2 else (0.9 if i == 1 else 0.0), 0.0, -1.0), true)
	ui.notify("Right click just before impact. Hold to block. Esc to configure or leave.")

func spawn_enemy(enemy_type: String, position: Vector3, training: bool) -> CharacterBody3D:
	var enemy := Enemy.new()
	world.add_child(enemy)
	enemy.setup(load("res://resources/enemies/%s.tres" % enemy_type), training)
	enemy.position = position
	enemy.ready_at = now + 2.0 + enemies.size() * 0.6
	enemies.append(enemy)
	return enemy

func spawn_centipede() -> void:
	var index := int(penalty.next_spawn / 15.0) % 4
	var locations := [Vector3(-8, 0, -8), Vector3(8, 0, -8), Vector3(8, 0, 8), Vector3(-8, 0, 8)]
	spawn_enemy("centipede", locations[index], false)

func _physics_process(delta: float) -> void:
	if not is_instance_valid(ui): return
	xr_wall_time += delta
	if xr_enabled:
		if menu_open: player.update_xr(delta, PlayerStats)
		if player.valid_tracking and not xr_was_tracked and menu_open:
			xr_panel.global_transform = player.camera.global_transform
			xr_panel.global_position = player.camera.to_global(Vector3(0, 0, -XR_PANEL_DISTANCE))
		elif not player.valid_tracking and xr_was_tracked:
			set_menu("pause")
		xr_was_tracked = player.valid_tracking
		update_xr_ui()
	if not menu_open and not pending_return:
		simulate(delta)
	ui.update_view(delta)
	if xr_enabled and is_instance_valid(xr_feedback):
		xr_feedback.text = ui.prompt.text + ("\n" + ui.toast_label.text if ui.toast_left > 0.0 else "")

func simulate(delta: float) -> void:
	now += delta
	player.advance(delta, PlayerStats)
	PlayerStats.set_awake_enemy_count(enemies.size() + (1 if awake_override else 0))
	PlayerStats.advance(delta)
	workout.advance(delta)
	if workout.active:
		var index := floori((workout.elapsed - 1.6) / 0.8)
		if index >= 0 and index != beat_index:
			beat_index = index
			audio.play_cue("beat")
		if xr_enabled: sample_xr_workout()
	penalty.advance(delta)
	if room == "warren": encounter.advance(delta)
	if pending_return: return
	update_enemies(delta)
	if xr_enabled:
		update_xr_combat()
	elif Rules.attack_active(player.swing_heavy, player.swing_time) and not swing_hit:
		swing_hit = true
		desktop_hit()
	if PlayerStats.hp < PlayerStats.max_hp() * 0.3 and now >= heart_at:
		heart_at = now + 0.85
		audio.play_cue("heart")

func update_enemies(delta: float) -> void:
	var tokens := 0
	for enemy in enemies:
		if enemy.state == "windup": tokens += 1
	for enemy in enemies.duplicate():
		if not is_instance_valid(enemy) or PlayerStats.dead: continue
		match enemy.state:
			"approach":
				var target: Vector3 = player.camera.global_position
				target.y = 0.0
				# Without a free attack token an enemy circles at 3 m and asks again every 2 s (GDD 2.2).
				var wants_attack: bool = room == "training" or (now >= enemy.ready_at and tokens < Rules.ATTACK_TOKENS)
				enemy.approach(player.camera.global_position, delta, wants_attack)
				if now >= enemy.ready_at and enemy.global_position.distance_to(target) <= enemy.definition.reach:
					if tokens < Rules.ATTACK_TOKENS:
						next_attack_id += 1
						enemy.begin_attack(now, practice.speed if room == "training" else 1.0, next_attack_id, target)
						audio.play_cue("warning", enemy.global_position)
						tokens += 1
					else:
						enemy.ready_at = now + Rules.TOKEN_RETRY
			"windup":
				enemy.animate_windup(now)
				if now >= enemy.impact_at:
					resolve_attack(enemy)
			"recover":
				if now >= enemy.ready_at:
					enemy.state = "approach"
					enemy.ready_at = now + 1.0

func record_defense_attempt() -> void:
	for enemy in enemies:
		if enemy.state == "windup":
			enemy.attempts.append(now)

func faces_enemy(enemy: Node3D) -> bool:
	var direction: Vector3 = enemy.global_position - player.camera.global_position
	direction.y = 0
	var forward: Vector3 = -player.camera.global_basis.z
	forward.y = 0
	return forward.normalized().dot(direction.normalized()) >= 0.5

func resolve_attack(enemy: CharacterBody3D) -> void:
	var window: float = PlayerStats.parry_window(Progress.is_mastered(enemy.definition.id))
	var perfect: bool = enemy.parried
	if not xr_enabled and faces_enemy(enemy):
		for time: float in enemy.attempts:
			if time >= enemy.impact_at - window - 0.000001 and time <= enemy.impact_at + 0.000001:
				perfect = true
	var player_flat: Vector3 = player.camera.global_position
	player_flat.y = 0.0
	var delta_position: Vector3 = player_flat - enemy.attack_origin
	var in_range: bool = delta_position.length() <= enemy.definition.reach and delta_position.normalized().dot(enemy.attack_direction) >= 0.5
	var dodged: bool = player.invulnerable > 0.0 or not in_range
	perfect = perfect and not dodged
	var blocked: bool = player.is_blocking and (xr_blade_contact(enemy) if xr_enabled else faces_enemy(enemy))
	var grade: String = Practice.grade_attempt(enemy.impact_at, window, enemy.attempts, perfect)
	if room == "training":
		practice.record(enemy.attack_id, grade)
		last_grade = grade
	if perfect:
		audio.play_cue("parry")
		if xr_enabled: player.right.trigger_haptic_pulse("haptic", 0.0, 0.45, 0.08, 0.0)
	elif not dodged:
		if blocked: PlayerStats.try_add_fatigue(10.0)
		if room != "training":
			PlayerStats.apply_incoming_damage(enemy.definition.damage * (0.2 if blocked else 1.0))
			audio.play_cue("hit")
	enemy.recover(now, perfect)

func desktop_hit() -> void:
	var from: Vector3 = player.camera.global_position
	var query := PhysicsRayQueryParameters3D.create(from, from - player.camera.global_basis.z * 2.2, 3)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and hit.collider in enemies:
		hit_enemy(hit.collider, float(Rules.attack_profile(player.swing_heavy).swing), hit.position)

## Rickey's damage (GDD 2.1): base x swing x Strength x zone x crit - armor. `point` is where
## the blow landed; its height on the body picks head, torso or limb.
func hit_enemy(enemy: CharacterBody3D, multiplier: float, point: Vector3 = Vector3.INF) -> void:
	if not is_instance_valid(enemy) or enemy.state == "dying":
		return
	if not point.is_finite():
		point = enemy.global_position + Vector3(0, enemy.body_height * 0.6, 0)
	var zone := Rules.zone_for_height(point.y - enemy.global_position.y, enemy.body_height)
	var crit := rng.randf() < PlayerStats.crit_chance()
	var raw := float(Rules.damage(Rules.RUSTY_DAGGER, multiplier, PlayerStats.damage_multiplier(), zone, crit, 0.0))
	var result: Dictionary = enemy.receive_hit(raw, now)
	audio.play_cue("hit", point)
	spark(point, crit)
	if room == "training":
		ui.notify("%d damage / invulnerable training target" % maxi(0, int(raw - enemy.definition.armor)))
		return
	damage_number(point, int(result.dealt), crit, zone)
	if result.killed:
		kill_enemy(enemy)
	elif enemy.definition.id == "chieftain" and not enemy.summoned and enemy.hp <= enemy.definition.health * 0.5 and room == "warren":
		enemy.summoned = true
		encounter.add_reinforcements(["kobold", "kobold"])
		ui.notify("THE CHIEFTAIN CALLS FOR HELP")

func kill_enemy(enemy: CharacterBody3D) -> void:
	enemies.erase(enemy)
	enemy.die()
	penalty.enemy_removed()
	if room != "warren":
		return
	encounter.enemy_removed()
	var xp := Rules.kill_xp(enemy.definition.base_xp, gate_rank)
	if xp > 0:
		PlayerStats.add_xp(xp)
		ui.notify("+%d XP" % xp)
	for kind in Rules.roll_drops(rng, enemy.definition.boss):
		if PlayerStats.add_potion(kind) > 0:
			ui.notify("%s potion found" % kind.capitalize())

## Floating damage number: white, gold for a crit, with the zone for head hits.
func damage_number(point: Vector3, amount: int, crit: bool, zone: String) -> void:
	var label := World.label(world, ("%d!" if crit else "%d") % amount + ("  HEAD" if zone == "head" else ""), point + Vector3(0, 0.15, 0), 64 if crit else 48, World.GOLD if crit else Color("dadada"))
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	var tween := label.create_tween().set_parallel()
	tween.tween_property(label, "position:y", label.position.y + 0.6, 0.8)
	tween.tween_property(label, "modulate:a", 0.0, 0.8).set_delay(0.25)
	tween.chain().tween_callback(label.queue_free)

## A short burst of System Blue sparks (gold on a crit) where a blow lands.
func spark(point: Vector3, crit: bool) -> void:
	var burst := CPUParticles3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.025, 0.025)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = (World.GOLD if crit else World.BLUE) * 1.8
	mesh.material = material
	burst.mesh = mesh
	burst.amount = 18
	burst.lifetime = 0.35
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.spread = 180.0
	burst.initial_velocity_min = 1.5
	burst.initial_velocity_max = 3.5
	burst.gravity = Vector3(0, -4, 0)
	world.add_child(burst)
	burst.global_position = point
	burst.emitting = true
	get_tree().create_timer(1.0).timeout.connect(burst.queue_free)

## The encounter asks for the next enemy: it appears at the dark far end of the room and walks in.
func spawn_from_dark(enemy_type: String, slot: int) -> void:
	var lanes := [-6.0, 2.0, -2.0, 6.0]
	var enemy := spawn_enemy(enemy_type, Vector3(lanes[slot % lanes.size()] + rng.randf_range(-0.8, 0.8), 0.0, -9.0), false)
	enemy.ready_at = now + 1.5

func finish_warren() -> void:
	Progress.register_gate_clear("warren")  # placeholder for gate.gd until Samaii's gates land
	ui.notify("GATE CLEARED  /  THE EXIT PORTAL IS OPEN")
	audio.play_cue("reward")
	if is_instance_valid(world) and world.has_method("open_exit"):
		var exit_area: Area3D = world.open_exit()
		exit_area.collision_mask = 4
		exit_area.body_entered.connect(func(body: Node3D): if body == player: call_deferred("change_room", "hub"))

func _on_hub_portal_entered(body: Node3D) -> void:
	if body == player and room == "hub" and Progress.portals_open and not menu_open:
		call_deferred("change_room", "warren")

func xr_blade_contact(enemy: CharacterBody3D) -> bool:
	var point := Geometry3D.get_closest_point_to_segment(enemy.blade_tip(), player.weapon.global_position, player.blade_position)
	return point.distance_to(enemy.blade_tip()) < 0.22

func update_xr_combat() -> void:
	if not player.valid_tracking:
		lunge_samples.clear()
		return
	for enemy in enemies.duplicate():
		if enemy.state == "windup" and xr_blade_contact(enemy):
			enemy.attempts.append(now)
			if player.xr_grip and player.right_speed >= 2.0 and now >= enemy.impact_at - PlayerStats.parry_window(Progress.is_mastered(enemy.definition.id)) and now <= enemy.impact_at:
				enemy.parried = true
		if room in ["penalty", "warren"] and player.xr_grip and player.right_speed > 1.5 and now >= xr_hit_at:
			var closest := Geometry3D.get_closest_point_to_segment(enemy.global_position + Vector3(0, 1, 0), player.weapon.global_position, player.blade_position)
			if closest.distance_to(enemy.global_position + Vector3(0, 1, 0)) < 0.5:
				xr_hit_at = now + 0.25
				hit_enemy(enemy, Rules.vr_swing(player.right_speed), closest)
	lunge_samples.append({"time": now, "position": player.camera.position})
	while not lunge_samples.is_empty() and now - float(lunge_samples[0].time) > 0.2:
		lunge_samples.pop_front()
	if not workout.active and not lunge_samples.is_empty() and player.xr_float("grip_value", true) > 0.6:
		var movement: Vector3 = player.camera.position - lunge_samples[0].position
		movement.y = 0
		if movement.length() >= 0.25:
			player.dash(PlayerStats)
			lunge_samples.clear()

func sample_xr_workout() -> void:
	var contacts: Array[bool] = []
	for i in range(2):
		var target: Node3D = world.punch_targets[i]
		target.visible = workout.action() == "punch"
		var hand: Node3D = player.left if i == 0 else player.right
		contacts.append(target.visible and target.global_position.distance_to(hand.global_position) < 0.18)
	gestures.sample(now, player.camera.position, player.left.position, player.right.position, player.valid_tracking, contacts[0], contacts[1])

func debug_command(command: String) -> void:
	test_modified = true
	match command:
		"xp": PlayerStats.add_xp(200)
		"points": PlayerStats.grant_points(5)
		"damage": PlayerStats.apply_incoming_damage(25)
		"low_hp":
			while PlayerStats.level < 5: PlayerStats.add_xp(PlayerStats.xp_cost() - PlayerStats.xp)
			PlayerStats.hp = PlayerStats.max_hp() * 0.25
			PlayerStats.changed.emit()
		"mp": PlayerStats.try_spend_mp(PlayerStats.mp)
		"fatigue": PlayerStats.try_add_fatigue(100)
		"rest":
			PlayerStats.set_sprinting(false)
			PlayerStats.advance(5.0)
		"potions":
			for kind: String in PlayerStats.POTION_CAPS: PlayerStats.add_potion(kind, 5)
		"awake": awake_override = not awake_override
		"warren", "nest": Progress.register_gate_clear(command)
		"shadow": Progress.register_stored_shadow_type("spitter")
		"penalty":
			workout.active = false
			Progress.workout_state = "penalty"
			start_penalty()
		"advance_penalty":
			if room == "penalty": penalty.advance(30.0)
			else: ui.notify("Enter the Penalty Zone first.")
		"mastery":
			start_training(["goblin"], 1.0)
			for i in range(9): practice.record(-100 - i, "Perfect." if i < 6 else "Too late.")
			ui.notify("6 Perfect / 3 late. Parry the next attack to earn mastery.")
		"simulate_squat", "simulate_punch": replay_gesture(command == "simulate_squat")
		"reset":
			workout.active = false
			penalty.active = false
			PlayerStats.reset()
			Progress.reset()
			practice.configure(["goblin"], 1.0)
			awake_override = false
			test_modified = false
			change_room("hub")
			ui.notify("Fresh session. All progress reset.")
	if menu_open: ui.refresh_stats()

func replay_gesture(squat: bool) -> void:
	gestures.calibrate(1.7)
	if squat:
		gestures.sample(0.0, Vector3(0, 1.7, 0), Vector3.ZERO, Vector3.ZERO, true, false, false)
		gestures.sample(0.2, Vector3(0, 1.2, 0), Vector3.ZERO, Vector3.ZERO, true, false, false)
		gestures.sample(1.1, Vector3(0, 1.7, 0), Vector3.ZERO, Vector3.ZERO, true, false, false)
	else:
		gestures.sample(0.0, Vector3(0, 1.7, 0), Vector3.ZERO, Vector3.ZERO, true, false, false)
		gestures.sample(0.1, Vector3(0, 1.7, 0), Vector3(0, 0, -0.3), Vector3.ZERO, true, true, false)
	gestures.clear_history()
	ui.notify("Replayed XR %s through the shared gesture detector.%s" % ["squat" if squat else "punch", "" if workout.active else " Begin a workout to count reps."])

func setup_xr_ui() -> void:
	xr_view = SubViewport.new()
	xr_view.size = Vector2i(1280, 720)
	xr_view.transparent_bg = true
	xr_view.gui_embed_subwindows = true
	xr_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(xr_view)
	xr_view.add_child(ui)
	xr_panel = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = XR_PANEL_SIZE
	xr_panel.mesh = quad
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_texture = xr_view.get_texture()
	xr_panel.material_override = material
	add_child(xr_panel)
	xr_pointer = World.box(self, Vector3.ZERO, Vector3(0.012, 0.012, 0.012), World.GOLD)

func update_xr_ui() -> void:
	xr_pointer.visible = menu_open
	if not menu_open or not player.valid_tracking:
		return
	var start: Vector3 = xr_panel.to_local(player.right_aim.global_position)
	var end: Vector3 = xr_panel.to_local(player.right_aim.to_global(Vector3(0, 0, -5)))
	var direction := end - start
	if absf(direction.z) < 0.00001: return
	var fraction := -start.z / direction.z
	var point := start + direction * fraction
	var poke_point: Vector3 = xr_panel.to_local(player.right.to_global(Vector3(0, 0, -0.08)))
	var poke := absf(poke_point.z) < 0.025 and absf(poke_point.x) < XR_PANEL_SIZE.x * 0.5 and absf(poke_point.y) < XR_PANEL_SIZE.y * 0.5
	if poke: point = poke_point
	if (fraction < 0.0 and not poke) or absf(point.x) > XR_PANEL_SIZE.x * 0.5 or absf(point.y) > XR_PANEL_SIZE.y * 0.5:
		if xr_pressed: send_xr_click(Vector2(-1, -1), false)
		xr_pressed = false
		return
	xr_pointer.global_position = xr_panel.to_global(Vector3(point.x, point.y, 0.01))
	var uv := Vector2((point.x / XR_PANEL_SIZE.x + 0.5) * 1280, (0.5 - point.y / XR_PANEL_SIZE.y) * 720)
	var motion := InputEventMouseMotion.new()
	motion.position = uv
	xr_view.push_input(motion, true)
	var pressed: bool = player.xr_float("trigger_value", false) > 0.6 or poke
	if pressed != xr_pressed: send_xr_click(uv, pressed)
	xr_pressed = pressed
	var scroll: float = player.xr_vector("turn", false).y
	if absf(scroll) > 0.5 and xr_wall_time > xr_scroll_at:
		xr_scroll_at = xr_wall_time + 0.12
		var wheel := InputEventMouseButton.new()
		wheel.position = uv
		wheel.button_index = MOUSE_BUTTON_WHEEL_UP if scroll > 0 else MOUSE_BUTTON_WHEEL_DOWN
		wheel.pressed = true
		xr_view.push_input(wheel, true)

func send_xr_click(position: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	xr_view.push_input(event, true)
