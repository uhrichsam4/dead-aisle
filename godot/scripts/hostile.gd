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

func despawn() -> void:
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
		if dead_t > 8.0:
			despawn()
		return
	if state == "idle" or target == null:
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
