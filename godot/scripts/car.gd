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
const MAX_FWD := 11.0     # the web's clamp(carSpeed, -6, 11)
const MAX_REV := -6.0

var speed := 0.0
var steer := 0.0
var driving := false
var is_parked := false
var model: Node3D
var camera: Camera3D
var wheels := {}
var cam_yaw := 0.0
var _cam_roll := 0.0
var _shake := 0.0
var _prev_spd := 0.0
var _accel_s := 0.0
var look_yaw := 0.0
var look_pitch := 0.0
var engine: AudioStreamPlayer3D
var radio: AudioStreamPlayer3D
var station := 0
var radio_on := false
var _hb_down := false

# visual suspension: the body rides on springs; only the model moves, the
# CharacterBody3D, its collider and the camera never do
const SUSP_K := 140.0         # ~1.9 Hz, a family saloon on soft springs
const SUSP_C := 14.0          # damping ratio ~0.6: one small overshoot, then still
const ROLL_PIVOT := Vector3(0, 0.45, 0)   # roll centre, not the tyre patch
var _model_rest := Basis()
var _pitch := 0.0
var _pitch_v := 0.0
var _roll := 0.0
var _roll_v := 0.0
var _heave := 0.0
var _heave_v := 0.0
var _dist := 0.0
var _phys_prev := 0.0
var _phys_acc := 0.0
var _lat_acc := 0.0
var _wheel_rest := {}         # wheel -> rest position in body space
# skid marks: one MultiMesh ring buffer, faded in the shader
const SKID_N := 320
const SKID_LIFE := 22.0
var _skid_mm: MultiMesh
var _skid_mat: ShaderMaterial
var _skid_i := 0
var _rear := [Vector3(-0.8, 0, 1.45), Vector3(0.8, 0, 1.45)]
var _skid_last: Array = [null, null]
var _skid := 0.0              # 0..1, how hard the tyres are sliding
var _smoke: Array = []
var _squeal: AudioStreamPlayer3D
var _brake_mat: StandardMaterial3D
var _t := 0.0

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
			_wheel_rest[n] = to_local((n as Node3D).global_position)
	_model_rest = model.basis
	var rl: Node3D = wheels.get("wheel_BL")
	var rr: Node3D = wheels.get("wheel_BR")
	if rl and rr:
		_rear = [_wheel_rest[rl] * Vector3(1, 0, 1), _wheel_rest[rr] * Vector3(1, 0, 1)]
	_brake_lamps()
	_build_skids()
	_build_smoke()
	_build_squeal()
	camera = Camera3D.new()
	camera.position = CAR_CAM
	camera.fov = 94.0
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
		Game.say_banner("RADIO ON", STATIONS[station].name)
	else:
		radio.stop()
		Game.say_banner("RADIO OFF", "")
	Game.play("gear_gopro_beep", -14.0, 0.7)       # the click of the knob

func radio_select(i: int) -> void:
	if i < 0 or i >= STATIONS.size():
		return
	radio_on = true
	_tune(i)
	Game.say_banner("RADIO", STATIONS[i].name)

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


