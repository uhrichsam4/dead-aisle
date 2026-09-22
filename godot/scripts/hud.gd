## The web build's HUD, element for element: the same positions (CSS px),
## Helvetica Neue at the same sizes and letter-spacing, the same colours and
## the same text. Sections are named after the DOM ids they replace
## (#objpanel, #hud-top, #points, #feed, #healbar-wrap, #ammo, #xh, #hm,
## #banner, #hint, #dmg, #goprohud, #phonefx, #radio-dial, survivor badges).
extends CanvasLayer

var player: Node          # set by main: crosshair spread, reload state
var car: Node             # set by main: the radio dial

# ---------------------------------------------------------------- fonts

static var _fonts := {}
static func font(weight := 400, italic := false, mono := false, spacing := 0.0) -> Font:
	var key := "%d%s%s%.2f" % [weight, italic, mono, spacing]
	if _fonts.has(key):
		return _fonts[key]
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["Menlo", "Consolas", "Courier New"] if mono else ["Helvetica Neue", "Arial"])
	sf.font_weight = weight
	sf.font_italic = italic
	var fv := FontVariation.new()
	fv.base_font = sf
	fv.spacing_glyph = roundi(spacing)
	_fonts[key] = fv
	return fv

## a Label styled the way the web styles text: size, colour, letter-spacing,
## weight, and a hard black text-shadow
func L(txt: String, px: int, color: Color, spacing := 0.0, weight := 400, shadow := true, italic := false, mono := false) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_override("font", font(weight, italic, mono, spacing))
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", color)
	if shadow:
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
		l.add_theme_constant_override("shadow_offset_x", 0)
		l.add_theme_constant_override("shadow_offset_y", 1)
		l.add_theme_constant_override("shadow_outline_size", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func box(parent: Control, bg: Color, border: Color, radius := 0.0, bw := 1) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(int(radius))
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(p)
	return p

func rect(parent: Control, color: Color, pos: Vector2, sz: Vector2) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.position = pos
	r.size = sz
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	return r

func circle(parent: Control, d: float, color: Color, border := Color(0, 0, 0, 0)) -> Panel:
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(int(ceil(d / 2.0)))
	if border.a > 0.0:
		sb.border_color = border
		sb.set_border_width_all(1)
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(d, d)
	p.size = Vector2(d, d)
	p.pivot_offset = Vector2(d, d) / 2.0
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(p)
	return p

func radial(stops: Array) -> GradientTexture2D:
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for s in stops:
		offs.append(s[0])
		cols.append(s[1])
	g.offsets = offs
	g.colors = cols
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 1.0)       # CSS 'ellipse at center': 100% at the corners
	return t

func _gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

