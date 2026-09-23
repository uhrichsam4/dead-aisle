## Pooled combat effects: bullet impacts read by surface, blood, a muzzle
## burst. Every emitter is built once, on its first use, and only restarted
## after that - a firefight never allocates a particle node. Static API; the
## pool lives on one node under the current scene, made on first call.
##   const Fx := preload("res://scripts/fx.gd")
##   Fx.impact(at, normal, "metal")   concrete | metal | wood | glass | tile | flesh
##   Fx.blood(at, dir)                spray + a splat on whatever is behind the hit
##   Fx.exit_wound(at, dir)           a headshot's exit: a burst out the far side
##   Fx.blood_pool(at, size)          a pool spreading under a corpse over ~4 s
##   Fx.muzzle(xform)                 a flash and a wisp of smoke (-Z is the bore)
extends Node3D

## emitters per kind, round-robin; a slot is reused by the time it comes round
const POOL := {"sparks": 8, "ping": 6, "dust": 10, "chips": 8, "splinters": 6, "shards": 6,
	"spray": 8, "drops": 8, "smoke": 6, "flash": 4, "burst": 4}
const MAX_BLOOD := 40
const MAX_POOLS := 12
const POOL_GROW := 4.0               # seconds a pool takes to spread
const WORLD_MASK := 1 | 32          # static world and props: never people or the car

static var _inst: Node3D
static var _star: Texture2D
static var _puff: Texture2D
static var _splats: Array[Texture2D] = []
static var _pool_tex: Texture2D
static var _pool_orm: Texture2D

var _pools := {}
var _idx := {}
var _decals: Array[Decal] = []
var _decal_i := 0
var _ray: PhysicsRayQueryParameters3D
# blood pools: [Decal, age, full size]; age < 0 is idle
var _puddles: Array = []
var _puddle_i := 0
var _growing := 0

# ------------------------------------------------------------------ API

static func impact(at: Vector3, normal: Vector3, surface: String) -> void:
	var f := _mgr()
	if f == null:
		return
	f.call("_impact", at, normal, surface)

static func blood(at: Vector3, dir: Vector3) -> void:
	var f := _mgr()
	if f == null:
		return
	f.call("_blood", at, dir)

static func exit_wound(at: Vector3, dir: Vector3) -> void:
	var f := _mgr()
	if f == null:
		return
	f.call("_exit_wound", at, dir)

static func blood_pool(at: Vector3, size: float) -> void:
	var f := _mgr()
	if f == null:
		return
	f.call("_blood_pool", at, size)

static func muzzle(xform: Transform3D) -> void:
	var f := _mgr()
	if f == null:
		return
	var fwd := -xform.basis.z.normalized()
	f.call("_emit", "flash", xform.origin, fwd, Color(0, 0, 0, 0))
	f.call("_emit", "smoke", xform.origin + fwd * 0.05, fwd, Color(0, 0, 0, 0))

## build every pool and texture up front (a loading-time cost, not a
## first-shot hitch); safe to call more than once
static func warm() -> void:
	var f := _mgr()
	if f == null:
		return
	star_texture()
	f.call("_warm")

func _warm() -> void:
	for k in POOL:
		if not _pools.has(k):
			_pools[k] = _build(k)
	if _splats.is_empty():
		for i in 4:
			_splats.append(_make_splat(i))
	_pool_textures()

## a seven point burst, white on alpha, for any muzzle flash
static func star_texture() -> Texture2D:
	if _star:
		return _star
	var n := 96
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var spikes := []
	var count := 7
	for i in count:
		# uneven prongs: a real flash is never a clean asterisk
		spikes.append([TAU * float(i) / count + randf_range(-0.2, 0.2), randf_range(0.55, 1.0), randf_range(0.6, 1.4)])
	for y in n:
		for x in n:
			var px := (float(x) + 0.5) / n * 2.0 - 1.0
			var py := (float(y) + 0.5) / n * 2.0 - 1.0
			var d := sqrt(px * px + py * py)
			var v := exp(-d * d * 22.0) * 1.1 + exp(-d * d * 5.0) * 0.25
			var a := atan2(py, px)
			for s in spikes:
				var along := d * cos(a - s[0])
				if along <= 0.0:
					continue
				var len_s: float = s[1]
				var t := along / len_s
				if t >= 1.0:
					continue
				var perp := d * sin(a - s[0])
				var w := 0.0025 * float(s[2]) + 0.012 * (1.0 - t)
				v += exp(-perp * perp / (w * w) * 0.5) * (1.0 - t) * (1.0 - t)
			v = clampf(v, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, v))
	_star = ImageTexture.create_from_image(img)
	return _star

