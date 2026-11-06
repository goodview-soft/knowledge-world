class_name KWObject
extends Node3D
## Représentation 3D d'un objet de données (World.data.objects[obj_id]).
## Reconstruit entièrement à chaque modification : la donnée fait foi.

var obj_id := ""
var body: StaticBody3D


func setup(id: String) -> KWObject:
	obj_id = id
	refresh()
	return self


func refresh() -> void:
	for ch in get_children():
		remove_child(ch)
		ch.queue_free()
	var o: Dictionary = World.data.objects.get(obj_id, {})
	if o.is_empty():
		return
	position = World.vec(o.pos)
	rotation_degrees = World.vec(o.rot)
	var scl := World.vec(o.scale)
	var visual := ObjectRegistry.build(o, _extra(o))
	visual.scale = scl
	add_child(visual)
	var s: Vector3 = ObjectRegistry.get_def(o.type).size * scl
	# Corps solides (layer 2) ; objets non bloquants ou passages : layer 8 (visables, traversables).
	body = StaticBody3D.new()
	body.collision_mask = 0
	body.set_meta("kw_id", obj_id)
	var parts: Array = [] if o.type in ["door", "portal"] else ObjectRegistry.colliders(o.type, scl)
	body.collision_layer = 2 if not parts.is_empty() else 8
	if parts.is_empty():
		parts = [{"size": s, "center": Vector3(0, s.y / 2.0, 0)}]
	for part in parts:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = (part.size as Vector3).max(Vector3(0.05, 0.05, 0.05))
		cs.shape = bs
		cs.position = part.center
		body.add_child(cs)
	add_child(body)


func _extra(o: Dictionary) -> Dictionary:
	var e := {}
	match o.type:
		"library":
			e.doc_count = World.docs_for_room(o.room_id).size()
		"door", "portal":
			var t: String = o.params.get("target_room", "")
			if World.data.rooms.has(t):
				var r = World.data.rooms[t]
				e.target_name = ("→ " if o.type == "door" else "") + (o.name if o.type == "portal" else r.name)
				e.color = r.color
	return e
