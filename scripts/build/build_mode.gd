class_name BuildMode
extends Node3D
## Mode construction : poser, sélectionner, déplacer, pivoter, redimensionner,
## dupliquer, supprimer ; accrochage au sol / aux murs selon la normale visée ;
## alignement sur grille optionnel (X).

var main: Node
var active := false
var snap := true
var selected := ""
var placing := ""
var grabbing := false
var _rot := 0.0
var _ghost: Node3D
var _sel_box: MeshInstance3D
var _target := {}


func _ready() -> void:
	_sel_box = MeshInstance3D.new()
	_sel_box.mesh = BoxMesh.new()
	var m := ObjectRegistry.mat(Color(1.0, 0.8, 0.35), 1.0)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color.a = 0.18
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_sel_box.material_override = m
	_sel_box.visible = false
	add_child(_sel_box)


func toggle() -> void:
	active = not active
	main.player.set_reach(8.0 if active else 3.5)
	if not active:
		cancel()
		deselect()
	_update_hud()


func _update_hud() -> void:
	var sel := ""
	if selected != "" and World.data.objects.has(selected):
		sel = World.label_of("object", selected)
	main.hud.set_build_state(active, placing, snap, sel, grabbing)


func cancel() -> void:
	placing = ""
	if grabbing and main.nodes.has(selected):
		main.nodes[selected].refresh()
	grabbing = false
	main.player.ray.clear_exceptions()
	if _ghost:
		_ghost.queue_free()
		_ghost = null
	_update_hud()


func deselect() -> void:
	selected = ""
	grabbing = false
	_sel_box.visible = false
	if active:
		_update_hud()


func select(id: String) -> void:
	selected = id
	_update_hud()


func _start_placing(type: String) -> void:
	cancel()
	deselect()
	placing = type
	_rot = 0.0
	var fake := {"id": "ghost", "type": type, "name": ObjectRegistry.get_def(type).label, "content": ObjectRegistry.default_content(type), "params": {}}
	_ghost = ObjectRegistry.build(fake)
	_make_ghost(_ghost)
	add_child(_ghost)
	_update_hud()


func _make_ghost(n: Node) -> void:
	for c in n.get_children():
		if c is GeometryInstance3D:
			c.transparency = 0.55
		if c is Light3D:
			c.visible = false
		_make_ghost(c)


## Calcule la pose (position, rotation) d'un objet de type/échelle donnés sous le réticule.
func _compute(type: String, scl: Vector3, base_rot) -> Dictionary:
	var ray: RayCast3D = main.player.ray
	ray.force_raycast_update()
	if not ray.is_colliding():
		return {}
	var p := ray.get_collision_point()
	var n := ray.get_collision_normal()
	var s: Vector3 = ObjectRegistry.get_def(type).size * scl
	var pos: Vector3
	var rot_y: float
	if n.y > 0.7:
		pos = p
		if base_rot == null:
			var to_player: Vector3 = main.player.global_position - p
			rot_y = rad_to_deg(atan2(to_player.x, to_player.z)) + _rot
		else:
			rot_y = base_rot + _rot
		if snap:
			pos.x = snappedf(pos.x, 0.25)
			pos.z = snappedf(pos.z, 0.25)
			rot_y = snappedf(rot_y, 15.0)
	elif absf(n.y) < 0.3:
		var nn := Vector3(n.x, 0, n.z).normalized()
		rot_y = rad_to_deg(atan2(nn.x, nn.z))
		pos = p + nn * (s.z / 2.0) - Vector3(0, s.y / 2.0, 0)
		if snap:
			var tan := Vector3(nn.z, 0, -nn.x)
			var t := pos.dot(tan)
			pos += tan * (snappedf(t, 0.25) - t)
			pos.y = snappedf(pos.y, 0.1)
		pos.y = maxf(pos.y, 0.0)
	else:
		return {}
	return {"pos": pos, "rot": Vector3(0, rot_y, 0)}


