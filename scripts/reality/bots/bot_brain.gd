class_name BotBrain
extends RefCounted
## Cerveau d'un bot : fiche, humeur, mémoire courte, faits et ragots (sans 3D).

const MAX_MEMORY := 6
const MAX_FACTS := 24

var bot_name := ""
var age := 30
var job := ""
var traits: Array = []
var mood := "calme"
var interests: Array = []
var speech := ""
var color := Color.WHITE
var facts: Array = []   # {text, source ("" = connu d'origine), fresh}
var memory: Array = []  # {who, text}
# identité et société
var last_name := ""
var gender := "m"
var work_id := ""
var links: Array = []          # {with, type}
var affinity := {}             # prénom -> score -100..100
var player_memory: Array = []  # résumés courts de ce que le joueur a dit
var home := {}                 # {building, floor, apt, address, node, desc}
# simulation (position locale à la ville)
const SPEED := 1.6
var pos := Vector3.ZERO
var node := -1
var path: Array = []
var dir := Vector3.FORWARD
var hidden := false
var key := ""
var kind := ""
var target := -1
var target_phrase := ""        # « à la boulangerie », « chez Léo », « home »
var reason := ""
var jitter := Vector3.ZERO
var offset := 0.0              # décalage d'horaire en heures (0..0.6)
var world_info := Callable()   # (brain, texte normalisé) -> String

const LINK_AFFINITY := {"ami": 35.0, "famille": 45.0, "collègue": 15.0, "voisin": 10.0, "tension": -25.0}
const POS_PAIRS := [["bavard", "curieu"], ["bavard", "joyeu"], ["timide", "discr"], ["timide", "rêveu"], ["rêveu", "créati"], ["joyeu", "chaleur"],
	["sérieu", "empath"], ["calme", "timide"], ["calme", "observ"], ["bavard", "chaleur"], ["curieu", "créati"], ["calme", "chaleur"]]
const NEG_PAIRS := [["grincheu", "bavard"], ["grincheu", "joyeu"], ["impuls", "sérieu"], ["impuls", "calme"], ["grincheu", "chaleur"], ["malin", "sérieu"]]

static func from_def(d: Dictionary) -> BotBrain:
	var b := BotBrain.new()
	b.bot_name = str(d.get("name", "?"))
	b.age = int(d.get("age", 30))
	b.job = str(d.get("job", ""))
	b.traits = d.get("traits", []).duplicate()
	b.mood = str(d.get("mood", "calme"))
	b.interests = d.get("interests", []).duplicate()
	b.speech = str(d.get("speech", ""))
	b.color = Color.html(str(d.get("color", "#ffffff")))
	b.last_name = str(d.get("last", ""))
	b.gender = str(d.get("gender", "m"))
	b.work_id = str(d.get("work", ""))
	b.links = d.get("links", []).duplicate(true)
	b.offset = float(absi(b.bot_name.hash()) % 60) / 100.0
	for f in d.get("facts", []):
		b.add_fact(str(f), "")
	return b

func full_name() -> String:
	return ("%s %s" % [bot_name, last_name]).strip_edges()

func pronoun() -> String:
	return "elle" if gender == "f" else "il"

func tonic() -> String:
	return "elle" if gender == "f" else "lui"

## Compatibilité de caractère : entier (positif = s'entendent, négatif = frictions).
func compat(o: BotBrain) -> int:
	var c := 0
	for p in POS_PAIRS:
		if (has_trait(p[0]) and o.has_trait(p[1])) or (has_trait(p[1]) and o.has_trait(p[0])):
			c += 1
	for p in NEG_PAIRS:
		if (has_trait(p[0]) and o.has_trait(p[1])) or (has_trait(p[1]) and o.has_trait(p[0])):
			c -= 1
	return c

func shared_interests(o: BotBrain) -> int:
	var n := 0
	for i in interests:
		if o.interests.has(i):
			n += 1
	return n

func aff(other: String) -> float:
	return float(affinity.get(other, 0.0))

func change_aff(other: String, delta: float) -> void:
	affinity[other] = clampf(aff(other) + delta, -100.0, 100.0)

## Après une rencontre : l'affinité évolue selon les traits et intérêts communs.
func met(o: BotBrain, weight := 1.0) -> void:
	var d := (0.5 + 2.0 * compat(o) + 0.7 * shared_interests(o)) * weight
	change_aff(o.bot_name, d)
	o.change_aff(bot_name, d)

