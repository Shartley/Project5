extends CharacterBody3D
## Replaceable desktop/OpenXR test rig. Game rules stay in shared models.
const Art = preload("res://scripts/world_builder.gd")
signal intent(action: String)
signal recentered
var xr: bool = false
var simulated: bool = false
var xr_interface: XRInterface
var controls_enabled: bool = true
var in_hub: bool = true
var camera: Camera3D
var head: Node3D
var origin: XROrigin3D
var left: XRController3D
var right: XRController3D
var weapon: Node3D
var wrist: Label3D
var bottle: Node3D
var bottle_kind: String = ""
var turn_armed: bool = true
var right_speed: float = 0.0
var previous_right: Vector3
var right_history: bool = false
var valid_tracking: bool = false
var blade_position: Vector3
var xr_grip: bool = false
var bottle_near: bool = false
var dash_remaining: float = 0.0
var invulnerable: float = 0.0
var swing_time: float = -1.0
var movement_input: Vector2
var is_blocking: bool = false
var simulated_valid: bool = false
var simulated_inputs: Dictionary = {}
var right_aim: XRController3D

func _ready() -> void:
	name = "PlayerRig"
	collision_layer = 4
	collision_mask = 1
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.25
	capsule.height = 1.7
	shape.shape = capsule
	shape.position.y = 0.85
	add_child(shape)
	if xr:
		build_xr()
	else:
		head = Node3D.new()
		add_child(head)
		head.position.y = 1.65
		camera = Camera3D.new()
		head.add_child(camera)
		camera.fov = 78
		weapon = make_weapon(camera)
		weapon.position = Vector3(0.33, -0.28, -0.5)
	camera.current = true
	camera.near = 0.03

func make_weapon(parent: Node3D) -> Node3D:
	var root := Node3D.new()
	parent.add_child(root)
	Art.box(root, Vector3(0, 0, 0.05), Vector3(0.04, 0.04, 0.16), Color("644d42"))
	Art.box(root, Vector3(0, 0, -0.05), Vector3(0.16, 0.025, 0.035), Art.GOLD)
	Art.box(root, Vector3(0, 0, -0.26), Vector3(0.055, 0.025, 0.4), Color("a9bcc4"))
	return root

func build_xr() -> void:
	origin = XROrigin3D.new()
	add_child(origin)
	camera = XRCamera3D.new()
	origin.add_child(camera)
	head = camera
	left = XRController3D.new()
	left.tracker = &"left_hand"
	left.pose = &"grip"
	origin.add_child(left)
	right = XRController3D.new()
	right.tracker = &"right_hand"
	right.pose = &"grip"
	origin.add_child(right)
	right_aim = XRController3D.new()
	right_aim.tracker = &"right_hand"
	right_aim.pose = &"aim"
	origin.add_child(right_aim)
	for controller in [left, right]:
		Art.box(controller, Vector3.ZERO, Vector3(0.06, 0.05, 0.12), Art.BLUE)
		controller.button_pressed.connect(_xr_button)
	weapon = make_weapon(right)
	wrist = Art.label(left, "SYSTEM", Vector3(0, 0.09, 0.06), 24, Art.BLUE)
	wrist.pixel_size = 0.001
	wrist.rotation.x = -PI / 3.0
	bottle = Node3D.new()
	left.add_child(bottle)
	Art.box(bottle, Vector3(0, 0, -0.1), Vector3(0.07, 0.14, 0.07), Color("e5383b"))
	Art.box(bottle, Vector3(0, 0.09, -0.1), Vector3(0.03, 0.05, 0.03), Art.GOLD)
	bottle.visible = false
	xr_interface = XRServer.find_interface("OpenXR")
	if xr_interface and xr_interface.has_signal("pose_recentered"):
		xr_interface.connect("pose_recentered", reset_pose_history)

func _xr_button(action: String) -> void:
	if action == "menu":
		intent.emit("pause_game")
	elif action == "stats":
		intent.emit("stats")
	elif action == "interact":
		intent.emit("interact")

func reset_pose_history() -> void:
	right_history = false
	right_speed = 0.0
	bottle_near = false
	recentered.emit()

func _unhandled_input(event: InputEvent) -> void:
	if xr or not controls_enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * 0.0023)
		head.rotation.x = clampf(head.rotation.x - event.relative.y * 0.0023, -1.35, 1.35)

func advance(delta: float, stats: Node) -> void:
	dash_remaining = maxf(0.0, dash_remaining - delta)
	invulnerable = maxf(0.0, invulnerable - delta)
	if swing_time >= 0.0:
		swing_time += delta
		if swing_time > 0.45:
			swing_time = -1.0
	if xr:
		update_xr(delta, stats)
	else:
		movement_input = Input.get_vector("move_left", "move_right", "move_forward", "move_back") if controls_enabled else Vector2.ZERO
		is_blocking = controls_enabled and Input.is_action_pressed("block")
		weapon.rotation = Vector3(0, 0, -0.8 if is_blocking else 0.0)
		if swing_time >= 0.0:
			weapon.rotation.x = -sin(swing_time / 0.45 * PI) * 1.5
	if not controls_enabled:
		stats.set_sprinting(false)
		return
	var sprint_requested := xr_button("sprint") if xr else Input.is_action_pressed("sprint")
	stats.set_sprinting(sprint_requested and movement_input.length() > 0.1 and not (xr and in_hub))
	var speed: float = (3.0 if stats.sprinting else 1.5) if xr else (5.0 if stats.sprinting else 3.0)
	var basis_yaw := Basis(Vector3.UP, camera.global_rotation.y)
	var direction := basis_yaw * Vector3(movement_input.x, 0, movement_input.y)
	velocity = direction * speed
	velocity.y = -1.0
	move_and_slide()

