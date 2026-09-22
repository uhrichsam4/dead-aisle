## The Al-Salaam mosque, act 2's objective, 900 m west of TOPS. Ported from
## the web build's buildMosque: authored in mosque-LOCAL coordinates at about
## 2.4x life size, then the whole group is scaled by MQ_S and shifted so the
## courtyard wall sits on the road. Collision is built in WORLD space from the
## same numbers (physics and scaled parents do not mix).
##
## One fix over the web build: its interior lights were placed with raw world
## numbers that were never run through the mosque transform, so several sat
## behind the qibla wall lighting nothing. They are placed in local space here.
extends NavigationRegion3D

const U := preload("res://scripts/util.gd")

const X := -900.0
const S := 0.46
const MQ_Z := 32.0 * (1.0 - S)       # keeps the courtyard wall on the road

var G: Node3D
var M := {}

static func mq(x: float, y: float, z: float) -> Vector3:
	return Vector3(X + x * S, y * S, MQ_Z + z * S)

static func mqx(x: float) -> float:
	return X + x * S

static func mqz(z: float) -> float:
	return MQ_Z + z * S

func build() -> void:
	G = Node3D.new()
	G.name = "MosqueGeometry"
	G.position = Vector3(X, 0, MQ_Z)
	G.scale = Vector3.ONE * S
	add_child(G)
	_materials()
	_hall()
	_rooms()
	_mihrab_and_dome()
	_courtyard()
	_gate_and_minarets()
	_lights()
	_props()
	_floor_collider()
	_setup_navmesh()

# ------------------------------------------------------------------ helpers

func box(w: float, h: float, d: float, x: float, y: float, z: float, mat: Material, collide = false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(w, h, d)
	mi.mesh = bm
	mi.material_override = mat
	mi.position = Vector3(x, y, z)
	if maxf(w, maxf(h, d)) < 1.6:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	G.add_child(mi)
	if collide:
		_world_box(Vector3(w, h, d) * S, mq(x, y, z), "concrete" if mat != M.wood else "wood")
	return mi

func _world_box(size: Vector3, pos: Vector3, surface := "concrete") -> void:
	var sb := StaticBody3D.new()
	sb.position = pos
	sb.set_meta("surface", surface)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	sb.add_child(cs)
	add_child(sb)

func _world_cyl(r: float, h: float, pos: Vector3) -> void:
	var sb := StaticBody3D.new()
	sb.position = pos
	sb.set_meta("surface", "concrete")
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = r
	sh.height = h
	cs.shape = sh
	sb.add_child(cs)
	add_child(sb)

## a pointed arch drawn as a fan of voussoirs
func arch(cx: float, cz: float, r: float, depth: float, y0: float, mat: Material, axis: String) -> void:
	for i in 13:
		var a := PI * (i / 12.0)
		var b := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.36, 0.52, depth)
		b.mesh = bm
		b.material_override = mat
		var ox := cos(a) * r
		var oy := sin(a) * r * 1.15
		if axis == "x":
			b.position = Vector3(cx, y0 + oy, cz + ox)
			b.rotation.x = -(a - PI / 2)
			bm.size = Vector3(depth, 0.52, 0.36)
		else:
			b.position = Vector3(cx + ox, y0 + oy, cz)
			b.rotation.z = a - PI / 2
		G.add_child(b)

func cyl(rt: float, rb: float, h: float, x: float, y: float, z: float, mat: Material, segs := 12) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = rt
	cm.bottom_radius = rb
	cm.height = h
	cm.radial_segments = segs
	mi.mesh = cm
	mi.material_override = mat
	mi.position = Vector3(x, y, z)
	G.add_child(mi)
	return mi

