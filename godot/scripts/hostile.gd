## A hostile: one of six real people (Microsoft Rocketbox, MIT), chasing on
## the navmesh, grabbing at arm's length, and going down as a heavy physical
## body when killed. HP and speed scale with the wave exactly as spawnZombie did.
extends CharacterBody3D

const U := preload("res://scripts/util.gd")
const Fx := preload("res://scripts/fx.gd")

signal killed(h: Node)

# --- the people: assets/enemies/enemy_01..06.glb, 05 and 06 women (04-06
# are the player's picks). Their clips are in place; these are the speeds the
# feet travel at 1x and scale 1
const MODELS := ["res://assets/enemies/enemy_01.glb", "res://assets/enemies/enemy_02.glb",
	"res://assets/enemies/enemy_03.glb", "res://assets/enemies/enemy_04.glb",
	"res://assets/enemies/enemy_05.glb", "res://assets/enemies/enemy_06.glb"]
const WALK_V := [1.40, 1.40, 1.40, 1.40, 1.30, 1.30]
const RUN_V := [3.07, 3.07, 3.07, 3.07, 3.16, 3.16]
const HEAD_R := 0.12          # the head's hit sphere, metres at scale 1

var hp := 100.0
var max_hp := 100.0
var speed := 1.4
var state := "idle"          # idle | chase | attack | dead
var target: Node3D
var attack_cd := 0.0
var dead_t := 0.0
var model: Node3D
var anim: AnimationPlayer
var agent: NavigationAgent3D
var head_y := 1.5
# the web's variants (applyVariant): walker, brute, crawler, screamer
var variant := "walker"
var _scream_t := 2.0
# the web's LOT CROWD and FLEEING ZOMBIE BEHAVIOR
var flee := false            # a runner: bolts about screaming, never attacks
var lot := false             # claimed by the dormant crowd in the lot
var lot_box := AABB(Vector3(-23, 0, 16), Vector3(46, 4, 13.5))
var car_ref: Node3D
var _flee_to := Vector3.INF
var _flee_scr := 0.0
var _sc_t := 0.0
var _sc_dir := Vector3.ZERO
var _sc_spd := 0.0
var _sc_scr := 0.0
var _wander := 0.0
var _wr := 0.0
# ragdoll: physics bodies on the skeleton, made on the first death and reused
var skel: Skeleton3D
var rag_boost := 1.0         # a car hit throws them harder
const RAG := [
	# bone, the bone the segment runs to ("" = along its own axis for len),
	# len, radius (m), mass (kg), joint parent (""= nearest ancestor with a
	# body), joint, swing / max bend (deg), twist (deg). Parents first.
	["Bip01 Pelvis", "Bip01 Spine", 0.0, 0.15, 10.0, "", "", 0.0, 0.0],
	["Bip01 Spine1", "Bip01 Spine2", 0.0, 0.13, 9.0, "", "cone", 18.0, 10.0],
	["Bip01 Spine2", "Bip01 Neck", 0.0, 0.15, 12.0, "", "cone", 18.0, 10.0],
	["Bip01 Neck", "Bip01 Head", 0.0, 0.05, 3.0, "", "cone", 25.0, 20.0],
	["Bip01 Head", "", 0.24, 0.1, 5.0, "", "cone", 30.0, 25.0],
	["Bip01 L UpperArm", "Bip01 L Forearm", 0.0, 0.055, 2.3, "Bip01 Spine2", "cone", 80.0, 40.0],
	["Bip01 L Forearm", "Bip01 L Hand", 0.0, 0.045, 1.7, "", "elbow", 145.0, 0.0],
	["Bip01 R UpperArm", "Bip01 R Forearm", 0.0, 0.055, 2.3, "Bip01 Spine2", "cone", 80.0, 40.0],
	["Bip01 R Forearm", "Bip01 R Hand", 0.0, 0.045, 1.7, "", "elbow", 145.0, 0.0],
	["Bip01 L Thigh", "Bip01 L Calf", 0.0, 0.075, 8.5, "", "cone", 55.0, 15.0],
	["Bip01 L Calf", "Bip01 L Foot", 0.0, 0.055, 4.5, "", "knee", 140.0, 0.0],
	["Bip01 R Thigh", "Bip01 R Calf", 0.0, 0.075, 8.5, "", "cone", 55.0, 15.0],
	["Bip01 R Calf", "Bip01 R Foot", 0.0, 0.055, 4.5, "", "knee", 140.0, 0.0],
]
var _anim_now := ""
var _groan_cd := 0.0
# audio: one voice per person for their whole life, as the web build did
var voice: AudioStreamPlayer3D
var voice_idx := 1
var seen_player := false
var _step_t := 0.0
# locomotion: the clips blended and paced by how fast the body really moves
var tree: AnimationTree
var lean: Lean
var reach: Reach
var _model_i := 0
var _height := 1.8           # this model's standing height at scale 1
var _sc := 1.0               # its scale now (variant and build)
var _hunch := 0.0            # a standing forward pitch (the crawler's stoop)
var _cap: CapsuleShape3D
var _body_cs: CollisionShape3D
var _head_cs: CollisionShape3D
var _head_sh: SphereShape3D
var _head_bone := -1
var _last_pos := Vector3.ZERO
var _spd := 0.0
var _amp := 0.0              # the walk's weight over the idle
var _runw := 0.0             # the run's weight over the walk
var _stride := 1.0           # this person's stride against the clip's
var _idle_rate := 1.0
var _turn := 6.0             # rad/s they can swing round at
var _yaw_vel := 0.0
var _lean := Vector2.ZERO    # spine pitch (+ forward), roll (+ toward -X)
var _lean_v := Vector2.ZERO
var _look := 0.0
var _stag_t := 0.0
var _atk_t := -1.0
var _atk_fired := false
var _grab_w := 0.0           # arms coming up as they close on you

# the grab is timed so its peak lands when the damage does: a rear-back with
# the arms up, then the lunge
const WIND := 0.22
const STRIKE := 0.29
const P_IDLE := &"parameters/its/scale"
const P_WALK := &"parameters/wts/scale"
const P_RUN := &"parameters/rts/scale"
const P_WALKB := &"parameters/walkb/blend_amount"
const P_RUNB := &"parameters/runb/blend_amount"
const P_SEEK := &"parameters/seek/seek_request"

