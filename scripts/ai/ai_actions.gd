class_name AIActions
extends RefCounted
## Extraction et nettoyage du bloc ```actions``` renvoyé par un modèle de langage.

const MAX_PROPOSALS := 4


## Texte affichable (pendant le streaming aussi) : sans <think>, sans bloc d'actions.
static func visible_text(raw: String) -> String:
	var t := raw
	while true:
		var a := t.find("<think>")
		if a < 0:
			break
		var b := t.find("</think>", a)
		t = t.left(a) if b < 0 else t.left(a) + t.substr(b + 8)
	var i := t.find("```actions")
	if i >= 0:
		t = t.left(i)
	# Début de bloc encore incomplet en fin de flux (« ` », « ``` », « ```act »…).
	var re := RegEx.new()
	re.compile("`{1,3}[a-z]*\\s*$")
	var m := re.search(t)
	if m != null and "actions".begins_with(m.get_string().replace("`", "").strip_edges()):
		t = t.left(m.get_start())
	return t.strip_edges()


## -> {text, proposals}
static func parse(raw: String, room_id := "") -> Dictionary:
	var props := []
	var text := raw
	var re := RegEx.new()
	re.compile("```\\s*(?:actions|json)?\\s*(\\[[\\s\\S]*?\\])\\s*(?:```|$)")
	for m in re.search_all(raw):
		var body := m.get_string(1)
		if not "kind" in body:
			continue
		var j = JSON.parse_string(body)
		if j is Array:
			props.append_array(normalize(j, room_id))
		text = text.replace(m.get_string(), "")
	return {"text": visible_text(text), "proposals": props.slice(0, MAX_PROPOSALS)}


static func normalize(items: Array, room_id := "") -> Array:
	var out := []
	for it in items:
		if not it is Dictionary:
			continue
		var kind := str(it.get("kind", "")).to_lower()
		var nm := str(it.get("name", "")).strip_edges().left(60)
		match kind:
			"note":
				var txt := str(it.get("text", "")).strip_edges()
				if txt != "":
					out.append({"kind": "note", "name": nm if nm != "" else "Note de l'assistant", "text": txt.left(4000)})
			"kanban":
				var cards := []
				var raw_cards = it.get("cards", [])
				if raw_cards is Array:
					for c in raw_cards:
						var s := str(c.get("title", c.get("text", ""))) if c is Dictionary else str(c)
						if s.strip_edges() != "":
							cards.append(s.strip_edges().left(80))
				if not cards.is_empty():
					out.append({"kind": "kanban", "name": nm if nm != "" else "Plan", "cards": cards.slice(0, 20)})
			"room":
				if nm.length() >= 2:
					out.append({"kind": "room", "name": nm})
			"relation":
				var target := str(it.get("to_room_name", it.get("to_room", nm))).strip_edges().to_lower()
				var rid := find_room(target)
				if rid != "" and rid != room_id:
					out.append({"kind": "relation", "name": World.data.rooms[rid].name, "to_room": rid})
	return out


static func find_room(name_low: String) -> String:
	if name_low == "":
		return ""
	var partial := ""
	for r in World.data.rooms.values():
		var n := str(r.name).to_lower()
		if n == name_low:
			return r.id
		if partial == "" and (n.contains(name_low) or name_low.contains(n)):
			partial = r.id
	return partial
