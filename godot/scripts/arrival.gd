## The arrival: you park, and you WATCH yourself get out, walk to the boot,
## lift the lid, take the camera out and put it on - and the view becomes the
## camera at that moment - then take the rifle. Third person for six stages,
## first person for the last two. Ported from the web build's cutscene, with
## its car-frame framing: ax is lateral (+ right), az runs along the car
## (+ forward), so the boot is at NEGATIVE az.
extends Node

const U := preload("res://scripts/util.gd")

signal finished

const STAGES := [
	{"id": "door",  "dur": 2.3, "tp": true},   # the driver's door swings open, he climbs out
	{"id": "shut",  "dur": 1.4, "tp": true},   # he pushes it shut
	{"id": "walk",  "dur": 2.7, "tp": true},   # down the flank, round to the boot
	{"id": "open",  "dur": 1.7, "tp": true},   # the lid comes up
	{"id": "reach", "dur": 1.6, "tp": true},   # he leans in for the camera
	{"id": "lift",  "dur": 1.3, "tp": true},   # and straightens up holding it
	{"id": "mount", "dur": 1.9, "tp": false},  # onto the head - the view becomes the GoPro here
	{"id": "rifle", "dur": 1.7, "tp": false},  # the rifle out of the boot, the boot shuts
]
const DOOR_SWING := 1.15
const LID_SWING := 1.05

var car: Node3D
var player: CharacterBody3D
var post: ShaderMaterial
var on := false
var t := 0.0
var fp := false
var fired := {}

var cam: Camera3D
var actor: Node3D
var actor_model: Node3D
var actor_anim: AnimationPlayer
var actor_cam_prop: Node3D
var feet: Array = []
var ankle := 0.0
var foot0 := 0.0
var clip := ""
var door: Node3D
var lid: Node3D
var door_rest := 0.0
var lid_rest := 0.0
var kit: Node3D
var kit_rifle: Node3D
var kit_cam: Node3D
var boot_lamp: OmniLight3D
var look_at_s := Vector3.ZERO
var cam_rot_basis: Basis

func begin(c: Node3D, p: CharacterBody3D, pm: ShaderMaterial) -> void:
	car = c
	player = p
	post = pm
	on = true
	t = 0.0
	fp = false
	fired.clear()
	door = car.model.find_child("door_FL", true, false) as Node3D
	lid = car.model.find_child("trunk_lid", true, false) as Node3D
	if door:
		door_rest = door.rotation.y
	if lid:
		lid_rest = lid.rotation.x
	cam = Camera3D.new()
	cam.fov = 62.0
	cam.near = 0.05
	cam.far = 900.0
	cam.cull_mask = 0xFFFFF & ~2
	add_child(cam)
	cam.current = true
	_build_actor()
	_build_kit()
	post.set_shader_parameter("mix_amt", 0.0)   # your own eyes until the camera goes on

func skip() -> void:
	if on:
		t = 999.0

# ------------------------------------------------------------------ setup

func _build_actor() -> void:
	actor = Node3D.new()
	actor.name = "ArrivalActor"
	get_tree().current_scene.add_child(actor)
	var ps: PackedScene = load("res://assets/operator.glb")
	actor_model = ps.instantiate() as Node3D
	actor_model.rotation.y = PI
	actor.add_child(actor_model)
	U.set_shadows(actor_model, true)
	# he walks to the boot to FETCH his camera, so it cannot already be on his helmet
	actor_cam_prop = actor_model.find_child("action_camera", true, false) as Node3D
	if actor_cam_prop:
		actor_cam_prop.visible = false
	# human height, measured
	var a := U.local_aabb(actor_model)
	var s := 1.78 / maxf(0.2, a.size.y)
	actor.scale = Vector3.ONE * s
	foot0 = a.position.y * s
	actor_anim = actor_model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if actor_anim:
		for n in ["idle", "walk", "crouch"]:
			if actor_anim.has_animation(n):
				actor_anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	for n in ["Foot_L", "Foot_R"]:
		var f := actor_model.find_child(n, true, false) as Node3D
		if f:
			feet.append(f)
	# ankle height above the sole, in world units, from the bind pose
	actor.global_position = Vector3(0, 0, 0)
	if not feet.is_empty():
		var lowest := INF
		for f in feet:
			lowest = minf(lowest, (f as Node3D).global_position.y)
		ankle = lowest - foot0
	_clip("idle", 0.0)

