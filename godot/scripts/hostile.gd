## A hostile: the web build's rigged walker, chasing on the navmesh, biting
## at arm's length, dying on its own clip. HP and speed scale with the wave
## exactly as spawnZombie did.
extends CharacterBody3D

const U := preload("res://scripts/util.gd")

signal killed(h: Node)

var hp := 100.0
var max_hp := 100.0
var speed := 1.4
var state := "idle"          # idle | chase | attack | dead
var target: Node3D
var attack_cd := 0.0
var dead_t := 0.0
var model: Node3D
var anim: AnimationPlayer
var agent: NavigationAgent3D
var head_y := 1.5
# the web's variants (applyVariant): walker, brute, crawler, screamer
var variant := "walker"
var _base_scale := Vector3.ONE
var _base_y := 0.0
var _base_head := 1.5
var _scream_t := 2.0
# the web's LOT CROWD and FLEEING ZOMBIE BEHAVIOR
var flee := false            # a runner: bolts about screaming, never attacks
var lot := false             # claimed by the dormant crowd in the lot
var lot_box := AABB(Vector3(-23, 0, 16), Vector3(46, 4, 13.5))
var car_ref: Node3D
var _flee_to := Vector3.INF
var _flee_scr := 0.0
var _sc_t := 0.0
var _sc_dir := Vector3.ZERO
var _sc_spd := 0.0
var _sc_scr := 0.0
var _wander := 0.0
var _wr := 0.0
# ragdoll: real physics bones on the skeleton, built the first time it dies
var skel: Skeleton3D
var rag_boost := 1.0         # a car hit throws them harder
const RAG_BONES := [
	# bone, the descendant the segment runs to, radius as a share of half-length, mass
	["root", "spine04", 0.9, 9.0],
	["spine04", "spine02", 0.8, 8.0],
	["spine02", "neck01", 0.65, 8.0],
	["neck01", "head", 0.5, 2.0],
	["head", "", 0.0, 4.0],
	["upperarm01_L", "lowerarm01_L", 0.3, 2.5],
	["lowerarm01_L", "wrist_L", 0.25, 1.8],
	["upperarm01_R", "lowerarm01_R", 0.3, 2.5],
	["lowerarm01_R", "wrist_R", 0.25, 1.8],
	["upperleg01_L", "lowerleg01_L", 0.3, 6.0],
	["lowerleg01_L", "foot_L", 0.25, 4.0],
	["upperleg01_R", "lowerleg01_R", 0.3, 6.0],
	["lowerleg01_R", "foot_R", 0.25, 4.0],
]
var _anim_now := ""
var _groan_cd := 0.0
# audio: one voice per person for their whole life, as the web build did
var voice: AudioStreamPlayer3D
var voice_idx := 1
var seen_player := false
var _step_t := 0.0

func _ready() -> void:
	add_to_group("hostiles")
	collision_layer = 4
	collision_mask = 1 | 4
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.75
	cs.shape = cap
	cs.position.y = 0.875
	add_child(cs)
	var lib := U.glb("res://assets/hostile.glb")
	if lib:
		model = lib.duplicate() as Node3D
		add_child(model)
		_fit_height(1.78)
		var sks := model.find_children("*", "Skeleton3D", true, false)
		if not sks.is_empty():
			skel = sks[0] as Skeleton3D
		_base_scale = model.scale
		_base_y = model.position.y
		_base_head = head_y
		anim = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if anim:
			for n in ["idle", "run"]:
				if anim.has_animation(n):
					anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).extra_cull_margin = 1.5   # skinned bounds are bind-pose
	voice = AudioStreamPlayer3D.new()
	voice.unit_size = 4.0
	voice.max_distance = 22.0          # past ~20 m they are silent
	voice.position.y = 1.55
	add_child(voice)
	agent = NavigationAgent3D.new()
	agent.path_desired_distance = 0.9     # the navmesh sits ~0.5 m up; 3D distance
	agent.target_desired_distance = 1.0
	agent.radius = 0.4
	agent.height = 1.8
	add_child(agent)
	despawn()

