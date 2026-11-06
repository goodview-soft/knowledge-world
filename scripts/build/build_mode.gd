class_name BuildMode
extends Node3D
## Mode construction : poser, sélectionner, déplacer, pivoter, redimensionner,
## dupliquer, supprimer ; accrochage au sol / aux murs selon la normale visée ;
## alignement sur grille optionnel (X) ; inventaire (I / Tab) et barre rapide 1-0 (KWHotbar) ;
## aperçu fantôme vert / rouge (collision) ; murs accrochés bout à bout.

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
var current_slot := 0
var blocked := false
var _tint_ok: StandardMaterial3D
var _tint_bad: StandardMaterial3D
var _grab_tinted := false


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
	_tint_ok = _tint_mat(Color(0.45, 1.0, 0.6, 0.22))
	_tint_bad = _tint_mat(Color(1.0, 0.35, 0.3, 0.45))


static func _tint_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.no_depth_test = false
	return m


## Ouvre l'inventaire (grille par catégories, barre rapide personnalisable).
func open_inventory() -> void:
	if not active:
		toggle()
	main.open_panel(InventoryPanel.new(self))


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
	main.hud.set_build_state(active, placing, snap, sel, grabbing, blocked)


func cancel() -> void:
	placing = ""
	if grabbing and main.nodes.has(selected):
		main.nodes[selected].refresh()
	grabbing = false
	_grab_tinted = false
	blocked = false
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
		if c is MeshInstance3D:
			c.material_overlay = _tint_ok
		if c is Light3D:
			c.visible = false
		_make_ghost(c)


## Teinte (vert = libre, rouge = occupé) d'un fantôme ou de l'objet déplacé.
func _set_tint(n: Node, bad: bool) -> void:
	for c in n.get_children():
		if c is MeshInstance3D:
			c.material_overlay = _tint_bad if bad else _tint_ok
		_set_tint(c, bad)


## L'emplacement chevauche-t-il un mur de salle, un objet bloquant ou le joueur ?
func _is_blocked(type: String, pos: Vector3, rot: Vector3, scl: Vector3, exclude: Array = []) -> bool:
	var parts := ObjectRegistry.colliders(type, scl)
	if parts.is_empty():
		return false
	var space := get_world_3d().direct_space_state
	var xf := Transform3D(Basis.from_euler(rot * (PI / 180.0)), pos)
	for part in parts:
		var sz: Vector3 = part.size
		var bs := BoxShape3D.new()
		bs.size = (sz - Vector3(0.06, 0.06, 0.06)).max(Vector3(0.01, 0.01, 0.01))
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = bs
		var c: Vector3 = part.center
		q.transform = xf * Transform3D(Basis(), c + Vector3(0, 0.02, 0))
		q.collision_mask = 1 | 2 | 4
		q.exclude = exclude
		if not space.intersect_shape(q, 1).is_empty():
			return true
	return false


## Accroche un mur au bout (ou en angle) d'un mur existant proche. {} si rien à moins de 0,7 m.
func _edge_snap(type: String, scl: Vector3, p: Vector3, exclude_id: String) -> Dictionary:
	var wn: float = ObjectRegistry.get_def(type).size.x * scl.x
	var tn: float = ObjectRegistry.get_def(type).size.z * scl.z
	var best := {}
	var best_d := 0.7
	for id in main.nodes:
		if id == exclude_id or not World.data.objects.has(id):
			continue
		var o: Dictionary = World.data.objects[id]
		var d: Dictionary = ObjectRegistry.get_def(o.type)
		if not d.get("edge_snap", false):
			continue
		var osc := World.vec(o.scale)
		var op := World.vec(o.pos)
		var ry: float = World.vec(o.rot).y
		var right := Basis(Vector3.UP, deg_to_rad(ry)) * Vector3.RIGHT
		var fwd := Basis(Vector3.UP, deg_to_rad(ry)) * Vector3.BACK
		var w: float = d.size.x * osc.x
		var to: float = d.size.z * osc.z
		for sgn in [-1.0, 1.0]:
			var e: Vector3 = op + right * sgn * w / 2.0
			var cands := [[e + right * sgn * wn / 2.0, ry]] # dans le prolongement
			for side in [-1.0, 1.0]: # en angle droit, affleurant
				cands.append([e - right * sgn * tn / 2.0 + fwd * side * (wn / 2.0 + to / 2.0), ry + 90.0])
			for cd in cands:
				var cp: Vector3 = cd[0]
				var dist := Vector2(cp.x - p.x, cp.z - p.z).length()
				if dist < best_d:
					best_d = dist
					best = {"pos": Vector3(cp.x, op.y, cp.z), "rot": Vector3(0, cd[1], 0)}
	return best