func _build_kit() -> void:
	# the rifle lying across the boot floor and the camera on a hard case,
	# located from the lid's own hinge so it survives any change to the model
	kit = Node3D.new()
	kit.name = "BootKit"
	car.add_child(kit)
	var base := Vector3(0, 0.72, 1.98)
	if lid:
		var h := car.to_local(lid.global_position)
		if h.y > 0.4 and h.y < 2.2 and absf(h.z) > 0.8:
			base = Vector3(0, h.y - 0.46, h.z + 0.14)
	kit.position = base
	var src: Node3D = player.guns.get(player.WEAPONS[player.weapon_index].id)
	if src:
		kit_rifle = src.duplicate() as Node3D
		U.set_layers(kit_rifle, 1)
		kit_rifle.visible = true
		kit_rifle.position = Vector3(0.02, 0, 0)
		kit_rifle.rotation = Vector3(0, 1.55, 0.04)
		kit_rifle.scale = Vector3.ONE * 0.8
		kit.add_child(kit_rifle)
	var case_mat := U.flat_mat(Color(0.14, 0.15, 0.17), 0.75)
	var kase := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.30, 0.09, 0.20)
	kase.mesh = bm
	kase.material_override = case_mat
	kase.position = Vector3(-0.34, -0.035, -0.16)
	kit.add_child(kase)
	kit_cam = Node3D.new()
	var body := MeshInstance3D.new()
	var cb := BoxMesh.new()
	cb.size = Vector3(0.075, 0.055, 0.045)
	body.mesh = cb
	body.material_override = case_mat
	kit_cam.add_child(body)
	var lens := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.017
	cm.bottom_radius = 0.017
	cm.height = 0.012
	lens.mesh = cm
	lens.material_override = U.flat_mat(Color(0.05, 0.06, 0.07), 0.35, 0.5)
	lens.rotation.x = PI / 2
	lens.position = Vector3(0, 0.004, 0.026)
	kit_cam.add_child(lens)
	kit_cam.position = Vector3(-0.34, 0.052, -0.16)
	kit_cam.rotation.y = 0.35
	kit.add_child(kit_cam)
	# the boot lamp comes on with the lid, like a real car - and it is what
	# lets you actually read the kit lying in a black boot at night
	boot_lamp = OmniLight3D.new()
	boot_lamp.light_color = Color(1, 0.86, 0.66)
	boot_lamp.light_energy = 0.0
	boot_lamp.omni_range = 1.5
	boot_lamp.position = Vector3(0, 0.38, 0.1)
	kit.add_child(boot_lamp)

func _clip(n: String, blend := 0.3) -> void:
	if actor_anim == null or clip == n or not actor_anim.has_animation(n):
		return
	actor_anim.play(n, blend)
	clip = n

# ------------------------------------------------------------------ car frame

## car-frame point: ax lateral (+right), ay up, az along the car (+forward)
func P(ax: float, ay: float, az: float) -> Vector3:
	return car.to_global(Vector3(ax, ay, -az))

func Dir(ax: float, az: float) -> Vector3:
	return car.global_basis * Vector3(ax, 0, -az)

func _put_actor(ax: float, az: float, dax: float, daz: float) -> void:
	var w := P(ax, 0, az)
	actor.global_position = Vector3(w.x, actor.global_position.y, w.z)
	var d := Dir(dax, daz)
	if d.length() > 0.001:
		actor.rotation.y = atan2(-d.x, -d.z)

# ------------------------------------------------------------------ tick

