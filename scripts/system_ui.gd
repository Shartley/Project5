extends Control
signal action(id: String, payload: Variant)
const NAVY := Color("0b1a2e")
const BLUE := Color("3fb8ff")
const GOLD := Color("ffc94a")
const WHITE := Color("dadada")
var game: Node
var page: String = ""
var resources: Dictionary = {}
var bar_labels: Dictionary = {}
var status: Label
var context: Label
var objective: Label
var prompt: Label
var toast_label: Label
var controls: Label
var overlay: ColorRect
var body: VBoxContainer
var page_title: Label
var stat_labels: Dictionary = {}
var stat_buttons: Dictionary = {}
var points_label: Label
var low_hp: Panel
var toast_left: float = 0.0
var enemy_one: OptionButton
var enemy_two: OptionButton
var speed_choice: OptionButton
var debug_indicator: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = create_theme()
	var top := MarginContainer.new()
	add_child(top)
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.add_theme_constant_override("margin_left", 28)
	top.add_theme_constant_override("margin_top", 22)
	top.add_theme_constant_override("margin_right", 28)
	var header := HBoxContainer.new()
	top.add_child(header)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 300
	header.add_child(left)
	status = text(left, "THE SYSTEM", 24, BLUE)
	for kind in ["HP", "MP", "FATIGUE"]:
		var row := HBoxContainer.new()
		left.add_child(row)
		var title := text(row, kind, 14)
		title.custom_minimum_size.x = 76
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(145, 14)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.show_percentage = false
		bar.add_theme_stylebox_override("background", style(Color("142436"), 2))
		bar.add_theme_stylebox_override("fill", style(Color("dd6062") if kind == "HP" else (BLUE if kind == "MP" else GOLD), 2))
		row.add_child(bar)
		resources[kind] = bar
		bar_labels[kind] = text(row, "100/100", 14)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var right := VBoxContainer.new()
	header.add_child(right)
	context = text(right, "PERSONAL CHAMBER", 22)
	context.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	objective = text(right, "Complete your daily workout", 16, BLUE)
	objective.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	debug_indicator = text(right, "", 13, GOLD)
	debug_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var center := Label.new()
	center.text = "+"
	center.add_theme_color_override("font_color", Color(0.85, 0.94, 1, 0.6))
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	prompt = Label.new()
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.add_theme_font_size_override("font_size", 28)
	prompt.add_theme_color_override("font_color", BLUE)
	prompt.add_theme_color_override("font_outline_color", NAVY)
	prompt.add_theme_constant_override("outline_size", 6)
	add_child(prompt)
	prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	prompt.offset_left = -600
	prompt.offset_right = 600
	prompt.offset_top = -180
	prompt.offset_bottom = -80
	prompt.add_theme_font_size_override("font_size", 23)
	toast_label = Label.new()
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.add_theme_font_size_override("font_size", 20)
	toast_label.add_theme_color_override("font_color", GOLD)
	add_child(toast_label)
	toast_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	toast_label.offset_left = -500
	toast_label.offset_right = 500
	toast_label.offset_top = 155
	toast_label.offset_bottom = 215
	toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls = Label.new()
	controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controls.add_theme_font_size_override("font_size", 15)
	add_child(controls)
	controls.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	controls.offset_top = -65
	controls.offset_bottom = -15
	low_hp = Panel.new()
	var warning_style := style(Color(0, 0, 0, 0), 0)
	warning_style.border_color = Color(0.9, 0.15, 0.18, 0.5)
	warning_style.set_border_width_all(8)
	low_hp.add_theme_stylebox_override("panel", warning_style)
	low_hp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(low_hp)
	low_hp.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	low_hp.hide()
	overlay = ColorRect.new()
	overlay.color = Color(0.01, 0.025, 0.045, 0.78)
	add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	overlay.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -340
	panel.offset_right = 340
	panel.offset_top = -300
	panel.offset_bottom = 300
	var margin := MarginContainer.new()
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 24)
	panel.add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 16)
	margin.add_child(stack)
	var heading := HBoxContainer.new()
	stack.add_child(heading)
	page_title = text(heading, "SYSTEM", 28, BLUE)
	page_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button(heading, "Close", func(): action.emit("close", null))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	stack.add_child(scroll)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	scroll.add_child(body)
	overlay.hide()
	PlayerStats.changed.connect(refresh_stats)
	refresh_stats()

