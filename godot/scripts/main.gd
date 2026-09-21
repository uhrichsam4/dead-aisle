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
const POOL := 18

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
var inside_waves := 0
var paused := false

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
	car.radio_changed.connect(func(t): hud.set_radio(t))

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
	player.hp_changed.connect(hud.set_hp)
	player.ammo_changed.connect(hud.set_ammo)
	player.hit_marker.connect(hud.on_hit)
	player.damaged.connect(hud.on_damage)
	player.died.connect(_on_died)
	player.select_weapon(0, true)

	# bake the navmesh once the world has settled
	get_tree().create_timer(0.5).timeout.connect(world.bake_nav)
	get_tree().create_timer(1.2).timeout.connect(mosque.bake_nav)
	_start_drive()

# ------------------------------------------------------------------ setup

func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var psm := PanoramaSkyMaterial.new()
	psm.panorama = U.tex("res://assets/tex/sky.jpg")
	psm.energy_multiplier = 0.6
	sky.sky_material = psm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.1
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 1.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.2, 0.24, 0.3)
	env.fog_density = 0.006
	env.fog_aerial_perspective = 0.4
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.4
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var moon := DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = Color(0.72, 0.78, 0.9)
	moon.light_energy = 0.9
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 90.0
	add_child(moon)
	moon.look_at_from_position(Vector3(-14, 18, -8) + Vector3(30, 0, 30), Vector3(30, 0, 30), Vector3.UP)

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
	hud.set_objectives([["drive", "DRIVE TO TOPS SUPERMARKET"], ["park", "PARK IN THE LOT"],
		["enter", "GET INSIDE"], ["clear", "CLEAR EVERY THREAT"],
		["rescue", "FIND THE 4 SURVIVORS"], ["extract", "WALK THEM OUT THROUGH THE DOORS"]])
	Game.set_objective("drive", "active")
	hud.show_combat_hud(false)
	hud.set_hint("W/S DRIVE · A/D STEER · SPACE HANDBRAKE · E RADIO · 1-5 STATION · F1 SKIP")
	Game.say_banner("DEAD AISLE", "TOPS SUPERMARKET IS JUST DOWN THE ROAD")
	car.take_wheel(true)
	post.set_shader_parameter("mix_amt", 0.25)   # a dashcam, not yet the GoPro
	Game.play("car_seatbelt", -8.0)
	get_tree().create_timer(0.7).timeout.connect(func(): Game.play("car_start", -5.0))
	get_tree().create_timer(1.6).timeout.connect(func(): Game.play_file("vo-deploy.mp3", -2.0))
	get_tree().create_timer(5.0).timeout.connect(func(): Game.vo("driving", 60.0))

func _on_parked() -> void:
	Game.set_phase("parking")
	Game.set_objective("drive", "done")
	Game.set_objective("park", "done")
	Game.set_objective("enter", "active")
	car.take_wheel(false)
	Game.play("car_handbrake", -4.0)
	Game.play("vo_parked", -2.0)
	hud.set_hint("ENTER TO SKIP")
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

func _begin_outside() -> void:
	# the arrival has already put you on your feet behind the boot
	player.activate(true)
	player.input_locked = false
	hud.show_combat_hud(true)
	hud.set_hint("WASD MOVE · SHIFT SPRINT · LMB FIRE · RMB AIM · R RELOAD · 1/2/3 WEAPON")
	Game.set_phase("outside")
	Game.play("gear_gopro_beep", -6.0)
	for p in _outside_pts():
		_spawn(p)
	Game.say_banner("THEY KNOW YOU ARE HERE", "GET THROUGH THE GATE" if Game.act == 2 else "GET TO THE DOORS")
	Game.play("vo_contact", -2.0)

func _enter_store() -> void:
	Game.set_phase("inside")
	Game.vo("moving", 20.0)
	Game.set_objective("enter", "done")
	Game.set_objective("clear", "active")
	Game.set_objective("rescue", "active")
	Game.say_banner("INSIDE", "CLEAR THE PRAYER HALL" if Game.act == 2 else "CLEAR THE STORE")
	inside_waves = 2
	_inside_wave()

func _inside_wave() -> void:
	if inside_waves < 2:
		Game.vo("clear", 6.0)            # a breath between waves
		get_tree().create_timer(2.2).timeout.connect(func(): Game.vo("contact", 10.0))
	inside_waves -= 1
	var pts := _inside_pts()
	pts.shuffle()
	for i in mini(8 + Game.wave * 2, pts.size()):
		_spawn(pts[i])