func _process(dt: float) -> void:
	if not on:
		return
	t += dt
	var acc := 0.0
	var i := 0
	while i < STAGES.size() and t >= acc + STAGES[i].dur:
		acc += STAGES[i].dur
		i += 1
	if i >= STAGES.size():
		_finish()
		return
	var st: Dictionary = STAGES[i]
	var u := clampf((t - acc) / st.dur, 0.0, 1.0)
	var ease := u * u * (3.0 - 2.0 * u)
	var id: String = st.id
	var cam_a := Vector3.ZERO
	var cam_b := Vector3.ZERO
	var door_a := 0.0
	var lid_a := 0.0
	var boot := P(0, 0.95, -2.55)
	var look := Vector3.ZERO
	var has_look := false

	# if time ever lands past the mount without passing through it (a frame
	# spike, a skip), catch the hand-off up rather than leave him in the world
	if not fp and not st.tp:
		_to_first_person()

	match id:
		"door":
			door_a = clampf(u * 2.0, 0.0, 1.0)             # the door leads, he follows
			var k2 := clampf((u - 0.30) / 0.70, 0.0, 1.0)
			var e2 := k2 * k2 * (3.0 - 2.0 * k2)
			_put_actor(lerpf(-0.92, -1.85, e2), lerpf(0.62, 0.30, e2), -1, -0.15)
			_clip("crouch" if u < 0.34 else ("walk" if e2 < 0.92 else "idle"))
			cam_a = Vector3(-4.5, 1.78, 3.2)
			cam_b = Vector3(-3.9, 1.72, 1.5)
		"shut":
			door_a = 1.0 - ease
			_put_actor(-1.95, 0.22, 1, 0.25)
			_clip("idle")
			cam_a = Vector3(-3.9, 1.72, 1.0)
			cam_b = Vector3(-3.7, 1.74, -0.4)
		"walk":
			var way := [Vector2(-1.95, 0.22), Vector2(-1.95, -1.55), Vector2(-1.20, -3.05), Vector2(-0.15, -3.25)]
			var f := ease * (way.size() - 1)
			var seg := mini(way.size() - 2, int(floor(f)))
			var pos: Vector2 = way[seg].lerp(way[seg + 1], f - seg)
			var dl: Vector2 = way[seg + 1] - way[seg]
			_put_actor(pos.x, pos.y, dl.x, dl.y)
			_clip("walk" if ease < 0.94 else "idle", 0.25)
			cam_a = Vector3(-4.1, 1.76, -1.0)
			cam_b = Vector3(-3.0, 1.70, -4.9)
		"open":
			_put_actor(-0.10, -3.15, 0, 1)
			_clip("idle")
			lid_a = ease
			cam_a = Vector3(-2.5, 1.70, -5.5)
			cam_b = Vector3(-1.9, 1.62, -5.0)
		"reach", "lift":
			_put_actor(-0.10, -3.05, 0, 1)
			_clip("crouch" if id == "reach" else "idle", 0.35)
			lid_a = 1.0
			if id == "lift" and u > 0.25 and kit_cam:
				kit_cam.visible = false                        # he has it now
			cam_a = Vector3(-1.7, 1.58, -4.9)
			cam_b = Vector3(-1.15, 1.52, -4.5)
		"mount":
			lid_a = 1.0
			if actor_cam_prop and u > 0.30:
				actor_cam_prop.visible = true                  # it goes on his head
			if not fp and u > 0.55:
				_to_first_person()
			if not fp:
				_put_actor(-0.10, -3.05, 0, 1)
				_clip("idle")
				cam_a = Vector3(-1.05, 1.60, -4.5)
				cam_b = Vector3(-0.75, 1.62, -4.2)
			else:
				_face(boot + Vector3(0, 0.1, 0), dt)
			post.set_shader_parameter("mix_amt", clampf((u - 0.45) / 0.45, 0.0, 1.0))
		"rifle":
			lid_a = 1.0 - clampf((u - 0.62) / 0.38, 0.0, 1.0)   # boot shuts behind you
			if kit_rifle and u > 0.30 and kit_rifle.visible:
				kit_rifle.visible = false                      # it is in your hands now
				player.show_rifle(true)
			_face(boot + Vector3(0, 0.1 + ease * 0.4, 0), dt)
			post.set_shader_parameter("mix_amt", 1.0)

	if st.tp and not fp:
		var a := P(cam_a.x, cam_a.y, cam_a.z)
		var b := P(cam_b.x, cam_b.y, cam_b.z)
		cam.global_position = a.lerp(b, ease)
		var ly := 1.15 if id in ["open", "reach", "lift"] else 1.30
		var tgt := Vector3(actor.global_position.x, ly, actor.global_position.z)
		if look_at_s == Vector3.ZERO:
			look_at_s = tgt
		look_at_s = look_at_s.lerp(tgt, clampf(dt * 7.0, 0.0, 1.0))   # the pan lags a touch
		cam.look_at(look_at_s, Vector3.UP)

	if door:
		door.rotation.y = door_rest - door_a * DOOR_SWING
	if lid:
		lid.rotation.x = lid_rest + lid_a * LID_SWING
	if boot_lamp:
		boot_lamp.light_energy = 1.1 * lid_a

	if not fp and actor.visible:
		_plant_feet()

	# one-shots on stage entry
	if not fired.has(id) and u > 0.02:
		fired[id] = true
		match id:
			"door":
				Game.play("car_seatbelt", -10.0)
				get_tree().create_timer(0.35).timeout.connect(func(): Game.play("car_dooropen", -3.0))
			"shut": Game.play("car_doorclose", -3.0)
			"open":
				Game.play("car_trunkopen", -3.0)
				Game.play("vo_trunk", -2.0)
			"mount":
				Game.play("gear_gopro_on", -2.0)
				Game.play("gear_strap", -4.0)
				Game.play("vo_camera_live", -2.0)
			"rifle":
				Game.play("gun_draw", -2.0)
				get_tree().create_timer(st.dur * 0.62).timeout.connect(func(): Game.play("car_trunkclose", -3.0))

