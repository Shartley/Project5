extends CharacterBody3D
## An enemy (Rickey's Enemies mechanic, GDD 2.2): approaches, circles at 3 m until it gets an
## attack token, winds up, attacks, recovers. Hits can stagger it, a parry stuns it with 0 armor,
## and on death it plays its death animation and its body stays for 6 s. Types with a real model
## use it; the rest are still box stand-ins. Rocky's practice mode drives the same states.
const Art = preload("res://scripts/world_builder.gd")
const Rules = preload("res://scripts/models/combat_rules.gd")
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
var body_height: float = 1.6
var stunned_until: float = -1.0
var stagger_until: float = -1.0
var strafe_dir: float = 1.0
var summoned: bool = false
var collider: CollisionShape3D

func setup(data: Resource, practice: bool) -> void:
	definition = data
	training = practice
	hp = definition.health
	collision_layer = 2
	collision_mask = 1
	add_to_group("test_enemies")
	strafe_dir = 1.0 if randf() < 0.5 else -1.0
	collider = CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.5
	collider.shape = capsule
	add_child(collider)
	collider.position.y = 0.75
	var label_height := 1.92
	if MODEL_SCALE.has(definition.id):
		var size := float(MODEL_SCALE[definition.id])
		model = GOBLIN_MODEL.instantiate()
		model.scale = Vector3.ONE * size
		model.rotation.y = PI  # the model faces +Z; this body faces -Z after look_at
		add_child(model)
		torso = MeshInstance3D.new()  # invisible: kept so the shared tint and boss scaling still work
		add_child(torso)
		body_height = 1.3 * size
		capsule.height = maxf(1.5, body_height)
		capsule.radius = 0.32 * sqrt(size)
		collider.position.y = capsule.height * 0.5
		label_height = 1.45 * size + 0.25
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
		body_height = 0.6
		for i in range(3):
			Art.box(self, Vector3(0, 0.3, (i + 1) * 0.35), Vector3(0.65, 0.35, 0.3), definition.color.darkened(i * 0.1))
	if definition.id in ["chieftain", "kasaka"]:
		torso.scale *= 1.3

## Moves toward the target. With wants_attack false (no token yet, or not ready) it circles the
## player at about 3 m instead of closing in, as GDD 2.2 orders: Approach, Circle, Wind-up.
func approach(target: Vector3, delta: float, wants_attack: bool = true) -> void:
	var to_target := target - global_position
	to_target.y = 0.0
	var distance := to_target.length()
	if distance > 0.05:
		look_at(global_position + to_target, Vector3.UP)
	var move := Vector3.ZERO
	if wants_attack or distance > Rules.CIRCLE_DISTANCE + 0.6:
		var stop_at := minf(definition.reach - 0.25, 2.0) if wants_attack else Rules.CIRCLE_DISTANCE
		if distance > stop_at:
			move = to_target.normalized() * definition.speed
	elif distance > 0.05:
		var tangent := to_target.normalized().cross(Vector3.UP) * strafe_dir
		var radial := to_target.normalized() * (distance - Rules.CIRCLE_DISTANCE)
		move = (tangent * 0.55 + radial).limit_length(1.0) * definition.speed * 0.55
	velocity = move
	velocity.y = -1.0
	move_and_slide()
	if not wants_attack and get_slide_collision_count() > 0:
		strafe_dir = -strafe_dir  # bumped into a wall or another enemy: circle the other way
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
	impact_at = now + Rules.windup_time(definition.windup, hp, definition.health, definition.boss) / speed
	attack_id = id
	attempts.clear()
	parried = false
	attack_origin = global_position
	attack_direction = (target - global_position).normalized()
	warning.visible = training  # the countdown is a practice aid; in gates the red glow and sound warn
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
	ready_at = now + (Rules.STUN_TIME if stun else Rules.RECOVER_TIME)
	if stun:
		stunned_until = now + Rules.STUN_TIME
	warning.visible = false
	torso.material_override = Art.material(definition.color)
	if stun:
		play_model(&"hit", 0.5)  # a parry staggers it
	elif not swung:
		play_model(&"attack", 0.5)

## Short stagger after a heavy blow: cancels a wind-up, which gives its attack token back.
func stagger(now: float) -> void:
	state = "recover"
	stagger_until = now + Rules.STAGGER_TIME
	ready_at = maxf(ready_at, now + Rules.STAGGER_TIME)
	warning.visible = false
	torso.material_override = Art.material(definition.color)
	play_model(&"hit", Rules.STAGGER_TIME)

func is_stunned(now: float) -> bool:
	return now < stunned_until

## Applies a hit of `raw` damage (before armor). Armor is 0 while stunned by a parry.
## Returns {dealt, killed, staggered}.
func receive_hit(raw: float, now: float) -> Dictionary:
	var result := {"dealt": 0, "killed": false, "staggered": false}
	if training or state == "dying":
		return result
	var armor: float = 0.0 if is_stunned(now) else definition.armor
	var dealt := maxi(0, roundi(raw - armor))
	hp = maxf(0.0, hp - dealt)
	result.dealt = dealt
	result.killed = hp <= 0.0
	title.text = "%s / %d HP" % [definition.display_name, ceili(hp)]
	if not result.killed:
		if Rules.staggers(dealt, definition.health, definition.boss):
			stagger(now)
			result.staggered = true
		elif state != "windup":
			play_model(&"hit", 0.35)
	return result

## Death: stop colliding and attacking, play the death animation, and remove the body after
## BODY_STAYS seconds (GDD 2.2; a full ragdoll can replace the animation later).
func die() -> void:
	state = "dying"
	velocity = Vector3.ZERO
	warning.visible = false
	title.visible = false
	collision_layer = 0
	collision_mask = 1
	if model != null:
		play_model(&"death", 99.0)
	else:
		rotation.x = -PI / 2.0
		position.y += 0.3
	get_tree().create_timer(Rules.BODY_STAYS).timeout.connect(queue_free)

func blade_tip() -> Vector3:
	return weapon.to_global(Vector3(0, 0, -0.85))
