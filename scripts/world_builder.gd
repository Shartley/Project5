extends Node3D
## Primitive art for Rocky's independent slice; replace the content node for real gates.
const NAVY := Color("0b1a2e")
const BLUE := Color("3fb8ff")
const GOLD := Color("ffc94a")
const PORTAL_SCENE = preload("res://assets/props/portal/portal.tscn")
const PILLAR_SCENE = preload("res://assets/props/pillar.tscn")
const CRYSTAL_SCENE = preload("res://assets/props/crystal_light.tscn")
const FLOOR_MATERIAL = preload("res://assets/materials/warren_floor.tres")
const STONE_MATERIAL = preload("res://assets/materials/warren_pillar.tres")
var portal_material: StandardMaterial3D
var portal: Node3D
var exit_portal: Node3D
var pad: MeshInstance3D
var punch_targets: Array[Node3D] = []

static func material(color: Color, glow: bool = false) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 0.9
	if glow:
		result.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return result

static func box(parent: Node3D, location: Vector3, size: Vector3, color: Color, solid: bool = false) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var shape := BoxMesh.new()
	shape.size = size
	mesh.mesh = shape
	mesh.material_override = material(color)
	parent.add_child(mesh)
	mesh.position = location
	if solid:
		var body := StaticBody3D.new()
		mesh.add_child(body)
		var collider := CollisionShape3D.new()
		var collision := BoxShape3D.new()
		collision.size = size
		collider.shape = collision
		body.add_child(collider)
	return mesh

static func label(parent: Node3D, text: String, location: Vector3, size: int = 40, color: Color = Color("dadada")) -> Label3D:
	var result := Label3D.new()
	result.text = text
	result.font_size = size
	result.pixel_size = 0.005
	result.modulate = color
	result.outline_size = 6
	result.outline_modulate = NAVY
	parent.add_child(result)
	result.position = location
	return result

func build(kind: String) -> void:
	var extent := 3.0 if kind == "hub" else (5.0 if kind == "training" else 10.0)
	if kind == "warren":
		build_warren(extent)
		return
	if kind != "hub":
		build_stone_room(kind, extent)
		return
	box(self, Vector3(0, -0.15, 0), Vector3(extent * 2, 0.3, extent * 2), Color("1c2e41"), true)
	for x in range(-int(extent), int(extent) + 1):
		box(self, Vector3(x, 0.006, 0), Vector3(0.014, 0.01, extent * 2), Color("2c455a"))
		box(self, Vector3(0, 0.006, x), Vector3(extent * 2, 0.01, 0.014), Color("2c455a"))
	for side in [-1, 1]:
		box(self, Vector3(side * extent, 1.5, 0), Vector3(0.2, 3.0, extent * 2), NAVY, true)
		box(self, Vector3(0, 1.5, side * extent), Vector3(extent * 2, 3.0, 0.2), NAVY, true)
		box(self, Vector3(side * (extent - 0.12), 0.12, 0), Vector3(0.035, 0.06, extent * 2), BLUE)
		box(self, Vector3(0, 0.12, side * (extent - 0.12)), Vector3(extent * 2, 0.06, 0.035), BLUE)
	for x in [-extent + 0.3, extent - 0.3]:
		for z in [-extent + 0.3, extent - 0.3]:
			box(self, Vector3(x, 1.4, z), Vector3(0.3, 2.8, 0.3), Color("344658"))
	build_hub()

## Training and the Penalty Zone in the Black Hall look: stone floor and walls, pillars in the
## corners with blue crystal lights, and the dark fog set by main.gd. Same size and collision as
## the stand-in rooms.
func build_stone_room(kind: String, extent: float) -> void:
	var ground := box(self, Vector3(0, -0.15, 0), Vector3(extent * 2, 0.3, extent * 2), Color("1c2e41"), true)
	ground.visible = false  # collision only; the textured plane below is what you see
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(extent * 2, extent * 2)
	floor_mesh.mesh = plane
	var floor_material: BaseMaterial3D = FLOOR_MATERIAL.duplicate()
	floor_material.uv1_scale = Vector3(extent, extent, 1)  # one 2 m stone tile per 2 m
	floor_mesh.material_override = floor_material
	add_child(floor_mesh)
	for side in [-1, 1]:
		box(self, Vector3(side * extent, 1.5, 0), Vector3(0.2, 3.0, extent * 2), NAVY, true).material_override = STONE_MATERIAL
		box(self, Vector3(0, 1.5, side * extent), Vector3(extent * 2, 3.0, 0.2), NAVY, true).material_override = STONE_MATERIAL
		box(self, Vector3(side * (extent - 0.12), 0.12, 0), Vector3(0.035, 0.06, extent * 2), BLUE)
		box(self, Vector3(0, 0.12, side * (extent - 0.12)), Vector3(extent * 2, 0.06, 0.035), BLUE)
	var inset := extent - 1.0
	for x in [-inset, inset]:
		for z in [-inset, inset]:
			var pillar: Node3D = PILLAR_SCENE.instantiate()
			pillar.position = Vector3(x, 0, z)
			add_child(pillar)
			var to_centre := Vector3(-x, 0, -z).normalized()
			var crystal: Node3D = CRYSTAL_SCENE.instantiate()
			add_child(crystal)
			crystal.position = Vector3(x, 2.1, z) + to_centre * 0.85
			crystal.look_at(crystal.position - to_centre, Vector3.UP)
	# One more crystal halfway along the side and far walls (not behind the spawn point). With the
	# corners and the player's light that is 8 lights, the per-object limit on Quest.
	for facing in [Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]:
		var crystal: Node3D = CRYSTAL_SCENE.instantiate()
		add_child(crystal)
		crystal.position = -facing * (extent - 0.15) + Vector3(0, 2.1, 0)
		crystal.look_at(crystal.position - facing, Vector3.UP)
	var probe := ReflectionProbe.new()  # gives the steel something to reflect
	probe.size = Vector3(extent * 2, 4.0, extent * 2)
	probe.position = Vector3(0, 1.8, 0)
	probe.interior = true
	add_child(probe)
	label(self, "PRACTICE CHAMBER" if kind == "training" else "PENALTY ZONE", Vector3(0, 2.3, -extent + 0.14), 58, BLUE if kind == "training" else GOLD)
	label(self, "READ THE WIND-UP. FIND YOUR MOMENT." if kind == "training" else "SURVIVE 180 SECONDS", Vector3(0, 1.9, -extent + 0.13), 24)

