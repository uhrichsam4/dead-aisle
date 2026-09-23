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
	_highway()
	var Props := preload("res://scripts/props.gd")
	Props.build_store(self)
	Props.build_street(self)
	preload("res://scripts/town.gd").build(self)
	preload("res://scripts/street_detail.gd").build(self)
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
		_collider(mi, size).set_meta("surface", _surface_of(mat))
	return mi

## what a round sounds like when it hits this material
func _surface_of(mat: Material) -> String:
	if mat == M.get("board"):
		return "wood"
	if mat in [M.get("metal"), M.get("metal_dark"), M.get("fixture"), M.get("red"), M.get("dark")]:
		return "metal"
	return "concrete"

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
func solid(size: Vector3, pos: Vector3, rot_y := 0.0, surface := "metal") -> void:
	var sb := StaticBody3D.new()
	sb.set_meta("surface", surface)
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
		sb.set_meta("surface", "metal")
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

	# the procedural tile layout over the scanned tile's relief
	var ceil := U.cc0("OfficeCeiling001", 3.6, Color(0.74, 0.74, 0.72), 1.0)
	ceil.albedo_texture = U.ceiling_tile()
	M.ceil = ceil

	M.floor = U.surface_mat("res://assets/tex/tiles2_c.jpg", "res://assets/tex/tiles2_n.jpg", "res://assets/tex/tiles2_r.jpg",
		Vector3(2.2, 2.2, 2.2), Color(0.62, 0.61, 0.58), 0.46, 0.05)
	# ambientCG scans: the road is the older, crazed surface; the lot a newer
	# seal. Both a touch lifted - raw asphalt under ACES reads as a hole
	M.road = U.cc0("Asphalt026C", 4.0, Color(1.12, 1.1, 1.06), 1.0)
	M.lot = U.cc0("Asphalt025C", 3.2, Color(1.15, 1.15, 1.12), 1.0)
	# the scans' roughness maps are a wet road's: dry, worn asphalt is matte
	U.even_rough(M.road, 0.93)
	U.even_rough(M.lot, 0.93)
	M.grass = U.even_rough(U.cc0("Grass004", 2.4, Color(0.82, 0.84, 0.72)), 1.0)
	M.dirt = U.surface_mat("res://assets/tex/ground2_c.jpg", "res://assets/tex/ground2_n.jpg", "",
		Vector3(4, 4, 4), Color(0.45, 0.44, 0.42), 1.0)
	# the facade back blocks: weathered red brick, about a 1.2 m repeat
	M.brick = U.cc0("Bricks097", 1.3, Color(0.86, 0.84, 0.82), 1.0)
	# the storefront parapet, pilasters and window surrounds
	M.clad = U.cc0("Bricks085", 1.2, Color(0.9, 0.86, 0.82), 1.0)       # the web's MAT_WALL
	# pavements and the apron: broom-finished concrete; kerb stones precast
	M.walk = U.cc0("Concrete042A", 2.4, Color(1.18, 1.16, 1.12), 1.0)
	M.kerb = U.cc0("Concrete012", 1.6, Color(0.95, 0.94, 0.9), 1.0)
	M.metal = U.cc0("Metal024", 1.2, Color(0.9, 0.92, 0.94), 1.0, 0.45)
	M.metal_dark = U.cc0("Metal024", 1.2, Color(0.5, 0.52, 0.54), 1.0, 0.4)
	# weathered plywood on the windows, greyed by the sun
	M.board = U.cc0("Wood087", 1.2, Color(0.56, 0.48, 0.39), 1.0)
	# road paint takes the asphalt's relief and roughness so it reads worn
	M.paint = U.surface_mat("", "res://assets/cc0/Asphalt025C/Asphalt025C_1K-JPG_NormalGL.jpg",
		"", Vector3(3.2, 3.2, 3.2), Color(0.74, 0.74, 0.71), 0.9)
	M.paint_y = U.surface_mat("", "res://assets/cc0/Asphalt025C/Asphalt025C_1K-JPG_NormalGL.jpg",
		"", Vector3(3.2, 3.2, 3.2), Color(0.8, 0.6, 0.14), 0.9)
	# chipped enamel over steel: the canopy, its posts, the bollards
	M.red = U.cc0("PaintedMetal010", 1.4, Color(0.78, 0.09, 0.08), 1.0, 0.15)
	M.dark = U.cc0("PaintedMetal010", 1.4, Color(0.13, 0.14, 0.15), 1.0, 0.15)
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
	ground.set_meta("surface", "concrete")
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
	# the north pavement runs the whole road; the south kerb breaks for the
	# TOPS driveway (x 6..18) and the mosque gate (x -903..-897)
	box(Vector3(1200, 0.14, 2.5), Vector3(-430, 0.07, 41.35), M.walk, false)
	_kerb(-430, 1200, 40.19)
	for seg in [[-27, 66, 31.15, 1.5], [39, 42, 31.15, 1.5], [-477.5, 835, 31.15, 1.5], [-966.5, 127, 31.15, 1.5]]:
		box(Vector3(seg[1], 0.14, seg[3]), Vector3(seg[0], 0.07, seg[2]), M.walk, false)
		_kerb(seg[0], seg[1], 31.81)
		_kerb(seg[0], seg[1], 30.49)

