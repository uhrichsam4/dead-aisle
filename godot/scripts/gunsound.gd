## Layered gunfire, the way a helmet camera hears it: a hard close crack
## with the bolt clacking under it, then the space answering - long slapbacks
## and a rolling decay off the buildings outdoors, a dense boxy smear inside.
## Layers are baked by assets/sfx/processed/make_gunsounds.py.
##
## Everything is pooled on one node parked under the Game autoload, so it
## survives reload_current_scene and no shot creates a node. Each layer is a
## single player with polyphony over an AudioStreamRandomizer (no repeats,
## random pitch), so overlapping shots never cut each other off.
##
##   GunSound.fire(camera_pos, Game.phase == "inside")   # the player's shot
##   GunSound.fire_distant(pos)                            # far gunfire, 3D
class_name GunSound
extends Node

const DIR := "res://assets/sfx/processed/"
const CLOSE_DB := -1.0
const TAIL_OUT_DB := -8.0
const TAIL_IN_DB := -7.0
const RING_DB := -32.0
const DISTANT_DB := 2.0
const SPEED_OF_SOUND := 343.0
const FAR_VOICES := 6

## heat: +HEAT_SHOT per shot, bleeds off at HEAT_COOL per second. Full auto
## (~10 rounds/s) crosses DUCK_FROM after about a second of fire.
const HEAT_SHOT := 0.16
const HEAT_COOL := 0.55
const HEAT_MAX := 3.0
const DUCK_FROM := 0.9
const DUCK_SPAN := 1.6

static var _inst: GunSound

var _close: AudioStreamPlayer
var _tail_out: AudioStreamPlayer
var _tail_in: AudioStreamPlayer
var _ring: AudioStreamPlayer
var _far: Array[AudioStreamPlayer3D] = []
var _far_next := 0
var _heat := 0.0
var _duck := 0.0
var _ring_cd := 0.0
var _game: Node   # the Game autoload, looked up rather than named so this
                  # script compiles before autoloads exist (tools, --script)
# distant shots wait for their sound to arrive: [due time, position] pairs
var _pend_t := PackedFloat64Array()
var _pend_p := PackedVector3Array()
var _pend_v := PackedFloat32Array()

## Builds the pool (idempotent). Game calls it once at startup.
static func warm() -> void:
	_host()

## The player's own shot. `at` is the camera; `indoors` picks the tail.
static func fire(at: Vector3, indoors: bool) -> void:
	var g := _host()
	if g == null:
		return
	g._shoot(at, indoors)

## Gunfire somewhere else in the world: a muffled boom and its echo, placed
## in 3D and delayed by the distance to the listener (sound is slow).
static func fire_distant(at: Vector3, vol_db := 0.0) -> void:
	var g := _host()
	if g == null:
		return
	var delay := 0.0
	var cam := g.get_viewport().get_camera_3d()
	if cam:
		delay = cam.global_position.distance_to(at) / SPEED_OF_SOUND
	g._pend_t.append(Time.get_ticks_msec() / 1000.0 + delay)
	g._pend_p.append(at)
	g._pend_v.append(vol_db)
	g.set_process(true)

static func _host() -> GunSound:
	if is_instance_valid(_inst):
		return _inst
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	var host: Node = tree.root.get_node_or_null("Game")
	_inst = GunSound.new()
	_inst.name = "GunSound"
	(host if host else tree.root).add_child(_inst)
	return _inst

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_game = get_node_or_null(^"/root/Game")
	_close = _layer("shot_close", 6, "Guns", 6, 1.035, 1.0)
	_tail_out = _layer("tail_out", 4, "Guns", 12, 1.05, 1.5)
	_tail_in = _layer("tail_in", 4, "Guns", 8, 1.05, 1.5)
	_ring = AudioStreamPlayer.new()
	_ring.stream = _load("ring")
	_ring.bus = &"Guns"
	_ring.volume_db = RING_DB
	add_child(_ring)
	var far := _randomizer("shot_distant", 3, 1.06, 2.0)
	for i in FAR_VOICES:
		var p := AudioStreamPlayer3D.new()
		p.stream = far
		p.bus = &"SFX"
		p.max_polyphony = 2
		p.unit_size = 22.0
		p.max_distance = 450.0
		p.attenuation_filter_cutoff_hz = 3500.0
		p.attenuation_filter_db = -18.0
		p.top_level = true
		add_child(p)
		_far.append(p)
	set_process(false)

func _load(n: String) -> AudioStream:
	var path := DIR + n + ".wav"
	return load(path) if ResourceLoader.exists(path) else null

func _randomizer(fam: String, count: int, pitch: float, vol_rand: float) -> AudioStreamRandomizer:
	var r := AudioStreamRandomizer.new()
	r.playback_mode = AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS
	r.random_pitch = pitch
	r.random_volume_offset_db = vol_rand
	for i in count:
		var s := _load(fam + "_" + str(i + 1))
		if s:
			r.add_stream(-1, s)
	return r

func _layer(fam: String, count: int, bus: StringName, voices: int, pitch: float, vol_rand: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = _randomizer(fam, count, pitch, vol_rand)
	p.bus = bus
	p.max_polyphony = voices
	add_child(p)
	return p

func _shoot(_at: Vector3, indoors: bool) -> void:
	_heat = minf(_heat + HEAT_SHOT, HEAT_MAX)
	# a long burst packs the tails into a wash; lean on them a little as the
	# heat builds so the cracks stay on top (acts on the tails in flight too)
	var wash := clampf(_heat / HEAT_MAX, 0.0, 1.0) * 4.0
	_close.volume_db = CLOSE_DB
	_close.play()
	if indoors:
		_tail_in.volume_db = TAIL_IN_DB - wash
		_tail_in.play()
	else:
		_tail_out.volume_db = TAIL_OUT_DB - wash
		_tail_out.play()
	set_process(true)

func _process(delta: float) -> void:
	# distant shots whose sound has arrived
	if not _pend_t.is_empty():
		var now := Time.get_ticks_msec() / 1000.0
		var i := 0
		while i < _pend_t.size():
			if _pend_t[i] <= now:
				var p := _far[_far_next]
				_far_next = (_far_next + 1) % _far.size()
				p.global_position = _pend_p[i]
				p.volume_db = DISTANT_DB + _pend_v[i]
				p.play()
				_pend_t.remove_at(i)
				_pend_p.remove_at(i)
				_pend_v.remove_at(i)
			else:
				i += 1
	# the ears: heat -> a short, subtle low-pass and dip on the rest of the mix
	_heat = maxf(_heat - HEAT_COOL * delta, 0.0)
	_ring_cd = maxf(_ring_cd - delta, 0.0)
	var target := clampf((_heat - DUCK_FROM) / DUCK_SPAN, 0.0, 1.0)
	# clamp down fast, come back slowly
	var rate := 6.0 if target > _duck else 1.2
	_duck = move_toward(_duck, target, rate * delta)
	if _game and _game.has_method(&"set_ear_duck"):
		_game.call(&"set_ear_duck", _duck)
	if _duck > 0.55 and _ring_cd <= 0.0 and _ring.stream:
		_ring.play()
		_ring_cd = 7.0
	if _heat <= 0.0 and _duck <= 0.0 and _pend_t.is_empty():
		set_process(false)
