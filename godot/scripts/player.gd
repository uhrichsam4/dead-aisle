## First-person operator: movement, look, the rifle and the viewmodel.
## Numbers are the web build's: 4.6 m/s walk, 7.2 sprint, the same bob, the
## same three AK-74 builds and their damage / fire interval / spread.
extends CharacterBody3D

const U := preload("res://scripts/util.gd")

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

func _ready() -> void:
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

func activate(on: bool) -> void:
	active = on
	visible = on
	vm_layer.visible = on
	if on:
		camera.current = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func place_at(p: Vector3, face_yaw: float) -> void:
	global_position = Vector3(p.x, maxf(p.y - EYE, 0.0), p.z)
	yaw = face_yaw
	pitch = 0.0
	velocity = Vector3.ZERO

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

	vm_root = Node3D.new()
	vm_root.position = Vector3(-0.02, -1.34, 0.02)
	vm_root.scale = Vector3.ONE * 0.84
	vm_cam.add_child(vm_root)

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
	flash_mesh = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.22, 0.22)
	flash_mesh.mesh = q
	var fm := U.emissive_mat(Color(1, 0.8, 0.5), 6.0)
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.albedo_color = Color(1, 0.85, 0.6, 0.9)
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	flash_mesh.material_override = fm
	flash_mesh.position = Vector3(0.04, 0.02, -0.42)
	flash_mesh.visible = false
	gun_root.add_child(flash_mesh)

	if hand_r:
		hand_r.add_child(gun_root)
	else:
		vm_cam.add_child(gun_root)
		gun_root.position = Vector3(0.18, -0.2, -0.45)
	U.set_layers(op, 2)
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

# ------------------------------------------------------------------ weapons

func select_weapon(i: int, silent := false) -> void:
	if i < 0 or i >= WEAPONS.size():
		return
	if i != weapon_index and not silent:
		Game.play("gun_draw", -4.0)
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
		fire_cd = 0.25
		try_reload()
		return
	var w: Dictionary = WEAPONS[weapon_index]
	fire_cd = w.interval
	mag -= 1
	ammo_changed.emit(mag, MAG_SIZE, w.name)
	Game.play("gun_shot", -2.0, randf_range(0.96, 1.04))
	recoil += 0.018
	kick = 1.0
	shake = maxf(shake, 0.12)
	flash_light.light_energy = 4.0
	flash_mesh.visible = true
	flash_mesh.rotation.z = randf() * TAU

	var spread: float = w.spread * (0.35 if ads_t > 0.5 else 1.0)
	var from := camera.global_position
	var dir := -camera.global_basis.z
	dir = (dir + camera.global_basis.x * randf_range(-spread, spread) + camera.global_basis.y * randf_range(-spread, spread)).normalized()
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 250.0, 1 | 4)
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
		hit_marker.emit(headshot, killed)
	else:
		_impact(hit.position, hit.normal)

func _impact(pos: Vector3, normal: Vector3) -> void:
	var kind := "concrete"
	if pos.y < 0.2 and absf(pos.x) < 22 and absf(pos.z) < 15:
		kind = "concrete"
	Game.play_at("hit_" + kind, pos, -6.0)
	# a short-lived spark + dust puff
	var p := GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.direction = normal
	pm.spread = 35.0
	pm.initial_velocity_min = 1.5
	pm.initial_velocity_max = 4.0
	pm.gravity = Vector3(0, -9, 0)
	pm.scale_min = 0.02
	pm.scale_max = 0.05
	pm.color = Color(0.75, 0.72, 0.66)
	p.process_material = pm
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 4
	sm.rings = 2
	p.draw_pass_1 = sm
	p.amount = 10
	p.lifetime = 0.5
	p.one_shot = true
	p.explosiveness = 1.0
	get_tree().current_scene.add_child(p)
	p.global_position = pos + normal * 0.02
	p.emitting = true
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)

# ------------------------------------------------------------------ damage

func take_damage(dmg: float, from: Vector3) -> void:
	if not alive or not active:
		return
	hp = maxf(0.0, hp - dmg)
	regen_cd = 4.0
	shake = maxf(shake, 0.35)
	damaged.emit(from)
	hp_changed.emit(hp, max_hp)
	Game.play("pain_hit", -3.0)
	if hp <= 0.0:
		alive = false
		died.emit()

