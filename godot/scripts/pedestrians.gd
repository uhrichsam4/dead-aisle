## STAGE G: TOWN NPCs - civilians walking both pavements the whole length of
## the road, so the drive between TOPS and the mosque is a town rather than
## an empty corridor. The same six Rocketbox people as the hostiles, each a
## little different in build, colour and pace, strolling on the stroll clip
## paced to the ground they cover; now and then one stops and stands a while,
## looking about, then walks on. Only the ones within 88 m move or draw.
## Ambience only: they never chase and never hurt.
extends Node3D

const U := preload("res://scripts/util.gd")
const H := preload("res://scripts/hostile.gd")

const WORLD_X0 := -1030.0
const WORLD_X1 := 170.0
const MOSQUE_X := -900.0
const DRAW := 88.0
const TURN := 2.2               # rad/s at most: a person turning, not a flip
const ACCEL := 1.1              # m/s^2 starting off and slowing to a stop

# {root, loco, ap, dir, cruise (m/s), spd (now), sc, yaw, side,
#  stop_in (s until the next stop), stand (s left standing), face (yaw)}
var folk := []
var car: Node3D
var player: Node3D
var rng := RandomNumberGenerator.new()

func setup(car_node: Node3D, player_node: Node3D) -> void:
	car = car_node
	player = player_node
	var libs := []              # [model, index in H.MODELS]
	for mi in H.MODELS.size():
		var l := U.glb(H.MODELS[mi])
		if l:
			libs.append([l, mi])
	if libs.is_empty():
		return
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
					1 if side == 1 else -1, side)
				i += 1
		x += 64.0

func _spawn(libs: Array, i: int, x: float, z: float, dir: int, side: int) -> void:
	var root := Node3D.new()
	root.name = "Folk%d" % i
	add_child(root)
	# the six people in turn, so the street is evenly mixed
	var pick: Array = libs[i % libs.size()]
	var mi_idx: int = pick[1]
	var m := (pick[0] as Node3D).duplicate() as Node3D
	root.add_child(m)
	# a little taller or shorter each
	m.scale = Vector3.ONE * rng.randf_range(0.93, 1.06)
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		(mi as MeshInstance3D).extra_cull_margin = 1.0
	# the hostiles' look shader, each in their own tint
	H.dress(m)
	H.vary(m, rng)
	var ap := m.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var loco: H.Loco = null
	# a stride a few percent longer or shorter than the clip's: the same
	# rate jitter the hostiles have, without the feet sliding
	var sc := m.scale.x * rng.randf_range(0.94, 1.06)
	var cruise := 1.0
	if ap and ap.has_animation("walk"):
		loco = H.Loco.new()
		loco.setup(ap, str(H.MODELS[mi_idx]).get_file().get_basename(), H.WALK_V[mi_idx], H.RUN_V[mi_idx])
		# neighbours on different takes of the stroll
		var walk := H.Loco.variant(ap, H.Loco.pick(ap, ["walk_stroll", "walk"]), i % 3)
		loco.force(1, walk)
		loco.force(0, _idle_for(ap))
		loco.reset(rng.randf() * 11.0)
		loco.idle_rate(rng.randf_range(0.88, 1.12))
		loco.fast_on = false
		loco.tree.active = false
		# a stroll close to the clip's own pace, so the rate stays natural
		cruise = loco.cv[1][0] * sc * rng.randf_range(0.86, 1.06)
	root.position = Vector3(x, 0, z)
	root.visible = false
	root.rotation.y = PI / 2 if dir > 0 else -PI / 2
	folk.append({"root": root, "loco": loco, "ap": ap, "dir": dir, "cruise": cruise, "spd": cruise,
		"sc": sc, "yaw": root.rotation.y, "side": side, "stop_in": rng.randf_range(4.0, 40.0),
		"stand": 0.0, "face": 0.0})

## a standing idle: mostly looking about, some fidgeting, on a random take
func _idle_for(ap: AnimationPlayer) -> String:
	var opts := ["idle_look", "idle_look", "idle_nervous", "idle"]
	return H.Loco.variant(ap, H.Loco.pick(ap, [opts[rng.randi() % opts.size()], "idle"]), rng.randi() % 3)

func _process(dt: float) -> void:
	if folk.is_empty():
		return
	var cx: float = car.global_position.x if Game.phase in ["drive", "parking", "menu"] and car else (player.global_position.x if player else 0.0)
	for f in folk:
		var r: Node3D = f.root
		var loco: H.Loco = f.loco
		var near := absf(r.position.x - cx) < DRAW
		if r.visible != near:
			r.visible = near
			if loco:
				loco.tree.active = near
		if not near:
			continue
		var path_yaw: float = PI / 2 if f.dir > 0 else -PI / 2
		var px := r.position.x
		# clear of the ends and the turn-back zones, so a stop never parks
		# someone in a shopfront
		var clear := absf(px) > 40.0 and absf(px - MOSQUE_X) > 46.0 and px < WORLD_X1 - 40.0 and px > WORLD_X0 + 40.0
		var target := 0.0
		var want := path_yaw
		if float(f.stand) > 0.0:
			f.stand = float(f.stand) - dt
			want = float(f.face)
			if float(f.stand) <= 0.0:
				f.stop_in = rng.randf_range(15.0, 45.0)
		else:
			f.stop_in = float(f.stop_in) - dt
			if float(f.stop_in) <= 0.0 and clear and f.loco:
				# stop a while: half turn to watch the road (the traffic, the
				# car), the rest just stand facing the way they were going
				f.stand = rng.randf_range(3.0, 9.0)
				f.face = (PI if int(f.side) == 1 else 0.0) + rng.randf_range(-0.5, 0.5) if rng.randf() < 0.5 else path_yaw + rng.randf_range(-0.3, 0.3)
				loco.want(0, _idle_for(f.ap))
			else:
				target = float(f.cruise)
		# a turn is eased in and capped, and they only cover ground as fast
		# as they face their way
		var diff := wrapf(want - float(f.yaw), -PI, PI)
		f.yaw = wrapf(float(f.yaw) + clampf(diff * clampf(dt * 4.0, 0.0, 1.0), -TURN * dt, TURN * dt), -PI, PI)
		r.rotation.y = f.yaw
		var along := maxf(0.0, cos(wrapf(path_yaw - float(f.yaw), -PI, PI)))
		f.spd = move_toward(float(f.spd), target * along, ACCEL * dt)
		r.position.x += f.dir * float(f.spd) * dt
		if loco:
			loco.step(dt, float(f.spd), float(f.sc))
		if px > WORLD_X1 - 30.0:
			f.dir = -1
		if px < WORLD_X0 + 30.0:
			f.dir = 1
		# turn back rather than stroll through a shopfront or the mosque gate
		if absf(px) < 30.0:
			f.dir = 1 if px > 0.0 else -1
		elif absf(px - MOSQUE_X) < 36.0:
			f.dir = 1 if px > MOSQUE_X else -1
