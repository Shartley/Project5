extends SceneTree
## Runs real rendered frames and input events; writes QA captures to ignored .godot/.
var game: Node
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func frames(count: int = 3) -> void:
	for i in range(count): await process_frame

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)
	print("PASS: " if condition else "FAIL: ", label)

func capture(id: String) -> void:
	await frames()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/qa-%s.png" % id)

func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func click(button: Button) -> void:
	var point := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	Input.parse_input_event(motion)
	await frames(2)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.pressed = pressed
		Input.parse_input_event(event)
		await frames(2)

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames(10)
	await capture("welcome")
	# Click the real first menu button, then exercise physical input.
	await click(game.ui.body.get_child(1))
	check(not game.menu_open, "Welcome button closes menu")
	var initial: Vector3 = game.player.global_position
	key(KEY_W, true)
	await create_timer(0.3).timeout
	key(KEY_W, false)
	check(game.player.global_position.z < initial.z - 0.3, "W moves forward with collisions")
	await capture("hub")
	key(KEY_TAB, true)
	key(KEY_TAB, false)
	await frames()
	check(game.ui.page == "stats", "Tab opens status")
	root.get_node("PlayerStats").grant_points(5)
	await click(game.ui.stat_buttons.Strength)
	check(root.get_node("PlayerStats").stats.Strength == 11, "Click plus spends a point")
	await capture("stats")
	game.set_menu("")
	game.start_workout()
	await create_timer(1.5).timeout
	key(KEY_SPACE, true)
	key(KEY_SPACE, false)
	await frames()
	check(game.workout.reps == 1, "Space on the beat counts squat")
	await capture("workout")
	game.workout.active = false
	game.change_room("training")
	game.set_menu("training")
	await capture("training-menu")
	game.start_training(["goblin"], 0.5)
	# Observe a real attack and inject a right click inside its parry window.
	var enemy = game.enemies[0]
	for i in range(600):
		await physics_frame
		if enemy.state == "windup": break
	check(enemy.state == "windup", "Training enemy approaches and winds up")
	await capture("training")
	for i in range(300):
		await physics_frame
		if enemy.state != "windup" or enemy.impact_at - game.now <= 0.10: break
	var block := InputEventMouseButton.new()
	block.button_index = MOUSE_BUTTON_RIGHT
	block.pressed = true
	Input.parse_input_event(block)
	await create_timer(0.22).timeout
	block = InputEventMouseButton.new()
	block.button_index = MOUSE_BUTTON_RIGHT
	block.pressed = false
	Input.parse_input_event(block)
	check(game.last_grade == "Perfect.", "Timed RMB input earns Perfect")
	await capture("parry")
	game.debug_command("penalty")
	game.penalty.advance(60)
	await create_timer(0.5).timeout
	check(game.enemies.size() == 4, "Penalty renders four enemies")
	await capture("penalty")
	game.set_menu("debug")
	await capture("debug")
	var before: float = game.penalty.elapsed
	await create_timer(0.2).timeout
	check(game.penalty.elapsed == before, "Pause freezes penalty clock")
	print("VISUAL PLAYTEST: %d checks, %d failures" % [checks, failures.size()])
	game.queue_free()
	await frames()
	quit(0 if failures.is_empty() else 1)
