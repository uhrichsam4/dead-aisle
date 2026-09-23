## The town details the web build had and the port did not: the derelict
## sedans along the road and in the lot (townWreck), and the car-park
## dressing (cl_dressLot) - cart corrals, oil stains, painted arrows and the
## TOPS stencil, concrete bumpers at the stall heads, two tipped trolleys and
## the disabled bay.
extends RefCounted

const U := preload("res://scripts/util.gd")

## townWreck: a block-built sedan, solid to the car and to people
const WRECKS := [[-38.0, 34.6, PI, "565b52"], [-25.0, 34.8, 0.0, "6e5044"], [31.0, 34.5, PI, "49525e"],
	[45.0, 34.9, 0.0, "6d6752"], [-16.0, 18.2, PI, "6e5044"]]

static func build(w: Node3D) -> void:
	_wrecks(w)
	_corrals(w)
	_markings(w)
	_bumpers(w)
	var Props = load("res://scripts/props.gd")
	var cart: ArrayMesh = Props._cart_mesh()
	for c in [[17.2, 18.3], [14.3, 19.4]]:
		var mi := MeshInstance3D.new()
		mi.mesh = cart
		mi.position = Vector3(c[0], 0.52, c[1])
		mi.rotation = Vector3(PI / 2 * 0.9, randf() * TAU, 0.4)
		w.add_child(mi)

static func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi

static func _solid(parent: Node3D, size: Vector3, pos: Vector3, ry := 0.0) -> void:
	var sb := StaticBody3D.new()
	sb.set_meta("surface", "metal")
	sb.position = pos
	sb.rotation.y = ry
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	sb.add_child(cs)
	parent.add_child(sb)

static func _wrecks(w: Node3D) -> void:
	var glass := U.flat_mat(Color("10161c"), 0.3, 0.6)
	var trim := U.flat_mat(Color("191b1e"), 0.7)
	var wheel := CylinderMesh.new()
	wheel.top_radius = 0.34
	wheel.bottom_radius = 0.34
	wheel.height = 0.26
	wheel.radial_segments = 14
	# faded paint: the car's own colour over the chipped-enamel scan's relief
	# and roughness (its albedo's rust blotches read as camouflage on a body)
	var paints := {}
	for e in WRECKS:
		if not paints.has(e[3]):
			paints[e[3]] = U.cc0("PaintedMetal010", 1.8, Color(e[3]), 1.0, 0.2, false)
	var under := U.cc0("Metal024", 0.9, Color(0.42, 0.33, 0.27), 1.0, 0.3)   # rusted sills and bumpers
	for e in WRECKS:
		var g := Node3D.new()
		g.name = "Wreck"
		g.position = Vector3(e[0], 0, e[1])
		g.rotation.y = e[2]
		w.add_child(g)
		var body: StandardMaterial3D = paints[e[3]]
		_box(g, Vector3(4.2, 0.6, 1.8), Vector3(0, 0.55, 0), body)
		_box(g, Vector3(2.0, 0.55, 1.62), Vector3(-0.2, 1.1, 0), body)
		var gl := _box(g, Vector3(2.04, 0.34, 1.5), Vector3(-0.2, 1.16, 0), glass)
		gl.scale = Vector3(1.02, 1, 1)
		for wx in [-1.4, 1.4]:
			for wz in [-0.82, 0.82]:
				var wm := MeshInstance3D.new()
				wm.mesh = wheel
				wm.material_override = trim
				wm.rotation.x = PI / 2
				wm.position = Vector3(wx, 0.34, wz)
				g.add_child(wm)
		for bx in [-2.14, 2.14]:
			_box(g, Vector3(0.18, 0.22, 1.9), Vector3(bx, 0.42, 0), under)
		_solid(w, Vector3(4.5, 1.4, 2.1), Vector3(e[0], 0.7, e[1]), e[2])

## cart corrals: two rail pens by the store front
static func _corrals(w: Node3D) -> void:
	# galvanised tube: a dull scan, and only half metallic - at 0.6 metallic
	# with a flat colour the sky reflection turned the rails white
	var rail := U.cc0("Metal024", 0.8, Color(0.62, 0.64, 0.66), 1.0, 0.35)
	for cx in [-11.0, 15.5]:
		var cz := 16.75
		for px in [-1.15, 1.15]:
			for pz in [-0.45, 0.45]:
				_box(w, Vector3(0.06, 0.85, 0.06), Vector3(cx + px, 0.425, cz + pz), rail)
		for pz in [-0.45, 0.45]:
			for py in [0.78, 0.45]:
				_box(w, Vector3(2.4, 0.05, 0.05), Vector3(cx, py, cz + pz), rail)
			_box(w, Vector3(0.05, 0.05, 1.0), Vector3(cx + (-1.15 if pz < 0 else 1.15), 0.78, cz + pz), rail)
		_solid(w, Vector3(2.7, 0.85, 1.4), Vector3(cx, 0.425, cz))

## paint on the asphalt: a flat quad just above it, alpha-blended
static func _decal(w: Node3D, tex_path: String, size: Vector2, pos: Vector3, rz: float, alpha: float) -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = size
	mi.mesh = pm
	var m := StandardMaterial3D.new()
	m.albedo_texture = U.tex(tex_path)
	m.albedo_color = Color(1, 1, 1, alpha)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.95
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos
	mi.rotation.y = rz
	w.add_child(mi)

static func _markings(w: Node3D) -> void:
	var i := 0
	for s in [[-17.5, 23.8, 1.5], [-3.2, 26.6, 1.1], [2.6, 21.4, 1.3], [8.0, 27.4, 1.0], [15.2, 24.2, 1.4], [-9.4, 19.2, 0.85]]:
		_decal(w, "res://assets/tex/lot/oil.png", Vector2(s[2] * 1.5, s[2] * 1.2), Vector3(s[0], 0.018 + i * 0.0022, s[1]), randf() * TAU, 0.35)
		i += 1
	# lane arrows and the TOPS stencil, pointing at the doors
	_decal(w, "res://assets/tex/lot/arrow.png", Vector2(1.5, 1.95), Vector3(11.2, 0.033, 24.6), 0.0, 0.8)
	_decal(w, "res://assets/tex/lot/arrow.png", Vector2(1.5, 1.95), Vector3(4.2, 0.033, 26.9), 0.32, 0.8)
	_decal(w, "res://assets/tex/lot/tops.png", Vector2(3.8, 1.07), Vector3(7.8, 0.033, 22.1), 0.0, 0.75)
	_decal(w, "res://assets/tex/lot/handicap.png", Vector2(2.1, 2.1), Vector3(-11.8125, 0.036, 18.55), 0.0, 0.9)

## precast wheel stops at every stall head: 1.65 x 0.15 x 0.1 like the real
## thing, weathered concrete with a worn yellow nose
static func _bumpers(w: Node3D) -> void:
	var mat := U.cc0("Concrete012", 1.2, Color(0.9, 0.89, 0.85), 1.0)
	var nose := U.flat_mat(Color(0.62, 0.5, 0.16), 0.9)
	var x := -19.6875
	while x <= 19.69:
		var b := _box(w, Vector3(1.65, 0.1, 0.15), Vector3(x, 0.05, 20.3), mat)
		b.rotation.y = randf_range(-0.015, 0.015)
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var n := _box(b, Vector3(1.5, 0.03, 0.155), Vector3.ZERO, nose)
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		x += 2.625
