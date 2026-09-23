## First-person operator: movement, look, the rifle and the viewmodel.
## Numbers are the web build's: 4.6 m/s walk, 7.2 sprint, the same bob, the
## same three AK-74 builds and their damage / fire interval / spread.
extends CharacterBody3D

const U := preload("res://scripts/util.gd")
const MosqueScript := preload("res://scripts/mosque.gd")
const Fx := preload("res://scripts/fx.gd")

signal died
signal hp_changed(hp: float, max_hp: float)
signal ammo_changed(mag: int, mag_size: int, weapon_name: String)
signal hit_marker(headshot: bool, kill: bool)
signal damaged(from: Vector3)

const WALK := 4.6
const SPRINT := 7.2
const ACCEL := 12.0
const GRAVITY := 18.0
const JUMP := 5.2
const EYE := 1.7
const MOUSE_SENS := 0.0022

const WEAPONS := [
	{"id": "ak_tactical", "name": "AK-74 TACTICAL", "damage": 34.0, "interval": 0.095, "spread": 0.011},
	{"id": "ak_wood",     "name": "AK-74 WOOD",     "damage": 38.0, "interval": 0.112, "spread": 0.0095},
	{"id": "ak_scoped",   "name": "AK-74 1P29",     "damage": 42.0, "interval": 0.135, "spread": 0.008},
]
const MAG_SIZE := 30
const RELOAD_TIME := 1.9
const HEAD_MULT := 2.6

## rifle-in-hand calibration: the pistol grip is solved into the right palm
## (VM_GRIP below); this is a camera-space nudge off that and a tilt (radians)
const GRIP := {"x": 0.0, "y": 0.0, "z": 0.0, "tilt_x": 0.0, "tilt_y": 0.0, "tilt_z": 0.0, "scale": 1.0}
const AK_FIT := {"scale": 0.8, "pos": Vector3(0.04, -0.03, 0.0)}

## ---- viewmodel tuning. Camera space is +x right, +y up, -z ahead (metres);
## rotations are (pitch up, yaw left, roll left) in radians. Gun-local points
## are in the guns.glb mesh's own units (muzzle toward -z, top +y).
const VM_FOV_HIP := 72.0                       # the arms' lens at the hip
const VM_FOV_ADS := 44.0                       # and on the sights
const VM_ARMS := "res://assets/skin_military.glb"   # the arms: the Rocketbox soldier
const VM_ARMS_AT := Vector3(0.0, -1.55, 0.05)     # its origin under the lens (it faces the lens' way)
const VM_ARMS_HIDE := Vector3(0.0, 1.5, -0.3)     # skeleton space: behind the lens, where the rest of him goes
const VM_PALM_OFF := 0.028                        # palm to the centre of what it holds
# hand frames (gun-local): the wrist-to-knuckle direction and the thumb side
const VM_HAND_R_ALONG := Vector3(-0.05, -0.3, -1.0)  # round a raked pistol grip
const VM_HAND_R_THUMB := Vector3(0.0, 1.0, -0.35)
const VM_HAND_L_ALONG := Vector3(0.75, 0.3, -0.6)    # cupped under the handguard
const VM_HAND_L_THUMB := Vector3(-0.2, 0.25, -1.0)
const VM_HAND_MAG_ALONG := Vector3(0.0, -1.0, -0.2) # on the magazine's flank
const VM_HAND_MAG_THUMB := Vector3(0.0, 0.2, -1.0)
# finger curl, radians per joint: thumb (base, mid, tip), fingers (base, mid, tip)
const VM_CURL_R := [0.35, 0.3, 0.2, 1.05, 1.25, 0.8]
const VM_CURL_L := [0.3, 0.25, 0.15, 0.8, 1.0, 0.6]
const VM_SUIT_CLOTH := Color(0.075, 0.08, 0.095)   # the SUIT outfit's sleeves
const VM_HIP_AT := Vector3(0.16, -0.088, -0.44)  # the rear sight at the ready
const VM_HIP_ROT := Vector3(0.0, 0.06, -0.035)   # ready carry: muzzle in toward the centre, a little cant
const VM_ADS_AT := Vector3(0.0, 0.0, -0.215)      # the rear sight on the lens axis
const VM_PIVOT := Vector3(0.0, -0.06, 0.13)       # grip / shoulder pivot, off the rear sight
const VM_SHOULDER_L_HIP := Vector3(-0.24, -0.4, 0.02)  # the left arm comes up from here (IK root)
const VM_SHOULDER_L_ADS := Vector3(-0.2, -0.26, 0.02)
const VM_SHOULDER_R_HIP := Vector3(0.15, -0.3, 0.1)
const VM_SHOULDER_R_ADS := Vector3(0.1, -0.22, 0.12)
const VM_POLE_L := Vector3(-0.45, -1.0, 0.25)     # elbows bend down and out
const VM_POLE_R := Vector3(0.6, -1.0, 0.3)
const VM_SKY_ENERGY := 0.55                       # the rifle's reflected sky, at full daylight
const VM_GRIP := Vector3(0.0, -0.085, 0.2)        # the pistol grip (gun-local): right palm
const VM_HANDGUARD := Vector3(-0.012, -0.04, -0.13)  # where the left palm rides (gun-local)
const VM_MAG_GRAB := Vector3(-0.03, -0.1, 0.03)   # the left palm on the magazine (gun-local)
const VM_MAG_DROP := Vector3(0.0, -0.13, 0.035)   # the magazine clear of the well (gun-local offset)
const VM_POUCH := Vector3(-0.2, -0.55, 0.12)      # the hand down at the vest, out of frame (gun-local)
const VM_CHARGE := Vector3(0.055, 0.035, 0.0)     # the charging handle, right side (gun-local)
const VM_CHARGE_PULL := 0.1                       # how far the handle is racked back (gun-local)
const VM_ADS_ARC := Vector3(0.012, -0.02, 0.0)    # the rifle rises through this on the way to the eye
const VM_SPRINT_ROT := Vector3(-0.3, 0.5, 0.45)   # sprint carry: muzzle low and across, canted
const VM_SPRINT_POS := Vector3(-0.03, -0.02, 0.04)
const VM_DRAW_TIME := 0.55                        # equip / draw
const VM_DRAW_ROT := Vector3(-1.05, 0.25, 0.7)
const VM_DRAW_POS := Vector3(0.05, -0.26, 0.08)
const VM_WALL_REACH := 0.85                       # a wall nearer than this pushes the rifle in
const VM_WALL_MIN := 0.3                          # fully tucked at this distance
const VM_WALL_ROT := Vector3(-0.6, 0.35, 0.3)     # tucked: muzzle down and in
const VM_WALL_POS := Vector3(-0.02, -0.05, 0.14)
const VM_LOOK_LAG := 0.011                        # rad of trail per rad/s of turn
const VM_LOOK_ROLL := 0.009
const VM_STRAFE_ROLL := 0.07                      # roll at a full sprint sideways
const VM_BOB := Vector3(0.007, 0.009, 0.022)      # own bob: side, lift, roll (walk)
const VM_BOB_LAG := 0.45                          # rad of step phase the rifle trails the head by
const VM_BREATH := 0.004                          # idle breathing / drift, rad
# recoil: an impulse per round into two springs (translation, rotation) and
# a heat that builds under full auto, so a burst climbs and then settles
const VM_KICK_V := Vector3(0.12, 0.12, 1.15)      # m/s: side (random), up, straight back
const VM_KICK_RV := Vector3(1.7, 0.65, 0.9)       # rad/s: climb, yaw (random), roll (random)
const VM_HEAT_CLIMB := 0.009                      # held climb per round of heat
const VM_HEAT_MAX := 0.065
const VM_HEAT_DECAY := 3.2                        # 1/s

var hp := 100.0
var max_hp := 100.0
var alive := true
var active := false          # false while driving / in cutscenes
var input_locked := false    # on camera, but the arrival is steering the view
var holding := false         # a cart / melon / axe in hand: no rifle (throwables.gd)
var yaw := PI
var pitch := 0.0
var fov_base := 80.0

var camera: Camera3D
var vm_cam: Camera3D
var vm_layer: CanvasLayer
var vm_root: Node3D
var op: Node3D
var anim: AnimationPlayer
var hand_r: Node3D
var gun_root: Node3D
var guns := {}
var flash_light: OmniLight3D
var flash_mesh: MeshInstance3D