func _spawn(pos: Vector3) -> void:
	for h in hostiles:
		if h.state == "idle":
			h.spawn(pos, Game.wave, player)
			return

func _on_survivor_found(_s: Node) -> void:
	rescued += 1
	Game.points += 150
	Game.say_banner("SURVIVOR FOUND", "%d OF %d - THEY ARE FOLLOWING YOU" % [rescued, survivors.size()])
	if rescued >= survivors.size():
		Game.set_objective("rescue", "done")
		Game.vo("all_survivors", 0.0)
		_maybe_extract_objective()
	else:
		Game.vo("survivor", 4.0)

func _maybe_extract_objective() -> void:
	if cleared and rescued >= survivors.size():
		Game.set_objective("extract", "active")
		Game.say_banner("EVERYONE IS WITH YOU", "WALK THEM OUT THROUGH THE GATE" if Game.act == 2 else "WALK THEM OUT THROUGH THE DOORS")
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
	Game.points += 100

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
	inside_waves = 0
	for h in hostiles:
		h.despawn()
	for i in survivors.size():
		survivors[i].place(_mq(SURV_SPOTS2[i]) + Vector3(0, -0.05, 0), player)
	player.activate(false)
	player.heal_full()
	player.mag = player.MAG_SIZE
	car.global_position = Vector3(7.5, 0, 36.5)
	car.rotation.y = PI / 2
	car.speed = 0.0
	car.park_box = car.PARK_ACT2
	car.is_parked = false
	car.take_wheel(true)
	post.set_shader_parameter("mix_amt", 0.25)
	hud.show_combat_hud(false)
	hud.set_objectives([["drive", "DRIVE WEST TO THE AL-SALAAM MOSQUE"], ["park", "PARK AT THE GATE"],
		["enter", "GET INSIDE THE MOSQUE"], ["clear", "CLEAR EVERY THREAT"],
		["rescue", "FIND THE 4 SURVIVORS"], ["extract", "WALK THEM OUT THROUGH THE GATE"]])
	Game.set_objective("drive", "active")
	hud.set_hint("W/S DRIVE · A/D STEER · E RADIO · 1-5 STATION")
	Game.set_phase("drive")
	Game.say_banner("NEW OBJECTIVE", "AL-SALAAM MOSQUE — DRIVE WEST")
	Game.play("car_seatbelt", -8.0)
	get_tree().create_timer(0.7).timeout.connect(func(): Game.play("car_start", -5.0))
	get_tree().create_timer(3.0).timeout.connect(func(): Game.vo("driving", 0.0))

func _on_died() -> void:
	Game.set_phase("dead")
	Game.say_banner("K.I.A.", "CLICK TO REDEPLOY")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _win() -> void:
	if Game.act == 1:
		Game.points += 400
		Game.say_banner("TOPS CLEAR", "+400 · THE MOSQUE IS NEXT")
		Game.vo("clear", 0.0)
		Game.set_phase("between")
		get_tree().create_timer(4.0).timeout.connect(_start_act2)
		return
	Game.set_phase("win")
	Game.points += 500
	Game.say_banner("MISSION COMPLETE", "%d KILLS · %d POINTS · CLICK TO PLAY AGAIN" % [Game.kills, Game.points])
	Game.vo("clear", 0.0)
	get_tree().create_timer(1.6).timeout.connect(func(): Game.play_file("vo-win.mp3", -2.0))
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

# ------------------------------------------------------------------ loop

func _process(dt: float) -> void:
	if Game.phase not in ["dead", "win"]:
		Game.run_time += dt
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
			if _threats() == 0 and not cleared:
				if inside_waves > 0:
					_inside_wave()
				else:
					cleared = true
					Game.set_objective("clear", "done")
					if rescued < survivors.size():
						Game.say_banner("MOSQUE CLEAR" if Game.act == 2 else "STORE CLEAR", "FIND THE SURVIVORS - %d LEFT" % (survivors.size() - rescued))
					_maybe_extract_objective()
			_check_extract()
	var n := _threats()
	hud.set_center("THREATS: %d" % n if Game.phase == "inside" and n > 0 else "")
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
	if Game.phase == "parking" and e.is_action_pressed("skip"):
		arrival.skip()
		return
	if e.is_action_pressed("pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		paused = true
	elif e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
		if Game.phase in ["dead", "win"]:
			Game.points = 0
			Game.kills = 0
			get_tree().reload_current_scene()
		elif Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			paused = false