## Upper-body layer over the clips: a hit rocks the spine, the head follows
## what they are looking at. A modifier runs after the AnimationTree, so it
## bends the animated pose rather than fighting it. (survivor.gd uses it too.)
class Lean extends SkeletonModifier3D:
	var pitch := 0.0
	var roll := 0.0
	var yaw := 0.0
	var bones := PackedInt32Array()
	var share := PackedFloat32Array()
	var look := PackedFloat32Array()
	var ax := Vector3.RIGHT
	var ay := Vector3.UP
	var az := Vector3.BACK

	func setup(sk: Skeleton3D, top: Node3D, names: Array, sh: Array, lk: Array) -> void:
		for i in names.size():
			var b := sk.find_bone(names[i])
			if b >= 0:
				bones.append(b)
				share.append(sh[i])
				look.append(lk[i])
		# the model's axes in skeleton space (the armature is scaled and turned)
		var rel := Transform3D.IDENTITY
		var n: Node = sk
		while n != top and n is Node3D:
			rel = (n as Node3D).transform * rel
			n = n.get_parent()
		var inv := rel.basis.inverse()
		ax = (inv * Vector3.RIGHT).normalized()
		ay = (inv * Vector3.UP).normalized()
		az = (inv * Vector3.BACK).normalized()

	func _process_modification_with_delta(_delta: float) -> void:
		var sk := get_skeleton()
		if sk == null:
			return
		for i in bones.size():
			var q := Quaternion(ax, pitch * share[i]) * Quaternion(az, roll * share[i]) * Quaternion(ay, yaw * look[i])
			var gp := sk.get_bone_global_pose(bones[i])
			gp.basis = Basis(q) * gp.basis
			sk.set_bone_global_pose(bones[i], gp)

## The grab: there is no attack clip, so after the clips and the lean both
## arms are swung from wherever the clip has them toward straight ahead
## (the model faces +Z, its left is +X), elbows opening as they go. Runs last,
## so it also keeps the finished head pose for the head hitbox.
class Reach extends SkeletonModifier3D:
	var amount := 0.0          # 0 the clip's arms, 1 reaching straight out
	var raise := 0.0           # extra lift for the wind-up
	var ua := PackedInt32Array()
	var fa := PackedInt32Array()
	var hd := PackedInt32Array()
	var head := -1
	var head_pose := Transform3D.IDENTITY
	var has_head := false
	# the finished pose of the ragdoll bones (clip + lean + reach), for the
	# ragdoll to start from: the skeleton reverts modifier output after each
	# update, so reading it later gives the bare clip and a stooped or
	# lunging body snapped upright as it died
	var snap_ids := PackedInt32Array()
	var snap := {}

	func setup(sk: Skeleton3D) -> void:
		for s in ["L", "R"]:
			ua.append(sk.find_bone("Bip01 %s UpperArm" % s))
			fa.append(sk.find_bone("Bip01 %s Forearm" % s))
			hd.append(sk.find_bone("Bip01 %s Hand" % s))
		head = sk.find_bone("Bip01 Head")

	func _process_modification_with_delta(_delta: float) -> void:
		var sk := get_skeleton()
		if sk == null:
			return
		if amount > 0.002 and ua[0] >= 0 and ua[1] >= 0 and fa[0] >= 0 and fa[1] >= 0 and hd[0] >= 0 and hd[1] >= 0:
			for i in 2:
				var side := 1.0 if i == 0 else -1.0
				_aim(sk, ua[i], fa[i], Vector3(0.2 * side, 0.1 + raise, 1.0).normalized(), amount)
				_aim(sk, fa[i], hd[i], Vector3(0.06 * side, 0.05 + raise * 0.6, 1.0).normalized(), amount * 0.9)
		if head >= 0:
			head_pose = sk.get_bone_global_pose(head)
			has_head = true
		for b in snap_ids:
			snap[b] = sk.get_bone_global_pose(b)

	func _aim(sk: Skeleton3D, b: int, child: int, want: Vector3, w: float) -> void:
		var gp := sk.get_bone_global_pose(b)
		var cur := sk.get_bone_global_pose(child).origin - gp.origin
		if cur.length() < 0.001:
			return
		var from := cur.normalized()
		if from.dot(want) < -0.99:
			return
		var q := Quaternion.IDENTITY.slerp(Quaternion(from, want), clampf(w, 0.0, 1.0))
		gp.basis = Basis(q) * gp.basis
		sk.set_bone_global_pose(b, gp)

## --- the look: the models' own textures on one shared shader per source
## material, with each person's tint and roughness as instance uniforms, so a
## crowd of different people costs no extra materials. Subtle by design: a
## tint of a few percent either way, never darker than 0.86 of the texture.
const LOOK_SHADER := """
shader_type spatial;
render_mode %s;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 albedo_col : source_color = vec4(1.0);
uniform bool has_normal = false;
uniform float normal_scale = 1.0;
uniform float base_rough = 0.8;
uniform bool is_head = false;
instance uniform vec3 tint_body = vec3(1.0);
instance uniform vec3 tint_head = vec3(1.0);
instance uniform float rough_off = 0.0;
void fragment() {
	vec3 t = texture(albedo_tex, UV).rgb * albedo_col.rgb;
	ALBEDO = t * (is_head ? tint_head : tint_body);
	ROUGHNESS = clamp(base_rough + rough_off, 0.35, 1.0);
	SPECULAR = 0.5;
	if (has_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = normal_scale;
	}
}
"""

static var _hroot: AnimationNodeBlendTree
static var _rng: RandomNumberGenerator
static var _next_model := 0
static var _look_mats := {}      # source StandardMaterial3D -> ShaderMaterial
static var _look_shaders := {}   # render mode -> Shader
static var _rag_pm: PhysicsMaterial