var weapon_index := 0
var mag := MAG_SIZE
var reloading := false
var reload_t := 0.0
var _reload_stage := 0
var fire_cd := 0.0
var ads_t := 0.0
var recoil := 0.0
var kick := 0.0
var bob_t := 0.0
var stride := 0.0
var regen_cd := 0.0
var shake := 0.0
var _anim_now := ""
# audio state
var breath: AudioStreamPlayer
var exertion := 0.0          # 0 calm .. 1 spent; sprinting builds it, rest drains it
var _was_aiming := false
var _was_floor := true
var _rustle_t := 4.0
var _low_hp_said := false
var _dead_t := 0.0
var _sprinting := false
var _vm_view: SubViewport
var _fov_now := 88.0
var heart: AudioStreamPlayer
var _heart_t := 0.0
var _holes: Array[Decal] = []
static var _hole_tex: Texture2D
# weapon feel: the rig hangs off a pivot at the eye so sway, the sprint carry
# and the landing dip swing it about the view, not about the operator's feet
var vm_pivot: Node3D
var _rec := Vector2.ZERO          # recoil on the view now (pitch, yaw)
var _rec_to := Vector2.ZERO       # where the kicks are pushing it
var _punch := 0.0
var _punch_side := 1.0
var _sway := Vector2.ZERO
var _sway_to := Vector2.ZERO
var _sprint_k := 0.0
var _land_t := 1.0
var _land_amp := 0.0
var _flash_frames := 0
# brass: a ring of casings, reused oldest-first
const CASINGS := 16
var _casings: Array[RigidBody3D] = []
var _casing_i := 0
static var _casing_mesh: CylinderMesh
static var _casing_shape: CapsuleShape3D
# the lens is a GoPro strapped to the helmet, not the eyes: up on the shell,
# over the right temple, a touch proud of the brow. It rides the head's pitch.
const MOUNT := Vector3(0.045, 0.085, -0.035)
const SHUTTER := 1.0 / 90.0       # how long the sensor smears a whip-pan
var _step_ph := 0.0               # footfalls: every whole number lands a foot
var _bob_amp := 0.0
var _bob_sprint := 0.0
var _lean := 0.0
var _prev_look := Vector2.ZERO
var _turn_w := Vector2.ZERO       # the look's angular rate (yaw, pitch), rad/s
var _turn_off := Vector3.ZERO     # the head lagging a whip and settling (spring)
var _turn_vel := Vector3.ZERO
var _hj := Vector3.ZERO           # head jolts: shots, hits, landings (spring)
var _hjv := Vector3.ZERO
var _hp := Vector3.ZERO           # the same, as a shove of the head
var _hpv := Vector3.ZERO
var _breath_t := 0.0
var _shake_t := 0.0
var _vm_lag := 0.0                # the rifle rides the body, a beat behind the head
var _post_mat: ShaderMaterial
var _blur_sent := Vector2.ZERO
# viewmodel rig (see _vm_update)
var _vm_env: Environment
var _vm_sky_mat: ProceduralSkyMaterial
var _world_sky_mat: Material
var _vm_sky_k := 1.0
var _vm_ready := false
var _vm_sight: Array[Vector3] = []     # each rifle's rear sight, gun-local
var _vm_sight_rig: Array[Vector3] = [] # the same in vm_root space, at calibration
var _vm_q_hip := Quaternion.IDENTITY   # vm_root rotation at the ready / on the sights
var _vm_q_ads := Quaternion.IDENTITY
var _mags: Array[MeshInstance3D] = []  # each rifle's magazine, split off its mesh
var _mag_state := 0                    # 0 seated, 1 dropping out of the well, 2 in the left hand
var _skel: Skeleton3D                  # the soldier's arms (_build_arms)
var _arms_ok := false
var _hl: Node3D                        # the left hand, for the magazine
var _arm_bone := PackedInt32Array([-1, -1, -1, -1, -1, -1])   # L upper, fore, hand, R upper, fore, hand
var _arm_rest: Array[Transform3D] = [Transform3D(), Transform3D(), Transform3D(), Transform3D(), Transform3D(), Transform3D()]
var _frame_rest: Array[Basis] = [Basis(), Basis()]
var _rel_fh: Array[Basis] = [Basis(), Basis()]
var _palm: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _sleeve_mat: BaseMaterial3D
var _sleeve_tex: Texture2D
var _sleeve_rough := 1.0
var _wall_ray: RayCast3D
var _rifle_on := true
var _draw_t := 1.0
var _rk_p := Vector3.ZERO              # recoil spring: translation / rotation
var _rk_v := Vector3.ZERO
var _rk_r := Vector3.ZERO
var _rk_rv := Vector3.ZERO
var _rk_heat := 0.0
var _lk := Vector3.ZERO                # look inertia spring
var _lk_v := Vector3.ZERO
var _jo := Vector3.ZERO                # landing / mag-in / charge jolts
var _jo_v := Vector3.ZERO
var _wall := 0.0
var _wall_v := 0.0
var _strafe := 0.0

func _on_settings() -> void:
	fov_base = float(Game.settings.fov)
	if _vm_view:
		_vm_view.scaling_3d_scale = Game.render_scale()

func _ready() -> void:
	_on_settings()
	Game.settings_changed.connect(_on_settings)
	collision_layer = 2
	collision_mask = 1
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.42
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	add_child(cs)

	camera = Camera3D.new()
	camera.position.y = EYE
	camera.fov = fov_base
	camera.near = 0.05
	camera.far = 900.0
	camera.cull_mask = 0xFFFFF & ~2   # everything but the viewmodel layer
	add_child(camera)
	# what is right in front of the lens: the rifle tucks in rather than
	# pointing through a wall or a shelf
	_wall_ray = RayCast3D.new()
	_wall_ray.target_position = Vector3(0.0, 0.0, -VM_WALL_REACH)
	_wall_ray.collision_mask = 1 | 8
	_wall_ray.add_exception(self)
	camera.add_child(_wall_ray)
	_build_viewmodel()
	breath = AudioStreamPlayer.new()
	breath.volume_db = -16.0
	add_child(breath)
	breath.finished.connect(_next_breath)
	heart = AudioStreamPlayer.new()
	heart.stream = Game.heartbeat()
	heart.volume_db = -3.0
	add_child(heart)

func activate(on: bool) -> void:
	active = on
	visible = on
	vm_layer.visible = on
	_settle_head()
	if on:
		camera.current = true
		_vm_sync_env()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if breath and not breath.playing:
			_next_breath()
	elif breath:
		breath.stop()

func place_at(p: Vector3, face_yaw: float) -> void:
	global_position = Vector3(p.x, maxf(p.y - EYE, 0.0), p.z)
	yaw = face_yaw
	pitch = 0.0
	velocity = Vector3.ZERO
	_settle_head()

## a cut (on or off foot, a teleport) is not a whip-pan: no lag, no smear
func _settle_head() -> void:
	_prev_look = Vector2(yaw, pitch)
	_turn_w = Vector2.ZERO
	_turn_off = Vector3.ZERO
	_turn_vel = Vector3.ZERO
	_send_blur(Vector2.ZERO)

func _notification(what: int) -> void:
	# a pause freezes _process: never leave the menu smeared mid-turn
	if what == NOTIFICATION_PAUSED:
		_send_blur(Vector2.ZERO)

func _send_blur(b: Vector2) -> void:
	if _post_mat == null:
		var cs := get_tree().current_scene if is_inside_tree() else null
		if cs == null or not ("post" in cs):
			return
		_post_mat = cs.get("post") as ShaderMaterial
		if _post_mat == null:
			return
	if b.is_equal_approx(_blur_sent):
		return
	_blur_sent = b
	_post_mat.set_shader_parameter(&"cam_blur", b)

# ------------------------------------------------------------------ viewmodel

func _build_viewmodel() -> void:
	# The arms and rifle are drawn by their own camera into a transparent
	# SubViewport on top of the world - the same trick as the web build's
	# second pass - so they never clip into a wall and get their own FOV.
	vm_layer = CanvasLayer.new()
	vm_layer.layer = 1
	add_child(vm_layer)
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vm_layer.add_child(svc)
	var sv := SubViewport.new()
	_vm_view = sv
	sv.scaling_3d_scale = Game.render_scale()
	sv.transparent_bg = true
	sv.msaa_3d = Viewport.MSAA_4X
	sv.handle_input_locally = false
	svc.add_child(sv)
	vm_cam = Camera3D.new()
	vm_cam.cull_mask = 2
	vm_cam.fov = VM_FOV_HIP
	vm_cam.near = 0.01
	vm_cam.far = 10.0
	var env := Environment.new()
	_vm_env = env
	env.background_mode = Environment.BG_CLEAR_COLOR
	# The rifle is metal (metallic 1 under textured metalness maps): with the
	# old clear-colour reflections it had nothing to reflect but transparent
	# black and no diffuse at all, which is the near-black silhouette. It now
	# reflects a soft grey sky of its own (the world's HDR, sun and all, blew
	# the optic out white) whose energy follows the world sky's day / store /
	# night fade (_vm_sync_env), and takes part of its ambient from it over a
	# small grey floor.
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	_vm_sky_mat = psm
	psm.sky_top_color = Color(0.42, 0.5, 0.6)
	psm.sky_horizon_color = Color(0.66, 0.68, 0.7)
	psm.ground_horizon_color = Color(0.5, 0.48, 0.45)
	psm.ground_bottom_color = Color(0.2, 0.19, 0.18)
	psm.sun_angle_max = 1.0
	psm.energy_multiplier = VM_SKY_ENERGY
	sky.sky_material = psm
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	env.sky = sky
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.7
	env.ambient_light_color = Color(0.5, 0.52, 0.55)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	vm_cam.environment = env
	# its own fixed exposure: the world's auto exposure (main.gd) would meter
	# this mostly-empty layer and blow the rifle out
	vm_cam.attributes = CameraAttributesPractical.new()
	sv.add_child(vm_cam)
	# its own key and fill, like every FPS - at night the world lights leave
	# the rifle a black silhouette. The world's sun reaches this layer too
	# (and its shadows: the rifle goes into shade under a roof), so these are
	# kept low enough not to double the daylight into a glow.
	var key := DirectionalLight3D.new()
	key.light_cull_mask = 2
	key.light_energy = 0.75
	key.light_color = Color(1, 0.94, 0.86)
	key.rotation = Vector3(-0.75, 0.55, 0)
	key.light_specular = 0.6
	key.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	vm_cam.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.light_cull_mask = 2
	fill.light_energy = 0.3
	fill.light_color = Color(0.62, 0.7, 0.82)
	fill.rotation = Vector3(-0.2, -1.2, 0)
	fill.light_specular = 0.3
	fill.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	vm_cam.add_child(fill)

	vm_pivot = Node3D.new()
	vm_cam.add_child(vm_pivot)
	vm_root = Node3D.new()
	vm_pivot.add_child(vm_root)
	# the rifle hangs off hand_r: the grip frame, which the framing places
	# (_vm_update); the arms are then solved onto the rifle (_arms)
	hand_r = Node3D.new()
	hand_r.name = "hand_r"
	vm_root.add_child(hand_r)
	_build_arms()

	gun_root = Node3D.new()
	var lib := U.glb("res://assets/guns.glb")
	for w in WEAPONS:
		var src := lib.find_child(w.id, true, false) if lib else null
		if src:
			var g := src.duplicate() as Node3D
			g.scale = Vector3.ONE * AK_FIT.scale
			g.position = AK_FIT.pos
			g.rotation = Vector3.ZERO
			g.visible = false
			gun_root.add_child(g)
			guns[w.id] = g
			_gun_decal(g)
			_vm_sight.append(_sight_of(g))
			_mags.append(_split_mag(g))
		else:
			_vm_sight.append(Vector3(0.0, 0.1, 0.0))
			_mags.append(null)
	# the flash: a ragged star burst, hot white at the core, re-rolled every
	# shot (rotation, size) and up for one or two frames only
	flash_mesh = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.3, 0.3)
	flash_mesh.mesh = q
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.albedo_texture = Fx.star_texture()
	fm.albedo_color = Color(2.6, 1.8, 1.0, 1.0)
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fm.billboard_keep_scale = true
	fm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	fm.no_depth_test = true
	flash_mesh.material_override = fm
	flash_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flash_mesh.position = Vector3(0.04, 0.02, -0.42)
	flash_mesh.visible = false
	flash_mesh.layers = 2
	gun_root.add_child(flash_mesh)

	hand_r.add_child(gun_root)
	U.set_layers(op, 2)
	U.set_layers(gun_root, 2)
	U.set_shadows(op, false)
	# the muzzle flash lights the WORLD, so it rides the main camera
	flash_light = OmniLight3D.new()
	flash_light.light_color = Color(1, 0.73, 0.4)
	flash_light.light_energy = 0.0
	flash_light.omni_range = 7.0
	flash_light.position = Vector3(0.1, -0.1, -0.6)
	camera.add_child(flash_light)
	select_weapon(0, true)
	_vm_calibrate()
	(func(): Fx.warm()).call_deferred()

