class_name OSDocuments
extends OSApp
## Documents : liste et lecture des documents de la bibliothèque (World.data.documents),
## salles liées, extrait sélectionné → note.

const VIEW_MAX := 300000

var search: LineEdit
var list: ItemList
var ids := []
var current := ""
var title_lbl: Label
var info_lbl: Label
var rooms_box: HFlowContainer
var viewer: TextEdit


func _init() -> void:
	super()
	var split := OSApp.split_list(300)
	add_child(split)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 240
	split.add_child(left)
	search = KWPanel.line(left, "", "Rechercher (nom ou contenu)…")
	search.text_changed.connect(func(_t): refresh())
	list = ItemList.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.item_selected.connect(func(i: int): show_doc(ids[i]))
	left.add_child(list)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(right)
	title_lbl = Label.new()
	title_lbl.theme_type_variation = "Header"
	title_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	right.add_child(title_lbl)
	info_lbl = KWPanel.dim(right, "Sélectionnez un document.")
	rooms_box = HFlowContainer.new()
	right.add_child(rooms_box)
	viewer = TextEdit.new()
	viewer.editable = false
	viewer.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	viewer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(viewer)
	var acts := KWPanel.hbox(right)
	KWPanel.btn(acts, "Sélection → note", _to_note)
	KWPanel.dim(acts, "Renommer / supprimer : Explorateur.")
	refresh()


func open_args(args: Dictionary) -> void:
	if args.has("doc"):
		show_doc(args.doc)


func refresh() -> void:
	var q := search.text.strip_edges().to_lower()
	var docs: Array = World.data.documents.values().filter(func(d): return q == "" or q in str(d.name).to_lower() or q in str(d.text).to_lower())
	docs.sort_custom(func(a, b): return str(a.name).naturalnocasecmp_to(str(b.name)) < 0)
	list.clear()
	ids.clear()
	for d in docs:
		var i := list.add_item("%s\n%s · %d car." % [d.name, str(d.get("ext", "")).to_upper(), str(d.text).length()])
		ids.append(d.id)
		if d.id == current:
			list.select(i)
	if current != "" and not World.data.documents.has(current):
		current = ""
		title_lbl.text = ""
		viewer.text = ""
		info_lbl.text = "Document supprimé."
		OSApp.clear(rooms_box)
	elif current != "":
		_show_meta()


func show_doc(did: String) -> void:
	if not World.data.documents.has(did):
		return
	current = did
	var d: Dictionary = World.data.documents[did]
	var t := str(d.text)
	viewer.text = t.left(VIEW_MAX) + ("\n\n… (affichage tronqué)" if t.length() > VIEW_MAX else "")
	viewer.scroll_vertical = 0
	_show_meta()
	for i in ids.size():
		if ids[i] == did:
			list.select(i)


func _show_meta() -> void:
	var d: Dictionary = World.data.documents[current]
	title_lbl.text = d.name
	var words := str(d.text).split(" ", false).size()
	info_lbl.text = "%s · %d caractères · ~%d mots%s" % [str(d.get("ext", "")).to_upper(), str(d.text).length(), words,
		("  ·  " + str(d.source_path).get_file()) if str(d.get("source_path", "")) != "" else ""]
	OSApp.clear(rooms_box)
	KWPanel.section(rooms_box, "Salles")
	if d.rooms.is_empty():
		KWPanel.dim(rooms_box, "aucune")
	for r in d.rooms:
		if World.data.rooms.has(r):
			var rid: String = r
			KWPanel.chip(rooms_box, OSData.room_name(r), func(): _go(rid))


func _go(rid: String) -> void:
	if os != null:
		os.go_to_room(rid)


func _to_note() -> void:
	if current == "":
		return
	var sel := viewer.get_selected_text().strip_edges()
	if sel == "":
		toast("Sélectionnez un passage du document.")
		return
	var d: Dictionary = World.data.documents[current]
	var nid := OSData.create_note(current_room(), "Extrait · " + d.name, "> " + sel.replace("\n", "\n> ") + "\n\n[[%s]]\n" % d.name)
	World.add_relation("document", current, "object", nid, "source", "Extrait du document")
	toast("Note créée dans « %s »." % OSData.room_name(current_room()))
	open_ref({"kind": "object", "id": nid})
