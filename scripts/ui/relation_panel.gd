class_name RelationPanel
extends KWPanel
## Relations d'un élément (salle, portail, objet, document) : liste, ajout, suppression.

var kind: String
var id: String
var list_box: VBoxContainer
var target: OptionButton
var type_opt: OptionButton
var desc: LineEdit
var targets := []


func _init(k: String, i: String) -> void:
	kind = k
	id = i
	super("Relations — " + World.label_of(k, i), Vector2(960, 640))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list_box)
	body.add_child(HSeparator.new())
	lbl(body, "Nouvelle relation", 17)
	var row := hbox(body)
	target = OptionButton.new()
	target.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(target)
	type_opt = OptionButton.new()
	for t in World.RELATION_TYPES:
		type_opt.add_item(t)
	row.add_child(type_opt)
	var row2 := hbox(body)
	desc = line(row2, "", "Description (facultatif)")
	btn(row2, "Ajouter", _add)


func _ready() -> void:
	super()
	_fill_targets()
	_refresh()


func _fill_targets() -> void:
	targets.clear()
	target.clear()
	var add := func(k: String, i: String):
		if not (k == kind and i == id):
			targets.append([k, i])
			target.add_item(World.label_of(k, i))
	for r in World.data.rooms:
		add.call("room", r)
	for p in World.data.portals:
		add.call("portal", p)
	for o in World.objects_in_room(main.current_room):
		if not o.type in ["door", "portal", "lamp"]:
			add.call("object", o.id)
	for d in World.data.documents:
		add.call("document", d)


func _refresh() -> void:
	for c in list_box.get_children():
		c.queue_free()
	var rels := World.relations_of(kind, id)
	if rels.is_empty():
		lbl(list_box, "Aucune relation pour l'instant.")
	for r in rels:
		var outgoing: bool = r.from.kind == kind and r.from.id == id
		var other: Dictionary = r.to if outgoing else r.from
		var h := hbox(list_box)
		var l := lbl(h, "%s  [%s]  %s%s" % ["→" if outgoing else "←", r.type, World.label_of(other.kind, other.id),
			("  — " + r.description) if r.description != "" else ""])
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if other.kind in ["room", "object"]:
			btn(h, "Aller", func():
				if other.kind == "room": main.go_to_room(other.id)
				else: main.go_to_object(other.id))
		btn(h, "✕", func(): World.delete_relation(r.id); _refresh())


func _add() -> void:
	if target.selected < 0:
		return
	var t: Array = targets[target.selected]
	World.add_relation(kind, id, t[0], t[1], World.RELATION_TYPES[type_opt.selected], desc.text.strip_edges())
	desc.clear()
	_refresh()