## GUN_DECAL: "MOGGED" on both flanks of the receiver, each facing out,
## sized off the weapon's own bounds (the three builds differ in width)
func _gun_decal(g: Node3D) -> void:
	var b := U.local_aabb(g)
	var sc := g.scale.x
	var lo := b.position
	var hi := b.end
	var cz := (lo.z + hi.z) * 0.5
	var cy := (lo.y + hi.y) * 0.5
	var ln := absf(hi.z - lo.z)
	var tall := absf(hi.y - lo.y)
	var w := minf(ln * 0.26, 0.34 / sc) * 0.78          # GUN_DECAL.scale
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Arial Black", "Arial", "Helvetica Neue"])
	f.font_weight = 900
	var fs := 118
	var tw := f.get_string_size("MOGGED", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var squeeze := minf(1.0, 472.0 / maxf(1.0, tw))       # squeezed to fit the 512 px sticker
	for side in [-1, 1]:
		var l := Label3D.new()
		l.name = "gun_decal"
		l.text = "MOGGED"
		l.font = f
		l.font_size = fs
		l.modulate = Color("e8e2d4")
		l.outline_modulate = Color(0, 0, 0, 0.55)
		l.outline_size = int(fs * 0.16)
		l.pixel_size = w / 512.0
		l.scale = Vector3(squeeze, 1, 1)
		l.double_sided = false
		l.shaded = true
		l.alpha_cut = Label3D.ALPHA_CUT_DISABLED
		l.layers = 2
		l.position = Vector3((lo.x if side < 0 else hi.x) + side * 0.004 / sc, cy + tall * 0.06 + 0.010 / sc, cz + 0.10 / sc)
		l.rotation.y = -PI / 2 if side < 0 else PI / 2
		g.add_child(l)

## The rear sight: where the eye looks through (gun-local). A red dot's
## reticle or a scope's lenses when the rifle has them, else the iron sights'
## line (the front post's top), at the receiver.
func _sight_of(g: Node3D) -> Vector3:
	var mi := g as MeshInstance3D
	if mi == null or mi.mesh == null:
		return Vector3(0.0, 0.1, 0.0)
	var m := mi.mesh
	var dot := AABB()
	var glass := AABB()
	var has_dot := false
	var has_glass := false
	for si in m.get_surface_count():
		var mat := mi.get_active_material(si)
		var nm := mat.resource_name.to_lower() if mat else ""
		if nm.contains("reticle") or nm.contains("glass"):
			var ab := _verts_aabb(m.surface_get_arrays(si)[Mesh.ARRAY_VERTEX])
			if nm.contains("reticle"):
				dot = ab
				has_dot = true
			else:
				glass = ab
				has_glass = true
	if has_glass:
		var c := (dot if has_dot else glass).get_center()
		return Vector3(c.x, c.y, glass.end.z)
	var b := m.get_aabb()
	var top := b.get_center().y
	for si in m.get_surface_count():
		for v in m.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]:
			if v.z < b.position.z + 0.12 and absf(v.x) < 0.012 and v.y > top:
				top = v.y
	return Vector3(0.0, top, b.get_center().z)

static func _verts_aabb(vs: PackedVector3Array) -> AABB:
	if vs.is_empty():
		return AABB()
	var ab := AABB(vs[0], Vector3.ZERO)
	for v in vs:
		ab = ab.expand(v)
	return ab

## The magazine is its own surface of the rifle mesh: lift it out into a
## child mesh so the reload can take it out of the well and put it back.
func _split_mag(g: Node3D) -> MeshInstance3D:
	var mi := g as MeshInstance3D
	if mi == null or mi.mesh == null:
		return null
	var src := mi.mesh
	var at := -1
	for si in src.get_surface_count():
		var mat := mi.get_active_material(si)
		if mat == null:
			continue
		var tex: Texture2D = (mat as BaseMaterial3D).albedo_texture if mat is BaseMaterial3D else null
		if mat.resource_name.to_lower().contains("mag") or (tex and tex.resource_path.to_lower().contains("_mag")):
			at = si
			break
	if at < 0:
		return null
	var body := ArrayMesh.new()
	var magm := ArrayMesh.new()
	for si in src.get_surface_count():
		var dst := magm if si == at else body
		dst.add_surface_from_arrays(src.surface_get_primitive_type(si), src.surface_get_arrays(si))
		dst.surface_set_material(dst.get_surface_count() - 1, mi.get_active_material(si))
	mi.mesh = body
	for si in body.get_surface_count():
		mi.set_surface_override_material(si, null)
	var mag := MeshInstance3D.new()
	mag.name = "mag"
	mag.mesh = magm
	mi.add_child(mag)
	return mag

## the rifle's sky dims with the world's (main.gd fades the world sky's energy
## between day, the store and the night)
func _vm_sync_env() -> void:
	if _vm_sky_mat == null or not is_inside_tree():
		return
	if _world_sky_mat == null:
		var we := get_world_3d().environment
		if we and we.sky and we.sky.sky_material and ("energy_multiplier" in we.sky.sky_material):
			_world_sky_mat = we.sky.sky_material
		else:
			return
	var k: float = _world_sky_mat.get(&"energy_multiplier")
	if absf(k - _vm_sky_k) > 0.004:
		_vm_sky_k = k
		_vm_sky_mat.energy_multiplier = VM_SKY_ENERGY * k

## The first-person arms: the Rocketbox soldier (the MILITARY outfit's own
## model), cut down to its arms. Only the triangles skinned to the upper arms,
## forearms, hands and fingers are kept, split into a sleeve surface (tinted
## per outfit by dress_arms) and a glove surface; any vertex still weighted to
## the collarbones or the spine collapses to a point behind the lens. The
## skeleton is never animated: _arms sets the arm bones every frame and the
## fingers are curled once, round the grip and the handguard.
func _build_arms() -> void:
	var ps: PackedScene = load(VM_ARMS)
	op = ps.instantiate() as Node3D
	op.name = "arms"
	op.rotation.y = PI                # the soldier faces +Z; the lens looks down -Z
	op.position = VM_ARMS_AT
	vm_cam.add_child(op)
	anim = op.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim:
		anim.stop()
		anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for n in op.find_children("*", "Skeleton3D", true, false):
		_skel = n as Skeleton3D
		break
	var body: MeshInstance3D = null
	for n in op.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.skin and body == null:
			body = mi
		else:
			mi.visible = false        # the helmet camera, the pouches: not the arms
	if _skel == null or body == null:
		push_warning("player: no skinned arms in " + VM_ARMS)
		return
	_skel.reset_bone_poses()
	var names := ["Bip01 L UpperArm", "Bip01 L Forearm", "Bip01 L Hand", "Bip01 R UpperArm", "Bip01 R Forearm", "Bip01 R Hand"]
	for i in names.size():
		var b := _skel.find_bone(names[i])
		if b < 0:
			push_warning("player: arms bone missing: " + names[i])
			return
		_arm_bone[i] = b
		_arm_rest[i] = _skel.get_bone_global_rest(b)
	var arm := {}                     # bone -> 1 arm, 2 hand / finger
	for b in _skel.get_bone_count():
		var nm := _skel.get_bone_name(b)
		if nm.contains(" UpperArm") or nm.contains(" Forearm"):
			arm[b] = 1
		elif nm.contains(" Hand") or nm.contains(" Finger"):
			arm[b] = 2
	_arms_mesh(body, arm)
	# hand frames at rest (skeleton space): along = wrist to middle knuckle,
	# thumb = little-finger knuckle to index knuckle; the palm point is held
	# object's centre, a grip's radius off the palm
	for side in 2:
		var lr := "L" if side == 0 else "R"
		var h := _arm_rest[side * 3 + 2]
		var f1 := _skel.get_bone_global_rest(_skel.find_bone("Bip01 %s Finger1" % lr)).origin
		var f2 := _skel.get_bone_global_rest(_skel.find_bone("Bip01 %s Finger2" % lr)).origin
		var f4 := _skel.get_bone_global_rest(_skel.find_bone("Bip01 %s Finger4" % lr)).origin
		var a := (f2 - h.origin).normalized()
		var t := f1 - f4
		t = (t - a * t.dot(a)).normalized()
		var fr := Basis(a, t, a.cross(t))
		_frame_rest[side] = fr
		# a x t is the palm on the left hand and the back of it on the right
		var palm_n := a.cross(t) * (1.0 if side == 0 else -1.0)
		var p := h.origin + (f2 - h.origin) * 0.5 + palm_n * VM_PALM_OFF
		_palm[side] = h.basis.inverse() * (p - h.origin)
		_rel_fh[side] = _arm_rest[side * 3 + 1].basis.inverse() * h.basis
		# fingers curl toward the palm: about -t on the left hand, +t on the right
		var k := -t if side == 0 else t
		var curls: Array = VM_CURL_L if side == 0 else VM_CURL_R
		for f in 5:
			for j in 3:
				var bn := "Bip01 %s Finger%d%s" % [lr, f, "" if j == 0 else str(j)]
				var b := _skel.find_bone(bn)
				if b < 0:
					continue
				var kl := (_skel.get_bone_global_rest(b).basis.inverse() * k).normalized()
				var ang: float = curls[mini(f, 1) * 3 + j]
				_skel.set_bone_pose_rotation(b, _skel.get_bone_rest(b).basis.get_rotation_quaternion() * Quaternion(kl, ang))
	# the left hand as a node, for the magazine to ride in (set every frame)
	_hl = Node3D.new()
	_hl.name = "hand_l"
	_skel.add_child(_hl)
	_hl.transform = _arm_rest[2]
	_arms_ok = true

