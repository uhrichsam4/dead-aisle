## Set dressing from the Poly Haven packs and the map2 drop, placed where the
## web build put it (phPlace / P in dead-aisle.html). Store clutter goes
## through floor_spot() so nothing lands in an aisle or on a checkout.
##
## Anything marked solid gets a box body. Tall props block movement (layer 1);
## small ones sit on layer 32, which rounds hit but nobody trips over and the
## navmesh does not carve round. brk makes it a breakable (breakable.gd).
extends RefCounted

const U := preload("res://scripts/util.gd")
const BreakScript := preload("res://scripts/breakable.gd")
const MQ := preload("res://scripts/mosque.gd")

const SMALL_LAYER := 32
const MAP2 := "res://assets/map2.glb"
const STORE := "res://assets/ph_store.glb"
const STREET := "res://assets/ph_street.glb"
const FURN := "res://assets/ph_furn.glb"
const EXTRA := "res://assets/ph_extra.glb"
const CHECKOUT_X := [-13.0, -4.5, 4.5, 13.0]

static var rng := RandomNumberGenerator.new()

## phPlace: fit by height (h) or by largest horizontal extent (w), seat the
## BASE at y whatever the pack's pivot, face ry (random if absent)
static func put(parent: Node3D, lib: String, n: String, x: float, z: float, o := {}) -> Node3D:
	var p := U.part(lib, n)
	if p == null:
		return null
	p.position = Vector3.ZERO
	p.rotation = Vector3.ZERO
	p.scale = Vector3.ONE
	var a := U.local_aabb(p)
	var sc := 1.0
	if o.has("h"):
		sc = float(o.h) / maxf(0.001, a.size.y)
	elif o.has("w"):
		sc = float(o.w) / maxf(0.001, maxf(a.size.x, a.size.z))
	var ry: float = o.get("ry", rng.randf() * TAU)
	var y: float = o.get("y", 0.0)
	var bsize := a.size * sc
	U.set_shadows(p, bsize.y >= 1.2)
	if o.has("cull"):
		_cull(p, float(o.cull))
	var brk: String = o.get("brk", "")
	if not o.get("solid", false) and brk == "":
		p.scale = Vector3.ONE * sc
		p.position = Vector3(x, y - a.position.y * sc, z)
		p.rotation.y = ry
		parent.add_child(p)
		return p
	var bcentre := Vector3(a.get_center().x * sc, bsize.y * 0.5, a.get_center().z * sc)
	var body: StaticBody3D
	if brk != "":
		body = BreakScript.new()
		body.call("setup", brk, bsize, bcentre, float(o.get("brk_scale", 1.0)))
	else:
		body = StaticBody3D.new()
		body.set_meta("surface", o.get("surface", surface_for(n)))
	body.name = n
	body.collision_layer = 1 if bsize.y > 0.5 and o.get("collide", true) else SMALL_LAYER
	body.collision_mask = 0
	body.position = Vector3(x, y, z)
	body.rotation.y = ry
	p.scale = Vector3.ONE * sc
	p.position = Vector3(0, -a.position.y * sc, 0)
	body.add_child(p)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(maxf(bsize.x, 0.05), maxf(bsize.y, 0.05), maxf(bsize.z, 0.05))
	cs.shape = sh
	cs.position = bcentre
	body.add_child(cs)
	parent.add_child(body)
	return body

## the web's cull distances, as Godot visibility ranges
static func _cull(root: Node, dist: float) -> void:
	if root is GeometryInstance3D:
		(root as GeometryInstance3D).visibility_range_end = dist
		(root as GeometryInstance3D).visibility_range_end_margin = 4.0
	for c in root.get_children():
		_cull(c, dist)

## what a round sounds like on it, by name
static func surface_for(n: String) -> String:
	var l := n.to_lower()
	for k in ["metal", "can", "trash", "extinguisher", "hydrant", "desk", "chest", "toolbox", "cart", "pipe",
			"jerry", "payphone", "aircon", "ladder", "barrel", "register", "truck", "fence", "tyre"]:
		if l.contains(k):
			return "metal"
	for k in ["wood", "bench", "stool", "crate", "table", "chair", "shelf", "box", "plastic", "broom", "seating"]:
		if l.contains(k):
			return "wood"
	return "concrete"

