extends CharacterBody3D
## Minimal replaceable attacker, not the team's production enemy AI.
const Art = preload("res://scripts/world_builder.gd")
var definition: Resource
var training: bool = false
var hp: float = 40.0
var state: String = "approach"
var windup_start: float = 0.0
var impact_at: float = 0.0
var ready_at: float = 0.0
var attack_id: int = -1
var attempts: Array[float] = []
var parried: bool = false
var weapon: Node3D
var torso: MeshInstance3D
var title: Label3D
var warning: Label3D
var attack_origin: Vector3
var attack_direction: Vector3

func setup(data: Resource, practice: bool) -> void:
	definition = data
	training = practice
	hp = definition.health
	collision_layer = 2
	collision_mask = 1
	add_to_group("test_enemies")
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.5
	collider.shape = capsule
	add_child(collider)
	collider.position.y = 0.75
	torso = Art.box(self, Vector3(0, 0.85, 0), Vector3(0.65, 0.72, 0.4), definition.color)
	Art.box(self, Vector3(0, 1.4, 0), Vector3(0.43, 0.4, 0.4), definition.color.lightened(0.15))
	for side in [-1, 1]:
		Art.box(self, Vector3(side * 0.18, 0.25, 0), Vector3(0.2, 0.5, 0.25), Color("172c3a"))
		Art.box(self, Vector3(side * 0.11, 1.45, -0.211), Vector3(0.075, 0.04, 0.02), Art.GOLD)
	weapon = Node3D.new()
	add_child(weapon)
	weapon.position = Vector3(-0.5, 1.1, 0)
	Art.box(weapon, Vector3(0, 0, -0.4), Vector3(0.08, 0.08, 0.85), Color("dadada"))
	title = Art.label(self, definition.display_name, Vector3(0, 1.92, 0), 25)
	title.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	warning = Art.label(self, "!", Vector3(0, 2.3, 0), 75, Color("e5383b"))
	warning.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	warning.visible = false
	if definition.id == "centipede":
		for i in range(3):
			Art.box(self, Vector3(0, 0.3, (i + 1) * 0.35), Vector3(0.65, 0.35, 0.3), definition.color.darkened(i * 0.1))
	if definition.id in ["chieftain", "kasaka"]:
		torso.scale *= 1.3

func approach(target: Vector3, delta: float) -> void:
	var direction := target - global_position
	direction.y = 0.0
	if direction.length() > 0.05:
		look_at(global_position + direction, Vector3.UP)
	velocity = direction.normalized() * definition.speed if direction.length() > minf(definition.reach - 0.25, 2.0) else Vector3.ZERO
	velocity.y = -1.0
	move_and_slide()
	weapon.rotation.x = lerpf(weapon.rotation.x, 0.0, delta * 8.0)

func begin_attack(now: float, speed: float, id: int, target: Vector3) -> void:
	state = "windup"
	windup_start = now
	impact_at = now + definition.windup / speed
	attack_id = id
	attempts.clear()
	parried = false
	attack_origin = global_position
	attack_direction = (target - global_position).normalized()
	warning.visible = true
	torso.material_override = Art.material(Color("e5383b"))

func animate_windup(now: float) -> void:
	var progress := clampf((now - windup_start) / (impact_at - windup_start), 0.0, 1.0)
	weapon.rotation.x = -0.9 * sin(progress * PI)
	warning.text = "!  %.2f" % maxf(0.0, impact_at - now)

func recover(now: float, stun: bool = false) -> void:
	state = "recover"
	ready_at = now + (1.5 if stun else 1.0)
	warning.visible = false
	torso.material_override = Art.material(definition.color)

func take_hit(amount: float) -> bool:
	if training:
		return false
	hp = maxf(0.0, hp - maxf(0.0, amount - definition.armor))
	title.text = "%s / %d HP" % [definition.display_name, ceili(hp)]
	return hp <= 0.0

func blade_tip() -> Vector3:
	return weapon.to_global(Vector3(0, 0, -0.85))
