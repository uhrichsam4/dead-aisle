## A survivor: hiding in a corner of the store until you reach them, then
## following you out. The web build drew these as block figures; here they are
## real people (the civilian rig, recoloured) with a green marker overhead so
## you do not mistake them for a hostile in the dark.
extends CharacterBody3D

const U := preload("res://scripts/util.gd")
const H := preload("res://scripts/hostile.gd")

signal found(s: Node)

# the supplied rig's planted foot speeds at 1x, in model units/s (measured
# off the Walk and Sprint stance frames); gait rates come from these
const WALK_V := 1.0
const SPRINT_V := 6.5
const P_IDLE := &"parameters/its/scale"
const P_WALK := &"parameters/ws/scale"
const P_SPRINT := &"parameters/ss/scale"
const P_GAIT := &"parameters/gait/blend_amount"
const P_MOVE := &"parameters/move/blend_amount"
var tree: AnimationTree
var lean: H.Lean
var _walk_len := 1.333
var _sprint_len := 0.667
var _last_pos := Vector3.ZERO
var _spd := 0.0
var _amp := 0.0
var _yaw_vel := 0.0
var _ph := 0.0               # their own rhythm for the nervous sway
var _near_p := Vector3.INF   # the nearest live hostile while hiding
var _look := 0.0
var _hunch := 0.0

var state := "hiding"        # hiding | following | out
var model_path := ""         # a rigged survivor model (set by main before adding)
var _clips := {}             # our names (idle/walk/run) -> the model's clip names
var target: Node3D
var home := Vector3.ZERO
var model: Node3D
var anim: AnimationPlayer
var marker: MeshInstance3D
var voice: AudioStreamPlayer3D
var agent: NavigationAgent3D
var fear := 0.25
var _whimper_cd := 3.0
var _anim_now := ""
var _stuck_t := 0.0
var _best_d := INF
var _t := 0.0

func _ready() -> void:
	collision_layer = 16
	collision_mask = 1
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.7
	cs.shape = cap
	cs.position.y = 0.85
	add_child(cs)
	if model_path != "" and ResourceLoader.exists(model_path):
		# one of the supplied rigged people, on its own Idle / Walk / Sprint
		var ps: PackedScene = load(model_path)
		model = ps.instantiate() as Node3D
		add_child(model)
		U.fix_materials(model, true)
		anim = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if anim:
			for n in anim.get_animation_list():
				var l := str(n).to_lower()
				if l == "idle" and not _clips.has("idle"):
					_clips.idle = n
				elif l == "walk" and not _clips.has("walk"):
					_clips.walk = n
				elif (l == "sprint" or l == "run") and not _clips.has("run"):
					_clips.run = n
			for k in _clips:
				anim.get_animation(_clips[k]).loop_mode = Animation.LOOP_LINEAR
		# measured in an animated pose: this rig's rest pose is not its bind
		# pose (it measures 11 cm), and its mesh bounds carry a 0.01 scale
		_fit_posed(1.72)
		# the same model four times over: at least not the same height
		var j := randf_range(0.95, 1.05)
		model.scale *= j
		model.position.y *= j
		_build_tree()
	else:
		var lib := U.glb("res://assets/hostile.glb")
		if lib:
			model = lib.duplicate() as Node3D
			add_child(model)
			_fit(1.72)
			_civilian_look()
			anim = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if model:
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).extra_cull_margin = 1.5
	marker = MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.1
	cone.bottom_radius = 0.0
	cone.height = 0.18
	cone.radial_segments = 4
	marker.mesh = cone
	marker.material_override = U.emissive_mat(Color(0.27, 1.0, 0.4), 2.5)
	marker.position.y = 2.15
	add_child(marker)
	# they follow you round the gondolas and through doorways on the navmesh,
	# the same as the hostiles; straight-line following left people stuck
	# behind shelving, and the doors will not let you out without them
	agent = NavigationAgent3D.new()
	# the baked surface sits up to half a metre over the floor, and these are
	# 3D distances: at 0.5 a waypoint could never count as reached
	agent.path_desired_distance = 1.0
	agent.target_desired_distance = 1.2
	agent.radius = 0.35
	agent.height = 1.7
	add_child(agent)
	voice = AudioStreamPlayer3D.new()
	voice.position.y = 1.5
	voice.unit_size = 3.0
	voice.max_distance = 16.0
	add_child(voice)

