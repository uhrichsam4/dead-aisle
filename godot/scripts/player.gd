## First-person operator: movement, look, the rifle and the viewmodel.
## Numbers are the web build's: 4.6 m/s walk, 7.2 sprint, the same bob, the
## same three AK-74 builds and their damage / fire interval / spread.
extends CharacterBody3D

const U := preload("res://scripts/util.gd")
const MosqueScript := preload("res://scripts/mosque.gd")
const Fx := preload("res://scripts/fx.gd")

signal died
signal hp_changed(hp: float, max_hp: float)
signal ammo_changed(mag: int, mag_size: int, weapon_name: String)
signal hit_marker(headshot: bool, kill: bool)
signal damaged(from: Vector3)

const WALK := 4.6
const SPRINT := 7.2
const ACCEL := 12.0
const GRAVITY := 18.0
const JUMP := 5.2
const EYE := 1.7
const MOUSE_SENS := 0.0022

const WEAPONS := [
	{"id": "ak_tactical", "name": "AK-74 TACTICAL", "damage": 34.0, "interval": 0.095, "spread": 0.011},
	{"id": "ak_wood",     "name": "AK-74 WOOD",     "damage": 38.0, "interval": 0.112, "spread": 0.0095},
	{"id": "ak_scoped",   "name": "AK-74 1P29",     "damage": 42.0, "interval": 0.135, "spread": 0.008},
]
const MAG_SIZE := 30
const RELOAD_TIME := 1.9
const HEAD_MULT := 2.6

## rifle-in-hand calibration from the web build (camera-space nudge, radians)
const GRIP := {"x": 0.02, "y": 0.10, "z": -0.28, "tilt_x": -0.06, "tilt_y": 0.05, "tilt_z": 0.0, "scale": 1.0}
const AK_FIT := {"scale": 0.8, "pos": Vector3(0.04, -0.03, 0.0)}

var hp := 100.0
var max_hp := 100.0
var alive := true
var active := false          # false while driving / in cutscenes
var input_locked := false    # on camera, but the arrival is steering the view
var holding := false         # a cart / melon / axe in hand: no rifle (throwables.gd)
var yaw := PI
var pitch := 0.0
var fov_base := 80.0

var camera: Camera3D
var vm_cam: Camera3D
var vm_layer: CanvasLayer
var vm_root: Node3D
var op: Node3D
var anim: AnimationPlayer
var hand_r: Node3D
var gun_root: Node3D
var guns := {}
var flash_light: OmniLight3D
var flash_mesh: MeshInstance3D

var weapon_index := 0
var mag := MAG_SIZE
var reloading := false
var reload_t := 0.0
var _reload_stage := 0
var fire_cd := 0.0
var ads_t := 0.0
var recoil := 0.0
var kick := 0.0
var bob_t := 0.0
var stride := 0.0
var regen_cd := 0.0
var shake := 0.0
var _anim_now := ""
# audio state
var breath: AudioStreamPlayer
var exertion := 0.0          # 0 calm .. 1 spent; sprinting builds it, rest drains it
var _was_aiming := false
var _was_floor := true
var _rustle_t := 4.0
var _low_hp_said := false
var _dead_t := 0.0
var _sprinting := false
var _vm_view: SubViewport
var _fov_now := 88.0
var heart: AudioStreamPlayer
var _heart_t := 0.0
var _holes: Array[Decal] = []
static var _hole_tex: Texture2D
# weapon feel: the rig hangs off a pivot at the eye so sway, the sprint carry
# and the landing dip swing it about the view, not about the operator's feet
var vm_pivot: Node3D
var _rec := Vector2.ZERO          # recoil on the view now (pitch, yaw)
var _rec_to := Vector2.ZERO       # where the kicks are pushing it
var _punch := 0.0
var _punch_side := 1.0
var _sway := Vector2.ZERO
var _sway_to := Vector2.ZERO
var _sprint_k := 0.0
var _land_t := 1.0
var _land_amp := 0.0
var _flash_frames := 0
# brass: a ring of casings, reused oldest-first
const CASINGS := 16
var _casings: Array[RigidBody3D] = []
var _casing_i := 0
static var _casing_mesh: CylinderMesh
static var _casing_shape: CapsuleShape3D
# the lens is a GoPro strapped to the helmet, not the eyes: up on the shell,
# over the right temple, a touch proud of the brow. It rides the head's pitch.
const MOUNT := Vector3(0.045, 0.085, -0.035)
const SHUTTER := 1.0 / 90.0       # how long the sensor smears a whip-pan
var _step_ph := 0.0               # footfalls: every whole number lands a foot
var _bob_amp := 0.0
var _bob_sprint := 0.0
var _lean := 0.0
var _prev_look := Vector2.ZERO
var _turn_w := Vector2.ZERO       # the look's angular rate (yaw, pitch), rad/s
var _turn_off := Vector3.ZERO     # the head lagging a whip and settling (spring)
var _turn_vel := Vector3.ZERO
var _hj := Vector3.ZERO           # head jolts: shots, hits, landings (spring)
var _hjv := Vector3.ZERO
var _hp := Vector3.ZERO           # the same, as a shove of the head
var _hpv := Vector3.ZERO
var _breath_t := 0.0
var _shake_t := 0.0
var _vm_lag := 0.0                # the rifle rides the body, a beat behind the head
var _post_mat: ShaderMaterial
var _blur_sent := Vector2.ZERO

func _on_settings() -> void:
	fov_base = float(Game.settings.fov)
	if _vm_view:
		_vm_view.scaling_3d_scale = Game.render_scale()

