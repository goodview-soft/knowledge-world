class_name OSApp
extends VBoxContainer
## Base des applications de KW OS. `os` = OSPanel hôte (null possible en test isolé).

var os: Node


func _init() -> void:
	add_theme_constant_override("separation", 10)


## Appelée (coalescée) après une modification du monde.
func refresh() -> void:
	pass


## Enregistre les modifications en cours (fermeture de fenêtre / de l'OS).
func flush() -> void:
	pass


## Arguments d'ouverture (ex. {"note": id}).
func open_args(_args: Dictionary) -> void:
	pass


func current_room() -> String:
	if os != null and os.main != null and World.data.rooms.has(os.main.current_room):
		return os.main.current_room
	return World.data.hub


func toast(msg: String) -> void:
	if os != null:
		os.notify(msg)


## Ouvre une référence {kind, id} dans l'app adaptée.
func open_ref(ref: Dictionary) -> void:
	if os != null:
		os.open_ref(ref)


static func split_list(left_w := 300.0) -> HSplitContainer:
	var s := HSplitContainer.new()
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.split_offset = int(left_w)
	return s


static func scroll_v(parent: Control) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(sc)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	return v


static func clear(c: Node) -> void:
	for ch in c.get_children():
		c.remove_child(ch)
		ch.queue_free()