## Idle, and a gait blended from Walk to Sprint by speed. Both gait clips run
## at the same share of their cycle per second, so the feet stay in step
## through the blend (both start on the same planted foot), and the rate is
## set so the planted foot keeps pace with the ground.
func _build_tree() -> void:
	if anim == null or not (_clips.has("idle") and _clips.has("walk") and _clips.has("run")):
		return
	_walk_len = anim.get_animation(_clips.walk).length
	_sprint_len = anim.get_animation(_clips.run).length
	var bt := AnimationNodeBlendTree.new()
	for k in ["idle", "walk", "run"]:
		var a := AnimationNodeAnimation.new()
		a.animation = StringName(_clips[k])
		bt.add_node(StringName("a_" + k), a)
	bt.add_node(&"its", AnimationNodeTimeScale.new())
	bt.add_node(&"ws", AnimationNodeTimeScale.new())
	bt.add_node(&"ss", AnimationNodeTimeScale.new())
	var gait := AnimationNodeBlend2.new()
	gait.set_use_sync(true)
	bt.add_node(&"gait", gait)
	var mv := AnimationNodeBlend2.new()
	mv.set_use_sync(true)
	bt.add_node(&"move", mv)
	bt.connect_node(&"its", 0, &"a_idle")
	bt.connect_node(&"ws", 0, &"a_walk")
	bt.connect_node(&"ss", 0, &"a_run")
	bt.connect_node(&"gait", 0, &"ws")
	bt.connect_node(&"gait", 1, &"ss")
	bt.connect_node(&"move", 0, &"its")
	bt.connect_node(&"move", 1, &"gait")
	bt.connect_node(&"output", 0, &"move")
	anim.stop()
	tree = AnimationTree.new()
	anim.get_parent().add_child(tree)
	tree.anim_player = tree.get_path_to(anim)
	tree.root_node = tree.get_path_to(anim.get_node(anim.root_node))
	tree.tree_root = bt
	tree.active = true
	var sks := model.find_children("*", "Skeleton3D", true, false)
	if not sks.is_empty():
		lean = H.Lean.new()
		(sks[0] as Skeleton3D).add_child(lean)
		lean.setup(sks[0], model, ["mixamorigSpine", "mixamorigSpine2", "mixamorigNeck", "mixamorigHead"], [0.35, 0.35, 0.2, 0.1], [0.0, 0.15, 0.35, 0.5])
	_ph = randf() * TAU

## pace the tree off the distance actually covered this frame; `turning`
## shuffles the feet when they swing round on the spot
func _gait(dt: float) -> void:
	var mv := global_position - _last_pos
	_last_pos = global_position
	mv.y = 0.0
	var v := mv.length() / maxf(dt, 0.0001)
	if v > 10.0:
		v = 0.0                      # the catch-up teleport is not a step
	_spd = lerpf(_spd, v, clampf(dt * 10.0, 0.0, 1.0))
	if tree == null:
		return
	var sc := maxf(model.scale.x, 0.001)
	var vm := _spd / sc
	var w := clampf((vm - 1.2) / 5.8, 0.0, 1.0)
	var d_cyc := lerpf(WALK_V * _walk_len, SPRINT_V * _sprint_len, w)
	var a := 0.0 if _spd < 0.06 else clampf(_spd / 0.6, 0.35, 1.0)
	var cyc := vm / maxf(d_cyc * maxf(a, 0.05), 0.01)
	# turning on the spot: short steps round
	if _spd < 0.3 and absf(_yaw_vel) > 0.5:
		a = maxf(a, clampf(absf(_yaw_vel) * 0.12, 0.0, 0.3))
		cyc = maxf(cyc, 0.75 / _walk_len)
		w = 0.0
	_amp = lerpf(_amp, a, clampf(dt * 7.0, 0.0, 1.0))
	cyc = minf(cyc, 2.4 / _walk_len)
	tree.set(P_MOVE, _amp)
	tree.set(P_GAIT, w)
	tree.set(P_WALK, cyc * _walk_len)
	tree.set(P_SPRINT, cyc * _sprint_len)

## rate-limited, eased turning (no snapping round)
func _turn_to(want: float, dt: float) -> void:
	var diff := wrapf(want - rotation.y, -PI, PI)
	var step := clampf(diff * clampf(dt * 7.0, 0.0, 1.0), -5.0 * dt, 5.0 * dt)
	rotation.y = wrapf(rotation.y + step, -PI, PI)
	_yaw_vel = lerpf(_yaw_vel, step / maxf(dt, 0.0001), clampf(dt * 8.0, 0.0, 1.0))

