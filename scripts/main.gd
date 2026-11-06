extends Node3D
## MAIN — orchestration : environnement, joueur, salle courante, interactions,
## panneaux, transitions. Ne contient aucune donnée : tout vient de World.

var player: KWPlayer
var hud: KWHud
var ui_root: Control
var build: BuildMode
var fade: ColorRect
var room_root: Node3D
var room_geo: Node3D
var env: Environment
var dim: ColorRect
var relation_lines: MeshInstance3D
var portals: PortalSystem
var nodes := {} # obj_id -> KWObject
var current_room := ""
var panel: KWPanel = null
var _travelling := false


func _ready() -> void:
	_setup_input()
	_setup_environment()
	KWSettings.load_settings()
	player = KWPlayer.new()
	add_child(player)
	var layer := CanvasLayer.new()
	add_child(layer)
	ui_root = Control.new()
	ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.theme = KWTheme.make()
	layer.add_child(ui_root)
	hud = KWHud.new()
	ui_root.add_child(hud)
	dim = ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 0.0)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(dim)
	apply_settings()
	fade = ColorRect.new()
	fade.color = Color(0.02, 0.02, 0.03, 1.0)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(fade)
	build = BuildMode.new()
	build.main = self
	add_child(build)
	portals = PortalSystem.new()
	portals.main = self
	add_child(portals)
	relation_lines = MeshInstance3D.new()
	add_child(relation_lines)
	World.changed.connect(_on_world_changed)
	get_window().files_dropped.connect(import_files)
	enter_room(World.data.hub)
	create_tween().tween_property(fade, "color:a", 0.0, 1.0)
	_capture(true)
	var args := OS.get_cmdline_user_args()
	if "--kw-test" in args:
		SelfTest.run.call_deferred(self)
	for a in args:
		if a.begins_with("--kw-shot="):
			SelfTest.shot.call_deferred(self, a.substr(10))


func _setup_input() -> void:
	var keys := {"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN], "move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT], "sprint": [KEY_SHIFT]}
	for a in keys:
		if not InputMap.has_action(a):
			InputMap.add_action(a)
		for k in keys[a]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k # position physique : ZQSD en AZERTY, WASD en QWERTY
			InputMap.action_add_event(a, ev)


func _setup_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.05, 0.06)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.78, 0.75, 0.7)
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.04
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssil_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


# ------------------------------------------------------------------ salles

func go_to_room(room_id: String, from_room := "", focus_obj := "") -> void:
	if _travelling or not World.data.rooms.has(room_id):
		return
	_travelling = true
	close_panel()
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 1.0, 0.35)
	await tw.finished
	enter_room(room_id, from_room, focus_obj)
	create_tween().tween_property(fade, "color:a", 0.0, 0.5)
	_travelling = false


func go_to_object(obj_id: String) -> void:
	if World.data.objects.has(obj_id):
		go_to_room(World.data.objects[obj_id].room_id, "", obj_id)


func enter_room(room_id: String, from_room := "", focus_obj := "") -> void:
	build.cancel()
	build.deselect()
	if room_root:
		room_root.free()
	room_geo = null
	nodes.clear()
	current_room = room_id
	var room: Dictionary = World.data.rooms[room_id]
	room_root = Node3D.new()
	add_child(room_root)
	_build_room_geometry()
	for o in World.objects_in_room(room_id):
		_spawn(o.id)
	var spawn := Vector3(0, 0.05, room.size[2] / 2.0 - 2.0)
	var yaw := 0.0
	var anchor := {}
	if focus_obj != "":
		anchor = World.data.objects.get(focus_obj, {})
	elif from_room != "":
		for o in World.objects_in_room(room_id):
			if o.type in ["door", "portal"] and o.params.get("target_room", "") == from_room:
				anchor = o
				break
	if not anchor.is_empty():
		var fwd := Basis.from_euler(World.vec(anchor.rot) * PI / 180.0) * Vector3.BACK
		spawn = World.vec(anchor.pos) + fwd * 1.8
		spawn.y = 0.05
		# Depuis une porte : on regarde vers l'intérieur. Vers un objet : on le regarde.
		yaw = atan2(-fwd.x, -fwd.z) if focus_obj == "" else atan2(fwd.x, fwd.z)
	player.teleport(spawn, yaw)
	World.visit_room(room_id)
	var pid: String = room.portal_id
	hud.show_room_title(room.name, ("Portail · " + World.data.portals[pid].name) if World.data.portals.has(pid) else "Espace central")
	_draw_relations()
	portals.refresh()


## (Re)construit murs/sol/plafond/lumières de la salle courante sans toucher aux objets.
func _build_room_geometry() -> void:
	if room_geo:
		room_geo.free()
	var room: Dictionary = World.data.rooms[current_room]
	room_geo = RoomBuilder.build(room, current_room == World.data.hub)
	room_root.add_child(room_geo)
	room_root.move_child(room_geo, 0)
	var st := RoomBuilder.style_of(room)
	env.ambient_light_color = Color(0.78, 0.75, 0.7).lerp(RoomBuilder.light_color(st), 0.6)
	env.ambient_light_energy = 0.45 * clampf(RoomBuilder.light_energy(st) / 0.8, 0.35, 1.8)
	keep_player_inside()


