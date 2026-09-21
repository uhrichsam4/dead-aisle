## The HUD, drawn over the lens: objectives, health, ammo, crosshair, the
## GoPro OSD, banners and the damage flash. Built in code, no scene needed.
extends CanvasLayer

var obj_box: VBoxContainer
var obj_rows := {}
var hp_bar: ColorRect
var hp_back: ColorRect
var ammo: Label
var wname: Label
var banner_t: Label
var banner_s: Label
var hint: Label
var rec: Label
var clock: Label
var flash: ColorRect
var cross: Control
var hitmark: Label
var center_msg: Label
var radio_lbl: Label
var _radio_t := 0.0
var _banner_timer := 0.0
var _hit_t := 0.0
var _t := 0.0

func _ready() -> void:
	layer = 3
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	flash = ColorRect.new()
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.color = Color(0.6, 0, 0, 0)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(flash)

	# objectives, top left
	var panel := PanelContainer.new()
	panel.position = Vector2(24, 22)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.42)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", sb)
	root.add_child(panel)
	obj_box = VBoxContainer.new()
	panel.add_child(obj_box)
	var head := _lbl("OBJECTIVES", 13, Color(1, 1, 1, 0.55))
	obj_box.add_child(head)

	# GoPro OSD, top right
	rec = _lbl("● REC", 20, Color(1, 0.2, 0.18))
	rec.position = Vector2(0, 22)
	rec.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	rec.offset_left = -250
	rec.offset_right = -24
	rec.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(rec)
	clock = _lbl("", 16, Color(1, 1, 1, 0.85))
	clock.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	clock.offset_left = -330
	clock.offset_right = -24
	clock.offset_top = 50
	clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(clock)

	# health, bottom left
	hp_back = ColorRect.new()
	hp_back.color = Color(0, 0, 0, 0.5)
	hp_back.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hp_back.offset_left = 24
	hp_back.offset_top = -46
	hp_back.offset_right = 284
	hp_back.offset_bottom = -32
	root.add_child(hp_back)
	hp_bar = ColorRect.new()
	hp_bar.color = Color(0.85, 0.92, 0.88)
	hp_bar.position = Vector2(2, 2)
	hp_bar.size = Vector2(256, 10)
	hp_back.add_child(hp_bar)

	# ammo, bottom right
	ammo = _lbl("30 / 30", 34, Color(1, 1, 1))
	ammo.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ammo.offset_left = -300
	ammo.offset_top = -86
	ammo.offset_right = -28
	ammo.offset_bottom = -40
	ammo.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(ammo)
	wname = _lbl("", 14, Color(1, 1, 1, 0.6))
	wname.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	wname.offset_left = -300
	wname.offset_top = -40
	wname.offset_right = -28
	wname.offset_bottom = -18
	wname.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(wname)

	# crosshair: four ticks and a hitmarker
	cross = Control.new()
	cross.set_anchors_preset(Control.PRESET_CENTER)
	cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cross)
	for r in [Rect2(-1, -14, 2, 8), Rect2(-1, 6, 2, 8), Rect2(-14, -1, 8, 2), Rect2(6, -1, 8, 2)]:
		var t := ColorRect.new()
		t.color = Color(1, 1, 1, 0.8)
		t.position = r.position
		t.size = r.size
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cross.add_child(t)
	hitmark = _lbl("✕", 26, Color(1, 1, 1, 0))
	hitmark.position = Vector2(-9, -18)
	cross.add_child(hitmark)

	# banner, centre
	banner_t = _lbl("", 64, Color(0.86, 0.22, 0.18))
	banner_t.set_anchors_preset(Control.PRESET_CENTER_TOP)
	banner_t.offset_left = -700
	banner_t.offset_right = 700
	banner_t.offset_top = 250
	banner_t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_t.add_theme_constant_override("outline_size", 8)
	banner_t.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	root.add_child(banner_t)
	banner_s = _lbl("", 20, Color(1, 1, 1, 0.8))
	banner_s.set_anchors_preset(Control.PRESET_CENTER_TOP)
	banner_s.offset_left = -700
	banner_s.offset_right = 700
	banner_s.offset_top = 340
	banner_s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(banner_s)

	hint = _lbl("", 15, Color(1, 1, 1, 0.6))
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.offset_left = -600
	hint.offset_right = 600
	hint.offset_top = -44
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(hint)

	center_msg = _lbl("", 22, Color(1, 1, 1, 0.9))
	center_msg.set_anchors_preset(Control.PRESET_CENTER)
	center_msg.offset_left = -500
	center_msg.offset_right = 500
	center_msg.offset_top = 60
	center_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(center_msg)

	radio_lbl = _lbl("", 18, Color(1, 0.85, 0.5))
	radio_lbl.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	radio_lbl.offset_left = -400
	radio_lbl.offset_right = 400
	radio_lbl.offset_top = -80
	radio_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(radio_lbl)
	Game.banner.connect(show_banner)
	Game.objective.connect(set_objective)