# ------------------------------------------------------------------ manager

static func _mgr() -> Node3D:
	if is_instance_valid(_inst) and _inst.is_inside_tree():
		return _inst
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.current_scene == null:
		return null
	var n := Node3D.new()
	n.name = "Fx"
	n.set_script(load("res://scripts/fx.gd"))
	tree.current_scene.add_child(n)
	_inst = n
	return n

func _impact(at: Vector3, normal: Vector3, surface: String) -> void:
	var n := normal.normalized() if normal.length() > 0.01 else Vector3.UP
	var p := at + n * 0.015
	match surface:
		"metal":
			_emit("sparks", p, n, Color(0, 0, 0, 0))
			_emit("ping", p, n, Color(0, 0, 0, 0))
			_emit("dust", p, n, Color(0.42, 0.42, 0.42, 0.35))
		"wood":
			_emit("splinters", p, n, Color(0.55, 0.4, 0.24))
			_emit("dust", p, n, Color(0.6, 0.5, 0.38, 0.5))
		"glass":
			_emit("shards", p, n, Color(0.78, 0.88, 0.92))
			_emit("dust", p, n, Color(0.85, 0.9, 0.92, 0.3))
		"flesh":
			_emit("spray", p, n, Color(0, 0, 0, 0))
			_emit("drops", p, n, Color(0, 0, 0, 0))
		"tile":
			_emit("chips", p, n, Color(0.86, 0.85, 0.82))
			_emit("dust", p, n, Color(0.8, 0.79, 0.76, 0.6))
		_:
			_emit("chips", p, n, Color(0.52, 0.5, 0.47))
			_emit("dust", p, n, Color(0.68, 0.65, 0.6, 0.7))

func _blood(at: Vector3, dir: Vector3) -> void:
	var d := dir.normalized() if dir.length() > 0.01 else Vector3.DOWN
	_emit("spray", at, d, Color(0, 0, 0, 0))
	_emit("drops", at, d, Color(0, 0, 0, 0))
	# the splat goes where the round carried it: a wall behind, else the floor
	var hit := _cast(at, at + d * 2.6)
	if hit.is_empty():
		hit = _cast(at, at + Vector3.DOWN * 3.0)
		if hit.is_empty():
			return
		_splat(hit.position, hit.normal, randf_range(0.45, 0.75))
		return
	_splat(hit.position, hit.normal, randf_range(0.5, 0.9))
	# a wall hit also drips a pool under the victim, now and then
	if (hit.normal as Vector3).y < 0.6 and randf() < 0.5:
		var fl := _cast(at, at + Vector3.DOWN * 3.0)
		if not fl.is_empty():
			_splat(fl.position, fl.normal, randf_range(0.35, 0.6))

## a headshot: the round leaves through the far side of the skull - a hard,
## narrow burst along the shot, and a big splat on whatever is behind
func _exit_wound(at: Vector3, dir: Vector3) -> void:
	var d := dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
	var out := at + d * 0.2
	_emit("burst", out, d, Color(0, 0, 0, 0))
	_emit("drops", out, d, Color(0, 0, 0, 0))
	var hit := _cast(out, out + d * 4.0)
	if not hit.is_empty():
		_splat(hit.position, hit.normal, randf_range(0.9, 1.4))
		return
	var fl := _cast(out + d * 1.2, out + d * 1.2 + Vector3.DOWN * 3.0)
	if not fl.is_empty():
		_splat(fl.position, fl.normal, randf_range(0.7, 1.1))

