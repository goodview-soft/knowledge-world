class_name DoorPanel
extends KWPanel
## Configuration d'une porte / d'un portail : choix de la salle de destination.

var id: String
var opt: OptionButton
var room_ids := []


func _init(obj_id: String) -> void:
	id = obj_id
	super("Destination de la porte", Vector2(640, 260))
	lbl(body, "Choisissez la salle vers laquelle mène cette porte :")
	opt = OptionButton.new()
	body.add_child(opt)
	var cur: String = World.data.objects[id].params.get("target_room", "")
	for r in World.data.rooms.values():
		room_ids.append(r.id)
		opt.add_item(r.name)
		if r.id == cur:
			opt.select(room_ids.size() - 1)
	var row := hbox(body)
	btn(row, "Valider", _apply)
	btn(row, "Valider et y aller", func():
		_apply()
		main.go_to_room(room_ids[opt.selected], main.current_room))


func _apply() -> void:
	if opt.selected < 0:
		return
	var p: Dictionary = World.data.objects[id].params.duplicate()
	p.target_room = room_ids[opt.selected]
	World.update_object(id, {"params": p})
	closed.emit()