func _ready() -> void:
	add_to_group("hostiles")
	collision_layer = 4
	collision_mask = 1 | 4
	# the body from the feet to the neck, and the head as its own sphere
	# riding the head bone, so a headshot is a hit on the head
	_body_cs = CollisionShape3D.new()
	_cap = CapsuleShape3D.new()
	_cap.radius = 0.35
	_cap.height = 1.5
	_body_cs.shape = _cap
	_body_cs.position.y = 0.75
	add_child(_body_cs)
	_head_cs = CollisionShape3D.new()
	_head_sh = SphereShape3D.new()
	_head_sh.radius = HEAD_R
	_head_cs.shape = _head_sh
	_head_cs.position.y = 1.7
	add_child(_head_cs)
	# the six people spread evenly across the pool
	_model_i = _next_model % MODELS.size()
	_next_model += 1
	var lib := U.glb(MODELS[_model_i])
	if lib == null:
		_model_i = 0
		lib = U.glb(MODELS[0])
	if lib:
		model = lib.duplicate() as Node3D
		add_child(model)
		var sks := model.find_children("*", "Skeleton3D", true, false)
		if not sks.is_empty():
			skel = sks[0] as Skeleton3D
		_height = 0.0
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			m.extra_cull_margin = 1.5   # skinned bounds are bind-pose
			if m.mesh:
				_height = maxf(_height, m.mesh.get_aabb().end.y)
		if _height < 1.2:
			_height = 1.8
		anim = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if anim:
			for n in ["idle", "walk", "run"]:
				if anim.has_animation(n):
					anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
			# the player only lends its clips; the tree blends and paces them
			anim.stop()
			tree = AnimationTree.new()
			anim.get_parent().add_child(tree)
			tree.anim_player = tree.get_path_to(anim)
			tree.root_node = tree.get_path_to(anim.get_node(anim.root_node))
			tree.tree_root = _tree_root()
			tree.active = true
		if skel:
			lean = Lean.new()
			skel.add_child(lean)
			lean.setup(skel, model, ["Bip01 Spine1", "Bip01 Spine2", "Bip01 Neck", "Bip01 Head"], [0.35, 0.35, 0.2, 0.1], [0.0, 0.15, 0.35, 0.5])
			reach = Reach.new()
			skel.add_child(reach)
			reach.setup(skel)
			for e in RAG:
				for nm in [e[0], e[1]]:
					if str(nm) != "":
						var bi := skel.find_bone(nm)
						if bi >= 0 and not reach.snap_ids.has(bi):
							reach.snap_ids.append(bi)
			_head_bone = skel.find_bone("Bip01 Head")
		dress(model)
	voice = AudioStreamPlayer3D.new()
	voice.unit_size = 4.0
	voice.max_distance = 22.0          # past ~20 m they are silent
	voice.position.y = 1.55
	add_child(voice)
	agent = NavigationAgent3D.new()
	agent.path_desired_distance = 0.9     # the navmesh sits ~0.5 m up; 3D distance
	agent.target_desired_distance = 1.0
	agent.radius = 0.4
	agent.height = 1.8
	add_child(agent)
	despawn()

## idle, walk and run: the walk's weight over the idle, the run's over that,
## each clip on its own time scale (the rate that keeps the planted foot
## still), and a seek to start every person at a different point in the
## cycle. Shared by every hostile and the town's pedestrians.
static func _tree_root() -> AnimationNodeBlendTree:
	if _hroot:
		return _hroot
	var bt := AnimationNodeBlendTree.new()
	for k in ["idle", "walk", "run"]:
		var a := AnimationNodeAnimation.new()
		a.animation = StringName(k)
		bt.add_node(StringName("a_" + k), a)
	bt.add_node(&"its", AnimationNodeTimeScale.new())
	bt.add_node(&"wts", AnimationNodeTimeScale.new())
	bt.add_node(&"rts", AnimationNodeTimeScale.new())
	bt.add_node(&"walkb", AnimationNodeBlend2.new())
	bt.add_node(&"runb", AnimationNodeBlend2.new())
	bt.add_node(&"seek", AnimationNodeTimeSeek.new())
	bt.connect_node(&"its", 0, &"a_idle")
	bt.connect_node(&"wts", 0, &"a_walk")
	bt.connect_node(&"rts", 0, &"a_run")
	bt.connect_node(&"walkb", 0, &"its")
	bt.connect_node(&"walkb", 1, &"wts")
	bt.connect_node(&"runb", 0, &"walkb")
	bt.connect_node(&"runb", 1, &"rts")
	bt.connect_node(&"seek", 0, &"runb")
	bt.connect_node(&"output", 0, &"seek")
	_hroot = bt
	return bt

## Put a model's textured surfaces on the shared look shader (the alpha-cut
## hair and lashes keep their own material). Used by the pedestrians too.
static func dress(m: Node3D) -> void:
	for n in m.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for si in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(si) as StandardMaterial3D
			if src == null or src.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or src.albedo_texture == null:
				continue
			mi.set_surface_override_material(si, _look_material(src))

static func _look_material(src: StandardMaterial3D) -> ShaderMaterial:
	if _look_mats.has(src):
		return _look_mats[src]
	var mode := "cull_disabled" if src.cull_mode == BaseMaterial3D.CULL_DISABLED else "cull_back"
	if not _look_shaders.has(mode):
		var sh := Shader.new()
		sh.code = LOOK_SHADER % mode
		_look_shaders[mode] = sh
	var sm := ShaderMaterial.new()
	sm.shader = _look_shaders[mode]
	sm.set_shader_parameter(&"albedo_tex", src.albedo_texture)
	sm.set_shader_parameter(&"albedo_col", src.albedo_color)
	sm.set_shader_parameter(&"base_rough", src.roughness)
	var nt: Texture2D = src.normal_texture if src.normal_enabled else null
	sm.set_shader_parameter(&"has_normal", nt != null)
	if nt:
		sm.set_shader_parameter(&"normal_tex", nt)
		sm.set_shader_parameter(&"normal_scale", src.normal_scale)
	sm.set_shader_parameter(&"is_head", src.resource_name.to_lower().contains("head"))
	_look_mats[src] = sm
	return sm

## one person's variety: clothes a few percent warmer, cooler, lighter or
## darker; skin a touch warmer or paler; the fabric a little more or less worn
static func vary(m: Node3D, rng: RandomNumberGenerator) -> void:
	var b := rng.randf_range(0.9, 1.06)
	var w := rng.randf_range(-0.05, 0.05)
	var body := Vector3(b * (1.0 + w + rng.randf_range(-0.03, 0.03)), b * (1.0 + rng.randf_range(-0.03, 0.03)), b * (1.0 - w + rng.randf_range(-0.03, 0.03)))
	var sb := rng.randf_range(0.95, 1.04)
	var sw := rng.randf_range(-0.035, 0.035)
	var head := Vector3(sb * (1.0 + sw), sb, sb * (1.0 - sw))
	var ro := rng.randf_range(-0.08, 0.1)
	for n in m.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		mi.set_instance_shader_parameter(&"tint_body", body)
		mi.set_instance_shader_parameter(&"tint_head", head)
		mi.set_instance_shader_parameter(&"rough_off", ro)

func _play(n: String, blend := 0.2, rate := 1.0) -> void:
	if anim == null or not anim.has_animation(n):
		return
	if tree and tree.active:
		tree.active = false          # a clip on its own (the fallback death)
	if _anim_now != n:
		anim.play(n, blend, rate)
		_anim_now = n
	else:
		anim.speed_scale = rate

func spawn(pos: Vector3, wave: int, tgt: Node3D) -> void:
	global_position = pos
	target = tgt
	max_hp = 55.0 + wave * 14.0
	hp = max_hp
	var runner := wave >= 4 and randf() < minf(0.08 * wave, 0.45)
	speed = randf_range(2.3, 3.0) if runner else randf_range(1.05, 1.7) + wave * 0.03
	_roll_variant(wave)
	state = "chase"
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT
	voice_idx = randi_range(1, 7)
	seen_player = false
	_groan_cd = randf_range(1.5, 6.0)
	collision_layer = 4
	rotation.y = randf() * TAU
	_anim_now = ""
	_restart_body()

