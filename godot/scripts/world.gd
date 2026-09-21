## Builds the static world: the TOPS supermarket, the car park, the road and
## the street. Coordinates are lifted straight from dead-aisle.html - three.js
## and Godot are both right-handed, Y-up, -Z forward, so they carry over 1:1.
## Everything static lives under this NavigationRegion3D so the navmesh bake
## sees the colliders.
extends NavigationRegion3D

const U := preload("res://scripts/util.gd")

const WORLD_CX := -430.0
const SHELF_ROWS := [-8.2, -2.9, 2.9, 8.2]
const CHECKOUT_X := [-13.0, -4.5, 4.5, 13.0]
const SHELF_TIERS := [0.09, 0.65, 1.21]
const WALL_TIERS := [0.10, 0.52, 0.94, 1.36]

var M := {}
var rng := RandomNumberGenerator.new()

func build() -> void:
	rng.seed = 1337
	_materials()
	_ground()
	_store_shell()
	_storefront()
	_store_interior()
	_street()
	_setup_navmesh()

# ------------------------------------------------------------------ helpers

func box(size: Vector3, pos: Vector3, mat: Material, solid := true, rot_y := 0.0, parent: Node = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.rotation.y = rot_y
	if maxf(size.x, maxf(size.y, size.z)) < 1.6:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(parent if parent else self).add_child(mi)
	if solid:
		_collider(mi, size)
	return mi

func _collider(host: Node3D, size: Vector3, offset := Vector3.ZERO) -> StaticBody3D:
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	cs.position = offset
	sb.add_child(cs)
	host.add_child(sb)
	return sb

## an invisible collider on its own, for props whose meshes are too detailed
func solid(size: Vector3, pos: Vector3, rot_y := 0.0) -> void:
	var sb := StaticBody3D.new()
	sb.position = pos
	sb.rotation.y = rot_y
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	sb.add_child(cs)
	add_child(sb)

func plane(size: Vector2, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = size
	mi.mesh = pm
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi

## place a part from a model library: position, yaw, uniform scale. Keeps the
## part's own x/z rotation (as three.js does when you set rotation.y alone).
func place(lib: String, part_name: String, pos: Vector3, ry := 0.0, sc := 1.0, collide := false) -> Node3D:
	var p := U.part(lib, part_name)
	if p == null:
		return null
	p.position = pos
	p.rotation.y = ry
	if sc != 1.0:
		p.scale = Vector3(sc, sc, sc)
	add_child(p)
	if collide:
		var a := U.local_aabb(p)
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = a.size
		cs.shape = sh
		cs.position = a.get_center()
		sb.add_child(cs)
		p.add_child(sb)
	return p

func label(text: String, pos: Vector3, size_px: int, color: Color, ry := 0.0, outline := 0) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size_px
	l.pixel_size = 0.005
	l.modulate = color
	l.outline_size = outline
	l.position = pos
	l.rotation.y = ry
	l.double_sided = false
	l.shaded = true
	add_child(l)
	return l

# ------------------------------------------------------------------ materials

func _materials() -> void:
	var paint: Array = U.painted_block()
	var wall := StandardMaterial3D.new()
	wall.albedo_texture = paint[0]
	wall.normal_enabled = true
	wall.normal_texture = paint[1]
	wall.normal_scale = 0.35
	wall.albedo_color = Color(0.9, 0.9, 0.88)
	wall.roughness = 0.93
	wall.uv1_triplanar = true
	wall.uv1_world_triplanar = true
	wall.uv1_scale = Vector3(1.0 / 3.14, 1.0 / 2.5, 1.0 / 3.14)
	M.wall = wall

	var ceil := StandardMaterial3D.new()
	ceil.albedo_texture = U.ceiling_tile()
	ceil.albedo_color = Color(0.72, 0.72, 0.7)
	ceil.roughness = 1.0
	ceil.uv1_triplanar = true
	ceil.uv1_world_triplanar = true
	ceil.uv1_scale = Vector3(1.0 / 2.4, 1.0 / 2.4, 1.0 / 2.4)
	M.ceil = ceil

	M.floor = U.surface_mat("res://assets/tex/tiles2_c.jpg", "res://assets/tex/tiles2_n.jpg", "res://assets/tex/tiles2_r.jpg",
		Vector3(2.2, 2.2, 2.2), Color(0.62, 0.61, 0.58), 0.46, 0.05)
	M.road = U.surface_mat("res://assets/tex/road2_c.jpg", "res://assets/tex/road2_n.jpg", "res://assets/tex/road2_r.jpg",
		Vector3(5, 5, 5), Color(0.8, 0.8, 0.8), 0.85)
	M.lot = U.surface_mat("res://assets/tex/road2_c.jpg", "res://assets/tex/road2_n.jpg", "res://assets/tex/road2_r.jpg",
		Vector3(3.4, 3.4, 3.4), Color(0.72, 0.72, 0.72), 0.8)
	M.grass = U.surface_mat("res://assets/tex/grass2_c.jpg", "res://assets/tex/grass2_n.jpg", "",
		Vector3(2.8, 2.8, 2.8), Color(0.62, 0.66, 0.58), 1.0)
	M.dirt = U.surface_mat("res://assets/tex/ground2_c.jpg", "res://assets/tex/ground2_n.jpg", "",
		Vector3(4, 4, 4), Color(0.45, 0.44, 0.42), 1.0)
	M.brick = U.surface_mat("res://assets/tex/brick.jpg", "res://assets/tex/brick_n.jpg", "",
		Vector3(2.6, 1.6, 2.6), Color(0.85, 0.8, 0.76), 0.95)
	M.clad = U.surface_mat("res://assets/tex/wall.jpg", "res://assets/tex/wall_n.jpg", "",
		Vector3(3.2, 2.5, 3.2), Color(1.25, 1.25, 1.2), 0.92)
	M.walk = U.flat_mat(Color(0.52, 0.52, 0.5), 0.92)
	M.metal = U.flat_mat(Color(0.61, 0.63, 0.64), 0.4, 0.75)
	M.metal_dark = U.flat_mat(Color(0.34, 0.36, 0.37), 0.55, 0.6)
	M.board = U.flat_mat(Color(0.48, 0.37, 0.26), 0.95)
	M.paint = U.flat_mat(Color(0.86, 0.86, 0.84), 0.7)
	M.paint_y = U.flat_mat(Color(0.86, 0.66, 0.14), 0.7)
	M.red = U.flat_mat(Color(0.75, 0.08, 0.07), 0.6)
	M.dark = U.flat_mat(Color(0.09, 0.1, 0.11), 0.8)
	M.sign = U.flat_mat(Color(0.93, 0.93, 0.91), 0.5)
	M.tube = U.emissive_mat(Color(0.85, 0.95, 0.89), 3.0)
	M.tube_dead = U.flat_mat(Color(0.17, 0.19, 0.17), 0.9)
	M.fixture = U.flat_mat(Color(0.47, 0.49, 0.46), 0.6, 0.5)

# ------------------------------------------------------------------ ground

func _ground() -> void:
	# a catch-all underlay so nothing ever shows the void
	var under := plane(Vector2(1600, 600), Vector3(WORLD_CX, -0.03, 20), M.dirt)
	under.name = "Underlay"
	plane(Vector2(1240, 45.3), Vector3(WORLD_CX, 0.0, 37.85), M.grass).name = "Verge"
	plane(Vector2(48, 15), Vector3(0, 0.015, 22.5), M.lot).name = "Lot"
	plane(Vector2(1240, 8), Vector3(WORLD_CX, 0.018, 36), M.road).name = "Road"
	# one ground collider for everything
	var ground := StaticBody3D.new()
	ground.name = "GroundCollider"
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(1600, 1, 600)
	cs.shape = sh
	cs.position = Vector3(WORLD_CX, -0.5, 20)
	ground.add_child(cs)
	add_child(ground)

	# bay markings
	var x := -21.0
	while x <= 21.0:
		box(Vector3(0.14, 0.04, 4.4), Vector3(x, 0.04, 18.1), M.paint, false)
		x += 2.625
	box(Vector3(43, 0.04, 0.14), Vector3(0, 0.04, 20.5), M.paint, false)

	# centre-line dashes: one MultiMesh instead of two hundred nodes
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var dash := BoxMesh.new()
	dash.size = Vector3(2.6, 0.04, 0.18)
	dash.material = M.paint_y
	mm.mesh = dash
	var xs := []
	var dx := -1024.0
	while dx <= 164.0:
		xs.append(dx)
		dx += 6.0
	mm.instance_count = xs.size()
	for i in xs.size():
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(xs[i], 0.045, 36)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)

	# kerbs and pavements (the gap at x 6..18 is the driveway into the lot)
	for seg in [[-27, 66, 31.15, 1.5], [39, 42, 31.15, 1.5], [0, 120, 41.35, 2.5], [-190, 380, 41.35, 2.5], [120, 100, 41.35, 2.5]]:
		box(Vector3(seg[1], 0.14, seg[3]), Vector3(seg[0], 0.07, seg[2]), M.walk, false)

# ------------------------------------------------------------------ store shell

func _store_shell() -> void:
	var f := plane(Vector2(47, 33), Vector3(0, 0.004, 0), M.floor)
	f.name = "StoreFloor"
	box(Vector3(44, 0.3, 30), Vector3(0, 4.5, 0), M.ceil).name = "Ceiling"
	box(Vector3(0.4, 5, 30), Vector3(-22, 2.5, 0), M.wall)
	box(Vector3(0.4, 5, 30), Vector3(22, 2.5, 0), M.wall)
	box(Vector3(44, 5, 0.4), Vector3(0, 2.5, -15), M.wall)
	# front wall with the door gap at x -2..2
	box(Vector3(20, 5, 0.4), Vector3(-12, 2.5, 15), M.wall)
	box(Vector3(20, 5, 0.4), Vector3(12, 2.5, 15), M.wall)
	box(Vector3(4.6, 1.6, 0.45), Vector3(0, 4.2, 15), M.wall)
	for dxp in [-2.1, 2.1]:
		box(Vector3(0.25, 3.4, 0.5), Vector3(dxp, 1.7, 15), M.metal_dark)
	# the boarded-up shop windows, both faces
	for wx in [-16.0, -8.0, 8.0, 16.0]:
		for side in [-1, 1]:
			var z: float = 15.0 + side * 0.26
			box(Vector3(5, 1.2, 0.08), Vector3(wx, 4.4, z), M.clad, false)
			box(Vector3(1.4, 3.8, 0.08), Vector3(wx - 1.8, 1.9, z), M.clad, false)
			box(Vector3(1.4, 3.8, 0.08), Vector3(wx + 1.8, 1.9, z), M.clad, false)
			for k in 3:
				var b := box(Vector3(4.2, 0.9, 0.05), Vector3(wx, 1.0 + k * 1.05, z + side * 0.04), M.board, false)
				b.rotation.z = rng.randf_range(-0.05, 0.05)

	# fluorescent rig: on/off pattern straight from the web build
	var tubes := [[-14, -10, true], [-14, 0, true], [-14, 10, true], [0, -10, true], [0, 0, false],
		[0, 10, true], [14, -10, false], [14, 0, true], [14, 10, true]]
	for i in 6:
		tubes.append([rng.randf_range(-20, 20), rng.randf_range(-13, 13), false])
	for t in tubes:
		_tube(Vector3(t[0], 4.15, t[1]), t[2])

func _tube(pos: Vector3, on: bool) -> void:
	var g := Node3D.new()
	g.position = pos
	add_child(g)
	var fx := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(2.4, 0.06, 0.34)
	fx.mesh = bm
	fx.material_override = M.fixture
	fx.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.add_child(fx)
	var tube := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(2.2, 0.05, 0.2)
	tube.mesh = tm
	tube.position.y = -0.05
	tube.material_override = M.tube if on else M.tube_dead
	tube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if not on:
		tube.rotation.z = rng.randf_range(-0.06, 0.06)
	g.add_child(tube)
	if on:
		var l := OmniLight3D.new()
		l.light_color = Color(0.81, 0.91, 0.85)
		l.light_energy = 1.3
		l.omni_range = 15.0
		l.omni_attenuation = 1.2
		l.position.y = -0.4
		l.add_to_group("tubes")
		g.add_child(l)
		g.add_to_group("tube_fixtures")

# ------------------------------------------------------------------ storefront

func _storefront() -> void:
	# parapet, accent stripe and the TOPS sign
	box(Vector3(45, 1.5, 1.2), Vector3(0, 5.75, 15.3), M.clad, false)
	box(Vector3(45, 0.35, 0.1), Vector3(0, 4.75, 15.95), M.red, false)
	box(Vector3(14, 2.6, 0.3), Vector3(0, 6.6, 15.55), M.sign, false)
	box(Vector3(14.3, 0.18, 0.34), Vector3(0, 5.25, 15.56), M.red, false)
	var tops := label("TOPS", Vector3(0, 6.6, 15.72), 330, Color(0.86, 0.1, 0.09))
	tops.shaded = false
	# pilasters
	for px in [-21.0, -12.0, -4.6, 4.6, 12.0, 21.0]:
		box(Vector3(1.1, 4.9, 0.7), Vector3(px, 2.45, 15.3), M.clad, false)
	# entrance canopy on two posts
	box(Vector3(9.4, 0.35, 3.2), Vector3(0, 3.62, 16.7), M.dark, false)
	box(Vector3(9.4, 0.22, 0.22), Vector3(0, 3.4, 18.24), M.red, false)
	for cx in [-4.4, 4.4]:
		box(Vector3(0.16, 3.5, 0.16), Vector3(cx, 1.75, 18.2), M.dark)
	var canopy_l := SpotLight3D.new()
	canopy_l.position = Vector3(0, 3.4, 17.2)
	canopy_l.rotation_degrees = Vector3(-90, 0, 0)
	canopy_l.light_color = Color(1, 0.9, 0.75)
	canopy_l.light_energy = 3.0
	canopy_l.spot_range = 9.0
	canopy_l.spot_angle = 55.0
	add_child(canopy_l)
	# bollards and the apron
	for bx in [-3.2, -1.2, 1.2, 3.2]:
		var b := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.13
		cm.bottom_radius = 0.13
		cm.height = 1.04
		b.mesh = cm
		b.material_override = M.red
		b.position = Vector3(bx, 0.52, 17.6)
		add_child(b)
		_collider(b, Vector3(0.26, 1.04, 0.26))
	box(Vector3(44, 0.06, 1.6), Vector3(0, 0.03, 15.9), M.walk, false)
	# EXIT sign over the doors, inside
	box(Vector3(0.95, 0.36, 0.14), Vector3(0, 3.15, 14.42), U.emissive_mat(Color(0.1, 0.72, 0.35), 1.6), false)
	var ex := label("EXIT", Vector3(0, 3.15, 14.34), 64, Color(0.4, 1, 0.6), PI)
	ex.shaded = false

# ------------------------------------------------------------------ store interior

func _store_interior() -> void:
	var props := "res://assets/props.glb"
	var sp := "res://assets/storeprops.glb"
	U.fix_materials(U.glb(props))
	U.fix_materials(U.glb(sp))
	U.fix_materials(U.glb("res://assets/cstore.glb"))
	# the props pack's retail orange blows out under the tubes; the web build
	# pulled it down to 55%
	var dimmed := {}
	for n in U.glb(props).find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(i)
			if mat is StandardMaterial3D and not dimmed.has(mat):
				dimmed[mat] = true
				var sm := mat as StandardMaterial3D
				sm.albedo_color = sm.albedo_color * Color(0.55, 0.55, 0.55, 1)
				sm.roughness = maxf(sm.roughness, 0.8)

	var stock := StockBuilder.new(self, rng)
	# gondola rows: five units a side, mounted back to back
	for rz in SHELF_ROWS:
		solid(Vector3(15, 2.2, 1.5), Vector3(0, 1.1, rz))
		for i in 5:
			for side in [[0.30, 0.0], [-0.30, PI]]:
				place(props, "shelf_step", Vector3(-7.5 + 1.46 + i * 2.95, 0, rz + side[0]), side[1])
		for face in [-1, 1]:
			for tier in SHELF_TIERS:
				var x := -7.25
				while x < 7.3:
					stock.add(Vector3(x, tier, rz + face * 0.46), rng.randf_range(0, TAU), 0.2)
					x += rng.randf_range(0.2, 0.34)

	# industrial wall shelving: back wall and both side walls
	var units := []
	var bx := -19.0
	while bx <= 19.0:
		units.append([Vector3(bx, 0, -14.0), 0.0])
		bx += 2.75
	var sz := -11.0
	while sz <= 6.0:
		units.append([Vector3(-21.2, 0, sz), PI / 2])
		units.append([Vector3(21.2, 0, sz), -PI / 2])
		sz += 2.75
	for u in units:
		place(sp, "shelf0", u[0], u[1])
		var basis := Basis(Vector3.UP, u[1])
		for tier in WALL_TIERS:
			if rng.randf() < 0.1:
				continue   # the odd bare shelf
			var lx := -1.05
			while lx < 1.0:
				var p: Vector3 = u[0] + basis * Vector3(lx, tier, 0.10 + rng.randf_range(-0.03, 0.03))
				stock.add(p, rng.randf_range(0, TAU), 0.22)
				lx += rng.randf_range(0.24, 0.42)
	solid(Vector3(41.5, 2.2, 0.6), Vector3(0, 1.1, -14.0))
	solid(Vector3(0.6, 2.2, 20.2), Vector3(-21.2, 1.1, -2.5))
	solid(Vector3(0.6, 2.2, 20.2), Vector3(21.2, 1.1, -2.5))

	# checkout line
	for cx in CHECKOUT_X:
		place(sp, "desk0", Vector3(cx, 0, 11.6), PI)
		solid(Vector3(3.4, 1.0, 1.4), Vector3(cx, 0.5, 11.6))
	# deli and bakery cases down the west wall, the cashier on the east
	for d in [["case_a", -19.6, -2.0, PI / 2], ["case_a", -19.6, 1.6, PI / 2], ["counter_sm", -19.6, 4.8, PI / 2],
			["cashier", 18.9, -5.5, -PI / 2], ["case_b", 18.5, 6.0, -PI / 2], ["case_b", -18.5, 6.0, PI / 2]]:
		place(props, d[0], Vector3(d[1], 0, d[2]), d[3], 1.0, true)

	stock.finish()

	# hanging aisle signs
	var rows := [[-8.2, "AISLE 1", Color(1, 0.84, 0.42)], [-2.9, "DEALS", Color(1, 0.32, 0.22)],
		[2.9, "FROZEN", Color(0.62, 0.85, 0.91)], [8.2, "CHECKOUT", Color(0.49, 0.86, 0.53)]]
	var sx := [-6.0, 5.5, -5.5, 6.0]
	for i in 4:
		var base := Vector3(sx[i], 3.6, rows[i][0])
		box(Vector3(2.3, 0.58, 0.05), base, M.dark, false)
		for s in [-1, 1]:
			var l := label(rows[i][1], base + Vector3(0, 0, s * 0.03), 80, rows[i][2], 0.0 if s > 0 else PI)
			l.shaded = false
		for wx in [-0.95, 0.95]:
			box(Vector3(0.012, 0.47, 0.012), base + Vector3(wx, 0.52, 0), M.dark, false)

# ------------------------------------------------------------------ street

const FACADES := ["wP_Facade_A", "wP_Facade_B", "wP_Facade_C", "wP_Facade_D", "wP_Facade_E", "wP_Facade_G"]

func _street() -> void:
	var lib := "res://assets/street.glb"
	U.fix_materials(U.glb(lib))
	var dims := {}
	for n in FACADES:
		var src := U.glb(lib).find_child(n, true, false) as Node3D
		if src:
			dims[n] = U.local_aabb(src)
	_facade_row(lib, dims, -72, 72, 46.6, -1, 0.55)
	_facade_row(lib, dims, -124, -34, 25.5, 1, 0.5)
	_facade_row(lib, dims, 34, 124, 25.5, 1, 0.5)

	var sx := -110.0
	while sx <= 110.0:
		if absf(sx) >= 24:
			place(lib, "wP_Lampost1", Vector3(sx, 0, 40.6))
			var head := OmniLight3D.new()
			head.position = Vector3(sx, 5.1, 40.0)
			head.light_color = Color(1, 0.75, 0.5)
			head.light_energy = 1.2
			head.omni_range = 16.0
			add_child(head)
			if rng.randf() < 0.6:
				place(lib, "wP_Bench", Vector3(sx + rng.randf_range(-5, 5), 0, 41.5), rng.randf_range(0, TAU))
		sx += 26.0
	var trees := ["wP_Tree_001", "wP_Tree_002", "wP_Tree_003", "wP_Tree_004"]
	var tx := -118.0
	while tx <= 118.0:
		if absf(tx) >= 28:
			place(lib, trees[rng.randi() % 4], Vector3(tx + rng.randf_range(-3, 3), 0, 42.0 + rng.randf_range(-1.5, 1.5)),
				rng.randf_range(0, TAU), rng.randf_range(0.55, 0.85))
		tx += 17.0

## Lay facades edge to edge along a frontage, each placed by its OWN bounds:
## left edge on the cursor, front face on the line, base on the ground. The
## prefab pivots are all over the place. A brick block sits behind each one
## so it reads as a building rather than a cardboard cut-out.
func _facade_row(lib: String, dims: Dictionary, x0: float, x1: float, z_front: float, facing: int, sc: float) -> void:
	var ry := PI if facing < 0 else 0.0
	var x := x0
	var i := posmod(int(x0 * 7), FACADES.size())
	while x < x1:
		var n: String = FACADES[i % FACADES.size()]
		i += 1
		if not dims.has(n):
			x += 14.0
			continue
		var d: AABB = dims[n]
		var w := d.size.x * sc
		var h := d.size.y * sc
		if x + w > x1 + 6:
			break
		var px := (x + d.end.x * sc) if facing < 0 else (x - d.position.x * sc)
		var pz := (z_front + d.end.z * sc) if facing < 0 else (z_front - d.end.z * sc)
		var f := place(lib, n, Vector3(px, -d.position.y * sc, pz), ry, sc)
		if f:
			var back := box(Vector3(w * 0.99, h * 0.97, 13), Vector3(x + w / 2, h * 0.485, z_front - facing * 10), M.brick)
			back.name = "FacadeBack"
		x += w + 0.3

# ------------------------------------------------------------------ navigation

func _setup_navmesh() -> void:
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	nm.agent_radius = 0.45
	nm.agent_height = 1.8
	nm.agent_max_climb = 0.3
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	# only the fight: the store, the lot and the street in front of it
	nm.filter_baking_aabb = AABB(Vector3(-32, -1, -18), Vector3(64, 5, 58))
	navigation_mesh = nm

func bake_nav() -> void:
	bake_navigation_mesh(true)


## Groceries on the shelves, batched into one MultiMesh per product so a few
## thousand items cost a couple of dozen draws.
class StockBuilder:
	var host: Node3D
	var rng: RandomNumberGenerator
	var items := []          # [{mesh, xf, h}]
	var buckets := {}        # index -> Array[Transform3D]

	func _init(h: Node3D, r: RandomNumberGenerator) -> void:
		host = h
		rng = r
		for lib in ["res://assets/food.glb", "res://assets/cstore.glb"]:
			var root := U.glb(lib)
			if root == null:
				continue
			U.fix_materials(root)
			for c in root.get_children():
				var cname := str(c.name)
				if cname.begins_with("cs_"):
					continue
				var mi: MeshInstance3D = c if c is MeshInstance3D else c.find_child("*", true, false) as MeshInstance3D
				if mi == null or mi.mesh == null:
					for d in c.find_children("*", "MeshInstance3D", true, false):
						mi = d
						break
				if mi == null or mi.mesh == null:
					continue
				var a := mi.mesh.get_aabb()
				if a.size.y <= 0.0001:
					continue
				items.append({"mesh": mi.mesh, "aabb": a})

	func add(pos: Vector3, ry: float, target_h: float) -> void:
		if items.is_empty():
			return
		var idx := rng.randi() % items.size()
		var it: Dictionary = items[idx]
		var a: AABB = it.aabb
		var s := target_h * rng.randf_range(0.8, 1.25) / a.size.y
		var basis := Basis(Vector3.UP, ry).scaled(Vector3(s, s, s))
		# seat the item by its own bounds on the shelf deck
		var origin := pos - basis * Vector3(a.get_center().x, a.position.y, a.get_center().z)
		if not buckets.has(idx):
			buckets[idx] = []
		buckets[idx].append(Transform3D(basis, origin))

	func finish() -> void:
		for idx in buckets:
			var xfs: Array = buckets[idx]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = items[idx].mesh
			mm.instance_count = xfs.size()
			for i in xfs.size():
				mm.set_instance_transform(i, xfs[i])
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			host.add_child(mmi)
