class_name BotDirector
extends Node
## Charge bots.json, attribue foyers/travail, simule la journée (horloge, emplois du temps,
## événements, relations) et orchestre les rencontres. Seuls les bots proches ont dialogue/animation.

const DATA_PATH := "res://data/bots/bots.json"
const EVENTS_PATH := "res://data/city/events.json"
const MEET_DIST := 3.0
const LISTEN_DIST := 25.0
const DETAIL_DIST := 45.0

var brains: Array = []
var bots: Array = []
var dialogue: BotDialogue
var listener := Vector3.ZERO
var rng := RandomNumberGenerator.new()
var clock := GameClock.new()
var city: CityBuilder
var events: Array = []
var announced := {}
var blackout := false
var _night_on := false
var _cooldown := 0.0
var _conversing := false
var _acc := 0.0
var _pair_cd := {}
var _by_name := {}

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
		var b := BotBrain.from_def(d)
		b.world_info = answer_info
		brains.append(b)
	for b in brains:   # liens symétriques + affinités initiales
		for l in b.links:
			var o := brain_of(str(l["with"]))
			if o == null:
				continue
			var has := false
			for l2 in o.links:
				if l2["with"] == b.bot_name:
					has = true
			if not has:
				o.links.append({"with": b.bot_name, "type": l["type"]})
			var a: float = float(BotBrain.LINK_AFFINITY.get(str(l["type"]), 0.0))
			b.affinity[o.bot_name] = a
			o.affinity[b.bot_name] = a
	return brains

func set_listener(pos: Vector3) -> void:
	listener = pos

func brain_of(bot_name: String) -> BotBrain:
	for b in brains:
		if b.bot_name == bot_name:
			return b
	return null

# --- Mise en place : foyers, travail, événements ---

func setup(c: CityBuilder, events_path := EVENTS_PATH) -> void:
	city = c
	if brains.is_empty():
		load_brains()
	var f := FileAccess.open(events_path, FileAccess.READ)
	if f != null:
		var d = JSON.parse_string(f.get_as_text())
		if typeof(d) == TYPE_DICTIONARY:
			events = d.get("events", [])
			clock.day_length = float(d.get("day_length_real", 1200.0))
			clock.set_time(1, float(d.get("start_hour", 8.0)))
	assign_homes()
	for b in brains:
		var p := plan_for(b)
		_apply_plan(b, p, true)
	# départ vivant : deux bots sur trois sont déjà en route depuis chez eux
	var i := 0
	for b in brains:
		b.wrng.seed = 100 + i
		if i % 3 != 0 and not b.home.is_empty():
			b.key = ""
			b.node = int(b.home["node"])
			b.pos = city.graph.pos(b.node)
			_apply_plan(b, plan_for(b), false)
			b.step(rng.randf_range(8.0, 40.0), city.graph)
		i += 1

func assign_homes() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 7
	var res: Array = []
	for b in city.buildings:
		if b["role"] == "residence":
			res.append(b)
	var used := {}
	var by_name := {}
	for br in brains:
		var bi := -1
		for l in br.links:
			if (l["type"] == "famille" or l["type"] == "voisin") and by_name.has(l["with"]):
				bi = int(by_name[l["with"]])
		if bi < 0 and not res.is_empty():
			var free: Array = res.filter(func(x) -> bool: return not used.has(x["idx"]))
			if free.is_empty():
				free = res
			bi = int(free[r.randi() % free.size()]["idx"])
		if bi < 0:
			continue
		by_name[br.bot_name] = bi
		var bd: Dictionary = city.buildings[bi]
		var n: int = int(used.get(bi, 0))
		used[bi] = n + 1
		var fl: int = (n / 2) % int(bd["floors"])
		var apt: int = fl * 10 + n % 2 + 1
		var fl_txt := "rez-de-chaussée" if fl == 0 else "étage %d" % fl
		br.home = {"building": bi, "floor": fl, "apt": apt, "address": bd["address"], "node": int(bd["door"]),
			"desc": "au %s, %s, appartement %d" % [bd["address"], fl_txt, apt]}
		br.work_id = br.work_id if city.places.has(br.work_id) else str(city.places.keys()[0])
	for b in brains:
		b.jitter = Vector3.ZERO

func place_of(id: String) -> Dictionary:
	return city.places.get(id, {})

# --- Emploi du temps ---

func event_applies(e: Dictionary, day: int) -> bool:
	var every: int = maxi(1, int(e.get("every", 1)))
	return day >= 1 and (day - int(e.get("offset", 0))) % every == 0

func event_active(e: Dictionary) -> bool:
	return event_applies(e, clock.day) and clock.hour() >= float(e["start"]) - 0.5 and clock.hour() < float(e["end"])

