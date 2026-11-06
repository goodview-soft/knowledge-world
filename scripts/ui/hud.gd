class_name KWHud
extends Control
## Affichage tête haute : réticule, indication d'interaction, titre de salle,
## messages éphémères, aide, état du mode construction.

var hint: Label
var title: Label
var subtitle: Label
var toasts: VBoxContainer
var build_box: PanelContainer
var build_label: Label
var help: PanelContainer
var crosshair: ColorRect


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair = ColorRect.new()
	crosshair.color = Color(1, 1, 1, 0.8)
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.offset_left = -3
	crosshair.offset_top = -3
	crosshair.offset_right = 3
	crosshair.offset_bottom = 3
	add_child(crosshair)
	hint = _label(20, Control.PRESET_CENTER)
	hint.offset_top = 24
	hint.offset_left = -400
	hint.offset_right = 400
	title = _label(34, Control.PRESET_CENTER_TOP)
	title.offset_top = 40
	title.offset_left = -500
	title.offset_right = 500
	subtitle = _label(18, Control.PRESET_CENTER_TOP)
	subtitle.offset_top = 88
	subtitle.offset_left = -500
	subtitle.offset_right = 500
	var foot := _label(15, Control.PRESET_BOTTOM_LEFT)
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	foot.offset_left = 16
	foot.offset_top = -34
	foot.offset_right = 900
	foot.text = "F1 aide · Tab carte & recherche · B construction · N note rapide · H hub"
	foot.modulate.a = 0.7
	toasts = VBoxContainer.new()
	toasts.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	toasts.offset_left = -520
	toasts.offset_top = -260
	toasts.offset_right = -16
	toasts.offset_bottom = -16
	toasts.alignment = BoxContainer.ALIGNMENT_END
	toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(toasts)
	build_box = PanelContainer.new()
	build_box.position = Vector2(16, 16)
	build_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	build_box.visible = false
	add_child(build_box)
	build_label = Label.new()
	build_box.add_child(build_label)
	help = PanelContainer.new()
	help.set_anchors_preset(Control.PRESET_CENTER)
	help.offset_left = -380
	help.offset_right = 380
	help.offset_top = -300
	help.offset_bottom = 300
	help.visible = false
	help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(help)
	var ht := Label.new()
	ht.text = World.GUIDE_TEXT
	ht.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.add_child(ht)


func _label(size: int, preset: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.set_anchors_preset(preset)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func set_hint(t: String) -> void:
	hint.text = t


func show_room_title(t: String, sub: String) -> void:
	title.text = t
	subtitle.text = sub
	title.modulate.a = 0.0
	subtitle.modulate.a = 0.0
	var tw := create_tween().set_parallel()
	tw.tween_property(title, "modulate:a", 1.0, 0.6)
	tw.tween_property(subtitle, "modulate:a", 0.8, 0.6)
	tw.chain().tween_interval(2.0)
	tw.chain().tween_property(title, "modulate:a", 0.0, 1.2)
	tw.parallel().tween_property(subtitle, "modulate:a", 0.0, 1.2)


func toast(t: String) -> void:
	var l := Label.new()
	l.text = t
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	toasts.add_child(l)
	var tw := l.create_tween()
	tw.tween_interval(3.5)
	tw.tween_property(l, "modulate:a", 0.0, 0.8)
	tw.tween_callback(l.queue_free)


func set_build(active: bool, text: String) -> void:
	build_box.visible = active
	build_label.text = text
