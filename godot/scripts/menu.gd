## The web build's screens, one to one: the lobby (#menu), PAUSED (#pause),
## SETTINGS (#settings), YOU DIED (#dead) and MISSION COMPLETE (#win), with
## the same text, colours, sizes and animations. Runs while the tree is
## paused.
extends CanvasLayer

const HudScript := preload("res://scripts/hud.gd")

signal play_pressed
signal quit_to_menu
signal skin_changed(i: int)

const RED := Color("c8352b")
const YEL := Color("f6d434")
const TXT := Color("e8e6dc")

## the web's SKINS: palette outfits for the operator (dark -> light) + flesh
const SKINS := [
	{"id": "operator", "name": "OPERATOR", "pal": ["#23262a", "#3f444a", "#6b5b43"], "skin": "#ffd9a0", "chip": "#3f444a"},
	# a full model rather than a palette: a Rocketbox soldier with the GoPro on
	# his helmet; `face` turns him to the camera (he faces +Z, the operator -Z)
	# and `vm_pal` dresses the first-person arms to match
	{"id": "military", "name": "MILITARY", "chip": "#6b705c", "model": "res://assets/skin_military.glb",
		"face": 0.0, "vm_pal": ["#3f423a", "#6e7366", "#9a9d8e"], "skin": "#b98a66"},
	{"id": "ranger", "name": "RANGER", "pal": ["#1b2a18", "#3c5233", "#7d7a4a"], "skin": "#e8b98a", "chip": "#3c5233"},
	{"id": "medic", "name": "MEDIC", "pal": ["#d9dbd8", "#b5322c", "#8f9295"], "skin": "#f0c49a", "chip": "#b5322c"},
	{"id": "nightfall", "name": "NIGHTFALL", "pal": ["#14161b", "#242a35", "#3d4756"], "skin": "#d9a97e", "chip": "#242a35"},
	{"id": "hazard", "name": "HAZARD", "pal": ["#c9922a", "#2c2a26", "#8a6a2a"], "skin": "#e6bd93", "chip": "#c9922a"},
	{"id": "coastal", "name": "COASTAL", "pal": ["#e6e2d6", "#2f6f78", "#9a9384"], "skin": "#c98f60", "chip": "#2f6f78"},
	{"id": "ember", "name": "EMBER", "pal": ["#3a1d16", "#8a3a1e", "#c4652c"], "skin": "#b3805a", "chip": "#8a3a1e"},
	{"id": "arctic", "name": "ARCTIC", "pal": ["#eceef0", "#b9c3cc", "#6f7d88"], "skin": "#f2cfa8", "chip": "#b9c3cc"},
	{"id": "suit", "name": "SUIT", "chip": "#2b3038"},
]

var screens := {}
var current := ""
var _back_to := ""
var _rows := {}
var _skin_cards: Array[Button] = []
var _slot_name: Label
var _slot_dot: Label
var _name_edit: LineEdit
var _avatar: Label
var _party_status: RichTextLabel
var _code := ""
var _grade: Label
var _win_parts: Array[Control] = []
var _dead_lbl: RichTextLabel
var _dead_xtra: RichTextLabel
var _stat_lbls := {}

func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_lobby()
	_build_pause()
	_build_settings()
	_build_dead()
	_build_win()
	show_screen("")

# ---------------------------------------------------------------- helpers

func L(txt: String, px: int, color: Color, spacing := 0.0, weight := 400, mono := false) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_override("font", HudScript.font(weight, false, mono, spacing))
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func R(bb: String, px: int, spacing := 0.0, center := true) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_OFF
	r.add_theme_font_override("normal_font", HudScript.font(400, false, false, spacing))
	r.add_theme_font_override("bold_font", HudScript.font(700, false, false, 1))
	r.add_theme_font_size_override("normal_font_size", px)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.text = ("[center]%s[/center]" % bb) if center else bb
	return r

func sbox(bg: Color, border: Color, radius := 0, bw := 1, pad := Vector4.ZERO) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad.x
	sb.content_margin_top = pad.y
	sb.content_margin_right = pad.z
	sb.content_margin_bottom = pad.w
	return sb

func panel(bg: Color, border: Color, radius := 0, pad := Vector4.ZERO) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", sbox(bg, border, radius, 1, pad))
	return p

