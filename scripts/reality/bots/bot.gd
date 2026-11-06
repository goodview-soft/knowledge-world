class_name Bot
extends CharacterBody3D
## Bot 3D stylisé : errance, bulle de texte, conversations entre bots.

signal said(text: String)

const SPEED := 1.4
var brain: BotBrain
var waypoints: Array = []
var busy := false          # en conversation
var _target := Vector3.ZERO
var _has_target := false
var _pause := 0.0
var _label: Label3D
var _fade := 0.0

static func create(b: BotBrain) -> Bot:
	var bot := Bot.new()
	bot.brain = b
	bot.name = b.bot_name
	var mat := StandardMaterial3D.new()
	mat.albedo_color = b.color
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.3
	cap.height = 1.4
	body.mesh = cap
	body.material_override = mat
	body.position.y = 0.7
	bot.add_child(body)
	var head := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.22
	sph.height = 0.44
	head.mesh = sph
	head.material_override = mat
	head.position.y = 1.62
	bot.add_child(head)
	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.3
	shape.height = 1.7
	col.shape = shape
	col.position.y = 0.85
	bot.add_child(col)
	var l := Label3D.new()
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.position.y = 2.2
	l.pixel_size = 0.006
	l.font_size = 40
	l.outline_size = 10
	l.width = 500
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.modulate.a = 0.0
	bot.add_child(l)
	bot._label = l
	return bot

func set_waypoints(points: Array) -> void:
	waypoints = points.duplicate()

func say_text(text: String, duration := 4.0) -> void:
	if _label:
		_label.text = text
		_label.modulate.a = 1.0
	_fade = duration
	said.emit(text)

func talk_to_player(text: String, cb: Callable) -> void:
	var dlg := _dialogue()
	var done := func(r: String) -> void:
		say_text(r)
		cb.call(r)
	if dlg:
		dlg.answer_player(brain, text, done)
	else:
		done.call(BotDialogue.fallback_player(brain, text))

func _dialogue() -> BotDialogue:
	var d = get_meta("dialogue", null)
	return d as BotDialogue

func is_free() -> bool:
	return not busy

## Conversation courte avec un autre bot (2-4 répliques) puis ragots.
func converse_with(other: Bot, dlg: BotDialogue, rng: RandomNumberGenerator, done := Callable()) -> void:
	busy = true
	other.busy = true
	var n := rng.randi_range(2, 4)
	_turn(other, dlg, rng, n, "", done)

func _turn(other: Bot, dlg: BotDialogue, rng: RandomNumberGenerator, left: int, heard: String, done: Callable) -> void:
	if left <= 0:
		var g := BotBrain.exchange_gossip(brain, other.brain, rng)
		for e in g:
			print_debug("ragot ", e)
		busy = false
		other.busy = false
		if done.is_valid():
			done.call(g)
		return
	dlg.say(brain, other.brain.bot_name, heard, func(t: String) -> void:
		if not is_inside_tree():
			return
		say_text(t)
		get_tree().create_timer(2.5).timeout.connect(func() -> void:
			if is_inside_tree():
				other._turn(self, dlg, rng, left - 1, t, done)))

func _physics_process(delta: float) -> void:
	if _fade > 0.0:
		_fade -= delta
		if _fade < 1.0:
			_label.modulate.a = maxf(0.0, _fade)
	if busy or waypoints.is_empty():
		velocity = Vector3.ZERO
		return
	if _pause > 0.0:
		_pause -= delta
		return
	if not _has_target:
		_target = waypoints[randi() % waypoints.size()]
		_has_target = true
	var to := _target - global_position
	to.y = 0.0
	if to.length() < 0.4:
		_has_target = false
		_pause = randf_range(2.0, 6.0)
		return
	var dir := to.normalized()
	velocity = dir * SPEED
	look_at(global_position + dir, Vector3.UP)
	move_and_slide()
