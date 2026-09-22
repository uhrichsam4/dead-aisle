## DEAD AISLE - main scene. Builds the lighting and the world, spawns the
## player, the car and the hostile pool, and runs act 1:
## drive to TOPS -> park -> get out -> fight to the doors -> clear the store.
extends Node3D

const U := preload("res://scripts/util.gd")
const WorldScript := preload("res://scripts/world.gd")
const PlayerScript := preload("res://scripts/player.gd")
const CarScript := preload("res://scripts/car.gd")
const HostileScript := preload("res://scripts/hostile.gd")
const HudScript := preload("res://scripts/hud.gd")
const ArrivalScript := preload("res://scripts/arrival.gd")
const SurvivorScript := preload("res://scripts/survivor.gd")
const MosqueScript := preload("res://scripts/mosque.gd")
const MenuScript := preload("res://scripts/menu.gd")
const ThrowScript := preload("res://scripts/throwables.gd")
# act 2 tables, in mosque-LOCAL coordinates (the web build's own numbers)
const OUTSIDE_PTS2 := [[-20, 18], [20, 19], [-8, 28], [14, 29], [-16, 24], [6, 22]]
const INSIDE_PTS2 := [[-21.7, -12.7], [-12.6, -12.7], [-3.5, -12.7], [5.7, -12.7], [14.8, -12.7],
	[-17.2, -4.9], [-8, -4.9], [1.1, -4.9], [10.2, -4.9], [22, -6.9], [-16.5, 4.2], [-7.4, 4.2], [7, 4.2], [16.1, 4.2]]
const SURV_SPOTS2 := [[-17.2, -4.9], [10.2, -4.9], [-12.6, -12.7], [14.8, -12.7]]
const SURV_SPOTS := [[-16.4, 11.0], [16.4, 10.6], [-19.5, -12.5], [18.8, -3.0]]

const CAR_START := Vector3(124, 0, 36.5)
const OUTSIDE_PTS := [[-20, 28], [20, 27], [-8, 26], [24, 23.5], [-24, 22], [14, 29]]
const INSIDE_PTS := [[-19, -12], [19, -12], [-19, -6], [19, -6], [-8, -11], [8, -11], [-16, 0], [16, 0],
	[-19, 5], [19, 5], [-10, 9], [10, 9], [-17, 13], [17, 13], [0, -9.4], [3, -12]]
const POOL := 26          # the web's actor pool

var world: NavigationRegion3D
var mosque: NavigationRegion3D
var player: CharacterBody3D
var car: CharacterBody3D
var hud: CanvasLayer
var post: ShaderMaterial
var hostiles: Array = []
var emergency: OmniLight3D
var arrival: Node
var survivors: Array = []
var cleared := false
var rescued := 0
var inside_left := 0        # hostiles still to come inside (the web's trickle)
var _trickle_t := 0.0
var menu: CanvasLayer
var throwables: Node3D
var menu_cam: Camera3D
var post_layer: CanvasLayer
var moon: DirectionalLight3D
var _drive_t := 0.0
var _crowd_groan_t := 4.0