## Scale to a real human height by the SKELETON, not the mesh bounds. This
## rig's armature carries a 0.1 scale over bones authored in 10x units, and a
## skinned mesh renders through its bones - so the mesh AABB read 0.2 m and the
## first cut scaled every hostile up 8.9x into a 15 m giant.
func _fit_height(target: float) -> void:
	model.scale = Vector3.ONE
	var skels := model.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		return
	var sk := skels[0] as Skeleton3D
	var to_model := model.global_transform.affine_inverse() * sk.global_transform
	var lo := INF
	var hi := -INF
	for b in sk.get_bone_count():
		var y := (to_model * sk.get_bone_global_rest(b)).origin.y
		lo = minf(lo, y)
		hi = maxf(hi, y)
	var span := hi - lo
	if span <= 0.01:
		return
	# foot bone to head bone is roughly 0.88 of standing height
	var s := target * 0.88 / span
	model.scale = Vector3.ONE * s
	model.position.y = -lo * s + 0.06
	head_y = (hi * s + model.position.y) - 0.28

func _play(n: String, blend := 0.2, rate := 1.0) -> void:
	if anim == null or not anim.has_animation(n):
		return
	if _anim_now != n:
		anim.play(n, blend, rate)
		_anim_now = n
	else:
		anim.speed_scale = rate

func spawn(pos: Vector3, wave: int, tgt: Node3D) -> void:
	global_position = pos
	target = tgt
	max_hp = 55.0 + wave * 14.0
	hp = max_hp
	var runner := wave >= 4 and randf() < minf(0.08 * wave, 0.45)
	speed = randf_range(2.3, 3.0) if runner else randf_range(1.05, 1.7) + wave * 0.03
	_roll_variant(wave)
	state = "chase"
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT
	voice_idx = randi_range(1, 7)
	seen_player = false
	_groan_cd = randf_range(1.5, 6.0)
	collision_layer = 4
	rotation.y = randf() * TAU
	_anim_now = ""
	_play("run", 0.0, speed / 1.6)

## weighted by wave, as the web rolled them: brutes from wave 2, screamers
## from wave 3, crawlers any time
func _roll_variant(wave: int) -> void:
	var w := maxi(1, wave)
	var pb := minf(0.16, 0.08 + (w - 2) * 0.015) if w >= 2 else 0.0
	var pc := 0.12
	var ps := 0.10 if w >= 3 else 0.0
	var r := randf()
	variant = "brute" if r < pb else ("crawler" if r < pb + pc else ("screamer" if r < pb + pc + ps else "walker"))
	if model:
		model.scale = _base_scale
		model.position.y = _base_y
	head_y = _base_head
	match variant:
		"brute":          # big, slow, soaks a magazine
			max_hp *= 2.4
			speed *= 0.75
			if model:
				model.scale = _base_scale * 1.25
				model.position.y = _base_y * 1.25
			head_y = _base_head * 1.25
		"crawler":        # low and quick, dies easily
			max_hp *= 0.5
			speed *= 1.15
			if model:
				model.scale.y = _base_scale.y * 0.76
				model.position.y = _base_y * 0.76
			head_y = _base_head * 0.76
		"screamer":       # fast, and shrieks as it comes
			max_hp *= 0.75
			speed *= 1.9
			_scream_t = randf_range(1.0, 3.0)
	hp = max_hp

## their own shout (the voice they were given), a reaction line, or a scream
func _say(file: String, vol_db := 0.0, pitch := 1.0) -> void:
	var st := Game.file(file)
	if st == null or not visible:
		return
	voice.stream = st
	voice.volume_db = vol_db
	voice.pitch_scale = pitch
	voice.play()