## Keep only the arm triangles of the body surface, as two surfaces over the
## same vertices - sleeves, then gloves - and collapse every other bone.
func _arms_mesh(mi: MeshInstance3D, arm: Dictionary) -> void:
	var src := mi.mesh
	var sk := mi.skin.duplicate() as Skin
	var bind_bone := PackedInt32Array()
	bind_bone.resize(sk.get_bind_count())
	for i in sk.get_bind_count():
		var b := sk.get_bind_bone(i)
		if b < 0:
			b = _skel.find_bone(sk.get_bind_name(i))
		bind_bone[i] = b
		if b >= 0 and not arm.has(b):
			# whatever still hangs off this bone is drawn at one point, behind the lens
			var o := _skel.get_bone_global_rest(b).affine_inverse() * VM_ARMS_HIDE
			sk.set_bind_pose(i, Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), o))
	var si := 0
	for i in src.get_surface_count():
		var m := mi.get_active_material(i) as BaseMaterial3D
		if m and m.albedo_texture and m.albedo_texture.resource_path.to_lower().contains("body"):
			si = i
			break
	var arr := src.surface_get_arrays(si)
	var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var nv: int = (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var per := bones.size() / maxi(nv, 1)
	var cls := PackedByteArray()
	cls.resize(nv)
	for v in nv:
		var best := -1
		var bw := -1.0
		for j in per:
			if weights[v * per + j] > bw:
				bw = weights[v * per + j]
				best = bones[v * per + j]
		var b := bind_bone[best] if best >= 0 and best < bind_bone.size() else -1
		cls[v] = arm.get(b, 0)
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var sleeves := PackedInt32Array()
	var gloves := PackedInt32Array()
	for t in idx.size() / 3:
		var c0: int = cls[idx[t * 3]]
		var c1: int = cls[idx[t * 3 + 1]]
		var c2: int = cls[idx[t * 3 + 2]]
		if c0 == 0 and c1 == 0 and c2 == 0:
			continue
		var dst := gloves if (c0 == 2 and c1 == 2 and c2 == 2) else sleeves
		dst.append(idx[t * 3])
		dst.append(idx[t * 3 + 1])
		dst.append(idx[t * 3 + 2])
	var flags: int = src.surface_get_format(si) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
	var mat := mi.get_active_material(si) as BaseMaterial3D
	var out := ArrayMesh.new()
	arr[Mesh.ARRAY_INDEX] = sleeves
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, flags)
	_sleeve_mat = mat.duplicate() as BaseMaterial3D if mat else StandardMaterial3D.new()
	_sleeve_tex = _sleeve_mat.albedo_texture
	_sleeve_rough = _sleeve_mat.roughness
	out.surface_set_material(0, _sleeve_mat)
	arr[Mesh.ARRAY_INDEX] = gloves
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, flags)
	out.surface_set_material(1, mat)
	mi.mesh = out
	mi.skin = sk
	for i in out.get_surface_count():
		mi.set_surface_override_material(i, null)
	mi.custom_aabb = AABB(Vector3(-2, -1, -2), Vector3(4, 4, 4))

## The outfit on the sleeves (main.gd _dress_arms). The soldier wears his
## sleeves rolled (bare forearms in the texture), which is the MILITARY
## outfit as it is; every other outfit rolls them down - the sleeve surface
## becomes plain cloth: a dark suit cloth for the SUIT, the palette's middle
## colour otherwise. The gloves never change.
func dress_arms(skin: Dictionary) -> void:
	if _sleeve_mat == null:
		return
	var id := str(skin.get("id", ""))
	if id == "military" or (id != "suit" and not skin.has("pal")):
		_sleeve_mat.albedo_texture = _sleeve_tex
		_sleeve_mat.albedo_color = Color.WHITE
		_sleeve_mat.roughness = _sleeve_rough
		return
	_sleeve_mat.albedo_texture = null
	_sleeve_mat.albedo_color = VM_SUIT_CLOTH if id == "suit" else Color(str((skin.pal as Array)[1]))
	_sleeve_mat.roughness = 0.92

## The framing's inputs: each rifle's rear sight in rig space (hand_r and
## gun_root sit at the rig's origin, square to it, so the rifle is square to
## the lens when vm_root is), and the ready carry's rotation.
func _vm_calibrate() -> void:
	gun_root.transform = Transform3D.IDENTITY
	hand_r.transform = Transform3D.IDENTITY
	_vm_q_ads = Quaternion.IDENTITY
	_vm_q_hip = Quaternion(Basis.from_euler(VM_HIP_ROT))
	_vm_sight_rig.clear()
	for i in WEAPONS.size():
		var g: Node3D = guns.get(WEAPONS[i].id)
		_vm_sight_rig.append(g.transform * _vm_sight[i] if g else Vector3(0.0, 0.1, 0.0))
	_vm_ready = true

func _play(name: String, blend := 0.2) -> void:
	if anim == null or _anim_now == name or not anim.has_animation(name):
		return
	anim.play(name, blend)
	_anim_now = name

# ------------------------------------------------------------------ breathing

## One breath after another, the family picked by how hard you are working:
## calm on your feet, medium and heavy as a sprint wears on, spent when you
## are hurt or blown, and held while you aim.
func _next_breath() -> void:
	if not active or not alive:
		return
	var fam := "breath_calm"
	if hp < max_hp * 0.3 or exertion > 0.85:
		fam = "breath_spent"
	elif ads_t > 0.6:
		fam = "breath_hold"
	elif exertion > 0.55:
		fam = "breath_heavy"
	elif exertion > 0.25:
		fam = "breath_medium"
	var v: Array = Game.variants(fam)
	if v.is_empty():
		return
	breath.stream = v[randi() % v.size()]
	breath.volume_db = lerpf(-19.0, -10.0, clampf(exertion, 0.0, 1.0))
	breath.pitch_scale = randf_range(0.96, 1.04)
	breath.play()

# ------------------------------------------------------------------ weapons

## the arrival hands you the rifle only when you take it out of the boot
func refresh_ammo() -> void:
	ammo_changed.emit(mag, MAG_SIZE, WEAPONS[weapon_index].name)

## Hands full (a cart, a melon, the axe) or the rifle still in the boot: the
## arms go with it, rather than hanging in the frame holding nothing. Coming
## back, the rifle is drawn up into the frame.
func show_rifle(on: bool) -> void:
	if gun_root:
		gun_root.visible = on
	if op:
		op.visible = on
	if on and not _rifle_on:
		_draw_t = 0.0
	if not on:
		_mag_home()
	_rifle_on = on

func select_weapon(i: int, silent := false) -> void:
	if i < 0 or i >= WEAPONS.size():
		return
	if i != weapon_index and not silent:
		Game.play("gun_holster", -8.0)
		get_tree().create_timer(0.18).timeout.connect(func(): Game.play("gun_draw", -4.0))
		_draw_t = 0.0                 # the new one comes up from below
	_mag_home()
	weapon_index = i
	for id in guns:
		guns[id].visible = (id == WEAPONS[i].id)
	ammo_changed.emit(mag, MAG_SIZE, WEAPONS[i].name)

func try_reload() -> void:
	if reloading or mag >= MAG_SIZE or not alive:
		return
	reloading = true
	reload_t = 0.0
	_reload_stage = 0
	Game.vo("reloading", 14.0, 0.35)
	# the reload is procedural (_vm_reload), timed to the sounds below: the
	# operator's reload clip is 1.6 s against the 1.9 s reload and drops the
	# rifle out of the frame

func _reload_tick(dt: float) -> void:
	if not reloading:
		return
	reload_t += dt
	# a reload is several events, not one noise: mag out, a fumble, mag in,
	# bolt home - scheduled as fractions of the reload
	var stages := [[0.08, "gun_magout"], [0.34, "gun_fumble"], [0.55, "gun_magin"], [0.8, "gun_charge"]]
	while _reload_stage < stages.size() and reload_t >= stages[_reload_stage][0] * RELOAD_TIME:
		Game.play(stages[_reload_stage][1], -5.0)
		# the rifle answers the hands: a shove up as the mag seats, a jerk as
		# the bolt is racked
		if _reload_stage == 2:
			_jo_v += Vector3(0.0, 0.55, 0.0)
			_rk_rv += Vector3(0.9, 0.0, 0.0)
		elif _reload_stage == 3:
			_jo_v += Vector3(0.0, 0.0, 0.45)
			_rk_rv += Vector3(-0.5, 0.0, 1.2)
		_reload_stage += 1
	if reload_t >= RELOAD_TIME:
		reloading = false
		mag = MAG_SIZE
		_anim_now = ""
		ammo_changed.emit(mag, MAG_SIZE, WEAPONS[weapon_index].name)

