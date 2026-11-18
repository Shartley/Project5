extends CharacterBody3D
## Minimal replaceable attacker, not the team's production enemy AI.
const Art = preload("res://scripts/world_builder.gd")
const GOBLIN_MODEL = preload("res://assets/models/enemies/goblin/goblin.tscn")
## Enemy types that already have real models, with the scale to show them at.
const MODEL_SCALE := {"goblin": 1.0, "chieftain": 1.5}
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
var model: Node3D  # real art when this type has a model; null keeps the box stand-in
var model_anim: StringName = &""
var anim_lock: float = 0.0
var swung: bool = false

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
	var label_height := 1.92
	if MODEL_SCALE.has(definition.id):
		model = GOBLIN_MODEL.instantiate()
		model.scale = Vector3.ONE * float(MODEL_SCALE[definition.id])
		model.rotation.y = PI  # the model faces +Z; this body faces -Z after look_at
		add_child(model)
		torso = MeshInstance3D.new()  # invisible: kept so the shared tint and boss scaling still work
		add_child(torso)
		label_height = 1.45 * float(MODEL_SCALE[definition.id]) + 0.25
	else:
		torso = Art.box(self, Vector3(0, 0.85, 0), Vector3(0.65, 0.72, 0.4), definition.color)
		Art.box(self, Vector3(0, 1.4, 0), Vector3(0.43, 0.4, 0.4), definition.color.lightened(0.15))
		for side in [-1, 1]:
			Art.box(self, Vector3(side * 0.18, 0.25, 0), Vector3(0.2, 0.5, 0.25), Color("172c3a"))
			Art.box(self, Vector3(side * 0.11, 1.45, -0.211), Vector3(0.075, 0.04, 0.02), Art.GOLD)
	weapon = Node3D.new()
	add_child(weapon)
	weapon.position = Vector3(-0.5, 1.1, 0)
	if model == null:
		Art.box(weapon, Vector3(0, 0, -0.4), Vector3(0.08, 0.08, 0.85), Color("dadada"))
	title = Art.label(self, definition.display_name, Vector3(0, label_height, 0), 25)
	title.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	warning = Art.label(self, "!", Vector3(0, label_height + 0.38, 0), 75, Color("e5383b"))
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
	if model != null:
		anim_lock = maxf(0.0, anim_lock - delta)
		if anim_lock <= 0.0:
			play_model(&"walk" if Vector2(velocity.x, velocity.z).length() > 0.1 else &"idle")

func play_model(anim: StringName, lock: float = 0.0) -> void:
	if model == null or (anim == model_anim and lock <= 0.0):
		return
	model_anim = anim
	anim_lock = lock
	model.play(anim, 0.08 if lock > 0.0 else 0.2)

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
	swung = false
	play_model(&"windup", 99.0)

func animate_windup(now: float) -> void:
	var progress := clampf((now - windup_start) / (impact_at - windup_start), 0.0, 1.0)
	weapon.rotation.x = -0.9 * sin(progress * PI)
	# Start the swing a little before impact so the club comes down as the hit lands.
	if model != null and not swung and now >= impact_at - 0.2:
		swung = true
		play_model(&"attack", 0.6)
	warning.text = "!  %.2f" % maxf(0.0, impact_at - now)

func recover(now: float, stun: bool = false) -> void:
	state = "recover"
	ready_at = now + (1.5 if stun else 1.0)
	warning.visible = false
	torso.material_override = Art.material(definition.color)
	if stun:
		play_model(&"hit", 0.5)  # a parry staggers it
	elif not swung:
		play_model(&"attack", 0.5)

func take_hit(amount: float) -> bool:
	if training:
		return false
	hp = maxf(0.0, hp - maxf(0.0, amount - definition.armor))
	if state != "windup":
		play_model(&"hit", 0.35)
	title.text = "%s / %d HP" % [definition.display_name, ceili(hp)]
	return hp <= 0.0

func blade_tip() -> Vector3:
	return weapon.to_global(Vector3(0, 0, -0.85))
