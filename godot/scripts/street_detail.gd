## Street life along the drive: cars parked nose-to-tail at the south kerb,
## bollards and bins in the gaps between them, speed and parking signs. The
## road runs x -1030..170, carriageway z 32..40; the drive lane (z 34..39),
## the TOPS forecourt and the mosque frontage are left clear.
##
## The parked cars are one mesh (car-lod.glb) drawn through a MultiMesh per
## 60 m stretch, paint as a per-instance colour: a whole stretch of street
## costs the same draws as a single car, and a stretch out of range costs none.
extends RefCounted

const U := preload("res://scripts/util.gd")
const Props := preload("res://scripts/props.gd")

const CAR := "res://assets/car-lod.glb"
const EXTRA := "res://assets/ph_extra.glb"
const STREET := "res://assets/ph_street.glb"
const OIL := "res://assets/tex/lot/oil.png"

const PARK_Z := 32.98         # a parked car's centre line, a hand off the kerb
const KERB_S := 31.74         # south kerb edge, on the pavement side
const KERB_N := 40.32         # north kerb edge
const CHUNK := 60.0            # small enough for mesh LOD and culling to bite
const DRAW := 100.0           # past this a car at the kerb is a few pixels
# where cars may park: off the TOPS forecourt and wrecks, off the mosque gate
const RUNS := [[-1020.0, -918.0], [-882.0, -48.5], [54.5, 165.0]]
# what a real street is parked up with: mostly silver, white, black and grey
const PAINT := ["c3c6c9", "e6e6e2", "1c1e20", "50555a", "c3c6c9", "e6e6e2", "2a2c30", "8d9296",
	"1f2c44", "6b1a1d", "2b4034", "a69c83", "4b6a89", "4a2226", "d8d2c0", "3a3f45"]
# a couple under dust sheets, at the south kerb
const COVERED := [-402.0, -733.0]
# the speed and parking signs: [x, north side?, kind]
const SIGNS := [[150.0, true, "30"], [70.0, false, "P"], [-64.0, true, "30"], [-170.0, false, "P"],
	[-246.0, true, "P"], [-352.0, false, "30"], [-470.0, true, "30"], [-590.0, false, "P"],
	[-700.0, true, "P"], [-812.0, false, "30"], [-870.0, true, "30"], [-960.0, false, "P"]]

static var rng := RandomNumberGenerator.new()

static func build(w: Node3D) -> void:
	rng.seed = 90210
	var src := _car_source()
	var chunks := {}          # chunk index -> {cars: [], stains: [], bollards: []}
	# [x, half-width] of what already stands at the south kerb
	var reserved: Array = []
	for s in SIGNS:
		if not s[1]:
			reserved.append([s[0], 0.6])
	for cx in COVERED:
		reserved.append([cx, 2.9])
	for run in RUNS:
		var x: float = run[0] + rng.randf_range(1.0, 5.0)
		while x < run[1]:
			if rng.randf() < 0.58:
				var sc := rng.randf_range(0.96, 1.04)
				var half := 2.28 * sc
				if x + half * 2.0 > run[1]:
					break
				if _blocked(reserved, x, x + half * 2.0):
					x += 1.5
					continue
				_park(w, chunks, src, x + half, sc)
				x += half * 2.0 + rng.randf_range(0.8, 2.4)
			else:
				# a gap: a run of bollards, a bin, or just empty kerb
				var gap := rng.randf_range(9.0, 30.0)
				var mid := minf(x + gap * 0.5, run[1] - 1.0)
				var r := rng.randf()
				if _blocked(reserved, mid - 3.5, mid + 3.5):
					r = 1.0
				if r < 0.3:
					var n := rng.randi_range(3, 5)
					for i in n:
						_chunk(chunks, mid).bollards.append(Vector3(mid + (i - (n - 1) * 0.5) * 1.5, _kerb_y(mid, false), KERB_S))
				elif r < 0.55:
					Props.put(w, EXTRA, "metal_trash_can", mid, KERB_S - 0.18, {h = 0.9, y = _kerb_y(mid, false), ry = rng.randf_range(-0.4, 0.4), solid = true, cull = DRAW})
				x += gap
	# nobody has moved these in a long while
	for cx in COVERED:
		_covered(w, cx)
	for s in SIGNS:
		_sign(w, s[0], s[1], s[2])
	_north_bins(w)
	for k in chunks:
		_flush(w, chunks[k], float(k) * CHUNK + CHUNK * 0.5, src)

