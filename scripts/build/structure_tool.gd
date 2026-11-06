class_name StructureTool
extends Node3D
## Outil de tracé des structures (mode construction) :
##  - Mur : clic au point A, clic au point B (grille 0,5 m, angles recouverts).
##  - Sol / plancher : clic sur un coin, clic sur le coin opposé.
##  - Escalier : un clic (R pour pivoter) ; monte d'un étage (3 m).
## PgUp/PgDn : étage · M : matériau suivant · clic droit / Échap : quitter l'outil.
## Le tracé vise un plan horizontal à la hauteur de l'étage : jamais refusé.

const WALL_T := 0.15

var build: Node
var active := false
var type := ""
var level := 0
var mat_id := "enduit"
var _a = null # point A (Vector3) ou null
var _rot := 0.0
var _ghost: MeshInstance3D
var _grid: MeshInstance3D
var _label: Label
var _target = null


func _ready() -> void:
	_ghost = MeshInstance3D.new()
	_ghost.mesh = BoxMesh.new()
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.55, 0.8, 1.0, 0.35)
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost.material_override = gm
	_ghost.visible = false
	add_child(_ghost)
	_grid = MeshInstance3D.new()
	var lm := StandardMaterial3D.new()
	lm.albedo_color = Color(0.7, 0.85, 1.0, 0.35)
	lm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_grid.material_override = lm
	_grid.visible = false
	add_child(_grid)


func _main() -> Node:
	return build.main


func start(t: String) -> void:
	active = true
	type = t
	_a = null
	_rot = 0.0
	if t == "struct_floor" or t == "stairs":
		if mat_id == "enduit":
			mat_id = "bois"
	if _label == null:
		_label = Label.new()
		_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_label.offset_top = 130
		_label.offset_left = -420
		_label.offset_right = 420
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
		_main().hud.add_child(_label)
	_label.visible = true
	_update_label()


func stop() -> void:
	active = false
	_a = null
	_ghost.visible = false
	_grid.visible = false
	if _label:
		_label.visible = false


func _update_label() -> void:
	var what: String = ObjectRegistry.get_def(type).label
	var step := "clic : poser" if type == "stairs" else ("clic : point B" if _a != null else "clic : point A")
	_label.text = "%s · %s · Étage %d   —   %s · PgUp/PgDn étage · M matériau%s · clic droit : quitter" % [
		what, StructureKit.MATERIALS[mat_id].label, level, step, " · R pivoter" if type == "stairs" else ""]


## Point visé sur le plan de l'étage, aligné sur la grille.
func _aim() -> Variant:
	var cam: Camera3D = _main().player.cam
	var o := cam.global_position
	var d := -cam.global_basis.z
	var y := level * StructureKit.LEVEL_H
	if absf(d.y) < 0.02:
		return null
	var t := (y - o.y) / d.y
	if t < 0.3 or t > 30.0:
		return null
	var p := o + d * t
	return Vector3(snappedf(p.x, StructureKit.GRID), y, snappedf(p.z, StructureKit.GRID))


func _process(_delta: float) -> void:
	if not active:
		return
	_target = _aim()
	_ghost.visible = _target != null
	_grid.visible = _target != null
	if _target == null:
		return
	_draw_grid(_target)
	var spec := _spec(_target)
	if spec.is_empty():
		(_ghost.mesh as BoxMesh).size = Vector3(0.12, 0.12, 0.12)
		_ghost.global_position = _target + Vector3(0, 0.06, 0)
		_ghost.rotation = Vector3.ZERO
		return
	var sz: Vector3 = ObjectRegistry.get_def(type).size * spec.scale
	(_ghost.mesh as BoxMesh).size = sz
	_ghost.global_position = spec.pos + Basis.from_euler(spec.rot * PI / 180.0) * Vector3(0, sz.y / 2.0, 0)
	_ghost.rotation_degrees = spec.rot


## Pose de la pièce entre A (s'il existe) et le point visé.
func _spec(p: Vector3) -> Dictionary:
	match type:
		"struct_wall":
			if _a == null:
				return {}
			var a: Vector3 = _a
			var d := p - a
			d.y = 0
			var length := d.length()
			if length < 0.25:
				return {}
			var rot_y := rad_to_deg(atan2(-d.z, d.x))
			return {"pos": (a + p) / 2.0, "rot": Vector3(0, rot_y, 0), "scale": Vector3(length + WALL_T, 1, 1)}
		"struct_floor":
			if _a == null:
				return {}
			var a: Vector3 = _a
			var sx := maxf(absf(p.x - a.x), StructureKit.GRID)
			var sz := maxf(absf(p.z - a.z), StructureKit.GRID)
			var fy: float = -0.19
			if level > 0:
				fy = p.y - 0.2
			return {"pos": Vector3((a.x + p.x) / 2.0, fy, (a.z + p.z) / 2.0), "rot": Vector3.ZERO, "scale": Vector3(sx, 1, sz)}
		"stairs":
			var f: Vector3 = -_main().player.global_basis.z
			var yaw := snappedf(rad_to_deg(atan2(-f.x, -f.z)), 90.0) + _rot
			return {"pos": p, "rot": Vector3(0, yaw, 0), "scale": Vector3.ONE}
	return {}


func _draw_grid(c: Vector3) -> void:
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var r := 3.0
	var g := StructureKit.GRID
	var k := -r
	while k <= r + 0.001:
		im.surface_add_vertex(c + Vector3(k, 0.012, -r))
		im.surface_add_vertex(c + Vector3(k, 0.012, r))
		im.surface_add_vertex(c + Vector3(-r, 0.012, k))
		im.surface_add_vertex(c + Vector3(r, 0.012, k))
		k += g
	if _a != null:
		var a: Vector3 = _a
		im.surface_add_vertex(a + Vector3(0, 0.02, 0))
		im.surface_add_vertex(a + Vector3(0, 1.0, 0))
	im.surface_end()
	_grid.mesh = im
	_grid.global_position = Vector3.ZERO


func _input(event: InputEvent) -> void:
	if active and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and _main().panel == null:
		stop()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not active or _main().panel != null or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_click()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if _a != null:
				_a = null
			else:
				stop()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_PAGEUP: level = mini(level + 1, _max_level())
			KEY_PAGEDOWN: level = maxi(level - 1, 0)
			KEY_M: mat_id = StructureKit.MAT_ORDER[(StructureKit.MAT_ORDER.find(mat_id) + 1) % StructureKit.MAT_ORDER.size()]
			KEY_R: _rot += 90.0
			_: return
		_update_label()
		get_viewport().set_input_as_handled()


func _max_level() -> int:
	var h: float = World.data.rooms[_main().current_room].size[1]
	return maxi(0, int(floor(h / StructureKit.LEVEL_H)) - 1)


func _click() -> void:
	if _target == null:
		return
	if type != "stairs" and _a == null:
		_a = _target
		_update_label()
		return
	var spec := _spec(_target)
	if spec.is_empty():
		return
	place(type, spec.pos, spec.rot, spec.scale)
	# Murs : enchaînement (B devient le nouveau A). Sols : on recommence.
	_a = _target if type == "struct_wall" else null
	_update_label()


func place(t: String, pos: Vector3, rot: Vector3, scl: Vector3) -> String:
	return World.create_object(t, _main().current_room, pos, rot, scl, "", {}, {"style": {"material": mat_id}})
