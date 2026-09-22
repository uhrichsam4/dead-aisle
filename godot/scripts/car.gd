## The black Sonata: arcade driving, the in-cabin camera, wheel spin and the
## parking check. Forward is -Z, as in the web build (the model itself sits
## rotated 180 degrees inside this body - CAR_FIT.ry).
extends CharacterBody3D

const U := preload("res://scripts/util.gd")

signal parked
signal radio_changed(text: String)

## The radio is a real object in the car, not a track over the mix: once you
## park and walk away it is still playing back there, quieter the further you
## go. Rename freely - the name is what shows on the dial.
const STATIONS := [
	{"name": "STATIC FM",  "file": "radio-song.mp3"},
	{"name": "NIGHTSHIFT", "file": "radio-nightshift.mp3"},
	{"name": "LOWRIDER",   "file": "radio-lowrider.mp3"},
	{"name": "MAGIC VIP",  "file": "radio-magic.mp3"},
	{"name": "PARKSIDE",   "file": "park-song.mp3"},
]

const CAR_CAM := Vector3(-0.37, 1.15, -0.62)
const PARK_ACT1 := AABB(Vector3(6, 0, 17.5), Vector3(4, 3, 3))       # the TOPS bay
const PARK_ACT2 := AABB(Vector3(-890, 0, 33.5), Vector3(5, 3, 3))     # the kerb by the mosque gate
var park_box := PARK_ACT1
const MAX_FWD := 24.0
const MAX_REV := -7.0

var speed := 0.0
var steer := 0.0
var driving := false
var is_parked := false
var model: Node3D
var camera: Camera3D
var wheels := {}
var cam_yaw := 0.0
var look_yaw := 0.0
var look_pitch := 0.0
var engine: AudioStreamPlayer3D
var radio: AudioStreamPlayer3D
var station := 0
var radio_on := false
var _hb_down := false

func _ready() -> void:
	collision_layer = 8
	collision_mask = 1
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(1.9, 1.3, 4.7)
	cs.shape = sh
	cs.position.y = 0.75
	add_child(cs)
	var ps: PackedScene = load("res://assets/car2.glb")
	model = ps.instantiate() as Node3D
	model.rotation.y = PI
	add_child(model)
	U.fix_materials(model, false)       # black is the point - no lift
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		for i in (mi as MeshInstance3D).mesh.get_surface_count():
			var mat := (mi as MeshInstance3D).mesh.surface_get_material(i)
			if mat is StandardMaterial3D:
				var sm := mat as StandardMaterial3D
				var n := sm.resource_name.to_lower()
				if n.contains("glass"):
					# the driver sits inside: the glazing has to be see-through
					sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					sm.albedo_color = Color(0.16, 0.2, 0.22, 0.18)
					sm.cull_mode = BaseMaterial3D.CULL_DISABLED
				elif n.begins_with("interior") or n.contains("bej"):
					sm.albedo_color = Color(0.3, 0.29, 0.28) if sm.albedo_texture else Color(0.1, 0.098, 0.095)
	for w in ["wheel_FL", "wheel_FR", "wheel_BL", "wheel_BR"]:
		var n := model.find_child(w, true, false)
		if n:
			wheels[w] = n
	camera = Camera3D.new()
	camera.position = CAR_CAM
	camera.fov = 88.0
	camera.near = 0.05
	camera.far = 900.0
	camera.cull_mask = 0xFFFFF & ~2
	add_child(camera)
	# a warm instrument-cluster glow; nothing else reaches the dash at night
	var dash := OmniLight3D.new()
	dash.position = Vector3(-0.37, 0.8, -1.2)
	dash.light_color = Color(1, 0.7, 0.48)
	dash.light_energy = 0.6
	dash.omni_range = 1.6
	add_child(dash)
	engine = AudioStreamPlayer3D.new()
	var rev: Array = Game.variants("car_rev")
	if not rev.is_empty():
		var st: AudioStream = rev[0]
		if st is AudioStreamMP3:
			(st as AudioStreamMP3).loop = true
		engine.stream = st
	engine.volume_db = -14.0
	engine.unit_size = 6.0
	add_child(engine)
	radio = AudioStreamPlayer3D.new()
	radio.position = Vector3(0, 1.0, -0.9)      # the dash
	radio.unit_size = 4.0
	radio.max_distance = 140.0
	radio.volume_db = -6.0
	radio.bus = &"Music"          # the MUSIC slider, not SFX
	add_child(radio)

# ------------------------------------------------------------------ radio

func radio_toggle() -> void:
	radio_on = not radio_on
	if radio_on:
		_tune(station)
	else:
		radio.stop()
		radio_changed.emit("RADIO OFF")
	Game.play("gear_gopro_beep", -14.0, 0.7)       # the click of the knob

func radio_select(i: int) -> void:
	if i < 0 or i >= STATIONS.size():
		return
	radio_on = true
	_tune(i)

func radio_next() -> void:
	radio_select((station + 1) % STATIONS.size())

func _tune(i: int) -> void:
	station = i
	var st := Game.file(STATIONS[i].file)
	if st is AudioStreamMP3:
		(st as AudioStreamMP3).loop = true
	radio.stream = st
	# drop in partway through, like tuning into something already playing
	var len := st.get_length() if st else 0.0
	radio.play(randf_range(0.0, len * 0.6) if len > 10.0 else 0.0)
	radio_changed.emit("♪  " + STATIONS[i].name)