## the walk cycle raises the hips; plant the lower sole on the ground each frame
func _plant_feet() -> void:
	if feet.is_empty():
		actor.global_position.y = -foot0
		return
	var lowest := INF
	for f in feet:
		lowest = minf(lowest, (f as Node3D).global_position.y)
	if is_finite(lowest):
		actor.global_position.y -= (lowest - ankle)

func _to_first_person() -> void:
	fp = true
	actor.visible = false
	var w := P(-0.10, 0, -3.62)
	var boot := P(0, 0.95, -2.55)
	var d := boot - w
	player.place_at(Vector3(w.x, 1.7, w.z), atan2(-d.x, -d.z))
	player.input_locked = true
	player.activate(true)
	player.show_rifle(false)          # still in the boot

## the camera turns to look into the boot, then lifts as the rifle comes up
func _face(target: Vector3, dt: float) -> void:
	var eye: Vector3 = player.camera.global_position
	var d := target - eye
	var want_yaw := atan2(-d.x, -d.z)
	var want_pitch := atan2(d.y, Vector2(d.x, d.z).length())
	player.yaw = lerp_angle(player.yaw, want_yaw, clampf(dt * 5.0, 0.0, 1.0))
	player.pitch = lerpf(player.pitch, want_pitch, clampf(dt * 5.0, 0.0, 1.0))

func _finish() -> void:
	on = false
	if door:
		door.rotation.y = door_rest
	if lid:
		lid.rotation.x = lid_rest
	if kit:
		kit.queue_free()
	if actor:
		actor.queue_free()
	if cam:
		cam.queue_free()
	post.set_shader_parameter("mix_amt", 1.0)
	if not fp:
		_to_first_person()
	player.pitch = 0.0
	player.input_locked = false
	player.show_rifle(true)
	finished.emit()