func _fit_posed(target_h: float) -> void:
	var skels := model.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty() or anim == null:
		return
	var sk := skels[0] as Skeleton3D
	anim.play(_clips.get("idle", anim.get_animation_list()[0]))
	anim.advance(0.0)
	model.scale = Vector3.ONE
	model.position = Vector3.ZERO
	var to_model := model.global_transform.affine_inverse() * sk.global_transform
	var lo := INF
	var hi := -INF
	for b in sk.get_bone_count():
		var y := (to_model * sk.get_bone_global_pose(b)).origin.y
		lo = minf(lo, y)
		hi = maxf(hi, y)
	if hi - lo <= 0.01:
		return
	var s := target_h * 0.9 / (hi - lo)
	model.scale = Vector3.ONE * s
	model.position.y = -lo * s + 0.03

func _fit(target_h: float) -> void:
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
	if hi - lo <= 0.01:
		return
	var s := target_h * 0.88 / (hi - lo)
	model.scale = Vector3.ONE * s
	model.position.y = -lo * s + 0.06

## same person as a hostile underneath, so dress them differently: a lighter
## shirt and a warmer skin, never the hostiles' black suit
func _civilian_look() -> void:
	# work shirts and hi-vis: staff and shoppers, never the hostiles' black
	var shirts := [Color(0.85, 0.72, 0.36), Color(0.36, 0.52, 0.78), Color(0.78, 0.36, 0.3), Color(0.9, 0.85, 0.2)]
	var shirt: Color = shirts[randi() % shirts.size()]
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i)
			if m is StandardMaterial3D:
				var c := (m as StandardMaterial3D).duplicate() as StandardMaterial3D
				var nm := c.resource_name.to_lower()
				if nm.contains("suit"):          # short04 is the HAIR, not shorts
					# the texture is a black jumper, and tinting multiplies - black
					# times any colour is still black. Take the texture off and
					# keep the normal map for the folds.
					c.albedo_texture = null
					c.albedo_color = shirt
				mi.set_surface_override_material(i, c)

func place(pos: Vector3, tgt: Node3D) -> void:
	home = pos
	global_position = pos
	target = tgt
	state = "hiding"
	rotation.y = randf() * TAU
	marker.visible = true
	_last_pos = pos
	_spd = 0.0
	_best_d = INF
	_stuck_t = 0.0
	if tree == null:
		_play("idle")

func _play(n: String, blend := 0.25, rate := 1.0) -> void:
	if not _clips.is_empty():
		# a supplied model: map onto its clips; it walks when close, sprints when far
		if n == "run" and rate < 1.0 and _clips.has("walk"):
			n = "walk"
			rate = rate * 1.6
		n = _clips.get(n, n)
	if anim == null or not anim.has_animation(n):
		return
	if _anim_now != n:
		anim.play(n, blend, rate)
		_anim_now = n
		if n == "idle":
			anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
		elif n == "run":
			anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	anim.speed_scale = rate

