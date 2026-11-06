class_name ChatOverlay
extends Control
## Chat « dans la pièce », façon Minecraft : Entrée (appui court) ouvre une ligne
## de saisie en bas à gauche, on parle à la conscience de la salle sans quitter
## le monde ; ses réponses s'affichent au fil de l'eau puis s'estompent.
## Entrée maintenue (≥ 0,35 s) : ouvre le chat complet (panneau).
## Les réponses de la conscience (orbe) sont lues à voix haute (KWVoice).

const HOLD_TIME := 0.35
const VISIBLE_TIME := 12.0
const MAX_LINES := 8

var main: Node
var log_box: VBoxContainer
var input: LineEdit
var is_open := false
var _holding := false
var _hold_t := 0.0
var _live_line: Label = null
var _live_desk := ""


func _init() -> void:
	set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	offset_left = 16
	offset_top = -330
	offset_right = 720
	offset_bottom = -56
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_END
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(v)
	log_box = VBoxContainer.new()
	log_box.alignment = BoxContainer.ALIGNMENT_END
	log_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	log_box.add_theme_constant_override("separation", 2)
	v.add_child(log_box)
	input = LineEdit.new()
	input.placeholder_text = "Parler à la conscience…  (Entrée envoyer · Échap annuler)"
	input.visible = false
	input.text_submitted.connect(_submit)
	v.add_child(input)


func _ready() -> void:
	main = get_tree().current_scene
	Assistant.reply_chunk.connect(_on_chunk)
	Assistant.reply_ready.connect(_on_ready)


func _unhandled_input(event: InputEvent) -> void:
	if is_open or main.panel != null or main.title != null:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		_holding = true
		_hold_t = 0.0
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if is_open and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close_input()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _holding:
		_hold_t += delta
		var down := Input.is_key_pressed(KEY_ENTER) or Input.is_key_pressed(KEY_KP_ENTER)
		if _hold_t >= HOLD_TIME and down:
			_holding = false
			main.open_panel(ChatPanel.new(main.room_ai()))
		elif not down:
			_holding = false
			open_input()
	# Les lignes s'estompent quand la saisie est fermée.
	for l in log_box.get_children():
		var age: float = Time.get_ticks_msec() / 1000.0 - float(l.get_meta("t", 0.0))
		l.modulate.a = 1.0 if is_open else clampf((VISIBLE_TIME - age) / 2.0, 0.0, 1.0)


func open_input() -> void:
	is_open = true
	input.visible = true
	input.clear()
	input.grab_focus()
	main.player.enabled = false


func close_input() -> void:
	is_open = false
	input.release_focus()
	input.visible = false
	if main.panel == null:
		main.player.enabled = true


func _submit(text: String) -> void:
	var q := text.strip_edges()
	close_input()
	if q == "":
		return
	add_line("[Vous] " + q, Color(0.9, 0.9, 0.92))
	var desk: String = main.room_ai()
	_live_desk = desk
	_live_line = add_line("[%s] …" % _ai_name(desk), Color(0.62, 0.82, 1.0))
	KWVoice.stop()
	Assistant.ask(desk, main.current_room, q, "room")


func _ai_name(desk: String) -> String:
	var o: Dictionary = World.data.objects.get(desk, {})
	return str(o.get("name", "Conscience")) if not o.is_empty() else "Conscience"


func add_line(text: String, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 680
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.add_theme_font_size_override("font_size", 16)
	l.set_meta("t", Time.get_ticks_msec() / 1000.0)
	log_box.add_child(l)
	while log_box.get_child_count() > MAX_LINES:
		log_box.get_child(0).free()
	return l


func _on_chunk(desk_id: String, text: String) -> void:
	if desk_id == _live_desk and is_instance_valid(_live_line):
		_live_line.text = "[%s] %s" % [_ai_name(desk_id), _clean(text).left(400)]
		_live_line.set_meta("t", Time.get_ticks_msec() / 1000.0)


func _on_ready(desk_id: String, result: Dictionary) -> void:
	var text := _clean(str(result.get("text", "")))
	if desk_id == _live_desk and is_instance_valid(_live_line):
		_live_line.text = "[%s] %s" % [_ai_name(desk_id), text.left(400)]
		_live_line.set_meta("t", Time.get_ticks_msec() / 1000.0)
		_live_line = null
	# La conscience parle (où que l'on ait discuté avec elle).
	var o: Dictionary = World.data.objects.get(desk_id, {})
	if o.get("type", "") == "orb":
		KWVoice.speak(text)


static func _clean(t: String) -> String:
	var re := RegEx.new()
	re.compile("```[\\s\\S]*?```|[*_`#>]")
	return re.sub(t, "", true).strip_edges()
