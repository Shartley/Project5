extends Node3D
## The Goblin's look: plays its animations and sets its eye glow. Gameplay (moving, attacking,
## health) belongs in enemy.gd, which calls play() on this node.
##
## Animations: idle, walk (both loop), windup (0.8 s), attack, hit, death.
## Eyes glow System Blue, and turn Warning Red for the wind-up so the attack can be read
## from the pose AND the colour (the GDD's "never red alone" rule).

@export var idle_eye_color := Color("3FB8FF")
@export var windup_eye_color := Color("E5383B")
@export_range(0.0, 8.0) var eye_glow := 1.1
## Animation played when the goblin appears (handy for previews and set dressing).
@export var start_animation: StringName = &"idle"

var _anim: AnimationPlayer
var _eye_material: StandardMaterial3D


func _ready() -> void:
	_anim = find_child("AnimationPlayer", true, false) as AnimationPlayer
	var eyes := find_child("GoblinEyes", true, false) as MeshInstance3D
	if eyes != null and eyes.get_active_material(0) is StandardMaterial3D:
		# Each goblin gets its own copy, so one winding up does not turn every goblin red.
		_eye_material = eyes.get_active_material(0).duplicate()
		_eye_material.emission_enabled = true
		_eye_material.emission_energy_multiplier = eye_glow
		eyes.set_surface_override_material(0, _eye_material)
	play(start_animation, 0.0)


## Plays an animation by name with a short blend. Unknown names are ignored with a warning.
func play(anim_name: StringName, blend := 0.15) -> void:
	if _anim == null:
		return
	if not _anim.has_animation(anim_name):
		push_warning("Goblin has no animation '%s'" % anim_name)
		return
	_anim.play(anim_name, blend)
	set_eye_color(windup_eye_color if anim_name == &"windup" or anim_name == &"attack" else idle_eye_color)


func set_eye_color(color: Color) -> void:
	if _eye_material != null:
		_eye_material.emission = color
