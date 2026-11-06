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
	for f in d.get("facts", []):
		b.add_fact(str(f), "")
	return b

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
	if not force and rng.randf() > gossip_chance():
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
	return {"name": bot_name, "mood": mood, "facts": facts.duplicate(true), "memory": memory.duplicate(true)}

func from_dict(d: Dictionary) -> void:
	mood = str(d.get("mood", mood))
	if d.has("facts"):
		facts = d["facts"].duplicate(true)
	if d.has("memory"):
		memory = d["memory"].duplicate(true)