## lotCrowdInit: one of the onlookers standing about the lot before you
## arrive - an 80 HP walker at the round's strength, idling, watching the car
func lot_idle(pos: Vector3, tgt: Node3D, car_node: Node3D, box: AABB, rnd: int) -> void:
	spawn(pos, 3, tgt)
	state = "lotidle"
	lot = true
	flee = false
	variant = "walker"
	if model:
		model.scale = _base_scale * randf_range(0.93, 1.07)
		model.position.y = _base_y
	head_y = _base_head
	var r := rnd - 1
	max_hp = 80.0 * (1.0 + r * 0.22)
	hp = max_hp
	speed = randf_range(0.9, 1.5) * (1.0 + r * 0.09)
	car_ref = car_node
	lot_box = box
	_wander = randf() * TAU
	_wr = randf_range(-0.45, 0.45)
	_sc_t = 0.0
	_anim_now = ""
	_play("idle", 0.3)

## lotCrowdScatter: the car pulls in and they panic away from it for 2.2 s
func scatter_from(p: Vector3) -> void:
	if state != "lotidle":
		return
	var d := global_position - p
	d.y = 0.0
	d = d.normalized() + Vector3(randf_range(-0.3, 0.3), 0, randf_range(-0.3, 0.3))
	_sc_dir = d.normalized()
	_sc_spd = randf_range(3.4, 4.8)
	_sc_t = 2.2
	_sc_scr = randf_range(0.0, 0.3)

## the crowd wakes: two in five run, the rest come for you
func wake() -> void:
	if state != "lotidle":
		return
	state = "chase"
	flee = randf() < 0.4
	attack_cd = randf_range(0.2, 0.9)
	seen_player = true
	_flee_to = Vector3.INF
	if not flee and Game.may_react(0.3):
		_say("hostile-v%d.mp3" % randi_range(1, 6), -1.0, randf_range(0.95, 1.05))   # "I see him"

func _lot_step(dt: float) -> void:
	velocity = Vector3.ZERO
	if _sc_t > 0.0:
		_sc_t -= dt
		_play("run", 0.15, 1.6)
		var p := global_position + _sc_dir * _sc_spd * dt
		p.x = clampf(p.x, lot_box.position.x, lot_box.end.x)
		p.z = clampf(p.z, lot_box.position.z, lot_box.end.z)
		global_position = Vector3(p.x, global_position.y, p.z)
		rotation.y = lerp_angle(rotation.y, atan2(_sc_dir.x, _sc_dir.z), clampf(dt * 9.0, 0.0, 1.0))
		_sc_scr -= dt
		if _sc_scr <= 0.0:
			_sc_scr = randf_range(0.7, 1.6)
			if Game.may_shout(0.25):
				_say("sfx-enemy-scream.mp3", -6.0, randf_range(0.95, 1.12))
		return
	# standing about: the player if close, otherwise the car, with a slow sway
	_play("idle", 0.3)
	var look: Vector3 = target.global_position if target else global_position
	if target and global_position.distance_to(target.global_position) >= 13.0 and car_ref:
		look = car_ref.global_position
	_wander += _wr * dt
	var want := atan2(look.x - global_position.x, look.z - global_position.z) + sin(_wander) * 0.55
	rotation.y = lerp_angle(rotation.y, want, clampf(dt * 1.6, 0.0, 1.0))