func attends(b: BotBrain, e: Dictionary, day: int) -> bool:
	if str(e.get("place", "")) == "":
		return false
	if b.work_id == str(e["place"]):
		return true
	var ch := float(e.get("attendance", 0.3))
	if b.has_trait("bavard") or b.has_trait("joyeu"):
		ch += 0.2
	if b.has_trait("timide") or b.has_trait("grincheu"):
		ch -= 0.2
	return float(absi(("%s%s%d" % [b.bot_name, e["id"], day]).hash()) % 100) / 100.0 < ch

func attended_event(b: BotBrain) -> Dictionary:
	for e in events:
		if event_active(e) and attends(b, e, clock.day):
			return e
	return {}

func plan_for(b: BotBrain) -> Dictionary:
	return BotSchedule.plan(b, clock.hour(), clock.day, attended_event(b))

## Résout la cible symbolique : {node, phrase, reason, key, kind}.
func resolve(b: BotBrain, p: Dictionary) -> Dictionary:
	var t: String = p["target"]
	var node: int = int(b.home.get("node", -1))
	var phrase := "home"
	var pl := {}
	if t == "work":
		pl = place_of(b.work_id)
	elif t.begins_with("place:"):
		pl = place_of(t.substr(6))
	elif t.begins_with("friend:"):
		var fr := brain_of(t.substr(7))
		if fr != null and not fr.home.is_empty():
			node = int(fr.home["node"])
			phrase = "chez " + fr.bot_name
	elif t != "home":
		pl = place_of(t)
	if not pl.is_empty():
		node = int(pl["door"])
		phrase = "%s %s" % [pl["prep"], pl["name"]]
	var reason := "Je rentre chez moi."
	match str(p["kind"]):
		"work": reason = "Je vais travailler %s." % phrase
		"break": reason = "Je fais une pause %s." % phrase
		"visit": reason = "Je rends visite à %s." % str(t.substr(7))
		"leisure": reason = "Je vais me promener %s." % phrase
		"event":
			var ev := ""
			for e in events:
				if str(p["key"]).begins_with("event:" + str(e["id"]) + ":"):
					ev = str(e["name"])
			reason = "Je vais profiter de %s." % ev
	return {"node": node, "phrase": phrase, "reason": reason, "key": p["key"], "kind": p["kind"]}

func _apply_plan(b: BotBrain, p: Dictionary, teleport := false) -> bool:
	if p["key"] == b.key:
		return false
	var r := resolve(b, p)
	if r["node"] < 0:
		return false
	b.key = r["key"]
	b.kind = r["kind"]
	b.target = r["node"]
	b.target_phrase = r["phrase"]
	b.reason = r["reason"]
	if teleport:
		b.node = b.target
		b.pos = city.graph.pos(b.node)
		b.path = []
		return true
	var start := b.node
	if not b.path.is_empty():
		start = int(b.path[0])
	b.path = city.graph.find_path(start, b.target)
	return true

# --- Simulation ---

func spawn_in(parent: Node3D) -> void:
	if brains.is_empty():
		load_brains()
	for b in brains:
		var bot := Bot.create(b)
		bot.set_meta("dialogue", dialogue)
		parent.add_child(bot)
		bot.position = b.pos
		bots.append(bot)
		_by_name[b.bot_name] = bot

func _process(delta: float) -> void:
	if city != null:
		sim(delta)

## Avance toute la simulation de `delta` secondes réelles.
func sim(delta: float) -> void:
	clock.advance(delta)
	_cooldown -= delta
	if city.traffic != null:
		city.traffic.sim(delta)
	var nt := clock.hour() >= 19.0 or clock.hour() < 7.0
	if nt != _night_on:
		_night_on = nt
		city.set_night(nt)
	for b in brains:
		b.decay(delta * 0.002)
		var bot = _by_name.get(b.bot_name)
		if bot == null or not bot.busy:
			b.step(delta, city.graph)
		b.hidden = b.path.is_empty() and (b.kind == "work" or b.kind == "visit" or (b.kind == "home" and clock.is_night()))
	for bot in bots:
		if is_instance_valid(bot):
			bot.sync_from_brain(listener, DETAIL_DIST)
	_acc += delta
	if _acc < 0.5:
		return
	var dt := _acc
	_acc = 0.0
	for k in _pair_cd.keys():
		_pair_cd[k] -= dt
		if _pair_cd[k] <= 0.0:
			_pair_cd.erase(k)
	tick_events()
	for b in brains:
		if _apply_plan(b, plan_for(b)):
			var bot = _by_name.get(b.bot_name)
			if bot != null and not bot.busy and bot.global_position.distance_to(listener) < LISTEN_DIST:
				bot.say_text(b.reason, 3.5)
	_meetings()