func _ready() -> void:
	randomize()
	_environment()
	world = WorldScript.new()
	world.name = "World"
	add_child(world)
	world.build()
	mosque = MosqueScript.new()
	mosque.name = "Mosque"
	add_child(mosque)
	mosque.build()

	car = CarScript.new()
	car.name = "Car"
	add_child(car)
	car.global_position = CAR_START
	car.rotation.y = PI / 2
	car.parked.connect(_on_parked)

	player = PlayerScript.new()
	player.name = "Player"
	add_child(player)
	player.activate(false)
	player.global_position = Vector3(8.2, 0, 22.6)

	for i in POOL:
		var h: CharacterBody3D = HostileScript.new()
		h.name = "Hostile%d" % i
		add_child(h)
		h.killed.connect(_on_kill)
		hostiles.append(h)

	for i in SURV_SPOTS.size():
		var sv: CharacterBody3D = SurvivorScript.new()
		sv.name = "Survivor%d" % i
		# the supplied survivors: survivor_1..4.glb, reusing the first until
		# the others arrive
		var mp := "res://assets/survivor_%d.glb" % (i + 1)
		sv.model_path = mp if ResourceLoader.exists(mp) else "res://assets/survivor_1.glb"
		sv.add_to_group("survivors")
		add_child(sv)
		sv.place(Vector3(SURV_SPOTS[i][0], 0.05, SURV_SPOTS[i][1]), player)
		sv.found.connect(_on_survivor_found)
		survivors.append(sv)

	_post()
	arrival = ArrivalScript.new()
	arrival.name = "Arrival"
	add_child(arrival)
	arrival.finished.connect(_begin_outside)
	hud = HudScript.new()
	add_child(hud)
	hud.player = player
	hud.car = car
	player.hp_changed.connect(hud.set_hp)
	player.ammo_changed.connect(hud.set_ammo)
	player.hit_marker.connect(hud.on_hit)
	player.damaged.connect(hud.on_damage)
	player.died.connect(_on_died)
	player.select_weapon(0, true)
	throwables = ThrowScript.new()
	throwables.name = "Throwables"
	add_child(throwables)
	throwables.setup(player, hud)
	var folk := preload("res://scripts/pedestrians.gd").new()
	folk.name = "Pedestrians"
	add_child(folk)
	folk.setup(car, player)

	# bake the navmesh once the world has settled
	get_tree().create_timer(0.5, false).timeout.connect(world.bake_nav)
	get_tree().create_timer(1.2, false).timeout.connect(mosque.bake_nav)

	menu = MenuScript.new()
	menu.name = "Menu"
	add_child(menu)
	menu.play_pressed.connect(_on_play)
	menu.quit_to_menu.connect(_quit_to_menu)
	Game.settings_changed.connect(_apply_video)
	_apply_video()
	if Game.quick_deploy:
		Game.quick_deploy = false
		_start_drive()
	else:
		_show_lobby()

## the lobby sits over the live world: a slow orbit round the car at the
## start line, its radio already playing
## The web's lobby: four pads in the TOPS lot, your operator on the first in
## the outfit you picked, the other three waiting for a party, and a camera
## that drifts so the shot is never dead still (LOBBY.camPos / camLook).
const LOBBY_CAM := Vector3(2.1, 1.5, 26.6)
const LOBBY_LOOK := Vector3(-0.35, 1.05, 20.6)
var lobby_group: Node3D
var lobby_rings: Array[MeshInstance3D] = []
var lobby_doll: Node3D
var _lobby_t := 0.0

func _show_lobby() -> void:
	Game.set_phase("menu")
	hud.visible = false
	menu_cam = Camera3D.new()
	menu_cam.fov = 70.0
	menu_cam.far = 900.0
	menu_cam.cull_mask = 0xFFFFF & ~2
	add_child(menu_cam)
	menu_cam.current = true
	lobby_group = Node3D.new()
	lobby_group.name = "Lobby"
	add_child(lobby_group)
	for i in 4:
		var x := -2.55 + i * 1.7
		var pad := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.62
		cm.bottom_radius = 0.62
		cm.height = 0.06
		cm.radial_segments = 28
		pad.mesh = cm
		var pm := StandardMaterial3D.new()
		pm.albedo_color = Color("4a3b16") if i == 0 else Color("2b2f36")
		pm.roughness = 0.5
		pm.metallic = 0.4
		pm.emission_enabled = true
		pm.emission = Color("6a5410") if i == 0 else Color("101418")
		pad.material_override = pm
		pad.position = Vector3(x, 0.04, 20.6)
		lobby_group.add_child(pad)
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.62
		tm.outer_radius = 0.86
		tm.rings = 36
		ring.mesh = tm
		ring.scale = Vector3(1, 0.04, 1)
		var rm := StandardMaterial3D.new()
		rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		rm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		rm.albedo_color = Color("f6d434") if i == 0 else Color("3d6f8a")
		rm.albedo_color.a = 0.5
		ring.material_override = rm
		ring.position = Vector3(x, 0.09, 20.6)
		lobby_group.add_child(ring)
		lobby_rings.append(ring)
	_lobby_doll(menu.skin_index())
	menu.skin_changed.connect(_lobby_doll)
	menu.show_screen("lobby")