## Garde le joueur dans la salle (après redimensionnement, murs reconstruits…).
func keep_player_inside() -> void:
	if player == null or current_room == "":
		return
	var s: Array = World.data.rooms[current_room].size
	var m := 0.5
	var p := player.global_position
	var hx := float(s[0]) / 2.0 - m
	var hz := float(s[2]) / 2.0 - m
	var q := Vector3(clampf(p.x, -hx, hx), maxf(p.y, 0.05), clampf(p.z, -hz, hz))
	if q.y > float(s[1]) - 1.0:
		q.y = 0.05
	if not q.is_equal_approx(p):
		player.global_position = q
		player.velocity = Vector3.ZERO


## Applique les paramètres globaux (joueur, taille de l'UI).
func apply_settings() -> void:
	player.apply_settings()
	var sc := float(KWSettings.get_value("ui_scale"))
	if DisplayServer.get_name() != "headless":
		get_window().content_scale_factor = sc


func _spawn(id: String) -> void:
	var n := KWObject.new()
	room_root.add_child(n)
	nodes[id] = n.setup(id)


func _on_world_changed(kind: String, id: String, action: String) -> void:
	match kind:
		"object":
			var o = World.data.objects.get(id)
			if action == "deleted" or o == null or o.room_id != current_room:
				if nodes.has(id):
					nodes[id].queue_free()
					nodes.erase(id)
				if build.selected == id:
					build.deselect()
			elif nodes.has(id):
				if not (build.grabbing and build.selected == id):
					nodes[id].refresh()
			else:
				_spawn(id)
			if o == null or o.type in ["door", "portal"] or o.room_id != current_room:
				portals.request_refresh()
		"document":
			_refresh_types(["library"])
		"room":
			if action == "deleted" and id == current_room:
				enter_room(World.data.hub)
			else:
				if id == current_room and action == "updated":
					_build_room_geometry()
				_refresh_types(["door", "portal"])
				portals.request_refresh()
	if kind in ["relation", "object"]:
		_draw_relations()


## L'IA de la pièce : l'orbe de la salle s'il y en a une, sinon l'assistant global.
func room_ai() -> String:
	for o in World.objects_in_room(current_room):
		if o.type == "orb":
			return o.id
	return assistant_desk()


## Bureau « virtuel » de l'assistant global (Entrée) : un objet sans salle, jamais affiché.
func assistant_desk() -> String:
	var id: String = World.data.get("assistant_desk", "")
	if not World.data.objects.has(id):
		id = World.create_object("desk", "", Vector3.ZERO, Vector3.ZERO, Vector3.ONE, "Assistant")
		World.data["assistant_desk"] = id
	return id


func _refresh_types(types: Array) -> void:
	for id in nodes:
		if World.data.objects.has(id) and World.data.objects[id].type in types:
			nodes[id].refresh()


## Fils lumineux discrets entre objets reliés présents dans la salle.
func _draw_relations() -> void:
	var im := ImmediateMesh.new()
	var any := false
	for r in World.data.relations.values():
		if r.from.kind == "object" and r.to.kind == "object" and nodes.has(r.from.id) and nodes.has(r.to.id):
			if not any:
				im.surface_begin(Mesh.PRIMITIVE_LINES)
				any = true
			im.surface_add_vertex(nodes[r.from.id].position + Vector3(0, 0.2, 0))
			im.surface_add_vertex(nodes[r.to.id].position + Vector3(0, 0.2, 0))
	if any:
		im.surface_end()
	relation_lines.mesh = im
	var m := ObjectRegistry.mat(Color(0.6, 0.8, 1.0), 2.0)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	relation_lines.material_override = m

# ------------------------------------------------------------------ interaction

func aimed_object_id() -> String:
	var col = player.ray.get_collider()
	if col != null and col.has_meta("kw_id"):
		return col.get_meta("kw_id")
	return ""


func interact(id: String) -> void:
	var o: Dictionary = World.data.objects[id]
	match ObjectRegistry.get_def(o.type).panel:
		"note": open_panel(NotePanel.new(id))
		"whiteboard": open_panel(WhiteboardPanel.new(id))
		"kanban": open_panel(KanbanPanel.new(id))
		"chat": open_panel(ChatPanel.new(id))
		"poster": open_panel(PosterPanel.new(id))
		"library": open_panel(LibraryPanel.new(id))
		"travel":
			var t: String = o.params.get("target_room", "")
			if t != "" and World.data.rooms.has(t) and not build.active:
				go_to_room(t, current_room)
			else:
				open_panel(DoorPanel.new(id))
		_:
			open_relations("object", id)


func open_panel(p: KWPanel) -> void:
	close_panel()
	panel = p
	p.closed.connect(close_panel)
	ui_root.add_child(p)
	player.enabled = false
	hud.help.visible = false
	_capture(false)
	_fade_dim(0.45)


func close_panel() -> void:
	if panel == null:
		return
	var p := panel
	panel = null
	p.on_close()
	p.queue_free()
	player.enabled = true
	_capture(true)
	_fade_dim(0.0)


