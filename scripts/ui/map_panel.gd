class_name MapPanel
extends KWPanel
## Carte globale : arborescence portails/salles, recherche globale (salles, objets,
## documents), favoris, récents, téléportation, création/renommage/suppression.

var tree: Tree
var search: LineEdit
var name_edit: LineEdit
var side: VBoxContainer
var quick: VBoxContainer


func _init() -> void:
	super("Carte du monde", Vector2(1100, 720))
	var top := hbox(body)
	search = line(top, "", "Rechercher : salles, notes, tableaux, documents…")
	search.text_changed.connect(func(_t): _build_tree())
	btn(top, "⌂ Retour au hub", func(): main.go_to_room(World.data.hub, main.current_room))
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(split)
	tree = Tree.new()
	tree.hide_root = true
	tree.custom_minimum_size = Vector2(560, 0)
	tree.item_activated.connect(_go_selected)
	split.add_child(tree)
	side = VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(side)
	lbl(side, "Sélection (double-clic = y aller)", 17)
	var r1 := hbox(side)
	btn(r1, "Aller", _go_selected)
	btn(r1, "★ Favori", func():
		var m := _sel()
		if m.kind == "room":
			main.hud.toast("Ajouté aux favoris" if World.toggle_favorite(m.id) else "Retiré des favoris")
			_build_quick())
	btn(r1, "Relations…", func():
		var m := _sel()
		if m.kind != "":
			main.open_relations(m.kind, m.id))
	var r2 := hbox(side)
	name_edit = line(r2, "", "Nom…")
	var r3 := hbox(side)
	btn(r3, "Nouvelle salle ici", func(): _create_room(false))
	btn(r3, "Sous la sélection", func(): _create_room(true))
	var r4 := hbox(side)
	btn(r4, "Nouveau portail", _create_portal)
	btn(r4, "Renommer", func():
		var m := _sel()
		if m.kind == "room" and name_edit.text.strip_edges() != "":
			World.rename_room(m.id, name_edit.text.strip_edges())
			_build_tree())
	var del := btn(r4, "Supprimer la salle", func():
		var m := _sel()
		if m.kind == "room" and m.id != World.data.hub:
			if m.id == main.current_room:
				main.go_to_room(World.data.hub)
			World.delete_room(m.id)
			_build_tree())
	del.add_theme_color_override("font_color", Color(1, 0.6, 0.55))
	side.add_child(HSeparator.new())
	quick = VBoxContainer.new()
	side.add_child(quick)


func _ready() -> void:
	super()
	_build_tree()
	_build_quick()
	search.grab_focus()


func _sel() -> Dictionary:
	var it := tree.get_selected()
	return it.get_metadata(0) if it != null else {"kind": "", "id": ""}


func _item(parent: TreeItem, text: String, kind: String, id: String) -> TreeItem:
	var it := tree.create_item(parent)
	it.set_text(0, text)
	it.set_metadata(0, {"kind": kind, "id": id})
	if kind == "room" and id == main_room():
		it.set_custom_color(0, Color(1.0, 0.85, 0.5))
		it.set_text(0, text + "   ← vous êtes ici")
	return it


func main_room() -> String:
	return get_tree().current_scene.current_room if is_inside_tree() else ""


func _add_rooms(parent: TreeItem, parent_id: String) -> void:
	for r in World.child_rooms(parent_id):
		_add_rooms(_item(parent, r.name, "room", r.id), r.id)


func _build_tree() -> void:
	tree.clear()
	var root := tree.create_item()
	var q := search.text.strip_edges()
	if q != "":
		for res in World.search(q):
			_item(root, res.label, res.kind, res.id)
		return
	var hub := _item(root, "⌂ " + World.data.rooms[World.data.hub].name, "room", World.data.hub)
	_add_rooms(hub, World.data.hub)
	for p in World.data.portals.values():
		var pi := _item(root, "◈ Portail · " + p.name, "portal", p.id)
		if World.data.rooms.has(p.entrance):
			_add_rooms(_item(pi, World.data.rooms[p.entrance].name + " (entrée)", "room", p.entrance), p.entrance)


func _build_quick() -> void:
	for c in quick.get_children():
		c.queue_free()
	lbl(quick, "Favoris", 17)
	var f := HFlowContainer.new()
	quick.add_child(f)
	for id in World.data.favorites:
		if World.data.rooms.has(id):
			btn(f, "★ " + World.data.rooms[id].name, func(): main.go_to_room(id))
	lbl(quick, "Récents", 17)
	var r := HFlowContainer.new()
	quick.add_child(r)
	for id in World.data.recent:
		if World.data.rooms.has(id):
			btn(r, World.data.rooms[id].name, func(): main.go_to_room(id))


func _go_selected() -> void:
	var m := _sel()
	match m.kind:
		"room": main.go_to_room(m.id)
		"portal": main.go_to_room(World.data.portals[m.id].entrance)
		"object": main.go_to_object(m.id)
		"document":
			main.close_panel()
			main.open_panel(LibraryPanel.new())


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
	World.create_room(n, pr.portal_id, parent, [9.0 + randi() % 5, 4.0, 9.0 + randi() % 5])
	main.hud.toast("Salle « %s » créée (porte ajoutée dans « %s »)." % [n, pr.name])
	name_edit.clear()
	_build_tree()


func _create_portal() -> void:
	var n := name_edit.text.strip_edges()
	if n == "":
		n = "Nouveau domaine"
	World.create_portal(n, Color.from_hsv(randf(), 0.35, 0.85).to_html(false))
	main.hud.toast("Portail « %s » ajouté dans le hub." % n)
	name_edit.clear()
	_build_tree()