## Calcule la pose (position, rotation) d'un objet de type/échelle donnés sous le réticule.
## DEFS "mount" : floor (au sol ; visé sur un mur → posé au pied, dos au mur), wall, ceiling, sinon libre.
func _compute(type: String, scl: Vector3, base_rot, exclude_id := "") -> Dictionary:
	var ray: RayCast3D = main.player.ray
	ray.force_raycast_update()
	if not ray.is_colliding():
		return {}
	var p := ray.get_collision_point()
	var n := ray.get_collision_normal()
	var d: Dictionary = ObjectRegistry.get_def(type)
	var mount := str(d.get("mount", ""))
	var s: Vector3 = d.size * scl
	var pos: Vector3
	var rot_y: float
	if mount == "ceiling":
		if n.y > -0.7:
			return {}
		pos = p - Vector3(0, s.y, 0)
		var to_player: Vector3 = main.player.global_position - p
		rot_y = (rad_to_deg(atan2(to_player.x, to_player.z)) if base_rot == null else float(base_rot)) + _rot
		if snap:
			pos.x = snappedf(pos.x, 0.25)
			pos.z = snappedf(pos.z, 0.25)
			rot_y = snappedf(rot_y, 15.0)
	elif n.y > 0.7 and mount != "wall":
		pos = p
		if base_rot == null:
			var to_player: Vector3 = main.player.global_position - p
			rot_y = rad_to_deg(atan2(to_player.x, to_player.z)) + _rot
		else:
			rot_y = base_rot + _rot
		if snap:
			if d.get("edge_snap", false):
				var es := _edge_snap(type, scl, p, exclude_id)
				if not es.is_empty() and absf(p.y - es.pos.y) < 0.3:
					return es
				rot_y = snappedf(rot_y, 45.0)
			else:
				rot_y = snappedf(rot_y, 15.0)
			pos.x = snappedf(pos.x, 0.25)
			pos.z = snappedf(pos.z, 0.25)
	elif absf(n.y) < 0.3:
		var nn := Vector3(n.x, 0, n.z).normalized()
		rot_y = rad_to_deg(atan2(nn.x, nn.z))
		if mount == "floor":
			pos = Vector3(p.x, 0.0, p.z) + nn * (s.z / 2.0 + 0.005)
			rot_y += _rot
		else:
			pos = p + nn * (s.z / 2.0) - Vector3(0, s.y / 2.0, 0)
		if snap:
			var tan := Vector3(nn.z, 0, -nn.x)
			var t := pos.dot(tan)
			pos += tan * (snappedf(t, 0.25) - t)
			if mount != "floor":
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
			_target = _compute(o.type, World.vec(o.scale), World.vec(o.rot).y, selected)
			if not _target.is_empty():
				node.position = _target.pos
				node.rotation_degrees = _target.rot
				var b := _is_blocked(o.type, _target.pos, _target.rot, World.vec(o.scale), [node.body.get_rid()] if node.body else [])
				if b != blocked or not _grab_tinted:
					blocked = b
					_grab_tinted = true
					_set_tint(node, b)
					_update_hud()
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
			var b := _is_blocked(placing, _target.pos, _target.rot, Vector3.ONE)
			if b != blocked:
				blocked = b
				_set_tint(_ghost, b)
				_update_hud()


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
		if pk >= KEY_0 and pk <= KEY_9 and not event.ctrl_pressed:
			var idx := (pk - KEY_1) if pk != KEY_0 else 9
			current_slot = idx
			var t := KWHotbar.type_at(idx)
			if t != "":
				_start_placing(t)
			else:
				main.hud.toast("Slot %s vide : I pour ouvrir l'inventaire." % KWHotbar.key_label(idx))
			get_viewport().set_input_as_handled()
			return
		var handled := true
		match event.keycode:
			KEY_I, KEY_TAB:
				open_inventory()
				get_viewport().set_input_as_handled()
				return
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
			KEY_PAGEUP, KEY_KP_ADD: _scale(1.1, event.shift_pressed)
			KEY_PAGEDOWN, KEY_KP_SUBTRACT: _scale(1.0 / 1.1, event.shift_pressed)
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
		if blocked and not Input.is_key_pressed(KEY_SHIFT):
			main.hud.toast("Emplacement occupé (Maj+clic pour forcer).")
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
	if blocked and not Input.is_key_pressed(KEY_SHIFT) and not _target.is_empty():
		main.hud.toast("Emplacement occupé (Maj+clic pour forcer).")
		return
	grabbing = false
	blocked = false
	_grab_tinted = false
	main.player.ray.clear_exceptions()
	if not _target.is_empty() and World.data.objects.has(selected):
		var o: Dictionary = World.data.objects[selected]
		World.set_transform(selected, _target.pos, _target.rot, World.vec(o.scale))
	elif main.nodes.has(selected):
		main.nodes[selected].refresh()
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


## Taille : uniforme, ou largeur seule (Maj, et par défaut pour les murs / estrades).
func _scale(f: float, width_only := false) -> void:
	if selected == "" or not World.data.objects.has(selected):
		return
	var o: Dictionary = World.data.objects[selected]
	var s := World.vec(o.scale)
	if bool(ObjectRegistry.get_def(o.type).get("width_resize", false)) != width_only:
		s.x *= f
	else:
		s *= f
	World.update_object(selected, {"scale": s.clamp(Vector3.ONE * 0.2, Vector3.ONE * 5.0)})
