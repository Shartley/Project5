extends Node
## Browser Escape releases pointer lock before Godot can always see the key.
signal pause_requested
var document: JavaScriptObject
var lock_callback: JavaScriptObject
var visibility_callback: JavaScriptObject

func _ready() -> void:
	if not OS.has_feature("web"):
		return
	document = JavaScriptBridge.get_interface("document")
	lock_callback = JavaScriptBridge.create_callback(_pointer_lock_changed)
	visibility_callback = JavaScriptBridge.create_callback(_visibility_changed)
	document.addEventListener("pointerlockchange", lock_callback)
	document.addEventListener("visibilitychange", visibility_callback)

func _pointer_lock_changed(_args: Array) -> void:
	if document.pointerLockElement == null:
		pause_requested.emit()

func _visibility_changed(_args: Array) -> void:
	if document.hidden:
		pause_requested.emit()

func _exit_tree() -> void:
	if document != null:
		document.removeEventListener("pointerlockchange", lock_callback)
		document.removeEventListener("visibilitychange", visibility_callback)