## a pool under a body that has stopped moving: it spreads from a hand's
## width to its full size over POOL_GROW, the oldest of MAX_POOLS reused
func _blood_pool(at: Vector3, size: float) -> void:
	var hit := _cast(at + Vector3.UP * 0.4, at + Vector3.DOWN * 2.5)
	if hit.is_empty() or (hit.normal as Vector3).y < 0.7:
		return
	_pool_textures()
	var e: Array
	if _puddles.size() < MAX_POOLS:
		var dc := Decal.new()
		dc.cull_mask = WORLD_MASK
		dc.upper_fade = 0.15
		dc.lower_fade = 0.3
		dc.distance_fade_enabled = true
		dc.distance_fade_begin = 40.0
		dc.distance_fade_length = 15.0
		dc.texture_albedo = _pool_tex
		dc.texture_orm = _pool_orm
		add_child(dc)
		e = [dc, -1.0, 1.0]
		_puddles.append(e)
	else:
		e = _puddles[_puddle_i]
		_puddle_i = (_puddle_i + 1) % MAX_POOLS
	var dc: Decal = e[0]
	if float(e[1]) < 0.0 or float(e[1]) >= POOL_GROW:
		_growing += 1
	e[1] = 0.0
	e[2] = clampf(size, 0.4, 1.3)
	dc.visible = true
	dc.size = Vector3(0.12, 0.25, 0.12)
	dc.modulate = Color(randf_range(0.85, 1.0), 1, 1, 0.0)
	dc.global_transform = Transform3D(_basis_up(hit.normal) * Basis(Vector3.UP, randf() * TAU), (hit.position as Vector3) + Vector3.UP * 0.005)
	set_process(true)

func _process(dt: float) -> void:
	if _growing <= 0:
		set_process(false)
		return
	for e in _puddles:
		var t: float = e[1]
		if t < 0.0 or t >= POOL_GROW:
			continue
		t += dt
		e[1] = t
		var dc: Decal = e[0]
		# fast at first, slowing as it runs out
		var k := 1.0 - pow(1.0 - clampf(t / POOL_GROW, 0.0, 1.0), 2.2)
		var sz := lerpf(0.12, float(e[2]), k)
		dc.size = Vector3(sz, 0.25, sz)
		dc.modulate.a = clampf(t / 0.35, 0.0, 1.0) * 0.97
		if t >= POOL_GROW:
			_growing -= 1

## the pool: one thick body with a few lobes, soft at the rim; and its wet
## sheen (low roughness) in the same shape
static func _pool_textures() -> void:
	if _pool_tex:
		return
	var n := 128
	var rng := RandomNumberGenerator.new()
	rng.seed = 5171
	var blobs := [[64.0, 64.0, 34.0]]
	for i in 6:
		var ang := rng.randf() * TAU
		var dd := rng.randf_range(12.0, 24.0)
		blobs.append([64.0 + cos(ang) * dd, 64.0 + sin(ang) * dd, rng.randf_range(14.0, 24.0)])
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var orm := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			# a smooth union of the lobes: pools meet, they do not overlap
			var f := 0.0
			for b in blobs:
				var dx := float(x) - float(b[0])
				var dy := float(y) - float(b[1])
				var r: float = b[2]
				f += exp(-(dx * dx + dy * dy) / (r * r) * 2.2)
			var v := clampf((f - 0.35) / 0.25, 0.0, 1.0)
			var edge := clampf((f - 0.35) / 0.9, 0.0, 1.0)
			var c := Color(0.26, 0.01, 0.008).lerp(Color(0.09, 0.003, 0.003), edge)
			img.set_pixel(x, y, Color(c.r, c.g, c.b, v))
			orm.set_pixel(x, y, Color(1.0, 0.08, 0.0, v))
	img.generate_mipmaps()
	orm.generate_mipmaps()
	_pool_tex = ImageTexture.create_from_image(img)
	_pool_orm = ImageTexture.create_from_image(orm)

func _cast(a: Vector3, b: Vector3) -> Dictionary:
	if _ray == null:
		_ray = PhysicsRayQueryParameters3D.new()
		_ray.collision_mask = WORLD_MASK
		_ray.collide_with_areas = false
	_ray.from = a
	_ray.to = b
	return get_world_3d().direct_space_state.intersect_ray(_ray)

func _splat(pos: Vector3, normal: Vector3, s: float) -> void:
	if _splats.is_empty():
		for i in 4:
			_splats.append(_make_splat(i))
	var dc: Decal
	if _decals.size() < MAX_BLOOD:
		dc = Decal.new()
		dc.cull_mask = WORLD_MASK
		dc.upper_fade = 0.1
		dc.lower_fade = 0.1
		dc.distance_fade_enabled = true
		dc.distance_fade_begin = 40.0
		dc.distance_fade_length = 15.0
		add_child(dc)
		_decals.append(dc)
	else:
		dc = _decals[_decal_i]
		_decal_i = (_decal_i + 1) % MAX_BLOOD
	dc.texture_albedo = _splats[randi() % _splats.size()]
	dc.modulate = Color(randf_range(0.8, 1.0), 1, 1, randf_range(0.85, 1.0))
	dc.size = Vector3(s, 0.3, s)
	dc.global_transform = Transform3D(_basis_up(normal) * Basis(Vector3.UP, randf() * TAU), pos)