## floorFree: clear of the gondola rows, the checkouts and the wall runs
static func floor_free(x: float, z: float, pad: float) -> bool:
	for rz in [-8.2, -2.9, 2.9, 8.2]:
		if absf(x) < 8.4 + pad and absf(z - rz) < 1.05 + pad:
			return false
	for cx in CHECKOUT_X:
		if absf(x - cx) < 2.2 + pad and absf(z - 11.6) < 1.3 + pad:
			return false
	if absf(x) > 20.2 - pad:
		return false
	return z >= -13.2 + pad

static func floor_spot(x0: float, x1: float, z0: float, z1: float, pad := 0.9) -> Array:
	for k in 40:
		var x := rng.randf_range(x0, x1)
		var z := rng.randf_range(z0, z1)
		if floor_free(x, z, pad):
			return [x, z]
	return []

# ------------------------------------------------------------------ the store

static func build_store(w: Node3D) -> void:
	U.fix_materials(U.glb(STORE))
	U.fix_materials(U.glb(EXTRA))
	U.fix_materials(U.glb(FURN))
	# the drop's display shelving on the aisle ends, and stock on the floor
	put(w, MAP2, "shelfdisp", -13.5, 5.4, {h = 1.86, ry = PI / 2, solid = true, brk = "crate"})
	put(w, MAP2, "shelfdisp", 13.5, 5.4, {h = 1.86, ry = -PI / 2, solid = true, brk = "crate"})
	put(w, MAP2, "shelfdisp", 0.0, -12.4, {h = 1.86, ry = 0.0, solid = true, brk = "crate"})
	for s in [[-6.4, 10.2], [7.1, 9.6], [-15.2, -9.4], [16.0, -10.1], [2.4, -13.6]]:
		put(w, MAP2, "steaktray", s[0], s[1], {w = 0.28, y = 0.02, cull = 90.0})
	for i in 14:
		put(w, MAP2, "sodacan", rng.randf_range(-19, 19), rng.randf_range(-13, 10), {h = 0.13, y = 0.01, cull = 80.0})
	put(w, MAP2, "cartboxes", -9.2, 12.4, {h = 1.0, ry = 0.6, solid = true})
	put(w, MAP2, "cartboxes", 10.6, 13.1, {h = 1.0, ry = -1.9, solid = true})

	# ph_store: tills on the checkouts, drums and boxes at the back, bottles
	for cx in CHECKOUT_X:
		put(w, STORE, "CashRegister_01", cx - 1.1, 11.9, {h = 0.34, y = 1.0, ry = PI, solid = true, brk = "crate"})
	for i in 3:
		put(w, STORE, ["Barrel_01", "Barrel_02", "barrel_03"][i], -20.5 + i * 1.6, -12.5, {h = 0.9, solid = true, brk = "crate", brk_scale = 1.6})
	for i in 3:
		put(w, STORE, ["CheeseBox_01", "cardboard_box_01", "boombox"][i], 12 + i * 1.7, -12.2, {h = 0.42, solid = true, brk = "crate"})
	var bottles := ["all_purpose_cleaner", "bleach_bottle", "can_rusted", "cleaner_tin_01"]
	for i in bottles.size():
		put(w, STORE, bottles[i], -6 + i * 1.7, 6.0, {h = 0.26, solid = true, brk = "glass", brk_scale = 0.8})

	# ph_extra: what a shop floor actually has on it
	var shop_floor := [["plastic_crate_01", {h = 0.42}], ["plastic_crate_02", {h = 0.42}], ["plastic_crate_03", {h = 0.40}],
		["plastic_container", {h = 0.44}], ["industrial_pastic_container", {h = 0.52}],
		["metal_trash_can", {h = 0.62}], ["plastic_broom", {h = 1.18}], ["dustpan", {w = 0.32}],
		["plastic_monobloc_chair_01", {h = 0.82}], ["hand_truck", {h = 1.24}], ["cement_bag", {w = 0.62}]]
	for e in shop_floor:
		for i in 3:
			var s := floor_spot(-19, 19, -12.5, 12.5)
			if not s.is_empty():
				var o: Dictionary = (e[1] as Dictionary).duplicate()
				o.merge({solid = true, brk = "crate", cull = 95.0})
				put(w, EXTRA, e[0], s[0], s[1], o)
	# stacked crates in the back corners, where a stockroom run would be
	for k in 4:
		var cx := -17.6 if k < 2 else 17.6
		var cz := -11.4 + (k % 2) * 1.5
		for s2 in 2 + rng.randi_range(0, 1):
			put(w, EXTRA, "plastic_crate_0%d" % (1 + s2 % 3), cx, cz,
				{h = 0.42, y = s2 * 0.42, ry = rng.randf_range(-0.3, 0.3), solid = s2 == 0, cull = 95.0})
	var cleaners := ["multi_cleaner_5_litre", "multi_cleaner_bottle", "drain_cleaner", "lubricant_spray", "plastic_bottle_gallon"]
	for i in 5:
		var s := floor_spot(-19, 19, -12, 12)
		if not s.is_empty():
			put(w, EXTRA, cleaners[i], s[0], s[1], {h = [0.30, 0.24, 0.24, 0.20, 0.30][i], cull = 80.0})
	for cx in CHECKOUT_X:
		# on the counter's packing end (the web's z 10.4 hung them in front of it)
		put(w, EXTRA, "office_notepads", cx + rng.randf_range(0.5, 1.0), 11.55, {w = 0.24, y = 1.0, cull = 70.0})
		if rng.randf() < 0.5:
			put(w, EXTRA, "clipboard", cx + rng.randf_range(0.4, 1.0), 11.3, {w = 0.24, y = 1.0, cull = 70.0})
		_screen(w, cx)
	# safety kit by the doors and on the walls, and a back office
	put(w, EXTRA, "korean_fire_extinguisher_01", -2.6, 12.9, {h = 0.62, cull = 90.0})
	put(w, EXTRA, "korean_fire_extinguisher_01", 2.6, 12.9, {h = 0.62, cull = 90.0})
	put(w, EXTRA, "medical_box", -20.0, -6.0, {w = 0.36, y = 1.5, ry = PI / 2, cull = 80.0})
	for f in [[-20.2, 4.0], [20.2, 4.0], [0.0, -13.4]]:
		put(w, EXTRA, "fire_alarm", f[0], f[1], {h = 0.22, y = 2.3, cull = 80.0})
	put(w, EXTRA, "metal_office_desk", 16.4, -12.6, {h = 0.76, ry = 0.2, solid = true, cull = 95.0})
	put(w, EXTRA, "metal_stool_01", 15.0, -12.0, {h = 0.68, solid = true, brk = "wood", cull = 95.0})
	for i in 3:
		put(w, FURN, ["WoodenChair_01", "SchoolChair_01", "GreenChair_01"][i], -18 + i * 1.9, -11.0,
			{h = 0.95, solid = true, brk = "wood", brk_scale = 0.5})
	for i in 8:
		var s := floor_spot(-18, 18, -11, 9, 0.7)
		if not s.is_empty():
			put(w, EXTRA, ["long_life_food", "lemon", "hamburger_buns"][i % 3], s[0], s[1],
				{h = [0.16, 0.07, 0.11][i % 3], y = 0.02, cull = 70.0})
	_floor_debris(w)