func take_wheel(on: bool) -> void:
	driving = on
	if on:
		camera.current = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		look_yaw = 0.0
		look_pitch = 0.0

func _unhandled_input(e: InputEvent) -> void:
	if driving and not is_parked:
		if e.is_action_pressed("radio"):
			radio_toggle()
			return
		for k in 5:
			if e is InputEventKey and (e as InputEventKey).pressed and not (e as InputEventKey).echo and (e as InputEventKey).physical_keycode == KEY_1 + k:
				radio_select(k)
				return
		if e.is_action_pressed("next_weapon"):
			radio_next()
			return
	if driving and e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		look_yaw = clampf(look_yaw - (e as InputEventMouseMotion).relative.x * 0.002, -1.3, 1.3)
		look_pitch = clampf(look_pitch - (e as InputEventMouseMotion).relative.y * 0.002, -0.5, 0.4)

func _physics_process(dt: float) -> void:
	var thr := 0.0
	var brk := 0.0
	var st := 0.0
	if driving and not is_parked:
		thr = Input.get_action_strength("move_forward")
		brk = Input.get_action_strength("move_back")
		st = Input.get_action_strength("move_left") - Input.get_action_strength("move_right")
	if thr > 0.0:
		speed += (18.0 if speed < 0.0 else 9.5) * thr * dt
	if brk > 0.0:
		speed -= (20.0 if speed > 0.4 else 8.0) * brk * dt
	if thr == 0.0 and brk == 0.0:
		speed = move_toward(speed, 0.0, 4.0 * dt)
	var hb := Input.is_action_pressed("handbrake") and driving and not is_parked
	if hb:
		speed = move_toward(speed, 0.0, 16.0 * dt)
		if not _hb_down and absf(speed) > 3.0:
			Game.play("car_handbrake", -6.0)
	_hb_down = hb
	speed = clampf(speed, MAX_REV, MAX_FWD)
	steer = lerpf(steer, st, clampf(dt * 5.0, 0.0, 1.0))
	# steering scales with speed and flips in reverse, like a real car
	var turn := steer * clampf(absf(speed) / 6.0, 0.0, 1.0) * 1.35 * signf(speed if absf(speed) > 0.01 else 1.0)
	rotation.y += turn * dt * clampf(1.0 - absf(speed) / 60.0, 0.4, 1.0)

	_park_assist(dt)
	var fwd := -global_basis.z
	velocity = fwd * speed + Vector3(0, -9.0, 0)
	move_and_slide()
	# a wall stops you, it does not slide you along it at full speed
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		if absf(c.get_normal().y) < 0.5 and absf(speed) > 3.0:
			speed *= -0.25
			Game.play_at("hit_metal", global_position, -2.0)
			break
	for w in wheels:
		(wheels[w] as Node3D).rotate_object_local(Vector3.RIGHT, -speed * dt / 0.34)

	if not is_parked and absf(speed) < 0.45 and park_box.has_point(Vector3(global_position.x, 1, global_position.z)):
		is_parked = true
		speed = 0.0
		parked.emit()

	if engine.stream:
		if driving and not engine.playing:
			engine.play()
		engine.pitch_scale = 0.7 + absf(speed) / MAX_FWD * 1.1
		engine.volume_db = lerpf(-16.0, -8.0, clampf(thr + absf(speed) / MAX_FWD, 0.0, 1.0))
		if not driving and engine.playing:
			engine.stop()

## Hitting a 4 x 3 m box at a dead stop by hand is a coin flip, so once you
## are close and slow the car eases into the bay and squares up. You keep
## control - this only biases.
func _park_assist(dt: float) -> void:
	if is_parked or not driving:
		return
	var c := park_box.get_center()
	var d := Vector2(global_position.x - c.x, global_position.z - c.z).length()
	if d < 8.0 and speed > -0.5 and speed < 6.5:
		var k := clampf(1.0 - d / 8.0, 0.0, 1.0)
		speed = lerpf(speed, minf(speed, 2.4 * (d / 8.0)), clampf(dt * 2.4 * k, 0.0, 1.0))
		global_position.x = lerpf(global_position.x, c.x, clampf(dt * 2.0 * k, 0.0, 1.0))
		global_position.z = lerpf(global_position.z, c.z, clampf(dt * 2.0 * k, 0.0, 1.0))
		var target := PI / 2
		var dy := wrapf(target - rotation.y, -PI, PI)
		rotation.y += dy * clampf(dt * 2.6 * k, 0.0, 1.0)

func _process(dt: float) -> void:
	if not driving:
		return
	var spn := clampf(absf(speed) / 16.0, 0.0, 1.0)
	cam_yaw = lerpf(cam_yaw, steer * 0.12, clampf(dt * 6.0, 0.0, 1.0))
	camera.rotation = Vector3(-0.015 + look_pitch, cam_yaw + look_yaw, -steer * 0.05 * spn)
	camera.fov = lerpf(camera.fov, 88.0 + spn * 8.0, clampf(dt * 6.0, 0.0, 1.0))
