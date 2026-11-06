class_name GraphPanel
extends KWPanel
## Vue graphe (touche G) : tout le monde ou notes seules, filtre par #tag,
## clic sur un nœud = y aller / l'ouvrir.

var graph: KWGraphView
var mode := "all"
var tag := ""
var tag_pick: OptionButton
var tag_list: VBoxContainer
var tag_card: VBoxContainer
var _tags := []


func _init(start_mode := "all", start_tag := "") -> void:
	mode = start_mode
	tag = start_tag
	super("Graphe des connaissances", Vector2(1240, 760))
	var top := hbox(body)
	var group := ButtonGroup.new()
	for opt in [["all", "Tout"], ["notes", "Notes seules"]]:
		var key: String = opt[0]
		var b := chip(top, opt[1], func(): mode = key; rebuild())
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = key == mode
	tag_pick = OptionButton.new()
	tag_pick.focus_mode = Control.FOCUS_CLICK
	tag_pick.item_selected.connect(func(i): tag = _tags[i]; rebuild())
	top.add_child(tag_pick)
	ghost(top, "Recentrer", func(): graph.auto_fit = true; graph.fit())
	ghost(top, "Note du jour", func(): NoteLinks.open_ref(main, {"kind": "object", "id": NoteLinks.daily_note()}))
	var mid := HBoxContainer.new()
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 14)
	body.add_child(mid)
	graph = KWGraphView.new()
	graph.node_clicked.connect(_on_click)
	mid.add_child(graph)
	tag_card = card(mid, "Notes taguées")
	tag_card.get_parent().custom_minimum_size.x = 250
	tag_list = VBoxContainer.new()
	tag_card.add_child(tag_list)
	var legend := hbox(body)
	for pair in [["room", "Salle"], ["note", "Note"], ["document", "Document"]]:
		var l := lbl(legend, "●  " + pair[1])
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		l.add_theme_color_override("font_color", KWGraphView.COLORS[pair[0]])
	spacer(legend)
	dim(legend, "Molette : zoom · glisser : déplacer · survol : voisins · clic : ouvrir").autowrap_mode = TextServer.AUTOWRAP_OFF
	rebuild()


func rebuild() -> void:
	_tags = [""]
	tag_pick.clear()
	tag_pick.add_item("Tous les tags")
	var all := NoteLinks.all_tags()
	var keys := all.keys()
	keys.sort()
	for t in keys:
		_tags.append(t)
		tag_pick.add_item("#%s  (%d)" % [t, all[t]])
	if not tag in _tags:
		tag = ""
	tag_pick.select(_tags.find(tag))
	graph.build(mode, tag)
	tag_card.get_parent().visible = tag != ""
	for c in tag_list.get_children():
		c.queue_free()
	for nid in NoteLinks.notes_with_tag(tag) if tag != "" else []:
		var b := ghost(tag_list, "◆  " + World.data.objects[nid].name, func(): _on_click("object", nid))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	set_subtitle("%d nœuds · %d liens" % [graph.nodes.size(), graph.edges.size()])


func _on_click(kind: String, id: String) -> void:
	NoteLinks.open_ref(main, {"kind": kind, "id": id})
