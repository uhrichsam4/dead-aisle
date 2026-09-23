## Shared helpers: model libraries, materials, procedural textures, bounds.
## Everything is static so any script can `const U := preload(...)` it.
extends RefCounted

static var _glb_cache := {}
static var _tex_cache := {}

# ---------------------------------------------------------------- textures

static func tex(path: String) -> Texture2D:
	if _tex_cache.has(path):
		return _tex_cache[path]
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path)
	_tex_cache[path] = t
	return t

## A tiling surface material. World-space triplanar mapping, so texel density
## is the same on a 10 cm rib and a 44 m wall - the web build had to hand-tune
## a repeat per box and still smeared thin members 125:1.
static func surface_mat(albedo: String, normal := "", rough := "", tile := Vector3(3, 3, 3),
		color := Color.WHITE, roughness := 0.9, metallic := 0.0, ao := "") -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	if albedo != "":
		m.albedo_texture = tex(albedo)
	if normal != "":
		m.normal_enabled = true
		m.normal_texture = tex(normal)
	if rough != "":
		m.roughness_texture = tex(rough)
	if ao != "" and tex(ao) != null:
		m.ao_enabled = true
		m.ao_texture = tex(ao)
		m.ao_light_affect = 0.35
	m.roughness = roughness
	m.metallic = metallic
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(1.0 / tile.x, 1.0 / tile.y, 1.0 / tile.z)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m

## A CC0 scan set from ambientCG (assets/cc0/<id>): colour, GL normal,
## roughness and AO where the set ships one, through surface_mat. roughness
## is a multiplier on the map, as StandardMaterial3D reads it.
static func cc0(id: String, tile: float, color := Color.WHITE, roughness := 1.0, metallic := 0.0,
		use_albedo := true) -> StandardMaterial3D:
	var base := "res://assets/cc0/%s/%s_1K-JPG_" % [id, id]
	var m := surface_mat(base + "Color.jpg" if use_albedo else "", base + "NormalGL.jpg", base + "Roughness.jpg",
		Vector3(tile, tile, tile), color, roughness, metallic, base + "AmbientOcclusion.jpg")
	return m

## drop a scan's roughness map for one value: several are shot wet or
## polished (grass .26, travertine .04) and mirror the sky under this rig
static func even_rough(m: StandardMaterial3D, r: float) -> StandardMaterial3D:
	m.roughness_texture = null
	m.roughness = r
	return m