static func _blocked(res: Array, x0: float, x1: float) -> bool:
	for r in res:
		if x1 > float(r[0]) - float(r[1]) - 0.5 and x0 < float(r[0]) + float(r[1]) + 0.5:
			return true
	return false

## the pavement is a 14 cm kerb box: stand things on it, not in it. The south
## side has none east of the lot or across the TOPS drive and the mosque gate.
static func _kerb_y(x: float, north: bool) -> float:
	if north:
		return 0.14
	if x > 60.0 or (x > 6.0 and x < 18.0) or (x > -903.0 and x < -897.0):
		return 0.0
	return 0.14

static func _chunk(chunks: Dictionary, x: float) -> Dictionary:
	var k := floori(x / CHUNK)
	if not chunks.has(k):
		chunks[k] = {cars = [], paints = [], stains = [], bollards = []}
	return chunks[k]

## the car-lod mesh with its own paint surface, and its box in its own space
static func _car_source() -> Dictionary:
	var lib := U.glb(CAR)
	if lib == null:
		return {}
	U.fix_materials(lib, false)
	var mi: MeshInstance3D = null
	for n in lib.find_children("*", "MeshInstance3D", true, false):
		mi = n as MeshInstance3D
		break
	if mi == null or mi.mesh == null:
		return {}
	var xf := Transform3D.IDENTITY
	var p: Node = mi
	while p != lib and p != null:
		xf = (p as Node3D).transform * xf
		p = p.get_parent()
	var mesh := mi.mesh.duplicate() as ArrayMesh
	if mesh == null:
		return {}
	for i in mesh.get_surface_count():
		var m := mesh.surface_get_material(i)
		if m is StandardMaterial3D and (m as StandardMaterial3D).resource_name == "car":
			# the body panels take the instance colour; clearcoat for the
			# wet-look sheen streetlights pick out on real paint
			var paint := (m as StandardMaterial3D).duplicate() as StandardMaterial3D
			paint.vertex_color_use_as_albedo = true
			paint.vertex_color_is_srgb = true
			paint.albedo_color = Color.WHITE
			paint.metallic = 0.45
			paint.roughness = 0.34
			paint.clearcoat_enabled = true
			paint.clearcoat = 0.6
			paint.clearcoat_roughness = 0.18
			mesh.surface_set_material(i, paint)
		elif m is StandardMaterial3D and (m as StandardMaterial3D).resource_name.contains("light"):
			# parked means off: no lamp glowing on an empty car
			var off := (m as StandardMaterial3D).duplicate() as StandardMaterial3D
			off.emission_enabled = false
			mesh.surface_set_material(i, off)
		elif m is StandardMaterial3D and (m as StandardMaterial3D).resource_name == "emission_white":
			var off2 := (m as StandardMaterial3D).duplicate() as StandardMaterial3D
			off2.emission_enabled = false
			off2.albedo_color = Color(0.7, 0.72, 0.74)
			mesh.surface_set_material(i, off2)
	return {mesh = mesh, xf = xf, aabb = xf * mesh.get_aabb()}

## one car at the kerb: an instance in its stretch's MultiMesh and a box body
static func _park(w: Node3D, chunks: Dictionary, src: Dictionary, x: float, sc: float) -> void:
	if src.is_empty():
		return
	# with the traffic, mostly; the odd one parked facing the wrong way
	var ry := rng.randf_range(-0.025, 0.025) + (PI if rng.randf() < 0.12 else 0.0)
	var pos := Vector3(x, 0, PARK_Z + rng.randf_range(-0.1, 0.1))
	var c := _chunk(chunks, x)
	c.cars.append(Transform3D(Basis(Vector3.UP, ry).scaled(Vector3.ONE * sc), pos))
	c.paints.append(Color(PAINT[rng.randi() % PAINT.size()]))
	if rng.randf() < 0.4:
		c.stains.append(Vector3(x + rng.randf_range(-1.4, 1.4), 0, pos.z + rng.randf_range(-0.3, 0.3)))
	var a: AABB = src.aabb
	var body := StaticBody3D.new()
	body.name = "ParkedCar"
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", "metal")
	body.position = pos
	body.rotation.y = ry
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(a.size.x * sc * 0.97, a.size.y * sc * 0.92, a.size.z * sc * 0.95)
	cs.shape = sh
	cs.position = Vector3(a.get_center().x * sc, a.size.y * sc * 0.46, a.get_center().z * sc)
	body.add_child(cs)
	w.add_child(body)