## .screen .start: hairline box that fills red on hover
func start_btn(text: String, cb: Callable, px := 14, pad := Vector2(46, 14)) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", HudScript.font(400, false, false, 6))
	b.add_theme_font_size_override("font_size", px)
	var p4 := Vector4(pad.x, pad.y, pad.x, pad.y)
	b.add_theme_stylebox_override("normal", sbox(Color(1, 1, 1, 0.03), Color("666666"), 0, 1, p4))
	b.add_theme_stylebox_override("hover", sbox(RED, RED, 0, 1, p4))
	b.add_theme_stylebox_override("pressed", sbox(RED, RED, 0, 1, p4))
	b.add_theme_color_override("font_color", TXT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(func():
		Game.play("gear_gopro_beep", -12.0, 1.25)
		cb.call())
	return b

func gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

## .screen: fixed, rgba(2,3,2,.8), a centred column
func screen(id: String, bg := Color(2 / 255.0, 3 / 255.0, 2 / 255.0, 0.8)) -> VBoxContainer:
	var root := Control.new()
	root.name = id
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var dim := ColorRect.new()
	dim.color = bg
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(c)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 0)
	c.add_child(col)
	screens[id] = root
	return col

## .screen h1: 96 px (min 11vw), weight 900, 22 px tracking, with a glow
func h1(text: String, color: Color, glow: Color) -> Label:
	var l := L(text, 96, color, 22, 900)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_outline_color", glow)
	l.add_theme_constant_override("outline_size", 18)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("shadow_offset_y", 3)
	l.add_theme_constant_override("shadow_outline_size", 6)
	return l

func sub(text: String, color := Color("8f957f")) -> Label:
	var l := L(text, 13, color, 8)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

func show_screen(id: String) -> void:
	current = id
	for k in screens:
		screens[k].visible = (k == id)
	var hud = get_parent().get("hud")
	if hud:
		hud.visible = id == "" and Game.phase != "menu"
	if id != "":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

# ---------------------------------------------------------------- lobby (#menu)