## a runner: away from you to a spot eight metres off, a new one when it
## gets there, screaming now and then; never attacks
func _flee_step(dt: float) -> void:
	var pp: Vector3 = target.global_position
	if _flee_to == Vector3.INF or Vector2(_flee_to.x - global_position.x, _flee_to.z - global_position.z).length() < 0.8:
		var away := global_position - pp
		away.y = 0.0
		away = away.normalized() if away.length() > 0.01 else Vector3.FORWARD
		_flee_to = pp + away * 8.0 + Vector3(randf_range(-2.5, 2.5), 0, randf_range(-2.5, 2.5))
		_flee_to.x = clampf(_flee_to.x, lot_box.position.x + 0.5, lot_box.end.x - 0.5)
		_flee_to.z = clampf(_flee_to.z, lot_box.position.z + 0.5, lot_box.end.z - 0.5)
		_flee_scr = randf_range(0.5, 2.0)
	_flee_scr -= dt
	if _flee_scr <= 0.0:
		_flee_scr = randf_range(2.5, 6.0)
		if Game.may_shout(0.3):
			_say("sfx-enemy-scream.mp3", -3.0, randf_range(0.95, 1.1))
	var d := _flee_to - global_position
	d.y = 0.0
	var dir := d.normalized() if d.length() > 0.01 else Vector3.ZERO
	for o in get_tree().get_nodes_in_group("hostiles"):
		if o == self or not o.is_active():
			continue
		var off: Vector3 = global_position - (o as Node3D).global_position
		off.y = 0.0
		var od := off.length()
		if od < 0.7 and od > 0.001:
			dir += off / od * 0.9 * dt
	velocity.x = dir.x * speed * 1.4
	velocity.z = dir.z * speed * 1.4
	velocity.y = velocity.y - 18.0 * dt if not is_on_floor() else 0.0
	move_and_slide()
	if dir.length() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), clampf(dt * 7.0, 0.0, 1.0))
	_play("run", 0.2, clampf(speed * 1.4 / 1.6, 0.6, 2.2))

## A ragdoll that does not care about the rig's scale. Godot's physical
## bones inherit the skeleton transform, and this armature carries a 0.1
## scale, so the body came out ten times its size. Instead: world-space
## capsules on the segments, cone-twist joints between them, and every
## physics frame the bones are posed from the bodies with the scale stripped.
var _rag: Array = []          # [bone index, RigidBody3D, body->bone transform]
var _rag_joints: Array = []

