extends Node3D
## Primitive art for Rocky's independent slice; replace the content node for real gates.
const NAVY := Color("0b1a2e")
const BLUE := Color("3fb8ff")
const GOLD := Color("ffc94a")
var portal_material: StandardMaterial3D
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
	if kind == "hub":
		build_hub()
	else:
		label(self, "PRACTICE CHAMBER" if kind == "training" else "PENALTY ZONE", Vector3(0, 2.3, -extent + 0.14), 58, BLUE if kind == "training" else GOLD)
		label(self, "READ THE WIND-UP. FIND YOUR MOMENT." if kind == "training" else "SURVIVE 180 SECONDS", Vector3(0, 1.9, -extent + 0.13), 24)

func build_hub() -> void:
	var frame := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.85
	torus.outer_radius = 1.0
	torus.rings = 16
	torus.ring_segments = 6
	frame.mesh = torus
	frame.material_override = material(Color("3c536b"))
	add_child(frame)
	frame.position = Vector3(0, 1.2, -2.78)
	frame.rotation.x = PI / 2.0
	frame.scale = Vector3(0.8, 1.0, 1.1)
	var disk := MeshInstance3D.new()
	var circle := CylinderMesh.new()
	circle.top_radius = 0.83
	circle.bottom_radius = 0.83
	circle.height = 0.025
	circle.radial_segments = 24
	disk.mesh = circle
	portal_material = material(Color("183e58"), true)
	disk.material_override = portal_material
	frame.add_child(disk)
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
	if portal_material:
		portal_material.albedo_color = BLUE if value else Color("183e58")