## a fresh person: their clothes, gait and posture, the clip cycle at a
## random point so a crowd never steps in unison
func _restart_body() -> void:
	if _rng == null:
		_rng = RandomNumberGenerator.new()
		_rng.randomize()
	if model:
		vary(model, _rng)
	_stride = _rng.randf_range(0.94, 1.06)
	_idle_rate = _rng.randf_range(0.85, 1.15)
	_turn = 9.0 if variant == "screamer" else (4.5 if variant == "brute" else 6.5)
	_last_pos = global_position
	_spd = 0.0
	_amp = 0.0
	_runw = 0.0
	_yaw_vel = 0.0
	_lean = Vector2.ZERO
	_lean_v = Vector2.ZERO
	_look = 0.0
	_stag_t = 0.0
	_atk_t = -1.0
	_grab_w = 0.0
	if model:
		model.rotation = Vector3.ZERO
		model.position = Vector3.ZERO
	if lean:
		lean.active = true
		lean.pitch = 0.0
		lean.roll = 0.0
		lean.yaw = 0.0
	if reach:
		reach.active = true
		reach.amount = 0.0
		reach.raise = 0.0
	if tree:
		tree.active = true
		tree.set(P_WALKB, 0.0)
		tree.set(P_RUNB, 0.0)
		tree.set(P_SEEK, _rng.randf() * 3.0)

## a person's size: the model, the body capsule to the neck, the head sphere
func _apply_scale(s: float) -> void:
	_sc = s
	if model:
		model.scale = Vector3.ONE * s
	var stoop := 0.78 if variant == "crawler" else 0.84
	_cap.height = maxf(0.9, _height * s * stoop)
	_body_cs.position.y = _cap.height * 0.5
	_head_sh.radius = HEAD_R * s
	head_y = _height * s * (0.8 if variant == "crawler" else 0.9)
	_head_cs.position = Vector3(0, head_y, 0)

## weighted by wave, as the web rolled them: brutes from wave 2, screamers
## from wave 3, crawlers any time
func _roll_variant(wave: int) -> void:
	var w := maxi(1, wave)
	var pb := minf(0.16, 0.08 + (w - 2) * 0.015) if w >= 2 else 0.0
	var pc := 0.12
	var ps := 0.10 if w >= 3 else 0.0
	var r := randf()
	variant = "brute" if r < pb else ("crawler" if r < pb + pc else ("screamer" if r < pb + pc + ps else "walker"))
	# no two the same height or build
	var s := randf_range(0.95, 1.05)
	_hunch = randf_range(0.0, 0.06)
	match variant:
		"brute":          # big, slow, soaks a magazine
			max_hp *= 2.4
			speed *= 0.75
			s *= 1.1
		"crawler":        # low and quick, dies easily: stooped right over
			max_hp *= 0.5
			speed *= 1.15
			s *= 0.95
			_hunch = randf_range(0.7, 0.85)
		"screamer":       # fast, and shrieks as it comes
			max_hp *= 0.75
			speed *= 1.9
			_scream_t = randf_range(1.0, 3.0)
	hp = max_hp
	_apply_scale(s)

## their own shout (the voice they were given), a reaction line, or a scream
func _say(file: String, vol_db := 0.0, pitch := 1.0) -> void:
	var st := Game.file(file)
	if st == null or not visible:
		return
	voice.stream = st
	voice.volume_db = vol_db
	voice.pitch_scale = pitch
	voice.play()

## lotCrowdInit: one of the onlookers standing about the lot before you
## arrive - an 80 HP walker at the round's strength, idling, watching the car
func lot_idle(pos: Vector3, tgt: Node3D, car_node: Node3D, box: AABB, rnd: int) -> void:
	spawn(pos, 3, tgt)
	state = "lotidle"
	lot = true
	flee = false
	variant = "walker"
	_hunch = randf_range(0.0, 0.06)
	_apply_scale(randf_range(0.95, 1.05))
	var r := rnd - 1
	max_hp = 80.0 * (1.0 + r * 0.22)
	hp = max_hp
	speed = randf_range(0.9, 1.5) * (1.0 + r * 0.09)
	car_ref = car_node
	lot_box = box
	_wander = randf() * TAU
	_wr = randf_range(-0.45, 0.45)
	_sc_t = 0.0
	_turn = 6.5

## lotCrowdScatter: the car pulls in and they panic away from it for 2.2 s
func scatter_from(p: Vector3) -> void:
	if state != "lotidle":
		return
	var d := global_position - p
	d.y = 0.0
	d = d.normalized() + Vector3(randf_range(-0.3, 0.3), 0, randf_range(-0.3, 0.3))
	_sc_dir = d.normalized()
	_sc_spd = randf_range(3.4, 4.8)
	_sc_t = 2.2
	_sc_scr = randf_range(0.0, 0.3)

## the crowd wakes: two in five run, the rest come for you
func wake() -> void:
	if state != "lotidle":
		return
	state = "chase"
	flee = randf() < 0.4
	attack_cd = randf_range(0.2, 0.9)
	seen_player = true
	_flee_to = Vector3.INF
	if not flee and Game.may_react(0.3):
		_say("hostile-v%d.mp3" % randi_range(1, 6), -1.0, randf_range(0.95, 1.05))   # "I see him"

func _lot_step(dt: float) -> void:
	velocity = Vector3.ZERO
	_grab_w = 0.0
	if _sc_t > 0.0:
		_sc_t -= dt
		var p := global_position + _sc_dir * _sc_spd * dt
		p.x = clampf(p.x, lot_box.position.x, lot_box.end.x)
		p.z = clampf(p.z, lot_box.position.z, lot_box.end.z)
		global_position = Vector3(p.x, global_position.y, p.z)
		_sc_scr -= dt
		if _sc_scr <= 0.0:
			_sc_scr = randf_range(0.7, 1.6)
			if Game.may_shout(0.25):
				_say("sfx-enemy-scream.mp3", -6.0, randf_range(0.95, 1.12))
		# panicking: they look back at the car they are running from
		_animate(dt, atan2(_sc_dir.x, _sc_dir.z), 9.0, car_ref.global_position if car_ref else global_position - _sc_dir)
		return
	# standing about: the player if close, otherwise the car, with a slow sway
	var look: Vector3 = target.global_position if target else global_position
	if target and global_position.distance_to(target.global_position) >= 13.0 and car_ref:
		look = car_ref.global_position
	_wander += _wr * dt
	var want := atan2(look.x - global_position.x, look.z - global_position.z) + sin(_wander) * 0.55
	_animate(dt, want, 1.6, look)