func _hline() -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(1, 1, 1, 0.09)
	r.custom_minimum_size = Vector2(0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

# ---------------------------------------------------------------- state

var root: Control
var dmg: TextureRect
var dmg_flash := 0.0
var _hp := 100.0
var heal_fill: ColorRect
var ammo_mag: Label
var ammo_res: Label
var wname: Label
var round_chip: Label
var wave_label: Label
var wave_num: Label
var points_val: Label
var feed: Control
var xh: Control
var xh_lines: Array[ColorRect] = []
var hm: Control
var hm_spans: Array[ColorRect] = []
var _hm_t := 0.0
var banner_box: VBoxContainer
var banner_h: Label
var banner_p: Label
var _banner_t := 0.0
var hint: Label
var obj_panel: PanelContainer
var obj_list: VBoxContainer
var obj_rows := {}
var obj_threat: Label
var gopro: Control
var gp_tc: Label
var gp_temp: Label
var gp_live: PanelContainer
var gp_dots: Array[Panel] = []
var _gp_on := false
var _gp_sec := 0.0
var phone: PanelContainer
var pf_chat: VBoxContainer
var pf_count: Label
var pf_hn: Label
var pf_dot: Panel
var _stream := false
var _chat_t := 0.0
var _view_t := 0.0
var _heart_t := 0.0
var _viewers := 3
var _hearts := 142
var _msg_i := 0
var _user_i := 0
var radio_dial: PanelContainer
var radio_rows: Array[Label] = []
var radio_foot: Label
var badges: Control
var badge_lbls: Array[Label] = []
var _combat := false
var _t := 0.0

const GP_MSGS := ["BRO RUN", "chat is this real", "W streamer", "behind you!!", "clip that", "first", "go go go"]
const GP_USERS := [["grimbyte", "#ff6b81"], ["xQcCousin", "#7dd3fc"], ["lane_rat", "#fcd34d"],
	["ttv_novaa", "#a7f3d0"], ["doomer_dan", "#f0abfc"], ["snaccident", "#fdba74"],
	["yeetfleet", "#93c5fd"], ["mom_its_me", "#fda4af"]]

func _ready() -> void:
	layer = 3
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_dmg()
	_build_badges()
	_build_objpanel()
	_build_top()
	_build_points()
	_build_feed()
	_build_health()
	_build_ammo()
	_build_crosshair()
	_build_banner()
	_build_hint()
	_build_radio()
	_build_gopro()
	_build_phone()
	Game.banner.connect(show_banner)
	Game.objective.connect(set_objective)
	Game.points_changed.connect(_on_points)
	Game.phase_changed.connect(_on_phase)
	_on_points(Game.points, "", false)
	round_chip.text = "ROUND %d" % Game.round

# ---------------------------------------------------------------- #dmg

func _build_dmg() -> void:
	# radial-gradient(ellipse at center, transparent 34%, rgba(140,0,0,.55) 78%, rgba(90,0,0,.85) 100%)
	dmg = TextureRect.new()
	dmg.texture = radial([[0.0, Color(0.55, 0, 0, 0)], [0.34, Color(0.55, 0, 0, 0)],
		[0.78, Color(140 / 255.0, 0, 0, 0.55)], [1.0, Color(90 / 255.0, 0, 0, 0.85)]])
	dmg.set_anchors_preset(Control.PRESET_FULL_RECT)
	dmg.stretch_mode = TextureRect.STRETCH_SCALE
	dmg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dmg.modulate.a = 0.0
	root.add_child(dmg)

# ---------------------------------------------------------------- #objpanel

func _build_objpanel() -> void:
	obj_panel = box(root, Color(6 / 255.0, 8 / 255.0, 6 / 255.0, 0.55), Color(1, 1, 1, 0.12))
	var sb: StyleBoxFlat = obj_panel.get_theme_stylebox("panel")
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 9
	obj_panel.position = Vector2(28, 64)
	obj_panel.custom_minimum_size = Vector2(240, 0)
	obj_panel.size = Vector2(240, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	obj_panel.add_child(v)
	v.add_child(L("OBJECTIVES", 10, Color("8b917f"), 5, 700))
	v.add_child(_gap(5))
	v.add_child(_hline())
	v.add_child(_gap(6))
	obj_list = VBoxContainer.new()
	obj_list.add_theme_constant_override("separation", 0)
	obj_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(obj_list)
	v.add_child(_gap(8))
	v.add_child(_hline())
	v.add_child(_gap(6))
	obj_threat = L("THREATS: 0", 10, Color("aa3333"), 3, 400, true, false, true)
	v.add_child(obj_threat)

func set_objectives(rows: Array) -> void:
	for id in obj_rows:
		(obj_rows[id].row as Node).queue_free()
	obj_rows.clear()
	for r in rows:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var dot_holder := CenterContainer.new()
		dot_holder.custom_minimum_size = Vector2(7, 16)
		dot_holder.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		dot_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(dot_holder)
		var dot := circle(dot_holder, 7, Color(0, 0, 0, 0), Color("6d7266"))
		var txt := RichTextLabel.new()
		txt.bbcode_enabled = true
		txt.fit_content = true
		txt.scroll_active = false
		txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		txt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		txt.add_theme_font_override("normal_font", font(400, false, false, 2))
		txt.add_theme_font_size_override("normal_font_size", 11)
		txt.add_theme_constant_override("line_separation", 3)
		txt.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
		txt.add_theme_constant_override("shadow_offset_y", 1)
		txt.add_theme_constant_override("shadow_outline_size", 2)
		row.add_child(txt)
		var pad := MarginContainer.new()
		pad.add_theme_constant_override("margin_top", 3)
		pad.add_theme_constant_override("margin_bottom", 3)
		pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pad.add_child(row)
		obj_list.add_child(pad)
		obj_rows[r[0]] = {"row": pad, "dot": dot, "txt": txt, "text": r[1], "state": "pending"}
		_paint_objective(r[0])

func set_objective(id: String, state: String) -> void:
	if not obj_rows.has(id) or state not in ["pending", "active", "done"]:
		return
	obj_rows[id].state = state
	_paint_objective(id)

func _paint_objective(id: String) -> void:
	var o: Dictionary = obj_rows[id]
	var dot: Panel = o.dot
	var sb: StyleBoxFlat = dot.get_theme_stylebox("panel")
	var txt: RichTextLabel = o.txt
	match o.state:
		"pending":
			sb.bg_color = Color(0, 0, 0, 0)
			sb.border_color = Color("6d7266")
			dot.scale = Vector2.ONE
			dot.modulate.a = 1.0
			txt.text = "[color=#9aa08f]%s[/color]" % o.text
		"active":
			sb.bg_color = Color("ffd76a")
			sb.border_color = Color("ffd76a")
			txt.text = "[color=#e8e6dc]%s[/color]" % o.text
		"done":
			sb.bg_color = Color("9fb08a")
			sb.border_color = Color("9fb08a")
			dot.scale = Vector2.ONE
			dot.modulate.a = 0.75
			txt.text = "[color=#777c6c][s]%s[/s][/color] [color=#9fb08a]✓[/color]" % o.text

## setThreatCount + the #wave-num readout
func set_threats(n: int) -> void:
	obj_threat.text = "THREATS: %d" % n
	if Game.phase in ["outside", "inside"]:
		wave_num.text = "%02d" % n

# ---------------------------------------------------------------- #hud-top

func _build_top() -> void:
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_CENTER_TOP)
	v.offset_left = -200
	v.offset_right = 200
	v.offset_top = 24
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(v)
	round_chip = L("ROUND 1", 10, Color("f6d434"), 5, 800)
	round_chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(round_chip)
	v.add_child(_gap(5))
	wave_label = L("OBJECTIVE", 12, Color("aa3333"), 6)
	wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(wave_label)
	wave_num = L("—", 40, Color("d8d5c8"), 2, 800)
	wave_num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(wave_num)

# ---------------------------------------------------------------- #points / #feed

func _build_points() -> void:
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	v.offset_left = -236
	v.offset_right = -36
	v.offset_top = 26
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(v)
	points_val = L("500", 26, Color("e8e6dc"), 0, 700)
	points_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(points_val)
	var lab := L("POINTS", 10, Color("9aa08f"), 4)
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(lab)

func _build_feed() -> void:
	feed = Control.new()
	feed.position = Vector2(28, 86)
	feed.size = Vector2(400, 200)
	feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(feed)

func _on_points(total: int, label: String, head: bool) -> void:
	points_val.text = str(total)
	if label == "":
		return
	# newest on top, five at most, each rises and fades over a second
	for c in feed.get_children():
		c.set_meta("slot", int(c.get_meta("slot")) + 1)
	var l := L(label, 16, Color("ff9d3b") if head else Color("ffd76a"), 0, 700)
	l.set_meta("slot", 0)
	l.set_meta("t", 0.0)
	feed.add_child(l)
	while feed.get_child_count() > 5:
		var oldest: Node = null
		for c in feed.get_children():
			if oldest == null or int(c.get_meta("slot")) > int(oldest.get_meta("slot")):
				oldest = c
		feed.remove_child(oldest)
		oldest.queue_free()

func _tick_feed(dt: float) -> void:
	for c in feed.get_children():
		var t: float = float(c.get_meta("t")) + dt
		c.set_meta("t", t)
		# @keyframes feedup: 0% {0, +8px} 12% {1, 0} 80% {1} 100% {0, -14px}
		var a := 1.0
		var dy := 0.0
		if t < 0.12:
			a = t / 0.12
			dy = 8.0 * (1.0 - t / 0.12)
		elif t > 0.8:
			a = 1.0 - (t - 0.8) / 0.2
			dy = -14.0 * (t - 0.8) / 0.2
		(c as Control).modulate.a = clampf(a, 0.0, 1.0)
		(c as Control).position = Vector2(0, int(c.get_meta("slot")) * 20 + dy)
		if t >= 1.0:
			c.queue_free()

# ---------------------------------------------------------------- #healbar-wrap / #ammo

func _build_health() -> void:
	var lab := L("VITALS", 10, Color("cfd3c8"), 3)
	lab.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	lab.offset_left = 28
	lab.offset_top = -49
	lab.offset_bottom = -37
	root.add_child(lab)
	var bar := box(root, Color(1, 1, 1, 0.09), Color(1, 1, 1, 0.16))
	bar.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	bar.offset_left = 28
	bar.offset_right = 248
	bar.offset_top = -32
	bar.offset_bottom = -26
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(holder)
	heal_fill = rect(holder, Color("9fb08a"), Vector2(0, 0), Vector2(218, 4))

func set_hp(hp: float, max_hp: float) -> void:
	_hp = hp / max_hp * 100.0
	heal_fill.size.x = 218.0 * clampf(_hp / 100.0, 0.0, 1.0)
	heal_fill.color = Color("9fb08a") if _hp > 60 else (Color("c9a24a") if _hp > 30 else Color("c8352b"))

func _build_ammo() -> void:
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	v.offset_left = -332
	v.offset_right = -32
	v.offset_top = -110
	v.offset_bottom = -20
	v.alignment = BoxContainer.ALIGNMENT_END
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(v)
	ammo_mag = L("30", 44, Color("e8e6dc"), 1, 800)
	ammo_res = L("RESERVE ∞", 15, Color("9aa08f"), 2)
	wname = L("AK-74 TACTICAL", 11, Color("8b917f"), 4)
	for l in [ammo_mag, ammo_res]:
		(l as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		v.add_child(l)
	v.add_child(_gap(4))
	wname.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(wname)

func set_ammo(mag: int, _mag_size: int, weapon_name: String) -> void:
	var reloading: bool = player != null and bool(player.get("reloading"))
	ammo_mag.text = "--" if reloading else str(mag)
	wname.text = weapon_name

# ---------------------------------------------------------------- #xh / #hm

func _build_crosshair() -> void:
	xh = Control.new()
	xh.set_anchors_preset(Control.PRESET_CENTER)
	xh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(xh)
	for i in 4:
		var sh := rect(xh, Color(0, 0, 0, 0.55), Vector2.ZERO, Vector2.ONE)   # box-shadow 0 0 2px #000
		var l := rect(xh, Color("e8e6dc"), Vector2.ZERO, Vector2.ONE)
		l.set_meta("shadow", sh)
		xh_lines.append(l)
	hm = Control.new()
	hm.set_anchors_preset(Control.PRESET_CENTER)
	hm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hm)
	for deg in [45, 135, 225, 315]:
		var a := deg_to_rad(deg)
		var s := rect(hm, Color.WHITE, Vector2(cos(a) * 11 - 1, sin(a) * 11 - 5), Vector2(2, 9))
		s.pivot_offset = Vector2(1, 4.5)
		s.rotation = a
		s.modulate.a = 0.0
		hm_spans.append(s)

func _tick_crosshair() -> void:
	var recoil := 0.0
	var speed := 0.0
	var reloading := false
	var ads := 0.0
	if player:
		recoil = float(player.get("recoil")) * 40.0
		var vel: Vector3 = player.get("velocity")
		speed = clampf(Vector2(vel.x, vel.z).length() / 7.2, 0.0, 1.0)
		reloading = bool(player.get("reloading"))
		ads = float(player.get("ads_t"))
	var gap := 6.0 + recoil * 3.0 + speed * 8.0 + (10.0 if reloading else 0.0)
	var ln := 8.0
	var cfg := [[gap, 0.0, 1.0, ln], [-gap - ln, 0.0, 1.0, ln], [0.0, gap, ln, 1.0], [0.0, -gap - ln, ln, 1.0]]
	for i in 4:
		var l := xh_lines[i]
		l.position = Vector2(cfg[i][0], cfg[i][1])
		l.size = Vector2(cfg[i][2], cfg[i][3])
		var sh: ColorRect = l.get_meta("shadow")
		sh.position = l.position - Vector2(1, 1)
		sh.size = l.size + Vector2(2, 2)
	var want := 0.0
	if _combat:
		want = 0.25 if ads > 0.5 else 0.9
	xh.modulate.a = want

func on_hit(_headshot: bool, kill: bool) -> void:
	for s in hm_spans:
		s.color = Color("ff5238") if kill else Color.WHITE
	_hm_t = 0.22

# ---------------------------------------------------------------- #banner / #hint

func _build_banner() -> void:
	banner_box = VBoxContainer.new()
	banner_box.anchor_left = 0.0
	banner_box.anchor_right = 1.0
	banner_box.anchor_top = 0.34
	banner_box.anchor_bottom = 0.34
	banner_box.offset_top = -52
	banner_box.offset_bottom = 52
	banner_box.alignment = BoxContainer.ALIGNMENT_CENTER
	banner_box.add_theme_constant_override("separation", 8)
	banner_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_box.modulate.a = 0.0
	root.add_child(banner_box)
	banner_h = L("", 64, Color("c8352b"), 14, 900, false)
	banner_h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# text-shadow: 0 0 24px rgba(200,40,20,.6), 0 2px 6px #000
	banner_h.add_theme_color_override("font_outline_color", Color(200 / 255.0, 40 / 255.0, 20 / 255.0, 0.28))
	banner_h.add_theme_constant_override("outline_size", 14)
	banner_h.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	banner_h.add_theme_constant_override("shadow_offset_y", 2)
	banner_h.add_theme_constant_override("shadow_outline_size", 4)
	banner_box.add_child(banner_h)
	banner_p = L("", 13, Color("cfcabb"), 5)
	banner_p.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_box.add_child(banner_p)

## banner(h, p): straight up, gone after 2.3 s with a .5 s fade
func show_banner(title: String, sub := "") -> void:
	banner_h.text = title
	banner_p.text = sub
	banner_h.visible = title != ""
	_banner_t = 2.3

func _build_hint() -> void:
	hint = L("", 12, Color("bdb9aa"), 3)
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.offset_left = -700
	hint.offset_right = 700
	hint.offset_top = -126
	hint.offset_bottom = -110
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate.a = 0.85
	root.add_child(hint)

func set_hint(t: String) -> void:
	hint.text = t

func set_center(_t: String) -> void:
	pass          # the web shows threats in the objectives panel and #wave-num

# ---------------------------------------------------------------- #radio-dial

func _build_radio() -> void:
	radio_dial = box(root, Color(10 / 255.0, 12 / 255.0, 15 / 255.0, 0.62), Color(246 / 255.0, 212 / 255.0, 52 / 255.0, 0.22), 8)
	var sb: StyleBoxFlat = radio_dial.get_theme_stylebox("panel")
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 9
	sb.content_margin_bottom = 9
	radio_dial.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	radio_dial.grow_vertical = Control.GROW_DIRECTION_BEGIN
	radio_dial.offset_left = 18
	radio_dial.offset_top = -96
	radio_dial.offset_bottom = -96
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	radio_dial.add_child(v)
	v.add_child(L("RADIO", 10, Color("f6d434"), 1.6, 700))
	for i in 5:
		var l := L("", 11, Color("9aa3ad"), 0.77, 700)
		v.add_child(l)
		radio_rows.append(l)
	radio_foot = L("E ON", 10, Color("6d757d"), 0.7, 700)
	v.add_child(radio_foot)
	radio_dial.visible = false

func _tick_radio() -> void:
	var show := Game.phase in ["drive", "parking"] and car != null
	radio_dial.visible = show
	if not show:
		return
	var stations: Array = car.STATIONS
	var on: bool = car.radio_on
	for i in radio_rows.size():
		radio_rows[i].text = "%d %s" % [i + 1, stations[i].name]
		radio_rows[i].add_theme_color_override("font_color", Color("e8e6e0") if on and i == int(car.station) else Color("9aa3ad"))
	radio_foot.text = "E OFF" if on else "E ON"

func set_radio(_t: String) -> void:
	pass          # the web's dial shows the station; there is no toast

# ---------------------------------------------------------------- #goprohud

func _build_gopro() -> void:
	gopro = Control.new()
	gopro.set_anchors_preset(Control.PRESET_FULL_RECT)
	gopro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gopro.modulate.a = 0.0
	root.add_child(gopro)
	# corner crop brackets, 24 px, 2 px, 14 px in, at half opacity
	for c in [[Control.PRESET_TOP_LEFT, 1, 1], [Control.PRESET_TOP_RIGHT, -1, 1], [Control.PRESET_BOTTOM_LEFT, 1, -1], [Control.PRESET_BOTTOM_RIGHT, -1, -1]]:
		var k := Control.new()
		k.set_anchors_preset(c[0])
		k.mouse_filter = Control.MOUSE_FILTER_IGNORE
		gopro.add_child(k)
		var sx: int = c[1]
		var sy: int = c[2]
		var ox := 14.0 if sx > 0 else -38.0
		var oy := 14.0 if sy > 0 else -38.0
		rect(k, Color(1, 1, 1, 0.5), Vector2(ox, oy + (0.0 if sy > 0 else 22.0)), Vector2(24, 2))
		rect(k, Color(1, 1, 1, 0.5), Vector2(ox + (0.0 if sx > 0 else 22.0), oy), Vector2(2, 24))
	# rec dot + timecode, top left
	var rec := HBoxContainer.new()
	rec.position = Vector2(42, 30)
	rec.add_theme_constant_override("separation", 9)
	rec.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gopro.add_child(rec)
	var dc := CenterContainer.new()
	dc.custom_minimum_size = Vector2(10, 14)
	dc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rec.add_child(dc)
	gp_dots.append(circle(dc, 10, Color("ff2418")))
	gp_tc = L("00:00:00", 13, Color.WHITE, 2.5, 600)
	rec.add_child(gp_tc)
	# battery + resolution, top right
	var pwr := HBoxContainer.new()
	pwr.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	pwr.offset_left = -300
	pwr.offset_right = -42
	pwr.offset_top = 28
	pwr.alignment = BoxContainer.ALIGNMENT_END
	pwr.add_theme_constant_override("separation", 10)
	pwr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gopro.add_child(pwr)
	var batt := Control.new()
	batt.custom_minimum_size = Vector2(29, 16)
	batt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pwr.add_child(batt)
	var shell := box(batt, Color(0, 0, 0, 0), Color(1, 1, 1, 0.95), 2.5, 2)
	shell.position = Vector2(0, 2)
	shell.size = Vector2(24, 12)
	rect(batt, Color(1, 1, 1, 0.95), Vector2(24.5, 5.5), Vector2(3, 5))
	rect(batt, Color.WHITE, Vector2(3, 5), Vector2(12, 6))
	pwr.add_child(L("63%", 11, Color.WHITE, 2, 600))
	pwr.add_child(L("|", 11, Color(1, 1, 1, 0.5), 2, 400))
	var res := box(pwr, Color(0, 0, 0, 0), Color(1, 1, 1, 0.8), 2)
	var rsb: StyleBoxFlat = res.get_theme_stylebox("panel")
	rsb.content_margin_left = 6
	rsb.content_margin_right = 6
	rsb.content_margin_top = 3
	rsb.content_margin_bottom = 2
	res.add_child(L("4K|60", 10, Color.WHITE, 1.5, 600))
	# wordmark, bottom left
	var brand := VBoxContainer.new()
	brand.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	brand.offset_left = 42
	brand.offset_top = -72
	brand.offset_bottom = -32
	brand.alignment = BoxContainer.ALIGNMENT_END
	brand.add_theme_constant_override("separation", 5)
	brand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gopro.add_child(brand)
	brand.add_child(L("GoPro", 16, Color.WHITE, 3.5, 800, true, true))
	brand.add_child(L("HERO12", 9, Color(1, 1, 1, 0.8), 4, 600))
	# temperature, bottom right
	gp_temp = L("38°C", 11, Color(1, 1, 1, 0.92), 2, 600)
	gp_temp.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	gp_temp.offset_left = -200
	gp_temp.offset_right = -42
	gp_temp.offset_top = -46
	gp_temp.offset_bottom = -32
	gp_temp.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	gopro.add_child(gp_temp)
	# LIVE badge, bottom centre, while streaming
	var strip := CenterContainer.new()          # left:50%; transform:translateX(-50%)
	strip.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	strip.offset_left = 0
	strip.offset_right = 0
	strip.offset_top = -58 - 23
	strip.offset_bottom = -58
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gopro.add_child(strip)
	gp_live = box(strip, Color(0, 0, 0, 0.28), Color(1, 1, 1, 0.85), 3)
	var lsb: StyleBoxFlat = gp_live.get_theme_stylebox("panel")
	lsb.content_margin_left = 13
	lsb.content_margin_right = 13
	lsb.content_margin_top = 5
	lsb.content_margin_bottom = 4
	var lh := HBoxContainer.new()
	lh.add_theme_constant_override("separation", 8)
	lh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gp_live.add_child(lh)
	var ldc := CenterContainer.new()
	ldc.custom_minimum_size = Vector2(8, 12)
	ldc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lh.add_child(ldc)
	gp_dots.append(circle(ldc, 8, Color("ff2418")))
	lh.add_child(L("LIVE", 11, Color.WHITE, 3.5, 700))
	gp_live.modulate.a = 0.0

## goproSet(on): the OSD fades in over .4 s and the timecode starts from zero
func gopro_set(on: bool) -> void:
	_gp_on = on
	if on:
		_gp_sec = 0.0
		gp_tc.text = "00:00:00"

func _tick_gopro(dt: float) -> void:
	gopro.modulate.a = move_toward(gopro.modulate.a, 1.0 if _gp_on else 0.0, dt / 0.4)
	gp_live.modulate.a = move_toward(gp_live.modulate.a, 1.0 if _stream else 0.0, dt / 0.4)
	if not _gp_on:
		return
	var before := int(_gp_sec)
	_gp_sec += dt
	if int(_gp_sec) != before:
		var s := int(_gp_sec)
		gp_tc.text = "%02d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]
		if randf() < 0.3:
			gp_temp.text = "%.1f°C" % (37.6 + randf() * 0.8)
	# @keyframes gprecc: on until 54 %, then .16 - 1 s for REC, 1.2 s for LIVE
	gp_dots[0].modulate.a = 1.0 if fmod(_t, 1.0) < 0.55 else 0.16
	gp_dots[1].modulate.a = 1.0 if fmod(_t, 1.2) < 0.66 else 0.16

# ---------------------------------------------------------------- #phonefx

func _build_phone() -> void:
	phone = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(11 / 255.0, 12 / 255.0, 16 / 255.0, 0.85)
	sb.border_color = Color(1, 1, 1, 0.16)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(20)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 14
	sb.shadow_offset = Vector2(0, 10)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 13
	sb.content_margin_bottom = 10
	phone.add_theme_stylebox_override("panel", sb)
	phone.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	phone.offset_left = -256
	phone.offset_right = -24
	phone.offset_top = 78
	phone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(phone)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	phone.add_child(v)
	var notch := CenterContainer.new()
	notch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(notch)
	var nb := box(notch, Color(1, 1, 1, 0.22), Color(0, 0, 0, 0), 3, 0)
	nb.custom_minimum_size = Vector2(52, 5)
	v.add_child(_gap(10))
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(head)
	var pill := box(head, Color("e11919"), Color(0, 0, 0, 0), 20, 0)
	var psb: StyleBoxFlat = pill.get_theme_stylebox("panel")
	psb.content_margin_left = 9
	psb.content_margin_right = 9
	psb.content_margin_top = 3
	psb.content_margin_bottom = 2
	var ph := HBoxContainer.new()
	ph.add_theme_constant_override("separation", 5)
	ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(ph)
	var pdc := CenterContainer.new()
	pdc.custom_minimum_size = Vector2(5, 10)
	pdc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ph.add_child(pdc)
	pf_dot = circle(pdc, 5, Color.WHITE)
	ph.add_child(L("LIVE", 9, Color.WHITE, 2.5, 800, false))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(spacer)
	var viewers := HBoxContainer.new()
	viewers.add_theme_constant_override("separation", 4)
	viewers.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(viewers)
	pf_count = L("3", 12, Color.WHITE, 0, 700)
	viewers.add_child(pf_count)
	var w := L("WATCHING", 9, Color(1, 1, 1, 0.85), 2, 600)
	w.size_flags_vertical = Control.SIZE_SHRINK_END
	viewers.add_child(w)
	v.add_child(_gap(9))
	var chat_clip := Control.new()
	chat_clip.custom_minimum_size = Vector2(204, 116)
	chat_clip.clip_contents = true
	chat_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(chat_clip)
	pf_chat = VBoxContainer.new()
	pf_chat.set_anchors_preset(Control.PRESET_FULL_RECT)
	pf_chat.alignment = BoxContainer.ALIGNMENT_END
	pf_chat.add_theme_constant_override("separation", 4)
	pf_chat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chat_clip.add_child(pf_chat)
	v.add_child(_gap(9))
	v.add_child(_hline())
	v.add_child(_gap(8))
	var foot := HBoxContainer.new()
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(foot)
	pf_hn = L("♥ 142", 11, Color("ff4d5e"), 1, 700)
	foot.add_child(pf_hn)
	var sp2 := Control.new()
	sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foot.add_child(sp2)
	foot.add_child(L("@deadaisle_live", 9, Color(1, 1, 1, 0.55), 1.5))
	v.add_child(_gap(9))
	var home := CenterContainer.new()
	home.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(home)
	var hb := box(home, Color(1, 1, 1, 0.25), Color(0, 0, 0, 0), 2, 0)
	hb.custom_minimum_size = Vector2(74, 4)
	phone.visible = false

## streamStart / streamStop: the phone panel, chat, viewers and hearts
func stream_start() -> void:
	if _stream:
		return
	_stream = true
	phone.visible = true
	_push_chat()
	_chat_t = randf_range(0.7, 1.7)
	_view_t = 0.9
	_heart_t = randf_range(0.45, 1.4)

func stream_stop() -> void:
	_stream = false
	phone.visible = false

func _push_chat() -> void:
	var u: Array = GP_USERS[_user_i % GP_USERS.size()]
	_user_i += 1
	var msg: String = GP_MSGS[_msg_i % GP_MSGS.size()]
	_msg_i += 1
	var line := RichTextLabel.new()
	line.bbcode_enabled = true
	line.fit_content = true
	line.scroll_active = false
	line.autowrap_mode = TextServer.AUTOWRAP_OFF
	line.clip_contents = true
	line.custom_minimum_size = Vector2(204, 0)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_font_override("normal_font", font(400, false, false, 0.4))
	line.add_theme_font_override("bold_font", font(700, false, false, 0.4))
	line.add_theme_font_size_override("normal_font_size", 11)
	line.add_theme_font_size_override("bold_font_size", 11)
	line.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	line.add_theme_constant_override("shadow_offset_y", 1)
	line.text = "[b][color=%s]%s[/color][/b]  %s" % [u[1], u[0], msg]
	line.modulate.a = 0.0
	pf_chat.add_child(line)
	line.create_tween().tween_property(line, "modulate:a", 1.0, 0.25).set_ease(Tween.EASE_OUT)
	while pf_chat.get_child_count() > 5:
		var first := pf_chat.get_child(0)
		pf_chat.remove_child(first)
		first.queue_free()

static func _commas(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out

func _tick_stream(dt: float) -> void:
	if not _stream:
		return
	pf_dot.modulate.a = 1.0 if fmod(_t, 1.4) < 0.77 else 0.16
	_chat_t -= dt
	if _chat_t <= 0.0:
		_chat_t = randf_range(0.7, 1.7)
		_push_chat()
	_view_t -= dt
	if _view_t <= 0.0:
		_view_t = 0.9
		_viewers += (8 + randi() % 38) if randf() < 0.12 else (1 + randi() % 4)   # a raid, or a steady climb
		pf_count.text = _commas(_viewers)
	_heart_t -= dt
	if _heart_t <= 0.0:
		_heart_t = randf_range(0.45, 1.4)
		_hearts += 1 + randi() % 7
		pf_hn.text = "♥ " + _commas(_hearts)

# ---------------------------------------------------------------- survivor badges

func _build_badges() -> void:
	badges = Control.new()
	badges.set_anchors_preset(Control.PRESET_FULL_RECT)
	badges.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(badges)

## [screen position of head + 2.1 m, metres] per hiding survivor in view
func set_markers(list: Array) -> void:
	while badge_lbls.size() < list.size():
		var l := L("", 12, Color("44ff66"), 0, 700)
		l.add_theme_color_override("font_outline_color", Color(68 / 255.0, 1, 102 / 255.0, 0.35))
		l.add_theme_constant_override("outline_size", 4)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		l.size = Vector2(80, 32)
		badges.add_child(l)
		badge_lbls.append(l)
	for i in badge_lbls.size():
		var l := badge_lbls[i]
		l.visible = i < list.size()
		if l.visible:
			l.text = "▼\n%dm" % int(round(float(list[i][1])))
			l.position = (list[i][0] as Vector2) - Vector2(40, 32)    # translate(-50%, -100%)

# ---------------------------------------------------------------- phases

func on_damage(_from: Vector3) -> void:
	dmg_flash = clampf((1.0 - _hp / 100.0) + 0.35, 0.0, 1.0)

func show_combat_hud(on: bool) -> void:
	_combat = on

## setPhase's HUD half: the hint line, the top readout
func _on_phase(p: String) -> void:
	match p:
		"drive":
			hint.text = "W/S DRIVE · A/D STEER · E RADIO"
			wave_label.text = "OBJECTIVE"
			wave_num.text = "TOPS"
		"parking":
			hint.text = ""
		"outside":
			hint.text = "FIGHT TO THE DOORS  ·  N MUSIC"
			wave_label.text = "THREATS"
		"inside":
			hint.text = "R RELOAD · SHIFT SPRINT · RMB AIM · 1/2/3 WEAPON · N MUSIC"
			wave_label.text = "THREATS"
		"win", "dead":
			hint.text = ""
	round_chip.text = "ROUND %d" % Game.round

func _process(dt: float) -> void:
	_t += dt
	# #dmg: the hit flash ORed with the low-HP vignette under 65 HP
	dmg_flash = maxf(0.0, dmg_flash - dt * 2.6)
	var low_hp := clampf(0.9 - _hp / 80.0, 0.0, 0.85) if _hp < 65.0 else 0.0
	dmg.modulate.a = move_toward(dmg.modulate.a, maxf(dmg_flash, low_hp), dt / 0.18)
	if _banner_t > 0.0:
		_banner_t -= dt
		banner_box.modulate.a = move_toward(banner_box.modulate.a, 1.0, dt / 0.5)
	else:
		banner_box.modulate.a = move_toward(banner_box.modulate.a, 0.0, dt / 0.5)
	_hm_t = maxf(0.0, _hm_t - dt)
	for s in hm_spans:
		s.modulate.a = _hm_t / 0.22
	# the active objective's dot pulses (pulse-dot, 1.1 s)
	var k := 0.5 + 0.5 * cos(_t * TAU / 1.1)
	for id in obj_rows:
		var o: Dictionary = obj_rows[id]
		if o.state == "active":
			(o.dot as Panel).scale = Vector2.ONE * lerpf(0.7, 1.0, k)
			(o.dot as Panel).modulate.a = lerpf(0.6, 1.0, k)
	_tick_feed(dt)
	_tick_crosshair()
	_tick_radio()
	_tick_gopro(dt)
	_tick_stream(dt)
	if player:
		ammo_mag.text = "--" if bool(player.get("reloading")) else str(int(player.get("mag")))