## a precast kerb line proud of the pavement edge by a centimetre, so the
## pavement reads as a slab on a kerb rather than one white block. Visual only
func _kerb(cx: float, length: float, z: float) -> void:
	var k := box(Vector3(length + 0.02, 0.16, 0.2), Vector3(cx, 0.08, z), M.kerb, false)
	k.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

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
	# its street face in the storefront brick, not the painted block inside
	for sx in [-12.0, 12.0]:
		# 15.235: clear of the door header's face at 15.225, which it overlaps by 0.3 m
		box(Vector3(20, 5, 0.02), Vector3(sx, 2.5, 15.235), M.clad, false)
	box(Vector3(4.6, 1.6, 0.45), Vector3(0, 4.2, 15), M.wall)
	for dxp in [-2.1, 2.1]:
		box(Vector3(0.25, 3.4, 0.5), Vector3(dxp, 1.7, 15), M.metal_dark)
	# the boarded-up shop windows, both faces
	var nails: Array[Transform3D] = []
	# the nails get their own generator: drawing from `rng` here shifted every
	# random placement after it (stock, props) and moved the whole layout
	var nrng := RandomNumberGenerator.new()
	nrng.seed = 77
	for wx in [-16.0, -8.0, 8.0, 16.0]:
		for side in [-1, 1]:
			var z: float = 15.0 + side * 0.26
			box(Vector3(5, 1.2, 0.08), Vector3(wx, 4.4, z), M.clad, false)
			box(Vector3(1.4, 3.8, 0.08), Vector3(wx - 1.8, 1.9, z), M.clad, false)
			box(Vector3(1.4, 3.8, 0.08), Vector3(wx + 1.8, 1.9, z), M.clad, false)
			for k in 3:
				var b := box(Vector3(4.2, 0.9, 0.05), Vector3(wx, 1.0 + k * 1.05, z + side * 0.04), M.board, false)
				b.rotation.z = rng.randf_range(-0.05, 0.05)
				# nail heads along the studs, on the face you see
				for nx in [-1.95, -0.65, 0.65, 1.95]:
					for ny in [-0.33, 0.33]:
						var off := Vector3(nx + nrng.randf_range(-0.03, 0.03), ny + nrng.randf_range(-0.02, 0.02), side * 0.027)
						nails.append(Transform3D(Basis(Vector3.RIGHT, PI / 2), b.transform * off))
	_nails(nails)

	# fluorescent rig: on/off pattern straight from the web build
	var tubes := [[-14, -10, true], [-14, 0, true], [-14, 10, true], [0, -10, true], [0, 0, false],
		[0, 10, true], [14, -10, false], [14, 0, true], [14, 10, true]]
	for i in 6:
		tubes.append([rng.randf_range(-20, 20), rng.randf_range(-13, 13), false])
	for t in tubes:
		_tube(Vector3(t[0], 4.15, t[1]), t[2])

