## STAGE G: TOWN NPCs - civilians walking both pavements the whole length of
## the road, so the drive between TOPS and the mosque is a town rather than
## an empty corridor. The same six Rocketbox people as the hostiles, each a
## little different in build and colour, on their walk clip paced to the
## ground they cover; only the ones within 88 m move or draw. Ambience only:
## they never chase and never hurt.
extends Node3D

const U := preload("res://scripts/util.gd")
const H := preload("res://scripts/hostile.gd")

const WORLD_X0 := -1030.0
const WORLD_X1 := 170.0
const MOSQUE_X := -900.0
const DRAW := 88.0

var folk := []          # {root, tree, dir, speed, a (stride share), amp, stride, yaw}
var car: Node3D
var player: Node3D

func setup(car_node: Node3D, player_node: Node3D) -> void:
	car = car_node
	player = player_node
	var libs := []
	for path in H.MODELS:
		var l := U.glb(path)
		if l:
			libs.append(l)
	if libs.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var i := 0
	var x := WORLD_X0 + 60.0
	while x < WORLD_X1 - 40.0:
		# off the TOPS forecourt and out of the mosque courtyard
		if absf(x) >= 34.0 and absf(x - MOSQUE_X) >= 40.0:
			for side in [0, 1]:
				if rng.randf() < 0.28:
					continue
				_spawn(libs, i, x + rng.randf_range(-8, 8), 41.4 + rng.randf_range(-0.6, 0.6) if side == 1 else 30.6 + rng.randf_range(-0.7, 0.7),
					1 if side == 1 else -1, rng)
				i += 1
		x += 64.0

func _spawn(libs: Array, i: int, x: float, z: float, dir: int, rng: RandomNumberGenerator) -> void:
	var root := Node3D.new()
	root.name = "Folk%d" % i
	add_child(root)
	# the six people in turn, so the street is evenly mixed
	var mi_idx := i % libs.size()
	var m := (libs[mi_idx] as Node3D).duplicate() as Node3D
	root.add_child(m)
	# a little taller or shorter each
	m.scale = Vector3.ONE * rng.randf_range(0.95, 1.05)
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		(mi as MeshInstance3D).extra_cull_margin = 1.0
	# the hostiles' look shader, each in their own tint
	H.dress(m)
	H.vary(m, rng)
	var ap := m.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var tr: AnimationTree = null
	if ap and ap.has_animation("walk"):
		for n in ["idle", "walk", "run"]:
			if ap.has_animation(n):
				ap.get_animation(n).loop_mode = Animation.LOOP_LINEAR
		ap.stop()
		tr = AnimationTree.new()
		ap.get_parent().add_child(tr)
		tr.anim_player = tr.get_path_to(ap)
		tr.root_node = tr.get_path_to(ap.get_node(ap.root_node))
		tr.tree_root = H._tree_root()
		tr.set(H.P_SEEK, rng.randf() * 3.0)
		tr.set(H.P_IDLE, rng.randf_range(0.85, 1.15))
		tr.set(H.P_RUNB, 0.0)
		tr.active = false
	var spd := rng.randf_range(0.55, 1.15)
	root.position = Vector3(x, 0, z)
	root.visible = false
	root.rotation.y = PI / 2 if dir > 0 else -PI / 2
	# a stroll is a shorter stride than the clip's, not a slow-motion one: the
	# walk's weight over the idle is the stride's size, the rate is what keeps
	# the planted foot still at that size
	folk.append({"root": root, "tree": tr, "dir": dir, "speed": spd,
		"a": clampf(spd / 1.2, 0.55, 1.0) * rng.randf_range(0.94, 1.04), "amp": 0.0,
		"stride": float(H.WALK_V[mi_idx % H.WALK_V.size()]) * m.scale.x, "yaw": root.rotation.y})

func _process(dt: float) -> void:
	if folk.is_empty():
		return
	var cx: float = car.global_position.x if Game.phase in ["drive", "parking", "menu"] and car else (player.global_position.x if player else 0.0)
	for f in folk:
		var r: Node3D = f.root
		var near := absf(r.position.x - cx) < DRAW
		if r.visible != near:
			r.visible = near
			if f.tree:
				(f.tree as AnimationTree).active = near
		if not near:
			continue
		# a turn back is a slow-down, a turn on the spot and a walk off, not
		# a flip: they only cover ground as fast as they face their way
		var want: float = PI / 2 if f.dir > 0 else -PI / 2
		var diff := wrapf(want - float(f.yaw), -PI, PI)
		f.yaw = wrapf(float(f.yaw) + clampf(diff, -2.4 * dt, 2.4 * dt), -PI, PI)
		r.rotation.y = f.yaw
		var eff: float = f.speed * maxf(0.0, cos(diff))
		r.position.x += f.dir * eff * dt
		if f.tree:
			var at: float = float(f.a) * clampf(eff / (float(f.speed) * 0.5), 0.0, 1.0)
			f.amp = lerpf(float(f.amp), at, clampf(dt * 5.0, 0.0, 1.0))
			var tr := f.tree as AnimationTree
			tr.set(H.P_WALKB, f.amp)
			tr.set(H.P_WALK, clampf(eff / maxf(float(f.amp) * float(f.stride), 0.05), 0.3, 1.6) if f.amp > 0.02 else 1.0)
		if r.position.x > WORLD_X1 - 30.0:
			f.dir = -1
		if r.position.x < WORLD_X0 + 30.0:
			f.dir = 1
		# turn back rather than stroll through a shopfront or the mosque gate
		var px := r.position.x
		if absf(px) < 30.0:
			f.dir = 1 if px > 0.0 else -1
		elif absf(px - MOSQUE_X) < 36.0:
			f.dir = 1 if px > MOSQUE_X else -1