## The Goblin Warren as one Black Hall arena (Rickey's combat test until gate.gd builds the real
## rooms): open stone floor inside invisible walls, rings of pillars fading into the fog, crystals
## along the sides and none at the far end, so enemies walk out of the dark.
func build_warren(extent: float) -> void:
	var ground := box(self, Vector3(0, -0.15, 0), Vector3(extent * 2, 0.3, extent * 2), Color("1c2e41"), true)
	ground.visible = false
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 60)
	floor_mesh.mesh = plane
	var floor_material: BaseMaterial3D = FLOOR_MATERIAL.duplicate()
	floor_material.uv1_scale = Vector3(30, 30, 1)
	floor_mesh.material_override = floor_material
	add_child(floor_mesh)
	for side in [-1, 1]:  # invisible edges keep the fight inside the lit area
		box(self, Vector3(side * extent, 1.5, 0), Vector3(0.2, 3.0, extent * 2), NAVY, true).visible = false
		box(self, Vector3(0, 1.5, side * extent), Vector3(extent * 2, 3.0, 0.2), NAVY, true).visible = false
	var rows := [-17.0, -11.5, -5.75, 0.0, 5.75, 11.5, 17.0]
	for x in rows:
		for z in rows:
			if maxf(absf(x), absf(z)) < 11.5:
				continue
			var pillar: Node3D = PILLAR_SCENE.instantiate()
			pillar.position = Vector3(x, 0, z)
			add_child(pillar)
	for x in [-11.5, 11.5]:  # crystals on the side pillars only: the far end stays dark
		for z in [-5.75, 0.0, 5.75]:
			var facing := Vector3(-signf(x), 0, 0)
			var crystal: Node3D = CRYSTAL_SCENE.instantiate()
			add_child(crystal)
			crystal.position = Vector3(x, 2.1, z) + facing * 0.65
			crystal.look_at(crystal.position - facing, Vector3.UP)
	var probe := ReflectionProbe.new()
	probe.size = Vector3(24, 6, 24)
	probe.position = Vector3(0, 2.5, 0)
	probe.interior = true
	add_child(probe)
	exit_portal = PORTAL_SCENE.instantiate()
	add_child(exit_portal)
	exit_portal.position = Vector3(0, 0, -9.2)
	exit_portal.visible = false
	exit_portal.active = false

## Shows the exit portal after the boss and returns its entry area so main.gd can listen to it.
func open_exit() -> Area3D:
	exit_portal.visible = true
	exit_portal.active = true
	return exit_portal.get_node("EnterArea")

func build_hub() -> void:
	portal = PORTAL_SCENE.instantiate()
	portal.scale = Vector3.ONE * 0.85  # fits the 6 m hub's back wall
	add_child(portal)
	portal.position = Vector3(0, 0, -2.62)
	portal.active = false
	label(self, "AWAKENING", Vector3(0, 2.65, -2.8), 55, BLUE)
	label(self, "THE SYSTEM / PERSONAL CHAMBER", Vector3(0, 2.42, -2.8), 18)
	pad = box(self, Vector3(0, 0.04, 0), Vector3(1.6, 0.08, 1.6), Color("224e64"))
	for side in [-1, 1]:
		box(self, Vector3(side * 0.8, 0.09, 0), Vector3(0.025, 0.02, 1.6), BLUE)
		box(self, Vector3(0, 0.09, side * 0.8), Vector3(1.6, 0.02, 0.025), BLUE)
	label(self, "01 / DAILY QUEST", Vector3(-1.7, 1.7, -2.78), 24, GOLD)
	label(self, "5 SQUATS\n10 PUNCHES\n5 SQUATS\n10 PUNCHES", Vector3(-1.7, 1.1, -2.78), 20)
	label(self, "02 / TRAINING", Vector3(1.7, 1.7, -2.78), 24, BLUE)
	label(self, "LEARN THE TIMING\nMASTER YOUR ENEMY\n\nESC > TRAINING", Vector3(1.7, 1.05, -2.78), 18)
	for side in [-1, 1]:
		var target := box(self, Vector3(side * 0.35, 1.25, -0.55), Vector3(0.22, 0.22, 0.12), BLUE)
		target.visible = false
		punch_targets.append(target)

func set_portal_open(value: bool) -> void:
	if portal:
		portal.active = value
	if portal_material:
		portal_material.albedo_color = BLUE if value else Color("183e58")
