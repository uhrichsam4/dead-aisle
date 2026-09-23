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

func load_settings(apply := true) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	var fresh: bool = int(cfg.get_value("meta", "version", 0)) < SETTINGS_VERSION
	for k in DEFAULTS:
		settings[k] = DEFAULTS[k] if fresh and k not in ["name", "skin"] else cfg.get_value("settings", k, DEFAULTS[k])
	if apply:
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
	# the web renders at one pixel per CSS pixel (DPR_CAP 1) times RENDER
	# QUALITY - half resolution per axis on a Retina screen
	# FSR2 (temporal AA with the upscale) below native; it cannot go above 1
	get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2 if render_scale() <= 1.0 else Viewport.SCALING_3D_MODE_BILINEAR
	get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED if render_scale() <= 1.0 else Viewport.SCREEN_SPACE_AA_FXAA
	get_viewport().scaling_3d_scale = render_scale()
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
	# the ear: a low-pass and a dip on SFX that GunSound leans on after
	# sustained fire. Both stay bypassed until they are needed.
	var sfx := AudioServer.get_bus_index("SFX")
	if AudioServer.get_bus_effect_count(sfx) == 0:
		var lpf := AudioEffectLowPassFilter.new()
		lpf.cutoff_hz = 20000.0
		AudioServer.add_bus_effect(sfx, lpf, EAR_LPF)
		AudioServer.add_bus_effect(sfx, AudioEffectAmplify.new(), EAR_AMP)
		AudioServer.set_bus_effect_enabled(sfx, EAR_LPF, false)
		AudioServer.set_bus_effect_enabled(sfx, EAR_AMP, false)
	# the player's own gunfire rides its own bus, so the ear duck on SFX does
	# not swallow the shots that caused it; it follows the SFX slider
	if AudioServer.get_bus_index("Guns") == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, "Guns")
		AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	if not settings_changed.is_connected(_sync_gun_bus):
		settings_changed.connect(_sync_gun_bus)

const EAR_LPF := 0
const EAR_AMP := 1
var _ear := 0.0

## Keeps the Guns bus on the SFX slider (volume and mute).
func _sync_gun_bus() -> void:
	var s := AudioServer.get_bus_index("SFX")
	var g := AudioServer.get_bus_index("Guns")
	if s == -1 or g == -1:
		return
	AudioServer.set_bus_volume_db(g, AudioServer.get_bus_volume_db(s))
	AudioServer.set_bus_mute(g, AudioServer.is_bus_mute(s))

## 0 = clear hearing, 1 = the ears are shut down after a long burst: SFX
## loses its top end and dips a few dB. Subtle by design.
func set_ear_duck(k: float) -> void:
	k = clampf(k, 0.0, 1.0)
	if is_equal_approx(k, _ear):
		return
	_ear = k
	var sfx := AudioServer.get_bus_index("SFX")
	if AudioServer.get_bus_effect_count(sfx) < 2:
		return
	var on := k > 0.001
	AudioServer.set_bus_effect_enabled(sfx, EAR_LPF, on)
	AudioServer.set_bus_effect_enabled(sfx, EAR_AMP, on)
	if on:
		var lpf := AudioServer.get_bus_effect(sfx, EAR_LPF) as AudioEffectLowPassFilter
		lpf.cutoff_hz = lerpf(20000.0, 3800.0, pow(k, 0.6))
		var amp := AudioServer.get_bus_effect(sfx, EAR_AMP) as AudioEffectAmplify
		amp.volume_db = -4.0 * k

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
	GunSound.warm.call_deferred()      # gunfire layers loaded before the first shot
	# read now, so the lobby is built in the saved outfit; apply once the
	# viewport exists
	load_settings(false)
	apply_settings.call_deferred()
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

func render_scale() -> float:
	var dpr := DisplayServer.screen_get_scale(DisplayServer.window_get_current_screen())
	return clampf(float(settings.res) / 100.0 / maxf(1.0, dpr), 0.25, 2.0)

func _ui_scale() -> void:
	# size the 2D layers to the window, so the HUD reads the same fullscreen
	# as windowed: 780 logical px of height, whatever the screen
	var h := float(get_window().size.y)
	get_window().content_scale_factor = maxf(1.0, h / 780.0)
	if not get_window().size_changed.is_connected(_ui_scale):
		get_window().size_changed.connect(_ui_scale)

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
