## Global state, input map and the SFX pool. Autoloaded as `Game`.
extends Node

signal phase_changed(phase: String)
signal banner(title: String, sub: String)
signal objective(id: String, state: String)
signal settings_changed
signal points_changed(total: int, label: String, head: bool)

## drive -> parking -> outside -> inside -> win | dead
var phase := "menu"
var act := 1
var points := 500            # the web starts every run on 500
var kills := 0
var wave := 1
var run_time := 0.0
var god := false          # testing: nothing can hurt you
var quick_deploy := false # REDEPLOY skips the lobby on the reload
var round := 1            # mission.round: clearing a run escalates the next
# the end card's numbers
var shots := 0
var hits := 0
var headshots := 0
var saved := 0

## everything a run accumulates, back to a fresh deploy
func reset_run() -> void:
	phase = "menu"
	act = 1
	points = 500
	kills = 0
	wave = 1
	run_time = 0.0
	shots = 0
	hits = 0
	headshots = 0
	saved = 0

## the web build's settings screen, saved to user:// instead of the browser
const SETTINGS_PATH := "user://settings.cfg"
## SET_DEFAULTS from the web build
const DEFAULTS := {"master": 80, "music": 45, "sfx": 85, "sens": 100, "invert": false,
	"fov": 88, "res": 100, "shadows": true, "fx": true, "name": "", "skin": "operator"}
const SETTINGS_VERSION := 2
var settings := DEFAULTS.duplicate()

func load_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	var fresh: bool = int(cfg.get_value("meta", "version", 0)) < SETTINGS_VERSION
	for k in DEFAULTS:
		settings[k] = DEFAULTS[k] if fresh and k not in ["name", "skin"] else cfg.get_value("settings", k, DEFAULTS[k])
	apply_settings()

func save_settings() -> void:
	var cfg := ConfigFile.new()
	for k in settings:
		cfg.set_value("settings", k, settings[k])
	cfg.set_value("meta", "version", SETTINGS_VERSION)
	cfg.save(SETTINGS_PATH)

func reset_settings() -> void:
	var keep := {"name": settings.get("name", ""), "skin": settings.get("skin", "operator")}
	settings = DEFAULTS.duplicate()
	settings.merge(keep, true)
	apply_settings()
	save_settings()

func apply_settings() -> void:
	for pair in [["Master", "master"], ["Music", "music"], ["SFX", "sfx"]]:
		var i := AudioServer.get_bus_index(pair[0])
		var v: float = float(settings[pair[1]]) / 100.0
		AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.0001)))
		AudioServer.set_bus_mute(i, v <= 0.0)
	get_viewport().scaling_3d_scale = clampf(float(settings.res) / 100.0, 0.5, 2.0)
	settings_changed.emit()

## Music (the radio) and SFX (everything else) get their own sliders. Every
## player lands on SFX unless it asked for another bus, so nothing added
## later can slip past the slider.
func _setup_buses() -> void:
	for b in ["Music", "SFX"]:
		if AudioServer.get_bus_index(b) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, "Master")

func _on_node_added(n: Node) -> void:
	if n is AudioStreamPlayer and (n as AudioStreamPlayer).bus == &"Master":
		(n as AudioStreamPlayer).bus = &"SFX"
	elif n is AudioStreamPlayer3D and (n as AudioStreamPlayer3D).bus == &"Master":
		(n as AudioStreamPlayer3D).bus = &"SFX"

const SFX_DIR := "res://assets/sfx/"
var _variants := {}
var _last_pick := {}
var _pool: Array[AudioStreamPlayer] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	_setup_buses()
	get_tree().node_added.connect(_on_node_added)
	for i in 14:
		var p := AudioStreamPlayer.new()
		p.bus = &"SFX"
		add_child(p)
		_pool.append(p)
	load_settings.call_deferred()      # the viewport has to exist first
	# CSS pixels are logical pixels: on a Retina screen the browser draws the
	# web HUD at 2x. Scale the 2D layers the same way (3D is unaffected).
	_ui_scale.call_deferred()

## The web's heartbeat was synthesised (there is no file for it): a lub-dub
## of two low decaying thumps, built once as PCM.
var _heart: AudioStreamWAV
func heartbeat() -> AudioStreamWAV:
	if _heart:
		return _heart
	var rate := 22050
	var n := int(rate * 0.62)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var tt := float(i) / rate
		var v := 0.0
		for beat in [[0.0, 1.0], [0.24, 0.7]]:
			var b: float = tt - float(beat[0])
			if b >= 0.0:
				v += sin(TAU * 52.0 * b) * exp(-b * 22.0) * float(beat[1])
		data.encode_s16(i * 2, int(clampf(v * 0.9, -1.0, 1.0) * 32767.0))
	_heart = AudioStreamWAV.new()
	_heart.format = AudioStreamWAV.FORMAT_16_BITS
	_heart.mix_rate = rate
	_heart.stereo = false
	_heart.data = data
	return _heart

## the web's addPoints: the counter, and a pop-up when there is a label
func add_points(n: int, label := "", head := false) -> void:
	points += n
	points_changed.emit(points, label, head)

func _ui_scale() -> void:
	var sc := DisplayServer.screen_get_scale(DisplayServer.window_get_current_screen())
	get_window().content_scale_factor = maxf(1.0, sc)

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
		"throw": [KEY_F], "music": [KEY_N],
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

## one-off files in assets/ (the hostile voices, stingers, the radio)
var _files := {}
func file(name: String) -> AudioStream:
	if _files.has(name):
		return _files[name]
	var path := "res://assets/" + name
	var s: AudioStream = load(path) if ResourceLoader.exists(path) else null
	_files[name] = s
	return s

func play_file(name: String, vol_db := 0.0, pitch := 1.0) -> void:
	var s := file(name)
	if s == null:
		return
	var p: AudioStreamPlayer = _pool[0]
	for q in _pool:
		if not q.playing:
			p = q
			break
	p.stream = s
	p.volume_db = vol_db
	p.pitch_scale = pitch
	p.play()

func play_file_at(name: String, pos: Vector3, vol_db := 0.0, pitch := 1.0, range_m := 30.0) -> void:
	var s := file(name)
	if s == null or get_tree().current_scene == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.volume_db = vol_db
	p.pitch_scale = pitch
	p.unit_size = 5.0
	p.max_distance = range_m
	get_tree().current_scene.add_child(p)
	p.global_position = pos
	p.play()
	p.finished.connect(p.queue_free)

## Hostile voices are gated globally, as the web build did: never a chorus,
## and the reactions have their own gate so a volley does not stack eight.
var _last_shout := -10.0
var _last_react := -10.0
func may_shout(gap := 0.55) -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_shout < gap:
		return false
	_last_shout = now
	return true
func may_react(gap := 0.7) -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_react < gap:
		return false
	_last_react = now
	return true

## VO lines are rationed so the operator does not narrate everything
var _vo_last := {}
func vo(line: String, cooldown := 8.0, chance := 1.0, vol_db := -2.0) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _vo_last.get(line, -999.0) < cooldown or randf() > chance:
		return
	_vo_last[line] = now
	play("vo_" + line, vol_db)

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