## a splat: one body, satellite droplets flung one way, a few streaks
static func _make_splat(seed_i: int) -> Texture2D:
	var n := 128
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 * (seed_i + 1)
	var a := PackedFloat32Array()
	a.resize(n * n)
	var blobs := []                       # [cx, cy, r]
	blobs.append([64.0, 64.0, rng.randf_range(18.0, 24.0)])
	for i in 7:
		var ang := rng.randf() * TAU
		var dd := rng.randf_range(6.0, 16.0)
		blobs.append([64.0 + cos(ang) * dd, 64.0 + sin(ang) * dd, rng.randf_range(8.0, 14.0)])
	var fling := rng.randf() * TAU
	for i in 16:
		var ang := fling + rng.randf_range(-0.7, 0.7)
		var dd := rng.randf_range(26.0, 58.0)
		blobs.append([64.0 + cos(ang) * dd, 64.0 + sin(ang) * dd, rng.randf_range(1.2, 4.0) * (1.0 - dd / 90.0)])
	for b in blobs:
		var cx: float = b[0]
		var cy: float = b[1]
		var r: float = b[2]
		for y in range(maxi(0, int(cy - r - 2)), mini(n, int(cy + r + 3))):
			for x in range(maxi(0, int(cx - r - 2)), mini(n, int(cx + r + 3))):
				var d := Vector2(x - cx, y - cy).length()
				var v := clampf((r - d) / 1.6, 0.0, 1.0)
				var k := y * n + x
				a[k] = maxf(a[k], v)
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var v := a[y * n + x]
			# darker where it pooled thick, a brighter rim where it thinned
			var c := Color(0.30, 0.012, 0.01).lerp(Color(0.16, 0.005, 0.004), v)
			img.set_pixel(x, y, Color(c.r, c.g, c.b, v * 0.95))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

# ------------------------------------------------------------------ emitters

func _emit(kind: String, at: Vector3, up: Vector3, col: Color) -> void:
	if not _pools.has(kind):
		_pools[kind] = _build(kind)
	var list: Array = _pools[kind]
	var i: int = _idx.get(kind, 0)
	_idx[kind] = (i + 1) % list.size()
	var p: GPUParticles3D = list[i]
	p.global_transform = Transform3D(_basis_up(up), at)
	if col.a > 0.0:
		(p.process_material as ParticleProcessMaterial).color = col
	p.restart()

static func _basis_up(n: Vector3) -> Basis:
	var y := n.normalized()
	var ref := Vector3.RIGHT if absf(y.x) < 0.9 else Vector3.FORWARD
	var x := ref.cross(y).normalized()
	return Basis(x, y, x.cross(y))

func _build(kind: String) -> Array:
	var out := []
	for i in POOL.get(kind, 4):
		var p := _make(kind)
		add_child(p)
		out.append(p)
	return out