func _ready() -> void:
	_on_settings()
	Game.settings_changed.connect(_on_settings)
	collision_layer = 2
	collision_mask = 1
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.42
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	add_child(cs)

	camera = Camera3D.new()
	camera.position.y = EYE
	camera.fov = fov_base
	camera.near = 0.05
	camera.far = 900.0
	camera.cull_mask = 0xFFFFF & ~2   # everything but the viewmodel layer
	add_child(camera)
	_build_viewmodel()
	breath = AudioStreamPlayer.new()
	breath.volume_db = -16.0
	add_child(breath)
	breath.finished.connect(_next_breath)
	heart = AudioStreamPlayer.new()
	heart.stream = Game.heartbeat()
	heart.volume_db = -3.0
	add_child(heart)

func activate(on: bool) -> void:
	active = on
	visible = on
	vm_layer.visible = on
	_settle_head()
	if on:
		camera.current = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if breath and not breath.playing:
			_next_breath()
	elif breath:
		breath.stop()

func place_at(p: Vector3, face_yaw: float) -> void:
	global_position = Vector3(p.x, maxf(p.y - EYE, 0.0), p.z)
	yaw = face_yaw
	pitch = 0.0
	velocity = Vector3.ZERO
	_settle_head()

## a cut (on or off foot, a teleport) is not a whip-pan: no lag, no smear
func _settle_head() -> void:
	_prev_look = Vector2(yaw, pitch)
	_turn_w = Vector2.ZERO
	_turn_off = Vector3.ZERO
	_turn_vel = Vector3.ZERO
	_send_blur(Vector2.ZERO)

func _notification(what: int) -> void:
	# a pause freezes _process: never leave the menu smeared mid-turn
	if what == NOTIFICATION_PAUSED:
		_send_blur(Vector2.ZERO)

func _send_blur(b: Vector2) -> void:
	if _post_mat == null:
		var cs := get_tree().current_scene if is_inside_tree() else null
		if cs == null or not ("post" in cs):
			return
		_post_mat = cs.get("post") as ShaderMaterial
		if _post_mat == null:
			return
	if b.is_equal_approx(_blur_sent):
		return
	_blur_sent = b
	_post_mat.set_shader_parameter(&"cam_blur", b)

# ------------------------------------------------------------------ viewmodel

func _build_viewmodel() -> void:
	# The arms and rifle are drawn by their own camera into a transparent
	# SubViewport on top of the world - the same trick as the web build's
	# second pass - so they never clip into a wall and get their own FOV.
	vm_layer = CanvasLayer.new()
	vm_layer.layer = 1
	add_child(vm_layer)
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vm_layer.add_child(svc)
	var sv := SubViewport.new()
	_vm_view = sv
	sv.scaling_3d_scale = Game.render_scale()
	sv.transparent_bg = true
	sv.msaa_3d = Viewport.MSAA_4X
	sv.handle_input_locally = false
	svc.add_child(sv)
	vm_cam = Camera3D.new()
	vm_cam.cull_mask = 2
	vm_cam.fov = 52.0
	vm_cam.near = 0.01
	vm_cam.far = 10.0
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.57, 0.6)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	vm_cam.environment = env
	# its own fixed exposure: the world's auto exposure (main.gd) would meter
	# this mostly-empty layer and blow the rifle out
	vm_cam.attributes = CameraAttributesPractical.new()
	sv.add_child(vm_cam)
	# its own key and fill, like every FPS - at night the world lights leave
	# the rifle a black silhouette
	var key := DirectionalLight3D.new()
	key.light_cull_mask = 2
	key.light_energy = 1.3
	key.light_color = Color(1, 0.94, 0.86)
	key.rotation = Vector3(-0.9, 0.5, 0)
	vm_cam.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.light_cull_mask = 2
	fill.light_energy = 0.5
	fill.light_color = Color(0.62, 0.7, 0.82)
	fill.rotation = Vector3(-0.2, -1.2, 0)
	vm_cam.add_child(fill)

	vm_pivot = Node3D.new()
	vm_cam.add_child(vm_pivot)
	vm_root = Node3D.new()
	vm_root.position = Vector3(-0.02, -1.34, 0.02)
	vm_root.scale = Vector3.ONE * 0.84
	vm_pivot.add_child(vm_root)

	var ps: PackedScene = load("res://assets/operator.glb")
	op = ps.instantiate() as Node3D
	op.rotation.y = PI
	vm_root.add_child(op)
	var head := op.find_child("Head", true, false) as Node3D
	if head:
		head.visible = false          # never fill the lens with your own skull
	anim = op.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim:
		for a in ["idle", "walk", "run", "aim", "crouch", "look_around"]:
			if anim.has_animation(a):
				anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	hand_r = op.find_child("Hand_R", true, false) as Node3D

	gun_root = Node3D.new()
	var lib := U.glb("res://assets/guns.glb")
	for w in WEAPONS:
		var src := lib.find_child(w.id, true, false) if lib else null
		if src:
			var g := src.duplicate() as Node3D
			g.scale = Vector3.ONE * AK_FIT.scale
			g.position = AK_FIT.pos
			g.rotation = Vector3.ZERO
			g.visible = false
			gun_root.add_child(g)
			guns[w.id] = g
			_gun_decal(g)
	# the flash: a ragged star burst, hot white at the core, re-rolled every
	# shot (rotation, size) and up for one or two frames only
	flash_mesh = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.3, 0.3)
	flash_mesh.mesh = q
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.albedo_texture = Fx.star_texture()
	fm.albedo_color = Color(2.6, 1.8, 1.0, 1.0)
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fm.billboard_keep_scale = true
	fm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	fm.no_depth_test = true
	flash_mesh.material_override = fm
	flash_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flash_mesh.position = Vector3(0.04, 0.02, -0.42)
	flash_mesh.visible = false
	flash_mesh.layers = 2
	gun_root.add_child(flash_mesh)

	if hand_r:
		hand_r.add_child(gun_root)
	else:
		vm_cam.add_child(gun_root)
		gun_root.position = Vector3(0.18, -0.2, -0.45)
	U.set_layers(op, 2)
	U.set_layers(gun_root, 2)
	U.set_shadows(op, false)
	# the muzzle flash lights the WORLD, so it rides the main camera
	flash_light = OmniLight3D.new()
	flash_light.light_color = Color(1, 0.73, 0.4)
	flash_light.light_energy = 0.0
	flash_light.omni_range = 7.0
	flash_light.position = Vector3(0.1, -0.1, -0.6)
	camera.add_child(flash_light)
	select_weapon(0, true)
	call_deferred("_calibrate_grip")
	(func(): Fx.warm()).call_deferred()

