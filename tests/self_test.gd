class_name SelfTest
extends RefCounted
## Test d'intégration lancé dans la vraie scène :
##   ./lancer.sh --headless -- --kw-test --kw-save=/chemin/test.json
## Capture d'écran : ./lancer.sh -- --kw-shot=/chemin/capture.png

static var fails := 0


static func check(cond: bool, what: String) -> void:
	print(("  ok   " if cond else "  FAIL ") + what)
	if not cond:
		fails += 1


static func run(main) -> void:
	var tree: SceneTree = main.get_tree()
	await tree.process_frame
	var W = tree.root.get_node("World")
	print("SELFTEST start, save=", W.save_path)
	check(W.data.portals.size() >= 3, "3 portails de démonstration")
	# La souris au centre de l'écran doit atteindre le joueur (aucune UI ne doit la capter).
	main.player.force_active = true
	var yaw0: float = main.player.rotation.y
	var mm := InputEventMouseMotion.new()
	mm.position = main.get_viewport().get_visible_rect().size / 2
	mm.relative = Vector2(200, 0)
	main.get_viewport().push_input(mm)
	check(not is_equal_approx(main.player.rotation.y, yaw0), "la souris fait tourner la caméra (UI transparente)")
	main.player.force_active = false
	check(main.nodes.size() > 5, "hub peuplé (%d objets)" % main.nodes.size())
	# Navigation : entrer dans un portail puis la salle secondaire.
	var pid = W.data.portals.keys()[0]
	var entrance: String = W.data.portals[pid].entrance
	main.enter_room(entrance, W.data.hub)
	check(main.current_room == entrance, "entrée dans le portail")
	var doors = W.objects_in_room(entrance).filter(func(o): return o.type == "door")
	check(doors.size() >= 2, "portes retour + salle secondaire")
	# Création de salle + porte automatique.
	var rid: String = W.create_room("Salle test", W.data.rooms[entrance].portal_id, entrance)
	check(W.objects_in_room(rid).size() == 1, "nouvelle salle avec porte retour")
	await tree.process_frame
	check(main.nodes.size() == W.objects_in_room(entrance).size(), "porte vers la nouvelle salle affichée")
	# Notes + transformations.
	var nid: String = W.create_object("note", entrance, Vector3(0, 1, -5.9), Vector3.ZERO, Vector3.ONE, "Idées", {"text": "- un\n- deux\n- trois", "color": "#ffffff"})
	var k: Dictionary = W.transform("note_to_kanban", nid)
	check(W.data.objects[k.id].content.columns[0].cards.size() == 3, "note → kanban (3 cartes)")
	check(W.data.objects.has(nid), "note source conservée")
	check(W.relations_of("object", nid).size() == 1, "relation « dérivé » créée")
	var c: Dictionary = W.transform("note_to_card", nid)
	check(W.data.objects[c.id].type == "card", "note → fiche")
	# Construction : déplacer / dupliquer / redimensionner / supprimer.
	var dup: String = W.duplicate_object(nid)
	W.set_transform(dup, Vector3(1, 1, 1), Vector3(0, 45, 0), Vector3(2, 2, 2))
	await tree.process_frame
	check(main.nodes.has(dup) and is_equal_approx(main.nodes[dup].rotation_degrees.y, 45.0), "duplication + transformation appliquées en 3D")
	W.delete_object(dup)
	await tree.process_frame
	check(not main.nodes.has(dup), "suppression")
	# Documents.
	var tmp: String = W.save_path.get_base_dir().path_join("kw_test_doc.md")
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	f.store_string("Le jardin zen favorise la contemplation.")
	f.close()
	var did: String = W.import_document(tmp, entrance)
	check(did != "" and W.docs_for_room(entrance).size() >= 1, "import de document")
	W.link_document(did, W.data.hub)
	check(W.data.documents[did].rooms.size() == 2, "document associé à 2 salles sans duplication")
	check(tree.root.get_node("Assistant").rag.search("contemplation").size() == 1, "recherche documentaire")
	# Assistant simulé + validation.
	var desk: String = W.create_object("desk", entrance, Vector3(0, 0, 0))
	var A = tree.root.get_node("Assistant")
	var got := []
	A.reply_ready.connect(func(_d, r): got.append(r))
	A.ask(desk, entrance, "fais une synthèse", "room")
	await tree.process_frame
	await tree.process_frame
	check(got.size() == 1 and got[0].proposals.size() == 1, "assistant : réponse + proposition")
	var before: int = W.objects_in_room(entrance).size()
	A.apply_proposal(got[0].proposals[0], entrance)
	check(W.objects_in_room(entrance).size() == before + 1, "proposition validée → note créée")
	check(W.data.objects[desk].content.messages.size() == 2, "conversation persistée")
	# Relations.
	W.add_relation("room", rid, "room", W.data.hub, "dépendance", "test")
	check(W.relations_of("room", W.data.hub).size() >= 1, "relation salle ↔ salle")
	# Panneaux : instanciation / fermeture de chaque type.
	for p in [NotePanel.new(nid), WhiteboardPanel.new(W.create_object("whiteboard", entrance, Vector3.ZERO)), KanbanPanel.new(k.id),
			ChatPanel.new(desk), LibraryPanel.new(), MapPanel.new(), RelationPanel.new("room", rid), DoorPanel.new(doors[0].id)]:
		main.open_panel(p)
		await tree.process_frame
		main.close_panel()
	check(main.panel == null, "ouverture/fermeture de tous les panneaux")
	# Mode construction.
	main.build.toggle()
	main.build._start_placing("postit")
	await tree.process_frame
	main.build.toggle()
	check(not main.build.active, "mode construction on/off")
	# Suppression de salle + persistance.
	check(W.delete_room(rid), "suppression de salle")
	var counts := [W.data.rooms.size(), W.data.objects.size(), W.data.relations.size(), W.data.documents.size()]
	W.save_world()
	W.data = {}
	check(W.load_world(), "rechargement")
	check([W.data.rooms.size(), W.data.objects.size(), W.data.relations.size(), W.data.documents.size()] == counts, "données identiques après rechargement %s" % [counts])
	main.go_to_room(W.data.hub)
	await tree.create_timer(1.0).timeout
	check(main.current_room == W.data.hub, "téléportation au hub")
	print("SELFTEST ", "OK" if fails == 0 else "ÉCHECS : %d" % fails)
	tree.quit(0 if fails == 0 else 1)


static func shot(main, path: String) -> void:
	var tree: SceneTree = main.get_tree()
	await tree.create_timer(2.5).timeout
	main.get_viewport().get_texture().get_image().save_png(path)
	print("capture : ", path)
	tree.quit()