func _physics_process(dt: float) -> void:
	var thr := 0.0
	var brk := 0.0
	var st := 0.0
	if driving and not is_parked:
		thr = Input.get_action_strength("move_forward")
		brk = Input.get_action_strength("move_back")
		st = Input.get_action_strength("move_left") - Input.get_action_strength("move_right")
	# the web's carDrive, number for number
	if thr > 0.0:
		speed += (18.0 if speed < 0.0 else 10.0) * dt
	if brk > 0.0:
		speed -= (20.0 if speed > 0.4 else 8.0) * dt
	speed -= speed * 0.32 * dt
	if thr == 0.0 and brk == 0.0:
		speed -= signf(speed) * minf(absf(speed), 2.4 * dt)
	var hb := Input.is_action_pressed("handbrake") and driving and not is_parked
	if hb:
		speed = move_toward(speed, 0.0, 16.0 * dt)
		if not _hb_down and absf(speed) > 3.0:
			Game.play("car_handbrake", -6.0)
	_hb_down = hb
	speed = clampf(speed, MAX_REV, MAX_FWD)
	# steering: the lock narrows with speed, a bicycle model on a 2.7 m base
	var eff_max := 0.5 / (1.0 + absf(speed) * 0.055)
	steer = lerpf(steer, st * eff_max, clampf(dt * (5.5 if st != 0.0 else 9.0), 0.0, 1.0))
	rotation.y += (speed / 2.7) * tan(steer) * dt

	_park_assist(dt)
	var fwd := -global_basis.z
	velocity = fwd * speed + Vector3(0, -9.0, 0)
	move_and_slide()
	# roadkill: anyone in the car's 2.7 x 5.9 m footprint above walking pace
	# goes over the bonnet, thrown along the heading harder the faster you were
	# going, and the car loses a little speed for it
	if absf(speed) > 2.6:
		for h in get_tree().get_nodes_in_group("hostiles"):
			if not (h.is_active() or h.state == "lotidle"):
				continue
			var lp := to_local((h as Node3D).global_position)
			if absf(lp.x) > 1.35 or absf(lp.z) > 2.95:
				continue
			var dir := -global_basis.z * signf(speed)
			h.rag_boost = clampf(absf(speed) / 3.4, 1.0, 3.6)
			if h.take_hit(9999.0, (h as Node3D).global_position + Vector3(0, 1.05, 0), dir):
				Game.add_points(55, "+55")
			speed *= 0.93
			_shake = 0.5
			Game.play_file("sfx-body-drop.mp3", -1.0, randf_range(0.9, 1.05))
	# the web's clamp: the road ends, the car does not drive off the world
	global_position.x = clampf(global_position.x, -1022.0, 162.0)
	global_position.z = clampf(global_position.z, 17.0, 39.0)
	# a wall stops you, it does not slide you along it at full speed
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		if absf(c.get_normal().y) < 0.5 and absf(speed) > 3.0:
			_impact(absf(speed), c.get_normal())
			speed *= -0.25
			Game.play_at("hit_metal", global_position, -2.0)
			break
	for w in wheels:
		(wheels[w] as Node3D).rotate_object_local(Vector3.RIGHT, -speed * dt / 0.34)

	# what the springs and the tyres feel: longitudinal and lateral g
	var acc := (speed - _phys_prev) / dt if dt > 0.0 else 0.0
	_phys_prev = speed
	_phys_acc = lerpf(_phys_acc, clampf(acc, -22.0, 12.0), clampf(dt * 10.0, 0.0, 1.0))
	_lat_acc = speed * (speed / 2.7) * tan(steer)
	_dist += absf(speed) * dt
	# the tyres let go: a hard stop, the handbrake, a corner past the grip, or
	# a standing start with the throttle pinned
	var sk := 0.0
	if brk > 0.0 and speed > 4.0:
		sk = clampf((speed - 4.0) / 5.0, 0.35, 1.0)
	if hb and absf(speed) > 2.0:
		sk = maxf(sk, clampf(absf(speed) / 7.0, 0.4, 1.0))
	if absf(_lat_acc) > 7.5:
		sk = maxf(sk, clampf((absf(_lat_acc) - 7.5) / 5.0, 0.3, 1.0))
	if thr > 0.8 and speed > 0.2 and speed < 2.6:
		sk = maxf(sk, 0.3)
	_skid = sk
	_skid_update()
	if _brake_mat:
		var lit := (brk > 0.0 and speed > 0.4) or hb
		_brake_mat.emission_energy_multiplier = lerpf(_brake_mat.emission_energy_multiplier,
			(5.0 if lit else 0.9) if driving else 0.0, clampf(dt * 18.0, 0.0, 1.0))

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
	_t += dt
	_suspension(dt)
	if not driving:
		return
	# the web's carCamera: bolted to the cabin, the view leads into the turn,
	# rolls a little with speed, pitches with acceleration, and widens
	var spn := clampf(absf(speed) / 16.0, 0.0, 1.0)
	cam_yaw = lerpf(cam_yaw, steer * 0.28, clampf(dt * 8.0, 0.0, 1.0))
	_cam_roll = lerpf(_cam_roll, -steer * 0.07 * spn, clampf(dt * 6.0, 0.0, 1.0))
	var acc := (speed - _prev_spd) / dt if dt > 0.0 else 0.0
	_prev_spd = speed
	_accel_s = lerpf(_accel_s, clampf(acc, -8.0, 8.0), clampf(dt * 4.0, 0.0, 1.0))
	camera.rotation = Vector3(clampf(-_accel_s * 0.0045, -0.04, 0.05) - 0.015, cam_yaw, _cam_roll)
	camera.fov = lerpf(camera.fov, 94.0 + spn * 8.0, clampf(dt * 9.0, 0.0, 1.0))
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - dt * 2.4)
		camera.rotation += Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * _shake * 0.03

# ------------------------------------------------------------------ chassis feel

