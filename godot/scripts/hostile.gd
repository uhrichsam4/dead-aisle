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
var _atk_side := 1.0         # +1 the left arm (the model's +X), -1 the right
var _atk_grab := false       # both hands at once
var _near_w := 0.0           # hands drifting forward in the last metre and a half
var loco: Loco
var _runner := false         # rolled as a runner: sprints on run_fast
var _idle_t := 0.0           # until the idle is re-rolled
var _gait_key := -1          # what _gait() last chose for (hurt, sprint, lot, brute)
var _wvar := 0               # which take of the walk and run clips (0 base, 1 _2, 2 _3)
var _rvar := 0
var _moving := false         # walking now: the next stop starts a fresh idle
var _atk_tempo := 1.0        # this swing's speed, so no two are quite alike
var _atk_high := 1.45        # and where it is aimed: face or chest
var _vel := Vector3.ZERO     # how the body is really moving (for the ragdoll)
# hit reactions: rotation springs (model space, radians) on the torso, the
# head and each shoulder, a dip for a stumble, and a shove along the round
var _ft := Vector3.ZERO
var _ftv := Vector3.ZERO
var _fh := Vector3.ZERO
var _fhv := Vector3.ZERO
var _fl := Vector3.ZERO
var _flv := Vector3.ZERO
var _fr := Vector3.ZERO
var _frv := Vector3.ZERO
var _dip := 0.0
var _dip_v := 0.0
var _knock := Vector3.ZERO   # world m/s, bleeds off in a few tenths
var _leg_hurt := false       # a leg hit: they limp from then on
var _limp_side := 0.0
var _fall := 0.0             # no ragdoll: which way the fallback topple goes
# a death clip's first moments before the ragdoll takes over
var _dying := 0.0
var _die_dir := Vector3.ZERO
var _die_at := Vector3.ZERO
var _die_dmg := 0.0
# the attack clip in play (else the procedural strike), and when it lands
var _atk_clip := false
var _atk_len := 0.0
var _atk_contact := CONTACT
# DOWNED: shot to the ground but alive - crawling at you or writhing until
# they are finished off or bleed out. Either on the clips (fall_prone, then
# crawl / writhe) or, without them, on the ragdoll driven by hand
var _down_t := 0.0
var _down_life := 0.0
var _down_crawl := false
var _down_clip := false
var _fall_len := 0.0
var _down_pulse := 0.0
var _down_arm := 1.0
var _down_kick := 0.0
var _down_mode := 0          # 1 crawling, 2 writhing (the clips)
var _limp_cap := INF         # top speed on a bad leg
var _slide_on := false       # the downed bodies on the slick material (crawling)
var _down_y := 0.0           # the floor height they went down on
var _chest_bone := -1
var _grab_cd := 0.0
var _grab_t := 0.0
var _pelvis_bone := -1
var _neck_bone := -1

# the strike: cock the arm back and twist away, whip it across at the head,
# recover. The damage lands at CONTACT, most of the way through the swing
const WIND := 0.25
const STRIKE := 0.15
const RECOVER := 0.35
const CONTACT := WIND + STRIKE * 0.7
const REACH_M := 1.35         # they stop and swing inside this
const HIT_M := 1.65           # still in reach at contact
# the hit springs: stiff and a little under-damped, settled in ~0.4 s
const FL_K := 170.0
const FL_C := 15.0

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
		# nothing to bend (standing straight, looking ahead): no bone work
		if absf(pitch) + absf(roll) + absf(yaw) < 0.002:
			return
		var sk := get_skeleton()
		if sk == null:
			return
		for i in bones.size():
			var q := Quaternion(ax, pitch * share[i]) * Quaternion(az, roll * share[i]) * Quaternion(ay, yaw * look[i])
			var gp := sk.get_bone_global_pose(bones[i])
			gp.basis = Basis(q) * gp.basis
			sk.set_bone_global_pose(bones[i], gp)

## The layer over the clips and the lean, run last: the hit flinch (rotation
## springs on the spine, neck, head and shoulders), the strike (there is no
## attack clip, so the arm is posed by aiming the upper arm and forearm), and
## the hands drifting forward as they close in. Rocketbox skeleton space is
## the model's: it faces +Z, its left is +X. Also keeps the finished head
## pose for the head hitbox and the ragdoll bones' pose for the ragdoll.
class Reach extends SkeletonModifier3D:
	var amount := 0.0          # 0 the clip's arms, 1 hands forward at the chest
	# the strike: side +1 the left arm, -1 the right; k 0 cocked back .. 1
	# through the target; w how much of the clip it overrides
	var strike_side := 1.0
	var strike_k := 0.0
	var strike_w := 0.0
	var grab := false
	var aim := Vector3(0, 0.1, 1)  # shoulders to the target, model space, unit
	var twist := 0.0           # torso yaw for the wind-up and follow-through
	# hit flinch: rotation vectors (model space, radians)
	var fl_torso := Vector3.ZERO
	var fl_head := Vector3.ZERO
	var fl_l := Vector3.ZERO
	var fl_r := Vector3.ZERO
	var sp1 := -1
	var sp2 := -1
	var neck := -1
	var cl := PackedInt32Array()
	var ua := PackedInt32Array()
	var fa := PackedInt32Array()
	var hd := PackedInt32Array()
	var head := -1
	var head_pose := Transform3D.IDENTITY
	var has_head := false
	var arms_ok := false
	# the finished pose of the ragdoll bones (clip + lean + reach), for the
	# ragdoll to start from: the skeleton reverts modifier output after each
	# update, so reading it later gives the bare clip and a stooped or
	# lunging body snapped upright as it died
	var snap_ids := PackedInt32Array()
	var snap_x: Array[Transform3D] = []   # alongside snap_ids, preallocated
	var snap_ix := {}          # bone -> index into snap_x (built once)
	var snap_ok := false
	var far := false           # far off: the ragdoll pose only every 4th update
	var _tick := 0

	## size the snapshot once the bone list is known
	func snap_ready() -> void:
		snap_x.resize(snap_ids.size())
		snap_ix.clear()
		for i in snap_ids.size():
			snap_ix[snap_ids[i]] = i

	func has_snap(b: int) -> bool:
		return snap_ok and snap_ix.has(b)

	func snap_of(b: int) -> Transform3D:
		return snap_x[snap_ix[b]]

	func setup(sk: Skeleton3D) -> void:
		for s in ["L", "R"]:
			cl.append(sk.find_bone("Bip01 %s Clavicle" % s))
			ua.append(sk.find_bone("Bip01 %s UpperArm" % s))
			fa.append(sk.find_bone("Bip01 %s Forearm" % s))
			hd.append(sk.find_bone("Bip01 %s Hand" % s))
		sp1 = sk.find_bone("Bip01 Spine1")
		sp2 = sk.find_bone("Bip01 Spine2")
		neck = sk.find_bone("Bip01 Neck")
		head = sk.find_bone("Bip01 Head")
		arms_ok = not (ua.has(-1) or fa.has(-1) or hd.has(-1))

	func _process_modification_with_delta(_delta: float) -> void:
		var sk := get_skeleton()
		if sk == null:
			return
		# the flinch first, spread up the chain (each bone adds to its parent's
		# turn). The thighs hang off Bip01 Spine and the clavicles off the
		# neck, so the pelvis and lower spine are left alone and the neck
		# only takes a little
		var tv := fl_torso + Vector3(0.0, twist, 0.0)
		if tv.length_squared() > 1e-6:
			_rot(sk, sp1, tv * 0.45)
			_rot(sk, sp2, tv * 0.55)
		if fl_head.length_squared() > 1e-6:
			_rot(sk, neck, fl_head * 0.3)
			_rot(sk, head, fl_head * 0.7)
		if fl_l.length_squared() > 1e-6:
			_rot(sk, cl[0], fl_l * 0.4)
			_rot(sk, ua[0], fl_l * 0.6)
		if fl_r.length_squared() > 1e-6:
			_rot(sk, cl[1], fl_r * 0.4)
			_rot(sk, ua[1], fl_r * 0.6)
		if arms_ok and (amount > 0.002 or strike_w > 0.002):
			for i in 2:
				var side := 1.0 if i == 0 else -1.0
				# relaxed: upper arm down and a little forward, forearm out
				# in front at the waist, elbows soft
				var u := Vector3(0.18 * side, -0.62, 0.62)
				var f := Vector3(-0.08 * side, -0.05, 1.0)
				var w := amount
				if strike_w > 0.002:
					var su: Vector3
					var sf: Vector3
					var sw := strike_w
					if grab:
						# both hands up and out, then in at the chest together
						su = Vector3(0.5 * side, 0.2, 0.55).normalized().slerp((aim + Vector3(0.22 * side, -0.1, 0.0)).normalized(), strike_k)
						sf = Vector3(0.15 * side, 0.55, 0.8).normalized().slerp((aim + Vector3(-0.08 * side, 0.0, 0.0)).normalized(), strike_k)
					elif side == strike_side:
						# the elbow cocked back and out with the hand by the ear,
						# then the arm swings round and across at the head
						su = Vector3(0.6 * side, 0.2, -0.5).normalized().slerp((aim + Vector3(-0.25 * side, 0.08, 0.0)).normalized(), strike_k)
						sf = Vector3(0.1 * side, 0.9, 0.3).normalized().slerp((aim + Vector3(-0.45 * side, 0.0, 0.0)).normalized(), strike_k)
					else:
						# the other hand comes up to guard and brace
						su = Vector3(0.25 * side, -0.5, 0.55).normalized()
						sf = Vector3(-0.2 * side, 0.55, 0.8).normalized()
						sw *= 0.55
					if sw >= w:
						u = su
						f = sf
						w = sw
				_aim(sk, ua[i], fa[i], u.normalized(), w)
				_aim(sk, fa[i], hd[i], f.normalized(), w * 0.95)
		if head >= 0:
			head_pose = sk.get_bone_global_pose(head)
			has_head = true
		_tick += 1
		if far and snap_ok and (_tick & 3) != 0:
			return
		for i in snap_ids.size():
			snap_x[i] = sk.get_bone_global_pose(snap_ids[i])
		snap_ok = true

	func _rot(sk: Skeleton3D, b: int, v: Vector3) -> void:
		if b < 0:
			return
		var a := v.length()
		if a < 0.0005:
			return
		var gp := sk.get_bone_global_pose(b)
		gp.basis = Basis(v / a, a) * gp.basis
		sk.set_bone_global_pose(b, gp)

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

