class_name ObjectStylePanel
extends KWPanel
## Style d'un objet (T en mode construction) : nom, couleurs principale/secondaire,
## et pour la lampe : couleur et intensité de la lumière. Stocké dans params.style.

const DEFAULTS := {
	"note": ["", "#1f1f1f"], "postit": ["", "#1f1f1f"], "card": ["", "#1f1f1f"],
	"kanban": ["#2e333b", "#424a54"], "desk": ["#8c6b4f", "#333338"], "library": ["#7a5e47", "#7a5e47"],
	"table": ["#9e998f", "#9e998f"], "lamp": ["#333333", "#ffe2bd"], "door": ["#38383d", "#cfc8bc"], "portal": ["#38383d", "#cfc8bc"],
}

var id: String
var name_edit: LineEdit


func _init(obj_id: String) -> void:
	id = obj_id
	super("Style de l'objet", Vector2(620, 540))
	var o: Dictionary = World.data.objects[id]
	var c0 := card(body, "Nom")
	name_edit = line(c0, o.name, "Nom de l'objet")
	name_edit.text_submitted.connect(func(_t): _save_name())
	var slots: Array = ObjectRegistry.style_slots(o.type)
	if not slots.is_empty():
		var c1 := card(body, "Couleurs")
		var defs: Array = DEFAULTS.get(o.type, ["#999999", "#999999"])
		var p_def: String = defs[0] if defs[0] != "" else str(o.get("content", {}).get("color", "#f2efe6"))
		color_field(c1, slots[0], ObjectRegistry.style_color(o, "primary", Color(p_def)), func(c: Color): _put("primary", c.to_html(false)))
		color_field(c1, slots[1], ObjectRegistry.style_color(o, "secondary", Color(defs[1])), func(c: Color): _put("secondary", c.to_html(false)))
	if o.type == "lamp":
		var c2 := card(body, "Lumière")
		color_field(c2, "Couleur", ObjectRegistry.style_color(o, "light_color", Color(1.0, 0.83, 0.62)), func(c: Color): _put("light_color", c.to_html(false)))
		slider(c2, "Intensité", ObjectRegistry.style_float(o, "light_energy", 0.9), 0.0, 3.0, 0.05, func(v: float): _put("light_energy", v))
	if slots.is_empty() and o.type != "lamp":
		dim(body, "Ce type d'objet se personnalise uniquement par son nom.")
	spacer(body)
	var row := hbox(body)
	ghost(row, "Style par défaut", func():
		var p: Dictionary = World.data.objects[id].params.duplicate(true)
		p.erase("style")
		World.update_object(id, {"params": p})
		closed.emit())
	spacer(row)
	primary(row, "Terminé", func(): closed.emit())


func _ready() -> void:
	super()
	set_subtitle(ObjectRegistry.get_def(World.data.objects[id].type).label)


func _put(key: String, value) -> void:
	if not World.data.objects.has(id):
		return
	var p: Dictionary = World.data.objects[id].params.duplicate(true)
	var st: Dictionary = p.get("style", {})
	st[key] = value
	p["style"] = st
	World.update_object(id, {"params": p})


func _save_name() -> void:
	var n := name_edit.text.strip_edges()
	if n != "" and World.data.objects.has(id) and n != World.data.objects[id].name:
		World.update_object(id, {"name": n})


func on_close() -> void:
	_save_name()