## pad 0: you, in your outfit, idling, turned to the camera
func _lobby_doll(idx: int) -> void:
	if lobby_doll:
		lobby_doll.queue_free()
	var skin: Dictionary = menu.SKINS[idx]
	var path := "res://assets/skin_suit.glb" if skin.id == "suit" else "res://assets/operator.glb"
	var ps: PackedScene = load(path)
	if ps == null:
		return
	lobby_doll = Node3D.new()
	var model := ps.instantiate() as Node3D
	model.rotation.y = PI
	lobby_doll.add_child(model)
	var a := U.local_aabb(model)
	var s := 1.78 / maxf(0.2, a.size.y)
	model.scale *= s
	model.position.y = -a.position.y * s
	var cam := model.find_child("action_camera", true, false) as Node3D
	if cam:
		cam.visible = false
	if skin.has("pal"):
		_apply_skin(model, skin)
	U.set_shadows(model, true)
	lobby_group.add_child(lobby_doll)
	lobby_doll.global_position = Vector3(-2.55, 0, 20.6)
	var d := LOBBY_CAM - lobby_doll.global_position
	lobby_doll.rotation.y = atan2(-d.x, -d.z) + (0 - 1.5) * 0.11     # fanned, as the web lines them up
	var ap := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap:
		var names := ap.get_animation_list()
		var pick := ""
		for n in names:
			if str(n).to_lower().contains("idle"):
				pick = n
				break
		if pick == "" and names.size() > 0:
			pick = names[0]
		if pick != "":
			ap.get_animation(pick).loop_mode = Animation.LOOP_LINEAR
			ap.play(pick)

## skinApply: clothing materials ranked dark to light take the palette in
## order; anything that reads as skin takes the skin tone
func _apply_skin(root: Node, skin: Dictionary) -> void:
	var mats := []
	var owners := []
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m3 := mi as MeshInstance3D
		for si in m3.mesh.get_surface_count():
			var m := m3.get_active_material(si)
			if m is StandardMaterial3D:
				if not mats.has(m):
					mats.append(m)
				owners.append([m3, si, m])
	# skinIsFlesh: HSL lightness > .42, saturation .12-.72, a warm hue
	var flesh := func(c: Color) -> bool:
		var mx := maxf(c.r, maxf(c.g, c.b))
		var mn := minf(c.r, minf(c.g, c.b))
		var l := (mx + mn) / 2.0
		var sat := 0.0 if mx == mn else (mx - mn) / (1.0 - absf(2.0 * l - 1.0))
		return l > 0.42 and sat > 0.12 and sat < 0.72 and (c.h < 0.13 or c.h > 0.94)
	var cloth := mats.filter(func(m): return not flesh.call((m as StandardMaterial3D).albedo_color))
	cloth.sort_custom(func(x, y): return (x as StandardMaterial3D).albedo_color.get_luminance() < (y as StandardMaterial3D).albedo_color.get_luminance())
	var pal: Array = skin.pal
	var swap := {}
	for i in cloth.size():
		var c := (cloth[i] as StandardMaterial3D).duplicate() as StandardMaterial3D
		c.albedo_color = Color(pal[mini(pal.size() - 1, int(floor(i * pal.size() / float(maxi(1, cloth.size())))))])
		swap[cloth[i]] = c
	for m in mats:
		if not swap.has(m):
			var c := (m as StandardMaterial3D).duplicate() as StandardMaterial3D
			c.albedo_color = Color(skin.skin)
			swap[m] = c
	for o in owners:
		(o[0] as MeshInstance3D).set_surface_override_material(o[1], swap[o[2]])

func _on_play() -> void:
	menu.show_screen("")
	hud.visible = true
	if lobby_group:
		lobby_group.queue_free()
		lobby_group = null
		lobby_doll = null
	if menu_cam:
		menu_cam.queue_free()
		menu_cam = null
	_start_drive()

func _quit_to_menu() -> void:
	get_tree().paused = false
	Game.reset_run()
	Game.quick_deploy = false
	get_tree().reload_current_scene()

## settings that live on scene objects rather than the engine
func _apply_video() -> void:
	if post_layer:
		post_layer.visible = bool(Game.settings.fx)
	for l in find_children("*", "Light3D", true, false):
		if not l.has_meta("had_shadow"):
			l.set_meta("had_shadow", (l as Light3D).shadow_enabled)
		(l as Light3D).shadow_enabled = bool(l.get_meta("had_shadow")) and bool(Game.settings.shadows)

# ------------------------------------------------------------------ setup

## LIGHT_DAY / LIGHT_NIGHT from the web build: broad daylight everywhere
## except inside, where it fades (dt * .55) to the dark bodycam interior
const DAY := {"fog": Color("8fb6cf"), "fogd": 0.0099, "amb": 0.9, "ambc": Color("cfdbe4"), "sun": 2.6,
	"sunc": Color("fff2dc"), "fill": 0.95, "fillc": Color("dfe8f2"), "sky": 1.0, "envi": 0.55}