## a stretch's cars, oil stains and bollards: three draws' worth of batches,
## all dropped together once the camera is past DRAW of the stretch's ends
static func _flush(w: Node3D, c: Dictionary, cx: float, src: Dictionary) -> void:
	var origin := Vector3(cx, 0, 36)
	var range_end := DRAW + CHUNK * 0.5
	if not c.cars.is_empty() and not src.is_empty():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = src.mesh
		mm.instance_count = c.cars.size()
		for i in c.cars.size():
			var t: Transform3D = c.cars[i]
			t.origin -= origin
			mm.set_instance_transform(i, t * (src.xf as Transform3D))
			mm.set_instance_color(i, c.paints[i])
		_mmi(w, mm, origin, range_end, true, "ParkedCars")
	if not c.stains.is_empty():
		var pm := PlaneMesh.new()
		pm.size = Vector2(1.5, 1.15)
		var m := StandardMaterial3D.new()
		m.albedo_texture = U.tex(OIL)
		m.albedo_color = Color(1, 1, 1, 0.32)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = 0.35           # oil is the glossy patch on dry tarmac
		pm.material = m
		var mm2 := MultiMesh.new()
		mm2.transform_format = MultiMesh.TRANSFORM_3D
		mm2.mesh = pm
		mm2.instance_count = c.stains.size()
		for i in c.stains.size():
			var p: Vector3 = c.stains[i]
			mm2.set_instance_transform(i, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p - origin + Vector3(0, 0.024, 0)))
		_mmi(w, mm2, origin, range_end, false, "OilStains")
	if not c.bollards.is_empty():
		var mm3 := MultiMesh.new()
		mm3.transform_format = MultiMesh.TRANSFORM_3D
		mm3.mesh = _bollard_mesh()
		mm3.instance_count = c.bollards.size()
		var body := StaticBody3D.new()
		body.name = "Bollards"
		body.collision_layer = 1
		body.collision_mask = 0
		body.set_meta("surface", "metal")
		for i in c.bollards.size():
			var p: Vector3 = c.bollards[i]
			mm3.set_instance_transform(i, Transform3D(Basis(), p - origin))
			var cs := CollisionShape3D.new()
			var sh := BoxShape3D.new()
			sh.size = Vector3(0.2, 0.95, 0.2)
			cs.shape = sh
			cs.position = p + Vector3(0, 0.475, 0)
			body.add_child(cs)
		w.add_child(body)
		_mmi(w, mm3, origin, range_end, false, "BollardRow")

static func _mmi(w: Node3D, mm: MultiMesh, origin: Vector3, range_end: float, shadows: bool, n: String) -> void:
	var mmi := MultiMeshInstance3D.new()
	mmi.name = n
	mmi.multimesh = mm
	mmi.position = origin
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = range_end
	mmi.visibility_range_end_margin = 10.0
	w.add_child(mmi)

## a steel kerb bollard with a reflective band near the top, made once
static var _bollard: ArrayMesh
static func _bollard_mesh() -> ArrayMesh:
	if _bollard:
		return _bollard
	_bollard = ArrayMesh.new()
	var body := CylinderMesh.new()
	body.top_radius = 0.085
	body.bottom_radius = 0.095
	body.height = 0.95
	body.radial_segments = 12
	body.rings = 1
	var band := CylinderMesh.new()
	band.top_radius = 0.09
	band.bottom_radius = 0.091
	band.height = 0.07
	band.radial_segments = 12
	band.rings = 1
	var cap := SphereMesh.new()
	cap.radius = 0.085
	cap.height = 0.09
	cap.radial_segments = 12
	cap.rings = 3
	cap.is_hemisphere = true
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(body, 0, Transform3D(Basis(), Vector3(0, 0.475, 0)))
	st.append_from(cap, 0, Transform3D(Basis(), Vector3(0, 0.95, 0)))
	st.set_material(U.flat_mat(Color("1d1f21"), 0.5, 0.55))
	st.commit(_bollard)
	var st2 := SurfaceTool.new()
	st2.begin(Mesh.PRIMITIVE_TRIANGLES)
	st2.append_from(band, 0, Transform3D(Basis(), Vector3(0, 0.8, 0)))
	var refl := U.flat_mat(Color("e9e5d6"), 0.25, 0.1)
	refl.emission_enabled = true           # retroreflective: headlights pick it out
	refl.emission = Color("e9e5d6")
	refl.emission_energy_multiplier = 0.15
	st2.set_material(refl)
	st2.commit(_bollard)
	return _bollard