func _fire() -> void:
	if reloading or fire_cd > 0.0 or not alive:
		return
	if mag <= 0:
		Game.play("gun_dry", -6.0)
		Game.vo("need_ammo", 20.0, 0.4)
		fire_cd = 0.25
		try_reload()
		return
	var w: Dictionary = WEAPONS[weapon_index]
	fire_cd = w.interval
	mag -= 1
	Game.shots += 1
	ammo_changed.emit(mag, MAG_SIZE, w.name)
	GunSound.fire(camera.global_position, Game.phase == "inside")   # crack, mechanism, echo or reverb
	# recoil: a vertical kick with a little random drift sideways, pushed onto
	# a target the view eases toward, so a burst climbs rather than snaps;
	# a braced aim soaks up nearly half of it
	var steady := lerpf(1.0, 0.55, ads_t)
	_rec_to.x += 0.017 * steady * randf_range(0.85, 1.15)
	_rec_to.y += randf_range(-0.0055, 0.0055) * steady
	_punch = 1.0
	_punch_side = -1.0 if randf() < 0.5 else 1.0
	# the report through the stock, the shoulder and up the neck: the helmet
	# nods and twists a little on every round (half of it braced on the sights)
	var brace := lerpf(1.0, 0.45, ads_t)
	_hjv.x += 0.12 * brace * randf_range(0.8, 1.2)
	_hjv.z += randf_range(-0.22, 0.22) * brace
	_hpv.z += 0.3 * brace
	# the rifle itself (cosmetic, the rounds leave the lens): straight back
	# into the shoulder, the muzzle climbing about the grip, a random twist;
	# held heat makes a long burst climb and walk, then settle
	var vk := lerpf(1.0, 0.45, ads_t)
	_rk_v += Vector3(randf_range(-1.0, 1.0) * VM_KICK_V.x, VM_KICK_V.y * randf_range(0.6, 1.2), VM_KICK_V.z * randf_range(0.9, 1.1)) * vk
	_rk_rv += Vector3(VM_KICK_RV.x * randf_range(0.85, 1.15), randf_range(-1.0, 1.0) * VM_KICK_RV.y, randf_range(-1.0, 1.0) * VM_KICK_RV.z) * vk
	_rk_heat += 1.0
	kick = 1.0
	shake = maxf(shake, 0.12)
	flash_light.light_energy = randf_range(3.4, 4.8)
	flash_mesh.visible = true
	flash_mesh.rotation.z = randf() * TAU
	flash_mesh.scale = Vector3.ONE * randf_range(0.75, 1.35)
	_flash_frames = 1 + randi() % 2
	_eject_casing()

	var spread: float = w.spread * (0.35 if ads_t > 0.5 else 1.0)
	var from := camera.global_position
	var dir := -camera.global_basis.z
	dir = (dir + camera.global_basis.x * randf_range(-spread, spread) + camera.global_basis.y * randf_range(-spread, spread)).normalized()
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 250.0, 1 | 4 | 8 | 32)   # 8: the car, 32: small props
	q.exclude = [get_rid()]
	q.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	var col: Object = hit.collider
	var target: Node = col as Node
	while target and not target.has_method("take_hit"):
		target = target.get_parent()
	if target and target.has_method("take_hit"):
		var headshot: bool = target.call("is_head", hit.position)
		var dmg: float = w.damage * (HEAD_MULT if headshot else 1.0)
		var killed: bool = target.call("take_hit", dmg, hit.position, dir)
		Game.hits += 1
		if headshot:
			Game.headshots += 1
		# the web's table: +10 / +15 a hit, +55 / +90 a kill
		Game.add_points(15 if headshot else 10)
		if killed:
			var base := 90 if headshot else 55
			Game.add_points(base, ("HEADSHOT +%d" if headshot else "+%d") % base, headshot)
		hit_marker.emit(headshot, killed)
		if killed and headshot:
			Game.vo("nice_shot", 15.0, 0.5)
	else:
		var surf := "concrete"
		var n: Node = col as Node
		while n:
			if n.has_meta("surface"):
				surf = n.get_meta("surface")
				break
			n = n.get_parent()
		# the car is a CharacterBody3D, not tagged - it is a car
		if col is CharacterBody3D:
			surf = "metal"
		_impact(hit.position, hit.normal, surf)
		# glass, crates, pottery: breakable.gd
		if col is Node and (col as Node).has_method("shoot"):
			col.call("shoot", w.damage, hit.position, dir)
		elif not (col is CharacterBody3D):
			_bullet_hole(hit.position, hit.normal)

## a hole that stays where the round went in; the oldest of 64 is reused
func _bullet_hole(pos: Vector3, n: Vector3) -> void:
	if _hole_tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.35, 0.6, 1.0])
		g.colors = PackedColorArray([Color(0.02, 0.018, 0.015, 1), Color(0.05, 0.045, 0.04, 0.95),
			Color(0.12, 0.11, 0.1, 0.45), Color(0.2, 0.19, 0.18, 0)])
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(1.0, 0.5)
		gt.width = 32
		gt.height = 32
		_hole_tex = gt
	var d: Decal
	if _holes.size() >= 64:
		d = _holes.pop_front()
	else:
		d = Decal.new()
		d.texture_albedo = _hole_tex
		d.size = Vector3(0.08, 0.1, 0.08)
		d.cull_mask = 1 | 32            # walls and props, never people or the car
		get_tree().current_scene.add_child(d)
	_holes.append(d)
	var up := n.normalized()
	var ref := Vector3.UP if absf(up.y) < 0.95 else Vector3.RIGHT
	var x := ref.cross(up).normalized()
	var z := x.cross(up).normalized()
	d.global_transform = Transform3D(Basis(up, randf() * TAU) * Basis(x, up, z), pos)
	d.scale = Vector3.ONE * randf_range(0.8, 1.25)

func _impact(pos: Vector3, normal: Vector3, kind := "concrete") -> void:
	Game.play_at("hit_" + kind, pos, -6.0)
	Fx.impact(pos, normal, kind)      # pooled sparks / dust / chips / splinters / shards

## a spent case out of the port, to the right and a little forward, carrying
## your own speed; it tinks once on the first thing it meets
func _eject_casing() -> void:
	var host := get_tree().current_scene
	if host == null:
		return
	var b: RigidBody3D
	if _casings.size() < CASINGS:
		b = _make_casing()
		host.add_child(b)
		_casings.append(b)
	else:
		b = _casings[_casing_i]
		_casing_i = (_casing_i + 1) % CASINGS
		if not is_instance_valid(b) or not b.is_inside_tree():
			b = _make_casing()
			host.add_child(b)
			_casings[(_casing_i + CASINGS - 1) % CASINGS] = b
	var cb := camera.global_basis
	var at := camera.global_position + cb * Vector3(0.09, -0.09, -0.32 + ads_t * 0.08)
	# lie across the view, the way it leaves the port
	b.global_transform = Transform3D(cb * Basis(Vector3.BACK, PI / 2), at)
	b.linear_velocity = velocity + cb * Vector3(randf_range(2.2, 3.2), randf_range(1.3, 2.1), randf_range(-0.1, 0.5))
	b.angular_velocity = cb * Vector3(randf_range(-6, 6), randf_range(-25, -12), randf_range(-8, 8))
	b.sleeping = false
	b.set_meta("fresh", true)

func _make_casing() -> RigidBody3D:
	if _casing_mesh == null:
		_casing_mesh = CylinderMesh.new()
		_casing_mesh.top_radius = 0.0048
		_casing_mesh.bottom_radius = 0.0056
		_casing_mesh.height = 0.028
		_casing_mesh.radial_segments = 8
		_casing_mesh.rings = 1
		var m := U.flat_mat(Color(0.78, 0.57, 0.25), 0.28, 1.0)
		_casing_mesh.material = m
		_casing_shape = CapsuleShape3D.new()
		_casing_shape.radius = 0.0056
		_casing_shape.height = 0.028
	var b := RigidBody3D.new()
	b.collision_layer = 0          # nothing hits a case; it only meets the world
	b.collision_mask = 1 | 32
	b.mass = 0.01
	b.continuous_cd = true
	b.contact_monitor = true
	b.max_contacts_reported = 1
	b.angular_damp = 1.5
	var pmat := PhysicsMaterial.new()
	pmat.bounce = 0.35
	pmat.friction = 0.6
	b.physics_material_override = pmat
	var cs := CollisionShape3D.new()
	cs.shape = _casing_shape
	b.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = _casing_mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	b.add_child(mi)
	b.body_entered.connect(_casing_hit.bind(b))
	return b

func _casing_hit(_body: Node, b: RigidBody3D) -> void:
	if not b.get_meta("fresh", false):
		return
	b.set_meta("fresh", false)
	Game.play_at("hit_metal", b.global_position, -24.0, randf_range(2.2, 2.7))

# ------------------------------------------------------------------ damage

func take_damage(dmg: float, from: Vector3) -> void:
	if not alive or not active or Game.god:
		return
	hp = maxf(0.0, hp - dmg)
	regen_cd = 4.0
	shake = maxf(shake, 0.35)
	# the head snaps away from the blow and comes back
	var to := from - global_position
	var side := signf(to.dot(Vector3(cos(yaw), 0.0, -sin(yaw)))) if to.length_squared() > 0.01 else 0.0
	var s := clampf(dmg / 25.0, 0.4, 1.2)
	_hjv += Vector3(randf_range(0.4, 0.9), side * 0.8 + randf_range(-0.2, 0.2), side * 1.3 +randf_range(-0.3, 0.3)) * s
	_hpv += Vector3(-side * 0.4, 0.1, 0.5) * s
	damaged.emit(from)
	hp_changed.emit(hp, max_hp)
	Game.play("pain_hit", -3.0)
	Game.play_file("sfx-player-hit.mp3", -6.0, randf_range(0.95, 1.05))
	Game.vo("hit", 12.0, 0.3)
	if hp < max_hp * 0.3 and not _low_hp_said and hp > 0.0:
		_low_hp_said = true
		Game.vo("low_hp", 20.0)
	if hp > max_hp * 0.6:
		_low_hp_said = false
	if hp <= 0.0:
		alive = false
		breath.stop()
		Game.play_file("sfx-body-drop.mp3", -4.0)
		died.emit()