func _build_lobby() -> void:
	var root := Control.new()
	root.name = "lobby"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	screens["lobby"] = root
	# #lobby-bg
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.26, 0.58, 1.0])
	g.colors = PackedColorArray([Color(4 / 255.0, 7 / 255.0, 12 / 255.0, 0.72), Color(4 / 255.0, 7 / 255.0, 12 / 255.0, 0.12),
		Color(4 / 255.0, 7 / 255.0, 12 / 255.0, 0.10), Color(3 / 255.0, 5 / 255.0, 9 / 255.0, 0.88)])
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

	# #lobby-top: a 58 px bar with the brand, the tabs and you
	var tg := Gradient.new()
	tg.colors = PackedColorArray([Color(3 / 255.0, 6 / 255.0, 10 / 255.0, 0.92), Color(3 / 255.0, 6 / 255.0, 10 / 255.0, 0)])
	var tgt := GradientTexture2D.new()
	tgt.gradient = tg
	tgt.fill_from = Vector2(0, 0)
	tgt.fill_to = Vector2(0, 1)
	var topbg := TextureRect.new()
	topbg.texture = tgt
	topbg.stretch_mode = TextureRect.STRETCH_SCALE
	topbg.set_anchors_preset(Control.PRESET_TOP_WIDE)
	topbg.offset_bottom = 58
	topbg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(topbg)
	var top := HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 24
	top.offset_right = -24
	top.offset_bottom = 58
	top.add_theme_constant_override("separation", 26)
	root.add_child(top)
	var brand := L("DEAD AISLE", 17, RED, 6, 900)
	brand.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	brand.add_theme_color_override("font_outline_color", Color(200 / 255.0, 53 / 255.0, 43 / 255.0, 0.22))
	brand.add_theme_constant_override("outline_size", 10)
	top.add_child(brand)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	tabs.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(tabs)
	for t in [["PLAY", true, func(): pass], ["SETTINGS", false, func(): open_settings("lobby")]]:
		var b := Button.new()
		b.text = t[0]
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_override("font", HudScript.font(700, false, false, 3))
		b.add_theme_font_size_override("font_size", 12)
		var on: bool = t[1]
		var pad := Vector4(16, 8, 16, 8)
		b.add_theme_stylebox_override("normal", sbox(YEL if on else Color(0, 0, 0, 0), Color(0, 0, 0, 0), 5, 0, pad))
		b.add_theme_stylebox_override("hover", sbox(YEL if on else Color(1, 1, 1, 0.07), Color(0, 0, 0, 0), 5, 0, pad))
		b.add_theme_stylebox_override("pressed", sbox(YEL if on else Color(1, 1, 1, 0.07), Color(0, 0, 0, 0), 5, 0, pad))
		b.add_theme_color_override("font_color", Color("0b0d0a") if on else Color("9aa08f"))
		b.add_theme_color_override("font_hover_color", Color("0b0d0a") if on else Color.WHITE)
		b.pressed.connect(t[2])
		tabs.add_child(b)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(spacer)
	var who := HBoxContainer.new()
	who.add_theme_constant_override("separation", 10)
	who.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(who)
	var av := panel(RED, Color(0, 0, 0, 0), 13)
	av.custom_minimum_size = Vector2(26, 26)
	_avatar = L("O", 12, Color.WHITE, 0, 900)
	_avatar.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_avatar.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	av.add_child(_avatar)
	who.add_child(av)
	_name_edit = LineEdit.new()
	_name_edit.max_length = 12
	_name_edit.custom_minimum_size = Vector2(130, 0)
	_name_edit.placeholder_text = "YOUR NAME"
	_name_edit.add_theme_font_override("font", HudScript.font(400, false, false, 2))
	_name_edit.add_theme_font_size_override("font_size", 12)
	_name_edit.add_theme_color_override("font_color", TXT)
	var ne := StyleBoxFlat.new()
	ne.bg_color = Color(0, 0, 0, 0)
	ne.border_color = Color(1, 1, 1, 0.18)
	ne.border_width_bottom = 1
	ne.content_margin_left = 2
	ne.content_margin_top = 3
	ne.content_margin_bottom = 3
	_name_edit.add_theme_stylebox_override("normal", ne)
	var nf := ne.duplicate() as StyleBoxFlat
	nf.border_color = YEL
	_name_edit.add_theme_stylebox_override("focus", nf)
	_name_edit.text = str(Game.settings.get("name", ""))
	if _name_edit.text == "":
		_name_edit.text = "OPERATOR%d" % (1 + randi() % 89)
	_name_edit.text_changed.connect(_on_name)
	who.add_child(_name_edit)

	# #lobby-hint
	var hint := L("WASD MOVE · LMB FIRE · RMB AIM · R RELOAD · SHIFT SPRINT · F PICK UP / THROW · N MUSIC", 10, Color("6f7565"), 3)
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.offset_left = -600
	hint.offset_right = 600
	hint.offset_top = -238
	hint.offset_bottom = -224
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(hint)

	# #lobby-skins: OUTFIT
	var skins := VBoxContainer.new()
	skins.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	skins.offset_left = -380
	skins.offset_right = 380
	skins.offset_top = -210
	skins.offset_bottom = -128
	skins.alignment = BoxContainer.ALIGNMENT_END
	skins.add_theme_constant_override("separation", 7)
	root.add_child(skins)
	var oh := L("OUTFIT", 10, Color("8b8b80"), 2.2, 700, true)
	oh.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	skins.add_child(oh)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 5)
	skins.add_child(row)
	for i in SKINS.size():
		row.add_child(_skin_card(i))
	_paint_skins()

	# #lobby-play: the card and PLAY, bottom left
	var play := VBoxContainer.new()
	play.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	play.offset_left = 26
	play.offset_right = 26 + 288
	play.offset_top = -190
	play.offset_bottom = -30
	play.alignment = BoxContainer.ALIGNMENT_END
	play.add_theme_constant_override("separation", 10)
	root.add_child(play)
	var card := panel(Color(9 / 255.0, 12 / 255.0, 17 / 255.0, 0.85), Color(1, 1, 1, 0.10), 10, Vector4(15, 13, 15, 13))
	play.add_child(card)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 5)
	card.add_child(cv)
	cv.add_child(L("CO-OP · SOLO", 10, YEL, 4, 800))
	var ms := L("PARK AT TOPS · CLEAR THE STORE · GET ALL 4 SURVIVORS OUT", 11, Color("8b9080"), 2)
	ms.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ms.custom_minimum_size = Vector2(258, 0)
	cv.add_child(ms)
	var pb := Button.new()
	pb.text = "PLAY"
	pb.focus_mode = Control.FOCUS_NONE
	pb.custom_minimum_size = Vector2(288, 0)
	pb.add_theme_font_override("font", HudScript.font(900, false, false, 9))
	pb.add_theme_font_size_override("font_size", 19)
	var pn := sbox(YEL, YEL, 6, 0, Vector4(0, 17, 0, 17))
	pn.shadow_color = Color(246 / 255.0, 212 / 255.0, 52 / 255.0, 0.22)
	pn.shadow_size = 12
	pn.shadow_offset = Vector2(0, 6)
	pb.add_theme_stylebox_override("normal", pn)
	var ph := pn.duplicate() as StyleBoxFlat
	ph.bg_color = Color("ffe75c")
	pb.add_theme_stylebox_override("hover", ph)
	pb.add_theme_stylebox_override("pressed", ph)
	for c in ["font_color", "font_hover_color", "font_pressed_color"]:
		pb.add_theme_color_override(c, Color("0b0d0a"))
	pb.pressed.connect(func():
		Game.save_settings()
		play_pressed.emit())
	play.add_child(pb)

	# #lobby-slots, bottom centre: you, then three empty seats
	var slots := HBoxContainer.new()
	slots.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	slots.offset_left = -163
	slots.offset_right = 163
	slots.offset_top = -118
	slots.offset_bottom = -30
	slots.add_theme_constant_override("separation", 10)
	root.add_child(slots)
	for i in 4:
		var filled := i == 0
		var s := panel(Color(9 / 255.0, 12 / 255.0, 17 / 255.0, 0.8), Color(246 / 255.0, 212 / 255.0, 52 / 255.0, 0.45) if filled else Color(1, 1, 1, 0.10), 8)
		s.custom_minimum_size = Vector2(74, 88)
		var sv := VBoxContainer.new()
		sv.alignment = BoxContainer.ALIGNMENT_CENTER
		sv.add_theme_constant_override("separation", 6)
		s.add_child(sv)
		var dh := CenterContainer.new()
		sv.add_child(dh)
		var dot := panel(RED if filled else Color(1, 1, 1, 0.08), Color(0, 0, 0, 0), 13)
		dot.custom_minimum_size = Vector2(26, 26)
		var dl := L("O" if filled else "+", 12 if filled else 15, Color.WHITE if filled else Color("5f6558"), 0, 900)
		dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		dl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		dot.add_child(dl)
		dh.add_child(dot)
		var nm := L(_name_edit.text if filled else "EMPTY", 9, Color("d6d3c6") if filled else Color("6f7565"), 1)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm.clip_text = true
		nm.custom_minimum_size = Vector2(66, 0)
		sv.add_child(nm)
		slots.add_child(s)
		if filled:
			_slot_name = nm
			_slot_dot = dl
	_on_name(_name_edit.text)

	# #lobby-party, bottom right
	var party := panel(Color(9 / 255.0, 12 / 255.0, 17 / 255.0, 0.85), Color(1, 1, 1, 0.10), 10, Vector4(16, 14, 16, 14))
	party.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	party.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	party.grow_vertical = Control.GROW_DIRECTION_BEGIN
	party.offset_left = -26 - 308
	party.offset_right = -26
	party.offset_top = -30
	party.offset_bottom = -30
	root.add_child(party)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 9)
	party.add_child(pv)
	pv.add_child(L("PARTY", 10, RED, 4, 800))
	var letters := "ABCDEFGHJKLMNPQRSTUVWXYZ"
	for i in 6:
		_code += letters[randi() % letters.length()]
	var r1 := HBoxContainer.new()
	r1.add_theme_constant_override("separation", 9)
	pv.add_child(r1)
	var l1 := L("YOUR CODE", 10, Color("8b9080"), 2)
	l1.custom_minimum_size = Vector2(62, 0)
	l1.autowrap_mode = TextServer.AUTOWRAP_WORD
	r1.add_child(l1)
	var code := panel(Color(0, 0, 0, 0.45), Color(246 / 255.0, 212 / 255.0, 52 / 255.0, 0.4), 5, Vector4(10, 8, 10, 8))
	code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cl := L(_code, 19, YEL, 8, 800)
	cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	code.add_child(cl)
	r1.add_child(code)
	r1.add_child(_party_btn("COPY", func():
		DisplayServer.clipboard_set(_code)
		_party_msg("Copied [b][color=#7fd88f]%s[/color][/b]. Co-op is not in this build yet, so friends cannot join it." % _code)))
	var r2 := HBoxContainer.new()
	r2.add_theme_constant_override("separation", 9)
	pv.add_child(r2)
	var l2 := L("JOIN", 10, Color("8b9080"), 2)
	l2.custom_minimum_size = Vector2(62, 0)
	r2.add_child(l2)
	var join := LineEdit.new()
	join.max_length = 6
	join.placeholder_text = "CODE"
	join.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join.add_theme_font_override("font", HudScript.font(400, false, false, 5))
	join.add_theme_font_size_override("font_size", 14)
	join.add_theme_stylebox_override("normal", sbox(Color(0, 0, 0, 0.45), Color(1, 1, 1, 0.14), 5, 1, Vector4(10, 8, 10, 8)))
	join.add_theme_stylebox_override("focus", sbox(Color(0, 0, 0, 0.45), YEL, 5, 1, Vector4(10, 8, 10, 8)))
	r2.add_child(join)
	r2.add_child(_party_btn("JOIN", func(): _party_msg("[color=#e2685c][b]Co-op is not in this build yet.[/b][/color] Solo only for now.")))
	var sep := ColorRect.new()
	sep.color = Color(1, 1, 1, 0.07)
	sep.custom_minimum_size = Vector2(0, 1)
	pv.add_child(sep)
	_party_status = RichTextLabel.new()
	_party_status.bbcode_enabled = true
	_party_status.fit_content = true
	_party_status.scroll_active = false
	_party_status.custom_minimum_size = Vector2(276, 0)
	_party_status.add_theme_font_override("normal_font", HudScript.font(400, false, false, 2))
	_party_status.add_theme_font_override("bold_font", HudScript.font(700, false, false, 2))
	_party_status.add_theme_font_size_override("normal_font_size", 10)
	_party_status.add_theme_font_size_override("bold_font_size", 10)
	_party_status.add_theme_color_override("default_color", Color("7f8574"))
	_party_status.add_theme_constant_override("line_separation", 6)
	pv.add_child(_party_status)
	_party_msg("Offline — [b][color=#7fd88f]solo[/color][/b]. Share your code to let friends drop in.")

