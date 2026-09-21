## A survivor: hiding in a corner of the store until you reach them, then
## following you out. The web build drew these as block figures; here they are
## real people (the civilian rig, recoloured) with a green marker overhead so
## you do not mistake them for a hostile in the dark.
extends CharacterBody3D

const U := preload("res://scripts/util.gd")

signal found(s: Node)

var state := "hiding"        # hiding | following | out
var target: Node3D
var home := Vector3.ZERO
var model: Node3D
var anim: AnimationPlayer
var marker: MeshInstance3D
var voice: AudioStreamPlayer3D
var fear := 0.25
var _whimper_cd := 3.0
var _anim_now := ""
var _t := 0.0

func _ready() -> void:
	collision_layer = 16
	collision_mask = 1
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.7
	cs.shape = cap
	cs.position.y = 0.85
	add_child(cs)
	var lib := U.glb("res://assets/hostile.glb")
	if lib:
		model = lib.duplicate() as Node3D
		add_child(model)
		_fit(1.72)
		_civilian_look()
		anim = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).extra_cull_margin = 1.5
	marker = MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.1
	cone.bottom_radius = 0.0
	cone.height = 0.18
	cone.radial_segments = 4
	marker.mesh = cone
	marker.material_override = U.emissive_mat(Color(0.27, 1.0, 0.4), 2.5)
	marker.position.y = 2.15
	add_child(marker)
	voice = AudioStreamPlayer3D.new()
	voice.position.y = 1.5
	voice.unit_size = 3.0
	voice.max_distance = 16.0
	add_child(voice)

func _fit(target_h: float) -> void:
	var skels := model.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		return
	var sk := skels[0] as Skeleton3D
	var to_model := model.global_transform.affine_inverse() * sk.global_transform
	var lo := INF
	var hi := -INF
	for b in sk.get_bone_count():
		var y := (to_model * sk.get_bone_global_rest(b)).origin.y
		lo = minf(lo, y)
		hi = maxf(hi, y)
	if hi - lo <= 0.01:
		return
	var s := target_h * 0.88 / (hi - lo)
	model.scale = Vector3.ONE * s
	model.position.y = -lo * s + 0.06

## same person as a hostile underneath, so dress them differently: a lighter
## shirt and a warmer skin, never the hostiles' black suit
func _civilian_look() -> void:
	# work shirts and hi-vis: staff and shoppers, never the hostiles' black
	var shirts := [Color(0.85, 0.72, 0.36), Color(0.36, 0.52, 0.78), Color(0.78, 0.36, 0.3), Color(0.9, 0.85, 0.2)]
	var shirt: Color = shirts[randi() % shirts.size()]
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i)
			if m is StandardMaterial3D:
				var c := (m as StandardMaterial3D).duplicate() as StandardMaterial3D
				var nm := c.resource_name.to_lower()
				if nm.contains("suit"):          # short04 is the HAIR, not shorts
					# the texture is a black jumper, and tinting multiplies - black
					# times any colour is still black. Take the texture off and
					# keep the normal map for the folds.
					c.albedo_texture = null
					c.albedo_color = shirt
				mi.set_surface_override_material(i, c)

func place(pos: Vector3, tgt: Node3D) -> void:
	home = pos
	global_position = pos
	target = tgt
	state = "hiding"
	rotation.y = randf() * TAU
	marker.visible = true
	_play("idle")

func _play(n: String, blend := 0.25, rate := 1.0) -> void:
	if anim == null or not anim.has_animation(n):
		return
	if _anim_now != n:
		anim.play(n, blend, rate)
		_anim_now = n
		if n == "idle":
			anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
		elif n == "run":
			anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	anim.speed_scale = rate

func _physics_process(dt: float) -> void:
	_t += dt
	if target == null or state == "out":
		return
	var to := target.global_position - global_position
	to.y = 0.0
	var d := to.length()
	marker.position.y = 2.15 + sin(_t * 3.0) * 0.05
	marker.rotation.y += dt * 2.0
	if state == "hiding":
		# nearest live hostile sets how frightened they are
		var near := 999.0
		for h in get_tree().get_nodes_in_group("hostiles"):
			if h.is_active():
				near = minf(near, (h as Node3D).global_position.distance_to(global_position))
		fear = lerpf(fear, 1.0 if near < 6.0 else 0.25, clampf(dt * 3.0, 0.0, 1.0))
		_whimper_cd -= dt
		if near < 6.0 and _whimper_cd <= 0.0:
			_whimper_cd = randf_range(2.6, 6.5)
			_say("sfx-breath.mp3", -6.0, randf_range(1.15, 1.35))   # short frightened breaths
		# they shake while they hide
		if model:
			model.rotation.z = sin(_t * 23.0) * 0.012 * fear
		_play("idle", 0.3, 0.6)
		if d < 1.6:
			state = "following"
			marker.visible = false
			_say("sfx-breath.mp3", -2.0, 1.0)
			found.emit(self)
	elif state == "following":
		if d > 2.2:
			var dir := to / maxf(d, 0.001)
			# do not bunch up on each other
			for o in get_tree().get_nodes_in_group("survivors"):
				if o == self:
					continue
				var away := global_position - (o as Node3D).global_position
				away.y = 0.0
				var od := away.length()
				if od < 0.9 and od > 0.001:
					dir += away / od * 0.5
			dir = dir.normalized()
			var spd := 4.2 if d > 5.0 else 2.6
			velocity.x = dir.x * spd
			velocity.z = dir.z * spd
			_play("run", 0.25, spd / 3.0)
		else:
			velocity.x = 0.0
			velocity.z = 0.0
			_play("idle", 0.3)
		if not is_on_floor():
			velocity.y -= 18.0 * dt
		else:
			velocity.y = 0.0
		move_and_slide()
		if model:
			model.rotation.z = 0.0
		rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), clampf(dt * 6.0, 0.0, 1.0))

func _say(file: String, vol_db: float, pitch: float) -> void:
	var st := Game.file(file)
	if st == null:
		return
	voice.stream = st
	voice.volume_db = vol_db
	voice.pitch_scale = pitch
	voice.play()