## One person's locomotion (the hostiles and the town's pedestrians): idle,
## walk, run and the on-the-ground loops (crawl, writhe) each in two slots,
## so a new clip (another idle, the injured gait) cross-fades in rather than
## popping, and a sprint tier over the run. Every clip plays at the rate its
## feet travel at the speed the body really covers, at this person's size,
## so a planted foot stays planted. Two one-shots ride on top: an upper-body
## one for the attack clips (the legs keep walking) and a full-body one for
## a fall or the first moments of a death.
class Loco:
	const PRE := ["i", "w", "r", "d"]
	const FADE := 0.45
	const LOOPS := ["idle", "idle_angry", "idle_look", "idle_nervous", "walk", "walk_shamble",
		"walk_injured", "walk_stroll", "run", "run_fast", "run_injured", "crawl", "writhe"]
	const SPEEDS := "res://assets/enemies/clip_speeds.json"
	const EVENTS := "res://assets/enemies/clip_events.json"
	static var _speeds := {}
	static var _speeds_read := false
	static var _events := {}
	static var _events_read := false
	var tree: AnimationTree
	var ap: AnimationPlayer
	var key := ""              # the model's name in clip_speeds.json
	var walk_v := 1.4          # fallbacks when a clip has no measured speed
	var run_v := 3.07
	var nodes := [[null, null], [null, null], [null, null], [null, null]]
	var clip := [["", ""], ["", ""], ["", ""], ["", ""]]
	var cv := [[1.0, 1.0], [1.0, 1.0], [1.0, 1.0], [1.0, 1.0]]   # m/s at 1x and scale 1
	var cur := [0, 0, 0, 0]
	var x := [0.0, 0.0, 0.0, 0.0]
	var pend := ["", "", "", ""]
	var down := false          # the on-the-ground group over everything
	var downw := 0.0
	var atk_node: AnimationNodeAnimation
	var atk_shot: AnimationNodeOneShot
	var full_node: AnimationNodeAnimation
	var p_downb := &"parameters/downb/blend_amount"
	var p_atk := &"parameters/atk/request"
	var p_full := &"parameters/full/request"
	var p_full_on := &"parameters/full/active"
	var fast_node: AnimationNodeAnimation
	var fast_v := 4.0
	var fast_on := false
	var amp := 0.0
	var runw := 0.0
	var fastw := 0.0
	var p_x := []
	var p_s := [[], [], [], []]
	var p_walkb := &"parameters/walkb/blend_amount"
	var p_runb := &"parameters/runb/blend_amount"
	var p_fastb := &"parameters/fastb/blend_amount"
	var p_fs := &"parameters/fs/scale"
	var p_seek := &"parameters/seek/seek_request"

	## the measured travel speed of a clip at 1x, else the old constants
	static func speed_of(k: String, c: String, wv: float, rv: float) -> float:
		if not _speeds_read:
			_speeds_read = true
			if FileAccess.file_exists(SPEEDS):
				var d = JSON.parse_string(FileAccess.get_file_as_string(SPEEDS))
				if d is Dictionary:
					_speeds = d
		var m = _speeds.get(k)
		if m is Dictionary:
			if m.has(c) and float(m[c]) > 0.05:
				return float(m[c])
			# a variant (walk_2) without its own figure: its base clip's
			var b := base_of(c)
			if b != c and m.has(b) and float(m[b]) > 0.05:
				return float(m[b])
		if c.begins_with("crawl"):
			return 0.35
		return rv if c.begins_with("run") else wv

	## when in a one-shot clip its blow lands, in seconds: clip_events.json's
	## "hit" (seconds from the clip's start, as the clip builder writes it), else 45%
	static func hit_time(k: String, c: String, length: float) -> float:
		if not _events_read:
			_events_read = true
			if FileAccess.file_exists(EVENTS):
				var d = JSON.parse_string(FileAccess.get_file_as_string(EVENTS))
				if d is Dictionary:
					_events = d
		var m = _events.get(k)
		if m is Dictionary:
			for n in [c, base_of(c)]:
				var e = m.get(n)
				if e is Dictionary and e.has("hit"):
					var h := float(e["hit"])
					return clampf(h, 0.0, length)
		return 0.45 * length

	## walk_2 -> walk; anything else as it is
	static func base_of(c: String) -> String:
		if c.length() > 2 and c[c.length() - 2] == "_" and c[c.length() - 1] in ["2", "3"]:
			return c.substr(0, c.length() - 2)
		return c

	## one of a clip's three takes: idx 0 the base, 1 name_2, 2 name_3,
	## falling back to the base where that take is missing
	static func variant(p: AnimationPlayer, c: String, idx: int) -> String:
		if c == "" or idx <= 0:
			return c
		var v := "%s_%d" % [c, idx + 1]
		return v if p.has_animation(v) else c

	## the first of these clips the model has, or ""
	static func pick(p: AnimationPlayer, names: Array) -> String:
		for n in names:
			if n != "" and p.has_animation(n):
				return n
		return ""

	func setup(p: AnimationPlayer, model_key: String, wv: float, rv: float) -> void:
		ap = p
		key = model_key
		walk_v = wv
		run_v = rv
		for n in LOOPS:
			for sfx in ["", "_2", "_3"]:
				if ap.has_animation(n + sfx):
					ap.get_animation(n + sfx).loop_mode = Animation.LOOP_LINEAR
		# the player only lends its clips; the tree blends and paces them
		ap.stop()
		var bt := AnimationNodeBlendTree.new()
		for g in 4:
			var pre: String = PRE[g]
			bt.add_node(StringName(pre + "x"), AnimationNodeBlend2.new())
			p_x.append(StringName("parameters/%sx/blend_amount" % pre))
			for s in 2:
				var a := AnimationNodeAnimation.new()
				var an := StringName("%s%d" % [pre, s])
				var sn := StringName("%s%ds" % [pre, s])
				bt.add_node(an, a)
				bt.add_node(sn, AnimationNodeTimeScale.new())
				bt.connect_node(sn, 0, an)
				bt.connect_node(StringName(pre + "x"), s, sn)
				nodes[g][s] = a
				p_s[g].append(StringName("parameters/%s/scale" % sn))
		fast_node = AnimationNodeAnimation.new()
		bt.add_node(&"f", fast_node)
		bt.add_node(&"fs", AnimationNodeTimeScale.new())
		bt.connect_node(&"fs", 0, &"f")
		bt.add_node(&"walkb", AnimationNodeBlend2.new())
		bt.add_node(&"runb", AnimationNodeBlend2.new())
		bt.add_node(&"fastb", AnimationNodeBlend2.new())
		bt.add_node(&"seek", AnimationNodeTimeSeek.new())
		bt.connect_node(&"walkb", 0, &"ix")
		bt.connect_node(&"walkb", 1, &"wx")
		bt.connect_node(&"runb", 0, &"walkb")
		bt.connect_node(&"runb", 1, &"rx")
		bt.connect_node(&"fastb", 0, &"runb")
		bt.connect_node(&"fastb", 1, &"fs")
		bt.connect_node(&"seek", 0, &"fastb")
		# the attack clips over the upper body only (filter set by upper())
		atk_node = AnimationNodeAnimation.new()
		atk_shot = AnimationNodeOneShot.new()
		atk_shot.fadein_time = 0.12
		atk_shot.fadeout_time = 0.25
		bt.add_node(&"a_atk", atk_node)
		bt.add_node(&"atk", atk_shot)
		bt.connect_node(&"atk", 0, &"seek")
		bt.connect_node(&"atk", 1, &"a_atk")
		bt.add_node(&"downb", AnimationNodeBlend2.new())
		bt.connect_node(&"downb", 0, &"atk")
		bt.connect_node(&"downb", 1, &"dx")
		full_node = AnimationNodeAnimation.new()
		var full := AnimationNodeOneShot.new()
		full.fadein_time = 0.1
		full.fadeout_time = 0.3
		bt.add_node(&"a_full", full_node)
		bt.add_node(&"full", full)
		bt.connect_node(&"full", 0, &"downb")
		bt.connect_node(&"full", 1, &"a_full")
		bt.connect_node(&"output", 0, &"full")
		# every slot holds a real clip from the start (an empty one is an
		# invalid node); the callers pick the real ones straight after
		var base := pick(ap, ["idle", "walk", "run"])
		for g in 4:
			for s in 2:
				_load(g, s, pick(ap, [["idle", "walk"], ["walk", "idle"], ["run", "walk"], ["crawl", "writhe", "idle"]][g]) if base != "" else "")
		atk_node.animation = StringName(base)
		full_node.animation = StringName(base)
		fast_node.animation = StringName(pick(ap, ["run_fast", "run", "walk"]))
		fast_v = speed_of(key, str(fast_node.animation), walk_v, run_v)
		tree = AnimationTree.new()
		ap.get_parent().add_child(tree)
		tree.anim_player = tree.get_path_to(ap)
		tree.root_node = tree.get_path_to(ap.get_node(ap.root_node))
		tree.tree_root = bt
		tree.active = true

	func _load(g: int, s: int, c: String) -> void:
		if c == "":
			return
		(nodes[g][s] as AnimationNodeAnimation).animation = StringName(c)
		clip[g][s] = c
		cv[g][s] = speed_of(key, c, walk_v, run_v)

	## this clip on group g at once, in both slots (a fresh spawn)
	func force(g: int, c: String) -> void:
		if c == "":
			return
		_load(g, 0, c)
		_load(g, 1, c)
		cur[g] = 0
		x[g] = 0.0
		pend[g] = ""
		tree.set(p_x[g], 0.0)

	## fade group g over to this clip (queued until the spare slot is silent)
	func want(g: int, c: String) -> void:
		if c == "":
			return
		if clip[g][cur[g]] == c:
			pend[g] = ""
			return
		var o: int = 1 - cur[g]
		if clip[g][o] == c:
			cur[g] = o
			pend[g] = ""
			return
		pend[g] = c

	func now(g: int) -> String:
		return clip[g][cur[g]]

	func idle_rate(r: float) -> void:
		tree.set(p_s[0][0], r)
		tree.set(p_s[0][1], r)

	## the attack one-shot plays only on the spine, arms and head: every
	## track on a bone under Bip01 Spine1
	func upper(sk: Skeleton3D) -> void:
		var top := sk.find_bone("Bip01 Spine1")
		var a := ap.get_animation(pick(ap, ["walk", "idle"]))
		if top < 0 or a == null:
			return
		atk_shot.filter_enabled = true
		for t in a.get_track_count():
			var path := a.track_get_path(t)
			var b := sk.find_bone(str(path.get_concatenated_subnames()))
			while b >= 0 and b != top:
				b = sk.get_bone_parent(b)
			if b == top:
				atk_shot.set_filter_path(path, true)

	func fire_upper(c: String) -> void:
		atk_node.animation = StringName(c)
		tree.set(p_atk, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)

	func fire_full(c: String) -> void:
		full_node.animation = StringName(c)
		tree.set(p_full, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)

	func stop_shots() -> void:
		tree.set(p_atk, AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
		tree.set(p_full, AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)

	func reset(seek_t: float) -> void:
		amp = 0.0
		runw = 0.0
		fastw = 0.0
		down = false
		downw = 0.0
		tree.set(p_downb, 0.0)
		tree.set(p_walkb, 0.0)
		tree.set(p_runb, 0.0)
		tree.set(p_fastb, 0.0)
		tree.set(p_seek, seek_t)

	## spd: ground speed, m/s; sc: this person's size (scale x stride)
	func step(dt: float, spd: float, sc: float) -> void:
		for g in 4:
			var o: int = 1 - cur[g]
			var wo: float = x[g] if o == 1 else 1.0 - x[g]
			if pend[g] != "" and wo < 0.02:
				_load(g, o, pend[g])
				cur[g] = o
				pend[g] = ""
			var nx := move_toward(x[g], float(cur[g]), dt / FADE)
			if nx != x[g]:
				x[g] = nx
				tree.set(p_x[g], nx)
		# walk in over the idle by ~half the walk's speed, run in over the
		# walk past ~1.1x walk, the sprint over the run past ~1.1x run
		var vw: float = lerpf(cv[1][0], cv[1][1], x[1]) * sc
		var vr: float = lerpf(cv[2][0], cv[2][1], x[2]) * sc
		var vf: float = fast_v * sc
		var wa := 0.0 if spd < 0.06 else clampf(spd / (vw * 0.55), 0.0, 1.0)
		var ra := clampf((spd - vw * 1.1) / maxf(vr * 0.8 - vw * 1.1, 0.1), 0.0, 1.0)
		var fa := clampf((spd - vr * 1.1) / maxf(vf * 0.85 - vr * 1.1, 0.1), 0.0, 1.0) if fast_on else 0.0
		amp = lerpf(amp, wa, clampf(dt * 8.0, 0.0, 1.0))
		runw = lerpf(runw, ra, clampf(dt * 6.0, 0.0, 1.0))
		fastw = lerpf(fastw, fa, clampf(dt * 5.0, 0.0, 1.0))
		tree.set(p_walkb, amp)
		tree.set(p_runb, runw)
		tree.set(p_fastb, fastw)
		for s in 2:
			tree.set(p_s[1][s], clampf(spd / (float(cv[1][s]) * sc), 0.3, 2.0) if amp > 0.02 else 1.0)
			tree.set(p_s[2][s], clampf(spd / (float(cv[2][s]) * sc), 0.5, 1.8) if runw > 0.02 else 1.0)
		tree.set(p_fs, clampf(spd / vf, 0.5, 1.6) if fastw > 0.02 else 1.0)
		# on the ground: a crawl paced to the ground it drags over, a writhe
		# at its own pace
		var dw := move_toward(downw, 1.0 if down else 0.0, dt / 0.35)
		if dw != downw:
			downw = dw
			tree.set(p_downb, dw)
		if downw > 0.0:
			for s in 2:
				var crawl := str(clip[3][s]).begins_with("crawl")
				tree.set(p_s[3][s], clampf(spd / (float(cv[3][s]) * sc), 0.4, 1.8) if crawl and spd > 0.02 else (0.25 if crawl else 1.0))

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

static var _rng: RandomNumberGenerator
static var _next_model := 0
static var _var_rr := 0          # hands out clip takes in turn, so neighbours differ
static var _look_mats := {}      # source StandardMaterial3D -> ShaderMaterial
static var _look_shaders := {}   # render mode -> Shader
static var _rag_pm: PhysicsMaterial
static var _rag_slide: PhysicsMaterial
# the crawl's haul: chest first, the hips and thighs a little behind, the
# shins dragged; the share of the haul speed each is carried at
const DRAG_PARTS := ["Bip01 Spine2", "Bip01 Spine1", "Bip01 Pelvis", "Bip01 L Thigh", "Bip01 R Thigh", "Bip01 L Calf", "Bip01 R Calf"]
const DRAG_SHARE := [1.0, 0.95, 0.9, 0.85, 0.85, 0.75, 0.75]

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
		if anim and anim.has_animation("walk"):
			loco = Loco.new()
			loco.setup(anim, str(MODELS[_model_i]).get_file().get_basename(), WALK_V[_model_i], RUN_V[_model_i])
			tree = loco.tree
		if skel:
			lean = Lean.new()
			skel.add_child(lean)
			# the look turns the head most, the neck and upper chest a little
			# (the clavicles hang off the neck, so it cannot take much)
			lean.setup(skel, model, ["Bip01 Spine1", "Bip01 Spine2", "Bip01 Neck", "Bip01 Head"], [0.35, 0.35, 0.2, 0.1], [0.0, 0.25, 0.2, 0.55])
			reach = Reach.new()
			skel.add_child(reach)
			reach.setup(skel)
			for e in RAG:
				for nm in [e[0], e[1]]:
					if str(nm) != "":
						var bi := skel.find_bone(nm)
						if bi >= 0 and not reach.snap_ids.has(bi):
							reach.snap_ids.append(bi)
			reach.snap_ready()
			_head_bone = skel.find_bone("Bip01 Head")
			_pelvis_bone = skel.find_bone("Bip01 Pelvis")
			_neck_bone = skel.find_bone("Bip01 Neck")
			_chest_bone = skel.find_bone("Bip01 Spine2")
			if loco:
				loco.upper(skel)
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

## the gait for how they are now: walkers shamble, brutes plod on the plain
## walk, runners and the panicking sprint; anyone badly hurt or shot in the
## leg falls back on the injured walk and run
func _gait() -> void:
	if loco == null:
		return
	_gait_key = _gait_now()
	var hurt := (_gait_key & 1) != 0
	var sprinter := (_gait_key & 2) != 0
	var w := ["walk"]
	if hurt:
		w = ["walk_injured", "walk_shamble", "walk"]
	elif state == "lotidle":
		w = ["walk_stroll", "walk"]
	elif variant != "brute":
		w = ["walk_shamble", "walk"]
	var r := ["run_injured", "run"] if hurt else (["run_fast", "run"] if sprinter else ["run"])
	# a slow gait only if their pace suits it: a shamble hurried to 1.7x is
	# a scuttle, so a quick walker walks
	# a bad leg drags them down to what the limp can carry
	_limp_cap = INF
	if _leg_hurt:
		var lv := Loco.speed_of(loco.key, Loco.pick(anim, ["walk_injured", "walk"]), loco.walk_v, loco.run_v)
		_limp_cap = maxf(lv * _sc * _stride * 1.3, speed * 0.65)
	var pace := minf(speed, _limp_cap)
	# (the shamble reads as a stagger even played fast, so it runs to 1.9x;
	# measured on the take they will actually play; if their own take is
	# too slow for their pace, another take of the same gait before giving up)
	var wc := ""
	var fits := false
	for n in w:
		if not anim.has_animation(n):
			continue
		var top := 1.9 if n == "walk_shamble" else 1.4
		for t in 3:
			var c := Loco.variant(anim, n, (_wvar + t) % 3)
			if wc == "" or t == 0:
				wc = c
			if pace <= Loco.speed_of(loco.key, c, loco.walk_v, loco.run_v) * _sc * _stride * top:
				wc = c
				fits = true
				break
		if fits:
			break
	loco.want(1, wc)
	loco.want(2, Loco.variant(anim, Loco.pick(anim, r), _rvar))
	# the sprint tier over the run is for the rest when they really open up
	loco.fast_on = not hurt and not sprinter

## the things the gait depends on, as bits, so it is only re-picked on a change
func _gait_now() -> int:
	var k := 0
	if _leg_hurt or hp < max_hp * 0.4:
		k |= 1
	if _runner or flee or (state == "lotidle" and _sc_t > 0.0):
		k |= 2
	if state == "lotidle":
		k |= 4
	if variant == "brute":
		k |= 8
	return k

## a standing idle for the mood: onlookers look about or fidget, the ones
## after you stand braced and angry
func _pick_idle() -> String:
	if anim == null:
		return ""
	var take := _rng.randi() % 3
	if state == "lotidle":
		var opts := ["idle", "idle_look", "idle_nervous", "idle_look"]
		return Loco.variant(anim, Loco.pick(anim, [opts[_rng.randi() % opts.size()], "idle"]), take)
	return Loco.variant(anim, Loco.pick(anim, ["idle_angry", "idle"] if _rng.randf() < 0.7 else ["idle_nervous", "idle"]), take)

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
	_runner = runner
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
	_yaw_vel = 0.0
	_lean = Vector2.ZERO
	_lean_v = Vector2.ZERO
	_look = 0.0
	_stag_t = 0.0
	_atk_t = -1.0
	_atk_fired = false
	_atk_side = 1.0 if _rng.randf() < 0.5 else -1.0
	_near_w = 0.0
	_vel = Vector3.ZERO
	_ft = Vector3.ZERO
	_ftv = Vector3.ZERO
	_fh = Vector3.ZERO
	_fhv = Vector3.ZERO
	_fl = Vector3.ZERO
	_flv = Vector3.ZERO
	_fr = Vector3.ZERO
	_frv = Vector3.ZERO
	_dip = 0.0
	_dip_v = 0.0
	_knock = Vector3.ZERO
	_leg_hurt = false
	_limp_side = 0.0
	_limp_cap = INF
	_fall = 0.0
	_settled = false
	_still_t = 0.0
	_dying = 0.0
	_atk_clip = false
	_atk_contact = CONTACT
	_down_t = 0.0
	_down_clip = false
	_down_mode = 0
	_slide_on = false
	_grab_t = 0.0
	_idle_t = _rng.randf_range(4.0, 12.0)
	_moving = false
	# the walk and run takes in turn (a step of 1 or 2, never 0), so people
	# spawned together are never on the same one
	_var_rr += 1 + (_rng.randi() & 1)
	_wvar = _var_rr % 3
	_rvar = (_var_rr + 1 + (_rng.randi() & 1)) % 3
	_gait_key = -1
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
		reach.strike_w = 0.0
		reach.twist = 0.0
		reach.snap_ok = false        # last life's pose is not this one's
		reach.fl_torso = Vector3.ZERO
		reach.fl_head = Vector3.ZERO
		reach.fl_l = Vector3.ZERO
		reach.fl_r = Vector3.ZERO
	if loco:
		tree.active = true
		loco.stop_shots()
		# a random point in every cycle, so a crowd never steps in unison
		loco.reset(_rng.randf() * 11.0)
		loco.idle_rate(_idle_rate)
		loco.force(0, _pick_idle())
		_gait()
		loco.force(1, loco.pend[1] if loco.pend[1] != "" else loco.now(1))
		loco.force(2, loco.pend[2] if loco.pend[2] != "" else loco.now(2))

## a person's size: the model, the body capsule to the neck, the head sphere
func _apply_scale(s: float) -> void:
	_sc = s
	_body_cs.rotation = Vector3.ZERO     # upright again after lying downed
	_cap.radius = 0.35
	if model:
		model.scale = Vector3.ONE * s
	var stoop := 0.78 if variant == "crawler" else 0.84
	_cap.height = maxf(0.9, _height * s * stoop)
	_body_cs.position = Vector3(0.0, _cap.height * 0.5, 0.0)
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
	_idle_t = 0.0                # an onlooker's idle, not a chaser's

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
	_near_w = 0.0
	# a round's shove, straight onto the position (they are not sliding here)
	if _knock.length_squared() > 0.0001:
		global_position += Vector3(_knock.x, 0.0, _knock.z) * dt
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
	_animate(dt, want, 1.6, look, 40.0)

## a runner: away from you to a spot eight metres off, a new one when it
## gets there, screaming now and then; never attacks
func _flee_step(dt: float) -> void:
	_near_w = 0.0
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
	var sp := speed * 1.4 * (1.0 - 0.6 * clampf(_stag_t / 0.35, 0.0, 1.0))
	velocity.x = dir.x * sp + _knock.x
	velocity.z = dir.z * sp + _knock.z
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
var _rag_parts := {}          # bone name -> its body, for the downed crawl
var _rag_vy := Vector2.ZERO   # last vertical speed of pelvis, chest
var _thuds := 0
var _thud_cd := 0.0
var _pooled := false
var _settled := false         # the corpse has come to rest: physics off
var _still_t := 0.0

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
	if reach and reach.has_snap(bi):
		return reach.snap_of(bi)
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
		rb.freeze = false              # frozen when its last corpse settled
		rb.sleeping = false
		rb.collision_layer = 64        # (downed bodies are shootable: 64 | 4)
		rb.physics_material_override = _rag_pm
		_rag.append([bi, rb, rb.global_transform.affine_inverse() * bone_w, k])
		by_bone[bi] = rb
		_rag_parts[e[0]] = rb
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
	_rag_kick(dir, at, dmg, headshot, true)
	_rag_vy = Vector2.ZERO
	_thuds = 0
	_thud_cd = 0.0
	return true

## The momentum into the bodies: the whole body carries its own plus a share
## of the round's (whole: every body's velocity is set; a body already lying
## on the ground keeps its own), the round goes into the part it hit, and a
## car throws all of it along the bonnet and up.
func _rag_kick(dir: Vector3, at: Vector3, dmg: float, headshot: bool, whole: bool) -> void:
	var dn := dir.normalized() if dir.length() > 0.001 else -global_basis.z
	var flat := Vector3(dn.x, 0, dn.z)
	flat = flat.normalized() if flat.length() > 0.001 else -global_basis.z
	var k := clampf(dmg / 38.0, 0.6, 2.6)
	# the way the body was really moving (a stride, a lunge, a stagger)
	var carry := Vector3(_vel.x, 0.0, _vel.z).limit_length(6.0) * 0.85
	var body_v := carry + flat * 0.35 * k
	if headshot:
		# the lights go out: no push off the legs, the knees just go and the
		# body folds where it stood, drifting on with its step
		body_v = carry * 0.6 + flat * 0.12 * k + Vector3.DOWN * 0.5
	if rag_boost > 1.0:
		body_v = carry * 0.3 + flat * 2.2 * rag_boost + Vector3.UP * (0.6 + 0.9 * (rag_boost - 1.0))
	for r in _rag:
		var rb: RigidBody3D = r[1]
		if whole or rag_boost > 1.0:
			rb.linear_velocity = body_v
		rb.sleeping = false
	# the flinch in progress carries on: the chest and head keep turning the
	# way the last rounds were throwing them
	var wb := global_basis
	if whole and _rag_chest:
		_rag_chest.angular_velocity = wb * (_ftv * 0.6)
	if whole and _rag_head:
		_rag_head.angular_velocity = wb * ((_ftv + _fhv) * 0.6)
	# the round goes into the part it hit: a headshot snaps the head back
	var part: RigidBody3D = _rag_head if headshot and _rag_head else _nearest_part(at)
	if part:
		var imp := dn * (8.0 + 6.0 * k)
		if headshot:
			imp = dn * (10.0 + 5.0 * k) + Vector3.UP * 1.0
		if rag_boost > 1.0:
			imp = flat * 14.0 * rag_boost + Vector3.UP * 4.0 * rag_boost
		part.apply_impulse(imp, (at - part.global_position).limit_length(0.1))
		# a body hit also shoves the hips a little the same way, so they go
		# over away from the shot rather than crumpling onto it
		if not headshot and rag_boost <= 1.0 and _rag_pelvis and part != _rag_pelvis:
			_rag_pelvis.apply_central_impulse(flat * (2.0 + 1.5 * k))

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
	_rag_parts.clear()
	_rag_head = null
	_rag_pelvis = null
	_rag_chest = null

## the corpse: the body lands with a thud when the hips or chest hit the
## floor, and once it lies still the blood spreads out under it
func _dead_step(dt: float) -> void:
	if _settled:
		return
	if _dying > 0.0:
		# the death clip's opening: the hit springs keep going over it, then
		# the ragdoll takes the pose it has reached
		_dying -= dt
		_springs(dt)
		if loco:
			loco.step(dt, 0.0, _sc * _stride)
		if model:
			model.position = model.position.lerp(Vector3(0.0, _dip, 0.0), clampf(dt * 8.0, 0.0, 1.0))
		if _dying <= 0.0:
			_die_now(_die_dir, _die_at, _die_dmg, false)
		return
	if _rag.is_empty():
		# no bodies (no skeleton or a failed build): never left standing -
		# the whole model tips over away from the shot and sinks to the floor
		if model:
			var k := smoothstep(0.0, 0.55, dead_t)
			model.rotation.x = _fall * 1.45 * k * k
			model.position.y = -0.12 * k * _sc
		if not _pooled and dead_t > 1.2:
			_pooled = true
			Fx.blood_pool(global_position + Vector3(0, 0.3, 0), randf_range(0.6, 1.1) * _sc)
		if dead_t > 1.3:
			_settled = true
		return
	_rag_pose()
	# at rest (or long enough): the bodies freeze where they lie and the
	# bones keep that last pose, so a floor of corpses costs no physics
	if dead_t > 0.8 and _rag_pelvis and _rag_chest:
		var still := _rag_pelvis.linear_velocity.length() < 0.15 and _rag_chest.linear_velocity.length() < 0.15 \
				and _rag_chest.angular_velocity.length() < 0.6
		_still_t = _still_t + dt if still else 0.0
		if _still_t > 0.5 or dead_t > 6.0:
			_settle()
			return
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

func _settle() -> void:
	_settled = true
	for r in _rag:
		var rb: RigidBody3D = r[1]
		rb.linear_velocity = Vector3.ZERO
		rb.angular_velocity = Vector3.ZERO
		rb.freeze = true
	if not _pooled and _rag_chest and _rag_pelvis:
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
		model.rotation = Vector3.ZERO
	_settled = false
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
	return state == "chase" or state == "attack" or state == "downed"

## the middle of the head, off the head bone as it is drawn (after the lean
## and the grab), in world space
func head_center() -> Vector3:
	if skel == null or _head_bone < 0:
		return global_position + Vector3.UP * head_y
	if not _rag.is_empty() and _rag_head:
		# on the ragdoll (downed): the head body is the head
		return _rag_head.global_position
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
	var was_down := state == "downed"
	var leg := not head and not was_down and to_local(at).y < _height * _sc * 0.48
	hp -= dmg
	# on the ground, any round finishes them
	if was_down:
		hp = minf(hp, 0.0)
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
		_settled = false
		_still_t = 0.0
		collision_layer = 0
		velocity = Vector3.ZERO
		var rag := false
		if not _rag.is_empty():
			# already on the ground on the ragdoll: the bodies stop being a
			# target and take the round
			for r in _rag:
				(r[1] as RigidBody3D).collision_layer = 64
			if _slide_on:
				_slide_on = false
				_rag_material(_rag_pm)
			_rag_kick(dir, at, dmg, head, false)
			rag = true
		else:
			# a body shot on their feet, with a death clip: the first few
			# tenths of the authored collapse, then the ragdoll from that
			# pose. A headshot or the car is the ragdoll at once
			var dc := ""
			if loco and not head and not was_down and rag_boost <= 1.0 and skel and anim.has_animation("death"):
				dc = Loco.variant(anim, "death", _rng.randi() % 3)
			if dc != "":
				loco.stop_shots()
				loco.fire_full(dc)
				_dying = minf(randf_range(0.3, 0.6), anim.get_animation(dc).length * 0.9)
				_die_dir = dir
				_die_at = at
				_die_dmg = dmg
				_atk_t = -1.0
				# the killing round still rocks them, over the clip
				_react(dmg, at, dir, head)
				rag = true
			else:
				rag = _die_now(dir, at, dmg, head)
		if randf() < 0.6:
			_say("kill-voice.mp3", -4.0, randf_range(0.85, 1.1))
		if not rag:
			# no bodies to land: the thud on a timer, as before
			get_tree().create_timer(0.55).timeout.connect(func():
				if is_instance_valid(self) and visible: Game.play_file_at("sfx-body-drop.mp3", global_position + Vector3(0, 0.3, 0), -3.0, randf_range(0.9, 1.05), 30.0))
		killed.emit(self)
		return true
	_react(dmg, at, dir, head)
	# some go down and stay down: badly hurt, or a leg taken out from under
	# someone already hurt
	if state in ["chase", "attack"] and (hp < max_hp * 0.3 or (leg and hp < max_hp * 0.55)) and randf() < 0.3:
		_go_down(dir, at, dmg)
	return false

## DOWNED: a round that leaves them alive puts them on the ground. With the
## clips: the fall, then a crawl at you or a writhe, on their own hitbox
## laid along the body. Without: the ragdoll takes them down and is driven
## by hand - hauled forward arm over arm, or twitching and kicking - its
## bodies the target. Any round finishes them; left alone they bleed out.
func _go_down(dir: Vector3, at: Vector3, dmg: float) -> void:
	state = "downed"
	_cancel_strike()
	_down_t = 0.0
	_down_life = randf_range(12.0, 22.0)
	_down_crawl = randf() < 0.65
	_down_pulse = 0.0
	_down_kick = 0.5
	_down_mode = 0
	_grab_cd = 1.5
	_grab_t = 0.0
	_near_w = 0.0
	velocity = Vector3.ZERO
	var fall := Loco.pick(anim, ["fall_prone"]) if loco else ""
	var lie := Loco.pick(anim, ["crawl", "writhe"]) if loco else ""
	_down_y = global_position.y
	if fall != "" and lie != "":
		_down_clip = true
		var fc := Loco.variant(anim, fall, _rng.randi() % 3)
		_fall_len = anim.get_animation(fc).length
		loco.stop_shots()
		loco.fire_full(fc)
		# the ground loop waits under the fall and takes over as it ends
		_down_lie(_down_crawl, true)
		loco.down = true
		return
	_down_clip = false
	# a crawler folds forward onto their hands (toward you); the rest go
	# over the way the round pushed them
	var fall_dir := dir
	if _down_crawl:
		fall_dir = global_basis.z * 0.6 + Vector3.DOWN * 0.2
	if not _ragdoll(fall_dir, at, dmg * 0.6, false):
		# nothing to fall on: they stay up, hurt
		state = "chase"
		return
	collision_layer = 0
	for r in _rag:
		(r[1] as RigidBody3D).collision_layer = 64 | 4

## crawl or writhe on the ground group (a fresh take each time it changes)
func _down_lie(crawl: bool, now: bool) -> void:
	var m := 1 if crawl else 2
	if m == _down_mode:
		return
	_down_mode = m
	var c := Loco.variant(anim, Loco.pick(anim, ["crawl", "writhe"] if crawl else ["writhe", "crawl"]), _rng.randi() % 3)
	if now:
		loco.force(3, c)
	else:
		loco.want(3, c)

func _down_step(dt: float) -> void:
	_down_t += dt
	_grab_cd -= dt
	if _down_t > _down_life:
		_bleed_out()
		return
	if _down_clip:
		_down_step_clip(dt)
	else:
		_down_step_rag(dt)

## on the clips: the body crawls on the ground at the clip's pace, turning
## slowly toward you, or lies writhing
func _down_step_clip(dt: float) -> void:
	var pp := target.global_position
	var to := pp - global_position
	to.y = 0.0
	var dist := to.length()
	var up := _down_t > _fall_len - 0.25
	var crawl := _down_crawl and up and dist > 0.9 and dist < 16.0
	if up:
		_down_lie(crawl or (_down_crawl and dist <= 0.9), false)
	var sp := 0.0
	if crawl and loco.now(3).begins_with("crawl"):
		sp = float(loco.cv[3][loco.cur[3]]) * _sc * _stride
		var want := atan2(to.x, to.z)
		rotation.y = wrapf(rotation.y + clampf(wrapf(want - rotation.y, -PI, PI), -1.0 * dt, 1.0 * dt), -PI, PI)
	var fwd := global_basis.z
	velocity.x = fwd.x * sp + _knock.x
	velocity.z = fwd.z * sp + _knock.z
	# the origin stays at the floor they fell on: the laid-down hitbox is
	# no footing, so gravity here would sink the whole body
	velocity.y = 0.0
	move_and_slide()
	global_position.y = _down_y
	var mv := global_position - _last_pos
	_last_pos = global_position
	mv.y = 0.0
	_spd = lerpf(_spd, mv.length() / maxf(dt, 0.0001), clampf(dt * 10.0, 0.0, 1.0))
	_knock *= maxf(0.0, 1.0 - dt * 7.0)
	loco.step(dt, _spd, _sc * _stride)
	_springs(dt)
	if model:
		model.position = model.position.lerp(Vector3(0.0, _lie_lift(), 0.0), clampf(dt * 6.0, 0.0, 1.0))
	if lean:
		lean.pitch = lerpf(lean.pitch, 0.0, clampf(dt * 5.0, 0.0, 1.0))
		lean.roll = lerpf(lean.roll, 0.0, clampf(dt * 5.0, 0.0, 1.0))
		lean.yaw = lerpf(lean.yaw, 0.0, clampf(dt * 5.0, 0.0, 1.0))
	# a hand shoots out at your ankle when you stand over them
	if up and _grab_cd <= 0.0 and dist < 1.1:
		_ankle_grab()
	if reach:
		reach.amount = 0.0
		reach.twist = 0.0
		if _grab_t > 0.0:
			_grab_t -= dt
			var a := global_basis.inverse() * (pp + Vector3(0.0, 0.1, 0.0) - head_center())
			reach.aim = a.normalized() if a.length() > 0.01 else Vector3(0, 0, 1)
			reach.grab = false
			reach.strike_side = 1.0 if a.x > 0.0 else -1.0
			reach.strike_k = 1.0
			reach.strike_w = sin(clampf(1.0 - _grab_t / 0.5, 0.0, 1.0) * PI)
		else:
			reach.strike_w = 0.0
	_lie_hitbox()
	_sync_head()

## lying on the clips: however the clip places the body, the lowest of the
## hips, chest and head rests a body's thickness off the floor (none while
## the fall is still upright, and never more than a little either way)
func _lie_lift() -> float:
	if reach == null or not reach.has_snap(_pelvis_bone) or _down_t < _fall_len * 0.6:
		return 0.0
	var low := reach.snap_of(_pelvis_bone).origin.y
	if reach.has_snap(_chest_bone):
		low = minf(low, reach.snap_of(_chest_bone).origin.y)
	if reach.has_snap(_head_bone):
		low = minf(low, reach.snap_of(_head_bone).origin.y)
	# skeleton space is the model's, before its scale
	return clampf(0.12 * _sc - low * _sc, -0.25, 0.3)

## on the ragdoll: the node follows the hips (for the distance checks, the
## voice and the car), and the bodies are pushed about to look alive
func _down_step_rag(dt: float) -> void:
	if _rag.is_empty() or _rag_chest == null or _rag_pelvis == null:
		_bleed_out()
		return
	var hip := _rag_pelvis.global_position
	global_position = Vector3(hip.x, global_position.y, hip.z)
	_last_pos = global_position
	_rag_pose()                   # after the move, so the mesh sits on the bodies
	if _down_t < 1.3:
		return                    # still going down
	var life := clampf(1.0 - _down_t / _down_life, 0.0, 1.0)
	var pp := target.global_position
	var to := pp - _rag_chest.global_position
	to.y = 0.0
	var dist := to.length()
	var fwd := to / dist if dist > 0.01 else Vector3.FORWARD
	if _down_crawl and dist > 0.8 and dist < 16.0:
		# arm over arm: one arm lifts and stretches out ahead, plants, and
		# the body is hauled up to the planted hand with the hips and legs
		# sliding after; head and shoulders held up off the floor. The
		# bodies slide on a slicker material while crawling, and the chest
		# is swung round to face you so the drag is head first
		if not _slide_on:
			_slide_on = true
			_rag_material(_slide_pm())
		var per := 1.2 / (0.6 + 0.4 * life)
		_down_pulse += dt
		if _down_pulse >= per:
			_down_pulse -= per
			_down_arm = -_down_arm
		var ph := _down_pulse / per
		var fore: RigidBody3D = _rag_parts.get("Bip01 L Forearm" if _down_arm > 0.0 else "Bip01 R Forearm")
		var other: RigidBody3D = _rag_parts.get("Bip01 R Forearm" if _down_arm > 0.0 else "Bip01 L Forearm")
		var strength := 0.7 + 0.3 * life
		var pull := 0.15 * strength           # a little glide between hauls
		if ph < 0.4:
			# the reach: up and out ahead; the other hand stays planted
			if fore:
				fore.linear_velocity = fore.linear_velocity.lerp(fwd * 2.0 + Vector3.UP * 1.4, clampf(dt * 12.0, 0.0, 1.0))
			if other:
				other.linear_velocity = Vector3(0.0, minf(other.linear_velocity.y, 0.0), 0.0)
		else:
			# the haul: the reaching hand plants and holds, the body comes to it
			pull = 0.78 * strength * sin((ph - 0.4) / 0.6 * PI) + 0.15 * strength
			if fore:
				fore.linear_velocity = Vector3(0.0, minf(fore.linear_velocity.y, -0.4), 0.0)
		for i in DRAG_PARTS.size():
			var b: RigidBody3D = _rag_parts.get(DRAG_PARTS[i])
			if b:
				var bv := b.linear_velocity
				var k: float = DRAG_SHARE[i] * pull
				b.linear_velocity = Vector3(fwd.x * k, bv.y if i > 0 else maxf(bv.y, 0.25 * pull), fwd.z * k)
		# face you: yaw the chest (its Y runs up the spine to the neck)
		var sy := _rag_chest.global_basis.y
		var head_dir := Vector3(sy.x, 0.0, sy.z)
		if head_dir.length_squared() > 0.01:
			var err := head_dir.normalized().signed_angle_to(fwd, Vector3.UP)
			_rag_chest.angular_velocity.y = lerpf(_rag_chest.angular_velocity.y, clampf(err * 2.5, -1.5, 1.5), clampf(dt * 6.0, 0.0, 1.0))
		_rag_chest.apply_central_force(Vector3.UP * 55.0 * life)
		if _rag_head:
			_rag_head.apply_central_force(Vector3.UP * 30.0 * life + fwd * 6.0)
	else:
		# writhing: the chest rolls, a leg kicks out, an arm flails, weaker
		# and further apart as they bleed
		_down_kick -= dt
		if _down_kick <= 0.0:
			_down_kick = randf_range(0.35, 0.9) / maxf(life, 0.3)
			var s := 0.4 + 0.6 * life
			_rag_chest.apply_torque_impulse(Vector3(randf_range(-1, 1), randf_range(-0.4, 0.4), randf_range(-1, 1)) * 0.35 * s)
			var calf: RigidBody3D = _rag_parts.get("Bip01 L Calf" if randf() < 0.5 else "Bip01 R Calf")
			if calf:
				calf.apply_central_impulse((Vector3(randf_range(-1, 1), 0.0, randf_range(-1, 1)).normalized() * 3.0 + Vector3.UP * 2.0) * s)
			var arm: RigidBody3D = _rag_parts.get("Bip01 L Forearm" if randf() < 0.5 else "Bip01 R Forearm")
			if arm:
				arm.apply_central_impulse((Vector3.UP * 1.2 + Vector3(randf_range(-0.6, 0.6), 0.0, randf_range(-0.6, 0.6))) * s)
			if _rag_head:
				_rag_head.apply_torque_impulse(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.05 * s)
		_rag_chest.apply_central_force(Vector3.UP * 25.0 * life)
	if _grab_cd <= 0.0 and dist < 1.1:
		_ankle_grab()
		var near: RigidBody3D = _rag_parts.get("Bip01 L Forearm" if randf() < 0.5 else "Bip01 R Forearm")
		if near:
			var at := pp - near.global_position
			near.linear_velocity = at.normalized() * 3.0 + Vector3.UP * 0.8

static func _slide_pm() -> PhysicsMaterial:
	if _rag_slide == null:
		_rag_slide = PhysicsMaterial.new()
		_rag_slide.friction = 0.2
		_rag_slide.bounce = 0.0
	return _rag_slide

func _rag_material(pm: PhysicsMaterial) -> void:
	for r in _rag:
		(r[1] as RigidBody3D).physics_material_override = pm

## a grab at your ankle when you stand over them
func _ankle_grab() -> void:
	_grab_cd = randf_range(1.3, 2.0)
	_grab_t = 0.5
	if target.has_method("take_damage"):
		target.call("take_damage", 10.0, global_position)

## left alone they bleed out where they lie
func _bleed_out() -> void:
	hp = 0.0
	state = "dead"
	dead_t = 0.0
	_pooled = false
	_settled = false
	_still_t = 0.0
	collision_layer = 0
	velocity = Vector3.ZERO
	if not _rag.is_empty():
		for r in _rag:
			(r[1] as RigidBody3D).collision_layer = 64
		if _slide_on:
			_slide_on = false
			_rag_material(_rag_pm)
	else:
		_die_now(Vector3.DOWN, head_center(), 5.0, false)
	killed.emit(self)

## lying on the clips: the body's capsule laid from the hips to the neck
func _lie_hitbox() -> void:
	if reach == null or not reach.has_snap(_pelvis_bone) or not reach.has_snap(_neck_bone):
		return
	var sg := skel.global_transform
	var a := to_local(sg * reach.snap_of(_pelvis_bone).origin)
	var b := to_local(sg * reach.snap_of(_neck_bone).origin)
	var seg := b - a
	var ln := seg.length()
	if ln < 0.05:
		return
	var y := seg / ln
	var x := y.cross(Vector3.UP if absf(y.y) < 0.9 else Vector3.FORWARD).normalized()
	_cap.radius = 0.22 * _sc
	_cap.height = ln + _cap.radius * 2.0
	_body_cs.transform = Transform3D(Basis(x, y, x.cross(y)), (a + b) * 0.5)

## the ragdoll now, from the pose they are in; or, with no skeleton to build
## one on, the fallback topple (never left standing)
func _die_now(dir: Vector3, at: Vector3, dmg: float, head: bool) -> bool:
	if lean:
		lean.active = false
	if reach:
		reach.active = false
	if _ragdoll(dir, at, dmg, head):
		return true
	# no bodies and no clip: _dead_step tips the model over, away from the
	# round, rather than leaving them standing
	var ld := global_basis.inverse() * (dir if dir.length() > 0.001 else -global_basis.z)
	_fall = 1.0 if ld.z > 0.0 else -1.0
	if tree:
		tree.active = false
	return false

## A round that does not kill: kicks to the hit springs about where it went
## in, sized by the damage, plus a shove along its path and a check in the
## stride. The springs ride on top of the clips and the strike.
func _react(dmg: float, at: Vector3, dir: Vector3, head: bool) -> void:
	var dn := dir.normalized() if dir.length() > 0.001 else -global_basis.z
	var ld := global_basis.inverse() * dn        # the round's path, model space
	var lp := to_local(at)                        # where it went in
	var h := _height * _sc
	# a brute's bulk soaks a round that would rock anyone else
	var m := clampf(dmg / 35.0, 0.45, 1.5) * (0.6 if variant == "brute" else 1.0)
	var flat := Vector3(dn.x, 0.0, dn.z)
	if head:
		# the head snaps back along the round, the chest goes a little with it
		_fhv += _swing(lp - Vector3(0.0, h * 0.85, 0.0), ld) * 16.0 * m
		_ftv += _swing(lp - Vector3(0.0, h * 0.53, 0.0), ld) * 3.0 * m
		_knock += flat * 0.5 * m
		_stag_t = maxf(_stag_t, 0.4)
	elif lp.y < h * 0.48:
		# a leg: it gives - the body drops and pitches forward over it, the
		# stride checks hard, and they favour that leg from now on
		_leg_hurt = true
		_limp_side = 1.0 if lp.x >= 0.0 else -1.0
		_dip_v -= 0.9 * m
		_ftv += Vector3(2.8, 0.0, -_limp_side * 2.0) * m
		_knock += flat * 0.3 * m
		_stag_t = maxf(_stag_t, 0.7)
	else:
		# the body: the torso turns with the round about the hips, a hit
		# shoulder is thrown back on its own, and they are shoved a step
		_ftv += _swing(lp - Vector3(0.0, h * 0.53, 0.0), ld) * 6.5 * m
		# and a twist of its own, so no two hits read the same
		_ftv.y += randf_range(-1.5, 1.5) * m
		if lp.y > h * 0.68 and absf(lp.x) > h * 0.07:
			var sd := 1.0 if lp.x > 0.0 else -1.0
			var kick := _swing(lp - Vector3(sd * h * 0.12, h * 0.8, 0.0), ld) * 9.0 * m
			if sd > 0.0:
				_flv += kick
			else:
				_frv += kick
		_knock += flat * 1.3 * m
		_stag_t = maxf(_stag_t, 0.35)
	_knock = _knock.limit_length(2.2)
	# a heavy round breaks a wind-up; once the arm is coming it lands anyway
	if _atk_t >= 0.0 and _atk_t < _atk_contact * 0.7 and (head or m > 1.0):
		_cancel_strike()

## the hit springs and the dip of a stumble, onto the flinch layer
func _springs(dt: float) -> void:
	_ftv += (-_ft * FL_K - _ftv * FL_C) * dt
	_ft = (_ft + _ftv * dt).limit_length(0.7)
	_fhv += (-_fh * FL_K - _fhv * FL_C) * dt
	_fh = (_fh + _fhv * dt).limit_length(0.9)
	_flv += (-_fl * FL_K - _flv * FL_C) * dt
	_fl = (_fl + _flv * dt).limit_length(0.9)
	_frv += (-_fr * FL_K - _frv * FL_C) * dt
	_fr = (_fr + _frv * dt).limit_length(0.9)
	_dip_v += (-_dip * 120.0 - _dip_v * 11.0) * dt
	_dip = clampf(_dip + _dip_v * dt, -0.16, 0.05)
	if reach:
		reach.fl_torso = _ft
		reach.fl_head = _fh
		reach.fl_l = _fl
		reach.fl_r = _fr

## the turn a push along d gives a point at r from the pivot: about r x d,
## as strong as the push is square to the lever
static func _swing(r: Vector3, d: Vector3) -> Vector3:
	var ln := r.length()
	if ln < 0.001:
		return Vector3.ZERO
	return r.cross(d) / ln

func _cancel_strike() -> void:
	_atk_t = -1.0
	if _atk_clip and loco:
		loco.tree.set(loco.p_atk, AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
	_atk_clip = false

func _start_strike() -> void:
	_atk_t = 0.0
	_atk_fired = false
	attack_cd = 1.1              # one swing every 1.1 s, as the grab was
	_atk_grab = _rng.randf() < 0.22
	_atk_tempo = _rng.randf_range(0.85, 1.12) * (0.88 if variant == "brute" else 1.0)
	_atk_high = _rng.randf_range(1.3, 1.6)
	_atk_clip = false
	_atk_contact = CONTACT
	# an authored swing when there is one (a random take), over the upper
	# body so the legs keep walking in; it lands at its own hit frame
	if loco and anim.has_animation("attack"):
		var ac := Loco.variant(anim, "attack", _rng.randi() % 3)
		_atk_clip = true
		_atk_tempo = 1.0
		_atk_len = anim.get_animation(ac).length
		_atk_contact = Loco.hit_time(loco.key, ac, _atk_len)
		loco.fire_upper(ac)
	if not _atk_grab:
		_atk_side = -_atk_side   # left, right, left
	if Game.may_shout(0.3):
		_say("hostile-%d.mp3" % voice_idx, 0.0, randf_range(1.0, 1.1))

func _physics_process(dt: float) -> void:
	if state == "dead":
		dead_t += dt
		_dead_step(dt)
		if dead_t > 8.0:
			despawn()
		return
	if state == "idle" or target == null:
		return
	if state == "downed":
		_down_step(dt)
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
	# the strike starts a little outside arm's length, so the swing lands as
	# they arrive; backing right off during the wind-up makes them reset.
	# The damage is dealt at the moment of contact, if you are still there
	if _atk_t < 0.0 and attack_cd <= 0.0 and dist < REACH_M + maxf(_spd, 0.3) * CONTACT:
		_start_strike()
	elif _atk_t >= 0.0 and _atk_t < _atk_contact * 0.7 and dist > 2.8:
		_cancel_strike()
	if _atk_t >= _atk_contact and not _atk_fired:
		_atk_fired = true
		if dist < HIT_M and target.has_method("take_damage"):
			target.call("take_damage", 18.0, global_position)
	# hands drift up and forward only in the last metre and a half
	_near_w = smoothstep(REACH_M + 1.5, REACH_M + 0.1, dist) * 0.3
	if dist < REACH_M:
		state = "attack"
		velocity.x = _knock.x
		velocity.z = _knock.z
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
		# a round checks them for a beat, a leg hit for longer
		var sp := minf(speed, _limp_cap) * (1.0 - 0.65 * clampf(_stag_t / 0.35, 0.0, 1.0))
		velocity.x = d.x * sp + _knock.x
		velocity.z = d.z * sp + _knock.z
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
		want = atan2(velocity.x - _knock.x, velocity.z - _knock.z)
	elif dist > 0.01:
		want = atan2(to.x, to.z)
	_animate(dt, want, 9.0, target.global_position)

## Once per physics frame, after the body has moved: turn toward want_yaw at
## a limited rate (ease is how briskly), pace the clips off the distance the
## legs really covered, run the strike and the hit springs, drive the spine
## and head layer, and move the head hitbox onto the head. The head looks at
## look_at_p only inside look_max metres and ~100 degrees of the facing.
func _animate(dt: float, want_yaw: float, ease_k: float, look_at_p: Vector3, look_max := 15.0) -> void:
	var mv := global_position - _last_pos
	_last_pos = global_position
	mv.y = 0.0
	var inv_dt := 1.0 / maxf(dt, 0.0001)
	_vel = _vel.lerp(mv * inv_dt, clampf(dt * 12.0, 0.0, 1.0))
	# a round's shove is not a step: the legs pace only what they walked
	var walked := mv - Vector3(_knock.x, 0.0, _knock.z) * dt
	var v := minf(walked.length() * inv_dt, 9.0)
	_spd = lerpf(_spd, v, clampf(dt * 10.0, 0.0, 1.0))
	_knock *= maxf(0.0, 1.0 - dt * 7.0)
	_stag_t = maxf(0.0, _stag_t - dt)
	# a committed swing tracks you more slowly than a walk turns
	var turn := _turn * (0.45 if _atk_t >= _atk_contact * 0.7 else 1.0)
	var diff := wrapf(want_yaw - rotation.y, -PI, PI)
	var step := clampf(diff * clampf(dt * ease_k, 0.0, 1.0), -turn * dt, turn * dt)
	rotation.y = wrapf(rotation.y + step, -PI, PI)
	_yaw_vel = lerpf(_yaw_vel, step * inv_dt, clampf(dt * 8.0, 0.0, 1.0))
	if loco:
		if _gait_now() != _gait_key:
			_gait()
		# a fresh idle (and take) each time they come to a stop, and now and
		# then while they stand
		_idle_t -= dt
		if loco.amp > 0.6:
			_moving = true
		elif _moving and loco.amp < 0.3:
			_moving = false
			_idle_t = 0.0
		if _idle_t <= 0.0:
			_idle_t = _rng.randf_range(6.0, 14.0)
			loco.want(0, _pick_idle())
		loco.step(dt, _spd, _sc * _stride)
	# the strike: wind-up (arm cocked, torso twisted away, weight back),
	# the swing (arm whips across, torso twists through, a step in), recovery
	var atk_pitch := 0.0
	var lunge := 0.0
	var sw := 0.0
	var sk := 0.0
	var tw := 0.0
	if _atk_t >= 0.0 and _atk_clip:
		# the clip swings the arms; the body adds the step in at the blow
		_atk_t += dt
		lunge = 0.18 * sin(clampf(_atk_t / maxf(_atk_contact * 1.7, 0.1), 0.0, 1.0) * PI)
		if _atk_t >= _atk_len:
			_atk_t = -1.0
			_atk_clip = false
	elif _atk_t >= 0.0:
		_atk_t += dt * _atk_tempo
		var side := 0.0 if _atk_grab else _atk_side
		var reach_in := 0.36 if _atk_grab else 0.3
		if _atk_t < WIND:
			var u := smoothstep(0.0, WIND, _atk_t)
			sw = u
			tw = side * 0.45 * u
			atk_pitch = -0.1 * u
			lunge = -0.05 * u
		elif _atk_t < WIND + STRIKE:
			var u := (_atk_t - WIND) / STRIKE
			var e := u * u * (3.0 - 2.0 * u)
			sw = 1.0
			sk = e
			tw = lerpf(side * 0.45, -side * 0.4, e)
			atk_pitch = lerpf(-0.1, 0.25, e)
			lunge = lerpf(-0.05, reach_in, e)
		else:
			var u := clampf((_atk_t - WIND - STRIKE) / RECOVER, 0.0, 1.0)
			var e := 1.0 - u * u * (3.0 - 2.0 * u)
			sw = e
			sk = 1.0
			tw = -side * 0.4 * e
			atk_pitch = 0.25 * e
			lunge = reach_in * e
			if u >= 1.0:
				_atk_t = -1.0
	_springs(dt)
	if model:
		model.position = Vector3(0.0, _dip, lunge * _sc)
	if reach:
		reach.amount = lerpf(reach.amount, _near_w, clampf(dt * 6.0, 0.0, 1.0))
		reach.strike_w = sw
		reach.strike_k = sk
		reach.strike_side = _atk_side
		reach.grab = _atk_grab
		reach.twist = tw
		if sw > 0.0 and target:
			# from the shoulders to your face and chest, never behind them
			var tp := target.global_position + Vector3(0.0, _atk_high, 0.0)
			var a := global_basis.inverse() * (tp - (global_position + Vector3(0.0, _height * _sc * 0.8, 0.0)))
			a.z = maxf(a.z, 0.3)
			reach.aim = a.normalized()
	if lean:
		# spine: the stoop, into the run, banked into turns, the wind-up and
		# the swing; a bad leg leans them onto the other one
		var roll := clampf(-_yaw_vel * _spd * 0.02, -0.16, 0.16) - _limp_side * 0.05
		var tgt := Vector2(_hunch + clampf(_spd * 0.03, 0.0, 0.14) + atk_pitch, roll)
		_lean_v += ((tgt - _lean) * 140.0 - _lean_v * 17.0) * dt
		_lean += _lean_v * dt
		_lean = _lean.clamp(Vector2(-0.6, -0.5), Vector2(1.15, 0.5))
		# the head turns toward what they are watching, within a neck's reach,
		# only when it is near and roughly in front
		# past 40 m from you nobody can see a head turn: no look, and the
		# ragdoll pose is only kept every few frames
		var far := target != null and global_position.distance_squared_to(target.global_position) > 1600.0
		if reach:
			reach.far = far
		var lk := 0.0
		if not far:
			var tl := look_at_p - global_position
			var la := wrapf(atan2(tl.x, tl.z) - rotation.y, -PI, PI)
			if Vector2(tl.x, tl.z).length() < look_max and absf(la) < 1.75:
				lk = clampf(la, -1.1, 1.1)
		_look = lerpf(_look, lk, clampf(dt * 4.0, 0.0, 1.0))
		lean.pitch = _lean.x
		lean.roll = _lean.y
		lean.yaw = _look
	_sync_head()
