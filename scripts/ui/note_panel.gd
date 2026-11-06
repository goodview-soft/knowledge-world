class_name NotePanel
extends KWPanel
## Édition des notes, post-it et fiches + transformations.

const COLORS := ["#f2efe6", "#ffe27a", "#ffb3a7", "#a8d8b9", "#a7c7e7", "#d7bde2", "#ffffff"]
var id: String
var name_edit: LineEdit
var text_edit: TextEdit
var color: String


func _init(obj_id: String) -> void:
	id = obj_id
	var o: Dictionary = World.data.objects[id]
	super(ObjectRegistry.get_def(o.type).label, Vector2(780, 580))
	color = o.content.get("color", "#f2efe6")
	name_edit = line(body, o.name, "Titre")
	text_edit = TextEdit.new()
	text_edit.text = o.content.get("text", "")
	text_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	text_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text_edit.placeholder_text = "Écrivez ici… (une ligne = une carte si transformée en Kanban)"
	body.add_child(text_edit)
	var row := hbox(body)
	lbl(row, "Couleur :")
	for c in COLORS:
		var b := btn(row, "  ■  ", func(): color = c; _save())
		b.add_theme_color_override("font_color", Color(c))
		b.add_theme_color_override("font_hover_color", Color(c))
	var acts := hbox(body)
	btn(acts, "→ Fiche", func(): _transform("note_to_card", "Fiche créée à côté."))
	btn(acts, "→ Kanban", func(): _transform("note_to_kanban", "Kanban créé (une carte par ligne)."))
	btn(acts, "→ Nouvelle salle", func(): _transform("note_to_room", "Salle créée : une porte a été ajoutée ici."))
	btn(acts, "Relations…", func(): _save(); main.open_relations("object", id))
	var del := btn(acts, "Supprimer", func(): World.delete_object(id); closed.emit())
	del.add_theme_color_override("font_color", Color(1, 0.6, 0.55))


func _ready() -> void:
	super()
	text_edit.grab_focus()


func _save() -> void:
	if not World.data.objects.has(id):
		return
	var c: Dictionary = World.data.objects[id].content.duplicate(true)
	c.text = text_edit.text
	c.color = color
	World.update_object(id, {"name": name_edit.text, "content": c})


func _transform(op: String, msg: String) -> void:
	_save()
	World.transform(op, id)
	main.hud.toast(msg + " L'original est conservé.")
	closed.emit()


func on_close() -> void:
	_save()
