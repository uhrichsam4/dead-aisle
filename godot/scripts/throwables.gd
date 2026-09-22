## Carts, watermelons and axes: F picks one up, F throws it. The web build's
## THROWABLES - ballistic and spinning, with a SWEPT test against people (a
## melon covers ~0.8 m a frame, more than its hit radius, so a point test
## tunnels straight through a man) and bounces off anything solid. Melons
## burst, axes stick where they land, a cart smashes whatever it hits.
extends Node3D

const U := preload("res://scripts/util.gd")
const MQ := preload("res://scripts/mosque.gd")
const BreakScript := preload("res://scripts/breakable.gd")

const DEFS := {
	"cart": {"label": "SHOPPING CART", "fit": 1.05, "by": "y", "damage": 70.0, "radius": 0.6,
		"hold": Vector3(0.62, -0.78, -1.15), "spin": 5.5, "power": 11.0, "surface": "metal"},
	"watermelon": {"label": "WATERMELON", "fit": 0.3, "by": "max", "damage": 34.0, "radius": 0.28,
		"hold": Vector3(0.26, -0.24, -0.52), "spin": 11.0, "power": 15.5, "burst": true},
	"axe": {"label": "THROWING AXE", "fit": 0.75, "by": "max", "damage": 120.0, "radius": 0.34,
		"hold": Vector3(0.30, -0.26, -0.62), "spin": 16.0, "power": 19.0, "stick": true, "surface": "wood"},
}
# carts round the lot, melons inside and out, axes where you would find one
const SPOTS := [
	["cart", 6.2, 24.5], ["cart", -7.4, 25.8], ["cart", 12.5, 21.0], ["cart", -14.0, 20.4],
	["watermelon", 3.2, 26.5], ["watermelon", -4.6, 23.2], ["watermelon", 10.4, 27.1],
	["watermelon", -5.5, 6.2], ["watermelon", 5.2, 6.4], ["watermelon", -12.4, -1.2], ["watermelon", 13.0, -4.5],
	["watermelon", 0.0, -10.2], ["watermelon", -18.0, 9.0], ["watermelon", 17.5, 10.5],
	["axe", -16.5, 12.5], ["axe", 15.8, -12.2], ["axe", -2.5, -13.4], ["axe", 19.5, 4.5],
	["axe", -10.5, 22.5], ["axe", 9.5, 26.8],
]
# act 2: only the axes move to the mosque - carts and melons in a prayer hall
# read as a bug, but the axe is the secondary weapon (mosque-local coords)
const AXE_SPOTS2 := [[-16, 10], [16, 10], [-20, -6], [20, -6], [0, -13], [-11, 6], [11, 6],
	[-6, -9], [6, -9], [0, 4], [-18, 2], [18, 2], [8, 20], [-8, 22], [13, 24]]

var items := []          # dictionaries, see _spawn
var held = null
var player: Node
var hud: Node
var _proto := {}
var _hint_ours := false
var _hint_saved := ""

func setup(p: Node, h: Node) -> void:
	player = p
	hud = h
	var lib := U.glb("res://assets/throwables.glb")
	if lib:
		U.fix_materials(lib)       # the trolley's wire is a blended cutout
		for c in lib.get_children():
			var n := str(c.name).to_lower()
			if n.contains("cart"):
				_proto.cart = c
			elif n.contains("melon"):
				_proto.watermelon = c
	var axe := U.glb("res://assets/axe.glb")
	if axe:
		U.fix_materials(axe)
		# fifty-odd parts, each its own draw, times six on the floor: fold once
		_proto.axe = U.merge_by_material(axe)
	for s in SPOTS:
		_spawn(s[0], Vector3(s[1], 0, s[2]))

func _spawn(type: String, at: Vector3) -> void:
	if not _proto.has(type):
		return
	var d: Dictionary = DEFS[type]
	var src: Node3D = _proto[type]
	var holder := Node3D.new()          # the item spins about its middle
	holder.name = type
	var m := src.duplicate() as Node3D
	m.transform = Transform3D.IDENTITY if type == "axe" else Transform3D(Basis.from_scale(src.scale), Vector3.ZERO)
	holder.add_child(m)
	var a := U.local_aabb(holder)
	var ext := a.size.y if d.by == "y" else maxf(a.size.x, maxf(a.size.y, a.size.z))
	var k := float(d.fit) / maxf(0.001, ext)
	m.scale *= k
	m.position = -a.get_center() * k
	U.set_shadows(holder, true)
	add_child(holder)
	var rest := a.size.y * k * 0.5         # centre height when it sits on its base
	holder.global_position = Vector3(at.x, rest, at.z)
	holder.rotation.y = randf() * TAU
	items.append({"type": type, "def": d, "node": holder, "state": "ground", "vel": Vector3.ZERO,
		"spin": Vector3.ZERO, "life": 0.0, "rest": rest, "home": holder.global_position})