## GUN_DECAL: "MOGGED" on both flanks of the receiver, each facing out,
## sized off the weapon's own bounds (the three builds differ in width)
func _gun_decal(g: Node3D) -> void:
	var b := U.local_aabb(g)
	var sc := g.scale.x
	var lo := b.position
	var hi := b.end
	var cz := (lo.z + hi.z) * 0.5
	var cy := (lo.y + hi.y) * 0.5
	var ln := absf(hi.z - lo.z)
	var tall := absf(hi.y - lo.y)
	var w := minf(ln * 0.26, 0.34 / sc) * 0.78          # GUN_DECAL.scale
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Arial Black", "Arial", "Helvetica Neue"])
	f.font_weight = 900
	var fs := 118
	var tw := f.get_string_size("MOGGED", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var squeeze := minf(1.0, 472.0 / maxf(1.0, tw))       # squeezed to fit the 512 px sticker
	for side in [-1, 1]:
		var l := Label3D.new()
		l.name = "gun_decal"
		l.text = "MOGGED"
		l.font = f
		l.font_size = fs
		l.modulate = Color("e8e2d4")
		l.outline_modulate = Color(0, 0, 0, 0.55)
		l.outline_size = int(fs * 0.16)
		l.pixel_size = w / 512.0
		l.scale = Vector3(squeeze, 1, 1)
		l.double_sided = false
		l.shaded = true
		l.alpha_cut = Label3D.ALPHA_CUT_DISABLED
		l.layers = 2
		l.position = Vector3((lo.x if side < 0 else hi.x) + side * 0.004 / sc, cy + tall * 0.06 + 0.010 / sc, cz + 0.10 / sc)
		l.rotation.y = -PI / 2 if side < 0 else PI / 2
		g.add_child(l)

## Solve the rotation that points the rifle down the camera axis while it
## sits in the hand - the hand bone's axes are arbitrary, so guessing Euler
## angles never works. Solved IN THE AIM POSE: the web build calibrates on the
## first frame after the aim clip has posed the hand, and solving against the
## rest pose instead parked the rifle a quarter-metre behind the hand.
func _calibrate_grip() -> void:
	_play("aim", 0.0)
	if anim:
		anim.advance(0.0)
	if hand_r == null:
		return
	var hq := hand_r.global_basis.get_rotation_quaternion()
	var cq := vm_cam.global_basis.get_rotation_quaternion()
	var hs := hand_r.global_basis.get_scale().x
	var inv := 1.0 / maxf(0.0001, hs)
	gun_root.quaternion = hq.inverse() * cq
	gun_root.rotate_object_local(Vector3.RIGHT, GRIP.tilt_x)
	gun_root.rotate_object_local(Vector3.UP, GRIP.tilt_y)
	gun_root.rotate_object_local(Vector3.BACK, GRIP.tilt_z)
	var nudge := cq * Vector3(GRIP.x, GRIP.y, GRIP.z)
	gun_root.position = (hq.inverse() * nudge) * inv
	gun_root.scale = Vector3.ONE * inv * GRIP.scale

func _play(name: String, blend := 0.2) -> void:
	if anim == null or _anim_now == name or not anim.has_animation(name):
		return
	anim.play(name, blend)
	_anim_now = name

# ------------------------------------------------------------------ breathing

## One breath after another, the family picked by how hard you are working:
## calm on your feet, medium and heavy as a sprint wears on, spent when you
## are hurt or blown, and held while you aim.
func _next_breath() -> void:
	if not active or not alive:
		return
	var fam := "breath_calm"
	if hp < max_hp * 0.3 or exertion > 0.85:
		fam = "breath_spent"
	elif ads_t > 0.6:
		fam = "breath_hold"
	elif exertion > 0.55:
		fam = "breath_heavy"
	elif exertion > 0.25:
		fam = "breath_medium"
	var v: Array = Game.variants(fam)
	if v.is_empty():
		return
	breath.stream = v[randi() % v.size()]
	breath.volume_db = lerpf(-19.0, -10.0, clampf(exertion, 0.0, 1.0))
	breath.pitch_scale = randf_range(0.96, 1.04)
	breath.play()

# ------------------------------------------------------------------ weapons

## the arrival hands you the rifle only when you take it out of the boot
func refresh_ammo() -> void:
	ammo_changed.emit(mag, MAG_SIZE, WEAPONS[weapon_index].name)

func show_rifle(on: bool) -> void:
	if gun_root:
		gun_root.visible = on

func select_weapon(i: int, silent := false) -> void:
	if i < 0 or i >= WEAPONS.size():
		return
	if i != weapon_index and not silent:
		Game.play("gun_holster", -8.0)
		get_tree().create_timer(0.18).timeout.connect(func(): Game.play("gun_draw", -4.0))
	weapon_index = i
	for id in guns:
		guns[id].visible = (id == WEAPONS[i].id)
	ammo_changed.emit(mag, MAG_SIZE, WEAPONS[i].name)

func try_reload() -> void:
	if reloading or mag >= MAG_SIZE or not alive:
		return
	reloading = true
	reload_t = 0.0
	_reload_stage = 0
	Game.vo("reloading", 14.0, 0.35)
	if anim and anim.has_animation("reload"):
		anim.play("reload", 0.12)
		_anim_now = "reload"

func _reload_tick(dt: float) -> void:
	if not reloading:
		return
	reload_t += dt
	# a reload is several events, not one noise: mag out, a fumble, mag in,
	# bolt home - scheduled as fractions of the reload
	var stages := [[0.08, "gun_magout"], [0.34, "gun_fumble"], [0.55, "gun_magin"], [0.8, "gun_charge"]]
	while _reload_stage < stages.size() and reload_t >= stages[_reload_stage][0] * RELOAD_TIME:
		Game.play(stages[_reload_stage][1], -5.0)
		_reload_stage += 1
	if reload_t >= RELOAD_TIME:
		reloading = false
		mag = MAG_SIZE
		_anim_now = ""
		ammo_changed.emit(mag, MAG_SIZE, WEAPONS[weapon_index].name)

func _fire() -> void:
	if reloading or fire_cd > 0.0 or not alive:
		return
	if mag <= 0:
		Game.play("gun_dry", -6.0)
		Game.vo("need_ammo", 20.0, 0.4)
		fire_cd = 0.25
		try_reload()
		return
	var w: Dictionary = WEAPONS[weapon_index]
	fire_cd = w.interval
	mag -= 1
	Game.shots += 1
	ammo_changed.emit(mag, MAG_SIZE, w.name)
	GunSound.fire(camera.global_position, Game.phase == "inside")   # crack, mechanism, echo or reverb
	# recoil: a vertical kick with a little random drift sideways, pushed onto
	# a target the view eases toward, so a burst climbs rather than snaps;
	# a braced aim soaks up nearly half of it
	var steady := lerpf(1.0, 0.55, ads_t)
	_rec_to.x += 0.017 * steady * randf_range(0.85, 1.15)
	_rec_to.y += randf_range(-0.0055, 0.0055) * steady
	_punch = 1.0
	_punch_side = -1.0 if randf() < 0.5 else 1.0
	# the report through the stock, the shoulder and up the neck: the helmet
	# nods and twists a little on every round (half of it braced on the sights)
	var brace := lerpf(1.0, 0.45, ads_t)
	_hjv.x += 0.12 * brace * randf_range(0.8, 1.2)
	_hjv.z += randf_range(-0.22, 0.22) * brace
	_hpv.z += 0.3 * brace
	kick = 1.0
	shake = maxf(shake, 0.12)
	flash_light.light_energy = randf_range(3.4, 4.8)
	flash_mesh.visible = true
	flash_mesh.rotation.z = randf() * TAU
	flash_mesh.scale = Vector3.ONE * randf_range(0.75, 1.35)
	_flash_frames = 1 + randi() % 2
	_eject_casing()

	var spread: float = w.spread * (0.35 if ads_t > 0.5 else 1.0)
	var from := camera.global_position
	var dir := -camera.global_basis.z
	dir = (dir + camera.global_basis.x * randf_range(-spread, spread) + camera.global_basis.y * randf_range(-spread, spread)).normalized()
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 250.0, 1 | 4 | 8 | 32)   # 8: the car, 32: small props
	q.exclude = [get_rid()]
	q.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	var col: Object = hit.collider
	var target: Node = col as Node
	while target and not target.has_method("take_hit"):
		target = target.get_parent()
	if target and target.has_method("take_hit"):
		var headshot: bool = target.call("is_head", hit.position)
		var dmg: float = w.damage * (HEAD_MULT if headshot else 1.0)
		var killed: bool = target.call("take_hit", dmg, hit.position, dir)
		Game.hits += 1
		if headshot:
			Game.headshots += 1
		# the web's table: +10 / +15 a hit, +55 / +90 a kill
		Game.add_points(15 if headshot else 10)
		if killed:
			var base := 90 if headshot else 55
			Game.add_points(base, ("HEADSHOT +%d" if headshot else "+%d") % base, headshot)
		hit_marker.emit(headshot, killed)
		if killed and headshot:
			Game.vo("nice_shot", 15.0, 0.5)
	else:
		var surf := "concrete"
		var n: Node = col as Node
		while n:
			if n.has_meta("surface"):
				surf = n.get_meta("surface")
				break
			n = n.get_parent()
		# the car is a CharacterBody3D, not tagged - it is a car
		if col is CharacterBody3D:
			surf = "metal"
		_impact(hit.position, hit.normal, surf)
		# glass, crates, pottery: breakable.gd
		if col is Node and (col as Node).has_method("shoot"):
			col.call("shoot", w.damage, hit.position, dir)
		elif not (col is CharacterBody3D):
			_bullet_hole(hit.position, hit.normal)

