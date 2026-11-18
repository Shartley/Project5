extends RefCounted

static func install() -> void:
	var keys := {"move_forward": KEY_W, "move_back": KEY_S, "move_left": KEY_A, "move_right": KEY_D, "sprint": KEY_SHIFT, "dash": KEY_SPACE, "interact": KEY_E, "stats": KEY_TAB, "pause_game": KEY_ESCAPE, "test_panel": KEY_F1, "squat": KEY_SPACE, "punch_left": KEY_J, "punch_right": KEY_K, "health_potion": KEY_1, "mana_potion": KEY_2, "tonic_potion": KEY_3}
	for action: String in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var event := InputEventKey.new()
			event.physical_keycode = keys[action]
			InputMap.action_add_event(action, event)
	for action: String in {"attack": MOUSE_BUTTON_LEFT, "block": MOUSE_BUTTON_RIGHT}:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var event := InputEventMouseButton.new()
			event.button_index = MOUSE_BUTTON_LEFT if action == "attack" else MOUSE_BUTTON_RIGHT
			InputMap.action_add_event(action, event)