const NIGHT := {"fog": Color("0b1014"), "fogd": 0.034, "amb": 0.38, "ambc": Color("50606f"), "sun": 1.0,
	"sunc": Color("9fb4d8"), "fill": 0.20, "fillc": Color("8ea4c4"), "sky": 0.12, "envi": 0.12}
var env: Environment
var sky_mat: PanoramaSkyMaterial
var fill: DirectionalLight3D
var light_mix := 1.0

func _light_apply(dt: float) -> void:
	var day := 0.0 if Game.phase == "inside" else 1.0
	light_mix += (day - light_mix) * clampf(dt * 0.55, 0.0, 1.0)
	var m := light_mix
	sky_mat.energy_multiplier = lerpf(NIGHT.sky, DAY.sky, m)
	env.fog_light_color = (NIGHT.fog as Color).lerp(DAY.fog, m)
	env.fog_density = lerpf(NIGHT.fogd, DAY.fogd, m)
	env.ambient_light_color = (NIGHT.ambc as Color).lerp(DAY.ambc, m)
	env.ambient_light_energy = lerpf(NIGHT.amb, DAY.amb, m)
	env.ambient_light_sky_contribution = lerpf(NIGHT.envi, DAY.envi, m)
	moon.light_energy = lerpf(NIGHT.sun, DAY.sun, m) * 0.62
	moon.light_color = (NIGHT.sunc as Color).lerp(DAY.sunc, m)
	fill.light_energy = lerpf(NIGHT.fill, DAY.fill, m) * 0.62
	fill.light_color = (NIGHT.fillc as Color).lerp(DAY.fillc, m)

func _environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky_mat = PanoramaSkyMaterial.new()
	sky_mat.panorama = U.tex("res://assets/tex/sky.jpg")
	sky_mat.energy_multiplier = 1.0
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 1.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.2, 0.24, 0.3)
	env.fog_density = DAY.fogd
	env.fog_sky_affect = 0.0          # three.js fog never touched the backdrop
	env.fog_aerial_perspective = 0.4
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.4
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	moon = DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = Color(0.72, 0.78, 0.9)
	moon.light_energy = 0.9
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 90.0
	add_child(moon)
	moon.look_at_from_position(Vector3(-14, 18, -8), Vector3.ZERO, Vector3.UP)
	# bounce/fill from the opposite side, no shadow: without it the whole TOPS
	# frontage and anyone crossing the lot at you is a silhouette
	fill = DirectionalLight3D.new()
	fill.name = "SunFill"
	fill.shadow_enabled = false
	add_child(fill)
	fill.look_at_from_position(Vector3(13, 11, 24), Vector3.ZERO, Vector3.UP)
	# the store's coloured practicals: a blue wash at the back, green by the
	# deli, and the EXIT glow over the doors
	for l in [[Color("5a7fae"), 12.0, 20.0, Vector3(0, 3, -13)], [Color("6a8a5a"), 9.0, 13.0, Vector3(-17, 3, 8)],
			[Color("44ff66"), 2.2, 5.5, Vector3(0, 3.9, 14)]]:
		var o := OmniLight3D.new()
		o.light_color = l[0]
		o.light_energy = l[1] * 0.12
		o.omni_range = l[2]
		o.omni_attenuation = 1.8
		o.position = l[3]
		add_child(o)

	emergency = OmniLight3D.new()
	emergency.light_color = Color(1, 0.16, 0.09)
	emergency.light_energy = 1.4
	emergency.omni_range = 24.0
	emergency.position = Vector3(0, 3.6, 0)
	add_child(emergency)

func _post() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 2
	add_child(layer)
	post_layer = layer
	var cr := ColorRect.new()
	cr.set_anchors_preset(Control.PRESET_FULL_RECT)
	cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	post = ShaderMaterial.new()
	post.shader = load("res://shaders/bodycam.gdshader")
	cr.material = post
	layer.add_child(cr)

# ------------------------------------------------------------------ mission

