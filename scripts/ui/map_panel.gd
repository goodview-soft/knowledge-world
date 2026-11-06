class_name MapPanel
extends KWPanel
## Carte globale : arborescence portails/salles, recherche globale (salles, objets,
## documents), favoris, récents, téléportation, création/renommage/suppression.

const KIND_LABEL := {"room": "Salle", "portal": "Portail", "object": "Objet", "document": "Document"}

var tree: Tree
var search: LineEdit
var name_edit: LineEdit
var rename_edit: LineEdit
var side: VBoxContainer
var quick: VBoxContainer
var sel_title: Label
var sel_kind: Label
var sel_actions: Array[Button] = []
var room_actions: Array[Button] = []
var del_btn: Button
var _confirm_delete := false


func _init() -> void:
	super("Carte du monde", Vector2(1180, 740))
	var top := hbox(body)
	search = line(top, "", "Rechercher une salle, une note, un tableau, un document…")
	search.custom_minimum_size.y = 42
	search.clear_button_enabled = true
	search.text_changed.connect(func(_t): _build_tree())
	search.text_submitted.connect(func(_t): _go_first())
	ghost(top, "⌂  Hub", func(): main.go_to_room(World.data.hub, main.current_room))
	ghost(top, "◎  Graphe", func(): main.open_panel(GraphPanel.new()))
	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 18)
	body.add_child(split)
	tree = Tree.new()
	tree.hide_root = true
	tree.columns = 2
	tree.set_column_expand(1, false)
	tree.set_column_custom_minimum_width(1, 150)
	tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tree.item_activated.connect(_go_selected)
	tree.item_selected.connect(_on_select)
	tree.nothing_selected.connect(func():
		tree.deselect_all()
		_on_select())
	split.add_child(tree)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = 380
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(scroll)
	side = VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.add_theme_constant_override("separation", 12)
	scroll.add_child(side)
	# Sélection.
	var c1 := card(side, "Sélection")
	sel_title = Label.new()
	sel_title.add_theme_font_size_override("font_size", 19)
	sel_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	c1.add_child(sel_title)
	sel_kind = dim(c1, "")
	var r1 := hbox(c1)
	var go := primary(r1, "Y aller", _go_selected)
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var fav := btn(r1, "★", func():
		var m := _sel()
		if m.kind == "room":
			main.hud.toast("Ajouté aux favoris" if World.toggle_favorite(m.id) else "Retiré des favoris")
			_build_quick())
	fav.tooltip_text = "Favori"
	var rel := btn(r1, "Relations", func():
		var m := _sel()
		if m.kind != "":
			main.open_relations(m.kind, m.id))
	sel_actions.append_array([go, rel])
	room_actions.append(fav)
	# Modifier la salle sélectionnée.
	var c2 := card(side, "Modifier la salle")
	var r2 := hbox(c2)
	rename_edit = line(r2, "", "Nouveau nom…")
	rename_edit.text_submitted.connect(func(_t): _rename())
	room_actions.append(btn(r2, "Renommer", _rename))
	var r3 := hbox(c2)
	var cust := btn(r3, "Personnaliser…", func():
		var m := _sel()
		if m.kind == "room":
			main.open_panel(RoomPanel.new(m.id)))
	cust.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	room_actions.append(cust)
	del_btn = danger(r3, "Supprimer", _delete)
	room_actions.append(del_btn)
	# Créer.
	var c3 := card(side, "Créer")
	name_edit = line(c3, "", "Nom de la nouvelle salle ou du portail")
	var r4 := hbox(c3)
	btn(r4, "Salle ici", func(): _create_room(false))
	btn(r4, "Sous la sélection", func(): _create_room(true))
	btn(r4, "Portail", _create_portal)
	# Accès rapide.
	quick = card(side, "Accès rapide")


func _ready() -> void:
	super()
	if World.data.rooms.has(main.current_room):
		set_subtitle("Vous êtes ici : " + World.data.rooms[main.current_room].name)
	_build_tree()
	_build_quick()
	_on_select()
	search.grab_focus()


func _sel() -> Dictionary:
	var it := tree.get_selected()
	return it.get_metadata(0) if it != null else {"kind": "", "id": ""}


func _item(parent: TreeItem, text: String, kind: String, id: String, detail := "") -> TreeItem:
	var it := tree.create_item(parent)
	it.set_text(0, text)
	it.set_metadata(0, {"kind": kind, "id": id})
	it.set_text(1, detail)
	it.set_custom_color(1, KWTheme.TEXT_FAINT)
	it.set_text_alignment(1, HORIZONTAL_ALIGNMENT_RIGHT)
	if kind == "room" and id == main_room():
		it.set_custom_color(0, KWTheme.ACCENT)
		it.set_text(1, "● vous êtes ici")
		it.set_custom_color(1, KWTheme.ACCENT)
	return it


func main_room() -> String:
	return get_tree().current_scene.current_room if is_inside_tree() else ""


func _room_detail(id: String) -> String:
	var n := World.objects_in_room(id).filter(func(o): return not o.type in ["door", "portal"]).size()
	var star := "★  " if id in World.data.favorites else ""
	return star + ("%d objet%s" % [n, "s" if n > 1 else ""])


func _add_rooms(parent: TreeItem, parent_id: String) -> void:
	for r in World.child_rooms(parent_id):
		_add_rooms(_item(parent, r.name, "room", r.id, _room_detail(r.id)), r.id)