## a hole that stays where the round went in; the oldest of 64 is reused
func _bullet_hole(pos: Vector3, n: Vector3) -> void:
	if _hole_tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.35, 0.6, 1.0])
		g.colors = PackedColorArray([Color(0.02, 0.018, 0.015, 1), Color(0.05, 0.045, 0.04, 0.95),
			Color(0.12, 0.11, 0.1, 0.45), Color(0.2, 0.19, 0.18, 0)])
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(1.0, 0.5)
		gt.width = 32
		gt.height = 32
		_hole_tex = gt
	var d: Decal
	if _holes.size() >= 64:
		d = _holes.pop_front()
	else:
		d = Decal.new()
		d.texture_albedo = _hole_tex
		d.size = Vector3(0.08, 0.1, 0.08)
		d.cull_mask = 1 | 32            # walls and props, never people or the car
		get_tree().current_scene.add_child(d)
	_holes.append(d)
	var up := n.normalized()
	var ref := Vector3.UP if absf(up.y) < 0.95 else Vector3.RIGHT
	var x := ref.cross(up).normalized()
	var z := x.cross(up).normalized()
	d.global_transform = Transform3D(Basis(up, randf() * TAU) * Basis(x, up, z), pos)
	d.scale = Vector3.ONE * randf_range(0.8, 1.25)