## a till screen on each checkout, on a post off the counter: one round
## and it is gone
static func _screen(w: Node3D, cx: float) -> void:
	var post := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.02
	pm.bottom_radius = 0.03
	pm.height = 0.2
	post.mesh = pm
	post.material_override = U.flat_mat(Color(0.2, 0.21, 0.22), 0.5, 0.6)
	post.position = Vector3(cx - 0.5, 1.1, 11.6)
	w.add_child(post)
	var b := BreakScript.new()
	b.name = "TillScreen"
	b.collision_layer = SMALL_LAYER
	b.position = Vector3(cx - 0.5, 1.34, 11.6)
	b.call("setup", "glass", Vector3(0.44, 0.32, 0.04), Vector3.ZERO, 0.6)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.44, 0.32, 0.04)
	mi.mesh = bm
	mi.material_override = U.emissive_mat(Color(0.08, 0.2, 0.09), 0.35)
	b.add_child(mi)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = bm.size
	cs.shape = sh
	b.add_child(cs)
	w.add_child(b)

## dropped paper, loose crates and tipped trolleys
static func _floor_debris(w: Node3D) -> void:
	var paper := [Color(0.85, 0.84, 0.8), Color(0.72, 0.62, 0.45), Color(0.6, 0.58, 0.55), Color(0.78, 0.76, 0.7)]
	for i in 20:
		var s := floor_spot(-20, 20, -13, 14, 0.15)
		if s.is_empty():
			continue
		var t := rng.randf_range(0.012, 0.035)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(rng.randf_range(0.12, 0.34), t, rng.randf_range(0.10, 0.28))
		mi.mesh = bm
		mi.material_override = U.flat_mat(paper[rng.randi() % 4], 0.95)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(s[0], t * 0.5, s[1])
		mi.rotation = Vector3(rng.randf_range(-0.05, 0.05), rng.randf() * TAU, rng.randf_range(-0.05, 0.05))
		w.add_child(mi)
	var card := U.flat_mat(Color(0.54, 0.42, 0.26), 0.95)
	for i in 8:
		var s := floor_spot(-19, 19, -13, 13, 0.5)
		if s.is_empty():
			continue
		var sz := Vector3(rng.randf_range(0.5, 0.9), rng.randf_range(0.4, 0.7), rng.randf_range(0.5, 0.8))
		var b := BreakScript.new()
		b.name = "Crate"
		b.collision_layer = 1 if sz.y > 0.5 else SMALL_LAYER
		b.position = Vector3(s[0], 0, s[1])
		b.rotation.y = rng.randf() * TAU
		b.call("setup", "crate", sz, Vector3(0, sz.y / 2, 0))
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = sz
		mi.mesh = bm
		mi.material_override = card
		mi.position.y = sz.y / 2
		b.add_child(mi)
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = sz
		cs.shape = sh
		cs.position.y = sz.y / 2
		b.add_child(cs)
		w.add_child(b)
	var cart := _cart_mesh()
	for c in [[-15.2, 4.4, true], [17.0, -11.0, false], [6.0, 13.4, false], [-9.0, -12.0, true], [15.4, 1.2, false]]:
		var mi := MeshInstance3D.new()
		mi.mesh = cart
		mi.position = Vector3(c[0], 0.52 if c[2] else 0.15, c[1])
		mi.rotation = Vector3(PI / 2 * 0.9 if c[2] else rng.randf_range(-0.1, 0.1), rng.randf() * TAU, 0.4 if c[2] else 0.0)
		w.add_child(mi)

