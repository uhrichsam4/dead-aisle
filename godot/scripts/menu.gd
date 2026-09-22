## Every full-screen card the web build had: the lobby, PAUSED, SETTINGS,
## YOU DIED and the MISSION COMPLETE rating. Built in code over the live
## world, and it keeps running while the tree is paused.
extends CanvasLayer

signal play_pressed
signal quit_to_menu

const RED := Color("c8352b")
const DIM := Color(0.008, 0.012, 0.008, 0.8)     # .screen background
const TXT := Color("e8e6dc")
const SUB := Color("8f957f")
const GREEN := Color("6fae5c")

var screens := {}
var current := ""
var _back_to := ""          # where DONE on settings returns to
var _rows := {}              # settings widgets by key
var _stat_lbls := {}
var _grade: Label
var _dead_stats: Label

func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_lobby()
	_build_pause()
	_build_settings()
	_build_dead()
	_build_win()
	show_screen("")

# ------------------------------------------------------------------ helpers

func _font(spacing: int, weight := 400) -> FontVariation:
	var f := FontVariation.new()
	f.base_font = ThemeDB.fallback_font
	f.spacing_glyph = spacing
	f.variation_embolden = 0.0 if weight < 700 else (0.6 if weight < 900 else 1.0)
	return f

func _lbl(text: String, size: int, color: Color, spacing := 0, weight := 400) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font(spacing, weight))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

## the web's .start: a hairline box that fills red on hover
func _btn(text: String, cb: Callable, big := false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", _font(6, 700))
	b.add_theme_font_size_override("font_size", 18 if big else 14)
	b.custom_minimum_size = Vector2(300 if big else 240, 60 if big else 48)
	for st in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1, 1, 1, 0.03) if st == "normal" else RED
		if big and st == "normal":
			sb.bg_color = RED.darkened(0.15)
		sb.border_color = Color("666666") if st == "normal" and not big else RED
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(2)
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_color_override("font_color", TXT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.pressed.connect(func():
		Game.play("gear_gopro_beep", -12.0, 1.25)
		cb.call())
	return b

## a .screen: full-rect dim with a centred column
func _screen(id: String, dim := true) -> VBoxContainer:
	var root := Control.new()
	root.name = id
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	if dim:
		var bg := ColorRect.new()
		bg.color = DIM
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		root.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 14)
	center.add_child(col)
	screens[id] = root
	return col

func _h1(text: String, color: Color) -> Label:
	var l := _lbl(text, 84, color, 18, 900)
	l.add_theme_constant_override("outline_size", 12)
	l.add_theme_color_override("font_outline_color", Color(color.r * 0.6, color.g * 0.2, color.b * 0.15, 0.45))
	return l

func _gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = h
	return c

func show_screen(id: String) -> void:
	current = id
	for k in screens:
		screens[k].visible = (k == id)
	# the HUD's banners and objectives would read through the dim
	var hud = get_parent().get("hud")
	if hud:
		hud.visible = id == "" and Game.phase != "menu"
	if id != "":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		var s: Control = screens[id]
		s.modulate.a = 0.0
		create_tween().tween_property(s, "modulate:a", 1.0, 0.25)

# ------------------------------------------------------------------ lobby

func _build_lobby() -> void:
	var root := Control.new()
	root.name = "lobby"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	screens["lobby"] = root
	# the web's #lobby-bg: dark top and bottom, the world clear in the middle
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.26, 0.58, 1.0])
	g.colors = PackedColorArray([Color(0.016, 0.027, 0.047, 0.72), Color(0.016, 0.027, 0.047, 0.12),
		Color(0.016, 0.027, 0.047, 0.10), Color(0.012, 0.02, 0.035, 0.9)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	var bg := TextureRect.new()
	bg.texture = gt
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)

	# top bar: brand + tabs
	var top := HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 28
	top.offset_top = 18
	top.add_theme_constant_override("separation", 30)
	root.add_child(top)
	var brand := _lbl("DEAD AISLE", 22, RED, 6, 900)
	brand.add_theme_constant_override("outline_size", 8)
	brand.add_theme_color_override("font_outline_color", Color(0.78, 0.2, 0.17, 0.25))
	top.add_child(brand)
	for t in [["PLAY", func(): pass], ["SETTINGS", func(): open_settings("lobby")]]:
		var tb := Button.new()
		tb.text = t[0]
		tb.flat = true
		tb.focus_mode = Control.FOCUS_NONE
		tb.add_theme_font_override("font", _font(3, 700))
		tb.add_theme_font_size_override("font_size", 13)
		tb.add_theme_color_override("font_color", Color.WHITE if t[0] == "PLAY" else Color("9aa08f"))
		tb.add_theme_color_override("font_hover_color", Color.WHITE)
		tb.pressed.connect(t[1])
		top.add_child(tb)

	# the play card, bottom centre
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	box.offset_left = -300
	box.offset_right = 300
	box.offset_top = -250
	box.offset_bottom = -60
	box.alignment = BoxContainer.ALIGNMENT_END
	box.add_theme_constant_override("separation", 16)
	root.add_child(box)
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.03, 0.05, 0.6)
	sb.border_color = Color(1, 1, 1, 0.08)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	card.add_theme_stylebox_override("panel", sb)
	box.add_child(card)
	var cv := VBoxContainer.new()
	card.add_child(cv)
	cv.add_child(_lbl("SOLO", 20, TXT, 6, 900))
	cv.add_child(_lbl("PARK AT TOPS · CLEAR THE STORE · GET ALL 4 SURVIVORS OUT", 12, SUB, 2))
	var play := _btn("PLAY", func(): play_pressed.emit(), true)
	play.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(play)

	var hint := _lbl("WASD MOVE · LMB FIRE · RMB AIM · R RELOAD · SHIFT SPRINT · E RADIO · ESC PAUSE", 12, Color("777c6c"), 2)
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.offset_left = -500
	hint.offset_right = 500
	hint.offset_top = -40
	root.add_child(hint)