## every nail in the boarding as one MultiMesh: a couple of hundred heads, one draw
func _nails(xfs: Array[Transform3D]) -> void:
	var head := CylinderMesh.new()
	head.top_radius = 0.011
	head.bottom_radius = 0.011
	head.height = 0.008
	head.radial_segments = 8
	head.rings = 1
	head.material = U.flat_mat(Color(0.2, 0.17, 0.15), 0.55, 0.6)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = head
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = 40.0
	add_child(mmi)

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
		# the web's PointLight(0xcfe8d8, 44, 22, 1.7): a strong tube reaching
		# the whole bay, which is what lifts the orange aisles
		l.light_energy = 2.6
		l.omni_range = 22.0
		l.omni_attenuation = 1.0
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
				# .55 in LINEAR, as three.js did it; on the sRGB value it came out
				# at a quarter and the orange aisles read as dark brown
				var lin := sm.albedo_color.srgb_to_linear()
				sm.albedo_color = Color(lin.r * 0.55, lin.g * 0.55, lin.b * 0.55, lin.a).linear_to_srgb()
				sm.roughness = maxf(sm.roughness, 0.8)

	var stock := StockBuilder.new(self, rng)
	# gondola rows: five units a side, mounted back to back
	for rz in SHELF_ROWS:
		solid(Vector3(15, 2.2, 1.5), Vector3(0, 1.1, rz))
		for i in 5:
			for side in [[0.30, 0.0], [-0.30, PI]]:
				place(props, "shelf_step", Vector3(-7.5 + 1.46 + i * 2.95, 0, rz + side[0]), side[1])
		# the web's block slots (.28-.6 wide), each filled with a cluster of
		# two to four goods rather than one lonely cupcake
		for face in [-1, 1]:
			for tier in SHELF_TIERS:
				var x := -7.0
				while x < 7.1:
					var w := rng.randf_range(0.28, 0.6)
					var n := 2 + rng.randi() % 3
					for k in n:
						var px := x + (k - (n - 1) / 2.0) * rng.randf_range(0.13, 0.2)
						stock.add(Vector3(px, tier, rz + face * (0.46 + rng.randf_range(-0.05, 0.05))), rng.randf_range(0, TAU), 0.0)
					x += w + rng.randf_range(0.06, 0.2)

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
				stock.add(p, rng.randf_range(0, TAU), 0.0, true)
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
			var l := label(rows[i][1], base + Vector3(0, 0, s * 0.04), 56, rows[i][2], 0.0 if s > 0 else PI)
			l.shaded = false
		for wx in [-0.95, 0.95]:
			box(Vector3(0.012, 0.47, 0.012), base + Vector3(wx, 0.52, 0), M.dark, false)

# ------------------------------------------------------------------ street

const FACADES := ["wP_Facade_A", "wP_Facade_B", "wP_Facade_C", "wP_Facade_D", "wP_Facade_E", "wP_Facade_G"]

func _street() -> void:
	var lib := "res://assets/street.glb"
	U.fix_materials(U.glb(lib))
	_facade_look(U.glb(lib))
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

## The facade prefabs' own materials, made to hold up at 0.5 render scale:
##  - mirror-smooth opaque walls (roughness 0, no map) sparkled into grey
##    noise under FSR - they get a real roughness
##  - their UVs run 20-110 repeats a metre, so the big flat-coloured walls get
##    a world-triplanar render and relief instead, tinted by their own colour
##  - the glass was alpha 0 (invisible), so the windows read as black holes;
##    it gets a dark, faintly reflective tint
##  - Facade_A is an open fire-escape frame with no wall: its pale rails
##    over the brick block behind were the "glitchy grey" facades. They are
##    painted iron now, and _facade_row puts a wall right behind the frame
const FACADE_WALLS := ["stone 1", "stone dark", "walls a", "walls darker", "wall grey", "stone wht",
	"wall stone panels", "white ceiling panels", "seal", "seal ss"]

func _facade_look(lib: Node) -> void:
	if lib == null:
		return
	var seen := {}
	for fname in FACADES:
		var f := lib.find_child(fname, true, false)
		if f == null:
			continue
		for mi in f.find_children("*", "MeshInstance3D", true, false) + ([f] if f is MeshInstance3D else []):
			var mesh: Mesh = (mi as MeshInstance3D).mesh
			if mesh == null:
				continue
			for i in mesh.get_surface_count():
				var m := mesh.surface_get_material(i) as StandardMaterial3D
				if m == null or seen.has(m):
					continue
				seen[m] = true
				var n := m.resource_name.to_lower().strip_edges()
				var glassy := m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED and (n.contains("gl") or n.contains("glass"))
				if glassy:
					# the importer made these scissor cutouts at alpha 0: blend them
					m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					m.albedo_color = Color(0.045, 0.055, 0.065, maxf(m.albedo_color.a, 0.62))
					m.roughness = 0.06
					m.metallic = 0.0
					m.metallic_specular = 0.7
					continue
				if n.begins_with("interior") or n == "inteiror":
					# the room behind the glass: dim and matte, not a black mirror
					m.albedo_color = Color(0.07, 0.065, 0.06)
					m.roughness = 1.0
					continue
				if fname == "wP_Facade_A" and (n == "metal rail" or n == "ss" or n == "metal dark"):
					m.albedo_color = Color(0.09, 0.09, 0.095)
					m.metallic = 0.3
					m.roughness = 0.62
					continue
				if m.roughness_texture == null and m.roughness < 0.35:
					m.roughness = 0.35 if m.metallic > 0.5 else 0.55
				if m.albedo_texture == null and n in FACADE_WALLS:
					var c := m.albedo_color
					var plaster := U.cc0("Plaster007", 2.6)
					m.albedo_texture = plaster.albedo_texture
					m.normal_enabled = true
					m.normal_texture = plaster.normal_texture
					m.normal_scale = 0.7
					m.roughness_texture = plaster.roughness_texture
					m.roughness = 1.0
					# Plaster007 is near white (mean ~.8): lift the tint to keep the
					# prefab's own shade
					m.albedo_color = Color(minf(c.r * 1.2, 1.0), minf(c.g * 1.2, 1.0), minf(c.b * 1.2, 1.0), c.a)
					m.uv1_triplanar = true
					m.uv1_world_triplanar = true
					m.uv1_scale = Vector3.ONE / 2.6
					m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC

