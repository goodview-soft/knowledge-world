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
	# Notes Obsidian : liens wiki, tags, relations synchronisées, rétroliens, graphe.
	check(NoteLinks.parse_links("a [[Alpha]] b [[Beta|alias]] [[Alpha]] `[[Code]]`") == ["Alpha", "Beta"], "parsing des liens wiki (alias, doublons, code)")
	check(NoteLinks.parse_tags("#idée et #projet/2026, pas#ça ni `#code`\n# Titre") == ["idée", "projet/2026"], "parsing des #tags")
	var na: String = NoteLinks.create_note(entrance, "Alpha", "Lien vers [[Bêta]] et [[%s]] #test" % W.data.rooms[W.data.hub].name)
	var nb: String = NoteLinks.create_note(W.data.hub, "Bêta", "Retour vers [[alpha]]")
	check(NoteLinks.resolve("bêta") == {"kind": "object", "id": nb} and NoteLinks.resolve("Inconnue").is_empty(), "résolution des noms (casse) et lien inexistant")
	var sa: Dictionary = NoteLinks.sync_relations(na)
	check(sa.added == 2 and NoteLinks.wiki_relations(na).size() == 2, "relations wikilink ajoutées (note + salle)")
	var hub_rel: String = W.add_relation("object", nb, "object", na, "source", "manuel")
	NoteLinks.sync_relations(nb)
	check(NoteLinks.wiki_relations(nb).is_empty(), "pas de doublon avec une relation manuelle")
	check(NoteLinks.sync_relations(na).added == 0, "synchro idempotente")
	check(NoteLinks.backlinks("object", na) == [nb] and NoteLinks.backlinks("object", nb) == [na], "rétroliens")
	check(NoteLinks.notes_with_tag("#TEST") == [na], "recherche par tag")
	var np := NotePanel.new(na)
	main.open_panel(np)
	await tree.process_frame
	check(np.back_box.get_child_count() >= 1 and "url=wiki:" in np.preview.text, "panneau note : aperçu + rétroliens")
	np.text_edit.text = "Plus de lien sauf [[Bêta]]\n- [ ] tâche"
	np._on_meta("task:1")
	check("- [x] tâche" in W.data.objects[na].content.text, "case à cocher cliquable")
	check(NoteLinks.wiki_relations(na).size() == 1, "relation wikilink supprimée à la sauvegarde")
	main.close_panel()
	W.delete_relation(hub_rel)
	var dn: String = NoteLinks.daily_note()
	check(dn == NoteLinks.daily_note() and W.data.objects[dn].room_id == W.data.hub, "note du jour (unique, dans le hub)")
	var gp := GraphPanel.new()
	main.open_panel(gp)
	await tree.process_frame
	gp.graph.step()
	check(gp.graph.nodes.size() >= W.data.rooms.size() + 3 and gp.graph.edges.size() > 0, "graphe construit (%d nœuds)" % gp.graph.nodes.size())
	gp.mode = "notes"
	gp.rebuild()
	check(gp.graph.nodes.all(func(n): return n.type == "note"), "graphe : filtre notes seules")
	main.close_panel()
	var gk := InputEventKey.new()
	gk.keycode = KEY_G
	gk.pressed = true
	main._unhandled_input(gk)
	check(main.panel is GraphPanel, "touche G ouvre le graphe")
	main.close_panel()
	check(main.panel == null, "graphe fermé")
	# Panneaux : instanciation / fermeture de chaque type.
	for p in [NotePanel.new(nid), WhiteboardPanel.new(W.create_object("whiteboard", entrance, Vector3.ZERO)), KanbanPanel.new(k.id),
			ChatPanel.new(desk), LibraryPanel.new(), MapPanel.new(), GraphPanel.new("notes", "test"), RelationPanel.new("room", rid), DoorPanel.new(doors[0].id)]:
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
	# Personnalisation de salle (persistée) + redimensionnement qui garde les objets dedans.
	main.enter_room(rid)
	var far: String = W.create_object("table", rid, Vector3(4.0, 0, 4.0))
	W.update_room(rid, W.ROOM_PRESETS["Nuit"])
	W.update_room(rid, {"size": [6.0, 3.0, 6.0], "floor_mat": "bois"})
	await tree.process_frame
	var rs: Dictionary = W.data.rooms[rid]
	check(rs.light == "tamisee" and rs.floor_mat == "bois" and float(rs["size"][0]) == 6.0, "salle personnalisée (préréglage + matériau + taille)")
	var fp: Vector3 = W.vec(W.data.objects[far].pos)
	check(absf(fp.x) <= 3.0 and absf(fp.z) <= 3.0, "objet recalé dans la salle redimensionnée")
	var dp: Vector3 = W.vec(W.objects_in_room(rid).filter(func(o): return o.type == "door")[0].pos)
	check(absf(absf(dp.x) - 3.0) < 0.6 or absf(absf(dp.z) - 3.0) < 0.6, "porte restée contre un mur")
	check(main.room_geo != null and main.room_geo.is_inside_tree(), "géométrie de salle reconstruite")
	# Style d'objet.
	var lamp: String = W.create_object("lamp", rid, Vector3(0, 0, 0))
	main.build.toggle()
	main.build.select(lamp)
	var sp := ObjectStylePanel.new(lamp)
	main.open_panel(sp)
	await tree.process_frame
	sp._put("light_color", "#3366ff")
	sp._put("primary", "#ff0000")
	sp.name_edit.text = "Lampe bleue"
	main.close_panel()
	main.build.toggle()
	await tree.process_frame
	check(W.data.objects[lamp].params.style.light_color == "#3366ff" and W.data.objects[lamp].name == "Lampe bleue", "style d'objet persisté")
	var lights: Array = main.nodes[lamp].find_children("*", "OmniLight3D", true, false)
	check(lights.size() == 1 and lights[0].light_color.is_equal_approx(Color("#3366ff")), "style d'objet appliqué en 3D")
	# Nouveaux panneaux : menu pause, paramètres, salle.
	for p2 in [PauseMenu.new(), SettingsPanel.new(), RoomPanel.new(rid), MapPanel.new()]:
		main.open_panel(p2)
		await tree.process_frame
		check(main.panel == p2, "panneau %s ouvert" % p2.get_class() if p2.get_script() == null else "panneau %s ouvert" % p2.get_script().get_global_name())
		main.close_panel()
	check(main.panel == null, "nouveaux panneaux fermés")
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	main._input(esc)
	check(main.panel is PauseMenu, "Échap ouvre le menu")
	main._input(esc)
	check(main.panel == null, "Échap referme le menu")
	KWSettings.set_value("fov", 90.0)
	main.apply_settings()
	KWSettings.save_settings()
	KWSettings.data = {}
	KWSettings.load_settings()
	check(is_equal_approx(main.player.cam.fov, 90.0) and float(KWSettings.get_value("fov")) == 90.0 and KWSettings.path.ends_with("settings_test.json"), "paramètres appliqués et sauvés (fichier de test)")
	main.build.toggle()
	main.build._start_placing("lamp")
	check(main.hud.build_box.visible and main.hud.build_slots[8].theme_type_variation == "SlotActive", "barre d'outils : slot actif en surbrillance")
	main.build.toggle()
	main.enter_room(entrance)
	# Catalogue étendu : chaque type se construit, se pose et s'affiche.
	var bad := []
	for t in ObjectRegistry.DEFS:
		var vis: Node3D = ObjectRegistry.build({"id": "t_" + t, "type": t, "name": "x", "content": ObjectRegistry.default_content(t), "params": {}})
		if vis.get_child_count() == 0:
			bad.append(t)
		vis.free()
	check(bad.is_empty(), "tous les types se construisent (%d) %s" % [ObjectRegistry.DEFS.size(), bad])
	var made := []
	for t in ObjectRegistry.inventory_types():
		made.append(W.create_object(t, entrance, Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))))
	await tree.process_frame
	check(made.all(func(i): return main.nodes.has(i)), "nouveaux objets posés et affichés (%d)" % made.size())
	for i in made:
		W.delete_object(i)
	check(ObjectRegistry.colliders("rug").is_empty() and ObjectRegistry.colliders("arch").size() == 3 and not ObjectRegistry.is_solid("frame"), "collisions : tapis/cadre non bloquants, arche passante")
	# Accrochage des murs bout à bout.
	var w1: String = W.create_object("wall", entrance, Vector3(0, 0, 0))
	await tree.process_frame
	var es: Dictionary = main.build._edge_snap("wall", Vector3.ONE, Vector3(2.15, 0, 0.1), "")
	check(not es.is_empty() and es.pos.distance_to(Vector3(2, 0, 0)) < 0.01 and is_equal_approx(es.rot.y, 0.0), "mur accroché au bout d'un autre")
	W.delete_object(w1)
	# Inventaire + barre rapide persistée.
	main.build.open_inventory()
	await tree.process_frame
	check(main.panel is InventoryPanel and main.build.active, "inventaire ouvert (mode construction)")
	var inv: InventoryPanel = main.panel
	inv.cat = "arch"
	inv._filter()
	check(inv.tiles["wall"].visible and not inv.tiles["sofa"].visible, "inventaire : filtre par catégorie")
	inv.cat = ""
	inv.search.text = "canap"
	inv._filter()
	check(inv.tiles["sofa"].visible and not inv.tiles["wall"].visible, "inventaire : recherche")
	inv.assign(9, "sofa")
	KWSettings.data = {}
	KWSettings.load_settings()
	check(KWHotbar.type_at(9) == "sofa" and KWHotbar.type_at(8) == "lamp", "slot assigné persisté (settings_test.json)")
	check((main.hud.build_slots[9].get_child(0).get_child(1) as Label).text == "Canapé", "barre rapide du HUD mise à jour")
	inv.choose("sofa")
	await tree.process_frame
	check(main.panel == null and main.build.placing == "sofa", "inventaire fermé, canapé en pose")
	check(main.build._is_blocked("sofa", main.player.global_position, Vector3.ZERO, Vector3.ONE) and not main.build._is_blocked("rug", main.player.global_position, Vector3.ZERO, Vector3.ONE), "aperçu : collision détectée (joueur), tapis libre")
	main.build.toggle()
	KWHotbar.assign(9, "door")
	# Saut / accroupi.
	var pl: KWPlayer = main.player
	for i in 40:
		await tree.physics_frame
	check(pl.is_on_floor(), "joueur au sol")
	var y0: float = pl.global_position.y
	pl.request_jump()
	for i in 3:
		await tree.physics_frame
	check(pl.velocity.y > 0.0 and pl.global_position.y > y0, "saut")
	for i in 4:
		await tree.physics_frame
	var vy: float = pl.velocity.y
	pl.request_jump()
	await tree.physics_frame
	check(pl.velocity.y < vy, "pas de double saut")
	for i in 60:
		await tree.physics_frame
	pl.crouch_toggled = true
	for i in 20:
		await tree.physics_frame
	check(pl.is_crouched and pl.capsule.height < 1.2 and pl.head.position.y < 1.1, "accroupi (capsule + caméra abaissées)")
	var lid: String = W.create_object("platform", entrance, pl.global_position + Vector3(0, 1.3, 0))
	for i in 3:
		await tree.physics_frame
	pl.crouch_toggled = false
	for i in 20:
		await tree.physics_frame
	check(pl.is_crouched and pl.capsule.height < 1.2, "impossible de se relever sous un obstacle")
	W.delete_object(lid)
	for i in 25:
		await tree.physics_frame
	check(not pl.is_crouched and pl.capsule.height > 1.7, "relevé une fois l'obstacle retiré")
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
	# Orbe, poster, portails vivants.
	main.enter_room(W.data.hub)
	await tree.process_frame
	check(W.objects_in_room(W.data.hub).any(func(o): return o.type == "orb"), "sphère de conscience au centre du hub")
	check(main.room_ai() != "" and W.data.objects[main.room_ai()].type == "orb", "Entrée → IA de la pièce")
	var pst: String = W.create_object("poster", W.data.hub, Vector3(0, 1, -9.9))
	await tree.process_frame
	check(main.nodes.has(pst) and main.nodes[pst].body.collision_layer == 8, "poster créé, non bloquant")
	check(main.portals.entries.size() >= 3, "portails vivants dans le hub (%d)" % main.portals.entries.size())
	var pe = main.portals.entries[0]
	var tgt: String = pe.target
	main.portals._traverse(pe, main.nodes[pe.obj_id].global_transform)
	await tree.process_frame
	check(main.current_room == tgt, "traversée d'un portail en marchant")
	check(main.portals.entries.size() >= 1, "portail de retour vivant")
	# Redimensionnement de la salle : le joueur reste dedans ; chute → retour.
	main.enter_room(W.data.hub)
	main.player.global_position = Vector3(9.0, 0.05, 9.0)
	var hs: Array = W.data.rooms[W.data.hub].size.duplicate()
	W.data.rooms[W.data.hub].size = [8.0, hs[1], 8.0]
	W.changed.emit("room", W.data.hub, "updated")
	await tree.process_frame
	var pp: Vector3 = main.player.global_position
	check(absf(pp.x) <= 3.6 and absf(pp.z) <= 3.6, "joueur recalé après réduction du hub")
	main.player.global_position = Vector3(0, -10, 0)
	await tree.physics_frame
	await tree.physics_frame
	check(main.player.global_position.y > -1.0, "chute sous la carte → retour dans la salle")
	W.data.rooms[W.data.hub].size = hs
	W.changed.emit("room", W.data.hub, "updated")
	print("SELFTEST ", "OK" if fails == 0 else "ÉCHECS : %d" % fails)
	tree.quit(0 if fails == 0 else 1)