func _physics_process(dt: float) -> void:
	_t += dt
	if target == null or state == "out":
		return
	var to := target.global_position - global_position
	to.y = 0.0
	var d := to.length()
	marker.position.y = 2.15 + sin(_t * 3.0) * 0.05
	marker.rotation.y += dt * 2.0
	if state == "hiding":
		# nearest live hostile sets how frightened they are
		var near := 999.0
		_near_p = Vector3.INF
		for h in get_tree().get_nodes_in_group("hostiles"):
			if h.is_active():
				var hd := (h as Node3D).global_position.distance_to(global_position)
				if hd < near:
					near = hd
					_near_p = (h as Node3D).global_position
		fear = lerpf(fear, 1.0 if near < 6.0 else 0.25, clampf(dt * 3.0, 0.0, 1.0))
		_whimper_cd -= dt
		if near < 6.0 and _whimper_cd <= 0.0:
			_whimper_cd = randf_range(2.6, 6.5)
			_say("sfx-breath.mp3", -6.0, randf_range(1.15, 1.35))   # short frightened breaths
		# they shake while they hide
		if lean:
			_nervous(dt, to)
		else:
			if model:
				model.rotation.z = sin(_t * 23.0) * 0.012 * fear
			_play("idle", 0.3, 0.6)
		if d < 1.6:
			state = "following"
			marker.visible = false
			_say("sfx-breath.mp3", -2.0, 1.0)
			found.emit(self)
	elif state == "following":
		if d > 2.2:
			var dir := to / maxf(d, 0.001)
			agent.target_position = target.global_position
			if not agent.is_navigation_finished():
				var np := agent.get_next_path_position()
				var step := Vector3(np.x - global_position.x, 0, np.z - global_position.z)
				if step.length() > 0.05:
					dir = step.normalized()
			# do not bunch up on each other
			for o in get_tree().get_nodes_in_group("survivors"):
				if o == self:
					continue
				var away := global_position - (o as Node3D).global_position
				away.y = 0.0
				var od := away.length()
				if od < 0.9 and od > 0.001:
					dir += away / od * 0.5
			dir = dir.normalized()
			var spd := 4.2 if d > 5.0 else 2.6
			velocity.x = dir.x * spd
			velocity.z = dir.z * spd
			if tree == null:
				_play("run", 0.25, spd / 3.0)
		else:
			velocity.x = 0.0
			velocity.z = 0.0
			if tree == null:
				_play("idle", 0.3)
		if not is_on_floor():
			velocity.y -= 18.0 * dt
		else:
			velocity.y = 0.0
		move_and_slide()
		# the safety net: someone who has made no progress for three seconds
		# while you walk away catches up out of sight, behind you - the doors
		# will not let you out without everyone, so nobody can be left stuck
		# progress is getting closer to you; shuffling on the spot is not
		if d <= 4.0 or d < _best_d - 0.5:
			_best_d = d
			_stuck_t = 0.0
		else:
			_stuck_t += dt
		if _stuck_t > 3.0:
			_stuck_t = 0.0
			_best_d = INF
			# the body never turns (the camera does), so behind is the camera's +Z
			var cam = target.get("camera")
			var bz: Vector3 = (cam as Node3D).global_basis.z if cam else Vector3.BACK
			bz.y = 0.0
			bz = bz.normalized() if bz.length() > 0.01 else Vector3.BACK
			var back: Vector3 = target.global_position + bz * 1.8
			var map := get_world_3d().navigation_map
			var p := NavigationServer3D.map_get_closest_point(map, back)
			global_position = p if p.distance_to(back) < 3.0 else back
		if model:
			model.rotation.z = 0.0
		if tree == null:
			rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), clampf(dt * 6.0, 0.0, 1.0))
			return
		# facing the way they are going, and you once they have stopped
		var hv := Vector2(velocity.x, velocity.z)
		_turn_to(atan2(velocity.x, velocity.z) if hv.length() > 0.1 else atan2(to.x, to.z), dt)
		_gait(dt)
		tree.set(P_IDLE, 1.0)
		if lean:
			# a glance at you over the shoulder; upright while they run
			var lk := clampf(wrapf(atan2(to.x, to.z) - rotation.y, -PI, PI), -0.9, 0.9)
			_look = lerpf(_look, lk, clampf(dt * 4.0, 0.0, 1.0))
			_hunch = lerpf(_hunch, clampf(_spd * 0.025, 0.0, 0.1), clampf(dt * 4.0, 0.0, 1.0))
			lean.pitch = _hunch
			lean.roll = clampf(-_yaw_vel * _spd * 0.015, -0.12, 0.12)
			lean.yaw = _look

## hiding: hunched lower the more frightened they are, breathing hard, a
## tremble through the spine, eyes on the nearest threat or scanning
func _nervous(dt: float, to_player: Vector3) -> void:
	_gait(dt)
	tree.set(P_IDLE, 0.75 + fear * 0.5)
	_hunch = lerpf(_hunch, 0.06 + fear * 0.12, clampf(dt * 2.0, 0.0, 1.0))
	lean.pitch = _hunch + sin(_t * (1.6 + fear * 1.4) + _ph) * 0.02
	lean.roll = sin(_t * 0.9 + _ph) * 0.03 + sin(_t * 23.0) * 0.02 * fear
	var want := sin(_t * 0.45 + _ph) * 0.7 + sin(_t * 1.7 + _ph * 2.0) * 0.15
	if _near_p != Vector3.INF and fear > 0.5:
		want = atan2(_near_p.x - global_position.x, _near_p.z - global_position.z) - rotation.y
	elif to_player.length() < 6.0:
		want = atan2(to_player.x, to_player.z) - rotation.y
	want = clampf(wrapf(want, -PI, PI), -1.0, 1.0)
	_look = lerpf(_look, want, clampf(dt * (2.0 + fear * 6.0), 0.0, 1.0))
	lean.yaw = _look

func _say(file: String, vol_db: float, pitch: float) -> void:
	var st := Game.file(file)
	if st == null:
		return
	voice.stream = st
	voice.volume_db = vol_db
	voice.pitch_scale = pitch
	voice.play()
