class_name OSShell
extends RefCounted
## Interpréteur du terminal KW OS. run(ligne) -> texte BBCode ; les effets hors
## données (voyage, ouverture, question IA, effacement) sont posés dans `action`.

const COMMANDS := ["help", "ls", "cd", "pwd", "cat", "open", "find", "tags", "new note", "rm", "goto", "ask", "stats", "history", "clear", "date"]
const HELP := [["ls [salle]", "contenu de la salle (sous-salles/, objets, documents)"], ["cd <salle>", "changer de salle (.. parent, / hub, a/b chemin)"],
	["pwd", "chemin de la salle courante"], ["cat <note>", "afficher une note ou un document"], ["open <note>", "ouvrir dans l'éditeur / l'app adaptée"],
	["find <texte>", "recherche globale"], ["tags", "#tags et nombre de notes"], ["new note <titre>", "créer une note ici"],
	["rm <objet>", "supprimer (confirmation o/n)"], ["goto [salle]", "aller dans la salle (quitte l'OS)"], ["ask <question>", "demander à l'assistant"],
	["stats", "statistiques du monde"], ["history", "commandes précédentes"], ["clear", "effacer l'écran"], ["date", "date et heure"]]

var cwd := ""
var history: Array = []
var pending_rm := {}
var action := {}
var last_created := ""


func _init(start_room := "") -> void:
	cwd = start_room if World.data.rooms.has(start_room) else World.data.hub


static func e(s) -> String:
	return str(s).replace("[", "[lb]")


static func c(s, col: Color) -> String:
	return "[color=#%s]%s[/color]" % [col.to_html(false), e(s)]


func prompt() -> String:
	if not World.data.rooms.has(cwd):
		cwd = World.data.hub
	return "kw:%s $" % OSData.room_path(cwd)


func run(line: String) -> String:
	action = {}
	var l := line.strip_edges()
	if not pending_rm.is_empty():
		var p := pending_rm
		pending_rm = {}
		if l.to_lower() in ["o", "oui", "y", "yes"]:
			if OSData.delete("object", p.id):
				return c("Supprimé : " + p.name, KWTheme.SUCCESS)
			return c("Introuvable.", KWTheme.DANGER)
		return "Annulé."
	if l == "":
		return ""
	if history.is_empty() or history[-1] != l:
		history.append(l)
		if history.size() > 200:
			history = history.slice(-200)
	var cmd := l.get_slice(" ", 0).to_lower()
	var arg := l.substr(cmd.length()).strip_edges()
	match cmd:
		"help", "?":
			var out := []
			for h in HELP:
				out.append("  %s%s" % [c(h[0], KWTheme.ACCENT), "  " + c(h[1], KWTheme.TEXT_DIM)])
			return "Commandes :\n" + "\n".join(out) + "\n" + c("Tab : compléter · ↑↓ : historique", KWTheme.TEXT_FAINT)
		"ls", "dir":
			return _ls(arg)
		"cd":
			return _cd(arg)
		"pwd":
			return e(OSData.room_path(cwd))
		"cat", "less", "more":
			return _cat(arg)
		"open":
			var ref := _ref(arg)
			if ref.is_empty():
				return _err("introuvable : " + arg)
			action = {"open": ref}
			return "Ouverture de « %s »…" % e(arg)
		"find", "search", "grep":
			return _find(arg)
		"tags":
			var tags := NoteLinks.all_tags()
			if tags.is_empty():
				return "Aucun #tag."
			var keys := tags.keys()
			keys.sort_custom(func(a, b): return tags[a] > tags[b] or (tags[a] == tags[b] and str(a) < str(b)))
			return "\n".join(PackedStringArray(keys.map(func(k): return "  %s  %d" % [c("#" + k, KWTheme.ACCENT), tags[k]])))
		"new", "touch":
			var title := arg
			if cmd == "new":
				if not arg.to_lower().begins_with("note"):
					return _err("usage : new note <titre>")
				title = arg.substr(4).strip_edges()
			if title == "":
				return _err("usage : new note <titre>")
			last_created = OSData.create_note(cwd, title)
			return c("Note créée : ", KWTheme.SUCCESS) + e(title) + c("  (" + OSData.room_path(cwd) + ")", KWTheme.TEXT_DIM)
		"rm", "del":
			if arg == "":
				return _err("usage : rm <objet>")
			var oid := OSData.find_object(arg, cwd)
			if oid == "":
				return _err("introuvable : " + arg)
			var o: Dictionary = World.data.objects[oid]
			pending_rm = {"id": oid, "name": str(o.name)}
			return c("Supprimer « %s » (%s, %s) ? [o/N]" % [o.name, ObjectRegistry.get_def(o.type).label, OSData.room_path(o.room_id)], Color("#f0c674"))
		"goto", "go":
			var rid := cwd if arg == "" else OSData.find_room(arg, cwd)
			if rid == "":
				return _err("salle introuvable : " + arg)
			action = {"goto": rid}
			return "Voyage vers %s…" % e(OSData.room_path(rid))
		"ask":
			if arg == "":
				return _err("usage : ask <question>")
			action = {"ask": arg}
			return c("Question envoyée à l'assistant…", KWTheme.TEXT_DIM)
		"stats":
			var s := OSData.stats()
			return "  portails %d · salles %d · objets %d\n  notes %d · documents %d · relations %d · tags %d\n  tâches %d/%d faites" % [
				s.portals, s.rooms, s.objects, s.notes, s.documents, s.relations, s.tags, s.tasks_done, s.tasks]
		"history":
			var out := []
			for i in history.size():
				out.append("%4d  %s" % [i + 1, e(history[i])])
			return "\n".join(out)
		"clear", "cls":
			action = {"clear": true}
			return ""
		"date":
			return Time.get_datetime_string_from_system(false, true)
	return _err("commande inconnue : %s — tapez help" % cmd)


