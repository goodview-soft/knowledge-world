class_name OSSelfTest
extends RefCounted
## Checks d'intégration de KW OS (appelés depuis SelfTest.run) + mise en scène de capture.


static func _desk(main) -> String:
	for o in World.data.objects.values():
		if o.type == "desk" and World.data.rooms.has(o.room_id):
			return o.id
	return World.create_object("desk", main.current_room, Vector3(2, 0, 2))


static func run(main) -> void:
	var tree: SceneTree = main.get_tree()
	var check := SelfTest.check
	var desk := _desk(main)
	var c0: Dictionary = World.data.objects[desk].content.duplicate(true)
	var msgs: Array = c0.get("messages", [])
	if msgs.is_empty():
		c0.messages = [{"role": "user", "text": "bonjour"}]
		World.update_object(desk, {"content": c0})
	var n_msgs: int = World.data.objects[desk].content.messages.size()
	check.call(ObjectRegistry.get_def("desk").panel == "os", "bureau → panneau os")
	main.interact(desk)
	await tree.process_frame
	await tree.process_frame
	var os = main.panel
	check.call(os is OSPanel, "E sur un bureau ouvre KW OS")
	if not os is OSPanel:
		return
	for a in OSPanel.APPS:
		var w = os.open_app(a.id)
		check.call(w != null and w.app != null and w.visible and w.is_inside_tree(), "OS : app « %s » s'ouvre" % a.name)
	await tree.process_frame
	check.call(os.windows.size() == OSPanel.APPS.size(), "OS : %d fenêtres simultanées" % os.windows.size())
	# Fenêtres : focus, agrandir, réduire, restaurer.
	var tw = os.windows["terminal"]
	os.focus(tw)
	check.call(os.active_key == "terminal" and os.layer.get_child(-1) == tw, "OS : focus = premier plan")
	tw.set_maximized(true)
	check.call(tw.size.is_equal_approx(os.layer.size), "OS : agrandir")
	tw.set_maximized(false)
	os._set_minimized(tw, true)
	check.call(not tw.visible, "OS : réduire")
	os._dock_click("terminal")
	check.call(tw.visible and os.active_key == "terminal", "OS : restaurer depuis le dock")
	# Terminal.
	var term = os.get_app("terminal")
	term.submit("cd /")
	check.call(term.shell.cwd == World.data.hub, "terminal : cd / → hub")
	var p: Dictionary = World.data.portals.values()[0]
	var ls: String = term.submit("ls")
	check.call(p.name in ls, "terminal : ls liste les portails/salles")
	term.submit("cd " + p.name)
	check.call(term.shell.cwd == p.entrance, "terminal : cd <salle>")
	check.call(term.shell.prompt().contains(p.name), "terminal : invite = chemin")
	term.submit("new note Test terminal OS")
	var nid: String = term.shell.last_created
	check.call(World.data.objects.has(nid) and World.data.objects[nid].room_id == p.entrance and World.data.objects[nid].name == "Test terminal OS", "terminal : new note dans la salle courante")
	var f: String = term.submit("find terminal OS")
	check.call("Test terminal OS" in f, "terminal : find")
	check.call("Test terminal OS" in term.submit("cat Test terminal OS"), "terminal : cat")
	term.submit("rm Test terminal OS")
	check.call(World.data.objects.has(nid), "terminal : rm demande confirmation")
	term.submit("o")
	check.call(not World.data.objects.has(nid), "terminal : rm confirmé supprime")
	var comp: Dictionary = term.shell.complete("cd /")
	comp = term.shell.complete("cd " + p.name.left(4))
	check.call(str(comp.line).begins_with("cd " + p.name.left(4)) and str(comp.line).length() >= ("cd " + p.name.left(4)).length(), "terminal : complétion Tab")
	check.call(term.shell.complete("hel").line == "help ", "terminal : complétion des commandes")
	term.shell.run("ask bonjour")
	check.call(term.shell.action.get("ask", "") == "bonjour", "terminal : ask → assistant")
	check.call(term.shell.history.size() >= 5 and World.data.objects[desk].content.os.get("term_history", []).size() >= 5, "terminal : historique persistant")
	# Tâches : cocher modifie la donnée source.
	var tn := OSData.create_note(main.current_room, "Courses OS", "- [ ] Acheter du pain\n- [x] Lait")
	var tasks = os.get_app("tasks")
	tasks.refresh()
	var hits: Array = tasks.tasks.filter(func(t): return t.text == "Acheter du pain")
	check.call(hits.size() == 1 and not hits[0].done, "tâches : case de note agrégée")
	if hits.size() == 1:
		tasks.toggle(hits[0])
	check.call("- [x] Acheter du pain" in str(World.data.objects[tn].content.text), "tâches : cocher → note source modifiée")
	var kid := World.create_object("kanban", main.current_room, Vector3(0, 1, 0), Vector3.ZERO, Vector3.ONE, "KB OS",
		{"columns": [{"title": "À faire", "cards": ["Tâche K"]}, {"title": "En cours", "cards": []}, {"title": "Fait", "cards": []}]})
	tasks.refresh()
	var kh: Array = tasks.tasks.filter(func(t): return t.text == "Tâche K")
	if kh.size() == 1:
		tasks.toggle(kh[0])
	check.call(World.data.objects[kid].content.columns[2].cards == ["Tâche K"], "tâches : cocher → carte Kanban dans « Fait »")
	# Notes : ouvrir / éditer / sauver.
	var notes = os.get_app("notes")
	await tree.process_frame
	notes.open_note(tn)
	notes.text_edit.text += "\nVoir [[Courses OS]] #osapp"
	notes._dirty = true
	notes.save()
	check.call("#osapp" in str(World.data.objects[tn].content.text), "notes : édition sauvegardée")
	check.call("[url=wiki:" in notes.preview.text, "notes : rendu Markdown + liens")
	# Journal.
	var jid: String = os.get_app("journal").open_journal()
	check.call(World.data.objects.has(jid) and World.data.objects[jid].name == "Journal " + Time.get_date_string_from_system(), "journal : note du jour créée")
	check.call(notes.current == jid, "journal : ouverte dans l'éditeur")
	check.call(OSData.journal_note(Time.get_date_string_from_system()) == jid, "journal : pas de doublon")
	# Tableau de bord / explorateur / documents.
	var s := OSData.stats()
	check.call(s.notes > 0 and s.rooms > 0, "tableau de bord : statistiques")
	check.call(not OSData.recent_activity().is_empty(), "tableau de bord : activité récente")
	var ex = os.get_app("explorer")
	ex.refresh()
	ex.select_ref({"kind": "object", "id": tn})
	check.call(ex.selected.get("id", "") == tn, "explorateur : sélection d'une note")
	OSData.rename("object", tn, "Courses OS 2")
	check.call(World.data.objects[tn].name == "Courses OS 2", "explorateur : renommer")
	if not World.data.documents.is_empty():
		var did: String = World.data.documents.keys()[0]
		os.open_ref({"kind": "document", "id": did})
		check.call(os.get_app("documents").current == did and os.get_app("documents").viewer.text != "", "documents : lecture")
	# Disposition mémorisée, messages du chat intacts.
	os._save_layout()
	var lay: Dictionary = World.data.objects[desk].content.get("os", {})
	check.call(lay.get("windows", {}).has("terminal") and lay.windows.terminal.open, "OS : disposition dans content.os")
	check.call(World.data.objects[desk].content.messages.size() >= n_msgs, "OS : content.messages intact")
	main.close_panel()
	await tree.process_frame
	check.call(main.panel == null, "OS : fermeture")
	main.interact(desk)
	await tree.process_frame
	await tree.process_frame
	await tree.process_frame
	check.call(main.panel is OSPanel and main.panel.windows.size() == OSPanel.APPS.size(), "OS : fenêtres restaurées à la réouverture")
	main.close_panel()
	await tree.process_frame
	for oid in [tn, kid, jid]:
		World.delete_object(oid)


## --kw-shot-ui=os : ouvre l'OS avec quelques fenêtres.
static func shot_setup(main) -> void:
	var desk := _desk(main)
	OSData.create_note(main.current_room, "Plan de la semaine", "# Plan de la semaine\n\n- [ ] Relire [[Godot & 3D]]\n- [x] Importer les PDF\n- [ ] Préparer la démo **KW OS**\n\n> Une idée par note.\n\n#projet #os")
	main.interact(desk)
	await main.get_tree().process_frame
	await main.get_tree().process_frame
	var os = main.panel
	if not os is OSPanel:
		return
	for k in os.windows.keys():
		os.close_app(k)
	var d = os.open_app("dashboard")
	d.set_rect(Rect2(20, 10, 900, 560))
	var n = os.open_app("notes")
	n.set_rect(Rect2(640, 220, 900, 520))
	var t = os.open_app("terminal")
	t.set_rect(Rect2(60, 400, 640, 330))
	for cmd in ["ls", "find godot", "tags"]:
		t.app.submit(cmd)
	n.app.refresh()
	if not n.app.ids.is_empty():
		n.app.open_note(n.app.ids[0])
