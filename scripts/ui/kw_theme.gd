class_name KWTheme
extends RefCounted
## Design system : palette sombre douce, un seul accent, coins arrondis, boutons plats.
## make() construit le Theme appliqué à toute l'UI par Main. Les variations de type
## (PrimaryButton, GhostButton, DangerButton, IconButton, Chip, Card, Header, Section,
## Dim, Pill, Toast, Slot, SlotActive) s'utilisent via `control.theme_type_variation`.

const BG := Color("#0e1014")
const SURFACE := Color("#15181e")
const SURFACE_2 := Color("#1c2028")
const SURFACE_3 := Color("#262b35")
const BORDER := Color(1, 1, 1, 0.07)
const BORDER_STRONG := Color(1, 1, 1, 0.14)
const TEXT := Color("#e7e9ee")
const TEXT_DIM := Color("#a0a7b4")
const TEXT_FAINT := Color("#6b7280")
const ACCENT := Color("#8ea8ff")
const ACCENT_DIM := Color("#8ea8ff", 0.18)
const DANGER := Color("#f2918a")
const SUCCESS := Color("#8fd6a8")
const RADIUS := 10
const FONT := 16


static func box(bg: Color, radius := RADIUS, margin := Vector4(14, 9, 14, 9), border := Color(0, 0, 0, 0), bw := 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = margin.x
	sb.content_margin_top = margin.y
	sb.content_margin_right = margin.z
	sb.content_margin_bottom = margin.w
	if bw > 0:
		sb.border_color = border
		sb.set_border_width_all(bw)
	sb.anti_aliasing = true
	return sb


static func _buttons(t: Theme, type: String, normal: Color, hover: Color, pressed: Color, fg: Color, fg_hover: Color, margin := Vector4(14, 8, 14, 8), radius := 8) -> void:
	t.set_stylebox("normal", type, box(normal, radius, margin))
	t.set_stylebox("hover", type, box(hover, radius, margin))
	t.set_stylebox("pressed", type, box(pressed, radius, margin))
	t.set_stylebox("hover_pressed", type, box(pressed, radius, margin))
	t.set_stylebox("disabled", type, box(Color(normal, normal.a * 0.5), radius, margin))
	t.set_stylebox("focus", type, box(Color(0, 0, 0, 0), radius, margin, Color(ACCENT, 0.7), 2))
	t.set_color("font_color", type, fg)
	t.set_color("font_hover_color", type, fg_hover)
	t.set_color("font_pressed_color", type, fg_hover)
	t.set_color("font_hover_pressed_color", type, fg_hover)
	t.set_color("font_focus_color", type, fg_hover)
	t.set_color("font_disabled_color", type, Color(fg, 0.4))
	t.set_color("icon_normal_color", type, fg)
	t.set_color("icon_hover_color", type, fg_hover)


static func make() -> Theme:
	var t := Theme.new()
	t.default_font_size = FONT
	# Conteneurs.
	var panel := box(Color(SURFACE, 0.97), 16, Vector4(24, 20, 24, 22), BORDER, 1)
	panel.shadow_color = Color(0, 0, 0, 0.45)
	panel.shadow_size = 24
	panel.shadow_offset = Vector2(0, 8)
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", box(SURFACE, 12))
	t.set_type_variation("Card", "PanelContainer")
	t.set_stylebox("panel", "Card", box(SURFACE_2, 12, Vector4(16, 14, 16, 14), BORDER, 1))
	t.set_type_variation("Pill", "PanelContainer")
	t.set_stylebox("panel", "Pill", box(Color(BG, 0.78), 18, Vector4(16, 7, 16, 7), BORDER, 1))
	t.set_type_variation("Toast", "PanelContainer")
	var toast := box(Color(SURFACE_2, 0.95), 12, Vector4(16, 10, 16, 10), BORDER, 1)
	toast.border_width_left = 3
	toast.border_color = ACCENT
	t.set_stylebox("panel", "Toast", toast)
	t.set_type_variation("Slot", "PanelContainer")
	t.set_stylebox("panel", "Slot", box(Color(SURFACE, 0.86), 10, Vector4(10, 8, 10, 8), BORDER, 1))
	t.set_type_variation("SlotActive", "PanelContainer")
	t.set_stylebox("panel", "SlotActive", box(Color(ACCENT, 0.22), 10, Vector4(10, 8, 10, 8), ACCENT, 2))
	t.set_type_variation("Backdrop", "PanelContainer")
	t.set_stylebox("panel", "Backdrop", box(Color(SURFACE, 0.9), 14, Vector4(18, 14, 18, 14), BORDER, 1))
	# Textes.
	t.set_color("font_color", "Label", TEXT)
	t.set_type_variation("Header", "Label")
	t.set_font_size("font_size", "Header", 24)
	t.set_color("font_color", "Header", TEXT)
	t.set_type_variation("Section", "Label")
	t.set_font_size("font_size", "Section", 12)
	t.set_color("font_color", "Section", TEXT_FAINT)
	t.set_type_variation("Dim", "Label")
	t.set_font_size("font_size", "Dim", 14)
	t.set_color("font_color", "Dim", TEXT_DIM)
	t.set_type_variation("Kbd", "Label")
	t.set_font_size("font_size", "Kbd", 13)
	t.set_color("font_color", "Kbd", TEXT)
	t.set_stylebox("normal", "Kbd", box(SURFACE_3, 6, Vector4(8, 2, 8, 3), BORDER_STRONG, 1))
	t.set_color("default_color", "RichTextLabel", TEXT)
	# Boutons.
	_buttons(t, "Button", SURFACE_3, Color("#323846"), Color(ACCENT, 0.28), TEXT, Color.WHITE)
	t.set_type_variation("PrimaryButton", "Button")
	_buttons(t, "PrimaryButton", ACCENT, ACCENT.lightened(0.12), ACCENT.darkened(0.15), Color("#0e1220"), Color("#0e1220"))
	t.set_type_variation("GhostButton", "Button")
	_buttons(t, "GhostButton", Color(0, 0, 0, 0), Color(1, 1, 1, 0.06), Color(1, 1, 1, 0.1), TEXT_DIM, TEXT)
	t.set_type_variation("DangerButton", "Button")
	_buttons(t, "DangerButton", Color(DANGER, 0.1), Color(DANGER, 0.2), Color(DANGER, 0.3), DANGER, Color("#ffd6d2"))
	t.set_type_variation("IconButton", "Button")
	_buttons(t, "IconButton", Color(0, 0, 0, 0), Color(1, 1, 1, 0.08), Color(1, 1, 1, 0.14), TEXT_DIM, TEXT, Vector4(10, 6, 10, 6), 8)
	t.set_type_variation("Chip", "Button")
	_buttons(t, "Chip", Color(1, 1, 1, 0.04), ACCENT_DIM, Color(ACCENT, 0.3), TEXT_DIM, TEXT, Vector4(12, 5, 12, 5), 16)
	t.set_font_size("font_size", "Chip", 14)
	t.set_type_variation("MenuItem", "Button")
	_buttons(t, "MenuItem", Color(0, 0, 0, 0), Color(1, 1, 1, 0.06), ACCENT_DIM, TEXT, Color.WHITE, Vector4(16, 12, 16, 12), 10)
	t.set_constant("h_separation", "Button", 8)
	for ty in ["CheckBox", "CheckButton"]:
		_buttons(t, ty, Color(0, 0, 0, 0), Color(1, 1, 1, 0.04), Color(0, 0, 0, 0), TEXT_DIM, TEXT, Vector4(6, 4, 6, 4))
	t.set_icon("checked", "CheckBox", _check_icon(true))
	t.set_icon("unchecked", "CheckBox", _check_icon(false))
	t.set_icon("checked", "CheckButton", _toggle_icon(true))
	t.set_icon("unchecked", "CheckButton", _toggle_icon(false))
	_buttons(t, "OptionButton", SURFACE_3, Color("#323846"), Color("#323846"), TEXT, Color.WHITE, Vector4(12, 8, 12, 8))
	t.set_icon("arrow", "OptionButton", _chevron())
	_buttons(t, "ColorPickerButton", SURFACE_2, SURFACE_3, SURFACE_3, TEXT, Color.WHITE, Vector4(6, 6, 6, 6))
	# Champs.
	for ty in ["LineEdit", "TextEdit"]:
		var m := Vector4(12, 9, 12, 9)
		t.set_stylebox("normal", ty, box(BG, 8, m, BORDER, 1))
		t.set_stylebox("focus", ty, box(BG, 8, m, Color(ACCENT, 0.8), 1))
		t.set_stylebox("read_only", ty, box(Color(BG, 0.5), 8, m, BORDER, 1))
		t.set_color("font_color", ty, TEXT)
		t.set_color("font_placeholder_color", ty, TEXT_FAINT)
		t.set_color("caret_color", ty, ACCENT)
		t.set_color("selection_color", ty, Color(ACCENT, 0.3))
		t.set_color("font_readonly_color", ty, TEXT_DIM)
	t.set_color("background_color", "TextEdit", Color(0, 0, 0, 0))
	t.set_constant("line_spacing", "TextEdit", 6)
	# Listes / arbres.
	var list_bg := box(BG, 10, Vector4(6, 6, 6, 6), BORDER, 1)
	var sel := box(ACCENT_DIM, 6, Vector4(8, 4, 8, 4))
	var hov := box(Color(1, 1, 1, 0.04), 6, Vector4(8, 4, 8, 4))
	for ty in ["ItemList", "Tree"]:
		t.set_stylebox("panel", ty, list_bg)
		t.set_stylebox("focus", ty, StyleBoxEmpty.new())
		t.set_stylebox("selected", ty, sel)
		t.set_stylebox("selected_focus", ty, sel)
		t.set_stylebox("hovered", ty, hov)
		t.set_stylebox("cursor", ty, StyleBoxEmpty.new())
		t.set_stylebox("cursor_unfocused", ty, StyleBoxEmpty.new())
		t.set_color("font_color", ty, TEXT_DIM)
		t.set_color("font_selected_color", ty, Color.WHITE)
		t.set_color("font_hovered_color", ty, TEXT)
		t.set_color("guide_color", ty, Color(0, 0, 0, 0))
	t.set_constant("v_separation", "ItemList", 6)
	t.set_constant("v_separation", "Tree", 8)
	t.set_constant("item_margin", "Tree", 18)
	t.set_constant("inner_item_margin_left", "Tree", 6)
	t.set_constant("draw_relationship_lines", "Tree", 0)
	t.set_color("relationship_line_color", "Tree", Color(1, 1, 1, 0.06))
	t.set_icon("arrow", "Tree", _chevron())
	t.set_icon("arrow_collapsed", "Tree", _chevron(true))
	# Menus déroulants / infobulles.
	t.set_stylebox("panel", "PopupMenu", box(SURFACE_2, 10, Vector4(6, 6, 6, 6), BORDER_STRONG, 1))
	t.set_stylebox("hover", "PopupMenu", box(ACCENT_DIM, 6))
	t.set_color("font_color", "PopupMenu", TEXT_DIM)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_constant("v_separation", "PopupMenu", 8)
	t.set_stylebox("panel", "TooltipPanel", box(SURFACE_3, 8, Vector4(10, 6, 10, 6), BORDER_STRONG, 1))
	t.set_color("font_color", "TooltipLabel", TEXT)
	# Barres de défilement fines.
	for o in ["V", "H"]:
		var ty: String = o + "ScrollBar"
		t.set_stylebox("scroll", ty, box(Color(0, 0, 0, 0), 4, Vector4(3, 3, 3, 3)))
		t.set_stylebox("grabber", ty, box(Color(1, 1, 1, 0.14), 4, Vector4(3, 3, 3, 3)))
		t.set_stylebox("grabber_highlight", ty, box(Color(1, 1, 1, 0.24), 4, Vector4(3, 3, 3, 3)))
		t.set_stylebox("grabber_pressed", ty, box(Color(ACCENT, 0.6), 4, Vector4(3, 3, 3, 3)))
		for ic in ["increment", "decrement", "increment_highlight", "decrement_highlight"]:
			t.set_icon(ic, ty, ImageTexture.new())
	# Curseurs, séparateurs, onglets, barres de progression.
	for ty in ["HSlider", "VSlider"]:
		t.set_stylebox("slider", ty, box(SURFACE_3, 3, Vector4(0, 2, 0, 2)))
		t.set_stylebox("grabber_area", ty, box(ACCENT, 3, Vector4(0, 2, 0, 2)))
		t.set_stylebox("grabber_area_highlight", ty, box(ACCENT.lightened(0.1), 3, Vector4(0, 2, 0, 2)))
		t.set_icon("grabber", ty, _dot(18, Color.WHITE))
		t.set_icon("grabber_highlight", ty, _dot(18, Color.WHITE))
	var sep := StyleBoxLine.new()
	sep.color = BORDER
	sep.thickness = 1
	t.set_stylebox("separator", "HSeparator", sep)
	t.set_constant("separation", "HSeparator", 12)
	var vsep := StyleBoxLine.new()
	vsep.color = BORDER
	vsep.vertical = true
	t.set_stylebox("separator", "VSeparator", vsep)
	t.set_stylebox("panel", "TabContainer", box(SURFACE_2, 10, Vector4(12, 12, 12, 12)))
	t.set_stylebox("tab_selected", "TabContainer", box(SURFACE_2, 8, Vector4(14, 7, 14, 7)))
	t.set_stylebox("tab_unselected", "TabContainer", box(Color(0, 0, 0, 0), 8, Vector4(14, 7, 14, 7)))
	t.set_stylebox("tab_hovered", "TabContainer", box(Color(1, 1, 1, 0.05), 8, Vector4(14, 7, 14, 7)))
	t.set_color("font_selected_color", "TabContainer", TEXT)
	t.set_color("font_unselected_color", "TabContainer", TEXT_FAINT)
	t.set_color("font_hovered_color", "TabContainer", TEXT_DIM)
	t.set_stylebox("background", "ProgressBar", box(SURFACE_3, 4, Vector4(0, 2, 0, 2)))
	t.set_stylebox("fill", "ProgressBar", box(ACCENT, 4, Vector4(0, 2, 0, 2)))
	t.set_constant("separation", "HSplitContainer", 16)
	t.set_icon("grabber", "HSplitContainer", ImageTexture.new())
	t.set_icon("grabber", "VSplitContainer", ImageTexture.new())
	t.set_constant("separation", "HBoxContainer", 8)
	t.set_constant("separation", "VBoxContainer", 8)
	t.set_constant("h_separation", "HFlowContainer", 6)
	t.set_constant("v_separation", "HFlowContainer", 6)
	t.set_constant("h_separation", "GridContainer", 12)
	t.set_constant("v_separation", "GridContainer", 10)
	return t

# ------------------------------------------------------------------ icônes procédurales

static func _img(w: int, h: int) -> Image:
	return Image.create(w, h, false, Image.FORMAT_RGBA8)


static func _dot(d: int, c: Color) -> ImageTexture:
	var im := _img(d, d)
	var r := d / 2.0
	for y in d:
		for x in d:
			var dist := Vector2(x + 0.5 - r, y + 0.5 - r).length()
			im.set_pixel(x, y, Color(c, clampf(r - dist, 0.0, 1.0)))
	return ImageTexture.create_from_image(im)


static func _rrect(im: Image, rect: Rect2, radius: float, c: Color, fill: bool) -> void:
	for y in im.get_height():
		for x in im.get_width():
			var p := Vector2(x + 0.5, y + 0.5)
			var q := (p - rect.get_center()).abs() - rect.size / 2.0 + Vector2(radius, radius)
			var dd := Vector2(maxf(q.x, 0), maxf(q.y, 0)).length() + minf(maxf(q.x, q.y), 0.0) - radius
			var a := clampf(0.5 - dd, 0.0, 1.0) if fill else clampf(1.0 - absf(dd + 0.75), 0.0, 1.0)
			if a > 0.0:
				var base := im.get_pixel(x, y)
				im.set_pixel(x, y, base.blend(Color(c, c.a * a)))


static func _check_icon(on: bool) -> ImageTexture:
	var im := _img(20, 20)
	if on:
		_rrect(im, Rect2(1, 1, 18, 18), 5, ACCENT, true)
		for i in 7:
			for k in 2:
				im.set_pixel(5 + i / 2, 9 + i / 2 + k, Color("#0e1220"))
		for i in 9:
			for k in 2:
				im.set_pixel(8 + i, 12 - i + k - 0, Color("#0e1220"))
	else:
		_rrect(im, Rect2(1, 1, 18, 18), 5, BORDER_STRONG.lightened(0.3), false)
	return ImageTexture.create_from_image(im)


static func _toggle_icon(on: bool) -> ImageTexture:
	var im := _img(36, 20)
	_rrect(im, Rect2(1, 1, 34, 18), 9, ACCENT if on else SURFACE_3, true)
	var cx := 26.0 if on else 10.0
	for y in 20:
		for x in 36:
			var a := clampf(7.0 - Vector2(x + 0.5 - cx, y + 0.5 - 10).length(), 0.0, 1.0)
			if a > 0:
				im.set_pixel(x, y, im.get_pixel(x, y).blend(Color(1, 1, 1, a)))
	return ImageTexture.create_from_image(im)


static func _chevron(right := false) -> ImageTexture:
	var im := _img(12, 12)
	for i in 4:
		for k in 2:
			if right:
				im.set_pixel(4 + i, 2 + i + k, TEXT_DIM)
				im.set_pixel(4 + i, 9 - i + k - 1, TEXT_DIM)
			else:
				im.set_pixel(2 + i + k, 4 + i, TEXT_DIM)
				im.set_pixel(9 - i + k - 1, 4 + i, TEXT_DIM)
	return ImageTexture.create_from_image(im)