static func style(color: Color, radius: int = 6) -> StyleBoxFlat:
	var result := StyleBoxFlat.new()
	result.bg_color = color
	result.set_corner_radius_all(radius)
	result.set_content_margin_all(10)
	return result

static func create_theme() -> Theme:
	var result := Theme.new()
	result.default_font_size = 18
	result.set_color("font_color", "Label", WHITE)
	result.set_color("font_color", "Button", WHITE)
	var panel := style(NAVY)
	panel.border_color = Color("295274")
	panel.set_border_width_all(2)
	result.set_stylebox("panel", "PanelContainer", panel)
	for type in ["Button", "OptionButton"]:
		result.set_stylebox("normal", type, style(Color("1b354e")))
		result.set_stylebox("hover", type, style(Color("275678")))
		result.set_stylebox("pressed", type, style(Color("326b90")))
		result.set_stylebox("disabled", type, style(Color("142638")))
		var focus := style(Color(0, 0, 0, 0))
		focus.border_color = BLUE
		focus.set_border_width_all(2)
		result.set_stylebox("focus", type, focus)
	return result

func text(parent: Node, value: String, size: int = 18, color: Color = WHITE) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func paragraph(value: String, color: Color = WHITE) -> void:
	var label := text(body, value, 18, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

func button(parent: Node, title: String, callback: Callable) -> Button:
	var result := Button.new()
	result.text = title
	result.custom_minimum_size.y = 42
	result.pressed.connect(callback)
	parent.add_child(result)
	return result

func show_page(id: String) -> void:
	page = id
	overlay.visible = not id.is_empty()
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()
	stat_labels.clear()
	stat_buttons.clear()
	points_label = null
	match id:
		"welcome", "pause":
			page_title.text = "AWAKENING" if id == "welcome" else "SYSTEM / PAUSED"
			paragraph("Rocky's playable slice: build your stats, finish the daily workout, and master enemy timing.")
			button(body, "Enter chamber" if id == "welcome" else "Resume", func(): action.emit("close", null))
			if game.room == "hub":
				if Progress.portals_open:
					button(body, "Enter the Goblin Warren", func(): action.emit("warren", null))
				if Progress.workout_state == "available":
					button(body, "Begin daily workout", func(): action.emit("workout", null))
				if Progress.workout_state != "active":
					button(body, "Training", func(): action.emit("training", null))
				else:
					button(body, "Abandon workout / enter Penalty Zone", func(): action.emit("abandon", null))
			elif game.room == "training":
				button(body, "Configure training", func(): action.emit("configure", null))
				button(body, "Leave training", func(): action.emit("hub", null))
			elif game.room == "warren":
				button(body, "Leave the Goblin Warren", func(): action.emit("hub", null))
			button(body, "Status & potions", func(): action.emit("stats", null))
			if OS.is_debug_build():
				button(body, "Test controls / F1", func(): action.emit("debug_page", null))
			paragraph("Left stick move / click sprint / right stick snap turn\nX status / Menu pause / A start workout\nGrip dagger to block or parry / left grip + lunge to dash\nMenus: right ray + trigger, or poke / right stick scroll" if game.xr_enabled else "WASD move  /  mouse look  /  Shift sprint\nE interact  /  Tab status  /  Esc pause\nLeft click attack  /  Right click block & parry  /  Space dash", Color("8fa9bd"))
		"stats":
			page_title.text = "SYSTEM / STATUS"
			points_label = text(body, "", 20, GOLD)
			points_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			var descriptions := ["+2% damage", "+10 HP, 0.5% mitigation", "Faster dash & Fatigue recovery", "+4 ms parry, +1% critical", "+2 MP, stronger shadows"]
			for i in range(PlayerStats.STAT_NAMES.size()):
				var stat: String = PlayerStats.STAT_NAMES[i]
				var row := HBoxContainer.new()
				body.add_child(row)
				var label := text(row, "", 18)
				label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				stat_labels[stat] = label
				var description := text(row, descriptions[i], 14, Color("8fa9bd"))
				description.custom_minimum_size.x = 240
				stat_buttons[stat] = button(row, "+", func(): PlayerStats.spend_point(stat))
			paragraph("Points are permanent for this session. Bonuses start above 10.", Color("8fa9bd"))
			var potion_row := HBoxContainer.new()
			body.add_child(potion_row)
			for kind in ["health", "mana", "tonic"]:
				var potion_button := button(potion_row, ("Hold " if game.xr_enabled else "Use ") + kind.capitalize(), func(): action.emit("potion", kind))
				potion_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			refresh_stats()
		"training":
			page_title.text = "SYSTEM / TRAINING"
			paragraph("Select one or two opponents. Seven Perfect parries in ten attacks at full speed against one type earns mastery.")
			enemy_one = enemy_selector(false)
			enemy_two = enemy_selector(true)
			speed_choice = OptionButton.new()
			for label in ["100% speed / mastery enabled", "75% speed / practice", "50% speed / practice"]:
				speed_choice.add_item(label)
			body.add_child(speed_choice)
			button(body, "Begin round", func():
				var types: Array[String] = [enemy_one.get_item_metadata(enemy_one.selected)]
				var second: String = enemy_two.get_item_metadata(enemy_two.selected)
				if not second.is_empty(): types.append(second)
				action.emit("start_training", {"types": types, "speed": [1.0, 0.75, 0.5][speed_choice.selected]})
			)
			paragraph("Mastered: " + (", ".join(Progress.mastered_types) if not Progress.mastered_types.is_empty() else "none yet"), GOLD)
			paragraph(game.practice.last_report, BLUE)
			button(body, "Return to hub", func(): action.emit("hub", null))
		"debug":
			page_title.text = "SYSTEM / TEST CONTROLS"
			paragraph("These controls change this session. Reset restores all starting values and rewards.", GOLD)
			var commands := {"xp": "+200 XP", "points": "+5 stat points", "damage": "Take 25 damage", "low_hp": "Level 5 / low HP scenario", "mp": "Empty MP", "fatigue": "Fatigue 100 / lock sprint and dash", "rest": "Advance resource recovery 5 seconds", "potions": "Refill potion inventory", "awake": "Toggle awake-enemy test override", "portals": "Open portals (skip the workout)", "warren": "Simulate Warren clear", "nest": "Simulate Nest clear", "shadow": "Simulate stored Spitter shadow", "penalty": "Enter Penalty Zone", "advance_penalty": "Advance Penalty clock 30 seconds", "mastery": "Set up 6 Perfect / 3 late round", "simulate_squat": "Replay XR squat sample", "simulate_punch": "Replay XR punch sample", "reset": "Reset entire session"}
			for command: String in commands:
				button(body, commands[command], func(): action.emit("debug", command))

func enemy_selector(optional: bool) -> OptionButton:
	var picker := OptionButton.new()
	if optional:
		picker.add_item("Second opponent: none")
		picker.set_item_metadata(0, "")
	for enemy_type: String in Progress.unlocked_types:
		picker.add_item(enemy_type.capitalize() + (" / Mastered" if Progress.is_mastered(enemy_type) else ""))
		picker.set_item_metadata(picker.item_count - 1, enemy_type)
	body.add_child(picker)
	return picker

func refresh_stats() -> void:
	if status == null:
		return
	status.text = "LV %02d  /  RANK %s  /  %s" % [PlayerStats.level, PlayerStats.rank, "MAX" if PlayerStats.level == 50 else "%d / %d XP" % [PlayerStats.xp, PlayerStats.xp_cost()]]
	var values := {"HP": [PlayerStats.hp, PlayerStats.max_hp()], "MP": [PlayerStats.mp, PlayerStats.max_mp()], "FATIGUE": [PlayerStats.fatigue, 100.0]}
	for kind: String in values:
		resources[kind].max_value = values[kind][1]
		resources[kind].value = values[kind][0]
		bar_labels[kind].text = "%d/%d" % [ceili(values[kind][0]), int(values[kind][1])]
	if is_instance_valid(points_label):
		points_label.text = "%d AVAILABLE POINTS  /  potions: %d HP, %d MP, %d tonic" % [PlayerStats.points, PlayerStats.potions.health, PlayerStats.potions.mana, PlayerStats.potions.tonic]
	for stat: String in stat_labels:
		stat_labels[stat].text = "%s   %d" % [stat, PlayerStats.stats[stat]]
		stat_buttons[stat].disabled = PlayerStats.points <= 0
	low_hp.visible = PlayerStats.hp < PlayerStats.max_hp() * 0.3

func notify(message: String) -> void:
	toast_label.text = message
	toast_left = 5.0

func update_view(delta: float) -> void:
	toast_left = maxf(0.0, toast_left - delta)
	toast_label.visible = toast_left > 0.0
	debug_indicator.text = ("TEST STATE MODIFIED  /  " if game.test_modified else "") + ("SIMULATED XR" if game.simulated_xr else ("OPENXR" if game.xr_enabled else "KEYBOARD + MOUSE"))
	context.text = {"hub": "PERSONAL CHAMBER", "training": "PRACTICE CHAMBER", "penalty": "PENALTY ZONE", "warren": "GOBLIN WARREN  /  RANK E"}.get(game.room, "SYSTEM")
	objective.text = "LOW HP!  /  " if low_hp.visible else ""
	objective.text += "SPRINT / DASH LOCKED" if PlayerStats.exhausted else "%d STAT POINTS AVAILABLE" % PlayerStats.points
	controls.text = "WASD Move   Shift Sprint   LMB Attack   RMB Parry/Block   Space Dash\nTab Status   1/2/3 Potions   Esc Pause   F1 Test Controls"
	if game.workout.active:
		var key: String = "SPACE / SQUAT" if game.workout.action() == "squat" else "J or K / PUNCH"
		var until: float = maxf(0.0, game.workout.next_beat - game.workout.elapsed)
		prompt.text = "%s   %d / 30\n%s" % [key, game.workout.reps, "NOW" if until <= 0.15 else "Beat in %.1f" % until]
		if game.xr_enabled:
			prompt.text = "%s  %d / 30\n%s" % [game.workout.action().to_upper(), game.workout.reps, "Lower then stand fully" if game.workout.action() == "squat" else "Strike the glowing pads"]
	elif game.room == "training":
		prompt.text = "[%s]\n%d / 10  /  %s" % [game.last_grade, game.practice.grades.size(), game.practice.last_report]
	elif game.room == "penalty":
		prompt.text = "SURVIVE  %02d:%02d\n%d / 4 CENTIPEDES" % [int(180 - game.penalty.elapsed) / 60, int(180 - game.penalty.elapsed) % 60, game.penalty.alive]
	elif game.room == "warren":
		var left: int = game.encounter.queue.size() + game.encounter.active
		prompt.text = ("%s\n%d ENEMIES LEFT" % [game.encounter.title(), left]) if game.encounter.running else "GATE CLEARED\nWALK INTO THE EXIT PORTAL"
	else:
		prompt.text = "E / BEGIN WORKOUT" if Progress.workout_state == "available" else "PORTALS OPEN  /  WALK INTO THE PORTAL"