# ------------------------------------------------------------------ pause

func _build_pause() -> void:
	var col := _screen("pause")
	col.add_child(_h1("PAUSED", Color("aaaabb")))
	col.add_child(_gap(30))
	for b in [["RESUME", resume], ["SETTINGS", func(): open_settings("pause")], ["QUIT TO MENU", func(): quit_to_menu.emit()]]:
		var btn := _btn(b[0], b[1])
		btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(btn)

func pause() -> void:
	get_tree().paused = true
	show_screen("pause")

func resume() -> void:
	get_tree().paused = false
	show_screen("")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

## Esc: pause in play, back out of settings, resume from pause
func _unhandled_input(e: InputEvent) -> void:
	if not e.is_action_pressed("pause"):
		return
	get_viewport().set_input_as_handled()
	match current:
		"settings":
			_close_settings()
		"pause":
			resume()
		"":
			if Game.phase in ["drive", "parking", "outside", "inside", "between"]:
				pause()

# ------------------------------------------------------------------ settings

func _build_settings() -> void:
	var col := _screen("settings")
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.04, 0.05, 0.92)
	sb.border_color = Color(1, 1, 1, 0.08)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size.x = 560
	col.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	v.add_child(_lbl("SETTINGS", 26, TXT, 8, 900))
	v.add_child(_lbl("SAVED ON THIS MACHINE", 10, Color("777c6c"), 3))
	var groups := [
		["AUDIO", [["master", "MASTER VOLUME", 0, 100, 1], ["music", "MUSIC", 0, 100, 1], ["sfx", "SOUND EFFECTS", 0, 100, 1]]],
		["CONTROLS", [["sens", "MOUSE SENSITIVITY", 20, 300, 5], ["invert", "INVERT LOOK"]]],
		["VIDEO", [["fov", "FIELD OF VIEW", 70, 110, 1], ["res", "RENDER QUALITY", 50, 200, 5],
			["shadows", "SHADOWS"], ["fx", "BODYCAM FILTER"]]],
	]
	for grp in groups:
		var gl := _lbl(grp[0], 11, RED, 4, 700)
		gl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		v.add_child(_gap(4))
		v.add_child(gl)
		for r in grp[1]:
			v.add_child(_setting_row(r))
	v.add_child(_gap(8))
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 12)
	v.add_child(btns)
	for b in [["RESET", _reset_settings], ["DONE", _close_settings]]:
		var btn := _btn(b[0], b[1])
		btn.custom_minimum_size = Vector2(0, 44)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btns.add_child(btn)

func _setting_row(r: Array) -> Control:
	var key: String = r[0]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var lab := _lbl(r[1], 12, Color("b9bcae"), 2)
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	lab.custom_minimum_size.x = 200
	row.add_child(lab)
	if r.size() > 2:
		var s := HSlider.new()
		s.min_value = r[2]
		s.max_value = r[3]
		s.step = r[4]
		s.focus_mode = Control.FOCUS_NONE
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(s)
		var val := _lbl("", 12, TXT, 1)
		val.custom_minimum_size.x = 56
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(val)
		s.value_changed.connect(func(x: float):
			Game.settings[key] = int(x)
			val.text = _fmt(key, int(x))
			Game.apply_settings())
		s.drag_ended.connect(func(_c): Game.save_settings())
		_rows[key] = [s, val]
	else:
		var t := CheckButton.new()
		t.focus_mode = Control.FOCUS_NONE
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t.alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(t)
		t.toggled.connect(func(on: bool):
			Game.settings[key] = on
			Game.apply_settings()
			Game.save_settings())
		_rows[key] = [t, null]
	return row