func update_xr(delta: float, stats: Node) -> void:
	valid_tracking = simulated_valid if simulated else (left.get_has_tracking_data() and right.get_has_tracking_data() and xr_interface != null and xr_interface.get_tracking_status() == XRInterface.XR_NORMAL_TRACKING)
	if not valid_tracking:
		reset_pose_history()
	else:
		var current := right.transform * Vector3(0, 0, -0.45)
		right_speed = current.distance_to(previous_right) / maxf(delta, 0.0001) if right_history else 0.0
		previous_right = current
		right_history = true
		blade_position = weapon.to_global(Vector3(0, 0, -0.45))
	xr_grip = xr_float("grip_value", false) > 0.6
	is_blocking = valid_tracking and xr_grip
	movement_input = xr_vector("move", true) if controls_enabled and not in_hub and valid_tracking else Vector2.ZERO
	# OpenXR thumbstick Y points up; Godot forward is negative Z.
	movement_input.y *= -1.0
	var turn := xr_vector("turn", false).x
	if absf(turn) < 0.25:
		turn_armed = true
	if controls_enabled and valid_tracking and absf(turn) > 0.7 and turn_armed:
		var pivot := camera.global_position
		rotate_y(-signf(turn) * PI / 4.0)
		global_position += pivot - camera.global_position
		turn_armed = false
		reset_pose_history()
	wrist.text = "HP %d/%d\nMP %d/%d\nFATIGUE %d\nX : STATUS" % [ceili(stats.hp), int(stats.max_hp()), ceili(stats.mp), int(stats.max_mp()), int(stats.fatigue)]
	bottle.visible = valid_tracking and not bottle_kind.is_empty() and xr_float("grip_value", true) > 0.6
	var mouth := camera.to_global(Vector3(0, -0.08, -0.08))
	var near_mouth := valid_tracking and bottle.visible and bottle.to_global(Vector3(0, 0.09, -0.1)).distance_to(mouth) < 0.15
	if near_mouth and not bottle_near and controls_enabled:
		intent.emit("drink_" + bottle_kind)
		bottle_kind = ""
	bottle_near = near_mouth

func xr_float(action: String, left_hand: bool) -> float:
	if simulated:
		return float(simulated_inputs.get(("left_" if left_hand else "right_") + action, 0.0))
	return left.get_float(action) if left_hand else right.get_float(action)

func xr_vector(action: String, left_hand: bool) -> Vector2:
	if simulated:
		return simulated_inputs.get(action, Vector2.ZERO)
	return left.get_vector2(action) if left_hand else right.get_vector2(action)

func xr_button(action: String) -> bool:
	return bool(simulated_inputs.get(action, false)) if simulated else left.is_button_pressed(action)

func feed_simulated_pose(head_pose: Transform3D, left_pose: Transform3D, right_pose: Transform3D, valid: bool, inputs: Dictionary = {}) -> void:
	if not simulated: return
	camera.transform = head_pose
	left.transform = left_pose
	right.transform = right_pose
	right_aim.transform = right_pose
	simulated_valid = valid
	simulated_inputs = inputs.duplicate()

func dash(stats: Node) -> bool:
	if dash_remaining > 0.0 or not controls_enabled or is_blocking:
		return false
	if not stats.try_add_fatigue(15.0, true):
		return false
	var input := movement_input if movement_input.length() > 0.1 else Vector2(0, 1)
	var direction := Basis(Vector3.UP, camera.global_rotation.y) * Vector3(input.x, 0, input.y).normalized()
	var collision := move_and_collide(direction * 3.0, true)
	var distance := maxf(0.0, collision.get_travel().length() - 0.3) if collision else 3.0
	move_and_collide(direction * distance)
	dash_remaining = stats.dash_cooldown()
	invulnerable = 0.2
	reset_pose_history()
	return true

func start_swing() -> bool:
	if swing_time >= 0.0 or is_blocking or invulnerable > 0.0:
		return false
	swing_time = 0.0
	return true

func place_at(location: Vector3) -> void:
	global_position = location
	rotation = Vector3.ZERO
	if not xr:
		head.rotation = Vector3.ZERO
	else:
		# Place physical head above the requested spawn without changing floor height.
		var offset := camera.global_position - global_position
		global_position.x -= offset.x
		global_position.z -= offset.z
	velocity = Vector3.ZERO
	dash_remaining = 0.0
	invulnerable = 0.0
	swing_time = -1.0
	bottle_kind = ""
	reset_pose_history()
