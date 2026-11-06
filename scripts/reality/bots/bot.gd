class_name Bot
extends CharacterBody3D
## Bot 3D stylisé : errance, bulle de texte, conversations entre bots.

signal said(text: String)

const SPEED := 1.4
var brain: BotBrain
var busy := false          # en conversation
var detailed := false      # proche du joueur : animation et bulles
var _body: MeshInstance3D
var _t := 0.0
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
	bot._body = body
	var head := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.22
	sph.height = 0.44
	head.mesh = sph
	head.material_override = mat
	head.position.y = 1.62
	bot.add_child(head)
	bot.collision_layer = 0
	bot.collision_mask = 0
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

func _process(delta: float) -> void:
	if _fade > 0.0:
		_fade -= delta
		if _fade < 1.0:
			_label.modulate.a = maxf(0.0, _fade)
	if detailed and (brain.is_moving() or brain.is_wandering()) and not busy:
		_t += delta * 8.0
		_body.position.y = 0.7 + absf(sin(_t)) * 0.05

## Position interpolée depuis la simulation (pas de physique) ; détail réservé aux bots proches.
func sync_from_brain(listener: Vector3, detail_dist: float) -> void:
	position = brain.pos + brain.jitter
	visible = not brain.hidden
	var d := global_position.distance_to(listener)
	detailed = d < detail_dist
	set_process(detailed or _fade > 0.0)
	if detailed and visible and (brain.is_moving() or brain.is_wandering()):
		rotation.y = atan2(-brain.dir.x, -brain.dir.z)
	if not detailed:
		_label.modulate.a = 0.0