## a runner: away from you to a spot eight metres off, a new one when it
## gets there, screaming now and then; never attacks
func _flee_step(dt: float) -> void:
	_grab_w = 0.0
	var pp: Vector3 = target.global_position
	if _flee_to == Vector3.INF or Vector2(_flee_to.x - global_position.x, _flee_to.z - global_position.z).length() < 0.8:
		var away := global_position - pp
		away.y = 0.0
		away = away.normalized() if away.length() > 0.01 else Vector3.FORWARD
		_flee_to = pp + away * 8.0 + Vector3(randf_range(-2.5, 2.5), 0, randf_range(-2.5, 2.5))
		_flee_to.x = clampf(_flee_to.x, lot_box.position.x + 0.5, lot_box.end.x - 0.5)
		_flee_to.z = clampf(_flee_to.z, lot_box.position.z + 0.5, lot_box.end.z - 0.5)
		_flee_scr = randf_range(0.5, 2.0)
	_flee_scr -= dt
	if _flee_scr <= 0.0:
		_flee_scr = randf_range(2.5, 6.0)
		if Game.may_shout(0.3):
			_say("sfx-enemy-scream.mp3", -3.0, randf_range(0.95, 1.1))
	var d := _flee_to - global_position
	d.y = 0.0
	var dir := d.normalized() if d.length() > 0.01 else Vector3.ZERO
	for o in get_tree().get_nodes_in_group("hostiles"):
		if o == self or not o.is_active():
			continue
		var off: Vector3 = global_position - (o as Node3D).global_position
		off.y = 0.0
		var od := off.length()
		if od < 0.7 and od > 0.001:
			dir += off / od * 0.9 * dt
	velocity.x = dir.x * speed * 1.4
	velocity.z = dir.z * speed * 1.4
	velocity.y = velocity.y - 18.0 * dt if not is_on_floor() else 0.0
	move_and_slide()
	# running away, glancing back over the shoulder at you
	_animate(dt, atan2(dir.x, dir.z) if dir.length() > 0.01 else rotation.y, 7.0, pp)

## A ragdoll that does not care about the rig's scale: world-space capsules
## on the segments (made once per hostile and reused), joints between them,
## and every physics frame the bones are posed from the bodies with the scale
## stripped. Knees and elbows are hinges that only bend the way they bend.
var _rag: Array = []          # [bone index, RigidBody3D, body->bone transform, RAG row]
var _rag_joints: Array = []
var _rag_rbs: Array = []      # one per RAG row, null until first needed
var _rag_head: RigidBody3D
var _rag_pelvis: RigidBody3D
var _rag_chest: RigidBody3D
var _rag_vy := Vector2.ZERO   # last vertical speed of pelvis, chest
var _thuds := 0
var _thud_cd := 0.0
var _pooled := false

func _rag_body(k: int) -> RigidBody3D:
	if _rag_rbs.size() < RAG.size():
		_rag_rbs.resize(RAG.size())
	if _rag_rbs[k] != null:
		return _rag_rbs[k]
	if _rag_pm == null:
		_rag_pm = PhysicsMaterial.new()
		_rag_pm.friction = 1.0
		_rag_pm.rough = true           # the grippier of the two surfaces wins
		_rag_pm.bounce = 0.0
	var rb := RigidBody3D.new()
	rb.name = "rag_" + str(RAG[k][0]).replace(" ", "_")
	rb.top_level = true
	rb.mass = RAG[k][4]
	rb.linear_damp = 0.3
	rb.angular_damp = 1.8
	rb.continuous_cd = true
	rb.collision_layer = 64          # bodies meet the world, not each other
	rb.collision_mask = 1 | 8 | 32         # the world, the car, the small props
	rb.physics_material_override = _rag_pm
	var cs := CollisionShape3D.new()
	cs.shape = CapsuleShape3D.new()
	rb.add_child(cs)
	rb.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(rb)
	_rag_rbs[k] = rb
	return rb

static func _basis_along(axis: Vector3, hint: Vector3) -> Basis:
	# a right-handed basis whose X runs along axis
	var x := axis.normalized()
	var y := hint - x * hint.dot(x)
	if y.length() < 0.01:
		y = Vector3.UP - x * x.y
		if y.length() < 0.01:
			y = Vector3.FORWARD
	y = y.normalized()
	return Basis(x, y, x.cross(y))

## the bone's pose as last drawn - modifiers included - when the reach
## modifier has it, else the skeleton's own
func _posed(bi: int) -> Transform3D:
	if reach and reach.snap.has(bi):
		return reach.snap[bi]
	return skel.get_bone_global_pose(bi)

