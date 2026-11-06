class_name OSExplorer
extends OSApp
## Explorateur : Hub / portails → salles → objets, et documents.
## Ouvrir, renommer, supprimer (confirmation), aller dans la salle.

const GLYPHS := {"portal": "◆", "room": "▦", "document": "❏", "note": "✎", "postit": "▪", "card": "▭", "kanban": "▥", "whiteboard": "▢", "desk": "✦", "library": "❏"}

var tree: Tree
var search: LineEdit
var furniture: CheckBox
var details: VBoxContainer
var selected := {}
var collapsed := {} # "kind:id" -> bool
var _filter := ""
var _confirm_del := false


func _init() -> void:
	super()
	var top := KWPanel.hbox(self)
	search = KWPanel.line(top, "", "Filtrer par nom…")
	search.text_changed.connect(func(t: String):
		_filter = t.strip_edges().to_lower()
		refresh())
	furniture = CheckBox.new()
	furniture.text = "Mobilier"
	furniture.tooltip_text = "Afficher aussi le mobilier et la décoration"
	furniture.toggled.connect(func(_b): refresh())
	top.add_child(furniture)
	var split := OSApp.split_list(360)
	add_child(split)
	tree = Tree.new()
	tree.hide_root = true
	tree.custom_minimum_size.x = 280
	tree.item_selected.connect(_on_select)
	tree.item_activated.connect(func(): _open(selected))
	tree.item_collapsed.connect(func(it: TreeItem):
		var m = it.get_metadata(0)
		if m is Dictionary:
			collapsed["%s:%s" % [m.kind, m.id]] = it.collapsed)
	split.add_child(tree)
	var right := PanelContainer.new()
	right.theme_type_variation = "Card"
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(right)
	details = VBoxContainer.new()
	details.add_theme_constant_override("separation", 10)
	right.add_child(details)
	refresh()


func open_args(args: Dictionary) -> void:
	if args.has("select"):
		select_ref(args.select)


func refresh() -> void:
	tree.clear()
	var root := tree.create_item()
	var hub: String = World.data.hub
	var hub_it := _room_item(root, hub, "Hub")
	for rid in World.data.rooms:
		var r: Dictionary = World.data.rooms[rid]
		if rid != hub and str(r.get("parent_id", "")) == "" and not _is_entrance(rid):
			_room_item(hub_it, rid)
	_prune(hub_it)
	var pids: Array = World.data.portals.keys()
	pids.sort_custom(func(a, b): return str(World.data.portals[a].name).naturalnocasecmp_to(str(World.data.portals[b].name)) < 0)
	for pid in pids:
		var p: Dictionary = World.data.portals[pid]
		var it := _item(root, "portal", pid, str(p.name), Color(str(p.get("color", "#8ea8ff"))))
		var ent := str(p.get("entrance", ""))
		if World.data.rooms.has(ent):
			_room_content(it, ent)
		_prune(it)
	var docs := _item(root, "folder", "documents", "Documents", KWTheme.TEXT_DIM)
	docs.set_selectable(0, false)
	for d in World.data.documents.values():
		if _match(str(d.name)):
			_item(docs, "document", d.id, str(d.name))
	_prune(docs)
	if not selected.is_empty() and World.exists(selected.kind, selected.id):
		select_ref(selected, false)
	else:
		selected = {}
		_show_details()


func _is_entrance(rid: String) -> bool:
	for p in World.data.portals.values():
		if p.get("entrance", "") == rid:
			return true
	return false


func _match(n: String) -> bool:
	return _filter == "" or _filter in n.to_lower()


func _item(parent: TreeItem, kind: String, iid: String, text: String, col := Color(0, 0, 0, 0)) -> TreeItem:
	var it := tree.create_item(parent)
	var glyph: String = GLYPHS.get(kind, "·")
	it.set_text(0, "%s  %s" % [glyph, text])
	it.set_metadata(0, {"kind": kind, "id": iid})
	if col.a > 0:
		it.set_custom_color(0, col.lightened(0.2))
	it.collapsed = collapsed.get("%s:%s" % [kind, iid], kind == "room" and _filter == "")
	return it


func _room_item(parent: TreeItem, rid: String, label := "") -> TreeItem:
	var it := _item(parent, "room", rid, label if label != "" else OSData.room_name(rid))
	_room_content(it, rid)
	if _filter == "" and label == "Hub":
		it.collapsed = collapsed.get("room:" + rid, false)
	return it


func _room_content(it: TreeItem, rid: String) -> void:
	for cr in OSData.child_rooms(rid):
		if cr != World.data.hub and str(World.data.rooms[cr].get("parent_id", "")) == rid:
			var sub := _room_item(it, cr)
			if not _match(OSData.room_name(cr)):
				_prune(sub)
	for o in OSData.objects_in(rid, not furniture.button_pressed):
		if o.type in ["door", "portal"] or not _match(str(o.name)):
			continue
		var t := _item(it, "object", o.id, str(o.name))
		t.set_text(0, "%s  %s" % [GLYPHS.get(o.type, "·"), o.name])
		t.set_tooltip_text(0, ObjectRegistry.get_def(o.type).label)


## Avec un filtre : retire les branches sans correspondance.
func _prune(it: TreeItem) -> void:
	if _filter == "" or it.get_child_count() > 0:
		return
	var m = it.get_metadata(0)
	var n := it.get_text(0).substr(3)
	if m is Dictionary and m.kind in ["room", "portal"] and _match(n):
		return
	it.get_parent().remove_child(it)
	it.free()