## the web's wire trolley, merged into one mesh: 60-odd bars, one draw
static func _cart_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var W := 1.0
	var H := 0.5
	var D := 0.7
	var BAR := 0.022
	var bars := []
	for ux in [-W / 2, W / 2]:
		for uz in [-D / 2, D / 2]:
			bars.append([Vector3(BAR, H, BAR), Vector3(ux, H / 2, uz)])
	for ry2 in [H, 0.04]:
		bars.append([Vector3(W, BAR, BAR), Vector3(0, ry2, -D / 2)])
		bars.append([Vector3(W, BAR, BAR), Vector3(0, ry2, D / 2)])
		bars.append([Vector3(BAR, BAR, D), Vector3(-W / 2, ry2, 0)])
		bars.append([Vector3(BAR, BAR, D), Vector3(W / 2, ry2, 0)])
	for i in range(1, 6):
		var px := -W / 2 + i * (W / 6)
		bars.append([Vector3(BAR, H, BAR), Vector3(px, H / 2, -D / 2)])
		bars.append([Vector3(BAR, H, BAR), Vector3(px, H / 2, D / 2)])
	for i in range(1, 4):
		var pz := -D / 2 + i * (D / 4)
		bars.append([Vector3(BAR, H, BAR), Vector3(-W / 2, H / 2, pz)])
		bars.append([Vector3(BAR, H, BAR), Vector3(W / 2, H / 2, pz)])
	for i in range(1, 5):
		bars.append([Vector3(W, BAR, BAR), Vector3(0, 0.04, -D / 2 + i * (D / 5))])
	bars.append([Vector3(0.9, 0.06, 0.06), Vector3(0, 0.55, -0.4)])     # handle
	for b in bars:
		var bm := BoxMesh.new()
		bm.size = b[0]
		st.append_from(bm, 0, Transform3D(Basis.IDENTITY, b[1]))
	var wire := StandardMaterial3D.new()
	wire.albedo_color = Color("9aa0a3")
	wire.metallic = 0.75
	wire.roughness = 0.38
	st.set_material(wire)
	return st.commit()

