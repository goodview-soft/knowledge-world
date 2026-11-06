class_name OSWindow
extends Control
## Fenêtre de KW OS : barre de titre (glisser, double-clic = agrandir), boutons
## réduire / agrandir / fermer, poignées de redimensionnement (bord droit, bas, coin).

signal close_requested(win: OSWindow)
signal minimize_requested(win: OSWindow)
signal layout_changed(win: OSWindow)

const MIN_SIZE := Vector2(380, 260)
const BAR_H := 40.0

var key: String
var app: Control
var maximized := false
var minimized := false
var active := false
var restore_rect := Rect2()
var frame: PanelContainer
var bar: PanelContainer
var title_lbl: Label
var max_btn: Button
var _drag := false
var _resize := Vector2.ZERO


func _init(k: String, title: String, glyph: String, tint: Color, content: Control) -> void:
	key = k
	app = content
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	frame = PanelContainer.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(frame)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	frame.add_child(v)
	bar = PanelContainer.new()
	bar.custom_minimum_size.y = BAR_H
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	bar.gui_input.connect(_bar_input)
	v.add_child(bar)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(h)
	var ic := OSWindow.tile(glyph, tint, 22, 11)
	h.add_child(ic)
	title_lbl = Label.new()
	title_lbl.text = title
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_lbl.add_theme_font_size_override("font_size", 14)
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(title_lbl)
	_bar_btn(h, "–", func(): minimize_requested.emit(self), "Réduire")
	max_btn = _bar_btn(h, "□", toggle_maximize, "Agrandir")
	var x := _bar_btn(h, "✕", func(): close_requested.emit(self), "Fermer")
	x.add_theme_color_override("font_hover_color", KWTheme.DANGER)
	var pad := MarginContainer.new()
	pad.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 14)
	pad.add_theme_constant_override("margin_top", 10)
	v.add_child(pad)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_child(content)
	# Poignées de redimensionnement.
	_grip(Vector2(1, 0), Control.PRESET_RIGHT_WIDE, Vector2(6, 0), Control.CURSOR_HSIZE)
	_grip(Vector2(0, 1), Control.PRESET_BOTTOM_WIDE, Vector2(0, 6), Control.CURSOR_VSIZE)
	_grip(Vector2(1, 1), Control.PRESET_BOTTOM_RIGHT, Vector2(18, 18), Control.CURSOR_FDIAGSIZE)
	set_active(false)


## Petite tuile d'icône : carré arrondi coloré + glyphe.
static func tile(glyph: String, tint: Color, side := 44, fs := 18) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(side, side)
	var sb := KWTheme.box(Color(tint, 0.22), int(side * 0.28), Vector4(0, 0, 0, 0), Color(tint, 0.45), 1)
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.text = glyph
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", tint.lightened(0.35))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	return p


func _bar_btn(parent: Control, glyph: String, cb: Callable, tip: String) -> Button:
	var b := KWPanel.icon_btn(parent, glyph, cb, tip)
	b.custom_minimum_size = Vector2(30, 26)
	b.focus_mode = Control.FOCUS_NONE
	return b


func _grip(dir: Vector2, preset: int, sz: Vector2, cursor: int) -> void:
	var g := Control.new()
	g.set_anchors_and_offsets_preset(preset)
	if dir.x > 0:
		g.offset_left = -sz.x
	if dir.y > 0:
		g.offset_top = -sz.y
	g.mouse_default_cursor_shape = cursor
	g.mouse_filter = Control.MOUSE_FILTER_STOP
	g.gui_input.connect(func(e: InputEvent): _grip_input(e, dir))
	add_child(g)


func set_active(on: bool) -> void:
	active = on
	var sb := KWTheme.box(Color(KWTheme.SURFACE, 0.985), 14, Vector4(0, 0, 0, 0), Color(KWTheme.ACCENT, 0.45) if on else KWTheme.BORDER_STRONG, 1)
	sb.shadow_color = Color(0, 0, 0, 0.55 if on else 0.3)
	sb.shadow_size = 28 if on else 14
	sb.shadow_offset = Vector2(0, 10)
	frame.add_theme_stylebox_override("panel", sb)
	var bsb := KWTheme.box(Color(KWTheme.SURFACE_2, 1.0 if on else 0.7), 14, Vector4(14, 6, 8, 6))
	bsb.corner_radius_bottom_left = 0
	bsb.corner_radius_bottom_right = 0
	bar.add_theme_stylebox_override("panel", bsb)
	title_lbl.add_theme_color_override("font_color", KWTheme.TEXT if on else KWTheme.TEXT_DIM)


func rect() -> Rect2:
	return Rect2(position, size)


func area() -> Vector2:
	var p := get_parent() as Control
	return p.size if p != null else Vector2(1600, 800)


func set_rect(r: Rect2) -> void:
	size = Vector2(maxf(r.size.x, MIN_SIZE.x), maxf(r.size.y, MIN_SIZE.y))
	position = r.position
	_clamp()


func _clamp() -> void:
	var a := area()
	position.x = clampf(position.x, -size.x + 140, maxf(a.x - 140, 0))
	position.y = clampf(position.y, 0, maxf(a.y - BAR_H, 0))


func toggle_maximize() -> void:
	set_maximized(not maximized)
	layout_changed.emit(self)


func set_maximized(on: bool) -> void:
	if on == maximized:
		return
	maximized = on
	if on:
		restore_rect = rect()
		position = Vector2.ZERO
		size = area()
	else:
		set_rect(restore_rect)
	max_btn.text = "❐" if on else "□"
	max_btn.tooltip_text = "Restaurer" if on else "Agrandir"


func fit_area() -> void:
	if maximized:
		position = Vector2.ZERO
		size = area()
	else:
		_clamp()


func _bar_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.double_click and e.pressed:
			toggle_maximize()
			_drag = false
		else:
			_drag = e.pressed
			if not e.pressed:
				layout_changed.emit(self)
	elif e is InputEventMouseMotion and _drag:
		if maximized:
			# Glisser une fenêtre agrandie la restaure sous le curseur.
			var ratio: float = e.position.x / maxf(size.x, 1.0)
			set_maximized(false)
			position = Vector2(e.global_position.x - get_parent().global_position.x - size.x * ratio, 0)
		position += e.relative
		_clamp()


func _grip_input(e: InputEvent, dir: Vector2) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		_resize = dir if e.pressed and not maximized else Vector2.ZERO
		if not e.pressed:
			layout_changed.emit(self)
	elif e is InputEventMouseMotion and _resize != Vector2.ZERO:
		var a := area()
		size.x = clampf(size.x + e.relative.x * _resize.x, MIN_SIZE.x, a.x - position.x)
		size.y = clampf(size.y + e.relative.y * _resize.y, MIN_SIZE.y, a.y - position.y)


func to_layout() -> Dictionary:
	var r := restore_rect if maximized else rect()
	return {"rect": [int(r.position.x), int(r.position.y), int(r.size.x), int(r.size.y)], "max": maximized, "min": minimized}