func _ragdoll(dir: Vector3, at: Vector3, dmg: float, headshot: bool) -> bool:
	if skel == null:
		return false
	_rag_clear()
	var sg := skel.global_transform
	var s := sg.basis.get_scale().x
	var by_bone := {}
	for k in RAG.size():
		var e: Array = RAG[k]
		var bi := skel.find_bone(e[0])
		if bi < 0:
			continue
		var bone_w: Transform3D = sg * _posed(bi)
		bone_w.basis = bone_w.basis.orthonormalized()
		var a: Vector3 = bone_w.origin
		var b: Vector3
		if e[1] != "":
			var ci := skel.find_bone(e[1])
			if ci < 0:
				continue
			b = (sg * _posed(ci)).origin
		else:
			b = a + bone_w.basis.x * float(e[2]) * s      # Biped bones run along X
		var seg := b - a
		var ln := seg.length()
		if ln < 0.02:
			continue
		var rb := _rag_body(k)
		var cap := (rb.get_child(0) as CollisionShape3D).shape as CapsuleShape3D
		cap.radius = float(e[3]) * s
		cap.height = maxf(ln, cap.radius * 2.0 + 0.001)
		rb.process_mode = Node.PROCESS_MODE_INHERIT
		# the capsule's axis (Y) along the segment, centred on it
		var yax := seg / ln
		var ref := Vector3.FORWARD if absf(yax.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
		var xax := ref.cross(yax).normalized()
		var zax := xax.cross(yax).normalized()
		rb.global_transform = Transform3D(Basis(xax, yax, zax), (a + b) * 0.5)
		rb.linear_velocity = Vector3.ZERO
		rb.angular_velocity = Vector3.ZERO
		rb.sleeping = false
		_rag.append([bi, rb, rb.global_transform.affine_inverse() * bone_w, k])
		by_bone[bi] = rb
		if e[0] == "Bip01 Head":
			_rag_head = rb
		elif e[0] == "Bip01 Pelvis":
			_rag_pelvis = rb
		elif e[0] == "Bip01 Spine2":
			_rag_chest = rb
	if _rag.is_empty():
		return false
	# joints: each body to its named parent or the nearest ancestor with one,
	# at the bone's head
	var lateral := sg.basis.x.normalized()     # the model's +X (its left)
	for r in _rag:
		var bi: int = r[0]
		var rb: RigidBody3D = r[1]
		var e: Array = RAG[r[3]]
		if e[6] == "":
			continue
		var p := -1
		if e[5] != "":
			p = skel.find_bone(e[5])
		else:
			p = skel.get_bone_parent(bi)
			while p >= 0 and not by_bone.has(p):
				p = skel.get_bone_parent(p)
		if p < 0 or not by_bone.has(p):
			continue
		var prb: RigidBody3D = by_bone[p]
		var pos := (sg * _posed(bi)).origin
		var cdir := rb.global_basis.y.normalized()
		var j: Joint3D
		var jb: Basis
		if e[6] == "cone":
			var cj := ConeTwistJoint3D.new()
			cj.set_param(ConeTwistJoint3D.PARAM_SWING_SPAN, deg_to_rad(e[7]))
			cj.set_param(ConeTwistJoint3D.PARAM_TWIST_SPAN, deg_to_rad(e[8]))
			jb = _basis_along(cdir, lateral)       # twist runs along the limb
			j = cj
		else:
			# a hinge about the joint's own sideways axis. Flexion is + about
			# `axis`: a knee folds the shin back, an elbow brings the hand up.
			# Jolt's hinge angle is + about -Z, so Z = -axis; the limits are
			# relative to the pose it dies in, so they are offset by the bend
			# it already has
			var pdir := prb.global_basis.y.normalized()
			var axis := lateral - pdir * lateral.dot(pdir)
			axis = axis.normalized() if axis.length() > 0.01 else lateral
			if e[6] == "elbow":
				axis = -axis
			var cur := atan2(pdir.cross(cdir).dot(axis), pdir.dot(cdir))
			var hj := HingeJoint3D.new()
			hj.set_flag(HingeJoint3D.FLAG_USE_LIMIT, true)
			hj.set_param(HingeJoint3D.PARAM_LIMIT_LOWER, minf(-cur, 0.0))
			hj.set_param(HingeJoint3D.PARAM_LIMIT_UPPER, maxf(deg_to_rad(e[7]) - cur, 0.0))
			var z := -axis
			var x := pdir - z * pdir.dot(z)
			x = x.normalized() if x.length() > 0.01 else cdir
			jb = Basis(x, z.cross(x), z)
			j = hj
		j.top_level = true
		add_child(j)
		j.global_transform = Transform3D(jb, pos)
		j.node_a = prb.get_path()
		j.node_b = rb.get_path()
		_rag_joints.append(j)
	if anim:
		anim.active = false
	if tree:
		tree.active = false
	if lean:
		lean.active = false
	if reach:
		reach.active = false
	# the whole body carries its own momentum plus a share of the round's;
	# a car throws all of it along the bonnet and up
	var dn := dir.normalized() if dir.length() > 0.001 else -global_basis.z
	var flat := Vector3(dn.x, 0, dn.z)
	flat = flat.normalized() if flat.length() > 0.001 else -global_basis.z
	var k := clampf(dmg / 38.0, 0.6, 2.6)
	var carry := global_basis.z.normalized() * _spd * 0.8
	carry.y = 0.0
	var body_v := carry + flat * 0.35 * k
	if rag_boost > 1.0:
		body_v = carry * 0.3 + flat * 2.2 * rag_boost + Vector3.UP * (0.6 + 0.9 * (rag_boost - 1.0))
	for r in _rag:
		(r[1] as RigidBody3D).linear_velocity = body_v
	# the round goes into the part it hit: a headshot snaps the head back
	var part: RigidBody3D = _rag_head if headshot and _rag_head else _nearest_part(at)
	if part:
		var imp := dn * (8.0 + 6.0 * k)
		if headshot:
			imp = dn * (12.0 + 6.0 * k) + Vector3.UP * 1.5
		if rag_boost > 1.0:
			imp = flat * 14.0 * rag_boost + Vector3.UP * 4.0 * rag_boost
		part.apply_impulse(imp, (at - part.global_position).limit_length(0.1))
	_rag_vy = Vector2.ZERO
	_thuds = 0
	_thud_cd = 0.0
	return true

## the body whose capsule the point is nearest (the hit is on the hitbox, not
## the mesh, so it is the closest segment rather than a contact)
func _nearest_part(at: Vector3) -> RigidBody3D:
	var best := INF
	var out: RigidBody3D = null
	for r in _rag:
		var rb: RigidBody3D = r[1]
		var cap := (rb.get_child(0) as CollisionShape3D).shape as CapsuleShape3D
		var half := maxf(cap.height * 0.5 - cap.radius, 0.0)
		var ax := rb.global_basis.y.normalized()
		var t := clampf((at - rb.global_position).dot(ax), -half, half)
		var d := at.distance_to(rb.global_position + ax * t) - cap.radius
		if d < best:
			best = d
			out = rb
	return out

## pose the bones from the bodies, parents first, scale stripped
func _rag_pose() -> void:
	var inv := skel.global_transform.affine_inverse()
	for r in _rag:
		var rb: RigidBody3D = r[1]
		var pose: Transform3D = inv * (rb.global_transform * (r[2] as Transform3D))
		pose.basis = pose.basis.orthonormalized()
		skel.set_bone_global_pose(r[0], pose)

func _rag_clear() -> void:
	for j in _rag_joints:
		if is_instance_valid(j):
			(j as Node).queue_free()
	_rag_joints.clear()
	for rb in _rag_rbs:
		if rb != null and is_instance_valid(rb):
			(rb as RigidBody3D).process_mode = Node.PROCESS_MODE_DISABLED
	_rag.clear()
	_rag_head = null
	_rag_pelvis = null
	_rag_chest = null

## the corpse: the body lands with a thud when the hips or chest hit the
## floor, and once it lies still the blood spreads out under it
func _dead_step(dt: float) -> void:
	if _rag.is_empty():
		if not _pooled and dead_t > 1.2:
			_pooled = true
			Fx.blood_pool(global_position + Vector3(0, 0.3, 0), randf_range(0.6, 1.1) * _sc)
		return
	_rag_pose()
	_thud_cd -= dt
	var vy := Vector2(_rag_pelvis.linear_velocity.y if _rag_pelvis else 0.0, _rag_chest.linear_velocity.y if _rag_chest else 0.0)
	for i in 2:
		if _thuds < 3 and _thud_cd <= 0.0 and _rag_vy[i] < -1.3 and vy[i] > _rag_vy[i] + 1.0:
			_thuds += 1
			_thud_cd = 0.25
			var rb: RigidBody3D = _rag_pelvis if i == 0 else _rag_chest
			var hard := clampf(-_rag_vy[i] / 5.0, 0.0, 1.0)
			Game.play_file_at("sfx-body-drop.mp3", rb.global_position, lerpf(-9.0, -1.0, hard) - _thuds * 2.0, randf_range(0.88, 1.02), 30.0)
	_rag_vy = vy
	if not _pooled and _rag_chest and _rag_pelvis and dead_t > 0.7:
		if (_rag_chest.linear_velocity.length() < 0.25 and _rag_pelvis.linear_velocity.length() < 0.25) or dead_t > 3.0:
			_pooled = true
			Fx.blood_pool((_rag_chest.global_position + _rag_pelvis.global_position) * 0.5, randf_range(0.6, 1.1) * _sc)

func despawn() -> void:
	_rag_clear()
	if skel:
		skel.reset_bone_poses()
	if anim:
		anim.active = true
		anim.stop()
	_anim_now = ""
	if tree:
		tree.active = true
	if model:
		model.position = Vector3.ZERO
	rag_boost = 1.0
	lot = false
	flee = false
	state = "idle"
	visible = false
	collision_layer = 0
	velocity = Vector3.ZERO
	global_position = Vector3(0, -50, 0)
	process_mode = Node.PROCESS_MODE_DISABLED

func is_active() -> bool:
	return state == "chase" or state == "attack"

## the middle of the head, off the head bone as it is drawn (after the lean
## and the grab), in world space
func head_center() -> Vector3:
	if skel == null or _head_bone < 0:
		return global_position + Vector3.UP * head_y
	var hp_s: Transform3D = reach.head_pose if reach and reach.has_head else skel.get_bone_global_pose(_head_bone)
	var t := skel.global_transform * hp_s
	# Biped: the head bone's X runs up through the crown, its Y out the face
	return t.origin + (t.basis.x.normalized() * 0.1 + t.basis.y.normalized() * 0.02) * _sc

func is_head(p: Vector3) -> bool:
	return p.distance_to(head_center()) < (HEAD_R + 0.05) * _sc

func _sync_head() -> void:
	if skel:
		_head_cs.position = to_local(head_center())

## returns true if this hit killed it
func take_hit(dmg: float, at: Vector3, dir: Vector3) -> bool:
	if state == "dead" or state == "idle":
		return false
	var head := is_head(at)
	hp -= dmg
	# a wet thud where the round lands, and they yell - gated, so a volley
	# into a crowd is not eight people shouting at once
	Game.play_file_at("sfx-body-drop.mp3", at, -14.0, randf_range(1.6, 1.9), 25.0)
	if hp > 0.0 and Game.may_react():
		_say("hostile-v%d.mp3" % randi_range(1, 6), -2.0, randf_range(0.95, 1.05))
	Fx.blood(at, dir)          # spray, drops, and a splat on the wall or floor behind
	if head:
		Fx.exit_wound(at, dir)
	if hp <= 0.0:
		state = "dead"
		dead_t = 0.0
		_pooled = false
		collision_layer = 0
		velocity = Vector3.ZERO
		if lean:
			lean.active = false
		if reach:
			reach.active = false
		var rag := _ragdoll(dir, at, dmg, head)
		if not rag:
			_play("death", 0.1)
		if randf() < 0.6:
			_say("kill-voice.mp3", -4.0, randf_range(0.85, 1.1))
		if not rag:
			# no bodies to land: the thud on a timer, as before
			get_tree().create_timer(0.55).timeout.connect(func():
				if is_instance_valid(self) and visible: Game.play_file_at("sfx-body-drop.mp3", global_position + Vector3(0, 0.3, 0), -3.0, randf_range(0.9, 1.05), 30.0))
		killed.emit(self)
		return true
	# a hit staggers it back a touch, rocks the spine away from the round and
	# checks its stride for a moment
	var push := Vector3(dir.x, 0, dir.z) * 0.08
	global_position += push
	_last_pos += push                # a shove is not a step
	var dn := dir.normalized() if dir.length() > 0.001 else -global_basis.z
	var loc := global_basis.inverse() * dn
	var k := clampf(dmg / 35.0, 0.5, 1.4) * 4.5
	if head:
		k *= 1.4
	_lean_v += Vector2(loc.z, -loc.x) * k
	_stag_t = 0.3
	return false

func _physics_process(dt: float) -> void:
	if state == "dead":
		dead_t += dt
		_dead_step(dt)
		if dead_t > 8.0:
			despawn()
		return
	if state == "idle" or target == null:
		return
	if state == "lotidle":
		_lot_step(dt)
		return
	if flee:
		_flee_step(dt)
		return
	attack_cd = maxf(0.0, attack_cd - dt)
	_groan_cd -= dt
	if variant == "screamer":
		_scream_t -= dt
		if _scream_t <= 0.0:
			_scream_t = randf_range(2.5, 5.5)
			if target.global_position.distance_to(global_position) < 15.0 and Game.may_shout(0.4):
				_say("sfx-enemy-scream.mp3", -1.0, randf_range(0.95, 1.08))
	var to := target.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	# the first time they clock you they scream, then they shout as they come
	if not seen_player and dist < 18.0:
		seen_player = true
		if Game.may_react(0.4):
			_say("sfx-enemy-scream.mp3" if randf() < 0.45 else "hostile-v%d.mp3" % randi_range(1, 6), -1.0, randf_range(0.92, 1.06))
	elif _groan_cd <= 0.0:
		_groan_cd = randf_range(3.5, 8.0)
		if dist < 20.0 and Game.may_shout():
			_say("hostile-%d.mp3" % voice_idx, -3.0, randf_range(0.96, 1.04))
	# the grab is timed so its peak lands when the damage does: rear back,
	# then lunge. It starts early enough to read on the way in, and a target
	# that backs off before the lunge leaves them to reset
	_stag_t = maxf(0.0, _stag_t - dt)
	if _atk_t < 0.0 and attack_cd <= WIND + STRIKE and dist < 1.35 + maxf(_spd, 0.4) * (WIND + STRIKE):
		_atk_t = 0.0
		_atk_fired = false
	elif _atk_t >= 0.0 and not _atk_fired and dist > 2.8:
		_atk_t = -1.0
	# the arms come up as they close in
	_grab_w = smoothstep(3.4, 1.5, dist) * 0.45
	if dist < 1.35:
		state = "attack"
		velocity.x = 0.0
		velocity.z = 0.0
		if attack_cd <= 0.0:
			attack_cd = 1.1
			if Game.may_shout(0.3):
				_say("hostile-%d.mp3" % voice_idx, 0.0, randf_range(1.0, 1.1))
			if target.has_method("take_damage"):
				target.call("take_damage", 18.0, global_position)
	else:
		state = "chase"
		var next := target.global_position
		agent.target_position = target.global_position
		if not agent.is_navigation_finished():
			var np := agent.get_next_path_position()
			if Vector2(np.x - global_position.x, np.z - global_position.z).length() > 0.05:
				next = np
		var d := next - global_position
		d.y = 0.0
		d = d.normalized() if d.length() > 0.01 else to.normalized()
		# a round checks them for a beat
		var sp := speed * (1.0 - 0.65 * clampf(_stag_t / 0.3, 0.0, 1.0))
		velocity.x = d.x * sp
		velocity.z = d.z * sp
		# their feet, quiet, and only when close enough to matter
		_step_t -= dt * speed
		if _step_t <= 0.0:
			_step_t = 0.75
			if dist < 12.0:
				var inside := absf(global_position.x) < 22.0 and absf(global_position.z) < 15.0
				Game.play_at("step_tile" if inside else "step_concrete", global_position, -20.0, randf_range(0.85, 0.95))
	if not is_on_floor():
		velocity.y -= 18.0 * dt
	else:
		velocity.y = 0.0
	move_and_slide()
	# face where they are going (round a shelf end, not sideways at you),
	# squaring up to you once close
	var want := rotation.y
	if state == "attack" or dist < 2.5:
		if dist > 0.01:
			want = atan2(to.x, to.z)
	elif Vector2(velocity.x, velocity.z).length() > 0.1:
		want = atan2(velocity.x, velocity.z)
	elif dist > 0.01:
		want = atan2(to.x, to.z)
	_animate(dt, want, 9.0, target.global_position)

## Once per physics frame, after the body has moved: turn toward want_yaw at
## a limited rate (ease is how briskly), blend and pace idle / walk / run off
## the distance actually covered, drive the spine and head layer and the
## grab, and move the head hitbox onto the head.
func _animate(dt: float, want_yaw: float, ease_k: float, look_at_p: Vector3) -> void:
	var mv := global_position - _last_pos
	_last_pos = global_position
	mv.y = 0.0
	var v := minf(mv.length() / maxf(dt, 0.0001), 9.0)
	_spd = lerpf(_spd, v, clampf(dt * 10.0, 0.0, 1.0))
	var diff := wrapf(want_yaw - rotation.y, -PI, PI)
	var step := clampf(diff * clampf(dt * ease_k, 0.0, 1.0), -_turn * dt, _turn * dt)
	rotation.y = wrapf(rotation.y + step, -PI, PI)
	_yaw_vel = lerpf(_yaw_vel, step / maxf(dt, 0.0001), clampf(dt * 8.0, 0.0, 1.0))
	if tree:
		# each clip at the rate its feet travel at this speed and size: walk
		# in over the idle by ~0.8 m/s, run in over the walk past ~1.1x walk
		var wv: float = WALK_V[_model_i] * _sc * _stride
		var rv: float = RUN_V[_model_i] * _sc * _stride
		var wa := 0.0 if _spd < 0.06 else clampf(_spd / (wv * 0.55), 0.0, 1.0)
		var ra := clampf((_spd - wv * 1.1) / maxf(rv * 0.8 - wv * 1.1, 0.1), 0.0, 1.0)
		_amp = lerpf(_amp, wa, clampf(dt * 8.0, 0.0, 1.0))
		_runw = lerpf(_runw, ra, clampf(dt * 6.0, 0.0, 1.0))
		tree.set(P_WALKB, _amp)
		tree.set(P_RUNB, _runw)
		tree.set(P_WALK, clampf(_spd / wv, 0.3, 2.0) if _amp > 0.02 else 1.0)
		tree.set(P_RUN, clampf(_spd / rv, 0.5, 1.8) if _runw > 0.02 else 1.0)
		tree.set(P_IDLE, _idle_rate)
	# the grab: rear back with the arms up for WIND, then reach and lunge
	var atk_pitch := 0.0
	var reach_w := _grab_w
	var raise := 0.0
	var lunge := 0.0
	if _atk_t >= 0.0:
		_atk_t += dt
		if not _atk_fired and _atk_t >= WIND:
			_atk_fired = true
		if _atk_t < WIND:
			var kw := smoothstep(0.0, WIND, _atk_t)
			atk_pitch = -0.2 * kw
			reach_w = maxf(reach_w, 0.6 * kw)
			raise = 0.45 * kw
			lunge = -0.05 * kw
		else:
			var kk := clampf((_atk_t - WIND) / 0.58, 0.0, 1.0)
			var bell := sin(kk * PI)
			atk_pitch = lerpf(-0.2, 0.0, clampf(kk * 4.0, 0.0, 1.0)) + 0.26 * bell
			reach_w = maxf(reach_w, (0.6 + 0.4 * clampf(kk * 3.0, 0.0, 1.0)) * (1.0 - smoothstep(0.6, 1.0, kk)))
			raise = 0.45 * (1.0 - clampf(kk * 3.0, 0.0, 1.0))
			lunge = lerpf(-0.05, 0.0, clampf(kk * 4.0, 0.0, 1.0)) + 0.26 * bell
		if _atk_t > WIND + 0.62:
			_atk_t = -1.0
	if model:
		model.position.z = lunge * _sc
	if reach:
		reach.amount = lerpf(reach.amount, reach_w, clampf(dt * 14.0, 0.0, 1.0))
		reach.raise = raise
	if lean:
		# spine: the stoop, into the run, banked into turns, the hit spring,
		# the wind-up and the lunge
		var tgt := Vector2(_hunch + clampf(_spd * 0.03, 0.0, 0.14) + atk_pitch, clampf(-_yaw_vel * _spd * 0.02, -0.16, 0.16))
		_lean_v += ((tgt - _lean) * 140.0 - _lean_v * 17.0) * dt
		_lean += _lean_v * dt
		_lean = _lean.clamp(Vector2(-0.6, -0.5), Vector2(1.15, 0.5))
		# the head turns toward what they are watching, within a neck's reach
		var lk := clampf(wrapf(atan2(look_at_p.x - global_position.x, look_at_p.z - global_position.z) - rotation.y, -PI, PI), -0.9, 0.9)
		_look = lerpf(_look, lk, clampf(dt * 5.0, 0.0, 1.0))
		lean.pitch = _lean.x
		lean.roll = _lean.y
		lean.yaw = _look
	_sync_head()
