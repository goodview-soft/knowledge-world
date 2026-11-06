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
	# Collé au passage, vitesse nulle, touche « avancer » enfoncée → on traverse.
	main.enter_room(W.data.hub)
	await tree.process_frame
	main.portals._cooldown = 0.0
	var pe2 = main.portals.entries[0]
	var pxf: Transform3D = main.nodes[pe2.obj_id].global_transform
	var fwd2: Vector3 = pxf.basis.z
	main.player.teleport(pxf.origin + fwd2 * 0.35 + Vector3(0, 0.05, 0), atan2(fwd2.x, fwd2.z))
	main.player.force_active = true
	Input.action_press("move_forward")
	for _i in 4:
		await tree.physics_frame
	Input.action_release("move_forward")
	main.player.force_active = false
	check(main.current_room == pe2.target, "traversée même collé au mur (vitesse nulle)")
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
	# Mondes multiples + écran d'accueil.
	var home: String = W.save_path
	var wp: String = W.create_world("Monde test", false)
	check(W.data.get("world_name", "") == "Monde test" and W.data.rooms.size() == 1, "nouveau monde vide créé")
	check(W.list_worlds().any(func(w): return w.path == wp), "monde listé")
	main.start_world(home)
	await tree.process_frame
	check(W.save_path == home and W.data.portals.size() >= 3, "retour au monde d'origine")
	check(W.delete_world(wp) and not FileAccess.file_exists(wp), "suppression d'un monde")
	check(not W.delete_world(home), "le monde ouvert ne peut pas être supprimé")
	main.show_title()
	await tree.process_frame
	check(main.title != null, "écran d'accueil affiché")
	main.start_world(home)
	await tree.process_frame
	check(main.title == null and main.current_room == W.data.hub, "écran d'accueil → monde")
	# Chat dans la pièce (façon Minecraft).
	main.enter_room(W.data.hub)
	main.chat.open_input()
	check(main.chat.is_open and not main.player.enabled, "chat en jeu ouvert, joueur figé")
	var n0: int = main.chat.log_box.get_child_count()
	main.chat._submit("fais une synthèse")
	await tree.process_frame
	await tree.process_frame
	await tree.process_frame
	check(main.chat.log_box.get_child_count() == n0 + 2 and main.player.enabled, "message + réponse de la conscience affichés")
	check(not "…" in main.chat.log_box.get_child(main.chat.log_box.get_child_count() - 1).text, "réponse complète reçue")
	# Structures : mur tracé, plancher d'étage, escalier praticable, matériau.
	main.enter_room(W.data.hub)
	var st: StructureTool = main.build.structure
	main.build._start_placing("struct_wall")
	check(st.active and main.build.active, "outil de tracé actif")
	st._a = Vector3(-6, 0, 4)
	var wspec: Dictionary = st._spec(Vector3(-2, 0, 4))
	var wid: String = st.place("struct_wall", wspec.pos, wspec.rot, wspec.scale)
	check(is_equal_approx(W.vec(W.data.objects[wid].scale).x, 4.15), "mur tracé de longueur exacte (4 m + recouvrement)")
	st.level = 1
	st.type = "struct_floor"
	st._a = Vector3(4, 3, -2)
	var fspec: Dictionary = st._spec(Vector3(8, 3, 2))
	var fid: String = st.place("struct_floor", fspec.pos, fspec.rot, fspec.scale)
	check(is_equal_approx(W.vec(W.data.objects[fid].pos).y, 2.8), "plancher posé à l'étage 1 (y = %s, spec %s)" % [W.vec(W.data.objects[fid].pos).y, fspec.pos])
	st.stop()
	main.build.toggle()
	var sid: String = W.create_object("stairs", W.data.hub, Vector3(-4, 0, 0), Vector3.ZERO, Vector3.ONE, "", {}, {"style": {"material": "pierre"}})
	await tree.physics_frame
	check(main.nodes[sid].body.get_child_count() == 1, "escalier : rampe de collision")
	main.player.teleport(Vector3(-4, 0.05, 3.2), 0.0)
	main.player.force_active = true
	Input.action_press("move_forward")
	var ymax := 0.0
	for _i in 150:
		await tree.physics_frame
		ymax = maxf(ymax, main.player.global_position.y)
	Input.action_release("move_forward")
	main.player.force_active = false
	check(ymax > 2.5, "on monte l'escalier jusqu'à l'étage (y max = %.2f)" % ymax)
	var pr: Dictionary = W.data.objects[wid].params.duplicate(true)
	pr.style.material = "brique"
	W.update_object(wid, {"params": pr})
	check(StructureKit.material_of(W.data.objects[wid]) == "brique", "matériau modifiable (brique)")
	for i in [wid, fid, sid]:
		W.delete_object(i)
	await mind_test(main)
	await OSSelfTest.run(main)
	# Entrer dans n'importe quel immeuble d'habitation (même sans bot).
	var rw2 = main.mind.reality
	var tgt_b = null
	for b in rw2.city.buildings:
		if b["role"] == "residence" and rw2.occupant_of(int(b["idx"])).is_empty():
			tgt_b = b
			break
	if tgt_b != null:
		rw2.portals.close()
		var dx2: Transform3D = rw2.portals.door_xf_of(tgt_b)
		main.player.global_position = dx2.origin + dx2.basis.z * 1.5 + Vector3(0, 0.05, 0)
		check(rw2.try_door() and rw2.portals.active, "porte d'un immeuble inoccupé : E ouvre l'entrée")
		rw2.portals.close()
	# Vraies portes : battant animé, verrouillage, sortie replacée dehors.
	var hb2: Dictionary = {}
	for b in rw2.city.buildings:
		if b["role"] == "residence" and not rw2.occupant_of(int(b["idx"])).is_empty():
			hb2 = b
			break
	if not hb2.is_empty():
		var bi2 := int(hb2["idx"])
		var sd: HingedDoor = rw2.portals.street_door(bi2)
		sd.swing(true, true)
		check(sd.openness() > 0.99 and sd.is_open, "porte d'immeuble : battant ouvert (95°)")
		sd.swing(false, true)
		check(sd.is_closed(), "porte d'immeuble : refermée")
		var clk: GameClock = rw2.director.clock
		var h0: float = clk.hour()
		clk.set_time(clk.day, 23.5)
		check(not rw2.street_open(bi2) and rw2.street_open(rw2.player_home), "entrée fermée la nuit sauf résident")
		clk.set_time(clk.day, 12.0)
		check(rw2.street_open(bi2), "entrée ouverte le jour")
		clk.set_time(clk.day, h0)
		var oc2: Dictionary = rw2.occupant_of(bi2)
		rw2.portals.open_for(bi2, str(oc2["who"]), oc2["color"], true, str(oc2.get("apartment_id", "")))
		var plan2: Dictionary = hb2["plan"]
		var other := ""
		for aid in plan2["apartments"]:
			if str(aid) != rw2.apartment.apartment_id and rw2.apartment.door_nodes.has(aid):
				other = str(aid)
				break
		check(other != "" and rw2.apartment.door_nodes.size() >= 2, "portes palières : battants")
		var my_apt: String = rw2.apartment.apartment_id
		check(rw2.apartment.door_nodes[my_apt].is_open, "appartement visité : porte ouverte")
		# sortie : replacé côté couloir, la porte se referme
		var cd3: Array = plan2["apartments"][my_apt]["corridor_door"]
		var ox3: float = float(plan2["entrance"]["x"])
		var fh3: float = float(plan2["fh"])
		var fl3: int = int(plan2["apartments"][my_apt]["floor"])
		var rooms3: Array = plan2["apartments"][my_apt]["rooms"]
		var cz3 := 0.0
		for r in rooms3:
			cz3 += float((r["rect"] as Array)[1]) + float((r["rect"] as Array)[3]) * 0.5
		cz3 /= float(rooms3.size())
		var ia3: float = 1.0 if cz3 > float(cd3[1]) else -1.0
		main.player.global_position = rw2.apartment.global_position + Vector3(float(cd3[0]) - ox3, fl3 * fh3 + 0.05, float(cd3[1]) + ia3 * 0.8)
		rw2.portals._cool = 0.0
		rw2.portals.interact_inside(main.player, true)
		var lz: float = main.player.global_position.z - rw2.apartment.global_position.z - float(cd3[1])
		check(lz * ia3 < 0.0, "sortie d'appartement : replacé côté couloir")
		var dn3: HingedDoor = rw2.apartment.door_nodes[my_apt]
		dn3.close_in(0.01)
		await main.get_tree().create_timer(1.4).timeout
		check(dn3.is_closed(), "porte d'appartement : se referme derrière nous")
		# occupant absent : verrouillé
		rw2.portals.close()
	print("SELFTEST ", "OK" if fails == 0 else "ÉCHECS : %d" % fails)
	tree.quit(0 if fails == 0 else 1)