func _party_btn(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", HudScript.font(400, false, false, 2))
	b.add_theme_font_size_override("font_size", 10)
	b.add_theme_stylebox_override("normal", sbox(Color(1, 1, 1, 0.07), Color(1, 1, 1, 0.18), 5, 1, Vector4(12, 8, 12, 8)))
	b.add_theme_stylebox_override("hover", sbox(RED, RED, 5, 1, Vector4(12, 8, 12, 8)))
	b.add_theme_stylebox_override("pressed", sbox(RED, RED, 5, 1, Vector4(12, 8, 12, 8)))
	b.add_theme_color_override("font_color", Color("d6d3c6"))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.pressed.connect(cb)
	return b

func _party_msg(bb: String) -> void:
	_party_status.text = bb

func _on_name(t: String) -> void:
	var n := t.to_upper().substr(0, 12)
	if n == "":
		n = "OPERATOR"
	Game.settings.name = n
	if _slot_name:
		_slot_name.text = n
	var ini := n.substr(0, 1)
	if _avatar:
		_avatar.text = ini
	if _slot_dot:
		_slot_dot.text = ini

func _skin_card(i: int) -> Button:
	var s: Dictionary = SKINS[i]
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(66, 58)      # ten outfits in the width the web's nine had
	b.set_meta("i", i)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 5)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var ch := CenterContainer.new()
	ch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(ch)
	var chip := Panel.new()
	chip.custom_minimum_size = Vector2(30, 30)
	chip.add_theme_stylebox_override("panel", sbox(Color(s.chip), Color(0, 0, 0, 0), 15, 0))
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ch.add_child(chip)
	var nm := L(s.name, 9, Color("8b8b80"), 0.7, 700, true)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(nm)
	b.set_meta("label", nm)
	b.pressed.connect(func(): _select_skin(i))
	_skin_cards.append(b)
	return b