func _start_drive() -> void:
	Game.act = 1
	Game.run_time = 0.0
	Game.set_phase("drive")
	hud.visible = true                  # a REDEPLOY skips the lobby that shows it
	hud.set_objectives([["drive", "DRIVE TO TOPS SUPERMARKET"], ["park", "PARK AT THE ENTRANCE"],
		["enter", "GET INSIDE THE STORE"], ["clear", "CLEAR EVERY THREAT"],
		["rescue", "FIND THE 4 SURVIVORS"], ["extract", "EXTRACT OUT FRONT"]])
	Game.set_objective("drive", "active")
	hud.show_combat_hud(false)
	Game.say_banner("FIND TOPS", "FOLLOW THE ROAD. PARK WHEN YOU ARRIVE.")
	_lot_crowd_init()
	_drive_t = 0.0
	car.take_wheel(true)
	post.set_shader_parameter("mix_amt", 1.0)    # the web drives through the full GoPro look
	Game.play("car_seatbelt", -8.0)
	get_tree().create_timer(0.7, false).timeout.connect(func(): Game.play("car_start", -5.0))
	get_tree().create_timer(1.6, false).timeout.connect(func(): if Game.phase == "drive": Game.play_file("vo-deploy.mp3", -2.0))
	get_tree().create_timer(5.0, false).timeout.connect(func(): if Game.phase == "drive": Game.vo("driving", 60.0))

func _on_parked() -> void:
	Game.set_phase("parking")
	for h in hostiles:
		h.scatter_from(car.global_position)
	_scream_burst(5, 0.7)
	Game.set_objective("drive", "done")
	Game.set_objective("park", "done")
	Game.set_objective("enter", "active")
	car.take_wheel(false)
	Game.play("car_handbrake", -4.0)
	Game.play("vo_parked", -2.0)
	hud.show_combat_hud(false)
	arrival.begin(car, player, post)

func _mq(p: Array) -> Vector3:
	return Vector3(MosqueScript.mqx(p[0]), 0.1, MosqueScript.mqz(p[1]))

func _outside_pts() -> Array:
	var out := []
	for p in (OUTSIDE_PTS2 if Game.act == 2 else OUTSIDE_PTS):
		out.append(_mq(p) if Game.act == 2 else Vector3(p[0], 0.1, p[1]))
	return out

func _inside_pts() -> Array:
	var out := []
	for p in (INSIDE_PTS2 if Game.act == 2 else INSIDE_PTS):
		out.append(_mq(p) if Game.act == 2 else Vector3(p[0], 0.1, p[1]))
	return out

## the lot's clamp box and the crowd's spawn box for this act (LC_LOT / LC_SPAWN)
func _lot_boxes() -> Array:
	if Game.act == 2:
		var a := AABB(Vector3(MosqueScript.mqx(-25), 0, MosqueScript.mqz(14.5)), Vector3(50 * MosqueScript.S, 4, 16.5 * MosqueScript.S))
		var b := AABB(Vector3(MosqueScript.mqx(-22), 0, MosqueScript.mqz(16)), Vector3(44 * MosqueScript.S, 4, 14 * MosqueScript.S))
		return [a, b]
	return [AABB(Vector3(-23, 0, 16), Vector3(46, 4, 13.5)), AABB(Vector3(-20, 0, 17), Vector3(40, 4, 12))]

## lotCrowdInit: onlookers standing about the lot before you get there,
## clear of the parking bay
func _lot_crowd_init() -> void:
	var boxes := _lot_boxes()
	var spawn_box: AABB = boxes[1]
	var n := mini(14, 9 + (Game.round - 1) * 2)
	var pb: AABB = car.park_box.grow(0.9)
	var placed := 0
	for h in hostiles:
		if placed >= n:
			break
		if h.state != "idle":
			continue
		var pos := Vector3.ZERO
		var ok := false
		for k in 50:
			pos = Vector3(randf_range(spawn_box.position.x, spawn_box.end.x), 0.1, randf_range(spawn_box.position.z, spawn_box.end.z))
			if not pb.has_point(Vector3(pos.x, 1, pos.z)):
				ok = true
				break
		if not ok:
			break
		h.lot_idle(pos, player, car, boxes[0], Game.round)
		placed += 1

func _scream_burst(count: int, spread: float) -> void:
	var idlers := hostiles.filter(func(h): return h.state == "lotidle" or h.is_active())
	for i in mini(count, idlers.size()):
		var p: Vector3 = (idlers[randi() % idlers.size()] as Node3D).global_position
		get_tree().create_timer(randf_range(0.0, spread), false).timeout.connect(func():
			Game.play_file_at("sfx-enemy-scream.mp3", p, -4.0, randf_range(0.95, 1.12), 30.0))