static func mind_test(main) -> void:
	var tree: SceneTree = main.get_tree()
	var pl: KWPlayer = main.player
	check(main.in_palace, "mind : test démarré dans le palais")
	var p0: Vector3 = pl.global_position
	var room0: String = main.current_room
	main.mind.exit_palace()
	await tree.create_timer(2.2).timeout
	check(main.mind.state == MindLink.S.REALITY and not main.in_palace, "mind : sortie du palais → réalité")
	check(pl.global_position.x > 9000.0 and pl.third_person, "mind : joueur dans la réalité, 3e personne")
	pl.force_active = true
	for k in [KEY_B, KEY_TAB, KEY_P, KEY_N, KEY_G, KEY_L, KEY_F, KEY_T, KEY_I]:
		var ev := InputEventKey.new()
		ev.keycode = k
		ev.pressed = true
		main.get_viewport().push_input(ev)
	check(main.panel == null and not main.build.active, "mind : touches palais bloquées en réalité")
	var rw: RealityWorld = main.mind.reality
	check(rw.city.building_count >= 20 and rw.city.lamp_count > 0 and rw.city.tree_count > 0, "ville : %d bâtiments générés" % rw.city.building_count)
	check(rw.director.bots.size() >= 1 and rw.city.plaza.size.x > 10.0, "ville : bots présents, place dégagée")
	check(rw.director.bots.size() == 12 and rw.director.brains[0].home.has("node") and rw.city.places.size() >= 5, "bots niveau 2 : 12 bots avec foyer, lieux nommés")
	check(rw._clock_label.text.begins_with("Jour"), "bots niveau 2 : heure affichée dans le HUD")
	var tb: Bot = rw.director.bots[0]
	pl.teleport(tb.global_position + Vector3(0, 0, 2), 0.0)
	var e_ev := InputEventKey.new()
	e_ev.keycode = KEY_E
	e_ev.pressed = true
	main.get_viewport().push_input(e_ev)
	check(rw.talk.is_open() and main.panel == null, "bots : E ouvre la saisie en réalité")
	rw.talk.submit("Bonjour !")
	check(rw.talk.last_reply != "", "bots : réponse (repli) reçue")
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	main.get_viewport().push_input(esc)
	check(not rw.talk.is_open() and not tb.busy, "bots : Échap ferme la saisie")
	var sh := InputEventKey.new()
	sh.keycode = KEY_SHIFT
	sh.pressed = true
	main.get_viewport().push_input(sh)
	var sh2 := sh.duplicate()
	sh2.pressed = false
	main.get_viewport().push_input(sh2)
	check(main.mind.state == MindLink.S.TO_PALACE, "mind : Maj court → entrée dans le palais")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	main.get_viewport().push_input(click)
	check(main.mind.state == MindLink.S.PALACE and main.in_palace, "mind : transition passée par clic")
	check(pl.global_position.distance_to(p0) < 0.3 and main.current_room == room0, "mind : retour à la dernière position du palais")
	check(World.data.get("reality", {}).has("pos"), "mind : position réalité sauvegardée")
	# Interior mapping + appartement visitable
	check(rw.city.wall_mats.size() > 0 and (rw.city.wall_mats[0] as ShaderMaterial).shader.code.contains("vec3 room("), "fenêtres : shader interior mapping en place")
	var apt := ApartmentInterior.new()
	apt.generate("Test")
	check(apt.room_count >= 4 and apt.furniture_count >= 5 and apt.window_count >= 2, "appartement généré (%s : %d pièces, %d meubles, %d fenêtres)" % [apt.layout_id, apt.room_count, apt.furniture_count, apt.window_count])
	apt.free()
	_building_plans(rw)
	var hb := -1
	for b in rw.city.buildings:
		if b["role"] == "residence" and not rw.occupant_of(int(b["idx"])).is_empty():
			hb = int(b["idx"])
			break
	check(hb >= 0, "appartement : un immeuble habité existe")
	var oc: Dictionary = rw.occupant_of(hb)
	rw.portals.open_for(hb, str(oc["who"]), oc["color"], true, str(oc.get("apartment_id", "")))
	var dxf: Transform3D = rw.portals.a_xf
	main.in_palace = false # le filet de sécurité du palais ne doit pas s'appliquer à la réalité
	pl.teleport(dxf.origin + dxf.basis.z * 0.4, 0.0)
	rw.portals.traverse(pl, true)
	check(pl.global_position.y < -400.0 and pl.global_position.distance_to(rw.apartment.global_position) < 4.0, "appartement : entrée par la porte")
	check(not pl.third_person, "intérieur : 1re personne forcée")
	await tree.create_timer(3.0).timeout
	var ay: float = rw.apartment.global_position.y
	check(pl.global_position.y > ay - 0.2 and pl.global_position.y < ay + 1.0, "intérieur : le joueur reste au-dessus du sol 3 s après la traversée (dy=%.2f)" % (pl.global_position.y - ay))
	var bplan: Dictionary = rw.city.buildings[hb]["plan"]
	var box: float = float(bplan["entrance"]["x"])
	var ids0: Array = bplan["floors_data"][0]["apartments"]
	var other := ""
	for aid in ids0:
		if str(aid) != rw.apartment.apartment_id:
			other = str(aid)
			break
	if other != "":
		var ocd: Array = bplan["apartments"][other]["corridor_door"]
		var ocz := 0.0
		for r in bplan["apartments"][other]["rooms"]:
			ocz += float((r["rect"] as Array)[1]) + float((r["rect"] as Array)[3]) * 0.5
		ocz /= float((bplan["apartments"][other]["rooms"] as Array).size())
		var oia: float = 1.0 if ocz > float(ocd[1]) else -1.0
		pl.teleport(rw.apartment.global_position + Vector3(float(ocd[0]) - box, 0.05, float(ocd[1]) - oia * 1.0), 0.0)
		var ocx: Dictionary = rw.occupant_of_apt(rw.portals.building, other)
		var was := rw.apartment.apartment_id
		var handled: bool = rw.portals.interact_inside(pl, true)
		if bool(ocx["present"]) or str(ocx["who"]) == "toi":
			check(handled and rw.apartment.apartment_id == other and rw.apartment.furniture_count >= 5, "E sur une porte d'appartement (occupant présent) : on y entre, meublé (%d meubles)" % rw.apartment.furniture_count)
		else:
			check(handled and rw.apartment.apartment_id == was, "porte d'appartement verrouillée : occupant absent")
		await tree.create_timer(1.0).timeout
		if rw.apartment.apartment_id != other:
			rw.portals.apt.generate_building(bplan, other, Color(0.7, 0.5, 0.4), false, "")
			pl.teleport(rw.apartment.global_position + Vector3(float(ocd[0]) - box, 0.05, float(ocd[1]) + oia * 1.0), 0.0)
		check(pl.global_position.y > ay - 0.2 and pl.global_position.y < ay + 1.0, "appartement : sol sous les pieds")
		rw.portals._cool = 0.0
		check(rw.portals.interact_inside(pl, true) and absf(pl.global_position.z - (float(ocd[1]) - oia * 1.1)) < 0.2, "E sur la porte de l'appartement : retour au couloir")
	rw.portals.traverse(pl, false)
	check(pl.global_position.y > -1.0 and pl.global_position.distance_to(dxf.origin) < 2.0, "appartement : sortie vers le trottoir")
	main.in_palace = true
	rw.portals.close()
	pl.force_active = false