var _dim_tw: Tween


func _fade_dim(a: float) -> void:
	if _dim_tw:
		_dim_tw.kill()
	_dim_tw = create_tween()
	_dim_tw.tween_property(dim, "color:a", a, 0.18)


func open_relations(kind: String, id: String) -> void:
	open_panel(RelationPanel.new(kind, id))


func import_files(paths: PackedStringArray) -> void:
	var n := 0
	var docs := PackedStringArray()
	for p in paths:
		if p.get_extension().to_lower() in ["png", "jpg", "jpeg", "webp"]:
			poster_from_file(p)
		else:
			docs.append(p)
	if docs.is_empty():
		return
	for p in docs:
		if World.import_document(p, current_room) != "":
			n += 1
	hud.toast("%d document(s) importé(s) dans « %s »." % [n, World.data.rooms[current_room].name] if n > 0 else "Format non pris en charge (texte ou PDF).")
	if panel is LibraryPanel:
		panel.refresh()


## Pose devant soi : sur le mur visé, sinon face au joueur.
func _front_placement(size: Vector3) -> Array:
	var f := -player.global_transform.basis.z
	f.y = 0
	var pos := player.global_position + f.normalized() * 1.2 + Vector3(0, 1.1, 0)
	var ray := player.ray
	ray.force_raycast_update()
	var rot := Vector3(0, rad_to_deg(atan2(-f.x, -f.z)), 0)
	if ray.is_colliding() and absf(ray.get_collision_normal().y) < 0.3:
		var n := ray.get_collision_normal()
		pos = ray.get_collision_point() + n * (size.z / 2.0 + 0.001) - Vector3(0, size.y / 2.0, 0)
		rot = Vector3(0, rad_to_deg(atan2(n.x, n.z)), 0)
	return [pos, rot]


func quick_note() -> void:
	var pr := _front_placement(ObjectRegistry.get_def("note").size)
	var id := World.create_object("note", current_room, pr[0], pr[1], Vector3.ONE, "Note rapide")
	open_panel(NotePanel.new(id))


## Glisser-déposer une image : poster accroché devant soi.
func poster_from_file(path: String) -> void:
	var pr := _front_placement(ObjectRegistry.get_def("poster").size)
	var id := World.create_object("poster", current_room, pr[0], pr[1], Vector3.ONE, path.get_file().get_basename())
	var pp := PosterPanel.new(id)
	open_panel(pp)
	pp.set_image(path)


func _capture(on: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if panel != null:
			close_panel()
		elif hud.help.visible:
			hud.help.visible = false
		elif build.placing != "" or build.grabbing:
			build.cancel()
		else:
			open_panel(PauseMenu.new())
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if panel != null:
		return
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_capture(true)
		get_viewport().set_input_as_handled()
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_E:
			var id := aimed_object_id()
			if id != "":
				interact(id)
		KEY_ENTER, KEY_KP_ENTER: open_panel(ChatPanel.new(room_ai()))
		KEY_B: build.toggle()
		KEY_TAB: open_panel(MapPanel.new())
		KEY_H: go_to_room(World.data.hub, current_room)
		KEY_N: quick_note()
		KEY_L: open_panel(LibraryPanel.new())
		KEY_G:
			if not build.active:
				open_panel(GraphPanel.new())
		KEY_F:
			var id := aimed_object_id()
			open_relations("object" if id != "" else "room", id if id != "" else current_room)
		KEY_F1: hud.help.visible = not hud.help.visible
		KEY_P: open_panel(RoomPanel.new(current_room))
		KEY_T:
			var id := aimed_object_id()
			if id != "":
				open_panel(ObjectStylePanel.new(id))
		KEY_S:
			if event.ctrl_pressed:
				World.save_world()
				hud.toast("Monde sauvegardé.")


func _physics_process(_delta: float) -> void:
	# Filet de sécurité : chute sous le sol ou sortie de la salle → retour à l'intérieur.
	if player == null or current_room == "" or _travelling:
		return
	var s: Array = World.data.rooms[current_room].size
	var p := player.global_position
	if p.y < -2.0 or absf(p.x) > float(s[0]) / 2.0 + 1.0 or absf(p.z) > float(s[2]) / 2.0 + 1.0:
		player.teleport(Vector3(0, 0.05, float(s[2]) / 2.0 - 2.0), 0.0)
		hud.toast("Vous avez été ramené dans la salle.")


func _process(_delta: float) -> void:
	if panel != null or _travelling:
		hud.set_hint("")
		return
	var id := aimed_object_id()
	if id == "" or not World.data.objects.has(id):
		hud.set_hint("")
		return
	var o: Dictionary = World.data.objects[id]
	var verb := "ouvrir"
	if o.type in ["door", "portal"]:
		var t: String = o.params.get("target_room", "")
		verb = "aller vers « %s »" % World.data.rooms[t].name if World.data.rooms.has(t) else "configurer"
	elif ObjectRegistry.get_def(o.type).panel == "":
		verb = "relations"
	hud.set_hint("E : %s — %s" % [verb, World.label_of("object", id)])