func _select_skin(i: int) -> void:
	Game.settings.skin = SKINS[i].id
	Game.save_settings()
	_paint_skins()
	Game.play("gear_gopro_beep", -14.0, 1.4)
	skin_changed.emit(i)

func skin_index() -> int:
	var id := str(Game.settings.get("skin", "operator"))
	for i in SKINS.size():
		if SKINS[i].id == id:
			return i
	return 0

func _paint_skins() -> void:
	var on_i := skin_index()
	for b in _skin_cards:
		var i: int = b.get_meta("i")
		var on := i == on_i
		var pad := Vector4(4, 7, 4, 6)
		var base := Color(16 / 255.0, 18 / 255.0, 20 / 255.0, 0.72)
		b.add_theme_stylebox_override("normal", sbox(base, YEL if on else Color("2c3036"), 7, 1, pad))
		b.add_theme_stylebox_override("hover", sbox(base, YEL if on else Color("4a5058"), 7, 1, pad))
		b.add_theme_stylebox_override("pressed", sbox(base, YEL, 7, 1, pad))
		(b.get_meta("label") as Label).add_theme_color_override("font_color", YEL if on else Color("8b8b80"))

# ---------------------------------------------------------------- #pause

func _build_pause() -> void:
	var col := screen("pause")
	col.add_child(h1("PAUSED", Color("aaaabb"), Color(0.7, 0.12, 0.06, 0.3)))
	col.add_child(gap(40))
	col.add_child(start_btn("RESUME", resume))
	col.add_child(gap(14))
	col.add_child(start_btn("SETTINGS", func(): open_settings("pause")))