func _err(s: String) -> String:
	return c(s, KWTheme.DANGER)


func _ls(arg: String) -> String:
	var rid := cwd if arg == "" else OSData.find_room(arg, cwd)
	if rid == "":
		return _err("salle introuvable : " + arg)
	var out := []
	for cr in OSData.child_rooms(rid):
		out.append(c(OSData.room_name(cr) + "/", KWTheme.ACCENT))
	for o in OSData.objects_in(rid):
		var col := KWTheme.SUCCESS if NoteLinks.is_note(o) else KWTheme.TEXT
		out.append(c(o.name, col) + c("  " + ObjectRegistry.get_def(o.type).label.to_lower(), KWTheme.TEXT_FAINT))
	for d in World.docs_for_room(rid):
		out.append(c(d.name, Color("#e8c9a0")) + c("  document", KWTheme.TEXT_FAINT))
	return "\n".join(out) if not out.is_empty() else c("(vide)", KWTheme.TEXT_FAINT)


func _cd(arg: String) -> String:
	if arg == "" or arg == "~" or arg == "/":
		cwd = World.data.hub
		return ""
	var cur: String = World.data.hub if arg.begins_with("/") else cwd
	for part in arg.trim_prefix("/").split("/", false):
		if part == "..":
			cur = OSData.parent_room(cur)
		elif part != ".":
			var r := OSData.find_room(part, cur)
			if r == "":
				return _err("salle introuvable : " + part)
			cur = r
	cwd = cur
	return ""


func _ref(arg: String) -> Dictionary:
	var oid := OSData.find_object(arg, cwd, true)
	if oid == "":
		oid = OSData.find_object(arg, cwd)
	if oid != "":
		return {"kind": "object", "id": oid}
	var did := OSData.find_document(arg)
	if did != "":
		return {"kind": "document", "id": did}
	var rid := OSData.find_room(arg, cwd)
	return {"kind": "room", "id": rid} if rid != "" else {}


func _cat(arg: String) -> String:
	if arg == "":
		return _err("usage : cat <note>")
	var ref := _ref(arg)
	if ref.is_empty() or ref.kind == "room":
		return _err("introuvable : " + arg)
	if ref.kind == "document":
		var d: Dictionary = World.data.documents[ref.id]
		var t := str(d.text)
		return c("── " + d.name + " ──", KWTheme.TEXT_DIM) + "\n" + e(t.left(4000)) + (c("\n… (tronqué, %d caractères)" % t.length(), KWTheme.TEXT_FAINT) if t.length() > 4000 else "")
	var o: Dictionary = World.data.objects[ref.id]
	var txt := ObjectRegistry.text_of(o)
	return c("── %s · %s ──" % [o.name, OSData.room_path(o.room_id)], KWTheme.TEXT_DIM) + "\n" + (e(txt) if txt.strip_edges() != "" else c("(vide)", KWTheme.TEXT_FAINT))


func _find(arg: String) -> String:
	if arg == "":
		return _err("usage : find <texte>")
	var res := World.search(arg, 40)
	if res.is_empty():
		return "Aucun résultat pour « %s »." % e(arg)
	return "\n".join(PackedStringArray(res.map(func(r): return "  " + e(r.label)))) + c("\n%d résultat(s)" % res.size(), KWTheme.TEXT_FAINT)

# ------------------------------------------------------------------ complétion

## Renvoie {line, options[]} : ligne complétée et propositions si ambiguës.
func complete(line: String) -> Dictionary:
	var l := line.lstrip(" ")
	if not " " in l:
		return _complete_from(l, "", COMMANDS)
	var cmd := l.get_slice(" ", 0).to_lower()
	var arg := l.substr(cmd.length() + 1)
	var head := cmd + " "
	var names := []
	match cmd:
		"cd", "ls", "goto", "go":
			var base := cwd
			var pre := ""
			if "/" in arg:
				pre = arg.substr(0, arg.rfind("/") + 1)
				var sub: String = OSData.find_room(pre.trim_suffix("/"), cwd) if pre != "/" else World.data.hub
				base = sub if sub != "" else cwd
				head += pre
				arg = arg.substr(pre.length())
			names = OSData.child_rooms(base).map(func(r): return OSData.room_name(r))
			names.append("..")
			if pre == "":
				for r in World.data.rooms:
					var n := OSData.room_name(r)
					if not n in names:
						names.append(n)
		"cat", "open", "rm":
			names = OSData.objects_in(cwd).map(func(o): return str(o.name))
			for o in NoteLinks.notes():
				if not str(o.name) in names and World.data.rooms.has(o.room_id):
					names.append(str(o.name))
			if cmd != "rm":
				for d in World.data.documents.values():
					names.append(str(d.name))
		"new":
			if not arg.to_lower().begins_with("note "):
				names = ["note"]
		_:
			return {"line": line, "options": []}
	return _complete_from(arg, head, names)


func _complete_from(prefix: String, head: String, names: Array) -> Dictionary:
	var p := prefix.to_lower()
	var hits := names.filter(func(n): return str(n).to_lower().begins_with(p))
	if hits.is_empty():
		return {"line": head + prefix, "options": []}
	if hits.size() == 1:
		return {"line": head + str(hits[0]) + ("" if str(hits[0]).ends_with("/") else " "), "options": []}
	var common: String = hits[0]
	for h in hits:
		var i := 0
		var hs := str(h)
		while i < common.length() and i < hs.length() and common[i].to_lower() == hs[i].to_lower():
			i += 1
		common = common.left(i)
	if common.length() < prefix.length():
		common = prefix
	return {"line": head + common, "options": hits}