static func _building_plans(rw: RealityWorld) -> void:
	var bs: Array = rw.city.buildings
	var tall: Dictionary = {}
	for b in bs:
		if int(b["plan"]["floors"]) >= 3 and tall.is_empty():
			tall = b
	var fails := 0
	var wins := 0
	var apts := 0
	for b in bs:
		var plan: Dictionary = b["plan"]
		var again := BuildingPlan.generate(str(plan["id"]), float(plan["w"]), float(plan["d"]), int(plan["floors"]), float(plan["fh"]), str(plan["address"]))
		if JSON.stringify(again["windows"]) != JSON.stringify(plan["windows"]) or JSON.stringify(again["floors_data"]) != JSON.stringify(plan["floors_data"]):
			fails += 1
		for aid in plan["apartments"]:
			apts += 1
			if not BuildingPlan.apartment_ok(plan["apartments"][aid]):
				fails += 1
		for wn in plan["windows"]:
			wins += 1
			var room: Dictionary = BuildingPlan.room_of_window(plan, wn)
			var fac: String = wn["facade"]
			var lim: float = float(plan["w"]) if fac in ["front", "back"] else float(plan["d"])
			if float(wn["w"]) < 1.0 or float(wn["h"]) < 1.2 or float(wn["x"]) - float(wn["w"]) * 0.5 < 0.0 or float(wn["x"]) + float(wn["w"]) * 0.5 > lim or float(wn["y"]) + float(wn["h"]) > float(plan["fh"]) or room.is_empty() or str(room["apartment_id"]) != str(wn["apartment_id"]):
				fails += 1
	var wi: Dictionary = BuildingPlan.window_info(tall["plan"], "front", 0)
	check(fails == 0 and wins > 50 and apts > 20 and not wi.is_empty() and BuildingPlan.windows_of(tall["plan"], str(wi["apartment_id"])).size() >= 0, "plans : déterministes, %d appartements complets, %d fenêtres >= 1,0 x 1,2 m dans les façades (%d erreurs)" % [apts, wins, fails])
	var path: Array = BuildingPlan.stair_path(tall["plan"])
	var maxd := 0.0
	for i in range(1, path.size()):
		maxd = maxf(maxd, absf((path[i] as Vector3).y - (path[i - 1] as Vector3).y))
	var top: float = (path[path.size() - 1] as Vector3).y
	check(maxd <= 0.2 and absf(top - (int(tall["plan"]["floors"]) - 1) * float(tall["plan"]["fh"])) < 0.01 and top >= 2.0 * float(tall["plan"]["fh"]), "escalier : marches <= 0,2 m, atteint l'étage %d (y=%.1f)" % [int(tall["plan"]["floors"]) - 1, top])
	var bi := int(tall["idx"])
	var ids: Array = tall["plan"]["apartment_ids"]
	var up: String = str(ids[ids.size() - 1])
	var ai := ApartmentInterior.new()
	ai.generate_building(tall["plan"], up, Color(0.6, 0.5, 0.4), true, "Test")
	check(ai.room_count >= 3 and ai.window_count >= 3 and ai.floor_count >= 3, "intérieur depuis le plan : hall, escalier, %d pièces, %d fenêtres, %d étages" % [ai.room_count, ai.window_count, ai.floor_count])
	ai.free()
	var occ := 0
	for b in bs:
		for aid in b["plan"]["apartments"]:
			occ += (b["plan"]["apartments"][aid]["occupants"] as Array).size()
	check(occ > 0 and bi >= 0, "foyers : %d occupants référencés dans les appartements" % occ)