func _build_tree() -> void:
	tree.clear()
	var root := tree.create_item()
	var q := search.text.strip_edges()
	if q != "":
		var res_list: Array = World.search(q)
		for res in res_list:
			_item(root, res.label, res.kind, res.id, KIND_LABEL.get(res.kind, ""))
		if res_list.is_empty():
			var it := tree.create_item(root)
			it.set_text(0, "Aucun résultat pour « %s »" % q)
			it.set_custom_color(0, KWTheme.TEXT_FAINT)
			it.set_selectable(0, false)
			it.set_selectable(1, false)
			it.set_metadata(0, {"kind": "", "id": ""})
		return
	var hub := _item(root, "⌂  " + World.data.rooms[World.data.hub].name, "room", World.data.hub, _room_detail(World.data.hub))
	_add_rooms(hub, World.data.hub)
	for p in World.data.portals.values():
		var pi := _item(root, "◈  " + p.name, "portal", p.id, "Portail")
		pi.set_custom_color(0, Color(p.color).lerp(KWTheme.TEXT, 0.4))
		if World.data.rooms.has(p.entrance):
			_add_rooms(_item(pi, World.data.rooms[p.entrance].name + "  · entrée", "room", p.entrance, _room_detail(p.entrance)), p.entrance)


func _build_quick() -> void:
	for c in quick.get_children().slice(1):
		c.queue_free()
	var any := false
	for pair in [["Favoris", World.data.favorites], ["Récents", World.data.recent]]:
		var ids: Array = pair[1].filter(func(i): return World.data.rooms.has(i))
		if ids.is_empty():
			continue
		any = true
		dim(quick, pair[0])
		var f := HFlowContainer.new()
		quick.add_child(f)
		for id in ids:
			chip(f, ("★ " if pair[0] == "Favoris" else "") + World.data.rooms[id].name, func(): main.go_to_room(id))
	if not any:
		dim(quick, "Aucun favori ni récent pour l'instant.")


func _on_select() -> void:
	var m := _sel()
	_confirm_delete = false
	del_btn.text = "Supprimer"
	var has: bool = m.kind != ""
	sel_title.text = World.label_of(m.kind, m.id).get_slice(" · ", 1) if has else "Aucune sélection"
	sel_kind.text = KIND_LABEL.get(m.kind, "") if has else "Choisissez un élément dans la liste (double-clic : y aller)."
	for b in sel_actions:
		b.disabled = not has
	for b in room_actions:
		b.disabled = m.kind != "room"
	del_btn.disabled = m.kind != "room" or m.id == World.data.hub
	rename_edit.editable = m.kind == "room"
	rename_edit.text = World.data.rooms[m.id].name if m.kind == "room" else ""


func _go_first() -> void:
	var first: TreeItem = tree.get_root().get_first_child() if tree.get_root() else null
	if first != null and first.get_metadata(0).kind != "":
		first.select(0)
		_go_selected()


func _go_selected() -> void:
	var m := _sel()
	match m.kind:
		"room": main.go_to_room(m.id)
		"portal": main.go_to_room(World.data.portals[m.id].entrance)
		"object": main.go_to_object(m.id)
		"document":
			main.close_panel()
			main.open_panel(LibraryPanel.new())


func _rename() -> void:
	var m := _sel()
	var n := rename_edit.text.strip_edges()
	if m.kind == "room" and n != "":
		World.rename_room(m.id, n)
		_build_tree()
		_reselect(m.id)


func _delete() -> void:
	var m := _sel()
	if m.kind != "room" or m.id == World.data.hub:
		return
	if not _confirm_delete:
		_confirm_delete = true
		del_btn.text = "Confirmer ?"
		return
	if m.id == main.current_room:
		main.go_to_room(World.data.hub)
	var nm: String = World.data.rooms[m.id].name
	World.delete_room(m.id)
	main.hud.toast("Salle « %s » supprimée." % nm)
	_build_tree()
	_on_select()


func _reselect(id: String) -> void:
	var it: TreeItem = tree.get_root().get_first_child() if tree.get_root() else null
	var stack := [it]
	while not stack.is_empty():
		var cur: TreeItem = stack.pop_back()
		if cur == null:
			continue
		if cur.get_metadata(0).id == id:
			cur.select(0)
			tree.scroll_to_item(cur)
			return
		stack.append(cur.get_next())
		stack.append(cur.get_first_child())


func _create_room(under_selection: bool) -> void:
	var n := name_edit.text.strip_edges()
	if n == "":
		n = "Nouvelle salle"
	var parent: String = main.current_room
	var m := _sel()
	if under_selection and m.kind == "room":
		parent = m.id
	elif under_selection and m.kind == "portal":
		parent = World.data.portals[m.id].entrance
	var pr: Dictionary = World.data.rooms[parent]
	var rid := World.create_room(n, pr.portal_id, parent, [9.0 + randi() % 5, 4.0, 9.0 + randi() % 5])
	main.hud.toast("Salle « %s » créée (porte ajoutée dans « %s »)." % [n, pr.name])
	name_edit.clear()
	_build_tree()
	_reselect(rid)


func _create_portal() -> void:
	var n := name_edit.text.strip_edges()
	if n == "":
		n = "Nouveau domaine"
	World.create_portal(n, Color.from_hsv(randf(), 0.35, 0.85).to_html(false))
	main.hud.toast("Portail « %s » ajouté dans le hub." % n)
	name_edit.clear()
	_build_tree()
