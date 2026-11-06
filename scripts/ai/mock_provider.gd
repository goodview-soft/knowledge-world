class_name MockProvider
extends AIProvider
## Assistant simulé, local et déterministe : exploite réellement le contexte
## (objets de la salle, documents, autres salles) sans aucun modèle IA.

func display_name() -> String:
	return "Assistant simulé (local, sans IA)"


func complete(ctx: Dictionary, _history: Array, cb: Callable, _on_chunk := Callable()) -> void:
	var q: String = ctx.question.to_lower()
	var room: Dictionary = ctx.room
	var res := {"text": "", "proposals": []}
	var notes: Array = room.objects.filter(func(o): return o.type in ["note", "postit", "card"])
	if "synth" in q or "résum" in q or "resum" in q:
		var lines := ["Synthèse de « %s » :" % room.name, "- %d objet(s), %d document(s) associé(s)." % [room.objects.size(), ctx.room_documents.size()]]
		for o in room.objects:
			if o.text != "":
				lines.append("- %s « %s » : %s" % [o.type_label, o.name, o.text.replace("\n", " ; ").left(140)])
		res.text = "\n".join(lines)
		res.proposals.append({"kind": "note", "name": "Synthèse · " + room.name, "text": res.text})
	elif "question" in q:
		var subj: String = room.name
		res.text = "Questions complémentaires pour « %s » :\n1. Quel est l'objectif concret de cet espace ?\n2. Quelles sources manquent pour avancer ?\n3. Quelles idées contredisent ce qui est déjà noté ?\n4. Quel est le prochain petit pas réalisable ?" % subj
		for n in notes.slice(0, 2):
			res.text += "\n5. Que faudrait-il approfondir dans « %s » ?" % n.name
		res.proposals.append({"kind": "note", "name": "Questions · " + subj, "text": res.text})
	elif "kanban" in q or "tâche" in q or "tache" in q or "plan" in q:
		var cards := []
		for n in notes:
			for l in n.text.split("\n", false):
				if l.strip_edges() != "":
					cards.append(l.strip_edges().left(60))
		if cards.is_empty():
			cards = ["Définir l'objectif", "Rassembler les sources", "Rédiger une première synthèse"]
		res.text = "Je propose un tableau Kanban avec %d carte(s) tirées des notes de la salle." % cards.size()
		res.proposals.append({"kind": "kanban", "name": "Plan · " + room.name, "cards": cards})
	elif "salle" in q or "pièce" in q:
		var nm: String = ctx.question.substr(q.find("salle") + 5).strip_edges().trim_prefix(":").strip_edges() if "salle" in q else ""
		if nm.length() < 2 or nm.length() > 60:
			nm = "Nouvelle réflexion"
		res.text = "Je peux créer une salle « %s » reliée à « %s » (une porte sera ajoutée)." % [nm, room.name]
		res.proposals.append({"kind": "room", "name": nm.capitalize()})
	elif "lien" in q or "connexion" in q or "relation" in q:
		var words := {}
		for o in room.objects:
			for t in KeywordRag.tokens(o.name + " " + o.text):
				words[t] = true
		for t in KeywordRag.tokens(room.name):
			words[t] = true
		var found := []
		for r in ctx.global.rooms:
			if r.id == room.id:
				continue
			for t in KeywordRag.tokens(r.name + " " + r.text):
				if words.has(t):
					found.append(r)
					break
		if found.is_empty():
			res.text = "Je ne trouve pas de connexion évidente par mots-clés. Ajoutez des notes pour enrichir le contexte."
		else:
			res.text = "Connexions possibles (mots communs) :\n" + "\n".join(found.slice(0, 5).map(func(r): return "- " + r.name))
			for r in found.slice(0, 3):
				res.proposals.append({"kind": "relation", "name": r.name, "to_room": r.id})
	else:
		res.text = "Je suis un assistant simulé (aucune IA connectée). Dans « %s » je vois %d objet(s) et %d document(s)." % [room.name, room.objects.size(), ctx.room_documents.size()]
		if not ctx.documents.is_empty():
			res.text += "\nPassages pertinents :\n" + "\n".join(ctx.documents.map(func(d): return "- %s… " % d.snippet.left(160)))
		res.text += "\nEssayez : « synthèse », « questions », « connexions », « plan kanban », « nouvelle salle : <nom> »."
	cb.call_deferred(res)