func sphere(r: float, x: float, y: float, z: float, mat: Material, hemi := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r if hemi else r * 2.0
	sm.is_hemisphere = hemi
	sm.radial_segments = 28
	sm.rings = 14
	mi.mesh = sm
	mi.material_override = mat
	mi.position = Vector3(x, y, z)
	G.add_child(mi)
	return mi

func floor_plane(w: float, d: float, x: float, y: float, z: float, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(w, d)
	mi.mesh = pm
	mi.material_override = mat
	mi.position = Vector3(x, y, z)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	G.add_child(mi)

# ------------------------------------------------------------------ materials

func _materials() -> void:
	# wall.jpg is photographed dark (mean rgb 69,62,50). wall_sand.jpg is it
	# relevelled to a pale limestone (x1.25 + 82): the web's x1.5 + 30 under
	# Godot's night rig and ACES still came out as brown brick
	M.sand = U.surface_mat("res://assets/tex/wall_sand.jpg", "res://assets/tex/wall_n.jpg", "",
		Vector3(1.5, 1.2, 1.5), Color("eee0c4"), 0.92)
	M.stone = U.flat_mat(Color(0.77, 0.71, 0.58), 0.95)
	M.teal = U.flat_mat(Color(0.18, 0.49, 0.47), 0.42, 0.35)
	M.gold = U.flat_mat(Color(0.79, 0.64, 0.15), 0.3, 0.8)
	M.carpet = U.flat_mat(Color(0.48, 0.18, 0.16), 0.98)
	M.carpet2 = U.flat_mat(Color(0.55, 0.23, 0.2), 0.98)
	M.wood = U.flat_mat(Color(0.36, 0.23, 0.14), 0.85)
	M.trim = U.flat_mat(Color(0.29, 0.25, 0.21), 0.8)
	M.niche = U.flat_mat(Color(0.12, 0.29, 0.28), 0.6)
	M.water = U.flat_mat(Color(0.24, 0.44, 0.48), 0.15, 0.1)
	M.lamp = U.emissive_mat(Color(1, 0.89, 0.67), 3.0)
	M.floor = U.surface_mat("res://assets/tex/tiles2_c.jpg", "res://assets/tex/tiles2_n.jpg", "res://assets/tex/tiles2_r.jpg",
		Vector3(1.15, 1.15, 1.15), Color(0.6, 0.58, 0.52), 0.7)
	M.yard = U.surface_mat("res://assets/tex/tiles2_c.jpg", "res://assets/tex/tiles2_n.jpg", "",
		Vector3(1.15, 1.15, 1.15), Color(0.66, 0.64, 0.56), 0.9)

# ------------------------------------------------------------------ the building

func _hall() -> void:
	floor_plane(50, 29, 0, 0.02, -1.5, M.floor)
	# prayer rows run ACROSS the hall, parallel to the qibla wall
	for i in 5:
		floor_plane(46, 2.3, 0, 0.06, -14.2 + i * 3.2, M.carpet if i % 2 == 1 else M.carpet2)
	box(0.7, 12, 29, -25, 6, -1.5, M.sand, true)
	box(0.7, 12, 29, 25, 6, -1.5, M.sand, true)
	box(50, 12, 0.7, 0, 6, -16, M.sand, true)          # qibla wall
	box(50, 0.6, 29, 0, 12.3, -1.5, M.stone, true)      # ceiling

## One straight spine, the way a mosque of this type reads: vestibule ->
## a tight portal -> the axial corridor -> doors either side into the wudu hall
## and the madrasa -> the corridor mouth opens into the prayer hall.
func _rooms() -> void:
	box(21.8, 12, 0.7, -14.45, 6, 13, M.sand, true)    # facade, split round the entrance arch
	box(21.8, 12, 0.7, 14.45, 6, 13, M.sand, true)
	arch(0, 13, 3.4, 0.95, 5.4, M.stone, "z")
	box(23.15, 12, 0.7, -13.78, 6, 8.7, M.sand, true)  # portal wall, a tight 4.4 threshold
	box(23.15, 12, 0.7, 13.78, 6, 8.7, M.sand, true)
	arch(0, 8.7, 2.2, 0.8, 5.4, M.stone, "z")
	box(0.7, 12, 2.65, -3.85, 6, 7.72, M.sand, true)   # corridor walls, a 3.0 door each side
	box(0.7, 12, 2.85, -3.85, 6, 1.98, M.sand, true)
	box(0.7, 12, 2.65, 3.85, 6, 7.72, M.sand, true)
	box(0.7, 12, 2.85, 3.85, 6, 1.98, M.sand, true)
	arch(-3.85, 4.9, 1.5, 0.8, 3.4, M.stone, "x")
	arch(3.85, 4.9, 1.5, 0.8, 3.4, M.stone, "x")
	box(7.35, 12, 0.7, -21.68, 6, 0.9, M.sand, true)   # hall north wall: corridor mouth + a door per chamber
	box(11.5, 12, 0.7, -9.25, 6, 0.9, M.sand, true)
	box(11.5, 12, 0.7, 9.25, 6, 0.9, M.sand, true)
	box(7.35, 12, 0.7, 21.68, 6, 0.9, M.sand, true)
	arch(-16.5, 0.9, 1.5, 0.8, 3.4, M.stone, "z")
	arch(16.5, 0.9, 1.5, 0.8, 3.4, M.stone, "z")
	# walled corner stores - a survivor hides in each
	box(0.7, 6, 3.75, -19.5, 3, 3.12, M.stone, true)
	box(1.85, 6, 0.7, -24.43, 3, 5.0, M.stone, true)
	box(1.75, 6, 0.7, -20.02, 3, 5.0, M.stone, true)
	box(0.7, 6, 3.75, 19.5, 3, 3.12, M.stone, true)
	box(1.85, 6, 0.7, 24.43, 3, 5.0, M.stone, true)
	box(1.75, 6, 0.7, 20.02, 3, 5.0, M.stone, true)
	box(0.6, 2.4, 3.05, -11, 1.2, 7.12, M.stone, true)  # wash-stall divider
	box(0.6, 2.4, 3.05, 11, 1.2, 7.12, M.stone, true)   # bookcase spine
	# dropped ceilings - lofty vestibule, squeezed corridor, low chambers
	box(49.3, 0.6, 3.6, 0, 10.5, 10.85, M.stone)
	box(7, 0.6, 8.5, 0, 7.9, 4.8, M.stone)
	box(20.5, 0.6, 7.6, -14.4, 6.1, 4.8, M.stone)
	box(20.5, 0.6, 7.6, 14.4, 6.1, 4.8, M.stone)
	# corridor runner and sconces
	floor_plane(6, 7.1, 0, 0.06, 4.8, M.carpet2)
	for sx in [-3.4, 3.4]:
		for sz in [2.6, 7.0]:
			box(0.3, 0.5, 0.28, sx, 3.4, sz, M.gold)
			sphere(0.16, sx * 0.86, 3.4, sz, M.lamp)
	# wudu trough with taps
	box(9, 0.9, 1.1, -13, 0.45, 1.9, M.stone, true)
	for i in 8:
		box(0.1, 0.5, 0.1, -17 + i * 1.1, 1.2, 1.9, M.gold)
	box(9, 0.12, 1.1, -13, 0.96, 1.9, M.teal)
	# madrasa: bookcases and reading desks
	box(0.6, 3.2, 4.0, 24.0, 1.6, 3.0, M.wood, true)
	box(0.6, 3.2, 4.0, 24.0, 1.6, 7.0, M.wood, true)
	for dz in [2.6, 5.4]:
		box(2.2, 0.1, 1.0, 20.5, 0.78, dz, M.wood, true)
	for sy in [1.0, 1.7, 2.4]:
		box(4.6, 0.12, 0.9, -22.25, sy, 1.8, M.wood)
		box(4.6, 0.12, 0.9, 22.25, sy, 1.8, M.wood)
	box(1.2, 0.6, 0.8, -20.6, 0.3, 4.0, M.carpet, true)
	box(1.2, 0.6, 0.8, 20.6, 0.3, 4.0, M.carpet, true)
	# shoe racks either side of the central arch
	for sx in [-6.4, 6.4]:
		box(3.4, 0.12, 1.1, sx, 0.9, 12.0, M.wood)
		box(3.4, 0.12, 1.1, sx, 1.5, 12.0, M.wood)
		box(0.12, 1.6, 1.1, sx - 1.7, 0.8, 12.0, M.wood)
		box(0.12, 1.6, 1.1, sx + 1.7, 0.8, 12.0, M.wood)

func _mihrab_and_dome() -> void:
	box(7.2, 9, 1.4, 0, 4.5, -15.2, M.stone)
	box(3.6, 6, 0.8, 0, 3, -14.6, M.niche)
	arch(0, -14.55, 1.9, 0.85, 6, M.gold, "z")
	# the minbar, always to the RIGHT of the mihrab
	for i in 6:
		box(1.9, 0.42, 0.9, 3.9, 0.21 + i * 0.42, -13.6 + i * 0.9, M.wood, i == 0)
	box(0.2, 3.2, 0.2, 3.0, 1.6, -13.4, M.wood)
	box(0.2, 3.2, 0.2, 4.8, 1.6, -13.4, M.wood)
	box(2.1, 0.16, 0.16, 3.9, 3.2, -13.4, M.gold)
	# the dome over the bay in front of the mihrab
	cyl(8.6, 8.6, 2.6, 0, 13.6, -9, M.sand, 8)
	sphere(8.6, 0, 14.9, -9, M.teal, true)
	cyl(0.16, 0.16, 2.6, 0, 24.5, -9, M.gold, 8)
	sphere(0.8, 0, 26.1, -9, M.gold)
	for cx in [-8.6, 8.6]:
		for cz in [-16.6, -1.4]:
			cyl(0.72, 0.8, 12, cx, 6, cz, M.stone, 14)
			_world_cyl(0.8 * S, 12 * S, mq(cx, 6, cz))
	# hanging lamps down the hall
	for lx in [-16, -8, 0, 8, 16]:
		for lz in [-12, -7, -2]:
			cyl(0.03, 0.03, 3.4, lx, 10.4, lz, M.trim, 5)
			sphere(0.36, lx, 8.5, lz, M.lamp)

func _courtyard() -> void:
	floor_plane(54, 19, 0, 0.03, 23, M.yard)
	# riwaq: an arcade down both long sides
	for sx in [-25.0, 25.0]:
		for i in 5:
			var cz := 16.4 + i * 3.9
			cyl(0.5, 0.56, 5.4, sx, 2.7, cz, M.stone)
			_world_cyl(0.6 * S, 5.4 * S, mq(sx, 2.7, cz))
			if i < 4:
				arch(sx, cz + 1.95, 1.85, 0.7, 5.2, M.stone, "x")
		box(1.6, 1.4, 19, sx, 6.1, 23, M.sand)
	# the ablution fountain at the centre of the sahn
	cyl(3.1, 3.4, 1.1, 0, 0.55, 23, M.stone, 16)
	cyl(2.8, 2.8, 0.1, 0, 1.08, 23, M.water, 16)
	cyl(0.22, 0.3, 2.2, 0, 2.1, 23, M.stone, 10)
	_world_cyl(3.4 * S, 1.1 * S, mq(0, 0.55, 23))
	for lx in [-15, 15]:
		for lz in [18, 29]:
			cyl(0.12, 0.16, 4.4, lx, 2.2, lz, M.trim, 8)
			sphere(0.42, lx, 4.7, lz, M.lamp)

func _gate_and_minarets() -> void:
	# the street wall reaches its own gate piers - the web build's stopped at
	# local x 8 and left a 1.3 m walk-through hole beside the gate
	box(21.8, 4.6, 0.8, -16.1, 2.3, 32, M.sand, true)
	box(21.8, 4.6, 0.8, 16.1, 2.3, 32, M.sand, true)
	for gx in [-4.2, 4.2]:
		box(2.0, 9.0, 2.0, gx, 4.5, 32, M.sand, true)
	box(22, 3.2, 1.5, 0, 10.6, 32, M.stone)              # the header the sign mounts on
	box(22, 0.5, 1.9, 0, 12.45, 32, M.stone)
	arch(0, 32, 3.4, 1.0, 3.4, M.stone, "z")
	# AL-SALAAM over the gate, both faces
	for f in [[32.8, 0.0], [31.2, PI]]:
		box(19.5, 2.7, 0.04, 0, 10.6, f[0], U.flat_mat(Color(0.94, 0.9, 0.81), 0.8))
		var l := Label3D.new()
		l.text = "AL-SALAAM"
		l.font_size = 260
		l.pixel_size = 0.005
		l.modulate = Color(0.12, 0.29, 0.28)
		l.shaded = false
		l.position = Vector3(0, 10.75, f[0] + (0.05 if f[1] == 0.0 else -0.05))
		l.rotation.y = f[1]
		G.add_child(l)
		var sub := Label3D.new()
		sub.text = "M O S Q U E"
		sub.font_size = 72
		sub.pixel_size = 0.005
		sub.modulate = Color(0.48, 0.44, 0.34)
		sub.shaded = false
		sub.position = Vector3(0, 9.7, f[0] + (0.05 if f[1] == 0.0 else -0.05))
		sub.rotation.y = f[1]
		G.add_child(sub)
	# minarets at the outer corners of the courtyard
	for mx in [-26.5, 26.5]:
		cyl(1.4, 1.75, 26, mx, 13, 31.5, M.sand)
		cyl(2.2, 2.2, 0.5, mx, 19.5, 31.5, M.stone)
		cyl(1.9, 1.9, 0.4, mx, 24.4, 31.5, M.stone)
		cyl(0.0, 1.8, 3.6, mx, 27.8, 31.5, M.teal)
		cyl(0.1, 0.1, 1.7, mx, 30.3, 31.5, M.gold, 8)
		_world_cyl(1.8 * S, 26 * S, mq(mx, 13, 31.5))

func _lights() -> void:
	var L := [
		[Vector3(0, 7.5, 10.85), Color(1, 0.86, 0.66), 2.0, 16.0],   # vestibule
		[Vector3(0, 6.5, 4.8), Color(1, 0.84, 0.63), 1.5, 9.0],      # corridor
		[Vector3(-14, 4.8, 4.8), Color(1, 0.88, 0.7), 1.4, 11.0],    # wudu hall
		[Vector3(14, 4.8, 4.8), Color(1, 0.88, 0.7), 1.4, 11.0],     # madrasa
		[Vector3(-22.2, 4.0, 3.0), Color(1, 0.81, 0.56), 0.9, 5.0],  # corner stores
		[Vector3(22.2, 4.0, 3.0), Color(1, 0.81, 0.56), 0.9, 5.0],
		[Vector3(0, 9.0, -6), Color(1, 0.86, 0.66), 2.6, 22.0],      # prayer hall
		[Vector3(-12, 8.0, -8), Color(1, 0.86, 0.66), 1.4, 12.0],
		[Vector3(12, 8.0, -8), Color(1, 0.86, 0.66), 1.4, 12.0],
		[Vector3(0, 6.0, -12.5), Color(1, 0.88, 0.69), 1.2, 9.0],    # mihrab
		[Vector3(0, 7.0, 24), Color(1, 0.85, 0.63), 1.8, 18.0],      # courtyard
	]
	for l in L:
		var o := OmniLight3D.new()
		o.position = mq(l[0].x, l[0].y, l[0].z)
		o.light_color = l[1]
		o.light_energy = l[2]
		o.omni_range = l[3]
		add_child(o)

func _props() -> void:
	var lib := "res://assets/ph_mosque.glb"
	var root := U.glb(lib)
	if root == null:
		return
	U.fix_materials(root)
	var names := []
	for c in root.get_children():
		names.append(str(c.name))
	var pick := func(re: String) -> Array:
		var rx := RegEx.new()
		rx.compile("(?i)" + re)
		return names.filter(func(n): return rx.search(n) != null)
	var chand: Array = pick.call("chandelier")
	var lant: Array = pick.call("lantern|diya")
	var vases: Array = pick.call("vase|pot|goblet|ceramic")
	var shelf: Array = pick.call("shelf|cabinet|commode")
	var books: Array = pick.call("book|binder")
	# placed through props.gd so the clay and the books can be shot to bits.
	# load, not preload: props.gd preloads this script for mqx/mqz
	var Props = load("res://scripts/props.gd")
	for i in chand.size():
		for cz in [-12, -6]:
			Props.put(self, lib, chand[i], mqx((i - 1) * 13), mqz(cz), {h = 1.6, y = 3.6})
	for n in lant:
		for p in [[-3.1, 3.0], [3.1, 3.0], [-3.1, 6.8], [3.1, 6.8]]:
			Props.put(self, lib, n, mqx(p[0]), mqz(p[1]), {h = 0.5, y = 1.15, solid = true, brk = "pottery"})
	for i in mini(6, vases.size()):
		Props.put(self, lib, vases[i], mqx(-17 + i * 1.9), mqz(3.1), {h = 0.42, solid = true, brk = "pottery"})
	for i in mini(3, shelf.size()):
		Props.put(self, lib, shelf[i], mqx(8.0 + i * 3.4), mqz(7.6), {h = 2.1, ry = PI, solid = true})
	for i in mini(4, books.size()):
		Props.put(self, lib, books[i], mqx(9.0 + i * 2.6), mqz(7.0), {h = 0.28, y = 0.84, solid = true, brk = "crate", brk_scale = 0.5})
	# the corner stores: pots either side
	for i in mini(4, vases.size()):
		for sx in [-22.2, 22.2]:
			Props.put(self, lib, vases[i], mqx(sx + randf_range(-0.8, 0.8)), mqz(2.2 + randf_range(-0.8, 0.8)),
				{h = 0.4, solid = true, brk = "pottery"})
	Props.build_mosque(self)

func _floor_collider() -> void:
	# a floor for the navmesh bake - the town's ground collider lives in
	# another region, which this one does not parse
	_world_box(Vector3(60 * S, 1, 60 * S), Vector3(X, -0.5, mqz(8)))

func _setup_navmesh() -> void:
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	nm.geometry_collision_mask = 1      # not the small props on layer 32
	nm.agent_radius = 0.4
	nm.agent_height = 1.8
	nm.agent_max_climb = 0.3
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	# prop tops (a 0.5 m container, a barrel) bake as tiny walkable islands,
	# and anyone standing next to one gets pathed onto it: drop the islands
	nm.region_min_size = 16.0
	nm.filter_baking_aabb = AABB(Vector3(X - 15, -1, mqz(-18)), Vector3(30, 5, mqz(40) - mqz(-18)))
	navigation_mesh = nm

func bake_nav() -> void:
	bake_navigation_mesh(true)