static func flat_mat(color: Color, roughness := 0.9, metallic := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	return m

static func emissive_mat(color: Color, energy := 2.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m

static func _fill(img: Image, r: Rect2i, c: Color) -> void:
	var clipped := r.intersection(Rect2i(0, 0, img.get_width(), img.get_height()))
	if clipped.size.x > 0 and clipped.size.y > 0:
		img.fill_rect(clipped, c)

## Painted blockwork for the supermarket walls: off-white running bond with
## grey mortar, scuffed. The scanned concrete block the web build started with
## read as a dungeon under the tube lights.
static func painted_block() -> Array:
	var S := 512
	var img := Image.create(S, S, false, Image.FORMAT_RGB8)
	img.fill(Color8(180, 177, 168))
	var cols := 8
	var rows := 13
	var bw := S / cols
	var bh := S / rows
	var j := 3
	for r in rows:
		var off := bw / 2 if r % 2 == 1 else 0
		for c in range(-1, cols + 1):
			var v := randi_range(-8, 8)
			_fill(img, Rect2i(c * bw + off + 1, r * bh + 1, bw - j, bh - j), Color8(214 + v, 210 + v, 200 + v))
	for k in 9000:
		var px := randi() % S
		var py := randi() % S
		img.set_pixel(px, py, img.get_pixel(px, py).darkened(randf_range(0.04, 0.16)))
	var height := img.duplicate() as Image
	height.convert(Image.FORMAT_L8)
	height.convert(Image.FORMAT_RGBA8)
	height.bump_map_to_normal_map(2.0)
	img.generate_mipmaps()
	height.generate_mipmaps()
	return [ImageTexture.create_from_image(img), ImageTexture.create_from_image(height)]

## Suspended acoustic ceiling tiles: a T-bar grid and the odd water stain.
## A flat near-black ceiling made the fixtures float in a void.
## Six 600 mm tiles a side, to line up with the OfficeCeiling001 normal and
## roughness it is paired with (3.6 m a repeat).
static func ceiling_tile() -> ImageTexture:
	var S := 512
	var n := 6
	var img := Image.create(S, S, false, Image.FORMAT_RGB8)
	img.fill(Color8(96, 97, 94))
	for r in n:
		for c in n:
			var x0 := int(c * S / float(n))
			var y0 := int(r * S / float(n))
			var x1 := int((c + 1) * S / float(n))
			var y1 := int((r + 1) * S / float(n))
			var v := randi_range(-7, 7)
			# no missing tiles: at a 3.6 m repeat one gap reads as a pattern
			var col := Color8(204 + v, 203 + v, 196 + v)
			_fill(img, Rect2i(x0 + 2, y0 + 2, x1 - x0 - 3, y1 - y0 - 3), col)
			if randf() < 0.1:
				var cx := x0 + randi_range(18, x1 - x0 - 18)
				var cy := y0 + randi_range(18, y1 - y0 - 18)
				for k in 700:
					var a := randf() * TAU
					var d := sqrt(randf()) * 26.0
					var x := clampi(int(cx + cos(a) * d), x0 + 2, x1 - 2)
					var y := clampi(int(cy + sin(a) * d * 0.8), y0 + 2, y1 - 2)
					img.set_pixel(x, y, img.get_pixel(x, y).lerp(Color8(122, 98, 62), 0.06))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

# ---------------------------------------------------------------- models

## An instantiated model library, cached and never added to the tree. Parts
## are duplicated out of it, so meshes and materials are shared by reference.
static func glb(path: String) -> Node3D:
	if _glb_cache.has(path):
		return _glb_cache[path]
	var inst: Node3D = null
	if ResourceLoader.exists(path):
		var ps: PackedScene = load(path)
		if ps:
			inst = ps.instantiate() as Node3D
	_glb_cache[path] = inst
	return inst

static func part(path: String, part_name: String) -> Node3D:
	var lib := glb(path)
	if lib == null:
		return null
	var n := lib.find_child(part_name, true, false)
	if n == null:
		return null
	return n.duplicate() as Node3D

static func part_names(path: String) -> Array:
	var lib := glb(path)
	var out := []
	if lib:
		for c in lib.get_children():
			out.append(c.name)
	return out

## Bounds of every mesh under root, in root's own space. Works before the node
## is in the tree, which global_transform does not.
static func local_aabb(root: Node3D) -> AABB:
	var res := AABB()
	var first := true
	var stack: Array = [[root, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var e: Array = stack.pop_back()
		var n: Node = e[0]
		var xf: Transform3D = e[1]
		if n is MeshInstance3D and (n as MeshInstance3D).mesh:
			var a: AABB = xf * (n as MeshInstance3D).mesh.get_aabb()
			if first:
				res = a
				first = false
			else:
				res = res.merge(a)
		for c in n.get_children():
			if c is Node3D:
				stack.append([c, xf * (c as Node3D).transform])
	return res

static func set_layers(root: Node, layer_bits: int) -> void:
	if root is VisualInstance3D:
		(root as VisualInstance3D).layers = layer_bits
	for c in root.get_children():
		set_layers(c, layer_bits)

## Fold every mesh under root into one MeshInstance3D, a surface per
## material: a forty-part prop becomes a couple of draws. Transforms are
## baked relative to root.
static func merge_by_material(root: Node3D) -> MeshInstance3D:
	var tools := {}
	var stack: Array = [[root, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var e: Array = stack.pop_back()
		var n: Node = e[0]
		var xf: Transform3D = e[1]
		if n is MeshInstance3D and (n as MeshInstance3D).mesh:
			var mi := n as MeshInstance3D
			for si in mi.mesh.get_surface_count():
				var mat := mi.get_active_material(si)
				if not tools.has(mat):
					var st := SurfaceTool.new()
					st.begin(Mesh.PRIMITIVE_TRIANGLES)
					tools[mat] = st
				(tools[mat] as SurfaceTool).append_from(mi.mesh, si, xf)
		for c in n.get_children():
			if c is Node3D:
				stack.append([c, xf * (c as Node3D).transform])
	var am := ArrayMesh.new()
	for mat in tools:
		var st: SurfaceTool = tools[mat]
		st.set_material(mat)
		st.commit(am)
	var out := MeshInstance3D.new()
	out.mesh = am
	return out

static func set_shadows(root: Node, on: bool) -> void:
	if root is GeometryInstance3D:
		(root as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in root.get_children():
		set_shadows(c, on)

# ---------------------------------------------------------------- material fixes

## The scanned prop packs ship the same defects under Godot's glTF importer as
## they did under three.js, so the same fixes apply:
##  - glTF's default metallicFactor is 1. With no metallic texture that is a
##    pure mirror: no diffuse term, renders black at night. Trees were holes.
##  - Cutouts exported as BLEND with alpha 1 sort by draw order and pop. Cut
##    them out instead (glass stays blended).
##  - One facade binds its colour image as its normal map.
##  - Near-black albedos no light rig can lift.
static func fix_materials(root: Node, lift_dark := true) -> void:
	var seen := {}
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(i)
			if mat is StandardMaterial3D and not seen.has(mat):
				seen[mat] = true
				_fix_one(mat as StandardMaterial3D, str(mi.name) + " " + str(mi.get_parent().name), lift_dark)

static func _fix_one(m: StandardMaterial3D, tag: String, lift_dark: bool) -> void:
	var t := (tag + " " + m.resource_name).to_lower()
	var foliage := false
	for w in ["tree", "leaf", "leaves", "foliage", "bush", "plant", "frond", "grass", "shrub"]:
		if t.contains(w):
			foliage = true
	if (m.metallic >= 0.99 and m.metallic_texture == null) or foliage:
		m.metallic = 0.0
		if foliage:
			m.metallic_texture = null
			m.roughness = maxf(m.roughness, 0.75)
	var glassy := t.contains("glass") or t.contains("window") or t.contains("water") or t.contains("screen")
	if m.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and m.albedo_color.a >= 0.99 and m.albedo_texture != null and not glassy:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.45
		m.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if m.normal_texture != null and m.normal_texture == m.albedo_texture:
		m.normal_enabled = false
		m.normal_texture = null
	if lift_dark and m.albedo_texture == null:
		var c := m.albedo_color
		var cl := c.srgb_to_linear()
		var lum := 0.2126 * cl.r + 0.7152 * cl.g + 0.0722 * cl.b
		const FLOOR := 0.055
		if lum < FLOOR:
			var lifted: Color
			if lum <= 0.000001:
				lifted = Color(FLOOR, FLOOR, FLOOR, 1.0)
			else:
				var k := FLOOR / lum
				lifted = Color(minf(1.0, cl.r * k), minf(1.0, cl.g * k), minf(1.0, cl.b * k), 1.0)
			var s := lifted.linear_to_srgb()
			m.albedo_color = Color(s.r, s.g, s.b, c.a)