func _fmt(key: String, v: int) -> String:
	match key:
		"sens", "res", "master", "music", "sfx":
			return "%d%%" % v
		"fov":
			return "%d°" % v
	return str(v)

func _sync_settings() -> void:
	for key in _rows:
		var w = _rows[key][0]
		if w is HSlider:
			(w as HSlider).set_value_no_signal(float(Game.settings[key]))
			(_rows[key][1] as Label).text = _fmt(key, int(Game.settings[key]))
		else:
			(w as CheckButton).set_pressed_no_signal(bool(Game.settings[key]))

func open_settings(from: String) -> void:
	_back_to = from
	_sync_settings()
	show_screen("settings")

func _reset_settings() -> void:
	Game.reset_settings()
	_sync_settings()

func _close_settings() -> void:
	Game.save_settings()
	show_screen(_back_to)

# ------------------------------------------------------------------ end cards

func _build_dead() -> void:
	var col := _screen("dead")
	col.add_child(_h1("YOU DIED", Color("8f2018")))
	col.add_child(_lbl("OVERRUN", 13, SUB, 8))
	col.add_child(_gap(20))
	_dead_stats = _lbl("", 13, Color("b9bcae"), 2)
	col.add_child(_dead_stats)
	col.add_child(_gap(24))
	for b in [["RE-DEPLOY", func(): _redeploy(true)], ["MENU", func(): _redeploy(false)]]:
		var btn := _btn(b[0], b[1])
		btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(btn)

func show_dead(where: String) -> void:
	_dead_stats.text = "DIED AT  %s\nKILLS  %d   ·   POINTS  %d" % [where, Game.kills, Game.points]
	show_screen("dead")

func _build_win() -> void:
	var col := _screen("win")
	col.add_child(_h1("MISSION COMPLETE", RED))
	col.add_child(_lbl("ALL SURVIVORS EXTRACTED", 13, Color("8fae84"), 8))
	_grade = _lbl("S", 150, Color(0, 0, 0, 0), 0, 900)
	_grade.add_theme_constant_override("outline_size", 10)
	col.add_child(_grade)
	col.add_child(_lbl("RATING", 10, Color("777c6c"), 6))
	col.add_child(_gap(16))
	var stats := HBoxContainer.new()
	stats.alignment = BoxContainer.ALIGNMENT_CENTER
	stats.add_theme_constant_override("separation", 34)
	col.add_child(stats)
	for k in ["KILLS", "HEADSHOTS", "ACCURACY", "SURVIVORS", "TIME", "POINTS"]:
		var cell := VBoxContainer.new()
		cell.add_child(_lbl(k, 10, Color("777c6c"), 3))
		var v := _lbl("—", 22, TXT, 1, 700)
		cell.add_child(v)
		stats.add_child(cell)
		_stat_lbls[k] = v
	col.add_child(_gap(24))
	var btn := _btn("REDEPLOY", func(): _redeploy(true))
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(btn)
	var mb := _btn("MENU", func(): _redeploy(false))
	mb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(mb)

## the web's esGrade: survivors first, then how clean the shooting was
func show_win() -> void:
	var acc := 100.0 * Game.hits / maxf(1.0, Game.shots)
	var s := int(Game.run_time)
	_stat_lbls.KILLS.text = str(Game.kills)
	_stat_lbls.HEADSHOTS.text = str(Game.headshots)
	_stat_lbls.ACCURACY.text = "%d%%" % roundi(acc) if Game.shots > 0 else "—"
	_stat_lbls.SURVIVORS.text = "%d/4" % Game.saved
	_stat_lbls.TIME.text = "%d:%02d" % [s / 60, s % 60]
	_stat_lbls.POINTS.text = str(Game.points)
	var g := ["C", Color("a33b32")]
	if Game.saved >= 4 and acc >= 45.0:
		g = ["S", Color("ffd76a")]
	elif Game.saved >= 3 and acc >= 35.0:
		g = ["A", GREEN]
	elif Game.saved >= 2:
		g = ["B", Color("e0a83c")]
	_grade.text = g[0]
	_grade.add_theme_color_override("font_outline_color", g[1])
	show_screen("win")
	# the letter lands a beat after the card, with a little overshoot
	_grade.scale = Vector2.ZERO
	await get_tree().process_frame           # laid out, so the pivot is the middle
	_grade.pivot_offset = _grade.size / 2.0
	var tw := create_tween()
	tw.tween_interval(0.35)
	tw.tween_property(_grade, "scale", Vector2.ONE, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func(): Game.play("gear_gopro_on", -6.0))

func _redeploy(quick: bool) -> void:
	get_tree().paused = false
	Game.reset_run()
	Game.quick_deploy = quick
	get_tree().reload_current_scene()
