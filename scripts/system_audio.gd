extends Node
## Short original synthesized cues, no external assets.
var sounds: Dictionary = {}

func _ready() -> void:
	for item in [["beat", 660.0, 0.08], ["good", 880.0, 0.12], ["parry", 1200.0, 0.18], ["hit", 120.0, 0.12], ["warning", 320.0, 0.2], ["reward", 1046.5, 0.4], ["heart", 55.0, 0.16]]:
		sounds[item[0]] = make_tone(item[1], item[2])

func make_tone(frequency: float, duration: float) -> AudioStreamWAV:
	var result := AudioStreamWAV.new()
	result.format = AudioStreamWAV.FORMAT_16_BITS
	result.mix_rate = 22050
	var count := int(22050 * duration)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in range(count):
		var time := float(i) / 22050.0
		var envelope := sin(PI * float(i) / count) * exp(-time * 5.0)
		data.encode_s16(i * 2, int(sin(TAU * frequency * time) * envelope * 10000))
	result.data = data
	return result

func play_cue(id: String, location: Vector3 = Vector3.INF) -> void:
	if not sounds.has(id) or DisplayServer.get_name() == "headless":
		return
	if location.is_finite():
		var player := AudioStreamPlayer3D.new()
		add_child(player)
		player.global_position = location
		player.stream = sounds[id]
		player.volume_db = -10
		player.finished.connect(player.queue_free)
		player.play()
	else:
		var player := AudioStreamPlayer.new()
		add_child(player)
		player.stream = sounds[id]
		player.volume_db = -14
		player.finished.connect(player.queue_free)
		player.play()
