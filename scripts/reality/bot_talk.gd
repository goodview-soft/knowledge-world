class_name BotTalk
extends CanvasLayer
## Ligne de saisie pour parler à un bot dans la réalité. Entrée envoie, Échap ferme.

signal closed

var bot: Bot
var _box: PanelContainer
var _edit: LineEdit
var _reply: Label
var _hint: Label
var last_reply := ""


func _init() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	_hint = Label.new()
	_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.position.y -= 140
	_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint.visible = false
	add_child(_hint)
	_box = PanelContainer.new()
	_box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_box.offset_top = -92
	_box.offset_bottom = -16
	_box.offset_left = 60
	_box.offset_right = -60
	var v := VBoxContainer.new()
	_reply = Label.new()
	_reply.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_edit = LineEdit.new()
	_edit.placeholder_text = "Dis quelque chose… (Entrée : envoyer, Échap : fermer)"
	_edit.text_submitted.connect(submit)
	v.add_child(_reply)
	v.add_child(_edit)
	_box.add_child(v)
	_box.visible = false
	add_child(_box)


func is_open() -> bool:
	return _box.visible


func show_hint(b: Bot) -> void:
	_hint.visible = b != null and not _box.visible
	if b != null:
		_hint.text = "E : parler à %s" % b.brain.bot_name


func open(b: Bot) -> void:
	bot = b
	b.busy = true
	_box.visible = true
	_hint.visible = false
	_reply.text = "%s te regarde." % b.brain.bot_name
	_edit.text = ""
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_edit.grab_focus()


func close() -> void:
	if not _box.visible:
		return
	_box.visible = false
	if is_instance_valid(bot):
		bot.busy = false
	bot = null
	closed.emit()


func submit(text: String) -> void:
	text = text.strip_edges()
	_edit.text = ""
	if text == "" or not is_instance_valid(bot):
		return
	var who: String = bot.brain.bot_name
	bot.talk_to_player(text, func(r: String) -> void:
		last_reply = r
		_reply.text = "%s : %s" % [who, r])


func _input(event: InputEvent) -> void:
	if _box.visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