func _begin_outside() -> void:
	# the arrival has already put you on your feet behind the boot
	player.activate(true)
	player.input_locked = false
	hud.show_combat_hud(true)
	Game.set_phase("outside")
	Game.play("gear_gopro_beep", -6.0)
	# the crowd wakes, all at once, with a burst of screams
	var woke := false
	for h in hostiles:
		if h.state == "lotidle":
			h.wake()
			woke = true
	if woke:
		_scream_burst(6, 0.8)
	var box: AABB = _lot_boxes()[0]
	for p in _outside_pts():
		var h = _spawn(p)
		if h:
			h.flee = randf() < 0.35
			h.lot_box = box
	Game.say_banner("THEY KNOW YOU ARE HERE", "GET THROUGH THE GATE" if Game.act == 2 else "GET TO THE DOORS")
	Game.play("vo_contact", -2.0)

func _enter_store() -> void:
	Game.set_phase("inside")
	# anyone still out in the lot is recycled - they cannot follow you through
	# the wall, and the clear waits on every chaser
	var gz := MosqueScript.mqz(13.2) if Game.act == 2 else 15.5
	for h in hostiles:
		if h.state not in ["idle", "dead"] and (h as Node3D).global_position.z > gz:
			h.despawn()
	Game.vo("moving", 20.0)
	Game.set_objective("enter", "done")
	Game.set_objective("clear", "active")
	Game.set_objective("rescue", "active")
	Game.say_banner("CLEAR THE PRAYER HALL" if Game.act == 2 else "CLEAR THE STORE", "4 SURVIVORS HIDING INSIDE")
	# the web streams them in rather than dropping two blocks of ten: sixteen
	# (twenty in act 2), never more than ten on their feet at once
	inside_left = mini(26, 16 + (Game.round - 1) * 3)     # roundScale().inside, both acts
	_trickle_t = 0.4                    # mission.spawnT: the first one in .4 s, then a steady trickle
	get_tree().create_timer(2.2, false).timeout.connect(func(): if Game.phase == "inside": Game.vo("contact", 10.0))

## one more from somewhere you are not standing
func _trickle_one() -> void:
	if inside_left <= 0:
		return
	var pts := _inside_pts()
	pts.shuffle()
	var pick: Vector3 = pts[0]
	for p in pts:
		if (p as Vector3).distance_to(player.global_position) > 7.0:
			pick = p
			break
	_spawn(pick)
	inside_left -= 1

## the web's fixed wave numbers: 3 for the fight outside, 4 inside (where
## the runners appear), one tougher in act 2
func _spawn(pos: Vector3):
	var w := (4 if Game.phase == "inside" else 3) + Game.act - 1
	for h in hostiles:
		if h.state == "idle":
			h.spawn(pos, w, player)
			# roundScale(): every round cleared makes them tougher and quicker
			var r := Game.round - 1
			h.max_hp *= 1.0 + r * 0.22
			h.hp = h.max_hp
			h.speed *= 1.0 + r * 0.09
			return h
	return null

func _on_survivor_found(_s: Node) -> void:
	rescued += 1
	Game.add_points(150, "SURVIVOR +150")
	Game.say_banner("SURVIVOR FOUND", "THEY ARE FOLLOWING YOU")
	if rescued >= survivors.size():
		Game.set_objective("rescue", "done")
		Game.vo("all_survivors", 0.0)
		_maybe_extract_objective()
	else:
		Game.vo("survivor", 4.0)

func _maybe_extract_objective() -> void:
	if cleared and rescued >= survivors.size():
		Game.set_objective("extract", "active")
		Game.say_banner("ALL CLEAR", "WALK THE SURVIVORS OUT THE FRONT DOORS")
		Game.vo("out_front", 5.0)

## out through the doors with everyone who is following you
func _check_extract() -> void:
	if not (cleared and rescued >= survivors.size()):
		return
	var p := player.global_position
	if Game.act == 2:
		# out through the courtyard gate onto the street
		if p.z < MosqueScript.mqz(32.6) or absf(p.x - MosqueScript.X) > 5.0:
			return
	elif p.z < 16.2 or absf(p.x) > 6.0:
		return
	for s in survivors:
		if s.state == "following" and (s as Node3D).global_position.distance_to(p) > 10.0:
			Game.vo("regroup", 10.0)          # someone is lagging - wait for them
			return
	for s in survivors:
		s.state = "out"
	Game.set_objective("extract", "done")
	_win()