## The body on its springs: squat under power, dive under brakes, lean out
## of a corner, and a faint patter from the road surface with speed. The
## wheels are pinned back where they were so they never sink into the road.
func _suspension(dt: float) -> void:
	if dt <= 0.0 or model == null:
		return
	dt = minf(dt, 0.05)
	var spn := clampf(absf(speed) / MAX_FWD, 0.0, 1.0)
	var tp := clampf(_phys_acc * 0.0032, -0.042, 0.028)
	var tr := clampf(-_lat_acc * 0.0028, -0.034, 0.034)
	_pitch_v += ((tp - _pitch) * SUSP_K - _pitch_v * SUSP_C) * dt
	_pitch += _pitch_v * dt
	_roll_v += ((tr - _roll) * SUSP_K - _roll_v * SUSP_C) * dt
	_roll += _roll_v * dt
	_heave_v += (-_heave * SUSP_K * 1.6 - _heave_v * SUSP_C) * dt
	_heave += _heave_v * dt
	# two incommensurate waves read as uneven tarmac, not a sine
	var bob := (sin(_dist * 1.9) * 0.6 + sin(_dist * 5.3 + 1.3) * 0.4) * 0.006 * spn
	var bp := sin(_dist * 3.1 + 0.7) * 0.0018 * spn
	var b := Basis.from_euler(Vector3(_pitch + bp, 0.0, _roll))
	model.transform = Transform3D(b * _model_rest, ROLL_PIVOT - b * ROLL_PIVOT + Vector3(0, _heave + bob, 0))
	for w in _wheel_rest:
		(w as Node3D).global_position = to_global(_wheel_rest[w])
	if _skid_mat:
		_skid_mat.set_shader_parameter("now", _t)

## Nose-first into a wreck: the chassis bucks, the cabin shakes, and you
## hear the weight of it before the scrape of metal.
func _impact(spd: float, n: Vector3) -> void:
	var k := clampf(spd / MAX_FWD, 0.3, 1.0)
	var ln := global_basis.inverse() * n
	_pitch_v -= ln.z * 0.9 * k
	_roll_v -= ln.x * 0.7 * k
	_heave_v += 0.3 * k
	_shake = maxf(_shake, 0.45 + 0.5 * k)
	Game.play_file("sfx-body-drop.mp3", lerpf(-8.0, 1.0, k), randf_range(0.5, 0.6))
	if k > 0.7:
		Game.play("hit_glass", -12.0, 0.8)

