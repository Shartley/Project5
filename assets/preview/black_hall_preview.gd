@tool
extends Node3D
## Art preview of the Goblin Warren's Black Hall: a grid of stone pillars around an open
## clearing, fading into black fog in every direction, lit only by blue crystals on the
## nearest pillars. For judging the look of the hall pieces; not a gameplay scene.

const PILLAR := preload("res://assets/props/pillar.tscn")
const CRYSTAL := preload("res://assets/props/crystal_light.tscn")

## Pillar centres along each axis (metres). The ±4.6 rows leave a clearing about 8 m wide.
@export var grid: PackedFloat32Array = [-34.0, -28.0, -22.0, -16.0, -10.0, -4.6, 4.6, 10.0, 16.0, 22.0, 28.0, 34.0]
## Pillars within this distance of the centre (on both axes) get a crystal facing the clearing.
@export var crystal_reach := 10.5
## Height of the crystals on the pillar face.
@export var crystal_height := 2.1


func _ready() -> void:
	_build()


func _build() -> void:
	var holder := get_node_or_null("Pillars")
	if holder == null:
		return
	for child in holder.get_children():
		holder.remove_child(child)
		child.free()
	for z in grid:
		for x in grid:
			var pillar := PILLAR.instantiate()
			pillar.position = Vector3(x, 0.0, z)
			holder.add_child(pillar)
			if absf(x) <= crystal_reach and absf(z) <= crystal_reach:
				_add_crystal(holder, Vector3(x, 0.0, z))


func _add_crystal(holder: Node3D, pillar_pos: Vector3) -> void:
	# Mount on the pillar face that points most toward the clearing.
	var to_centre := -pillar_pos
	var face := Vector3(signf(to_centre.x), 0.0, 0.0) if absf(to_centre.x) > absf(to_centre.z) else Vector3(0.0, 0.0, signf(to_centre.z))
	var crystal := CRYSTAL.instantiate()
	crystal.position = pillar_pos + face * 0.62 + Vector3.UP * crystal_height
	holder.add_child(crystal)
	crystal.look_at(crystal.global_position - face, Vector3.UP)
