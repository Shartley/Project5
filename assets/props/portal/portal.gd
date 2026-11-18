@tool
extends Node3D
## A gate portal: the stone frame, the swirling light inside it, its glow and drifting sparks.
## Set gate_color to System Blue for normal gates or Warning Red for Red gates (Kasaka's Nest).
## active = false shows a dim, still portal (locked); true makes it swirl and glow.
## gate.gd can listen to EnterArea.body_entered to start the gate.

const SYSTEM_BLUE := Color("3FB8FF")
const WARNING_RED := Color("E5383B")

@export var gate_color := SYSTEM_BLUE:
	set(value):
		gate_color = value
		_apply()
@export_range(0.0, 6.0) var intensity := 2.4:
	set(value):
		intensity = value
		_apply()
@export var active := true:
	set(value):
		active = value
		_apply()


func _ready() -> void:
	_apply()


func _apply() -> void:
	if not is_inside_tree():
		return
	var swirl := get_node_or_null("Swirl") as MeshInstance3D
	if swirl != null and swirl.get_surface_override_material(0) is ShaderMaterial:
		var mat := swirl.get_surface_override_material(0) as ShaderMaterial
		mat.set_shader_parameter("glow_color", gate_color)
		mat.set_shader_parameter("intensity", intensity if active else intensity * 0.15)
		mat.set_shader_parameter("swirl_speed", 0.25 if active else 0.03)
	var light := get_node_or_null("Glow") as OmniLight3D
	if light != null:
		light.light_color = gate_color
		light.light_energy = 2.5 if active else 0.3
	var sparks := get_node_or_null("Sparks") as CPUParticles3D
	if sparks != null:
		sparks.color = gate_color * 1.6
		sparks.emitting = active