## The 900 m west to the mosque. Frontages both sides from the town's own
## facade models, pulled in close to the road so they stay in the in-car view
## (the web build found a sparse row at the town's setback read as empty
## verge), with gaps so it does not read as one endless terrace; lamp posts,
## trees, and the roadside dressing from the web build's own props pack.
func _highway() -> void:
	var lib := "res://assets/street.glb"
	var dims := {}
	for n in FACADES:
		var src := U.glb(lib).find_child(n, true, false) as Node3D
		if src:
			dims[n] = U.local_aabb(src)
	# frontages in runs, broken for vacant lots and kept clear of the mosque
	var x := -842.0
	while x < -140.0:
		var run := rng.randf_range(60.0, 140.0)
		var end := minf(x + run, -140.0)
		_facade_row(lib, dims, x, end, 43.4, -1, rng.randf_range(0.45, 0.55))
		if not (x < -860.0 and end > -940.0):
			_facade_row(lib, dims, x, end, 30.0, 1, rng.randf_range(0.42, 0.5))
		x = end + rng.randf_range(18.0, 45.0)
	var sx := -136.0
	while sx > -1020.0:
		place(lib, "wP_Lampost1", Vector3(sx, 0, 40.6))
		sx -= 38.0
	var trees := ["wP_Tree_001", "wP_Tree_002", "wP_Tree_003", "wP_Tree_004"]
	var tx := -150.0
	while tx > -1010.0:
		if absf(tx + 900.0) > 34.0:
			place(lib, trees[rng.randi() % 4], Vector3(tx + rng.randf_range(-4, 4), 0, 42.0 + rng.randf_range(-1.0, 1.0)),
				rng.randf_range(0, TAU), rng.randf_range(0.5, 0.8))
		tx -= rng.randf_range(22.0, 36.0)
	_map2()

