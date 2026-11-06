class_name KWPanel
extends PanelContainer
## Base des panneaux d'édition : en-tête (titre, sous-titre, ✕), corps vertical, helpers.
## Main appelle on_close() avant de libérer le panneau (sauvegarde).

signal closed
var body: VBoxContainer
var main: Node
var header: HBoxContainer
var title_label: Label
var subtitle_label: Label


func _init(title: String, min_size := Vector2(900, 600)) -> void:
	custom_minimum_size = min_size
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	add_child(v)
	header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	v.add_child(header)
	var accent := ColorRect.new()
	accent.color = KWTheme.ACCENT
	accent.custom_minimum_size = Vector2(4, 26)
	accent.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(accent)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(tv)
	title_label = Label.new()
	title_label.text = title
	title_label.theme_type_variation = "Header"
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tv.add_child(title_label)
	subtitle_label = Label.new()
	subtitle_label.theme_type_variation = "Dim"
	subtitle_label.visible = false
	tv.add_child(subtitle_label)
	var esc := Label.new()
	esc.text = "Échap"
	esc.theme_type_variation = "Kbd"
	esc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	esc.modulate.a = 0.6
	header.add_child(esc)
	var x := icon_btn(header, "✕", func(): closed.emit(), "Fermer")
	x.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 2)
	v.add_child(sep)
	body = VBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	v.add_child(body)


func _ready() -> void:
	main = get_tree().current_scene
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -custom_minimum_size.x / 2
	offset_right = custom_minimum_size.x / 2
	offset_top = -custom_minimum_size.y / 2
	offset_bottom = custom_minimum_size.y / 2
	# Petite animation d'ouverture (fondu + léger zoom).
	pivot_offset = custom_minimum_size / 2
	modulate.a = 0.0
	scale = Vector2(0.97, 0.97)
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "modulate:a", 1.0, 0.16)
	tw.tween_property(self, "scale", Vector2.ONE, 0.2)


func on_close() -> void:
	pass


func set_subtitle(t: String) -> void:
	subtitle_label.text = t
	subtitle_label.visible = t != ""

# ------------------------------------------------------------------ helpers (API stable)

static func btn(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	b.focus_mode = Control.FOCUS_CLICK
	parent.add_child(b)
	return b


static func hbox(parent: Control) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	parent.add_child(h)
	return h


static func lbl(parent: Control, text: String, size := 0) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if size > 0:
		l.add_theme_font_size_override("font_size", size)
	parent.add_child(l)
	return l


static func line(parent: Control, text := "", placeholder := "") -> LineEdit:
	var e := LineEdit.new()
	e.text = text
	e.placeholder_text = placeholder
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(e)
	return e

# ------------------------------------------------------------------ helpers (design system)

## Bouton d'une variation donnée (PrimaryButton, GhostButton, DangerButton, Chip, MenuButton…).
static func styled_btn(parent: Control, text: String, cb: Callable, variation: String) -> Button:
	var b := btn(parent, text, cb)
	b.theme_type_variation = variation
	return b


static func primary(parent: Control, text: String, cb: Callable) -> Button:
	return styled_btn(parent, text, cb, "PrimaryButton")


static func ghost(parent: Control, text: String, cb: Callable) -> Button:
	return styled_btn(parent, text, cb, "GhostButton")


static func danger(parent: Control, text: String, cb: Callable) -> Button:
	return styled_btn(parent, text, cb, "DangerButton")


static func chip(parent: Control, text: String, cb: Callable) -> Button:
	return styled_btn(parent, text, cb, "Chip")


static func icon_btn(parent: Control, glyph: String, cb: Callable, tooltip := "") -> Button:
	var b := styled_btn(parent, glyph, cb, "IconButton")
	b.tooltip_text = tooltip
	return b


## Carte (surface légèrement surélevée) ; renvoie son conteneur vertical intérieur.
static func card(parent: Control, title := "") -> VBoxContainer:
	var pc := PanelContainer.new()
	pc.theme_type_variation = "Card"
	parent.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	pc.add_child(v)
	if title != "":
		section(v, title)
	return v


## Titre de section discret (petites capitales).
static func section(parent: Control, text: String) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.theme_type_variation = "Section"
	parent.add_child(l)
	return l


static func dim(parent: Control, text: String) -> Label:
	var l := lbl(parent, text)
	l.theme_type_variation = "Dim"
	return l


static func sep(parent: Control) -> HSeparator:
	var s := HSeparator.new()
	parent.add_child(s)
	return s


static func spacer(parent: Control) -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(c)
	return c


## Ligne « libellé — contrôle » alignée ; renvoie la HBox pour y ajouter le contrôle.
static func field(parent: Control, label_text: String, label_w := 150.0) -> HBoxContainer:
	var h := hbox(parent)
	var l := Label.new()
	l.text = label_text
	l.theme_type_variation = "Dim"
	l.custom_minimum_size.x = label_w
	h.add_child(l)
	return h


## Curseur avec valeur affichée. cb(value) appelé à chaque changement.
static func slider(parent: Control, label_text: String, value: float, lo: float, hi: float, step: float, cb: Callable, fmt := "%.2f") -> HSlider:
	var h := field(parent, label_text)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.focus_mode = Control.FOCUS_CLICK
	h.add_child(s)
	var v := Label.new()
	v.text = fmt % value
	v.custom_minimum_size.x = 56
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.theme_type_variation = "Dim"
	h.add_child(v)
	s.value_changed.connect(func(x: float):
		v.text = fmt % x
		cb.call(x))
	return s


static func color_field(parent: Control, label_text: String, value: Color, cb: Callable) -> ColorPickerButton:
	var h := field(parent, label_text)
	var c := ColorPickerButton.new()
	c.color = value
	c.edit_alpha = false
	c.custom_minimum_size = Vector2(120, 34)
	c.focus_mode = Control.FOCUS_CLICK
	c.color_changed.connect(cb)
	h.add_child(c)
	return c


## Groupe de boutons-chips exclusifs ; cb(key). Renvoie {key: Button}.
static func choice(parent: Control, label_text: String, options: Array, current: String, cb: Callable) -> Dictionary:
	var h := field(parent, label_text)
	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(flow)
	var group := ButtonGroup.new()
	var out := {}
	for opt in options:
		var key: String = opt[0]
		var b := chip(flow, opt[1], func(): cb.call(key))
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = key == current
		out[key] = b
	return out