static func shot(main, path: String) -> void:
	var tree: SceneTree = main.get_tree()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--kw-shot-reality"):
			await tree.create_timer(0.5).timeout
			if a.ends_with("=facade") or a.ends_with("=apt") or a.ends_with("=door") or a.ends_with("=aptdoor") or a.get_slice("=", 1) in ["hall", "corridor", "room", "room2", "stairs"]:
				var rw: RealityWorld = main.mind.reality
				rw.city.set_night(true)
				var pl: KWPlayer = main.player
				var tb := -1
				for b in rw.city.buildings:
					if b["role"] == "residence" and not rw.occupant_of(int(b["idx"])).is_empty():
						tb = int(b["idx"])
						break
				var oc: Dictionary = rw.occupant_of(tb)
				rw.portals.open_for(tb, str(oc["who"]), oc["color"], true)
				var dx: Transform3D = rw.portals.a_xf
				var kind := a.get_slice("=", 1)
				if kind in ["hall", "corridor", "room", "stairs", "room2"]:
					pl.teleport(dx.origin + dx.basis.z * 0.4, 0.0)
					rw.portals.traverse(pl, true)
					var plan: Dictionary = rw.city.buildings[tb]["plan"]
					var ap: Dictionary = plan["apartments"][rw.apartment.apartment_id]
					var fl: int = int(ap["floor"])
					var fh: float = float(plan["fh"])
					var ox: float = float(plan["entrance"]["x"])
					var pp := Vector2(0, 0.6)
					var lookat := Vector2(0, 5)
					var floor_y: float = 0.0
					match kind:
						"hall":
							pp = Vector2(0, 0.7)
							lookat = Vector2(0, 5)
						"corridor":
							floor_y = fl * fh
							for c in plan["floors_data"][fl]["cells"]:
								if str(c["kind"]) == "corridor":
									var rc: Array = c["rect"]
									pp = Vector2(float(rc[0]) - ox + 0.6, float(rc[1]) + float(rc[3]) * 0.5)
									lookat = pp + Vector2(8, 0)
									break
						"stairs":
							var sz: Dictionary = plan["stair"]
							pp = Vector2(float(sz["len"]) - ox + 1.0, clampf(float(sz["z0"]) + 0.65, 0.7, 20.0))
							lookat = Vector2(-ox, pp.y)
						_:
							floor_y = fl * fh
							for r in ap["rooms"]:
								if str(r["kind"]) == ("living" if kind == "room" else "bedroom"):
									var rc: Array = r["rect"]
									pp = Vector2(float(rc[0]) - ox + 0.5, float(rc[1]) + 0.5)
									lookat = Vector2(float(rc[0]) - ox + float(rc[2]) * 0.5, float(rc[1]) + float(rc[3]) * 0.5)
									break
					var dd := lookat - pp
					pl.teleport(rw.apartment.global_position + Vector3(pp.x, floor_y + 0.05, pp.y), atan2(-dd.x, -dd.y))
					pl.head.rotation.x = -0.12
				elif a.ends_with("=door"):
					var sdd: HingedDoor = rw.portals.street_door(tb)
					sdd.swing(false, true)
					pl.teleport(dx.origin + dx.basis.z * 3.2 + Vector3(0, 0.05, 0), atan2(dx.basis.z.x, dx.basis.z.z))
					pl.head.rotation.x = 0.05
					sdd.swing(true)
				elif a.ends_with("=aptdoor"):
					pl.teleport(dx.origin + dx.basis.z * 0.4, 0.0)
					rw.portals.traverse(pl, true)
					var pn: Dictionary = rw.city.buildings[tb]["plan"]
					var apx: Dictionary = pn["apartments"][rw.apartment.apartment_id]
					var cdx: Array = apx["corridor_door"]
					var czx := 0.0
					for r in apx["rooms"]:
						czx += float((r["rect"] as Array)[1]) + float((r["rect"] as Array)[3]) * 0.5
					czx /= float((apx["rooms"] as Array).size())
					var iax: float = 1.0 if czx > float(cdx[1]) else -1.0
					pl.teleport(rw.apartment.global_position + Vector3(float(cdx[0]) - float(pn["entrance"]["x"]), float(apx["floor"]) * float(pn["fh"]) + 0.05, float(cdx[1]) - iax * 1.1), PI if iax > 0.0 else 0.0)
					pl.head.rotation.x = -0.05
				elif a.ends_with("=apt"):
					pl.teleport(dx.origin + dx.basis.z * 0.4, 0.0)
					rw.portals.traverse(pl, true)
					pl.global_position += Vector3(0, 0, 0.0)
					pl.rotation.y = PI
					pl.global_position = rw.apartment.global_position + Vector3(0, 0.05, 1.8)
					pl.head.rotation.x = -0.05
				else:
					pl.teleport(dx.origin + dx.basis.z * 16.0 + Vector3(0, 0.05, 0), atan2(dx.basis.z.x, dx.basis.z.z))
					pl.head.rotation.x = 0.2
				if not a.ends_with("=door"):
					await tree.create_timer(1.0).timeout
			if a.ends_with("=bubble"):
				main.mind.enter_palace()
				await tree.create_timer(0.75).timeout
			else:
				await tree.create_timer(0.25 if a.ends_with("=door") else 0.5).timeout
			print("SHOTPOS ", main.player.global_position, " palace=", main.in_palace, " fp=", not main.player.third_person)
			main.get_viewport().get_texture().get_image().save_png(path)
			print("capture : ", path)
			tree.quit()
			return
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--kw-shot-transit="):
			await tree.create_timer(0.3).timeout
			var st := TransitStage.make(Color(0.85, 0.82, 0.76), Color(0.7, 0.64, 0.84))
			main.add_child(st)
			st.play()
			await tree.create_timer(float(a.substr(18))).timeout
			main.get_viewport().get_texture().get_image().save_png(path)
			print("capture : ", path)
			tree.quit()
			return
	if "--kw-shot-structures" in OS.get_cmdline_user_args():
		var W = tree.root.get_node("World")
		var h: String = W.data.hub
		W.create_object("struct_wall", h, Vector3(-3, 0, 2), Vector3(0, 0, 0), Vector3(6.15, 1, 1), "", {}, {"style": {"material": "brique"}})
		W.create_object("struct_wall", h, Vector3(-6, 0, 4.5), Vector3(0, 90, 0), Vector3(5.15, 1, 1), "", {}, {"style": {"material": "brique"}})
		W.create_object("struct_floor", h, Vector3(-3, -0.19, 4.5), Vector3.ZERO, Vector3(6, 1, 5), "", {}, {"style": {"material": "bois"}})
		W.create_object("stairs", h, Vector3(2.5, 0, 4), Vector3.ZERO, Vector3.ONE, "", {}, {"style": {"material": "pierre"}})
		W.create_object("struct_wall", h, Vector3(4.5, 0, 4), Vector3(0, 90, 0), Vector3(4.15, 1, 1), "", {}, {"style": {"material": "carrelage", "primary": "#cfd8dc"}})
		main.player.teleport(Vector3(0, 0.05, 9), 0.5)
	print("TTS voix disponibles : ", DisplayServer.tts_get_voices().size(), " fr : ", DisplayServer.tts_get_voices_for_language("fr").size())
	if "--kw-shot-title" in OS.get_cmdline_user_args():
		main.show_title()
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