func heal_full() -> void:
	hp = max_hp
	alive = true
	_dead_t = 0.0
	hp_changed.emit(hp, max_hp)

# ------------------------------------------------------------------ loop

func _unhandled_input(e: InputEvent) -> void:
	if not active or not alive or input_locked:
		return
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var m := e as InputEventMouseMotion
		var sens: float = MOUSE_SENS * float(Game.settings.sens) / 100.0
		var inv := -1.0 if Game.settings.invert else 1.0
		yaw -= m.relative.x * sens
		pitch = clampf(pitch - m.relative.y * sens * inv, -1.45, 1.45)
		# the rifle trails the turn a touch: it has weight
		_sway_to += Vector2(m.relative.x, m.relative.y * inv) * sens * 0.35
		_sway_to = _sway_to.clamp(Vector2(-0.07, -0.05), Vector2(0.07, 0.05))
	elif holding:
		return               # hands are full: no reload, no weapon swap
	elif e.is_action_pressed("reload"):
		try_reload()
	elif e.is_action_pressed("weapon_1"):
		select_weapon(0)
	elif e.is_action_pressed("weapon_2"):
		select_weapon(1)
	elif e.is_action_pressed("weapon_3"):
		select_weapon(2)
	elif e.is_action_pressed("next_weapon"):
		select_weapon((weapon_index + 1) % WEAPONS.size())

func _physics_process(dt: float) -> void:
	if not active:
		return
	fire_cd = maxf(0.0, fire_cd - dt)
	if input_locked:
		velocity = Vector3.ZERO
		return
	if alive:
		_move(dt)
		if Input.is_action_pressed("fire") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not holding:
			_fire()
	if alive and not holding:
		_reload_tick(dt)
	# under a third of your health the heart comes up, faster the worse it is
	if alive and hp < max_hp * 0.35:
		_heart_t -= dt
		if _heart_t <= 0.0:
			_heart_t = lerpf(0.5, 0.95, hp / (max_hp * 0.35))
			heart.play()
	else:
		_heart_t = 0.0
	if alive and hp < max_hp:
		regen_cd -= dt
		if regen_cd <= 0.0:
			hp = minf(max_hp, hp + 9.0 * dt)
			hp_changed.emit(hp, max_hp)