func _impact(pos: Vector3, normal: Vector3, kind := "concrete") -> void:
	Game.play_at("hit_" + kind, pos, -6.0)
	Fx.impact(pos, normal, kind)      # pooled sparks / dust / chips / splinters / shards

## a spent case out of the port, to the right and a little forward, carrying
## your own speed; it tinks once on the first thing it meets
func _eject_casing() -> void:
	var host := get_tree().current_scene
	if host == null:
		return
	var b: RigidBody3D
	if _casings.size() < CASINGS:
		b = _make_casing()
		host.add_child(b)
		_casings.append(b)
	else:
		b = _casings[_casing_i]
		_casing_i = (_casing_i + 1) % CASINGS
		if not is_instance_valid(b) or not b.is_inside_tree():
			b = _make_casing()
			host.add_child(b)
			_casings[(_casing_i + CASINGS - 1) % CASINGS] = b
	var cb := camera.global_basis
	var at := camera.global_position + cb * Vector3(0.09, -0.09, -0.32 + ads_t * 0.08)
	# lie across the view, the way it leaves the port
	b.global_transform = Transform3D(cb * Basis(Vector3.BACK, PI / 2), at)
	b.linear_velocity = velocity + cb * Vector3(randf_range(2.2, 3.2), randf_range(1.3, 2.1), randf_range(-0.1, 0.5))
	b.angular_velocity = cb * Vector3(randf_range(-6, 6), randf_range(-25, -12), randf_range(-8, 8))
	b.sleeping = false
	b.set_meta("fresh", true)

func _make_casing() -> RigidBody3D:
	if _casing_mesh == null:
		_casing_mesh = CylinderMesh.new()
		_casing_mesh.top_radius = 0.0048
		_casing_mesh.bottom_radius = 0.0056
		_casing_mesh.height = 0.028
		_casing_mesh.radial_segments = 8
		_casing_mesh.rings = 1
		var m := U.flat_mat(Color(0.78, 0.57, 0.25), 0.28, 1.0)
		_casing_mesh.material = m
		_casing_shape = CapsuleShape3D.new()
		_casing_shape.radius = 0.0056
		_casing_shape.height = 0.028
	var b := RigidBody3D.new()
	b.collision_layer = 0          # nothing hits a case; it only meets the world
	b.collision_mask = 1 | 32
	b.mass = 0.01
	b.continuous_cd = true
	b.contact_monitor = true
	b.max_contacts_reported = 1
	b.angular_damp = 1.5
	var pmat := PhysicsMaterial.new()
	pmat.bounce = 0.35
	pmat.friction = 0.6
	b.physics_material_override = pmat
	var cs := CollisionShape3D.new()
	cs.shape = _casing_shape
	b.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = _casing_mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	b.add_child(mi)
	b.body_entered.connect(_casing_hit.bind(b))
	return b

func _casing_hit(_body: Node, b: RigidBody3D) -> void:
	if not b.get_meta("fresh", false):
		return
	b.set_meta("fresh", false)
	Game.play_at("hit_metal", b.global_position, -24.0, randf_range(2.2, 2.7))

# ------------------------------------------------------------------ damage

func take_damage(dmg: float, from: Vector3) -> void:
	if not alive or not active or Game.god:
		return
	hp = maxf(0.0, hp - dmg)
	regen_cd = 4.0
	shake = maxf(shake, 0.35)
	# the head snaps away from the blow and comes back
	var to := from - global_position
	var side := signf(to.dot(Vector3(cos(yaw), 0.0, -sin(yaw)))) if to.length_squared() > 0.01 else 0.0
	var s := clampf(dmg / 25.0, 0.4, 1.2)
	_hjv += Vector3(randf_range(0.4, 0.9), side * 0.8 + randf_range(-0.2, 0.2), side * 1.3 +randf_range(-0.3, 0.3)) * s
	_hpv += Vector3(-side * 0.4, 0.1, 0.5) * s
	damaged.emit(from)
	hp_changed.emit(hp, max_hp)
	Game.play("pain_hit", -3.0)
	Game.play_file("sfx-player-hit.mp3", -6.0, randf_range(0.95, 1.05))
	Game.vo("hit", 12.0, 0.3)
	if hp < max_hp * 0.3 and not _low_hp_said and hp > 0.0:
		_low_hp_said = true
		Game.vo("low_hp", 20.0)
	if hp > max_hp * 0.6:
		_low_hp_said = false
	if hp <= 0.0:
		alive = false
		breath.stop()
		Game.play_file("sfx-body-drop.mp3", -4.0)
		died.emit()