func _find(it: TreeItem, ref: Dictionary) -> TreeItem:
	if it == null:
		return null
	var m = it.get_metadata(0)
	if m is Dictionary and m.kind == ref.kind and m.id == ref.id:
		return it
	var c := it.get_first_child()
	while c != null:
		var f := _find(c, ref)
		if f != null:
			return f
		c = c.get_next()
	return null


func select_ref(ref: Dictionary, scroll := true) -> void:
	var r := ref
	if r.kind == "portal" or r.kind == "room":
		# Une entrée de portail est représentée par le portail.
		for p in World.data.portals.values():
			if r.kind == "room" and p.get("entrance", "") == r.id:
				r = {"kind": "portal", "id": p.id}
	var it := _find(tree.get_root(), r)
	if it == null:
		return
	var p := it.get_parent()
	while p != null:
		p.collapsed = false
		p = p.get_parent()
	it.select(0)
	selected = r
	if scroll:
		tree.scroll_to_item(it)
	_show_details()


func _on_select() -> void:
	var it := tree.get_selected()
	var m = it.get_metadata(0) if it != null else null
	selected = m if m is Dictionary and m.kind != "folder" else {}
	_confirm_del = false
	_show_details()


func _show_details() -> void:
	OSApp.clear(details)
	if selected.is_empty() or not World.exists(selected.kind, selected.id):
		KWPanel.section(details, "Explorateur")
		KWPanel.dim(details, "Sélectionnez un portail, une salle, un objet ou un document.\nDouble-clic : ouvrir.")
		var s := OSData.stats()
		KWPanel.dim(details, "%d portails · %d salles · %d notes · %d documents" % [s.portals, s.rooms, s.notes, s.documents])
		return
	var k: String = selected.kind
	var sid: String = selected.id
	var nm := ""
	var info := []
	var room := ""
	match k:
		"portal":
			var p: Dictionary = World.data.portals[sid]
			nm = p.name
			room = str(p.get("entrance", ""))
			info.append("Portail · %d salle(s)" % World.data.rooms.values().filter(func(r): return r.get("portal_id", "") == sid).size())
		"room":
			var r: Dictionary = World.data.rooms[sid]
			nm = r.name
			room = sid
			info.append("Salle · " + OSData.room_path(sid))
			info.append("%d objet(s) · %d document(s)" % [OSData.objects_in(sid).size(), World.docs_for_room(sid).size()])
		"object":
			var o: Dictionary = World.data.objects[sid]
			nm = o.name
			room = o.room_id
			info.append("%s · %s" % [ObjectRegistry.get_def(o.type).label, OSData.room_path(o.room_id)])
			info.append("Modifié " + OSData.fmt_time(str(o.get("modified", ""))))
			var txt := ObjectRegistry.text_of(o).strip_edges()
			if txt != "":
				info.append("")
				info.append(txt.left(500) + ("…" if txt.length() > 500 else ""))
		"document":
			var d: Dictionary = World.data.documents[sid]
			nm = d.name
			info.append("Document %s · %d caractères" % [str(d.get("ext", "")).to_upper(), str(d.text).length()])
			info.append("Salles : " + (", ".join(PackedStringArray(d.rooms.map(func(r): return OSData.room_name(r)))) if not d.rooms.is_empty() else "aucune"))
	var title := Label.new()
	title.text = nm
	title.theme_type_variation = "Header"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(title)
	for l in info:
		KWPanel.dim(details, l)
	KWPanel.sep(details)
	var acts := HFlowContainer.new()
	details.add_child(acts)
	if k == "object" or k == "document":
		KWPanel.primary(acts, "Ouvrir", func(): _open(selected))
	if room != "":
		KWPanel.btn(acts, "Aller dans la salle", func(): _go(room))
	KWPanel.section(details, "Renommer")
	var rn := KWPanel.hbox(details)
	var edit := KWPanel.line(rn, nm)
	var do_rename := func():
		OSData.rename(k, sid, edit.text)
		toast("Renommé : " + edit.text)
	edit.text_submitted.connect(func(_t): do_rename.call())
	KWPanel.btn(rn, "Renommer", do_rename)
	if not (k == "room" and sid == World.data.hub):
		KWPanel.spacer(details)
		var del := KWPanel.danger(details, "Confirmer la suppression ?" if _confirm_del else "Supprimer…", func():
			if _confirm_del:
				OSData.delete(k, sid)
				toast("Supprimé : " + nm)
				selected = {}
				_confirm_del = false
			else:
				_confirm_del = true
				_show_details())
		del.size_flags_horizontal = Control.SIZE_SHRINK_END


func _open(ref: Dictionary) -> void:
	if ref.is_empty() or not World.exists(ref.kind, ref.id):
		return
	match ref.kind:
		"object":
			var o: Dictionary = World.data.objects[ref.id]
			if NoteLinks.is_note(o):
				open_ref(ref)
			elif os != null:
				os.go_to_object(ref.id)
		"document":
			open_ref(ref)
		"room":
			if os != null:
				os.go_to_room(ref.id)
		"portal":
			if os != null:
				os.go_to_room(str(World.data.portals[ref.id].entrance))


func _go(rid: String) -> void:
	if os != null:
		os.go_to_room(rid)
