extends Node3D
## Art walkthrough: stand in the Goblin Warren's Black Hall holding the two daggers, with goblins
## and a gate portal around you. Runs in a VR headset when OpenXR starts; otherwise on the computer.
## This only shows the art. Nothing attacks, nothing can be hit; gameplay comes from the
## mechanic scripts (combat.gd, enemy.gd, gate.gd ...).
##
## Computer: WASD to move, mouse to look, Shift to walk faster, Esc to free the mouse.
## Headset: left stick to move, right stick to turn in 30-degree steps.

@export var move_speed := 2.0
@export var snap_turn_degrees := 30.0
@export var mouse_sensitivity := 0.0025

@onready var _xr_origin: XROrigin3D = $XROrigin3D
@onready var _xr_camera: XRCamera3D = $XROrigin3D/XRCamera3D
@onready var _left_hand: XRController3D = $XROrigin3D/LeftHand
@onready var _right_hand: XRController3D = $XROrigin3D/RightHand
@onready var _desktop: Node3D = $Desktop
@onready var _desktop_camera: Camera3D = $Desktop/Camera3D

var _vr := false
var _turn_ready := true
var _yaw := 0.0
var _pitch := 0.0


func _ready() -> void:
	var xr := XRServer.find_interface("OpenXR")
	_vr = xr != null and xr.is_initialized()
	if _vr:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		get_viewport().use_xr = true
		_desktop.queue_free()
		_xr_camera.current = true
	else:
		_xr_origin.queue_free()
		_desktop_camera.current = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if _vr:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * mouse_sensitivity
		_pitch = clampf(_pitch - event.relative.y * mouse_sensitivity, -1.3, 1.3)
		_desktop.rotation.y = _yaw
		_desktop_camera.rotation.x = _pitch
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(delta: float) -> void:
	if _vr:
		_move_vr(delta)
	else:
		_move_desktop(delta)


func _move_desktop(delta: float) -> void:
	var dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		dir.z -= 1.0
	if Input.is_key_pressed(KEY_S):
		dir.z += 1.0
	if Input.is_key_pressed(KEY_A):
		dir.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		dir.x += 1.0
	if dir == Vector3.ZERO:
		return
	var speed := move_speed * (2.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0)
	_desktop.position += _desktop.basis * dir.normalized() * speed * delta


func _move_vr(delta: float) -> void:
	var stick := _left_hand.get_vector2("primary")
	if stick.length() > 0.15:
		var forward := -_xr_camera.global_basis.z
		forward.y = 0.0
		var right := _xr_camera.global_basis.x
		right.y = 0.0
		var move := forward.normalized() * stick.y + right.normalized() * stick.x
		_xr_origin.global_position += move * move_speed * delta
	var turn := _right_hand.get_vector2("primary").x
	if absf(turn) > 0.7 and _turn_ready:
		_turn_ready = false
		_snap_turn(-signf(turn) * deg_to_rad(snap_turn_degrees))
	elif absf(turn) < 0.3:
		_turn_ready = true


func _snap_turn(angle: float) -> void:
	# Turn around the player's head, not the play-space centre, so they turn in place.
	var pivot := _xr_camera.global_position
	var t := _xr_origin.global_transform
	t.origin -= pivot
	t = t.rotated(Vector3.UP, angle)
	t.origin += pivot
	_xr_origin.global_transform = t
