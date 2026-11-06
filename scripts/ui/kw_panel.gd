class_name KWPanel
extends PanelContainer
## Base des panneaux d'édition : titre, bouton fermer, corps vertical, helpers.
## Main appelle on_close() avant de libérer le panneau (sauvegarde).

signal closed
var body: VBoxContainer
var main: Node


func _init(title: String, min_size := Vector2(900, 600)) -> void:
	custom_minimum_size = min_size
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 22)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(t)
	btn(top, "Fermer (Échap)", func(): closed.emit())
	body = VBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
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


func on_close() -> void:
	pass


static func btn(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


static func hbox(parent: Control) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
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