func pause() -> void:
	get_tree().paused = true
	show_screen("pause")

func resume() -> void:
	get_tree().paused = false
	show_screen("")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

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

# ---------------------------------------------------------------- #settings

func _build_settings() -> void:
	var col := screen("settings", Color(3 / 255.0, 5 / 255.0, 7 / 255.0, 0.9))
	var box := PanelContainer.new()
	var sb := sbox(Color(15 / 255.0, 18 / 255.0, 23 / 255.0, 0.97), Color(1, 1, 1, 0.14), 16, 1, Vector4(30, 26, 30, 22))
	sb.shadow_color = Color(0, 0, 0, 0.6)
	sb.shadow_size = 30
	sb.shadow_offset = Vector2(0, 24)
	box.add_theme_stylebox_override("panel", sb)
	box.custom_minimum_size = Vector2(620, 0)
	col.add_child(box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	box.add_child(v)
	v.add_child(L("SETTINGS", 20, TXT, 7, 800))
	v.add_child(gap(4))
	v.add_child(L("SAVED TO THIS COMPUTER", 10, Color("6f7668"), 3))
	v.add_child(gap(20))
	var groups := [
		["AUDIO", [["master", "MASTER VOLUME", 0, 100, 1, "%"], ["music", "MUSIC", 0, 100, 1, "%"], ["sfx", "SOUND EFFECTS", 0, 100, 1, "%"]]],
		["CONTROLS", [["sens", "MOUSE SENSITIVITY", 20, 300, 5, "%"], ["invert", "INVERT LOOK"]]],
		["VIDEO", [["fov", "FIELD OF VIEW", 70, 110, 1, "°"], ["res", "RENDER QUALITY", 50, 200, 5, "%"],
			["shadows", "SHADOWS"], ["fx", "BODYCAM FILTER"]]],
	]
	var first := true
	for grp in groups:
		if not first:
			v.add_child(gap(18))
		first = false
		v.add_child(L(grp[0], 10, RED, 4, 800))
		v.add_child(gap(6))
		for r in grp[1]:
			v.add_child(_setting_row(r))
	v.add_child(gap(22))
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 12)
	v.add_child(btns)
	for b in [["RESET", _reset_settings], ["DONE", _close_settings]]:
		var bt := start_btn(b[0], b[1], 12, Vector2(0, 12))
		bt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btns.add_child(bt)