func _on_kill(_h: Node) -> void:
	Game.kills += 1

func _threats() -> int:
	var n := 0
	for h in hostiles:
		if h.is_active():
			n += 1
	return n

## Act 2: back in the car at the TOPS lot, pointed west, 900 m to Al-Salaam.
func _start_act2() -> void:
	Game.act = 2
	Game.wave += 1
	cleared = false
	rescued = 0
	inside_left = 0
	for h in hostiles:
		h.despawn()
	for i in survivors.size():
		survivors[i].place(_mq(SURV_SPOTS2[i]) + Vector3(0, -0.05, 0), player)
	throwables.act2()
	player.activate(false)
	player.heal_full()
	player.mag = player.MAG_SIZE
	player.reloading = false
	player.refresh_ammo()
	car.global_position = Vector3(7.5, 0, 36.5)
	car.rotation.y = PI / 2
	car.speed = 0.0
	car.park_box = car.PARK_ACT2
	car.is_parked = false
	_lot_crowd_init()                   # the forecourt crowd, clear of the new bay
	car.take_wheel(true)
	post.set_shader_parameter("mix_amt", 1.0)
	hud.show_combat_hud(false)
	hud.set_objectives([["drive", "DRIVE WEST TO THE AL-SALAAM MOSQUE"], ["park", "PARK AT THE GATE"],
		["enter", "GET INSIDE THE MOSQUE"], ["clear", "CLEAR EVERY THREAT"],
		["rescue", "FIND THE 4 SURVIVORS"], ["extract", "WALK THEM OUT THROUGH THE GATE"]])
	Game.set_objective("drive", "active")
	_drive_t = 0.0
	Game.set_phase("drive")
	Game.say_banner("NEW OBJECTIVE", "AL-SALAAM MOSQUE — DRIVE WEST")
	Game.play("car_seatbelt", -8.0)
	get_tree().create_timer(0.7, false).timeout.connect(func(): Game.play("car_start", -5.0))
	get_tree().create_timer(3.0, false).timeout.connect(func(): Game.vo("driving", 0.0))

func _on_died() -> void:
	# the web's die(): where you fell, the stream and the camera go dark
	var where := "THE ROAD" if Game.phase in ["drive", "parking"] else ("THE LOT" if Game.phase == "outside" else ("THE STORE" if Game.phase == "inside" else "TOPS"))
	Game.set_phase("dead")
	throwables.drop_held()
	hud.stream_stop()
	hud.gopro_set(false)
	car.radio.stop()
	get_tree().create_timer(0.9, false).timeout.connect(func(): menu.show_dead(where))

func _win() -> void:
	if Game.act == 1:
		Game.add_points(400, "TOPS CLEAR +400")
		_start_act2()                   # the web goes straight back to the car
		return
	Game.set_phase("win")
	player.activate(false)              # no walking about under the card; breathing stops
	hud.stream_stop()
	hud.gopro_set(false)
	car.radio.stop()
	Game.add_points(500, "EXTRACTED +500")
	Game.saved = rescued
	Game.vo("clear", 0.0)
	get_tree().create_timer(1.6, false).timeout.connect(func(): Game.play_file("vo-win.mp3", -2.0))
	get_tree().create_timer(2.4, false).timeout.connect(menu.show_win)

# ------------------------------------------------------------------ loop