## a tarp-covered car from the street pack, parked at the kerb
static func _covered(w: Node3D, x: float) -> void:
	var p := U.part(STREET, "covered_car")
	if p == null:
		return
	p.rotation = Vector3.ZERO
	p.scale = Vector3.ONE
	var a := U.local_aabb(p)
	p.free()
	# lie it along the road whichever way the pack modelled it
	var ry := 0.0 if a.size.x >= a.size.z else PI / 2
	Props.put(w, STREET, "covered_car", x, PARK_Z, {w = 4.5, ry = ry + rng.randf_range(-0.03, 0.03), solid = true, cull = DRAW + 20.0})

## A pole-mounted sign at the kerb, facing the traffic on that side: a "30"
## roundel or a blue parking plate. Lit by the scene, not glowing.
static func _sign(w: Node3D, x: float, north: bool, kind: String) -> void:
	var body := StaticBody3D.new()
	body.name = "StreetSign"
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", "metal")
	body.position = Vector3(x, _kerb_y(x, north), KERB_N if north else KERB_S)
	# local +Z is the face: north-side signs face the westbound lane (+X),
	# south-side ones the eastbound (-X)
	body.rotation.y = PI / 2 if north else -PI / 2
	var metal := U.flat_mat(Color("8e9296"), 0.45, 0.8)
	var pole := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.035
	pm.bottom_radius = 0.035
	pm.height = 2.6
	pm.radial_segments = 8
	pole.mesh = pm
	pole.material_override = metal
	pole.position.y = 1.3
	body.add_child(pole)
	if kind == "30":
		_disc(body, 0.32, 0.018, Color("b3171b"), Vector3(0, 2.3, 0.04))
		_disc(body, 0.255, 0.02, Color("ecebe6"), Vector3(0, 2.3, 0.045))
		_label(body, "30", 0.3, Color(0.05, 0.05, 0.05), Vector3(0, 2.3, 0.058))
	else:
		_plate(body, Vector3(0.46, 0.46, 0.025), Color("1d4f9c"), Vector3(0, 2.25, 0.05))
		_label(body, "P", 0.34, Color(0.95, 0.95, 0.93), Vector3(0, 2.25, 0.065))
		_plate(body, Vector3(0.46, 0.16, 0.02), Color("ecebe6"), Vector3(0, 1.93, 0.05))
		_label(body, "2 HOURS", 0.075, Color(0.08, 0.08, 0.1), Vector3(0, 1.93, 0.062))
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(0.12, 2.6, 0.12)
	cs.shape = sh
	cs.position.y = 1.3
	body.add_child(cs)
	_cull(body, DRAW)
	w.add_child(body)

static func _disc(parent: Node3D, r: float, t: float, col: Color, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = t
	cm.radial_segments = 24
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = U.flat_mat(col, 0.5, 0.1)
	mi.rotation.x = PI / 2           # the cylinder's axis onto the face normal
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)

static func _plate(parent: Node3D, size: Vector3, col: Color, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = U.flat_mat(col, 0.5, 0.1)
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)

static func _label(parent: Node3D, text: String, h: float, col: Color, pos: Vector3) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 64
	l.outline_size = 0
	l.pixel_size = h / 64.0
	l.modulate = Color(col.r, col.g, col.b, 1.0)
	l.shaded = true
	l.double_sided = false
	l.position = pos
	parent.add_child(l)

## bins on the north pavement's kerb edge, clear of the lamp posts, the
## concrete barriers and the liquor store's fence
static func _north_bins(w: Node3D) -> void:
	var x := -160.0
	while x > -1010.0:
		x -= rng.randf_range(45.0, 90.0)
		if absf(x + 900.0) < 40.0 or (x > -282.0 and x < -254.0):
			continue
		if absf(fposmod(x + 136.0, 38.0)) < 2.5 or absf(fposmod(x + 136.0, 38.0) - 38.0) < 2.5:
			continue
		var bar := false
		for i in 10:
			if absf(x - (-620.0 + i * 120.0)) < 3.5:
				bar = true
		for s in SIGNS:
			if s[1] and absf(x - float(s[0])) < 2.0:
				bar = true
		if bar:
			continue
		Props.put(w, EXTRA, "metal_trash_can", x, KERB_N + 0.2, {h = 0.9, y = 0.14, ry = rng.randf_range(-0.4, 0.4), solid = true, cull = DRAW})

static func _cull(root: Node, dist: float) -> void:
	if root is GeometryInstance3D:
		(root as GeometryInstance3D).visibility_range_end = dist
		(root as GeometryInstance3D).visibility_range_end_margin = 6.0
	for c in root.get_children():
		_cull(c, dist)