# ------------------------------------------------------------------ outside

static func build_street(w: Node3D) -> void:
	U.fix_materials(U.glb(STREET))
	put(w, MAP2, "cartboxes", 22.0, 24.5, {h = 1.0, ry = 2.4, solid = true, cull = 140.0})
	# ph_street: concrete barriers and the junk on the pavement opposite TOPS
	var barrier := ["concrete_road_barrier", "concrete_road_barrier_02"]
	for i in 10:
		put(w, STREET, barrier[i % 2], -620 + i * 120, 41.0, {h = 0.9, ry = 0.0, solid = true, brk = "crate", brk_scale = 2.0, cull = 170.0})
	for i in 3:
		put(w, STREET, ["Camera_01", "Megaphone_01", "Television_01"][i], -14 + i * 9, 41.5, {h = 0.5, solid = true, brk = "glass"})
	# ph_extra: the lot and the town frontage
	for h in [[-24, 17.4], [24, 17.4], [-46, 44.2], [18, 44.2]]:
		put(w, EXTRA, "fire_hydrant", h[0], h[1], {h = 0.78, solid = true, cull = 130.0})
	for b in [[-30, 43.4], [-8, 43.4], [14, 43.4], [36, 43.4]]:
		put(w, EXTRA, "painted_wooden_bench", b[0], b[1], {h = 0.86, ry = PI, solid = true, brk = "wood", cull = 130.0})
		if rng.randf() < 0.6:
			put(w, EXTRA, "metal_trash_can", b[0] + 2.6, b[1], {h = 0.62, solid = true, cull = 130.0})
	for p in [[-19, 44.0], [27, 44.0]]:
		put(w, EXTRA, "planter_box_01", p[0], p[1], {h = 0.52, solid = true, cull = 130.0})
	put(w, EXTRA, "modular_street_seating", 5, 43.8, {h = 0.8, ry = PI, solid = true, cull = 130.0})
	put(w, EXTRA, "korean_public_payphone_01", -37, 43.6, {h = 1.5, ry = PI, solid = true, cull = 130.0})
	for a in [[-28, 43.2, 3.4], [10, 43.2, 5.1], [40, 43.2, 3.0]]:
		put(w, EXTRA, "exterior_aircon_unit", a[0], a[1], {h = 0.62, y = a[2], ry = PI, cull = 130.0})
	# the industrial belt: yards, pipes, a fuel stop
	var x := -330.0
	while x > -575.0:
		put(w, EXTRA, "modular_industrial_pipes_01", x + 8, 44.6, {h = 2.2, solid = true, cull = 150.0})
		put(w, EXTRA, "old_tyre", x - 6, rng.randf_range(28.4, 29.6), {h = 0.28, cull = 130.0})
		put(w, EXTRA, "old_tyre", x - 9, rng.randf_range(28.4, 29.6), {h = 0.28, y = 0.28, cull = 130.0})
		if rng.randf() < 0.7:
			put(w, EXTRA, "old_military_crate", x - 14, 28.8, {h = 0.62, solid = true, brk = "crate", cull = 150.0})
		if rng.randf() < 0.6:
			put(w, EXTRA, "cement_bag", x + 16, 44.2, {h = 0.26, cull = 130.0})
		if rng.randf() < 0.5:
			put(w, EXTRA, "industrial_storage_cart", x + 22, 44.0, {h = 1.0, solid = true, cull = 150.0})
		x -= 44.0
	for j in [[-397.0, 25.4, "metal_jerrycan"], [-399.5, 25.4, "metal_jerrycan_green"], [-406.0, 25.4, "plastic_jerrycan"]]:
		put(w, EXTRA, j[2], j[0], j[1], {h = 0.42, cull = 130.0})
	put(w, EXTRA, "ladder_sectioned_01", -412, 26.2, {h = 2.4, ry = 0.3, cull = 150.0})
	put(w, EXTRA, "metal_tool_chest", -415, 26.6, {h = 0.9, solid = true, cull = 150.0})
	put(w, EXTRA, "metal_toolbox", -418, 26.4, {h = 0.28, cull = 130.0})
	put(w, EXTRA, "compost_bags", -352, 44.4, {h = 0.5, cull = 130.0})
	x = -336.0
	while x > -570.0:
		put(w, EXTRA, "modular_chainlink_fence", x, 27.2, {h = 2.0, cull = 150.0})
		x -= 88.0