## the web build's supplied roadside set: a liquor store on the way out of
## town, dead trees, grass tufts, boulders, rubble and culverts in the
## industrial belt, and a few people standing about
func _map2() -> void:
	var lib := "res://assets/map2.glb"
	var root := U.glb(lib)
	if root == null:
		return
	U.fix_materials(root)
	var P := func(n: String, x: float, z: float, h: float, ry := -1.0, y := 0.0, collide := false):
		var p := U.part(lib, n)
		if p == null:
			return
		p.position = Vector3.ZERO
		p.rotation = Vector3.ZERO
		p.scale = Vector3.ONE
		var a := U.local_aabb(p)
		var s := h / maxf(0.001, a.size.y)
		p.scale = Vector3.ONE * s
		p.position = Vector3(x, y - a.position.y * s, z)
		p.rotation.y = ry if ry >= 0.0 else rng.randf_range(0, TAU)
		add_child(p)
		if collide:
			var w := U.local_aabb(p)
			var sb := StaticBody3D.new()
			var cs := CollisionShape3D.new()
			var sh := BoxShape3D.new()
			# the body is a child of the scaled prop, so it inherits the scale -
			# give it the prop's UNSCALED bounds or it is scaled twice
			sh.size = w.size
			cs.shape = sh
			cs.position = w.get_center()
			sb.add_child(cs)
			sb.set_meta("surface", "concrete")
			p.add_child(sb)
	P.call("liquorstore", -268, 46.1, 9.2, PI, 0.0, true)
	for i in range(-3, 4):
		P.call("ironfence", -268 + i * 2.55, 41.2, 2.0, 0.0)
	var ti := 0
	var x := -150.0
	while x > -840.0:
		P.call("deadtree", x, 42.6 if ti % 2 == 1 else 29.4, rng.randf_range(5.4, 7.2))
		x -= 37.0
		ti += 1
	x = -146.0
	while x > -840.0:
		P.call("grasstuft" if rng.randf() < 0.5 else "grasstuft2", x + rng.randf_range(-4, 4), rng.randf_range(41.2, 43.2), rng.randf_range(0.3, 0.5))
		P.call("grasstuft" if rng.randf() < 0.5 else "grasstuft2", x + rng.randf_range(-4, 4), rng.randf_range(28.8, 30.8), rng.randf_range(0.3, 0.5))
		x -= 23.0
	x = -160.0
	while x > -830.0:
		P.call("boulder", x, rng.randf_range(43.5, 45.5), rng.randf_range(0.8, 1.5))
		P.call("rockscatter", x - 24, rng.randf_range(26.5, 28.5), rng.randf_range(0.5, 0.9))
		x -= 61.0
	x = -330.0
	while x > -575.0:
		P.call("rubblestack", x, rng.randf_range(43.8, 45.2), rng.randf_range(1.3, 1.9), -1.0, 0.0, true)
		P.call("culvert", x - 26, rng.randf_range(26.8, 28.2), rng.randf_range(1.1, 1.5), -1.0, 0.0, true)
		x -= 52.0
	for cx in [-200.0, -402.0, -486.0, -640.0, -790.0]:
		P.call("cobblepatch", cx, 41.6, 0.16)
	for f in [[-176, 42.2, "man_hoodie", 4.0], [-241, 29.2, "man_kurta", 1.1], [-402, 26.6, "man_hoodie", 0.4],
			[-455, 42.4, "man_kurta", 4.4], [-612, 29.0, "man_kurta", 2.6], [-742, 42.6, "man_hoodie", 5.6]]:
		P.call(f[2], f[0], f[1], 1.79, f[3])
	# the courtyard railing along the mosque frontage, leaving the gateway open
	for i in range(-6, 7):
		if absi(i) < 2:
			continue
		P.call("ironfence", -900.0 + i * 2.55 * 0.46, 32.0 * 0.46 + 32.0 * 0.54 + 0.4, 2.0, 0.0)

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
			if n == "wP_Facade_A":
				# the fire-escape frame has no wall of its own: a brick skin
				# just behind it (visual only - the block above is the collider)
				var depth := d.size.z * sc
				var skin := box(Vector3(w * 0.98, h * 0.97, 0.3), Vector3(x + w / 2, h * 0.485, z_front - facing * (depth + 0.17)), M.brick, false)
				skin.name = "FacadeSkin"
		x += w + 0.3

# ------------------------------------------------------------------ navigation

func _setup_navmesh() -> void:
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	nm.geometry_collision_mask = 1      # not the small props on layer 32
	nm.agent_radius = 0.45
	nm.agent_height = 1.8
	nm.agent_max_climb = 0.3
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	# prop tops (a 0.5 m container, a barrel) bake as tiny walkable islands,
	# and anyone standing next to one gets pathed onto it: drop the islands
	nm.region_min_size = 16.0
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
	var items := []          # [{mesh, aabb, scale}]
	var buckets := {}        # index -> Array[Transform3D]

	func _init(h: Node3D, r: RandomNumberGenerator) -> void:
		host = h
		rng = r
		var bi := 0
		var ci := 0
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
				var mesh: Mesh = mi.mesh
				var sc := 1.0
				# the web's cartons and cans: its own packaging on each (PACK_ART)
				# and its shelfScale (.26 / .30 of the pack's size)
				var is_box := cname.begins_with("box_")
				var is_can := cname.begins_with("can_")
				if is_box or is_can:
					sc = 0.30 if is_can else 0.26
					var tex_path := "res://assets/tex/pack/%s_%d.png" % ["can" if is_can else "box", ci % 7 if is_can else bi % 10]
					if is_can:
						ci += 1
					else:
						bi += 1
					var m := StandardMaterial3D.new()
					m.albedo_texture = U.tex(tex_path)
					m.roughness = 0.4 if is_can else 0.85
					m.metallic = 0.35 if is_can else 0.0
					mesh = mesh.duplicate() as Mesh
					for si in mesh.get_surface_count():
						mesh.surface_set_material(si, m)
				items.append({"mesh": mesh, "aabb": a, "scale": sc})

	## the web's stockMatrix: shelfScale x 1.5-2.3 on the gondolas, 1.4-2.1 on
	## the wall units, seated by the item's own bounds on the deck
	func add(pos: Vector3, ry: float, _unused := 0.0, wall := false) -> void:
		if items.is_empty():
			return
		var idx := rng.randi() % items.size()
		var it: Dictionary = items[idx]
		var a: AABB = it.aabb
		var s: float = float(it.scale) * (rng.randf_range(1.4, 2.1) if wall else rng.randf_range(1.5, 2.3))
		var basis := Basis(Vector3.UP, ry).scaled(Vector3(s, s, s))
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