func _process(dt: float) -> void:
	if Game.phase == "menu" and menu_cam:
		# lobbyTick: rings breathe, the camera drifts
		_lobby_t += dt
		for i in lobby_rings.size():
			var rm := lobby_rings[i].material_override as StandardMaterial3D
			rm.albedo_color.a = (0.36 + sin(_lobby_t * 2.0 + i) * 0.12) if i == 0 else 0.12
		var k := sin(_lobby_t * 0.22)
		menu_cam.global_position = Vector3(LOBBY_CAM.x + k * 0.34, LOBBY_CAM.y + sin(_lobby_t * 0.31) * 0.05, LOBBY_CAM.z + k * 0.1)
		menu_cam.look_at(LOBBY_LOOK, Vector3.UP)
	if Game.phase not in ["dead", "win", "menu"]:
		Game.run_time += dt
	_light_apply(dt)
	_crowd_groan_t -= dt
	if _crowd_groan_t <= 0.0:
		_crowd_groan_t = randf_range(3.0, 7.0)
		var idlers := hostiles.filter(func(h): return h.state == "lotidle")
		if not idlers.is_empty():
			var g: Node3D = idlers[randi() % idlers.size()]
			Game.play_file_at("hostile-%d.mp3" % randi_range(1, 7), g.global_position, -12.0, randf_range(0.7, 0.85), 22.0)
	emergency.light_energy = 1.2 + sin(Time.get_ticks_msec() * 0.0024) * 0.5
	emergency.position.x = sin(Time.get_ticks_msec() * 0.0007) * 8.0
	match Game.phase:
		"outside":
			var p := player.global_position
			if Game.act == 2:
				# in through the facade arch into the vestibule
				if p.z < MosqueScript.mqz(12.4) and absf(p.x - MosqueScript.X) < 11.0:
					_enter_store()
			elif p.z < 14.6 and absf(p.x) < 2.2:
				_enter_store()
		"inside":
			if inside_left > 0:
				_trickle_t -= dt
				if _trickle_t <= 0.0 and _threats() < mini(17, 10 + (Game.round - 1) * 2):
					_trickle_t = randf_range(0.45, 1.1)
					_trickle_one()
			elif _threats() == 0 and not cleared:
				cleared = true
				Game.vo("clear", 0.0)
				Game.set_objective("clear", "done")
				_maybe_extract_objective()
			_check_extract()
	var n := _threats()
	hud.set_threats(n if Game.phase in ["outside", "inside"] else 0)
	# the web's survivorsHUD: a badge over each survivor still hiding, inside
	# only, while they are in front of you; distance along the ground
	var marks := []
	if Game.phase == "inside" and player.alive:
		var cam: Camera3D = player.camera
		var fwd := -cam.global_basis.z
		for s in survivors:
			if s.state != "hiding":
				continue
			var sp: Vector3 = (s as Node3D).global_position
			var wp := sp + Vector3(0, 2.1, 0)
			if (wp - cam.global_position).dot(fwd) <= 0.2:
				continue
			var scr := cam.unproject_position(wp)
			var vs := get_viewport().get_visible_rect().size
			if scr.x < -0.025 * vs.x or scr.x > 1.025 * vs.x or scr.y < -0.025 * vs.y or scr.y > 1.025 * vs.y:
				continue
			marks.append([scr, Vector2(sp.x - player.global_position.x, sp.z - player.global_position.z).length()])
	hud.set_markers(marks)
	# the drive's prompts (missionUpdate): three seconds in, then twelve
	if Game.phase == "drive":
		var before := _drive_t
		_drive_t += dt
		if before < 3.0 and _drive_t >= 3.0:
			Game.say_banner("KEEP DRIVING", "STRAIGHT DOWN THE MAIN ROAD")
		if before < 12.0 and _drive_t >= 12.0:
			Game.say_banner("SHOULD BE JUST AHEAD", "LOOK FOR THE PARKING LOT")
	if Game.phase in ["outside", "inside"] and player.alive:
		_watch_your_back()

## something within arm's reach that you are not looking at
func _watch_your_back() -> void:
	var fwd: Vector3 = -player.camera.global_basis.z
	fwd.y = 0.0
	for h in hostiles:
		if not h.is_active():
			continue
		var to: Vector3 = h.global_position - player.global_position
		to.y = 0.0
		if to.length() < 4.0 and fwd.normalized().dot(to.normalized()) < -0.3:
			Game.vo("behind_you", 14.0)
			return

func _unhandled_input(e: InputEvent) -> void:
	# F1 skips the drive: straight to the car park on foot
	if e is InputEventKey and (e as InputEventKey).pressed and (e as InputEventKey).keycode == KEY_F1 and Game.phase == "drive":
		car.global_position = car.park_box.get_center() * Vector3(1, 0, 1)
		car.rotation.y = PI / 2
		car.speed = 0.0
		return
	# N MUSIC: mute or unmute the radio wherever you are
	if e.is_action_pressed("music"):
		var mb := AudioServer.get_bus_index("Music")
		AudioServer.set_bus_mute(mb, not AudioServer.is_bus_mute(mb))
		return
	if Game.phase == "parking" and e.is_action_pressed("skip"):
		arrival.skip()
		return
	# clicking back into the window takes the mouse again (Esc is the menu's)
	if e is InputEventMouseButton and (e as InputEventMouseButton).pressed and menu.current == "" \
			and Game.phase not in ["menu", "dead", "win"] and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
