class_name TouchControls
extends Control
## Contrôles tactiles (Android) : moitié gauche = joystick de déplacement,
## moitié droite = regarder, boutons : Interagir (E), Parler (Entrée), Sauter,
## Carte (Tab), Menu (Échap). Actif seulement sur écran tactile.

var main: Node
var _move_id := -1
var _move_origin := Vector2.ZERO
var _look_id := -1
var _knob: Panel
var _base: Panel


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_base = _circle(140, Color(1, 1, 1, 0.08))
	_knob = _circle(60, Color(1, 1, 1, 0.22))
	_base.visible = false
	_knob.visible = false
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	col.offset_left = -150
	col.offset_right = -24
	col.offset_top = -170
	col.offset_bottom = 170
	col.add_theme_constant_override("separation", 12)
	add_child(col)
	for b in [["Interagir", KEY_E], ["Parler", KEY_ENTER], ["Sauter", KEY_SPACE], ["Carte", KEY_TAB], ["Menu", KEY_ESCAPE]]:
		var btn := Button.new()
		btn.text = b[0]
		btn.custom_minimum_size = Vector2(126, 56)
		btn.focus_mode = Control.FOCUS_NONE
		var key: int = b[1]
		btn.button_down.connect(func(): _key(key, true))
		btn.button_up.connect(func(): _key(key, false))
		col.add_child(btn)


func _ready() -> void:
	main = get_tree().current_scene


func _circle(d: float, c: Color) -> Panel:
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(int(d / 2))
	p.add_theme_stylebox_override("panel", sb)
	p.size = Vector2(d, d)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(p)
	return p


func _key(k: int, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = k
	ev.physical_keycode = k
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _input(event: InputEvent) -> void:
	if main == null or main.panel != null or main.title != null:
		return
	var half := get_viewport_rect().size.x * 0.5
	if event is InputEventScreenTouch:
		if event.pressed:
			if event.position.x < half and _move_id < 0:
				_move_id = event.index
				_move_origin = event.position
				_base.position = event.position - _base.size / 2
				_knob.position = event.position - _knob.size / 2
				_base.visible = true
				_knob.visible = true
			elif event.position.x >= half and _look_id < 0 and event.position.x < get_viewport_rect().size.x - 170:
				_look_id = event.index
		else:
			if event.index == _move_id:
				_move_id = -1
				_base.visible = false
				_knob.visible = false
				for a in ["move_forward", "move_back", "move_left", "move_right"]:
					Input.action_release(a)
			elif event.index == _look_id:
				_look_id = -1
	elif event is InputEventScreenDrag:
		if event.index == _move_id:
			var v: Vector2 = (event.position - _move_origin).limit_length(70.0) / 70.0
			_knob.position = _move_origin + v * 70.0 - _knob.size / 2
			_axis("move_right", "move_left", v.x)
			_axis("move_back", "move_forward", v.y)
		elif event.index == _look_id and main.player.enabled:
			var s: float = main.player.sensitivity * 1.6
			main.player.rotate_y(-event.relative.x * s)
			main.player.head.rotation.x = clampf(main.player.head.rotation.x - event.relative.y * s, -1.45, 1.45)


func _axis(pos: String, neg: String, v: float) -> void:
	if v > 0.15:
		Input.action_press(pos, v)
		Input.action_release(neg)
	elif v < -0.15:
		Input.action_press(neg, -v)
		Input.action_release(pos)
	else:
		Input.action_release(pos)
		Input.action_release(neg)