func tick_events() -> void:
	var bo := false
	for e in events:
		if e.get("blackout", false) and event_applies(e, clock.day) and clock.hour() >= float(e["start"]) and clock.hour() < float(e["end"]):
			bo = true
		for td in [clock.day, clock.day + 1]:
			if not event_applies(e, td):
				continue
			var ann_day: int = td if float(e["announce"]) < float(e["start"]) else td - 1
			var ann_abs: float = ann_day * 24.0 + float(e["announce"])
			var k := "%s:%d" % [e["id"], td]
			if not announced.has(k) and clock.absolute() >= ann_abs and clock.absolute() < td * 24.0 + float(e["end"]):
				announced[k] = true
				_announce(e, td)
	if bo != blackout:
		blackout = bo
		if city != null:
			city.set_lamps(not bo)

func _announce(e: Dictionary, day: int) -> void:
	for b in brains:
		if attends(b, e, day) or rng.randf() < 0.5:
			b.refresh_fact(str(e["fact"]))

func _meetings() -> void:
	for i in brains.size():
		for j in range(i + 1, brains.size()):
			var a: BotBrain = brains[i]
			var b: BotBrain = brains[j]
			if a.hidden or b.hidden or a.pos.distance_to(b.pos) > MEET_DIST:
				continue
			var key := "%d-%d" % [i, j]
			if _pair_cd.has(key):
				continue
			var ba = _by_name.get(a.bot_name)
			var bb = _by_name.get(b.bot_name)
			var near: bool = ba != null and bb != null and ba.global_position.distance_to(listener) < LISTEN_DIST
			if near:
				if _conversing or _cooldown > 0.0 or ba.busy or bb.busy:
					continue
				_conversing = true
				_cooldown = 15.0
				_pair_cd[key] = 90.0
				ba.converse_with(bb, dialogue, rng, func(_g) -> void:
					a.met(b)
					_conversing = false)
				return
			_pair_cd[key] = 90.0
			silent_meet(a, b)

## Rencontre hors écran : affinité (demi-poids) et ragots éventuels.
func silent_meet(a: BotBrain, b: BotBrain) -> Array:
	a.met(b, 0.5)
	return BotBrain.exchange_gossip(a, b, rng)

# --- Réponses concrètes ---

static func norm(s: String) -> String:
	var t := s.to_lower()
	for pair in [["é", "e"], ["è", "e"], ["ê", "e"], ["ë", "e"], ["à", "a"], ["â", "a"], ["î", "i"], ["ï", "i"], ["ô", "o"], ["ö", "o"], ["ù", "u"], ["û", "u"], ["ü", "u"], ["ç", "c"], ["’", "'"]]:
		t = t.replace(pair[0], pair[1])
	return t

func _tokens(nt: String) -> Array:
	var clean := nt
	for ch in ["?", "!", ",", ".", ";", ":", "-", "'"]:
		clean = clean.replace(ch, " ")
	return Array(clean.split(" ", false))

func _named_in(nt: String, me: BotBrain) -> BotBrain:
	var toks := _tokens(nt)
	for o in brains:
		if toks.has(norm(o.bot_name)):
			return o
	return null

func where_is(o: BotBrain) -> String:
	if o.target_phrase == "":
		return "Je ne sais pas où est %s." % o.bot_name
	if o.hidden:
		return "%s est chez %s, je crois." % [o.bot_name, o.tonic()]
	if o.is_moving():
		return "Je crois que %s va %s." % [o.bot_name, o.target_text(false)]
	return "%s est %s." % [o.bot_name, o.target_text(false)]

func answer_info(b: BotBrain, nt: String) -> String:
	var asks := nt.contains("ou est") or nt.contains("ou habite") or nt.contains("ou se trouve") or nt.contains("ou travaille") or nt.contains("ou vit")
	if asks:
		var o := _named_in(nt, b)
		if o != null and o != b:
			if nt.contains("habite") or nt.contains("ou vit"):
				return "%s habite %s." % [o.bot_name, o.home.get("desc", "quelque part en ville")]
			if nt.contains("travaille"):
				var pw := place_of(o.work_id)
				return "%s travaille %s %s." % [o.bot_name, pw.get("prep", "à"), pw.get("name", "ici")]
			return where_is(o)
		if o == b and nt.contains("ou est"):
			return "Mais je suis juste devant toi !"
		if city != null and o == null:
			for id in city.places:
				var pl: Dictionary = city.places[id]
				if nt.contains(norm(str(id))) or nt.contains(norm(str(pl["name"]))):
					return "Rendez-vous %s %s, %s." % [pl["prep"], pl["name"], pl["address"]]
	return b.own_answer(nt)

func to_dict() -> Dictionary:
	var out := {}
	for b in brains:
		out[b.bot_name] = b.to_dict()
	return {"clock": clock.to_dict(), "announced": announced.duplicate(), "brains": out}

func from_dict(d: Dictionary) -> void:
	if brains.is_empty():
		load_brains()
	var bm: Dictionary = d.get("brains", d if not d.has("clock") else {})
	if d.has("clock"):
		clock.from_dict(d["clock"])
		announced = d.get("announced", {}).duplicate()
	for k in bm:
		var b := brain_of(str(k))
		if b:
			b.from_dict(bm[k])