func relation_label(other: String) -> String:
	var a := aff(other)
	if a >= 30.0:
		return "ami"
	if a <= -15.0:
		return "tension"
	return "connaissance"

## Meilleur ami (affinité >= min) en excluant `skip`, ou "".
func best_friend(min_aff: float, skip := "") -> String:
	var best := ""
	var ba := min_aff
	for k in affinity:
		if k != skip and float(affinity[k]) >= ba:
			ba = float(affinity[k])
			best = str(k)
	return best

func target_text(first_person: bool) -> String:
	if target_phrase == "home":
		return "chez moi" if first_person else "chez " + tonic()
	return target_phrase

func is_moving() -> bool:
	return not path.is_empty()

## Avance le long du chemin (positions locales ; graph : CityGraph).
func step(delta: float, graph: CityGraph) -> void:
	if path.is_empty():
		_wander(delta)
		return
	jitter = Vector3.ZERO
	var rem := SPEED * delta
	while rem > 0.0 and not path.is_empty():
		var tp: Vector3 = graph.pos(int(path[0]))
		var to := tp - pos
		to.y = 0.0
		var dist := to.length()
		if dist <= rem:
			pos = tp
			node = int(path[0])
			path.pop_front()
			rem -= dist
		else:
			dir = to / dist
			pos += dir * rem
			rem = 0.0

## Flânerie autour du point d'arrivée (dehors) : de petits trajets aléatoires.
var wgoal := Vector3.ZERO
var wait := 0.0
var wrng := RandomNumberGenerator.new()

func is_wandering() -> bool:
	return not hidden and jitter.distance_to(wgoal) > 0.05

func _wander(delta: float) -> void:
	if hidden:
		return
	if jitter.distance_to(wgoal) > 0.05:
		var to := wgoal - jitter
		var d := minf(to.length(), SPEED * 0.6 * delta)
		dir = to.normalized()
		jitter += dir * d
		return
	wait -= delta
	if wait <= 0.0:
		wait = wrng.randf_range(1.5, 5.0)
		wgoal = Vector3(wrng.randf_range(-3.0, 3.0), 0, wrng.randf_range(-2.0, 2.0))

func note_player(text: String) -> void:
	var sm := text.strip_edges().left(80)
	player_memory.append(sm)
	while player_memory.size() > 4:
		player_memory.remove_at(0)
	refresh_fact("Le voyageur a dit à %s : « %s »" % [bot_name, sm])

func refresh_fact(text: String) -> void:
	for i in facts.size():
		if facts[i]["text"] == text:
			facts.remove_at(i)
			break
	add_fact(text, "")

## Réponses concrètes (sans IA) sur soi ; "" si la question n'est pas reconnue. `nt` = texte normalisé.
func own_answer(nt: String) -> String:
	var desc := str(home.get("desc", ""))
	if (nt.contains("habite") or nt.contains("ou vis")) and desc != "":
		return "J'habite %s." % desc
	if nt.contains("ou vas") or nt.contains("ou allez") or nt.contains("tu fais quoi") or nt.contains("que fais") or nt.contains("ou cours"):
		if is_moving():
			return reason if reason != "" else "Je me promène."
		if hidden or target_phrase == "home":
			return "Je suis chez moi."
		return "Je suis %s." % target_text(true) if target_phrase != "" else "Je flâne un peu."
	if nt.contains("metier") or nt.contains("travail") or nt.contains("dans la vie"):
		return "Je suis %s." % job
	if nt.contains("t'ai-je dit") or nt.contains("retiens") or nt.contains("souviens"):
		if player_memory.is_empty():
			return "Tu ne m'as encore rien dit."
		return "Tu m'as dit : « %s »." % player_memory.back()
	return ""

func has_trait(sub: String) -> bool:
	for t in traits:
		if str(t).begins_with(sub):
			return true
	return false

func knows(text: String) -> bool:
	for f in facts:
		if f["text"] == text:
			return true
	return false

func add_fact(text: String, source: String) -> bool:
	if knows(text):
		return false
	facts.append({"text": text, "source": source, "fresh": 1.0})
	if facts.size() > MAX_FACTS:
		facts.remove_at(0)
	return true

func remember(who: String, text: String) -> void:
	memory.append({"who": who, "text": text})
	while memory.size() > MAX_MEMORY:
		memory.remove_at(0)

