class_name BotDirector
extends Node
## Charge bots.json, instancie les bots, orchestre les rencontres.

const DATA_PATH := "res://data/bots/bots.json"
const MEET_DIST := 3.0
const LISTEN_DIST := 25.0

var brains: Array = []
var bots: Array = []
var dialogue: BotDialogue
var listener := Vector3.ZERO
var rng := RandomNumberGenerator.new()
var _cooldown := 0.0
var _conversing := false

func _init() -> void:
	dialogue = BotDialogue.new()
	add_child(dialogue)

static func load_defs(path := DATA_PATH) -> Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return []
	var d = JSON.parse_string(f.get_as_text())
	if typeof(d) != TYPE_DICTIONARY:
		return []
	return d.get("bots", [])

func load_brains(path := DATA_PATH) -> Array:
	brains.clear()
	for d in load_defs(path):
		brains.append(BotBrain.from_def(d))
	return brains

func set_listener(pos: Vector3) -> void:
	listener = pos

func brain_of(bot_name: String) -> BotBrain:
	for b in brains:
		if b.bot_name == bot_name:
			return b
	return null

func spawn_in(parent: Node3D, area: AABB) -> void:
	if brains.is_empty():
		load_brains()
	var pts: Array = []
	for i in 6:
		pts.append(Vector3(area.position.x + rng.randf() * area.size.x, area.position.y, area.position.z + rng.randf() * area.size.z))
	for b in brains:
		var bot := Bot.create(b)
		bot.set_meta("dialogue", dialogue)
		parent.add_child(bot)
		bot.global_position = pts[rng.randi() % pts.size()]
		bot.set_waypoints(pts)
		bots.append(bot)

func _process(delta: float) -> void:
	_cooldown -= delta
	for b in brains:
		b.decay(delta * 0.002)
	if _conversing or _cooldown > 0.0:
		return
	var near: Array = []
	for bot in bots:
		if is_instance_valid(bot) and bot.is_free() and bot.global_position.distance_to(listener) < LISTEN_DIST:
			near.append(bot)
	for i in near.size():
		for j in range(i + 1, near.size()):
			if near[i].global_position.distance_to(near[j].global_position) < MEET_DIST:
				_conversing = true
				_cooldown = 15.0
				near[i].converse_with(near[j], dialogue, rng, func(_g) -> void: _conversing = false)
				return

func to_dict() -> Dictionary:
	var out := {}
	for b in brains:
		out[b.bot_name] = b.to_dict()
	return out

func from_dict(d: Dictionary) -> void:
	if brains.is_empty():
		load_brains()
	for k in d:
		var b := brain_of(str(k))
		if b:
			b.from_dict(d[k])