# ------------------------------------------------------------------ the mosque

static func build_mosque(m: Node3D) -> void:
	var q := func(lx: float, lz: float) -> Vector2: return Vector2(MQ.mqx(lx), MQ.mqz(lz))
	# the madrasa reading room, east of the corridor
	var chairs := ["SchoolChair_01", "WoodenChair_01", "SchoolChair_01", "WoodenChair_01"]
	for i in 4:
		var p: Vector2 = q.call(7.5 + (i % 2) * 2.2, 2.6 + floori(i / 2.0) * 2.6)
		put(m, FURN, chairs[i], p.x, p.y, {h = 0.95, solid = true, brk = "wood", brk_scale = 0.5})
	for i in 2:
		var p: Vector2 = q.call(13.5, 2.8 + i * 3.0)
		put(m, FURN, ["SchoolDesk_01", "WoodenTable_01"][i], p.x, p.y, {h = 0.76, solid = true, brk = "wood"})
	# the web stood these on top of the chairs (7.5, 5.0 vs 7.5, 5.2); the
	# east end of the room is clear
	for i in 4:
		var p: Vector2 = q.call(17.0 + (i % 2) * 2.4, 3.0 + floori(i / 2.0) * 2.6)
		put(m, EXTRA, "painted_wooden_stool", p.x, p.y, {h = 0.5, solid = true, brk = "wood", brk_scale = 0.5, cull = 130.0})
	# courtyard planters, the wudu jugs, a mirror and an extinguisher
	for o in [[-6.5, 15.5], [6.5, 15.5], [-6.5, 28.0], [6.5, 28.0]]:
		var p: Vector2 = q.call(o[0], o[1])
		put(m, EXTRA, "planter_pot_clay", p.x, p.y, {h = 0.66, solid = true, brk = "pottery", cull = 150.0})
	for i in 4:
		var p: Vector2 = q.call(-17 + i * 1.9, 2.4)
		put(m, EXTRA, "jug_01", p.x, p.y, {h = 0.32, solid = true, brk = "pottery", cull = 120.0})
	for i in 3:
		var p: Vector2 = q.call(15 + i * 1.6, 2.4)
		put(m, EXTRA, "metal_jug", p.x, p.y, {h = 0.30, cull = 120.0})
	for cz in [-6.0, -12.0]:
		var p: Vector2 = q.call(0.0, cz)
		put(m, EXTRA, "lantern_chandelier_01", p.x, p.y, {h = 1.3, y = 3.4, cull = 150.0})
	var mp: Vector2 = q.call(-22.6, -6.0)
	put(m, EXTRA, "ornate_mirror_01", mp.x, mp.y, {h = 1.4, y = 1.9, ry = PI / 2, cull = 130.0})
	var fp: Vector2 = q.call(3.2, 12.4)
	put(m, EXTRA, "korean_fire_extinguisher_01", fp.x, fp.y, {h = 0.62, cull = 130.0})