func _ragdoll(dir: Vector3, at: Vector3) -> bool:
	if skel == null:
		return false
	_rag_clear()
	var sg := skel.global_transform
	var by_bone := {}
	for e in RAG_BONES:
		var bi := skel.find_bone(e[0])
		if bi < 0:
			continue
		var bone_w: Transform3D = sg * skel.get_bone_global_pose(bi)
		bone_w.basis = bone_w.basis.orthonormalized()
		var a: Vector3 = bone_w.origin
		var b: Vector3
		if e[1] != "":
			var ci := skel.find_bone(e[1])
			if ci < 0:
				continue
			b = (sg * skel.get_bone_global_pose(ci)).origin
		else:
			var ni := skel.find_bone("neck01")
			var nd: Vector3 = (a - (sg * skel.get_bone_global_pose(ni)).origin).normalized() if ni >= 0 else Vector3.UP
			b = a + nd * 0.22
		var seg := b - a
		var ln := seg.length()
		if ln < 0.02:
			continue
		var rb := RigidBody3D.new()
		rb.name = "rag_" + str(e[0])
		rb.mass = e[3]
		rb.linear_damp = 0.25
		rb.angular_damp = 1.4
		rb.continuous_cd = true
		rb.collision_layer = 64          # bodies meet the world, not each other
		rb.collision_mask = 1
		var pm := PhysicsMaterial.new()
		pm.friction = 0.9
		pm.bounce = 0.05
		rb.physics_material_override = pm
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		var rf: float = e[2] if e[2] > 0.0 else 0.55
		cap.radius = clampf(ln * 0.5 * rf, 0.035, 0.2)
		cap.height = maxf(ln, cap.radius * 2.0 + 0.001)
		cs.shape = cap
		rb.add_child(cs)
		get_tree().current_scene.add_child(rb)
		# the capsule's axis (Y) along the segment, centred on it
		var yax := seg / ln
		var ref := Vector3.FORWARD if absf(yax.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
		var xax := ref.cross(yax).normalized()
		var zax := xax.cross(yax).normalized()
		rb.global_transform = Transform3D(Basis(xax, yax, zax), (a + b) * 0.5)
		_rag.append([bi, rb, rb.global_transform.affine_inverse() * bone_w])
		by_bone[bi] = rb
	# joints: each body to the nearest ancestor that has one, at the joint
	for r in _rag:
		var bi: int = r[0]
		var p := skel.get_bone_parent(bi)
		while p >= 0 and not by_bone.has(p):
			p = skel.get_bone_parent(p)
		if p < 0:
			continue
		var j := ConeTwistJoint3D.new()
		get_tree().current_scene.add_child(j)
		j.global_position = (sg * skel.get_bone_global_pose(bi)).origin
		j.node_a = (by_bone[p] as Node).get_path()
		j.node_b = (r[1] as Node).get_path()
		j.set_param(ConeTwistJoint3D.PARAM_SWING_SPAN, deg_to_rad(50.0))
		j.set_param(ConeTwistJoint3D.PARAM_TWIST_SPAN, deg_to_rad(25.0))
		_rag_joints.append(j)
	if _rag.is_empty():
		return false
	if anim:
		anim.active = false
	# the round (or the car) shoves it along the way it was going, the part
	# that was hit hardest
	var flat := Vector3(dir.x, 0, dir.z)
	flat = flat.normalized() if flat.length() > 0.001 else -global_basis.z
	var push := flat * 2.2 * rag_boost + Vector3.UP * (0.6 + 0.9 * (rag_boost - 1.0))
	var nearest: RigidBody3D = null
	var best := INF
	for r in _rag:
		var rb: RigidBody3D = r[1]
		rb.apply_central_impulse(push * rb.mass)
		var d := rb.global_position.distance_to(at)
		if d < best:
			best = d
			nearest = rb
	if nearest:
		nearest.apply_central_impulse(push * nearest.mass * 2.5)
	return true

## pose the bones from the bodies, parents first, scale stripped
func _rag_pose() -> void:
	var inv := skel.global_transform.affine_inverse()
	for r in _rag:
		var rb: RigidBody3D = r[1]
		var pose: Transform3D = inv * (rb.global_transform * (r[2] as Transform3D))
		pose.basis = pose.basis.orthonormalized()
		skel.set_bone_global_pose(r[0], pose)

func _rag_clear() -> void:
	for j in _rag_joints:
		if is_instance_valid(j):
			j.queue_free()
	for r in _rag:
		if is_instance_valid(r[1]):
			(r[1] as Node).queue_free()
	_rag.clear()
	_rag_joints.clear()

func despawn() -> void:
	_rag_clear()
	if skel:
		skel.reset_bone_poses()
	if anim:
		anim.active = true
	rag_boost = 1.0
	lot = false
	flee = false
	state = "idle"
	visible = false
	collision_layer = 0
	velocity = Vector3.ZERO
	global_position = Vector3(0, -50, 0)
	process_mode = Node.PROCESS_MODE_DISABLED

func is_active() -> bool:
	return state == "chase" or state == "attack"

func is_head(p: Vector3) -> bool:
	return p.y - global_position.y > head_y

## returns true if this hit killed it
func take_hit(dmg: float, at: Vector3, dir: Vector3) -> bool:
	if state == "dead" or state == "idle":
		return false
	hp -= dmg
	# a wet thud where the round lands, and they yell - gated, so a volley
	# into a crowd is not eight people shouting at once
	Game.play_file_at("sfx-body-drop.mp3", at, -14.0, randf_range(1.6, 1.9), 25.0)
	if hp > 0.0 and Game.may_react():
		_say("hostile-v%d.mp3" % randi_range(1, 6), -2.0, randf_range(0.95, 1.05))
	_blood(at, dir)
	if hp <= 0.0:
		state = "dead"
		dead_t = 0.0
		collision_layer = 0
		velocity = Vector3.ZERO
		if not _ragdoll(dir, at):
			_play("death", 0.1)
		if randf() < 0.6:
			_say("kill-voice.mp3", -4.0, randf_range(0.85, 1.1))
		# the body hits the floor as the death clip lands
		get_tree().create_timer(0.55).timeout.connect(func():
			if visible: Game.play_file_at("sfx-body-drop.mp3", global_position + Vector3(0, 0.3, 0), -3.0, randf_range(0.9, 1.05), 30.0))
		killed.emit(self)
		return true
	# a hit staggers it back a touch
	global_position += Vector3(dir.x, 0, dir.z) * 0.08
	return false

func _blood(at: Vector3, dir: Vector3) -> void:
	var p := GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.direction = dir
	pm.spread = 30.0
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 3.5
	pm.gravity = Vector3(0, -9, 0)
	pm.scale_min = 0.025
	pm.scale_max = 0.06
	pm.color = Color(0.45, 0.02, 0.02)
	p.process_material = pm
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 4
	sm.rings = 2
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.02, 0.02)
	mat.vertex_color_use_as_albedo = true
	sm.material = mat
	p.draw_pass_1 = sm
	p.amount = 14
	p.lifetime = 0.6
	p.one_shot = true
	p.explosiveness = 1.0
	get_tree().current_scene.add_child(p)
	p.global_position = at
	p.emitting = true
	get_tree().create_timer(1.2).timeout.connect(p.queue_free)