static func shot(main, path: String) -> void:
	var tree: SceneTree = main.get_tree()
	# Option : --kw-shot-ui=map|room|pause|settings|build (pour juger l'interface).
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--kw-shot-ui="):
			var what := a.substr(13)
			if "build" in what:
				main.build.toggle()
				main.build._start_placing("lamp")
			match what.replace("build", "").trim_prefix("+"):
				"map": main.open_panel(MapPanel.new())
				"room": main.open_panel(RoomPanel.new(main.current_room))
				"pause": main.open_panel(PauseMenu.new())
				"settings": main.open_panel(SettingsPanel.new())
				"graph": main.open_panel(GraphPanel.new())
				"note":
					var nn: String = NoteLinks.create_note(main.current_room, "Projet jardin", "# Projet jardin\n\nInspiré par [[Godot & 3D]] et [[Idée inexistante]].\n\n## Tâches\n- [x] Choisir les plantes\n- [ ] Dessiner le plan **au propre**\n- [ ] Lire `README`\n\n> Le jardin zen favorise la contemplation.\n\n#jardin #projet/2026")
					NoteLinks.create_note(main.current_room, "Journal", "Voir [[Projet jardin]] #journal")
					main.open_panel(NotePanel.new(nn))
	await tree.create_timer(2.5).timeout
	main.get_viewport().get_texture().get_image().save_png(path)
	print("capture : ", path)
	tree.quit()