func heal_full() -> void:
	hp = max_hp
	alive = true
	_dead_t = 0.0
	hp_changed.emit(hp, max_hp)

# ------------------------------------------------------------------ loop

func _unhandled_input(e: InputEvent) -> void:
	if not active or not alive or input_locked:
		return
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var m := e as InputEventMouseMotion
		var sens: float = MOUSE_SENS * float(Game.settings.sens) / 100.0
		var inv := -1.0 if Game.settings.invert else 1.0
		yaw -= m.relative.x * sens
		pitch = clampf(pitch - m.relative.y * sens * inv, -1.45, 1.45)
		# the rifle trails the turn a touch: it has weight
		_sway_to += Vector2(m.relative.x, m.relative.y * inv) * sens * 0.35
		_sway_to = _sway_to.clamp(Vector2(-0.07, -0.05), Vector2(0.07, 0.05))
	elif holding:
		return               # hands are full: no reload, no weapon swap
	elif e.is_action_pressed("reload"):
		try_reload()
	elif e.is_action_pressed("weapon_1"):
		select_weapon(0)
	elif e.is_action_pressed("weapon_2"):
		select_weapon(1)
	elif e.is_action_pressed("weapon_3"):
		select_weapon(2)
	elif e.is_action_pressed("next_weapon"):
		select_weapon((weapon_index + 1) % WEAPONS.size())

func _physics_process(dt: float) -> void:
	if not active:
		return
	fire_cd = maxf(0.0, fire_cd - dt)
	if input_locked:
		velocity = Vector3.ZERO
		return
	if alive:
		_move(dt)
		if Input.is_action_pressed("fire") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not holding:
			_fire()
	if alive and not holding:
		_reload_tick(dt)
	# under a third of your health the heart comes up, faster the worse it is
	if alive and hp < max_hp * 0.35:
		_heart_t -= dt
		if _heart_t <= 0.0:
			_heart_t = lerpf(0.5, 0.95, hp / (max_hp * 0.35))
			heart.play()
	else:
		_heart_t = 0.0
	if alive and hp < max_hp:
		regen_cd -= dt
		if regen_cd <= 0.0:
			hp = minf(max_hp, hp + 9.0 * dt)
			hp_changed.emit(hp, max_hp)