func decay(amount := 0.05) -> void:
	for f in facts:
		f["fresh"] = maxf(0.0, float(f["fresh"]) - amount)

## Probabilité de transmettre un ragot selon les traits.
func gossip_chance() -> float:
	var p := 0.35
	if has_trait("bavard"):
		p += 0.4
	if has_trait("curieu"):
		p += 0.1
	if has_trait("timide") or has_trait("discr"):
		p -= 0.25
	if has_trait("grincheu"):
		p -= 0.1
	return clampf(p, 0.05, 0.95)

## Fait à partager avec `other` (le plus frais qu'il ne connaît pas), ou {}.
func pick_gossip(other: BotBrain, rng: RandomNumberGenerator, force := false) -> Dictionary:
	var ch := gossip_chance() + clampf(aff(other.bot_name) / 100.0, -0.3, 0.3)
	if not force and rng.randf() > clampf(ch, 0.03, 0.97):
		return {}
	var best := {}
	for f in facts:
		if other.knows(f["text"]):
			continue
		if best.is_empty() or float(f["fresh"]) > float(best["fresh"]):
			best = f
	return best

func hear(text: String, from_name: String) -> bool:
	return add_fact(text, from_name)

## Échange de ragots mutuel ; renvoie [{from,to,text}] des faits transmis.
static func exchange_gossip(a: BotBrain, b: BotBrain, rng: RandomNumberGenerator, force := false) -> Array:
	var out: Array = []
	var fa := a.pick_gossip(b, rng, force)
	var fb := b.pick_gossip(a, rng, force)
	if not fa.is_empty() and b.hear(fa["text"], a.bot_name):
		out.append({"from": a.bot_name, "to": b.bot_name, "text": fa["text"]})
	if not fb.is_empty() and a.hear(fb["text"], b.bot_name):
		out.append({"from": b.bot_name, "to": a.bot_name, "text": fb["text"]})
	return out

## Réponse à « qu'as-tu entendu ? ».
func heard_summary() -> String:
	var parts: Array = []
	for f in facts:
		if str(f["source"]) != "":
			parts.append("%s m'a dit : %s" % [f["source"], f["text"]])
	if parts.is_empty():
		return "Je n'ai rien entendu de neuf."
	return " ".join(parts.slice(max(0, parts.size() - 2)))

func random_fact(rng: RandomNumberGenerator) -> String:
	if facts.is_empty():
		return ""
	return str(facts[rng.randi() % facts.size()]["text"])

func sheet() -> String:
	return "Tu es %s, %d ans, %s. Traits : %s. Humeur : %s. Intérêts : %s. Tu parles de façon %s." % [bot_name, age, job, ", ".join(traits), mood, ", ".join(interests), speech]

func to_dict() -> Dictionary:
	return {"name": bot_name, "mood": mood, "facts": facts.duplicate(true), "memory": memory.duplicate(true),
		"affinity": affinity.duplicate(), "player_memory": player_memory.duplicate(), "home": home.duplicate(true),
		"pos": [pos.x, pos.y, pos.z], "node": node, "path": path.duplicate(), "key": key, "kind": kind, "target": target,
		"target_phrase": target_phrase, "reason": reason}

func from_dict(d: Dictionary) -> void:
	mood = str(d.get("mood", mood))
	if d.has("facts"):
		facts = d["facts"].duplicate(true)
	if d.has("memory"):
		memory = d["memory"].duplicate(true)
	if d.has("affinity"):
		for k in d["affinity"]:
			affinity[str(k)] = float(d["affinity"][k])
	if d.has("player_memory"):
		player_memory = d["player_memory"].duplicate()
	if d.has("home") and not (d["home"] as Dictionary).is_empty():
		home = (d["home"] as Dictionary).duplicate(true)
		for k in ["building", "floor", "apt", "node"]:
			if home.has(k):
				home[k] = int(home[k])
	if d.has("pos"):
		var a: Array = d["pos"]
		pos = Vector3(float(a[0]), float(a[1]), float(a[2]))
		node = int(d.get("node", node))
		path = []
		for n in d.get("path", []):
			path.append(int(n))
		key = str(d.get("key", ""))
		kind = str(d.get("kind", ""))
		target = int(d.get("target", -1))
		target_phrase = str(d.get("target_phrase", ""))
		reason = str(d.get("reason", ""))