func _setting_row(r: Array) -> Control:
	var key: String = r[0]
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 0)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.custom_minimum_size = Vector2(0, 36)
	wrap.add_child(row)
	var lab := L(r[1], 12, Color("b9b6aa"), 2)
	lab.custom_minimum_size = Vector2(190, 0)
	lab.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(lab)
	if r.size() > 2:
		var s := HSlider.new()
		s.min_value = r[2]
		s.max_value = r[3]
		s.step = r[4]
		s.focus_mode = Control.FOCUS_NONE
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		# accent-color #c8352b on a 4 px track
		var track := sbox(Color(1, 1, 1, 0.18), Color(0, 0, 0, 0), 2, 0)
		track.content_margin_top = 2
		track.content_margin_bottom = 2
		s.add_theme_stylebox_override("slider", track)
		var fill := sbox(RED, Color(0, 0, 0, 0), 2, 0)
		fill.content_margin_top = 2
		fill.content_margin_bottom = 2
		s.add_theme_stylebox_override("grabber_area", fill)
		s.add_theme_stylebox_override("grabber_area_highlight", fill)
		row.add_child(s)
		var val := L("", 12, Color("ffd76a"), 1)
		val.custom_minimum_size = Vector2(58, 0)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		val.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(val)
		var suf: String = r[5]
		s.value_changed.connect(func(x: float):
			Game.settings[key] = int(x)
			val.text = "%d%s" % [int(x), suf]
			Game.apply_settings())
		s.drag_ended.connect(func(_c): Game.save_settings())
		_rows[key] = [s, val, suf]
	else:
		var sp := Control.new()
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(sp)
		var t := Button.new()
		t.focus_mode = Control.FOCUS_NONE
		t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		t.add_theme_font_override("font", HudScript.font(400, false, false, 3))
		t.add_theme_font_size_override("font_size", 11)
		row.add_child(t)
		t.pressed.connect(func():
			Game.settings[key] = not bool(Game.settings[key])
			_sync_settings()
			Game.apply_settings()
			Game.save_settings())
		_rows[key] = [t, null, ""]
	var line := ColorRect.new()
	line.color = Color(1, 1, 1, 0.05)
	line.custom_minimum_size = Vector2(0, 1)
	wrap.add_child(line)
	return wrap

func _sync_settings() -> void:
	for key in _rows:
		var w = _rows[key][0]
		if w is HSlider:
			(w as HSlider).set_value_no_signal(float(Game.settings[key]))
			(_rows[key][1] as Label).text = "%d%s" % [int(Game.settings[key]), _rows[key][2]]
		else:
			var on := bool(Game.settings[key])
			var b := w as Button
			b.text = "ON" if on else "OFF"
			var pad := Vector4(18, 5, 18, 5)
			b.add_theme_stylebox_override("normal", sbox(RED if on else Color(1, 1, 1, 0.05), RED if on else Color("555555"), 4, 1, pad))
			b.add_theme_stylebox_override("hover", sbox(RED if on else Color(1, 1, 1, 0.09), RED if on else Color("777777"), 4, 1, pad))
			b.add_theme_stylebox_override("pressed", sbox(RED, RED, 4, 1, pad))
			b.add_theme_color_override("font_color", Color.WHITE if on else Color("9a9e90"))
			b.add_theme_color_override("font_hover_color", Color.WHITE)

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

# ---------------------------------------------------------------- #dead

func _build_dead() -> void:
	var col := screen("dead")
	col.add_child(h1("YOU DIED", Color("8f2018"), Color(0.7, 0.12, 0.06, 0.3)))
	col.add_child(gap(14))
	col.add_child(sub("OVERRUN"))
	col.add_child(gap(40))
	_dead_lbl = R("", 16, 4)
	_dead_lbl.add_theme_constant_override("line_separation", 14)
	col.add_child(_dead_lbl)
	col.add_child(gap(18))
	_dead_xtra = R("", 15, 4)
	_dead_xtra.add_theme_constant_override("line_separation", 12)
	col.add_child(_dead_xtra)
	col.add_child(gap(36))
	col.add_child(start_btn("RE-DEPLOY", func(): _redeploy(true)))

func _v(s: String, px := 24) -> String:
	return "[font_size=%d][color=#ffd76a][b]%s[/b][/color][/font_size]" % [px, s]

func show_dead(where: String) -> void:
	_dead_lbl.text = "[center][color=#cfcabb]DIED AT %s\nKILLS %s  ·  POINTS %s[/color][/center]" % [_v(where), _v(str(Game.kills)), _v(str(Game.points))]
	var acc := "—" if Game.shots <= 0 else "%d%%" % roundi(100.0 * Game.hits / Game.shots)
	_dead_xtra.text = "[center][color=#cfcabb]HEADSHOTS %s\nACCURACY %s  ·  TIME %s\nSURVIVORS EXTRACTED %s[/color][/center]" % [
		_v(str(Game.headshots), 22), _v(acc, 22), _v(_clock(Game.run_time), 22), _v(str(Game.saved), 22)]
	show_screen("dead")