func _make(kind: String) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.emitting = false
	p.local_coords = false
	p.interpolate = false           # a teleported one-shot must not smear from its last spot
	p.fixed_fps = 0
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-4, -4, -4), Vector3(8, 8, 8))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	match kind:
		"sparks":
			p.amount = 16
			p.lifetime = 0.32
			pm.spread = 60.0
			pm.initial_velocity_min = 4.0
			pm.initial_velocity_max = 11.0
			pm.gravity = Vector3(0, -9.8, 0)
			pm.damping_min = 2.0
			pm.damping_max = 5.0
			pm.particle_flag_align_y = true
			pm.scale_min = 0.5
			pm.scale_max = 1.2
			pm.color_ramp = _ramp([Color(1, 1, 0.9, 1), Color(1, 0.62, 0.22, 1), Color(0.8, 0.18, 0.04, 0)])
			p.draw_pass_1 = _box(Vector3(0.006, 0.085, 0.006), _glow_mat(Color(4.0, 2.6, 1.2)))
		"ping":
			p.amount = 1
			p.lifetime = 0.06
			pm.spread = 0.0
			pm.gravity = Vector3.ZERO
			pm.angle_min = -180.0
			pm.angle_max = 180.0
			pm.scale_min = 0.7
			pm.scale_max = 1.2
			pm.color = Color(1, 0.8, 0.5)
			p.draw_pass_1 = _quad(0.22, _sprite_mat(star_texture(), Color(3.0, 2.1, 1.2), true, false))
		"dust":
			p.amount = 7
			p.lifetime = 1.1
			pm.spread = 38.0
			pm.initial_velocity_min = 0.5
			pm.initial_velocity_max = 2.4
			pm.damping_min = 2.5
			pm.damping_max = 4.0
			pm.gravity = Vector3(0, -0.5, 0)
			pm.angle_min = -180.0
			pm.angle_max = 180.0
			pm.angular_velocity_min = -40.0
			pm.angular_velocity_max = 40.0
			pm.scale_min = 0.6
			pm.scale_max = 1.2
			pm.scale_curve = _curve(0.35, 1.8)
			pm.color_ramp = _ramp([Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0)])
			p.draw_pass_1 = _quad(0.26, _sprite_mat(_puff_texture(), Color(1, 1, 1), false, true))
		"chips":
			p.amount = 9
			p.lifetime = 0.55
			pm.spread = 45.0
			pm.initial_velocity_min = 2.0
			pm.initial_velocity_max = 5.5
			pm.gravity = Vector3(0, -14, 0)
			pm.particle_flag_rotate_y = true
			pm.angular_velocity_min = -720.0
			pm.angular_velocity_max = 720.0
			pm.scale_min = 0.4
			pm.scale_max = 1.3
			pm.scale_curve = _curve(1.0, 0.0, 0.7)
			p.draw_pass_1 = _box(Vector3(0.018, 0.014, 0.02), _solid_mat(0.95, 0.0))
		"splinters":
			p.amount = 8
			p.lifetime = 0.65
			pm.spread = 50.0
			pm.initial_velocity_min = 2.0
			pm.initial_velocity_max = 6.0
			pm.gravity = Vector3(0, -12, 0)
			pm.particle_flag_align_y = true
			pm.scale_min = 0.5
			pm.scale_max = 1.3
			pm.scale_curve = _curve(1.0, 0.0, 0.7)
			p.draw_pass_1 = _box(Vector3(0.007, 0.07, 0.012), _solid_mat(0.85, 0.0))
		"shards":
			p.amount = 11
			p.lifetime = 0.7
			pm.spread = 55.0
			pm.initial_velocity_min = 1.5
			pm.initial_velocity_max = 5.0
			pm.gravity = Vector3(0, -12, 0)
			pm.particle_flag_rotate_y = true
			pm.angular_velocity_min = -900.0
			pm.angular_velocity_max = 900.0
			pm.scale_min = 0.4
			pm.scale_max = 1.4
			pm.scale_curve = _curve(1.0, 0.0, 0.75)
			p.draw_pass_1 = _box(Vector3(0.028, 0.003, 0.02), _solid_mat(0.06, 0.4))
		"spray":
			p.amount = 9
			p.lifetime = 0.45
			pm.spread = 28.0
			pm.initial_velocity_min = 1.2
			pm.initial_velocity_max = 4.0
			pm.damping_min = 3.0
			pm.damping_max = 6.0
			pm.gravity = Vector3(0, -5, 0)
			pm.angle_min = -180.0
			pm.angle_max = 180.0
			pm.scale_min = 0.5
			pm.scale_max = 1.1
			pm.scale_curve = _curve(0.4, 1.6)
			pm.color = Color(0.36, 0.02, 0.02)
			pm.color_ramp = _ramp([Color(1, 1, 1, 0.95), Color(0.8, 0.8, 0.8, 0.6), Color(0.6, 0.6, 0.6, 0)])
			p.draw_pass_1 = _quad(0.2, _sprite_mat(_puff_texture(), Color(1, 1, 1), false, true))
		"drops":
			p.amount = 14
			p.lifetime = 0.55
			pm.spread = 32.0
			pm.initial_velocity_min = 2.5
			pm.initial_velocity_max = 7.0
			pm.gravity = Vector3(0, -14, 0)
			pm.particle_flag_align_y = true
			pm.scale_min = 0.5
			pm.scale_max = 1.2
			pm.scale_curve = _curve(1.0, 0.2, 0.6)
			pm.color = Color(0.3, 0.015, 0.012)
			p.draw_pass_1 = _box(Vector3(0.007, 0.03, 0.007), _solid_mat(0.25, 0.0))
		"smoke":
			p.amount = 4
			p.lifetime = 1.2
			pm.spread = 18.0
			pm.initial_velocity_min = 0.3
			pm.initial_velocity_max = 1.0
			pm.damping_min = 1.5
			pm.damping_max = 2.5
			pm.gravity = Vector3(0, 0.35, 0)
			pm.angle_min = -180.0
			pm.angle_max = 180.0
			pm.angular_velocity_min = -30.0
			pm.angular_velocity_max = 30.0
			pm.scale_curve = _curve(0.4, 2.2)
			pm.color = Color(0.7, 0.7, 0.7)
			pm.color_ramp = _ramp([Color(1, 1, 1, 0.35), Color(1, 1, 1, 0.15), Color(1, 1, 1, 0)])
			p.draw_pass_1 = _quad(0.22, _sprite_mat(_puff_texture(), Color(1, 1, 1), false, true))
		"burst":
			p.amount = 24
			p.lifetime = 0.7
			pm.spread = 16.0
			pm.initial_velocity_min = 3.0
			pm.initial_velocity_max = 9.5
			pm.damping_min = 1.5
			pm.damping_max = 3.5
			pm.gravity = Vector3(0, -9.8, 0)
			pm.angle_min = -180.0
			pm.angle_max = 180.0
			pm.scale_min = 0.35
			pm.scale_max = 1.0
			pm.scale_curve = _curve(0.5, 1.8)
			pm.color = Color(0.3, 0.012, 0.01)
			pm.color_ramp = _ramp([Color(1, 1, 1, 1), Color(0.85, 0.85, 0.85, 0.7), Color(0.6, 0.6, 0.6, 0)])
			p.draw_pass_1 = _quad(0.16, _sprite_mat(_puff_texture(), Color(1, 1, 1), false, true))
		"flash":
			p.amount = 1
			p.lifetime = 0.05
			pm.spread = 0.0
			pm.gravity = Vector3.ZERO
			pm.angle_min = -180.0
			pm.angle_max = 180.0
			pm.scale_min = 0.8
			pm.scale_max = 1.3
			pm.color = Color(1, 0.85, 0.6)
			p.draw_pass_1 = _quad(0.45, _sprite_mat(star_texture(), Color(3.2, 2.2, 1.2), true, false))
	p.process_material = pm
	return p

