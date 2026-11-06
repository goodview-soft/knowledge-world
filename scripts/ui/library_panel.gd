class_name LibraryPanel
extends KWPanel
## Bibliothèque : import (bouton ou glisser-déposer), consultation, association
## multi-salles sans duplication, recherche documentaire (RagBackend).

var list: ItemList
var viewer: TextEdit
var info: Label
var search: LineEdit
var show_all: CheckBox
var ids := []
var current := ""
var obj_id := ""


func _init(library_obj := "") -> void:
	obj_id = library_obj
	super("Bibliothèque", Vector2(1180, 720))
	var top := hbox(body)
	search = line(top, "", "Rechercher dans les documents…")
	search.text_changed.connect(func(_t): refresh())
	show_all = CheckBox.new()
	show_all.text = "Tous les documents"
	show_all.toggled.connect(func(_b): refresh())
	top.add_child(show_all)
	btn(top, "Importer…", _import)
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(split)
	list = ItemList.new()
	list.custom_minimum_size = Vector2(360, 0)
	list.item_selected.connect(func(i): _show(ids[i]))
	split.add_child(list)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(right)
	info = lbl(right, "Sélectionnez un document. Astuce : glissez-déposez des fichiers dans la fenêtre.", 15)
	viewer = TextEdit.new()
	viewer.editable = false
	viewer.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	viewer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(viewer)
	var acts := hbox(right)
	btn(acts, "Associer à cette salle", func(): _link(true))
	btn(acts, "Retirer de cette salle", func(): _link(false))
	btn(acts, "Note depuis la sélection", _to_note)
	btn(acts, "Relations…", func():
		if current != "":
			main.open_relations("document", current))
	btn(acts, "Supprimer", func():
		if current != "":
			World.delete_document(current); current = ""; viewer.text = ""; refresh())


func _ready() -> void:
	super()
	refresh()


func refresh() -> void:
	list.clear()
	ids.clear()
	var q := search.text.strip_edges()
	if q != "":
		for r in Assistant.rag.search(q, [], 30):
			ids.append(r.doc_id)
			list.add_item("%s  (%d)" % [World.data.documents[r.doc_id].name, r.score])
	else:
		var docs: Array = World.data.documents.values() if show_all.button_pressed else World.docs_for_room(main.current_room)
		for d in docs:
			ids.append(d.id)
			list.add_item(d.name + ("" if main.current_room in d.rooms else "   (autre salle)"))
	if ids.is_empty():
		list.add_item("(aucun document — importez-en ou cochez « Tous les documents »)")
		list.set_item_disabled(0, true)


func _show(doc_id: String) -> void:
	current = doc_id
	var d: Dictionary = World.data.documents[doc_id]
	var rooms := PackedStringArray(d.rooms.filter(func(r): return World.data.rooms.has(r)).map(func(r): return World.data.rooms[r].name))
	info.text = "%s — importé le %s — salles : %s" % [d.name, d.imported.left(10), ", ".join(rooms) if rooms.size() > 0 else "aucune"]
	viewer.text = d.text


func _link(on: bool) -> void:
	if current == "":
		return
	World.link_document(current, main.current_room, on)
	_show(current)
	refresh()


func _to_note() -> void:
	if current == "":
		return
	var txt := viewer.get_selected_text()
	if txt.strip_edges() == "":
		txt = viewer.text.left(600)
	var pos := Vector3(0, 1.2, 0)
	var rot := Vector3.ZERO
	var lib = World.data.objects.get(obj_id)
	if lib != null:
		rot = World.vec(lib.rot)
		pos = World.vec(lib.pos) + Basis.from_euler(rot * PI / 180.0) * Vector3(1.1, 1.2, 0.0)
	World.transform("doc_to_note", current, {"room_id": main.current_room, "text": txt, "pos": pos, "rot": rot})
	main.hud.toast("Note créée (relation « source » vers le document).")


func _import() -> void:
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.use_native_dialog = true
	fd.filters = PackedStringArray(["*.txt, *.md, *.csv, *.json, *.log, *.html, *.xml, *.yaml ; Texte", "*.pdf ; PDF"])
	fd.files_selected.connect(func(paths):
		main.import_files(paths)
		refresh())
	add_child(fd)
	fd.popup_centered(Vector2i(900, 600))