## The tail lamps: dim with the engine on, bright on the brakes. One copy of
## the lens material, so the lot's other cars (and the import) are untouched.
func _brake_lamps() -> void:
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for i in m.mesh.get_surface_count():
			var mat := m.mesh.surface_get_material(i)
			if mat is StandardMaterial3D and (mat as StandardMaterial3D).resource_name.to_lower() == "redglass":
				if _brake_mat == null:
					_brake_mat = (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
					_brake_mat.albedo_color = Color(0.55, 0.04, 0.05, 0.9)
					_brake_mat.emission_enabled = true
					_brake_mat.emission = Color(1.0, 0.06, 0.04)
					_brake_mat.emission_energy_multiplier = 0.0
				m.set_surface_override_material(i, _brake_mat)

# ------------------------------------------------------------------ tyres

const SKID_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform float now = 0.0;
uniform float life = 22.0;
varying float fade;
void vertex() {
	// custom.r: when it was laid, custom.g: how hard the tyre was sliding
	float age = now - INSTANCE_CUSTOM.r;
	fade = clamp(1.0 - age / life, 0.0, 1.0) * INSTANCE_CUSTOM.g;
}
void fragment() {
	// rubber is densest mid-tread and feathers at the edges
	float edge = 1.0 - pow(abs(UV.y * 2.0 - 1.0), 3.0);
	ALBEDO = vec3(0.02, 0.02, 0.021);
	ROUGHNESS = 0.55;
	ALPHA = fade * edge * 0.8;
}
"""

func _build_skids() -> void:
	var sh := Shader.new()
	sh.code = SKID_SHADER
	_skid_mat = ShaderMaterial.new()
	_skid_mat.shader = sh
	_skid_mat.set_shader_parameter("life", SKID_LIFE)
	var pm := PlaneMesh.new()
	pm.size = Vector2.ONE
	pm.material = _skid_mat
	_skid_mm = MultiMesh.new()
	_skid_mm.transform_format = MultiMesh.TRANSFORM_3D
	_skid_mm.use_custom_data = true
	_skid_mm.mesh = pm
	_skid_mm.instance_count = SKID_N
	var hidden := Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -50, 0))
	for i in SKID_N:
		_skid_mm.set_instance_transform(i, hidden)
		_skid_mm.set_instance_custom_data(i, Color(-1000.0, 0, 0, 0))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "SkidMarks"
	mmi.multimesh = _skid_mm
	mmi.top_level = true
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-1100, -1, -20), Vector3(1350, 3, 90))
	add_child(mmi)
	mmi.global_transform = Transform3D.IDENTITY

## a soft round puff, made once
func _build_smoke() -> void:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 64
	gt.height = 64
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = gt
	mat.albedo_color = Color(0.78, 0.78, 0.8)
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var qm := QuadMesh.new()
	qm.size = Vector2(1.1, 1.1)
	qm.material = mat
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0))
	ramp.set_color(1, Color(1, 1, 1, 0))
	ramp.add_point(0.12, Color(1, 1, 1, 0.32))
	ramp.add_point(0.5, Color(1, 1, 1, 0.16))
	var rt := GradientTexture1D.new()
	rt.gradient = ramp
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.3))
	sc.add_point(Vector2(1, 1))
	var st := CurveTexture.new()
	st.curve = sc
	var pp := ParticleProcessMaterial.new()
	pp.direction = Vector3(0, 1, 0)
	pp.spread = 70.0
	pp.initial_velocity_min = 0.3
	pp.initial_velocity_max = 1.1
	pp.gravity = Vector3(0, 0.35, 0)
	pp.damping_min = 0.6
	pp.damping_max = 1.0
	pp.scale_min = 1.2
	pp.scale_max = 2.4
	pp.scale_curve = st
	pp.color_ramp = rt
	pp.angle_min = 0.0
	pp.angle_max = 360.0
	pp.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pp.emission_box_extents = Vector3(0.12, 0.05, 0.2)
	for i in 2:
		var p := GPUParticles3D.new()
		p.amount = 26
		p.lifetime = 1.8
		p.local_coords = false
		p.emitting = false
		p.process_material = pp
		p.draw_pass_1 = qm
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.visibility_aabb = AABB(Vector3(-22, -1, -22), Vector3(44, 8, 44))
		p.position = _rear[i] + Vector3(0, 0.15, 0.15)
		add_child(p)
		_smoke.append(p)

## A tyre scrub, synthesised once: band-passed noise with a faint wavering
## whine on top. One second, looped, so nothing is allocated while driving.
func _build_squeal() -> void:
	var rate := 22050
	var data := PackedByteArray()
	data.resize(rate * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var lo1 := 0.0
	var lo2 := 0.0
	for i in rate:
		var t := float(i) / rate
		var nz := rng.randf_range(-1.0, 1.0)
		lo1 += (nz - lo1) * 0.35
		lo2 += (lo1 - lo2) * 0.08
		var band := lo1 - lo2
		# 1100 Hz with a 7 Hz wobble: whole cycles in a second, so the loop is seamless
		var ph := TAU * 1100.0 * t + (40.0 / 7.0) * sin(TAU * 7.0 * t)
		var s := band * 0.7 + sin(ph) * 0.18 * (0.7 + 0.3 * sin(TAU * 3.0 * t))
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 26000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = rate
	_squeal = AudioStreamPlayer3D.new()
	_squeal.stream = wav
	_squeal.volume_db = -80.0
	_squeal.unit_size = 6.0
	_squeal.max_distance = 80.0
	_squeal.position = Vector3(0, 0.3, 1.2)
	add_child(_squeal)

## Lay rubber under both rear tyres while they slide: a quad from the last
## mark to here once the tyre has moved far enough, into the ring buffer.
func _skid_update() -> void:
	var on := _skid > 0.0 and absf(speed) > 0.6
	for i in 2:
		var p := to_global(_rear[i])
		p.y = 0.03
		if not on:
			_skid_last[i] = null
			continue
		if _skid_last[i] == null:
			_skid_last[i] = p
			continue
		var a: Vector3 = _skid_last[i]
		var d := p - a
		var len := d.length()
		if len > 4.0:              # a teleport (act change), not a slide
			_skid_last[i] = p
		elif len > 0.4:
			var dn := d / len
			var perp := Vector3(-dn.z, 0.0, dn.x)
			var seg := Basis(dn * (len + 0.06), Vector3.UP, perp * 0.21)
			_skid_mm.set_instance_transform(_skid_i, Transform3D(seg, (a + p) * 0.5))
			_skid_mm.set_instance_custom_data(_skid_i, Color(_t, _skid, 0, 0))
			_skid_i = (_skid_i + 1) % SKID_N
			_skid_last[i] = p
	for s in _smoke:
		var gp := s as GPUParticles3D
		var want := on and absf(speed) > 1.5
		if want:
			gp.amount_ratio = clampf(_skid, 0.2, 1.0)
		if gp.emitting != want:
			gp.emitting = want
	if _squeal:
		var target := lerpf(-22.0, -9.0, _skid) if on else -80.0
		_squeal.volume_db = move_toward(_squeal.volume_db, target, 240.0 * get_physics_process_delta_time())
		_squeal.pitch_scale = 0.85 + clampf(absf(speed) / MAX_FWD, 0.0, 1.0) * 0.25
		if _squeal.volume_db > -60.0 and not _squeal.playing:
			_squeal.play()
		elif _squeal.volume_db <= -60.0 and _squeal.playing:
			_squeal.stop()