func _process(_delta: float) -> void:
	if not active:
		return
	if selected != "" and main.nodes.has(selected):
		var node: KWObject = main.nodes[selected]
		var o: Dictionary = World.data.objects[selected]
		var s: Vector3 = ObjectRegistry.get_def(o.type).size * World.vec(o.scale)
		if grabbing:
			_target = _compute(o.type, World.vec(o.scale), World.vec(o.rot).y)
			if not _target.is_empty():
				node.position = _target.pos
				node.rotation_degrees = _target.rot
		_sel_box.visible = true
		_sel_box.global_transform = node.global_transform
		_sel_box.translate_object_local(Vector3(0, s.y / 2.0, 0))
		(_sel_box.mesh as BoxMesh).size = s + Vector3(0.06, 0.06, 0.06)
	else:
		_sel_box.visible = false
	if placing != "" and _ghost:
		_target = _compute(placing, Vector3.ONE, null)
		_ghost.visible = not _target.is_empty()
		if _ghost.visible:
			_ghost.position = _target.pos
			_ghost.rotation_degrees = _target.rot


func _unhandled_input(event: InputEvent) -> void:
	if not active or main.panel != null or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT: _click()
			MOUSE_BUTTON_RIGHT:
				if placing != "" or grabbing: cancel()
				else: deselect()
			MOUSE_BUTTON_WHEEL_UP: _rotate(1)
			MOUSE_BUTTON_WHEEL_DOWN: _rotate(-1)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		var pk: int = event.physical_keycode
		if pk >= KEY_0 and pk <= KEY_9:
			var idx := (pk - KEY_1) if pk != KEY_0 else 9
			if idx < ObjectRegistry.PALETTE.size():
				_start_placing(ObjectRegistry.PALETTE[idx])
			get_viewport().set_input_as_handled()
			return
		var handled := true
		match event.keycode:
			KEY_X:
				snap = not snap
				main.hud.toast("Alignement grille : " + ("activé" if snap else "désactivé"))
			KEY_G: _toggle_grab()
			KEY_T:
				if selected != "" and World.data.objects.has(selected):
					main.open_panel(ObjectStylePanel.new(selected))
				else:
					handled = false
			KEY_R: _rotate(-1 if event.shift_pressed else 1)
			KEY_PAGEUP, KEY_KP_ADD: _scale(1.1)
			KEY_PAGEDOWN, KEY_KP_SUBTRACT: _scale(1.0 / 1.1)
			KEY_DELETE, KEY_BACKSPACE:
				if selected != "":
					World.delete_object(selected)
					deselect()
			KEY_D:
				if event.ctrl_pressed and selected != "":
					var nid := World.duplicate_object(selected)
					select(nid)
					_toggle_grab()
				else:
					handled = false
			_: handled = false
		if handled:
			_update_hud()
			get_viewport().set_input_as_handled()


func _click() -> void:
	if placing != "":
		if _target.is_empty():
			return
		var type := placing
		var id := World.create_object(type, main.current_room, _target.pos, _target.rot)
		main.hud.toast("%s posé(e)." % ObjectRegistry.get_def(type).label)
		if type == "door":
			cancel()
			main.open_panel(DoorPanel.new(id))
		return
	if grabbing:
		_drop()
		return
	var id: String = main.aimed_object_id()
	if id == "":
		deselect()
	else:
		select(id)


func _toggle_grab() -> void:
	if selected == "" or not main.nodes.has(selected):
		return
	if grabbing:
		_drop()
		return
	grabbing = true
	_rot = 0.0
	main.player.ray.add_exception(main.nodes[selected].body)


func _drop() -> void:
	grabbing = false
	main.player.ray.clear_exceptions()
	if not _target.is_empty() and World.data.objects.has(selected):
		var o: Dictionary = World.data.objects[selected]
		World.set_transform(selected, _target.pos, _target.rot, World.vec(o.scale))
	_update_hud()


func _rotate(dir: int) -> void:
	var step := 15.0 if snap else 5.0
	if placing != "" or grabbing:
		_rot += step * dir
	elif selected != "":
		var o: Dictionary = World.data.objects[selected]
		var r := World.vec(o.rot)
		r.y += step * dir
		World.update_object(selected, {"rot": r})


func _scale(f: float) -> void:
	if selected == "" or not World.data.objects.has(selected):
		return
	var s := (World.vec(World.data.objects[selected].scale) * f).clamp(Vector3.ONE * 0.2, Vector3.ONE * 5.0)
	World.update_object(selected, {"scale": s})
