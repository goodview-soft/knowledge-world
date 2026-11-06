class_name KanbanPanel
extends KWPanel
## Tableau Kanban : colonnes et cartes éditables, déplacement gauche/droite.

var id: String
var content: Dictionary
var name_edit: LineEdit
var cols_box: HBoxContainer


func _init(obj_id: String) -> void:
	id = obj_id
	var o: Dictionary = World.data.objects[id]
	super("Kanban", Vector2(1200, 720))
	content = o.content.duplicate(true)
	var top := hbox(body)
	name_edit = line(top, o.name, "Nom du tableau")
	btn(top, "+ Colonne", func(): content.columns.append({"title": "Nouvelle colonne", "cards": []}); _commit())
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	cols_box = HBoxContainer.new()
	cols_box.add_theme_constant_override("separation", 12)
	cols_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(cols_box)
	_rebuild()


func _rebuild() -> void:
	for c in cols_box.get_children():
		c.queue_free()
	var cols: Array = content.columns
	for ci in cols.size():
		var col: Dictionary = cols[ci]
		var pc := PanelContainer.new()
		pc.custom_minimum_size = Vector2(270, 0)
		cols_box.add_child(pc)
		var v := VBoxContainer.new()
		pc.add_child(v)
		var head := hbox(v)
		var t := line(head, col.title)
		t.text_changed.connect(func(s): col.title = s)
		btn(head, "✕", func(): cols.remove_at(ci); _commit())
		for k in col.cards.size():
			var row := hbox(v)
			var e := line(row, str(col.cards[k]))
			e.text_changed.connect(func(s): col.cards[k] = s)
			if ci > 0:
				btn(row, "◀", func(): cols[ci - 1].cards.append(col.cards.pop_at(k)); _commit())
			if ci < cols.size() - 1:
				btn(row, "▶", func(): cols[ci + 1].cards.append(col.cards.pop_at(k)); _commit())
			btn(row, "✕", func(): col.cards.remove_at(k); _commit())
		btn(v, "+ Carte", func(): col.cards.append("Nouvelle carte"); _commit())


func _commit() -> void:
	_save()
	_rebuild()


func _save() -> void:
	World.update_object(id, {"name": name_edit.text, "content": content.duplicate(true)})


func on_close() -> void:
	if World.data.objects.has(id):
		_save()