func _lbl(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.5))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func set_objectives(rows: Array) -> void:
	for id in obj_rows:
		obj_rows[id].queue_free()
	obj_rows.clear()
	for r in rows:
		var l := _lbl("   " + r[1], 15, Color(1, 1, 1, 0.4))
		obj_box.add_child(l)
		obj_rows[r[0]] = l

func set_objective(id: String, state: String) -> void:
	if not obj_rows.has(id):
		return
	var l: Label = obj_rows[id]
	var base := l.text.substr(3)
	match state:
		"active":
			l.text = "▸  " + base
			l.add_theme_color_override("font_color", Color(1, 0.86, 0.45))
		"done":
			l.text = "✓  " + base
			l.add_theme_color_override("font_color", Color(0.55, 0.85, 0.6, 0.7))
		_:
			l.text = "   " + base
			l.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))

func show_banner(title: String, sub := "") -> void:
	banner_t.text = title
	banner_s.text = sub
	banner_t.modulate.a = 1.0
	banner_s.modulate.a = 1.0
	_banner_timer = 3.6

func set_hp(hp: float, max_hp: float) -> void:
	var k := clampf(hp / max_hp, 0.0, 1.0)
	hp_bar.size.x = 256.0 * k
	hp_bar.color = Color(0.85, 0.92, 0.88) if k > 0.35 else Color(0.95, 0.3, 0.25)

func set_ammo(mag: int, mag_size: int, weapon_name: String) -> void:
	ammo.text = "%d / %d" % [mag, mag_size]
	ammo.add_theme_color_override("font_color", Color(1, 0.35, 0.3) if mag <= 5 else Color(1, 1, 1))
	wname.text = weapon_name

func on_damage(_from: Vector3) -> void:
	flash.color.a = 0.32

func on_hit(headshot: bool, kill: bool) -> void:
	hitmark.add_theme_color_override("font_color", Color(1, 0.3, 0.25) if kill else Color(1, 1, 1))
	hitmark.modulate.a = 1.0
	_hit_t = 0.18 if not headshot else 0.3

func set_radio(t: String) -> void:
	radio_lbl.text = t
	radio_lbl.modulate.a = 1.0
	_radio_t = 3.0

func set_hint(t: String) -> void:
	hint.text = t

func set_center(t: String) -> void:
	center_msg.text = t

func show_combat_hud(on: bool) -> void:
	cross.visible = on
	ammo.visible = on
	wname.visible = on
	hp_back.visible = on

func _process(dt: float) -> void:
	_t += dt
	flash.color.a = maxf(0.0, flash.color.a - dt * 0.9)
	# the end cards carry the "click to redeploy" prompt, so they stay up
	if _banner_timer > 0.0 and Game.phase not in ["dead", "win"]:
		_banner_timer -= dt
		if _banner_timer < 1.0:
			banner_t.modulate.a = maxf(0.0, _banner_timer)
			banner_s.modulate.a = maxf(0.0, _banner_timer)
	_hit_t = maxf(0.0, _hit_t - dt)
	if _radio_t > 0.0:
		_radio_t -= dt
		radio_lbl.modulate.a = clampf(_radio_t, 0.0, 1.0)
	hitmark.modulate.a = clampf(_hit_t / 0.18, 0.0, 1.0)
	rec.modulate.a = 1.0 if fmod(_t, 1.2) < 0.8 else 0.25
	var s := int(Game.run_time)
	clock.text = "GoPro · 4K · 60   %02d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]