static func _clock(sec: float) -> String:
	var s := maxi(0, roundi(sec))
	return "%02d:%02d" % [s / 60, s % 60]

# ---------------------------------------------------------------- #win

func _build_win() -> void:
	var col := screen("win")
	var t := h1("MISSION COMPLETE", Color("6fae5c"), Color(100 / 255.0, 170 / 255.0, 85 / 255.0, 0.3))
	col.add_child(t)
	col.add_child(gap(14))
	var s := sub("ALL SURVIVORS EXTRACTED", Color("8fae84"))
	col.add_child(s)
	col.add_child(gap(26))
	var gw := VBoxContainer.new()
	gw.add_theme_constant_override("separation", 10)
	col.add_child(gw)
	_grade = L("S", 170, Color(0, 0, 0, 0), 0, 900)
	_grade.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_grade.add_theme_constant_override("outline_size", 10)     # -webkit-text-stroke 5px
	gw.add_child(_grade)
	var gl := L("RATING", 10, Color("777c6c"), 6)
	gl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gw.add_child(gl)
	col.add_child(gap(26))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 48)
	grid.add_theme_constant_override("v_separation", 8)
	var gc := CenterContainer.new()
	gc.add_child(grid)
	col.add_child(gc)
	var stats: Array[Control] = []
	for k in ["KILLS", "HEADSHOTS", "ACCURACY", "SURVIVORS", "TIME", "POINTS"]:
		var cell := R("", 15, 4, false)
		cell.custom_minimum_size = Vector2(0, 30)
		grid.add_child(cell)
		_stat_lbls[k] = cell
		stats.append(cell)
	col.add_child(gap(42))
	col.add_child(start_btn("REDEPLOY", func(): _redeploy(true)))
	_win_parts = [t, s, gw]
	_win_parts.append_array(stats)

## the web's esGrade: survivors first, then how clean the shooting was
func show_win() -> void:
	var acc := 100.0 * Game.hits / maxf(1.0, Game.shots)
	var vals := {"KILLS": str(Game.kills), "HEADSHOTS": str(Game.headshots),
		"ACCURACY": ("%d%%" % roundi(acc)) if Game.shots > 0 else "—", "SURVIVORS": "%d/4" % Game.saved,
		"TIME": _clock(Game.run_time), "POINTS": str(Game.points)}
	for k in _stat_lbls:
		(_stat_lbls[k] as RichTextLabel).text = "[color=#cfcabb]%s %s[/color]" % [k, _v(vals[k], 22)]
	var g := ["C", Color("a33b32")]
	if Game.saved >= 4 and acc >= 45.0:
		g = ["S", Color("ffd76a")]
	elif Game.saved >= 3 and acc >= 35.0:
		g = ["A", Color("6fae5c")]
	elif Game.saved >= 2:
		g = ["B", Color("e0a83c")]
	_grade.text = g[0]
	_grade.add_theme_color_override("font_outline_color", g[1])
	show_screen("win")
	# es-rise: title 0, sub .12, grade .3, stats .45 + i * .09; es-pop at .35
	for i in _win_parts.size():
		var c: Control = _win_parts[i]
		c.modulate.a = 0.0
		var delay: float = [0.0, 0.12, 0.3][i] if i < 3 else 0.45 + (i - 3) * 0.09
		var tw := create_tween()
		tw.tween_interval(delay)
		tw.tween_property(c, "modulate:a", 1.0, 0.4 if i >= 2 else 0.5).set_ease(Tween.EASE_OUT)
	_grade.scale = Vector2(0.25, 0.25)
	await get_tree().process_frame
	_grade.pivot_offset = _grade.size / 2.0
	var tw2 := create_tween()
	tw2.tween_interval(0.35)
	tw2.tween_property(_grade, "scale", Vector2.ONE * 1.12, 0.34).set_ease(Tween.EASE_OUT)
	tw2.tween_property(_grade, "scale", Vector2.ONE, 0.21)
	tw2.tween_callback(func(): Game.play("gear_gopro_on", -6.0))

func _redeploy(quick: bool) -> void:
	get_tree().paused = false
	# the web: REDEPLOY after a win is the next round; after a death it is the
	# same round again; the lobby starts over at round 1
	var r := Game.round
	if not quick:
		r = 1
	elif Game.phase == "win":
		r += 1
	Game.reset_run()
	Game.round = r
	Game.quick_deploy = quick
	get_tree().reload_current_scene()
