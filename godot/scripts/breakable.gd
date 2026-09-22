## A prop a round can destroy. The web build's BREAK_KINDS: glass goes in a
## couple of rounds, a crate takes a burst, a bench takes a mag. When it goes
## it throws chips sized off its own bounds (clamped, so a shelf does not
## shed half-metre slabs) and the body - collider and all - is gone.
extends StaticBody3D

const KINDS := {
	"glass":   {"hp": 14.0,  "kind": "glass",    "col": Color("bcd6e2"), "chips": 16},
	"wood":    {"hp": 60.0,  "kind": "wood",     "col": Color("7a5a38"), "chips": 12},
	"crate":   {"hp": 45.0,  "kind": "wood",     "col": Color("8a6a42"), "chips": 12},
	"pottery": {"hp": 18.0,  "kind": "concrete", "col": Color("c0a184"), "chips": 14},
	"plaster": {"hp": 110.0, "kind": "concrete", "col": Color("b9b3a4"), "chips": 14},
	"metal":   {"hp": 170.0, "kind": "metal",    "col": Color("9aa0a4"), "chips": 10},
}

var def: Dictionary
var hp := 1.0
var size := Vector3.ONE        # the prop's bounds, for chip sizing
var centre := Vector3.ZERO     # local

func setup(kind: String, bounds_size: Vector3, bounds_centre: Vector3, hp_scale := 1.0) -> void:
	def = KINDS.get(kind, KINDS.crate)
	hp = def.hp * hp_scale
	size = bounds_size
	centre = bounds_centre
	set_meta("surface", def.kind)

## a round landed on it
func shoot(dmg: float, _at: Vector3, dir: Vector3) -> void:
	if hp <= 0.0:
		return
	hp -= dmg
	if hp <= 0.0:
		shatter(dir)

func shatter(dir := Vector3.ZERO) -> void:
	hp = 0.0
	var c := to_global(centre)
	Debris.burst(get_tree().current_scene, c, size, def.col, mini(def.chips, 18), dir)
	match def.kind:
		"glass":
			Game.play_at("hit_glass", c, 2.0, 0.85)
			Game.play_at("hit_glass", c, -2.0, 1.2)
		"wood":
			Game.play_at("hit_wood", c, 2.0, 0.72)
			Game.play_at("hit_wood", c, -3.0, 0.9)
		"metal":
			Game.play_at("hit_metal", c, 2.0, 0.7)
		_:
			# fired clay: a dull crack with a bright ring on top
			Game.play_at("hit_concrete", c, 1.0, 1.15)
			Game.play_at("hit_glass", c, -6.0, 1.45)
	queue_free()


## Chips from every shatter, stepped by one node so a firefight does not
## leave hundreds of scripts running. The web's debrisUpdate, near enough.
class Debris extends Node3D:
	static var _box: BoxMesh
	static var _mats := {}
	var chips := []      # [MeshInstance3D, velocity, spin, life]

	static func burst(host: Node, at: Vector3, sz: Vector3, col: Color, n: int, dir: Vector3) -> void:
		if host == null:
			return
		var d: Debris = host.get_node_or_null("Debris")
		if d == null:
			d = Debris.new()
			d.name = "Debris"
			host.add_child(d)
		if _box == null:
			_box = BoxMesh.new()
		var away := Vector3(dir.x, 0, dir.z)
		if away.length() < 0.01:
			away = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
		away = away.normalized()
		for i in n:
			var m := MeshInstance3D.new()
			m.mesh = _box
			m.material_override = _mat(col * randf_range(0.7, 1.15))
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var chip := func(e: float) -> float: return clampf(e * randf_range(0.06, 0.2), 0.04, 0.34)
			m.scale = Vector3(chip.call(sz.x), chip.call(sz.y), chip.call(sz.z))
			d.add_child(m)
			m.global_position = at + Vector3(randf_range(-1, 1) * sz.x * 0.4, randf_range(-1, 1) * sz.y * 0.4, randf_range(-1, 1) * sz.z * 0.4)
			m.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
			var v := Vector3(away.x * randf_range(0.5, 3.4) + randf_range(-1.4, 1.4), randf_range(1.4, 5.2),
				away.z * randf_range(0.5, 3.4) + randf_range(-1.4, 1.4))
			var spin := Vector3(randf_range(-9, 9), randf_range(-9, 9), randf_range(-9, 9))
			d.chips.append([m, v, spin, randf_range(2.6, 4.4), m.scale])

	## a handful of shades per colour, shared, rather than a material per chip
	static func _mat(c: Color) -> StandardMaterial3D:
		var k := Color(snappedf(c.r, 0.05), snappedf(c.g, 0.05), snappedf(c.b, 0.05))
		if not _mats.has(k):
			var m := StandardMaterial3D.new()
			m.albedo_color = k
			m.roughness = 0.9
			_mats[k] = m
		return _mats[k]

	func _process(dt: float) -> void:
		var i := chips.size() - 1
		while i >= 0:
			var p: Array = chips[i]
			var m: MeshInstance3D = p[0]
			p[3] -= dt
			p[1].y -= 19.0 * dt
			m.position += p[1] * dt
			if m.position.y < 0.03:
				m.position.y = 0.03
				p[1].y *= -0.32
				p[1].x *= 0.7
				p[1].z *= 0.7
				p[2] *= 0.6
			m.rotation += p[2] * dt
			if p[3] < 0.7:
				m.scale = p[4] * maxf(0.0, p[3] / 0.7)    # shrink out, no transparency pass
			if p[3] <= 0.0:
				m.queue_free()
				chips.remove_at(i)
			i -= 1