func heal_full() -> void:
	hp = max_hp
	alive = true
	hp_changed.emit(hp, max_hp)

# ------------------------------------------------------------------ loop

func _unhandled_input(e: InputEvent) -> void:
	if not active or not alive:
		return
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var m := e as InputEventMouseMotion
		yaw -= m.relative.x * MOUSE_SENS
		pitch = clampf(pitch - m.relative.y * MOUSE_SENS, -1.45, 1.45)
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
	if alive:
		_move(dt)
		if Input.is_action_pressed("fire") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			_fire()
	_reload_tick(dt)
	if alive and hp < max_hp:
		regen_cd -= dt
		if regen_cd <= 0.0:
			hp = minf(max_hp, hp + 9.0 * dt)
			hp_changed.emit(hp, max_hp)

func _move(dt: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var sprinting := Input.is_action_pressed("sprint") and input.y < -0.1 and ads_t < 0.3
	var spd := SPRINT if sprinting else WALK
	var basis := Basis(Vector3.UP, yaw)
	var wish := basis * Vector3(input.x, 0, input.y) * spd
	var k := clampf(ACCEL * dt, 0.0, 1.0)
	velocity.x = lerpf(velocity.x, wish.x, k)
	velocity.z = lerpf(velocity.z, wish.z, k)
	if is_on_floor():
		if Input.is_action_just_pressed("jump"):
			velocity.y = JUMP
	else:
		velocity.y -= GRAVITY * dt
	move_and_slide()

	var speed := Vector2(velocity.x, velocity.z).length()
	bob_t += dt * (11.0 if sprinting else 8.0) * (speed / spd if speed > 0.5 else 0.0)
	# footsteps on the stride, surface by where you are
	stride += speed * dt
	if stride > (1.9 if sprinting else 1.6) and is_on_floor():
		stride = 0.0
		var p := global_position
		var inside := absf(p.x) < 22.0 and absf(p.z) < 15.0
		var surf := "tile" if inside else ("grass" if p.z > 31.9 and p.z < 60.0 and absf(p.z - 36.0) > 4.0 else "concrete")
		Game.play(("sprint_" if sprinting and surf != "grass" else "step_") + surf, -9.0)
	if speed > 0.5:
		_play("run" if sprinting else "walk", 0.25)
	elif not reloading:
		_play("aim", 0.25)

func _process(dt: float) -> void:
	if not active:
		return
	var aiming := Input.is_action_pressed("aim") and alive and not reloading
	ads_t = move_toward(ads_t, 1.0 if aiming else 0.0, dt * 6.0)
	recoil = lerpf(recoil, 0.0, clampf(dt * 10.0, 0.0, 1.0))
	kick = lerpf(kick, 0.0, clampf(dt * 14.0, 0.0, 1.0))
	shake = maxf(0.0, shake - dt * 2.4)
	flash_light.light_energy = lerpf(flash_light.light_energy, 0.0, clampf(dt * 30.0, 0.0, 1.0))
	if flash_light.light_energy < 1.0:
		flash_mesh.visible = false

	var speed := Vector2(velocity.x, velocity.z).length()
	var spd := SPRINT if speed > WALK + 0.3 else WALK
	var bl := 1.0 - ads_t * 0.8
	var bob_y := sin(bob_t * 2.0) * 0.035 * (speed / spd) * bl
	var bob_x := cos(bob_t) * 0.025 * (speed / spd) * bl
	rotation.y = 0.0
	camera.rotation = Vector3(pitch + recoil, yaw, 0.0)
	camera.position = Vector3(bob_x * cos(yaw), EYE + bob_y, -bob_x * sin(yaw))
	if shake > 0.0:
		camera.position += Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * shake * 0.05
	if not alive:
		camera.rotation.z = lerpf(camera.rotation.z, 0.35, dt * 2.0)
		camera.position.y = lerpf(camera.position.y, 0.6, dt * 2.0)
	camera.fov = lerpf(fov_base, fov_base * 0.66, ads_t)
	# the viewmodel camera rides the main one
	vm_cam.global_transform = camera.global_transform
	vm_cam.fov = lerpf(52.0, 38.0, ads_t)
	vm_root.position = Vector3(-0.02 - ads_t * 0.05, -1.34 + ads_t * 0.035, 0.02 + kick * 0.04)