# ------------------------------------------------------------------ bits

static func _puff_texture() -> Texture2D:
	if _puff:
		return _puff
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 64
	gt.height = 64
	_puff = gt
	return _puff

static func _ramp(cols: Array) -> GradientTexture1D:
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var pc := PackedColorArray()
	for i in cols.size():
		offs.append(float(i) / (cols.size() - 1))
		pc.append(cols[i])
	g.offsets = offs
	g.colors = pc
	var t := GradientTexture1D.new()
	t.gradient = g
	t.width = 64
	return t

## scale over life: from a to b, holding a until `hold`
static func _curve(a: float, b: float, hold := 0.0) -> CurveTexture:
	var c := Curve.new()
	c.max_value = maxf(1.0, maxf(a, b))
	c.add_point(Vector2(0, a))
	if hold > 0.0:
		c.add_point(Vector2(hold, a))
	c.add_point(Vector2(1, b))
	var t := CurveTexture.new()
	t.curve = c
	return t

static func _box(size: Vector3, mat: Material) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	m.material = mat
	return m

static func _quad(s: float, mat: Material) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(s, s)
	q.material = mat
	return q

## hot streaks that bloom: unshaded, additive, HDR
static func _glow_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.albedo_color = c
	m.disable_receive_shadows = true
	return m

## chips, splinters, shards, drops: lit, coloured by the emitter
static func _solid_mat(rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = rough
	m.metallic = metal
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	return m

## camera-facing sprites: additive flashes, or soft lit puffs of dust and smoke
static func _sprite_mat(tex: Texture2D, c: Color, additive: bool, lit: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.albedo_color = c
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.disable_receive_shadows = true
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	elif lit:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
		m.proximity_fade_enabled = true       # no hard line where a puff meets the wall
		m.proximity_fade_distance = 0.12
	else:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m