# ------------------------------------------------------------------ pick up / throw

func nearest():
	if held != null:
		return null
	var best = null
	var bd := 2.6
	var fwd: Vector3 = -player.camera.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.001 else Vector3.FORWARD
	var pp: Vector3 = player.global_position
	for t in items:
		if t.state != "ground" or not t.node.visible:
			continue
		var to: Vector3 = t.node.global_position - pp
		to.y = 0.0
		var d := to.length()
		if d > bd:
			continue
		if d > 0.4 and to.dot(fwd) / d < 0.1:
			continue          # roughly ahead of you
		bd = d
		best = t
	return best

func pick_up(t) -> void:
	if t == null or held != null:
		return
	held = t
	t.state = "held"
	var n: Node3D = t.node
	n.get_parent().remove_child(n)
	player.vm_cam.add_child(n)
	U.set_layers(n, 2)
	U.set_shadows(n, false)
	n.position = t.def.hold
	n.rotation = Vector3.ZERO
	player.holding = true
	player.show_rifle(false)
	hud.wname.text = t.def.label
	Game.play("gear_strap", -8.0)

func throw_held() -> void:
	var t = held
	if t == null:
		return
	held = null
	var n: Node3D = t.node
	var cam: Camera3D = player.camera
	var at: Vector3 = cam.global_transform * t.def.hold
	n.get_parent().remove_child(n)
	add_child(n)
	U.set_layers(n, 1)
	U.set_shadows(n, true)
	n.global_position = at
	n.rotation = Vector3.ZERO
	t.state = "flying"
	t.life = 0.0
	t.vel = -cam.global_basis.z * float(t.def.power) + Vector3(0, 3.1, 0)
	t.spin = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized() * float(t.def.spin)
	player.holding = false
	player.show_rifle(true)
	player.refresh_ammo()
	Game.play("pain_effort", -10.0, 1.1)     # it is heavy
	Game.play("gear_rustle", -8.0, 1.3)

## put it down and give the rifle back (death, the act change)
func drop_held() -> void:
	var t = held
	if t == null:
		return
	held = null
	var n: Node3D = t.node
	n.get_parent().remove_child(n)
	add_child(n)
	U.set_layers(n, 1)
	n.visible = false
	t.state = "gone"
	player.holding = false
	player.show_rifle(true)

func _unhandled_input(e: InputEvent) -> void:
	if not e.is_action_pressed("throw") or player == null or not player.active or not player.alive or player.input_locked:
		return
	if Game.phase not in ["outside", "inside"]:
		return
	if held != null:
		throw_held()
	else:
		pick_up(nearest())

## act 2: carts and melons stay behind, the axes turn up round the mosque
func act2() -> void:
	drop_held()
	var i := 0
	for t in items:
		t.vel = Vector3.ZERO
		t.spin = Vector3.ZERO
		if t.type != "axe":
			t.node.visible = false
			t.state = "gone"
			continue
		var s: Array = AXE_SPOTS2[i % AXE_SPOTS2.size()]
		i += 1
		t.node.visible = true
		t.state = "ground"
		t.node.rotation = Vector3(0, randf() * TAU, 0)
		t.node.global_position = Vector3(MQ.mqx(s[0]), t.rest + 0.02, MQ.mqz(s[1]))

# ------------------------------------------------------------------ flight

