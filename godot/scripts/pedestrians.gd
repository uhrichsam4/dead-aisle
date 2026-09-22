## STAGE G: TOWN NPCs - civilians walking both pavements the whole length of
## the road, so the drive between TOPS and the mosque is a town rather than
## an empty corridor. The hostile rig in a civilian palette on its walk
## clip, face and hair meshes stripped; only the ones within 88 m move or
## draw. Ambience only: they never chase and never hurt.
extends Node3D

const U := preload("res://scripts/util.gd")

const WORLD_X0 := -1030.0
const WORLD_X1 := 170.0
const MOSQUE_X := -900.0
const DRAW := 88.0
const SHIRT := ["b8b2a4", "7d6a58", "4c5a6b", "6b5560", "8a7f5e", "3f4a44", "93745a", "5d6470"]
const PANT := ["3a4048", "4e4438", "2f3540", "5a5348"]

var folk := []          # {root, anim, dir, speed, rate}
var car: Node3D
var player: Node3D

func setup(car_node: Node3D, player_node: Node3D) -> void:
	car = car_node
	player = player_node
	var lib := U.glb("res://assets/hostile.glb")
	if lib == null:
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
				_spawn(lib, i, x + rng.randf_range(-8, 8), 41.4 + rng.randf_range(-0.6, 0.6) if side == 1 else 30.6 + rng.randf_range(-0.7, 0.7),
					1 if side == 1 else -1, rng)
				i += 1
		x += 64.0

func _spawn(lib: Node3D, i: int, x: float, z: float, dir: int, rng: RandomNumberGenerator) -> void:
	var root := Node3D.new()
	root.name = "Folk%d" % i
	add_child(root)
	var m := lib.duplicate() as Node3D
	root.add_child(m)
	_fit(m, 1.76)
	var shirt := Color(SHIRT[i % SHIRT.size()])
	var pant := Color(PANT[(i * 3) % PANT.size()])
	var skin_k := 0.74 + float((i * 29) % 9) / 9.0 * 0.5
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		var n := str(mi.name).to_lower()
		if n.contains("eyebrow") or n.contains("low_poly") or n.contains("short04"):
			mi.queue_free()
			continue
		var m3 := mi as MeshInstance3D
		m3.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for si in m3.mesh.get_surface_count():
			var src := m3.get_active_material(si)
			if not (src is StandardMaterial3D):
				continue
			var c := (src as StandardMaterial3D).duplicate() as StandardMaterial3D
			var nm := c.resource_name.to_lower()
			if nm.contains("casualsuit") or nm.contains("suit"):
				c.albedo_texture = null
				c.albedo_color = (c.albedo_color * 0.9).lerp(shirt, 0.6)
			elif nm.contains("male") or nm.contains("skin"):
				c.albedo_color = c.albedo_color * skin_k
			elif nm.contains("shoes"):
				c.albedo_color = c.albedo_color.lerp(pant, 0.4)
			m3.set_surface_override_material(si, c)
	var ap := m.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap and ap.has_animation("run"):
		ap.get_animation("run").loop_mode = Animation.LOOP_LINEAR
		ap.play("run")
		ap.seek(rng.randf() * 2.0, true)
	root.position = Vector3(x, 0, z)
	root.visible = false
	folk.append({"root": root, "anim": ap, "dir": dir, "speed": rng.randf_range(0.55, 1.15), "rate": rng.randf_range(0.55, 0.85)})

## by the skeleton, as the hostiles are fitted (the rig carries a 0.1 scale)
func _fit(model: Node3D, h: float) -> void:
	var sks := model.find_children("*", "Skeleton3D", true, false)
	if sks.is_empty():
		return
	var sk := sks[0] as Skeleton3D
	var to_model := model.global_transform.affine_inverse() * sk.global_transform
	var lo := INF
	var hi := -INF
	for b in sk.get_bone_count():
		var y := (to_model * sk.get_bone_global_rest(b)).origin.y
		lo = minf(lo, y)
		hi = maxf(hi, y)
	if hi - lo <= 0.01:
		return
	var s := h * 0.88 / (hi - lo)
	model.scale = Vector3.ONE * s
	model.position.y = -lo * s + 0.06

func _process(dt: float) -> void:
	if folk.is_empty():
		return
	var cx: float = car.global_position.x if Game.phase in ["drive", "parking", "menu"] and car else (player.global_position.x if player else 0.0)
	for f in folk:
		var r: Node3D = f.root
		var near := absf(r.position.x - cx) < DRAW
		if r.visible != near:
			r.visible = near
			if f.anim:
				(f.anim as AnimationPlayer).speed_scale = 0.0 if not near else f.rate * (f.speed / 0.9)
		if not near:
			continue
		r.position.x += f.dir * f.speed * dt
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
		r.rotation.y = PI / 2 if f.dir > 0 else -PI / 2