func _move(dt: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var sprinting := Input.is_action_pressed("sprint") and input.y < -0.1 and ads_t < 0.3
	_sprinting = sprinting
	var spd := SPRINT if sprinting else WALK
	var basis := Basis(Vector3.UP, yaw)
	var wish := basis * Vector3(input.x, 0, input.y) * spd
	var k := clampf(ACCEL * dt, 0.0, 1.0)
	velocity.x = lerpf(velocity.x, wish.x, k)
	velocity.z = lerpf(velocity.z, wish.z, k)
	if is_on_floor():
		if Input.is_action_just_pressed("jump"):
			velocity.y = JUMP
			Game.play("pain_effort", -12.0)
			exertion = minf(1.0, exertion + 0.08)
	else:
		velocity.y -= GRAVITY * dt
	var fall_speed := -velocity.y
	move_and_slide()
	if is_on_floor() and not _was_floor and fall_speed > 3.0:
		Game.play("step_" + _surface(), -3.0, 0.85)       # landing
		Game.play("gear_rustle", -12.0)
		_land_t = 0.0
		_land_amp = clampf((fall_speed - 2.0) / 8.0, 0.2, 1.0)
		# the helmet keeps going when the boots stop: a nod and a twist
		_hjv.x -= 0.9 * _land_amp
		_hjv.z += randf_range(-0.45, 0.45) * _land_amp
		# the rifle's weight carries on down: it dips, muzzle first, and comes back
		_jo_v += Vector3(0.0, -0.75, 0.1) * _land_amp
		_lk_v += Vector3(-1.4, 0.0, randf_range(-0.6, 0.6)) * _land_amp
	_was_floor = is_on_floor()
	exertion = clampf(exertion + (dt * 0.09 if sprinting else -dt * 0.06), 0.0, 1.0)

	var speed := Vector2(velocity.x, velocity.z).length()
	# footsteps on the stride, surface by where you are; the same phase drives
	# the head bob, so every bounce of the lens lands on a footfall
	var ph0 := _step_ph
	_step_ph += speed * dt / (1.9 if sprinting else 1.6)
	if _step_ph > 1000.0:
		_step_ph -= 1000.0        # an even count: the bob's phase is unchanged
		ph0 -= 1000.0
	if floorf(_step_ph) != floorf(ph0) and is_on_floor():
		var surf := _surface()
		var sprint_ok := sprinting and (surf == "tile" or surf == "concrete")
		Game.play(("sprint_" if sprint_ok else "step_") + surf, -9.0 if not sprinting else -7.0)
	# kit shifting on you as you move
	if speed > 1.0:
		_rustle_t -= dt * (1.6 if sprinting else 1.0)
		if _rustle_t <= 0.0:
			_rustle_t = randf_range(4.0, 8.0)
			Game.play("gear_rustle", -16.0)
	# no clip switching: the arms hold the aim pose and the walk, the sprint
	# carry and the reload are laid over it in _vm_update

## what you are standing on: tile in the store, asphalt and paving on the lot
## and road, grass on the verge, gravel on the unmade ground beyond it
func _surface() -> String:
	var p := global_position
	# Al-Salaam: tiled halls and courtyard, and the flags round the ablution
	# fountain are always wet (mosque-local coordinates, see mosque.gd)
	var lx := (p.x - MosqueScript.X) / MosqueScript.S
	var lz := (p.z - MosqueScript.MQ_Z) / MosqueScript.S
	if absf(lx) < 27.5 and lz > -16.5 and lz < 32.4:
		return "wet" if Vector2(lx, lz - 23.0).length() < 5.2 else "tile"
	if absf(p.x) < 22.0 and absf(p.z) < 15.0:
		return "tile"
	if absf(p.z - 36.0) < 4.2 or (absf(p.x) < 24.0 and p.z < 30.2) or absf(p.z - 31.15) < 0.8 or absf(p.z - 41.35) < 1.3:
		return "concrete"
	if p.z > 15.2 and p.z < 60.4:
		return "grass"
	return "gravel"

func _process(dt: float) -> void:
	if not active:
		return
	var aiming := Input.is_action_pressed("aim") and alive and not reloading and not input_locked and not holding
	if aiming != _was_aiming:
		Game.play("gun_adsin" if aiming else "gun_adsout", -10.0)
		_was_aiming = aiming
	ads_t = move_toward(ads_t, 1.0 if aiming else 0.0, dt * 6.0)
	# the kicks' target settles back, the view eases after it: a smooth climb
	# under a burst and a smooth recovery once the trigger comes up
	_rec_to = _rec_to.lerp(Vector2.ZERO, clampf(dt * 6.0, 0.0, 1.0))
	_rec = _rec.lerp(_rec_to, clampf(dt * 26.0, 0.0, 1.0))
	recoil = _rec.x
	kick = lerpf(kick, 0.0, clampf(dt * 14.0, 0.0, 1.0))
	_punch = maxf(0.0, _punch - dt * 16.0)
	shake = maxf(0.0, shake - dt * 2.4)
	flash_light.light_energy = lerpf(flash_light.light_energy, 0.0, clampf(dt * 30.0, 0.0, 1.0))
	if _flash_frames > 0:
		_flash_frames -= 1
	else:
		flash_mesh.visible = false
	_sway_to = _sway_to.lerp(Vector2.ZERO, clampf(dt * 7.0, 0.0, 1.0))
	_sway = _sway.lerp(_sway_to, clampf(dt * 14.0, 0.0, 1.0))
	var lower := _sprinting and not reloading and ads_t < 0.1 and Vector2(velocity.x, velocity.z).length() > WALK * 0.8
	_sprint_k = move_toward(_sprint_k, 1.0 if lower else 0.0, dt * 4.5)
	var dip := 0.0
	if _land_t < 0.42:
		_land_t += dt
		dip = sin(PI * pow(clampf(_land_t / 0.42, 0.0, 1.0), 0.6)) * 0.085 * _land_amp

	_head(dt, dip)

## The lens rides the helmet. Everything here is cosmetic and eased: the bob
## is locked to the footfalls, the head banks into strafes and whip-pans and
## settles after them, and shots, hits and landings jolt it through springs.
## The aim itself (yaw, pitch, recoil) is never delayed: the lag is a small
## spring offset that falls back to zero, so the rounds still leave the lens.
func _head(dt: float, dip: float) -> void:
	var dtc := minf(dt, 1.0 / 30.0)
	var speed := Vector2(velocity.x, velocity.z).length()
	var grounded := is_on_floor()
	var moving := clampf(speed / WALK, 0.0, 1.0) if grounded and alive else 0.0
	_bob_amp = lerpf(_bob_amp, moving, clampf(dt * 8.0, 0.0, 1.0))
	_bob_sprint = lerpf(_bob_sprint, 1.0 if (_sprinting and speed > WALK + 0.3) else 0.0, clampf(dt * 5.0, 0.0, 1.0))
	var calm := 1.0 - ads_t * 0.85
	var amp := _bob_amp * calm
	var sp := _bob_sprint
	var ph := _step_ph * PI
	var s1 := sin(ph)                         # side to side over a pair of steps
	var s2 := 0.5 - 0.5 * cos(2.0 * ph)       # up between footfalls, down on each
	var bob_y := (s2 - 0.5) * lerpf(0.028, 0.05, sp) * amp
	var bob_x := s1 * lerpf(0.016, 0.032, sp) * amp
	var bob_roll := -s1 * lerpf(0.006, 0.016, sp) * amp
	var bob_nod := (0.5 - s2) * lerpf(0.004, 0.012, sp) * amp
	var bob_yaw := s1 * lerpf(0.003, 0.009, sp) * amp
	# strafe: the head banks into the side you are moving to
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var lean_to := -velocity.dot(right) / SPRINT * 0.03 * (1.0 - ads_t * 0.6) if alive else 0.0
	_lean = lerpf(_lean, lean_to, clampf(dt * 6.0, 0.0, 1.0))
	# turn inertia: the rate of the look, eased; the head lags a whip, banks
	# into it and overshoots a hair on the stop
	var look := Vector2(yaw, pitch)
	var dl := Vector2(wrapf(look.x - _prev_look.x, -PI, PI), look.y - _prev_look.y)
	_prev_look = look
	var w := (dl / maxf(dt, 0.001)).clamp(Vector2(-14.0, -14.0), Vector2(14.0, 14.0))
	_turn_w = _turn_w.lerp(w, clampf(dt * 14.0, 0.0, 1.0))
	var tk := 1.0 - ads_t * 0.7
	var t_to := Vector3(clampf(-_turn_w.y * 0.0035, -0.012, 0.012), clampf(-_turn_w.x * 0.0035, -0.012, 0.012),
		clampf(_turn_w.x * 0.006, -0.035, 0.035)) * tk
	_turn_vel += ((t_to - _turn_off) * 170.0 - _turn_vel * 17.0) * dtc
	_turn_off += _turn_vel * dtc
	# jolts
	_hjv += (-_hj * 150.0 - _hjv * 13.0) * dtc
	_hj += _hjv * dtc
	_hpv += (-_hp * 120.0 - _hpv * 12.0) * dtc
	_hp += _hpv * dtc
	# breathing when you stand: slow, deeper when blown, half held on the sights
	_breath_t += dt * lerpf(1.4, 2.6, exertion)
	var still := (1.0 - _bob_amp) * (1.0 - ads_t * 0.6) if alive else 0.0
	var br := (0.0022 + exertion * 0.004) * still
	var breath_p := sin(_breath_t) * br
	var breath_y := sin(_breath_t * 0.5 + 1.3) * br * 0.5
	# shake, as smooth noise rather than a new random every frame
	_shake_t += dt
	var t := _shake_t
	var n := Vector3(sin(t * 31.0) + sin(t * 17.3 + 1.7), sin(t * 27.1 + 0.4) + sin(t * 13.9 + 2.2), sin(t * 23.7 + 3.1)) * 0.5 * shake

	rotation.y = 0.0
	# the punch: a flick of roll and a nudge back down the bore, gone in a blink
	var pk := _punch * _punch * (1.0 - ads_t * 0.5)
	var head := Vector3(bob_nod + breath_p + _turn_off.x + _hj.x,
		bob_yaw + breath_y + _turn_off.y + _hj.y,
		bob_roll + _lean + _turn_off.z + _hj.z + _punch_side * pk * 0.012 + n.z * 0.03)
	camera.rotation = Vector3(pitch + recoil + head.x, yaw + _rec.y + head.y, head.z)
	var hy := bob_y - dip + sin(_breath_t) * 0.004 * still
	camera.position = Vector3(0.0, EYE + hy, 0.0) + Basis(Vector3.UP, yaw) * Vector3(bob_x, 0.0, 0.0) \
		+ Basis.from_euler(Vector3(pitch, yaw, 0.0)) * MOUNT
	camera.position += camera.basis * (_hp + Vector3(n.x * 0.04, n.y * 0.04, pk * 0.018))
	if not alive:
		# the rotation is rebuilt every frame above, so the fall is a function
		# of time since death rather than a lerp that never accumulates
		_dead_t += dt
		var k := 1.0 - exp(-_dead_t * 2.0)
		camera.rotation.z = 0.35 * k
		camera.position.y = lerpf(camera.position.y, 0.6, k)
	# GoPro-wide on foot: the web's .66x aiming, 1.09x sprinting
	var want_fov := fov_base * (1.09 if _sprinting and ads_t < 0.1 else 1.0)
	_fov_now = lerpf(_fov_now, want_fov, clampf(dt * 9.0, 0.0, 1.0))
	camera.fov = lerpf(_fov_now, fov_base * 0.66, ads_t)
	# the sensor smears a fast turn (and a hit's snap): the look's rate over
	# the shutter, in screen heights, past a dead zone so a steady track stays sharp
	var ang := _turn_w + Vector2(_hjv.y, _hjv.x) * 0.5
	var vs := get_viewport().get_visible_rect().size
	var fov_v := deg_to_rad(camera.fov)
	var bv := Vector2(ang.x * SHUTTER / (fov_v * maxf(vs.x / maxf(vs.y, 1.0), 0.5)), ang.y * SHUTTER / fov_v)
	var bl := bv.length()
	var blur := Vector2.ZERO
	if bl > 0.006 and alive:
		blur = bv * (minf(bl - 0.006, 0.022) / bl)
	_send_blur(blur.snapped(Vector2(0.0005, 0.0005)))

	# the viewmodel camera rides the main one
	vm_cam.global_transform = camera.global_transform
	_vm_lag = lerpf(_vm_lag, hy + dip, clampf(dt * 11.0, 0.0, 1.0))
	_vm_update(dt, hy, dip, bob_x, pk, Vector3(bob_nod + _hj.x + _turn_off.x,
		bob_yaw + _hj.y + _turn_off.y, bob_roll + _lean + _hj.z))

# ------------------------------------------------------------------ viewmodel motion

static func _smooth(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)

## 0 -> 1 between a and b, smoothstepped
static func _seg(u: float, a: float, b: float) -> float:
	return _smooth((u - a) / maxf(b - a, 0.0001))

## The whole rig, every frame, with no allocations. vm_root holds the base
## framing - the rear sight at VM_HIP_AT, squared up and canted by
## VM_HIP_ROT, eased onto the lens axis (VM_ADS_AT) on the sights - and
## vm_pivot lays every procedural layer over it, rotating about the grip
## (VM_PIVOT) so the muzzle climbs and the carry drops about the hands, not
## the eye. The rifle rides the body, not the helmet: it holds against part of
## the head's nods and jolts and bobs a beat behind it in the same step phase,
## so the two never fight.
func _vm_update(dt: float, hy: float, dip: float, bob_x: float, pk: float, head_rot: Vector3) -> void:
	if not _vm_ready or op == null or not op.visible:
		return
	var wi := weapon_index
	_vm_sync_env()
	# --- base framing, hip to sights: smootherstep, rising through a small arc
	var a := ads_t
	var e := a * a * a * (a * (a * 6.0 - 15.0) + 10.0)
	vm_cam.fov = lerpf(VM_FOV_HIP, VM_FOV_ADS, e)
	var rb := Basis(_vm_q_hip.slerp(_vm_q_ads, e))
	var at := VM_HIP_AT.lerp(VM_ADS_AT, e) + VM_ADS_ARC * sin(PI * e)
	vm_root.transform = Transform3D(rb, at - rb * _vm_sight_rig[wi])
	var sw := 1.0 - e * 0.75            # a braced aim soaks up most of the sway
	var still := 1.0 - _bob_amp

	# --- springs, integrated in fixed sub-steps so any frame rate feels the same
	var steady := lerpf(1.0, 0.55, a)
	_rk_heat *= exp(-dt * VM_HEAT_DECAY)
	var heat := minf(_rk_heat * VM_HEAT_CLIMB, VM_HEAT_MAX) * steady
	var rk_to_r := Vector3(heat, 0.0, 0.0)
	var rk_to_p := Vector3(0.0, 0.0, heat * 0.35)
	var lk_to := Vector3(clampf(-_turn_w.y * VM_LOOK_LAG, -0.07, 0.07),
		clampf(-_turn_w.x * VM_LOOK_LAG, -0.09, 0.09),
		clampf(_turn_w.x * VM_LOOK_ROLL, -0.07, 0.07)) * sw
	var wd := VM_WALL_REACH
	if _wall_ray.is_colliding():
		wd = camera.global_position.distance_to(_wall_ray.get_collision_point())
	var wall_to := clampf((VM_WALL_REACH - wd) / (VM_WALL_REACH - VM_WALL_MIN), 0.0, 1.0)
	var n := clampi(ceili(dt * 240.0), 1, 24)
	var h := dt / float(n)
	for i in n:
		_rk_v += ((rk_to_p - _rk_p) * 320.0 - _rk_v * 27.0) * h
		_rk_p += _rk_v * h
		_rk_rv += ((rk_to_r - _rk_r) * 210.0 - _rk_rv * 19.0) * h
		_rk_r += _rk_rv * h
		_lk_v += ((lk_to - _lk) * 95.0 - _lk_v * 13.0) * h
		_lk += _lk_v * h
		_jo_v += (-_jo * 170.0 - _jo_v * 15.0) * h
		_jo += _jo_v * h
		_wall_v += ((wall_to - _wall) * 70.0 - _wall_v * 15.0) * h
		_wall += _wall_v * h

	var rot := Vector3.ZERO
	var pos := Vector3.ZERO
	# --- rides the body: holds against part of the head's nods and jolts
	rot -= head_rot * 0.45 * sw
	pos.y += -dip * 0.55 + (_vm_lag - hy - dip) * 0.8 * sw
	pos.x -= bob_x * 0.25 * sw
	# --- its own bob, in the head's step phase and a beat behind it
	var sp := _bob_sprint
	var ph := _step_ph * PI - VM_BOB_LAG
	var s1 := sin(ph)
	var s2 := 0.5 - 0.5 * cos(2.0 * ph)
	var bamp := _bob_amp * (1.0 - e * 0.8) * lerpf(1.0, 2.2, sp)
	pos.x += s1 * VM_BOB.x * bamp
	pos.y += (s2 - 0.5) * VM_BOB.y * bamp
	rot.z += s1 * VM_BOB.z * bamp
	rot.y += s1 * VM_BOB.z * 0.35 * bamp
	# --- breathing and a slow drift when you stand; deeper when blown
	var br := VM_BREATH * (1.0 + exertion * 1.5) * lerpf(1.0, 0.3, e) * (0.35 + 0.65 * still)
	rot.x += sin(_breath_t) * br
	pos.y += sin(_breath_t) * br * 0.25
	rot.y += sin(_breath_t * 0.37 + 0.8) * br * 0.7
	rot.z += sin(_breath_t * 0.23 + 2.1) * br * 0.5
	# --- trails the look, and leans into a strafe
	rot += _lk
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	_strafe = lerpf(_strafe, velocity.dot(right) / SPRINT, 1.0 - exp(-dt * 6.0))
	rot.z -= _strafe * VM_STRAFE_ROLL * sw
	pos.x -= _strafe * 0.012 * sw
	# --- sprint carry: low, across and canted
	var sk := _smooth(_sprint_k)
	rot += VM_SPRINT_ROT * sk
	pos += VM_SPRINT_POS * sk
	# --- recoil, the punch's flick, jolts
	rot += _rk_r
	rot.z += _punch_side * pk * 0.02
	pos += _rk_p + _jo
	# --- a wall in the way: tuck it in
	var wk := _smooth(_wall) * (1.0 - e * 0.4)
	rot += VM_WALL_ROT * wk
	pos += VM_WALL_POS * wk
	# --- the reload: the rifle is canted and lifted to the hands, the left
	# hand goes to the magazine, down to the vest, back, then over to the handle
	var palm_to := VM_HANDGUARD
	var u := clampf(reload_t / RELOAD_TIME, 0.0, 1.0) if reloading else 1.0
	if reloading:
		var tin := _seg(u, 0.0, 0.1) * (1.0 - _seg(u, 0.84, 1.0))
		var magw := 1.0 - _seg(u, 0.56, 0.7)
		rot += Vector3(0.16, 0.14, -0.55) * tin * magw
		rot += Vector3(0.06, 0.05, 0.3) * tin * (1.0 - magw)
		pos += Vector3(-0.035, 0.035, 0.02) * tin
		# fumbling at the vest
		rot.z += sin(u * 70.0) * 0.012 * _seg(u, 0.24, 0.3) * (1.0 - _seg(u, 0.4, 0.46))
		palm_to = _vm_reload_palm(u)
	_mag_update(u)
	# --- the draw: up from below, a touch past, settle
	if _draw_t < 1.0:
		_draw_t = minf(1.0, _draw_t + dt / VM_DRAW_TIME)
	var t1 := _draw_t - 1.0
	var dk := 1.0 - (1.0 + 2.2 * t1 * t1 * t1 + 1.2 * t1 * t1)   # 1 -> 0, easing out with overshoot
	rot += VM_DRAW_ROT * dk
	pos += VM_DRAW_POS * dk

	var pb := Basis.from_euler(rot)
	var piv := at + VM_PIVOT
	vm_pivot.transform = Transform3D(pb, piv - pb * piv + pos)
	_arms(palm_to, e, u)

## where the left palm goes through the reload (gun-local), timed to the
## sounds in _reload_tick: magout .08, fumble .34, magin .55, charge .80
func _vm_reload_palm(u: float) -> Vector3:
	var hg := VM_HANDGUARD
	var grab := VM_MAG_GRAB
	var drop := VM_MAG_GRAB + VM_MAG_DROP
	var ch := VM_CHARGE
	if u < 0.08:
		return hg.lerp(grab, _seg(u, 0.0, 0.075))
	if u < 0.16:
		return grab.lerp(drop, _seg(u, 0.08, 0.15))
	if u < 0.3:
		return drop.lerp(VM_POUCH, _seg(u, 0.16, 0.28))
	if u < 0.42:
		return VM_POUCH + Vector3(0.0, sin(u * 40.0) * 0.015, 0.0)
	if u < 0.55:
		var k := _seg(u, 0.42, 0.5)
		return VM_POUCH.lerp(drop, k).lerp(grab, _seg(u, 0.5, 0.55))
	if u < 0.66:
		return grab.lerp(ch, _seg(u, 0.57, 0.66))
	if u < 0.8:
		return ch
	if u < 0.86:
		return ch + Vector3(0.0, 0.0, VM_CHARGE_PULL) * _seg(u, 0.8, 0.83)
	return (ch + Vector3(0.0, 0.0, VM_CHARGE_PULL)).lerp(hg, _seg(u, 0.86, 0.97))

## the magazine: seated, sliding out of the well, or in the left hand
func _mag_update(u: float) -> void:
	var m: MeshInstance3D = _mags[weapon_index] if weapon_index < _mags.size() else null
	if m == null:
		return
	var want := 0
	if reloading:
		if u >= 0.08 and u < 0.16:
			want = 1
		elif u >= 0.16 and u < 0.55:
			want = 2
	var g: Node3D = guns.get(WEAPONS[weapon_index].id)
	if want == 2 and _hl == null:
		want = 1                       # no hand to take it: it stays by the well
	if want == 2 and _mag_state != 2:
		m.reparent(_hl, true)          # it goes with the hand from here
	elif want != 2 and _mag_state == 2:
		m.reparent(g, false)           # back in the well (the hand is off-screen or on it)
	_mag_state = want
	if want == 0:
		m.transform = Transform3D.IDENTITY
	elif want == 1:
		m.transform = Transform3D(Basis.IDENTITY, VM_MAG_DROP * _seg(u, 0.08, 0.15))

func _mag_home() -> void:
	for i in _mags.size():
		var m := _mags[i]
		if m == null:
			continue
		var g: Node3D = guns.get(WEAPONS[i].id)
		if g and m.get_parent() != g:
			m.reparent(g, false)
		m.transform = Transform3D.IDENTITY
	_mag_state = 0

## The arms, every frame: each shoulder behind and under the lens where the
## body would carry it, each palm on the rifle - the right round the pistol
## grip, the left under the handguard (or on the magazine, or at the handle,
## through a reload) - the hands turned to hold it and the elbows bent down
## and out. The rifle does not move for the arms.
func _arms(palm_local: Vector3, e: float, u: float) -> void:
	if not _arms_ok:
		return
	var g: Node3D = guns.get(WEAPONS[weapon_index].id)
	if g == null or not gun_root.visible:
		return
	var cam := vm_cam.global_transform
	var ski := _skel.global_transform.affine_inverse()
	var gx := g.global_transform
	var gb := ski.basis * gx.basis.orthonormalized()     # gun axes in skeleton space
	var pole_b := ski.basis * cam.basis
	# right: round the grip
	_arm_solve(1, ski * (cam * VM_SHOULDER_R_HIP.lerp(VM_SHOULDER_R_ADS, e)), ski * (gx * VM_GRIP),
		gb * _hand_frame(VM_HAND_R_ALONG, VM_HAND_R_THUMB), pole_b * VM_POLE_R)
	# left: cupped under the handguard; turned onto the magazine through the
	# middle of a reload
	var fl := _hand_frame(VM_HAND_L_ALONG, VM_HAND_L_THUMB)
	if reloading:
		var w := _seg(u, 0.0, 0.07) * (1.0 - _seg(u, 0.55, 0.64))
		if w > 0.0:
			fl = Basis(Quaternion(fl).slerp(Quaternion(_hand_frame(VM_HAND_MAG_ALONG, VM_HAND_MAG_THUMB)), w))
	_arm_solve(0, ski * (cam * VM_SHOULDER_L_HIP.lerp(VM_SHOULDER_L_ADS, e)), ski * (gx * palm_local),
		gb * fl, pole_b * VM_POLE_L)

## an orthonormal hand frame (along, thumb side, their cross) from two
## rough directions
static func _hand_frame(along: Vector3, thumb: Vector3) -> Basis:
	var a := along.normalized()
	var t := (thumb - a * thumb.dot(a)).normalized()
	return Basis(a, t, a.cross(t))

## Two-bone IK in skeleton space for one arm (side 0 left, 1 right): the hand
## takes frame (as a rest-relative turn) with its palm point on palm_t; the
## wrist lands where that puts it, the elbow toward pole. The shoulder slides
## along when the arm is short - it is behind the lens. The forearm takes half
## the wrist's twist, as a real one does.
func _arm_solve(side: int, s: Vector3, palm_t: Vector3, frame: Basis, pole_dir: Vector3) -> void:
	var i := side * 3
	var ur := _arm_rest[i]
	var fr := _arm_rest[i + 1]
	var hr := _arm_rest[i + 2]
	var hb := frame * _frame_rest[side].inverse() * hr.basis
	var w := palm_t - hb * _palm[side]
	var la := (fr.origin - ur.origin).length()
	var lb := (hr.origin - fr.origin).length()
	var st := w - s
	var d := st.length()
	var reach := (la + lb) * 0.99
	if d > reach:
		s += st * ((d - reach) / d)
		st = w - s
		d = st.length()
	if d < 0.0001:
		return
	var dir := st / d
	d = clampf(d, absf(la - lb) + 0.001, la + lb - 0.001)
	var pole := pole_dir - dir * pole_dir.dot(dir)
	if pole.length_squared() < 0.000001:
		return
	pole = pole.normalized()
	var x := (la * la - lb * lb + d * d) / (2.0 * d)
	var el := s + dir * x + pole * sqrt(maxf(la * la - x * x, 0.0))
	var ru := Basis(Quaternion((fr.origin - ur.origin).normalized(), (el - s).normalized()))
	var ub := ru * ur.basis
	var fd := (w - el).normalized()
	var fb := Basis(Quaternion(ru * (hr.origin - fr.origin).normalized(), fd)) * (ru * fr.basis)
	# half the wrist's twist into the forearm
	var ideal := hb * _rel_fh[side].inverse()
	var zc := fb.z - fd * fb.z.dot(fd)
	var zt := ideal.z - fd * ideal.z.dot(fd)
	if zc.length_squared() > 0.000001 and zt.length_squared() > 0.000001:
		fb = Basis(fd, zc.signed_angle_to(zt, fd) * 0.5) * fb
	_skel.set_bone_global_pose(_arm_bone[i], Transform3D(ub, s))
	_skel.set_bone_global_pose(_arm_bone[i + 1], Transform3D(fb, el))
	_skel.set_bone_global_pose(_arm_bone[i + 2], Transform3D(hb, w))
	if side == 0 and _hl:
		_hl.transform = Transform3D(hb, w)