func _physics_process(dt: float) -> void:
	var space := get_world_3d().direct_space_state
	for t in items:
		if t.state != "flying":
			continue
		t.life += dt
		t.vel.y -= 19.0 * dt
		var n: Node3D = t.node
		var p0 := n.global_position
		var p1: Vector3 = p0 + t.vel * dt
		var r: float = t.def.radius
		n.rotation += t.spin * dt
		# people: closest approach of this frame's segment to each chest
		var seg := p1 - p0
		var seg2 := maxf(seg.length_squared(), 1e-6)
		var struck := false
		for h in get_tree().get_nodes_in_group("hostiles"):
			if not h.is_active():
				continue
			var chest: Vector3 = (h as Node3D).global_position + Vector3(0, 1.05, 0)
			var u := clampf((chest - p0).dot(seg) / seg2, 0.0, 1.0)
			var c := p0 + seg * u
			var dxz := Vector2(c.x - chest.x, c.z - chest.z).length()
			if dxz < r + 0.55 and absf(c.y - chest.y) < 1.15:
				var dir := Vector3(t.vel.x, 0, t.vel.z).normalized()
				var killed: bool = h.take_hit(float(t.def.damage), chest + Vector3(0, 0.05, 0), dir)
				player.hit_marker.emit(false, killed)
				player.shake = maxf(player.shake, 0.35)
				t.vel *= -0.22
				t.vel.y = 2.4
				if t.def.get("burst", false):
					_burst(t, c)
				struck = true
				break
		if struck:
			if t.state == "flying":
				n.global_position = p0
			continue
		# walls, shelving, props: bounce off, smash anything breakable
		if seg.length() > 0.0001:
			var q := PhysicsRayQueryParameters3D.create(p0, p1 + seg.normalized() * r, 1 | 32)
			var hit := space.intersect_ray(q)
			if not hit.is_empty() and hit.normal.y < 0.7:
				var nrm: Vector3 = hit.normal
				var col = hit.collider
				if col is Node and (col as Node).has_method("shoot"):
					col.call("shoot", float(t.def.damage) * 0.6, hit.position, seg.normalized())
				var speed2: float = t.vel.length_squared()
				Game.play_at("hit_" + str(t.def.get("surface", "wood")), hit.position, -4.0 if speed2 > 9.0 else -12.0)
				if t.def.get("burst", false) and t.life > 0.12 and speed2 > 9.0:
					_burst(t, hit.position)
					continue
				var vn: Vector3 = t.vel.project(nrm)
				t.vel = (t.vel - vn - vn * 0.35) * 0.72
				t.spin *= 0.6
				p1 = hit.position + nrm * r
		# the floor
		var rest: float = t.rest + 0.02
		if p1.y <= rest:
			p1.y = rest
			if t.def.get("burst", false) and t.life > 0.12:
				_burst(t, p1)
				continue
			if t.vel.length_squared() > 4.0:
				Game.play_at("hit_" + str(t.def.get("surface", "wood")), p1, -10.0, 0.8)
			t.vel = Vector3(t.vel.x * 0.6, -t.vel.y * 0.28, t.vel.z * 0.6)
			t.spin *= 0.5
			if t.def.get("stick", false):
				# the axe bites and stays where it lands
				t.state = "ground"
				t.vel = Vector3.ZERO
				t.spin = Vector3.ZERO
				n.global_position = Vector3(p1.x, rest, p1.z)
				n.rotation = Vector3(randf_range(-0.2, 0.2), randf() * TAU, PI * 0.5 + randf_range(-0.25, 0.25))
				continue
			if absf(t.vel.y) < 1.2 and t.vel.length_squared() < 1.6:
				t.state = "ground"
				t.vel = Vector3.ZERO
				n.rotation = Vector3(0, n.rotation.y, 0)
		if t.life > 14.0:
			t.state = "ground"
			t.vel = Vector3.ZERO
		n.global_position = p1

## a melon meets something at speed
func _burst(t, at: Vector3) -> void:
	t.state = "gone"
	t.node.visible = false
	var dir := Vector3(t.vel.x, 0, t.vel.z)
	BreakScript.Debris.burst(get_tree().current_scene, at, Vector3(0.3, 0.3, 0.3), Color(0.86, 0.22, 0.28), 12, dir)
	BreakScript.Debris.burst(get_tree().current_scene, at, Vector3(0.3, 0.3, 0.3), Color(0.2, 0.42, 0.16), 6, dir)
	Game.play_file_at("sfx-body-drop.mp3", at, -6.0, randf_range(1.5, 1.8), 25.0)

# ------------------------------------------------------------------ prompt

func _process(_dt: float) -> void:
	if player == null or hud == null:
		return
	var text := ""
	if player.active and player.alive and Game.phase in ["outside", "inside"]:
		if held != null:
			text = "F THROW"
		else:
			var t = nearest()
			if t != null:
				text = "F PICK UP " + str(t.def.label)
	if text != "":
		if not _hint_ours:
			_hint_saved = hud.hint.text
			_hint_ours = true
		if hud.hint.text != text:
			hud.set_hint(text)
	elif _hint_ours:
		_hint_ours = false
		hud.set_hint(_hint_saved)