func _move(dt: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var sprinting := Input.is_action_pressed("sprint") and input.y < -0.1 and ads_t < 0.3
	_sprinting = sprinting
	var spd := SPRINT if sprinting else WALK
	var basis := Basis(Vector3.UP, yaw)
	var wish := basis * Vector3(input.x, 0, input.y) * spd
	var k := clampf(ACCEL * dt, 0.0, 1.0)
	velocity.x = lerpf(velocity.x, wish.x, k)
	velocity.z = lerpf(velocity.z, wish.z, k)
	if is_on_floor():
		if Input.is_action_just_pressed("jump"):
			velocity.y = JUMP
			Game.play("pain_effort", -12.0)
			exertion = minf(1.0, exertion + 0.08)
	else:
		velocity.y -= GRAVITY * dt
	var fall_speed := -velocity.y
	move_and_slide()
	if is_on_floor() and not _was_floor and fall_speed > 3.0:
		Game.play("step_" + _surface(), -3.0, 0.85)       # landing
		Game.play("gear_rustle", -12.0)
		_land_t = 0.0
		_land_amp = clampf((fall_speed - 2.0) / 8.0, 0.2, 1.0)
		# the helmet keeps going when the boots stop: a nod and a twist
		_hjv.x -= 0.9 * _land_amp
		_hjv.z += randf_range(-0.45, 0.45) * _land_amp
	_was_floor = is_on_floor()
	exertion = clampf(exertion + (dt * 0.09 if sprinting else -dt * 0.06), 0.0, 1.0)

	var speed := Vector2(velocity.x, velocity.z).length()
	# footsteps on the stride, surface by where you are; the same phase drives
	# the head bob, so every bounce of the lens lands on a footfall
	var ph0 := _step_ph
	_step_ph += speed * dt / (1.9 if sprinting else 1.6)
	if _step_ph > 1000.0:
		_step_ph -= 1000.0        # an even count: the bob's phase is unchanged
		ph0 -= 1000.0
	if floorf(_step_ph) != floorf(ph0) and is_on_floor():
		var surf := _surface()
		var sprint_ok := sprinting and (surf == "tile" or surf == "concrete")
		Game.play(("sprint_" if sprint_ok else "step_") + surf, -9.0 if not sprinting else -7.0)
	# kit shifting on you as you move
	if speed > 1.0:
		_rustle_t -= dt * (1.6 if sprinting else 1.0)
		if _rustle_t <= 0.0:
			_rustle_t = randf_range(4.0, 8.0)
			Game.play("gear_rustle", -16.0)
	if reloading:
		pass                     # the reload clip plays out, walking or not
	elif speed > 0.5:
		_play("run" if sprinting else "walk", 0.25)
	else:
		_play("aim", 0.25)

## what you are standing on: tile in the store, asphalt and paving on the lot
## and road, grass on the verge, gravel on the unmade ground beyond it
func _surface() -> String:
	var p := global_position
	# Al-Salaam: tiled halls and courtyard, and the flags round the ablution
	# fountain are always wet (mosque-local coordinates, see mosque.gd)
	var lx := (p.x - MosqueScript.X) / MosqueScript.S
	var lz := (p.z - MosqueScript.MQ_Z) / MosqueScript.S
	if absf(lx) < 27.5 and lz > -16.5 and lz < 32.4:
		return "wet" if Vector2(lx, lz - 23.0).length() < 5.2 else "tile"
	if absf(p.x) < 22.0 and absf(p.z) < 15.0:
		return "tile"
	if absf(p.z - 36.0) < 4.2 or (absf(p.x) < 24.0 and p.z < 30.2) or absf(p.z - 31.15) < 0.8 or absf(p.z - 41.35) < 1.3:
		return "concrete"
	if p.z > 15.2 and p.z < 60.4:
		return "grass"
	return "gravel"

func _process(dt: float) -> void:
	if not active:
		return
	var aiming := Input.is_action_pressed("aim") and alive and not reloading and not input_locked and not holding
	if aiming != _was_aiming:
		Game.play("gun_adsin" if aiming else "gun_adsout", -10.0)
		_was_aiming = aiming
	ads_t = move_toward(ads_t, 1.0 if aiming else 0.0, dt * 6.0)
	# the kicks' target settles back, the view eases after it: a smooth climb
	# under a burst and a smooth recovery once the trigger comes up
	_rec_to = _rec_to.lerp(Vector2.ZERO, clampf(dt * 6.0, 0.0, 1.0))
	_rec = _rec.lerp(_rec_to, clampf(dt * 26.0, 0.0, 1.0))
	recoil = _rec.x
	kick = lerpf(kick, 0.0, clampf(dt * 14.0, 0.0, 1.0))
	_punch = maxf(0.0, _punch - dt * 16.0)
	shake = maxf(0.0, shake - dt * 2.4)
	flash_light.light_energy = lerpf(flash_light.light_energy, 0.0, clampf(dt * 30.0, 0.0, 1.0))
	if _flash_frames > 0:
		_flash_frames -= 1
	else:
		flash_mesh.visible = false
	_sway_to = _sway_to.lerp(Vector2.ZERO, clampf(dt * 7.0, 0.0, 1.0))
	_sway = _sway.lerp(_sway_to, clampf(dt * 14.0, 0.0, 1.0))
	var lower := _sprinting and not reloading and ads_t < 0.1 and Vector2(velocity.x, velocity.z).length() > WALK * 0.8
	_sprint_k = move_toward(_sprint_k, 1.0 if lower else 0.0, dt * 4.5)
	var dip := 0.0
	if _land_t < 0.42:
		_land_t += dt
		dip = sin(PI * pow(clampf(_land_t / 0.42, 0.0, 1.0), 0.6)) * 0.085 * _land_amp

	_head(dt, dip)

## The lens rides the helmet. Everything here is cosmetic and eased: the bob
## is locked to the footfalls, the head banks into strafes and whip-pans and
## settles after them, and shots, hits and landings jolt it through springs.
## The aim itself (yaw, pitch, recoil) is never delayed: the lag is a small
## spring offset that falls back to zero, so the rounds still leave the lens.
func _head(dt: float, dip: float) -> void:
	var dtc := minf(dt, 1.0 / 30.0)
	var speed := Vector2(velocity.x, velocity.z).length()
	var grounded := is_on_floor()
	var moving := clampf(speed / WALK, 0.0, 1.0) if grounded and alive else 0.0
	_bob_amp = lerpf(_bob_amp, moving, clampf(dt * 8.0, 0.0, 1.0))
	_bob_sprint = lerpf(_bob_sprint, 1.0 if (_sprinting and speed > WALK + 0.3) else 0.0, clampf(dt * 5.0, 0.0, 1.0))
	var calm := 1.0 - ads_t * 0.85
	var amp := _bob_amp * calm
	var sp := _bob_sprint
	var ph := _step_ph * PI
	var s1 := sin(ph)                         # side to side over a pair of steps
	var s2 := 0.5 - 0.5 * cos(2.0 * ph)       # up between footfalls, down on each
	var bob_y := (s2 - 0.5) * lerpf(0.028, 0.05, sp) * amp
	var bob_x := s1 * lerpf(0.016, 0.032, sp) * amp
	var bob_roll := -s1 * lerpf(0.006, 0.016, sp) * amp
	var bob_nod := (0.5 - s2) * lerpf(0.004, 0.012, sp) * amp
	var bob_yaw := s1 * lerpf(0.003, 0.009, sp) * amp
	# strafe: the head banks into the side you are moving to
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var lean_to := -velocity.dot(right) / SPRINT * 0.03 * (1.0 - ads_t * 0.6) if alive else 0.0
	_lean = lerpf(_lean, lean_to, clampf(dt * 6.0, 0.0, 1.0))
	# turn inertia: the rate of the look, eased; the head lags a whip, banks
	# into it and overshoots a hair on the stop
	var look := Vector2(yaw, pitch)
	var dl := Vector2(wrapf(look.x - _prev_look.x, -PI, PI), look.y - _prev_look.y)
	_prev_look = look
	var w := (dl / maxf(dt, 0.001)).clamp(Vector2(-14.0, -14.0), Vector2(14.0, 14.0))
	_turn_w = _turn_w.lerp(w, clampf(dt * 14.0, 0.0, 1.0))
	var tk := 1.0 - ads_t * 0.7
	var t_to := Vector3(clampf(-_turn_w.y * 0.0035, -0.012, 0.012), clampf(-_turn_w.x * 0.0035, -0.012, 0.012),
		clampf(_turn_w.x * 0.006, -0.035, 0.035)) * tk
	_turn_vel += ((t_to - _turn_off) * 170.0 - _turn_vel * 17.0) * dtc
	_turn_off += _turn_vel * dtc
	# jolts
	_hjv += (-_hj * 150.0 - _hjv * 13.0) * dtc
	_hj += _hjv * dtc
	_hpv += (-_hp * 120.0 - _hpv * 12.0) * dtc
	_hp += _hpv * dtc
	# breathing when you stand: slow, deeper when blown, half held on the sights
	_breath_t += dt * lerpf(1.4, 2.6, exertion)
	var still := (1.0 - _bob_amp) * (1.0 - ads_t * 0.6) if alive else 0.0
	var br := (0.0022 + exertion * 0.004) * still
	var breath_p := sin(_breath_t) * br
	var breath_y := sin(_breath_t * 0.5 + 1.3) * br * 0.5
	# shake, as smooth noise rather than a new random every frame
	_shake_t += dt
	var t := _shake_t
	var n := Vector3(sin(t * 31.0) + sin(t * 17.3 + 1.7), sin(t * 27.1 + 0.4) + sin(t * 13.9 + 2.2), sin(t * 23.7 + 3.1)) * 0.5 * shake

	rotation.y = 0.0
	# the punch: a flick of roll and a nudge back down the bore, gone in a blink
	var pk := _punch * _punch * (1.0 - ads_t * 0.5)
	var head := Vector3(bob_nod + breath_p + _turn_off.x + _hj.x,
		bob_yaw + breath_y + _turn_off.y + _hj.y,
		bob_roll + _lean + _turn_off.z + _hj.z + _punch_side * pk * 0.012 + n.z * 0.03)
	camera.rotation = Vector3(pitch + recoil + head.x, yaw + _rec.y + head.y, head.z)
	var hy := bob_y - dip + sin(_breath_t) * 0.004 * still
	camera.position = Vector3(0.0, EYE + hy, 0.0) + Basis(Vector3.UP, yaw) * Vector3(bob_x, 0.0, 0.0) \
		+ Basis.from_euler(Vector3(pitch, yaw, 0.0)) * MOUNT
	camera.position += camera.basis * (_hp + Vector3(n.x * 0.04, n.y * 0.04, pk * 0.018))
	if not alive:
		# the rotation is rebuilt every frame above, so the fall is a function
		# of time since death rather than a lerp that never accumulates
		_dead_t += dt
		var k := 1.0 - exp(-_dead_t * 2.0)
		camera.rotation.z = 0.35 * k
		camera.position.y = lerpf(camera.position.y, 0.6, k)
	# GoPro-wide on foot: the web's .66x aiming, 1.09x sprinting
	var want_fov := fov_base * (1.09 if _sprinting and ads_t < 0.1 else 1.0)
	_fov_now = lerpf(_fov_now, want_fov, clampf(dt * 9.0, 0.0, 1.0))
	camera.fov = lerpf(_fov_now, fov_base * 0.66, ads_t)
	# the sensor smears a fast turn (and a hit's snap): the look's rate over
	# the shutter, in screen heights, past a dead zone so a steady track stays sharp
	var ang := _turn_w + Vector2(_hjv.y, _hjv.x) * 0.5
	var vs := get_viewport().get_visible_rect().size
	var fov_v := deg_to_rad(camera.fov)
	var bv := Vector2(ang.x * SHUTTER / (fov_v * maxf(vs.x / maxf(vs.y, 1.0), 0.5)), ang.y * SHUTTER / fov_v)
	var bl := bv.length()
	var blur := Vector2.ZERO
	if bl > 0.006 and alive:
		blur = bv * (minf(bl - 0.006, 0.022) / bl)
	_send_blur(blur.snapped(Vector2(0.0005, 0.0005)))

	# the viewmodel camera rides the main one
	vm_cam.global_transform = camera.global_transform
	vm_cam.fov = lerpf(52.0, 38.0, ads_t)
	# helmet framing: from up on the shell the rifle sits lower and a touch
	# nearer; on the sights it comes back to the aim line
	var hip := 1.0 - ads_t
	vm_root.position = Vector3(-0.02 - ads_t * 0.05 - 0.012 * hip, -1.34 + ads_t * 0.035 - 0.05 * hip, 0.02 + 0.025 * hip + kick * 0.055)
	# the rig about the eye: mouse sway, muzzle climb, the sprint carry (low
	# and canted), a lag behind the landing and a little of its own bob. The
	# rifle rides the body, not the helmet, so it holds against the head's
	# nods and jolts and trails its bounce by a beat.
	_vm_lag = lerpf(_vm_lag, hy + dip, clampf(dt * 11.0, 0.0, 1.0))
	var sk := _sprint_k * _sprint_k * (3.0 - 2.0 * _sprint_k)
	var sw := 1.0 - ads_t * 0.75
	var hold := 0.45 * sw
	vm_pivot.rotation = Vector3(
		_sway.y * sw + kick * 0.045 * (1.0 - ads_t * 0.55) - sk * 0.2 - (bob_nod + _hj.x + _turn_off.x) * hold,
		_sway.x * sw + sk * 0.32 - (bob_yaw + _hj.y + _turn_off.y) * hold,
		_sway.x * sw * 0.6 + sk * 0.24 + _punch_side * pk * 0.016 - (bob_roll + _lean + _hj.z) * hold)
	vm_pivot.position = Vector3(-bob_x * 0.25 * sw - sk * 0.02, -dip * 0.55 + (_vm_lag - hy - dip) * 0.8 * sw - sk * 0.03, kick * 0.012)