func _physics_process(dt: float) -> void:
	if state == "dead":
		dead_t += dt
		if not _rag.is_empty():
			_rag_pose()
		if dead_t > 8.0:
			despawn()
		return
	if state == "idle" or target == null:
		return
	if state == "lotidle":
		_lot_step(dt)
		return
	if flee:
		_flee_step(dt)
		return
	attack_cd = maxf(0.0, attack_cd - dt)
	_groan_cd -= dt
	if variant == "screamer":
		_scream_t -= dt
		if _scream_t <= 0.0:
			_scream_t = randf_range(2.5, 5.5)
			if target.global_position.distance_to(global_position) < 15.0 and Game.may_shout(0.4):
				_say("sfx-enemy-scream.mp3", -1.0, randf_range(0.95, 1.08))
	var to := target.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	# the first time they clock you they scream, then they shout as they come
	if not seen_player and dist < 18.0:
		seen_player = true
		if Game.may_react(0.4):
			_say("sfx-enemy-scream.mp3" if randf() < 0.45 else "hostile-v%d.mp3" % randi_range(1, 6), -1.0, randf_range(0.92, 1.06))
	elif _groan_cd <= 0.0:
		_groan_cd = randf_range(3.5, 8.0)
		if dist < 20.0 and Game.may_shout():
			_say("hostile-%d.mp3" % voice_idx, -3.0, randf_range(0.96, 1.04))
	if dist < 1.35:
		state = "attack"
		velocity.x = 0.0
		velocity.z = 0.0
		_play("attack", 0.15)
		if attack_cd <= 0.0:
			attack_cd = 1.1
			if Game.may_shout(0.3):
				_say("hostile-%d.mp3" % voice_idx, 0.0, randf_range(1.0, 1.1))
			if target.has_method("take_damage"):
				target.call("take_damage", 18.0, global_position)
	else:
		state = "chase"
		var next := target.global_position
		agent.target_position = target.global_position
		if not agent.is_navigation_finished():
			var np := agent.get_next_path_position()
			if Vector2(np.x - global_position.x, np.z - global_position.z).length() > 0.05:
				next = np
		var d := next - global_position
		d.y = 0.0
		d = d.normalized() if d.length() > 0.01 else to.normalized()
		velocity.x = d.x * speed
		velocity.z = d.z * speed
		_play("run", 0.2, clampf(speed / 1.6, 0.6, 2.0))
		# their feet, quiet, and only when close enough to matter
		_step_t -= dt * speed
		if _step_t <= 0.0:
			_step_t = 0.75
			if dist < 12.0:
				var inside := absf(global_position.x) < 22.0 and absf(global_position.z) < 15.0
				Game.play_at("step_tile" if inside else "step_concrete", global_position, -20.0, randf_range(0.85, 0.95))
	if not is_on_floor():
		velocity.y -= 18.0 * dt
	else:
		velocity.y = 0.0
	move_and_slide()
	if to.length() > 0.01:
		var want := atan2(to.x, to.z)
		rotation.y = lerp_angle(rotation.y, want, clampf(dt * 8.0, 0.0, 1.0))
