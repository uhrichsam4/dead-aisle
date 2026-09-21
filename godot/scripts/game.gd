## Global state, input map and the SFX pool. Autoloaded as `Game`.
extends Node

signal phase_changed(phase: String)
signal banner(title: String, sub: String)
signal objective(id: String, state: String)

## drive -> parking -> outside -> inside -> win | dead
var phase := "menu"
var act := 1
var points := 0
var kills := 0
var wave := 1
var run_time := 0.0

const SFX_DIR := "res://assets/sfx/"
var _variants := {}
var _last_pick := {}
var _pool: Array[AudioStreamPlayer] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	for i in 14:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)

func set_phase(p: String) -> void:
	phase = p
	phase_changed.emit(p)

func say_banner(title: String, sub := "") -> void:
	banner.emit(title, sub)

func set_objective(id: String, state: String) -> void:
	objective.emit(id, state)

# ---------------------------------------------------------------- input

func _setup_input() -> void:
	var keys := {
		"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"sprint": [KEY_SHIFT], "jump": [KEY_SPACE], "crouch": [KEY_C, KEY_CTRL],
		"reload": [KEY_R], "interact": [KEY_E], "radio": [KEY_E],
		"weapon_1": [KEY_1], "weapon_2": [KEY_2], "weapon_3": [KEY_3], "next_weapon": [KEY_Q],
		"skip": [KEY_ENTER, KEY_SPACE], "pause": [KEY_ESCAPE], "handbrake": [KEY_SPACE],
	}
	for a in keys:
		if not InputMap.has_action(a):
			InputMap.add_action(a)
		for k in keys[a]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(a, ev)
	for pair in [["fire", MOUSE_BUTTON_LEFT], ["aim", MOUSE_BUTTON_RIGHT]]:
		if not InputMap.has_action(pair[0]):
			InputMap.add_action(pair[0])
		var mb := InputEventMouseButton.new()
		mb.button_index = pair[1]
		InputMap.action_add_event(pair[0], mb)

# ---------------------------------------------------------------- audio

## gun_shot -> gun_shot_1 .. gun_shot_N. A single file with no number
## (vo_trunk.mp3) is a family of one.
func variants(fam: String) -> Array:
	if _variants.has(fam):
		return _variants[fam]
	var out := []
	for i in range(1, 10):
		var path := SFX_DIR + fam + "_" + str(i) + ".mp3"
		if ResourceLoader.exists(path):
			out.append(load(path))
	if out.is_empty() and ResourceLoader.exists(SFX_DIR + fam + ".mp3"):
		out.append(load(SFX_DIR + fam + ".mp3"))
	_variants[fam] = out
	return out

func _pick(fam: String) -> AudioStream:
	var v := variants(fam)
	if v.is_empty():
		return null
	var i := randi() % v.size()
	if v.size() > 1 and _last_pick.get(fam, -1) == i:
		i = (i + 1) % v.size()   # never the same take twice in a row
	_last_pick[fam] = i
	return v[i]

func play(fam: String, vol_db := 0.0, pitch := 1.0) -> void:
	var s := _pick(fam)
	if s == null:
		return
	var p: AudioStreamPlayer = _pool[0]
	for q in _pool:
		if not q.playing:
			p = q
			break
	p.stream = s
	p.volume_db = vol_db
	p.pitch_scale = pitch * randf_range(0.97, 1.03)
	p.play()

func play_at(fam: String, pos: Vector3, vol_db := 0.0, pitch := 1.0) -> void:
	var s := _pick(fam)
	if s == null or get_tree().current_scene == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.volume_db = vol_db
	p.pitch_scale = pitch * randf_range(0.96, 1.04)
	p.unit_size = 6.0
	p.max_distance = 90.0
	get_tree().current_scene.add_child(p)
	p.global_position = pos
	p.play()
	p.finished.connect(p.queue_free)
