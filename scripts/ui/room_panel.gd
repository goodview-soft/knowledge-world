class_name RoomPanel
extends KWPanel
## Personnalisation d'une salle (P) : préréglages, couleurs, matériau du sol,
## ambiance lumineuse, dimensions. Tout est enregistré dans World.data.rooms[id].

const MAT_LABELS := [["uni", "Uni"], ["bois", "Bois"], ["beton", "Béton"], ["moquette", "Moquette"], ["carrelage", "Carrelage"], ["marbre", "Marbre"]]
const MOOD_LABELS := [["chaude", "Chaude"], ["neutre", "Neutre"], ["froide", "Froide"], ["tamisee", "Tamisée"]]

var room_id: String
var _content: VBoxContainer
var _size_timer: Timer
var _pending_size := []


func _init(id: String) -> void:
	room_id = id
	super("Personnaliser la salle", Vector2(780, 760))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 12)
	scroll.add_child(_content)
	_size_timer = Timer.new()
	_size_timer.one_shot = true
	_size_timer.wait_time = 0.3
	_size_timer.timeout.connect(_apply_size)
	add_child(_size_timer)
	var row := hbox(body)
	ghost(row, "Réinitialiser l'apparence", func():
		var r: Dictionary = World.data.rooms[room_id]
		for k in ["wall_color", "floor_color", "ceil_color", "floor_mat", "light", "light_energy"]:
			r.erase(k)
		World.update_room(room_id, {})
		_build())
	spacer(row)
	primary(row, "Terminé", func(): closed.emit())
	_build()


func _ready() -> void:
	super()
	if World.data.rooms.has(room_id):
		set_subtitle(World.data.rooms[room_id].name)


func _build() -> void:
	for c in _content.get_children():
		c.queue_free()
	if not World.data.rooms.has(room_id):
		return
	var r: Dictionary = World.data.rooms[room_id]
	var st := RoomBuilder.style_of(r)
	var c0 := card(_content, "Préréglages")
	var flow := HFlowContainer.new()
	c0.add_child(flow)
	for pname in World.ROOM_PRESETS:
		chip(flow, pname, func():
			World.update_room(room_id, World.ROOM_PRESETS[pname])
			_build())
	var c1 := card(_content, "Couleurs")
	color_field(c1, "Murs", st.wall_color, func(c: Color): _put("wall_color", c.to_html(false)))
	color_field(c1, "Sol", st.floor_color, func(c: Color): _put("floor_color", c.to_html(false)))
	color_field(c1, "Plafond", st.ceil_color, func(c: Color): _put("ceil_color", c.to_html(false)))
	choice(c1, "Matériau du sol", MAT_LABELS, st.floor_mat, func(k: String): _put("floor_mat", k))
	var c2 := card(_content, "Lumière")
	choice(c2, "Ambiance", MOOD_LABELS, st.light, func(k: String): _put("light", k))
	slider(c2, "Intensité", st.light_energy, 0.2, 2.0, 0.05, func(v: float): _put("light_energy", v), "%.2f")
	var c3 := card(_content, "Dimensions")
	var s: Array = r["size"]
	_pending_size = [float(s[0]), float(s[1]), float(s[2])]
	slider(c3, "Largeur", _pending_size[0], 4.0, 40.0, 0.5, func(v: float): _queue_size(0, v), "%.1f m")
	slider(c3, "Profondeur", _pending_size[2], 4.0, 40.0, 0.5, func(v: float): _queue_size(2, v), "%.1f m")
	slider(c3, "Hauteur", _pending_size[1], 2.6, 12.0, 0.1, func(v: float): _queue_size(1, v), "%.1f m")
	dim(c3, "Les objets restent dans la salle ; ceux fixés aux murs (portes, tableaux) suivent leur mur.")


func _put(key: String, value) -> void:
	World.update_room(room_id, {key: value})


func _queue_size(axis: int, v: float) -> void:
	_pending_size[axis] = v
	_size_timer.start()


func _apply_size() -> void:
	World.update_room(room_id, {"size": _pending_size.duplicate()})


func on_close() -> void:
	if not _size_timer.is_stopped():
		_size_timer.stop()
		_apply_size()
