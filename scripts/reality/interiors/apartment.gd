class_name ApartmentInterior
extends Node3D
## Appartement généré par motif depuis data/city/apartment_layouts.json (plan + meubles du
## registre d'objets), variantes selon la graine (id du bot). Origine locale = seuil de la
## porte d'entrée ; +Z = vers l'intérieur.

const PATH := "res://data/city/apartment_layouts.json"
const DOOR_W := 1.2
const DOOR_H := 2.3
const SKY_SHADER := """
shader_type spatial;
render_mode unshaded;
uniform float seed = 0.0;
float h(float x) { return fract(sin(x * 12.9898 + seed) * 43758.5453); }
void fragment() {
	vec3 sky = mix(vec3(0.75, 0.84, 0.95), vec3(0.4, 0.6, 0.9), 1.0 - UV.y);
	float col = floor(UV.x * 9.0);
	float top = 0.15 + 0.4 * h(col);
	float far = 0.1 + 0.3 * h(col + 40.0);
	vec3 c = sky;
	if ((1.0 - UV.y) < far) { c = vec3(0.55, 0.62, 0.72); }
	if ((1.0 - UV.y) < top) { c = vec3(0.32, 0.36, 0.42); vec2 w = fract(UV * vec2(9.0, 22.0)); if (w.x > 0.3 && w.x < 0.7 && w.y > 0.3 && w.y < 0.7 && h(col + floor(UV.y * 22.0) * 3.0) > 0.5) { c = vec3(1.0, 0.9, 0.6); } }
	ALBEDO = c;
}
"""

var data: Dictionary = {}
var layout_id := ""
var occupant := ""
var room_count := 0
var furniture_count := 0
var window_count := 0
var _body: StaticBody3D
var _rng := RandomNumberGenerator.new()
var _wall_mat: StandardMaterial3D
var _sky_shader: Shader
var _yoff := 0.0
var floor_count := 0
var apartment_id := ""
var _mats := {}


static func load_data() -> Dictionary:
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return {}
	var j = JSON.parse_string(f.get_as_text())
	return j if j is Dictionary else {}


func generate(seed_str: String, bot_color := Color(0.7, 0.5, 0.4), present := false) -> void:
	for c in get_children():
		c.queue_free()
		remove_child(c)
	room_count = 0
	furniture_count = 0
	window_count = 0
	occupant = seed_str
	_yoff = 0.0
	if data.is_empty():
		data = load_data()
	_rng.seed = absi(seed_str.hash()) + 1
	var layouts: Array = data.get("layouts", [])
	var lay: Dictionary = layouts[_rng.randi() % layouts.size()]
	layout_id = str(lay.get("id", "?"))
	var pal: Array = data.get("palette", ["#dddddd"])
	var acc: Array = data.get("accent", ["#886644"])
	_wall_mat = ObjectRegistry.mat(Color(str(pal[_rng.randi() % pal.size()])), 0.0, 0.9)
	var accent := Color(str(acc[_rng.randi() % acc.size()]))
	_sky_shader = Shader.new()
	_sky_shader.code = SKY_SHADER
	_body = StaticBody3D.new()
	_body.collision_layer = 1
	add_child(_body)
	var rooms: Array = lay.rooms
	var rects: Array = []
	for r in rooms:
		var a: Array = r.rect
		rects.append(Rect2(float(a[0]), float(a[1]), float(a[2]), float(a[3])))
	var hgt: float = float(data.get("height", 2.6))
	for i in rooms.size():
		_room(i, rooms, rects, hgt, accent)
	# palier derrière la porte
	_box(Vector3(2.4, 0.2, 1.6), Vector3(0, -0.1, -0.8), ObjectRegistry.mat(Color(0.35, 0.33, 0.3)), true)
	if present:
		_add_occupant(rects[1] if rects.size() > 1 else rects[0], bot_color)


func door_xf() -> Transform3D:
	return global_transform


func _room(i: int, rooms: Array, rects: Array, hgt: float, accent: Color) -> void:
	var r: Rect2 = rects[i]
	var kind: String = str(rooms[i].kind)
	room_count += 1
	var fcol := {"entry": Color(0.45, 0.4, 0.36), "living": Color(0.55, 0.4, 0.26), "kitchen": Color(0.7, 0.7, 0.68), "bedroom": Color(0.5, 0.42, 0.34)}.get(kind, Color(0.5, 0.45, 0.4)) as Color
	var c3 := Vector3(r.position.x + r.size.x * 0.5, 0, r.position.y + r.size.y * 0.5)
	_box(Vector3(r.size.x, 0.2, r.size.y), c3 + Vector3(0, -0.1, 0), ObjectRegistry.mat(fcol, 0.0, 0.7), true)
	_box(Vector3(r.size.x, 0.2, r.size.y), c3 + Vector3(0, hgt + 0.1, 0), ObjectRegistry.mat(Color(0.93, 0.93, 0.9)), true)
	var lamp := OmniLight3D.new()
	lamp.position = c3 + Vector3(0, hgt - 0.4, 0)
	lamp.omni_range = maxf(r.size.x, r.size.y) * 1.3
	lamp.light_energy = 1.4
	lamp.light_color = Color(1.0, 0.92, 0.8)
	add_child(lamp)
	# murs : n (z=pos.y), s, w, e
	for e in 4:
		var horiz: bool = e < 2
		var fixed: float = [r.position.y, r.end.y, r.position.x, r.end.x][e]
		var lo: float = r.position.x if horiz else r.position.y
		var hi: float = r.end.x if horiz else r.end.y
		var ivs: Array = []
		var shared: Array = []
		for j in rects.size():
			if j == i:
				continue
			var o: Rect2 = rects[j]
			var touch := false
			var a0 := 0.0
			var a1 := 0.0
			match e:
				0: touch = is_equal_approx(o.end.y, fixed); a0 = o.position.x; a1 = o.end.x
				1: touch = is_equal_approx(o.position.y, fixed); a0 = o.position.x; a1 = o.end.x
				2: touch = is_equal_approx(o.end.x, fixed); a0 = o.position.y; a1 = o.end.y
				_: touch = is_equal_approx(o.position.x, fixed); a0 = o.position.y; a1 = o.end.y
			a0 = maxf(a0, lo)
			a1 = minf(a1, hi)
			if touch and a1 - a0 > 0.5:
				ivs.append([a0, a1, j])
		ivs.sort_custom(func(a, b): return a[0] < b[0])
		var cur := lo
		for iv in ivs:
			if iv[0] > cur + 0.01:
				_ext_wall(horiz, fixed, cur, iv[0], e, kind == "entry" and e == 0 and i == 0, hgt)
			var dw: bool = int(iv[2]) > i
			if dw:
				_wall(horiz, fixed, iv[0], iv[1], (iv[0] + iv[1]) * 0.5, 1.0, 0.0, 2.1, hgt)
			else:
				pass
			cur = maxf(cur, iv[1])
		if hi > cur + 0.01:
			_ext_wall(horiz, fixed, cur, hi, e, kind == "entry" and e == 0 and i == 0, hgt)
	_furnish(kind, r, accent)


func _ext_wall(horiz: bool, fixed: float, lo: float, hi: float, e: int, is_door: bool, hgt: float) -> void:
	if is_door:
		_wall(horiz, fixed, lo, hi, 0.0, DOOR_W, 0.0, DOOR_H, hgt)
	elif hi - lo >= 2.4:
		var mid := (lo + hi) * 0.5
		_wall(horiz, fixed, lo, hi, mid, 1.5, 0.9, 2.1, hgt)
		_glass(horiz, fixed, mid, e)
	else:
		_wall(horiz, fixed, lo, hi, 0.0, 0.0, 0.0, 0.0, hgt)


## Mur plein de lo à hi ; ouverture (gap_w > 0) entre gap_bot et gap_top.
func _wall(horiz: bool, fixed: float, lo: float, hi: float, gc: float, gw: float, gb: float, gt: float, hgt: float) -> void:
	var th := 0.2
	var segs: Array = []
	if gw <= 0.0:
		segs.append([lo, hi, 0.0, hgt])
	else:
		segs.append([lo, gc - gw * 0.5, 0.0, hgt])
		segs.append([gc + gw * 0.5, hi, 0.0, hgt])
		if gb > 0.0:
			segs.append([gc - gw * 0.5, gc + gw * 0.5, 0.0, gb])
		segs.append([gc - gw * 0.5, gc + gw * 0.5, gt, hgt])
	for s in segs:
		var len: float = s[1] - s[0]
		if len < 0.02 or s[3] - s[2] < 0.02:
			continue
		var mid: float = (s[0] + s[1]) * 0.5
		var size := Vector3(len, s[3] - s[2], th) if horiz else Vector3(th, s[3] - s[2], len)
		var pos := Vector3(mid, (s[2] + s[3]) * 0.5, fixed) if horiz else Vector3(fixed, (s[2] + s[3]) * 0.5, mid)
		_box(size, pos, _wall_mat, true)


func _glass(horiz: bool, fixed: float, mid: float, e: int) -> void:
	window_count += 1
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(1.5, 1.2)
	q.mesh = qm
	var m := ShaderMaterial.new()
	m.shader = _sky_shader
	m.set_shader_parameter("seed", float(window_count) * 7.3 + float(_rng.randi() % 50))
	q.material_override = m
	var yaw: float = [0.0, PI, PI * 0.5, -PI * 0.5][e]
	q.rotation.y = yaw
	q.position = Vector3(mid, 1.5, fixed) if horiz else Vector3(fixed, 1.5, mid)
	add_child(q)


func _box(size: Vector3, pos: Vector3, mat: Material, collide: bool) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	if collide:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		cs.position = pos
		_body.add_child(cs)


func _furnish(kind: String, r: Rect2, accent: Color) -> void:
	var sets: Array = data.get("furniture", {}).get(kind, [])
	if sets.is_empty():
		return
	var set: Array = sets[_rng.randi() % sets.size()]
	var mirror := _rng.randf() < 0.5
	for it in set:
		if _rng.randf() > float(it.get("opt", 1.0)):
			continue
		var at: Array = it.at
		var fx: float = 1.0 - float(at[0]) if mirror else float(at[0])
		var rot: float = float(it.get("rot", 0.0))
		if mirror and absf(rot) == 90.0:
			rot = -rot
		var pos := Vector3(r.position.x + fx * r.size.x, _yoff, r.position.y + float(at[1]) * r.size.y)
		var t: String = str(it.type)
		var n: Node3D
		if t == "bed":
			n = _bed(accent)
		else:
			n = ObjectRegistry.build({"type": t, "name": t, "content": {}, "params": {"style": {"primary": "#" + accent.to_html(false)} if t in ["sofa", "armchair"] else {}}})
		n.position = pos
		n.rotation_degrees.y = rot
		add_child(n)
		furniture_count += 1


func _bed(accent: Color) -> Node3D:
	var root := Node3D.new()
	ObjectRegistry.box(root, Vector3(1.5, 0.35, 2.0), Vector3(0, 0.25, 0), ObjectRegistry.mat(Color(0.4, 0.3, 0.22)))
	ObjectRegistry.box(root, Vector3(1.4, 0.2, 1.9), Vector3(0, 0.52, 0), ObjectRegistry.mat(accent.lightened(0.5)))
	ObjectRegistry.box(root, Vector3(1.5, 0.9, 0.1), Vector3(0, 0.55, -1.0), ObjectRegistry.mat(Color(0.4, 0.3, 0.22)))
	ObjectRegistry.box(root, Vector3(0.5, 0.12, 0.3), Vector3(-0.35, 0.68, -0.75), ObjectRegistry.mat(Color(0.95, 0.95, 0.92)))
	ObjectRegistry.box(root, Vector3(0.5, 0.12, 0.3), Vector3(0.35, 0.68, -0.75), ObjectRegistry.mat(Color(0.95, 0.95, 0.92)))
	return root


func _add_occupant(r: Rect2, col: Color) -> void:
	var b := Node3D.new()
	b.name = "Occupant"
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.3
	cap.height = 1.4
	body.mesh = cap
	body.material_override = ObjectRegistry.mat(col)
	body.position.y = 0.7
	b.add_child(body)
	var head := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.2
	sph.height = 0.4
	head.mesh = sph
	head.material_override = ObjectRegistry.mat(col.lightened(0.3))
	head.position.y = 1.6
	b.add_child(head)
	var l := Label3D.new()
	l.text = occupant
	l.position.y = 2.0
	l.pixel_size = 0.006
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	b.add_child(l)
	b.position = Vector3(r.position.x + r.size.x * 0.5 + 0.8, _yoff, r.position.y + r.size.y * 0.3)
	add_child(b)


# --- Génération depuis le plan de l'immeuble (même source que la façade) ---

func _cmat(c: Color) -> StandardMaterial3D:
	var k := c.to_html()
	if not _mats.has(k):
		_mats[k] = ObjectRegistry.mat(c, 0.0, 0.9)
	return _mats[k]


## Hall, cage d'escalier praticable, couloirs de tous les étages ; l'appartement `apt_id` est entièrement
## aménagé, les autres sont des volumes fermés (porte seule). Origine locale = seuil de l'entrée, +Z vers l'intérieur.
func generate_building(plan: Dictionary, apt_id: String, bot_color := Color(0.7, 0.5, 0.4), present := false, who := "") -> void:
	for c in get_children():
		c.queue_free()
		remove_child(c)
	room_count = 0
	furniture_count = 0
	window_count = 0
	floor_count = int(plan["floors"])
	occupant = who
	apartment_id = apt_id
	layout_id = str(plan["pattern"])
	_mats.clear()
	if data.is_empty():
		data = load_data()
	_rng.seed = absi(apt_id.hash()) + 1
	_sky_shader = Shader.new()
	_sky_shader.code = SKY_SHADER
	_body = StaticBody3D.new()
	_body.collision_layer = 1
	add_child(_body)
	var acc: Array = data.get("accent", ["#886644"])
	var accent := Color(str(acc[_rng.randi() % acc.size()]))
	var ox: float = float(plan["entrance"]["x"])
	var apt: Dictionary = plan["apartments"][apt_id]
	for f in floor_count:
		_building_floor(plan, f, apt_id, ox, accent)
	_stairs(plan, ox)
	_box(Vector3(2.4, 0.2, 1.6), Vector3(0, -0.1, -0.8), ObjectRegistry.mat(Color(0.35, 0.33, 0.3)), true)
	if present:
		_yoff = float(apt["floor"]) * float(plan["fh"])
		for r in apt["rooms"]:
			if r["kind"] == "living":
				var rc: Array = r["rect"]
				_add_occupant(Rect2(float(rc[0]) - ox, float(rc[1]), float(rc[2]), float(rc[3])), bot_color)
				break
	_yoff = 0.0


func _building_floor(plan: Dictionary, f: int, apt_id: String, ox: float, accent: Color) -> void:
	var fd: Dictionary = plan["floors_data"][f]
	var fh: float = float(plan["fh"])
	var apt_floor: int = int(plan["apartments"][apt_id]["floor"])
	_yoff = f * fh
	var cells: Array = []
	for c in fd["cells"]:
		var rc: Array = c["rect"]
		var aid: String = str(c["apartment_id"])
		if aid == "" or aid == apt_id:
			cells.append({"r": Rect2(float(rc[0]) - ox, float(rc[1]), float(rc[2]), float(rc[3])), "kind": str(c["kind"]), "col": Color(str(c["color"])), "open": true, "wins": c["windows"], "rid": c["id"]})
	for aid in fd["apartments"]:
		if aid == apt_id:
			continue
		var u := Rect2()
		var first := true
		for r in plan["apartments"][aid]["rooms"]:
			var rc: Array = r["rect"]
			var rr := Rect2(float(rc[0]) - ox, float(rc[1]), float(rc[2]), float(rc[3]))
			u = rr if first else u.merge(rr)
			first = false
		cells.append({"r": u, "kind": "closed", "col": Color(0.8, 0.8, 0.78), "open": false, "wins": [], "rid": aid})
		_box(Vector3(u.size.x, fh + 0.2, u.size.y), Vector3(u.position.x + u.size.x * 0.5, _yoff + fh * 0.5 - 0.1, u.position.y + u.size.y * 0.5), _cmat(Color(0.8, 0.8, 0.78)), true)
	var doors: Array = fd["doors"]
	for i in cells.size():
		var cell: Dictionary = cells[i]
		if not cell["open"]:
			continue
		var r: Rect2 = cell["r"]
		var kind: String = cell["kind"]
		var c3 := Vector3(r.position.x + r.size.x * 0.5, 0, r.position.y + r.size.y * 0.5)
		var target := f == apt_floor and str(plan["rooms"][cell["rid"]]["apartment_id"]) == apt_id
		if kind == "stair" and f > 0:
			_box(Vector3(0.1, 0.2, r.size.y), Vector3(r.end.x - 0.05, _yoff - 0.1, c3.z), _cmat(Color(0.45, 0.43, 0.4)), true)
		else:
			var fcol := {"living": Color(0.55, 0.4, 0.26), "kitchen": Color(0.7, 0.7, 0.68), "bedroom": Color(0.5, 0.42, 0.34), "corridor": Color(0.4, 0.38, 0.36)}.get(kind, Color(0.45, 0.42, 0.4)) as Color
			_box(Vector3(r.size.x, 0.2, r.size.y), Vector3(c3.x, _yoff - 0.1, c3.z), _cmat(fcol), true)
		if f == floor_count - 1:
			_box(Vector3(r.size.x, 0.2, r.size.y), Vector3(c3.x, _yoff + fh + 0.1, c3.z), _cmat(Color(0.93, 0.93, 0.9)), true)
		if target or kind in ["stair", "corridor", "hall"]:
			var lamp := OmniLight3D.new()
			lamp.position = Vector3(c3.x, _yoff + fh - 0.4, c3.z)
			lamp.omni_range = clampf(maxf(r.size.x, r.size.y) * 1.3, 4.0, 9.0)
			lamp.light_energy = 1.2
			lamp.light_color = Color(1.0, 0.92, 0.8)
			add_child(lamp)
		if target:
			room_count += 1
			_furnish(kind, r, accent)
		for e in 4:
			_cell_edge(plan, f, cells, i, e, doors, ox)
	_yoff = 0.0


func _cell_edge(plan: Dictionary, f: int, cells: Array, i: int, e: int, doors: Array, ox: float) -> void:
	var cell: Dictionary = cells[i]
	var r: Rect2 = cell["r"]
	var fh: float = float(plan["fh"])
	var horiz: bool = e < 2
	var fixed: float = [r.position.y, r.end.y, r.position.x, r.end.x][e]
	var lo: float = r.position.x if horiz else r.position.y
	var hi: float = r.end.x if horiz else r.end.y
	var ivs: Array = []
	for j in cells.size():
		if j == i:
			continue
		var o: Rect2 = (cells[j] as Dictionary)["r"]
		var touch := false
		var a0 := 0.0
		var a1 := 0.0
		match e:
			0: touch = is_equal_approx(o.end.y, fixed); a0 = o.position.x; a1 = o.end.x
			1: touch = is_equal_approx(o.position.y, fixed); a0 = o.position.x; a1 = o.end.x
			2: touch = is_equal_approx(o.end.x, fixed); a0 = o.position.y; a1 = o.end.y
			_: touch = is_equal_approx(o.position.x, fixed); a0 = o.position.y; a1 = o.end.y
		a0 = maxf(a0, lo)
		a1 = minf(a1, hi)
		if touch and a1 - a0 > 0.3:
			ivs.append([a0, a1, j])
	ivs.sort_custom(func(a, b): return a[0] < b[0])
	var cur := lo
	var mat := _cmat(cell["col"])
	for iv in ivs:
		if iv[0] > cur + 0.01:
			_ext_edge(plan, f, cell, horiz, fixed, cur, iv[0], e, mat, ox)
		var nb: Dictionary = cells[int(iv[2])]
		if not nb["open"] or int(iv[2]) > i:
			var ops: Array = []
			for dr in doors:
				var dx: float = float(dr["x"]) - ox
				var dz: float = float(dr["z"])
				var on_line: bool = absf(dz - fixed) < 0.06 if horiz else absf(dx - fixed) < 0.06
				var along: float = dx if horiz else dz
				if on_line and along > iv[0] - 0.01 and along < iv[1] + 0.01:
					if nb["open"]:
						ops.append([along, float(dr["w"]), 0.0, float(dr["h"])])
					else:
						var pos := Vector3(along, _yoff + 1.05, fixed) if horiz else Vector3(fixed, _yoff + 1.05, along)
						var sz := Vector3(float(dr["w"]), 2.1, 0.26) if horiz else Vector3(0.26, 2.1, float(dr["w"]))
						_box(sz, pos, ObjectRegistry.mat(Color(0.35, 0.22, 0.14)), false)
			_wall_ops(horiz, fixed, iv[0], iv[1], ops, mat, fh)
		cur = maxf(cur, iv[1])
	if hi > cur + 0.01:
		_ext_edge(plan, f, cell, horiz, fixed, cur, hi, e, mat, ox)


func _ext_edge(plan: Dictionary, f: int, cell: Dictionary, horiz: bool, fixed: float, lo: float, hi: float, e: int, mat: Material, ox: float) -> void:
	var fac := ""
	match e:
		0: fac = "front" if absf(fixed) < 0.05 else ""
		1: fac = "back" if absf(fixed - float(plan["d"])) < 0.05 else ""
		2: fac = "left" if absf(fixed + ox) < 0.05 else ""
		_: fac = "right" if absf(fixed - (float(plan["w"]) - ox)) < 0.05 else ""
	var ops: Array = []
	var glass: Array = []
	for wn in cell["wins"]:
		if str(wn["facade"]) != fac:
			continue
		var c: float = float(wn["x"]) - (ox if horiz else 0.0)
		if c > lo and c < hi:
			ops.append([c, float(wn["w"]), float(wn["y"]), float(wn["y"]) + float(wn["h"])])
			glass.append([c, float(wn["w"]), float(wn["h"]), float(wn["y"])])
	if f == 0 and fac == "front" and lo < 0.0 and hi > 0.0 and cell["kind"] in ["hall", "corridor"]:
		ops.append([0.0, DOOR_W, 0.0, DOOR_H])
	_wall_ops(horiz, fixed, lo, hi, ops, mat, float(plan["fh"]))
	for g in glass:
		_glass_at(horiz, fixed, g[0], e, g[1], g[2], _yoff + g[3] + g[2] * 0.5)


## Mur plein de lo à hi avec ouvertures [centre, largeur, bas, haut] (hauteurs relatives à l'étage).
func _wall_ops(horiz: bool, fixed: float, lo: float, hi: float, ops: Array, mat: Material, hgt: float) -> void:
	ops.sort_custom(func(a, b): return a[0] < b[0])
	var segs: Array = []
	var cur := lo
	for o in ops:
		var x0: float = o[0] - o[1] * 0.5
		var x1: float = o[0] + o[1] * 0.5
		segs.append([cur, x0, 0.0, hgt])
		if o[2] > 0.0:
			segs.append([x0, x1, 0.0, o[2]])
		segs.append([x0, x1, o[3], hgt])
		cur = x1
	segs.append([cur, hi, 0.0, hgt])
	for s in segs:
		var ln: float = s[1] - s[0]
		if ln < 0.02 or s[3] - s[2] < 0.02:
			continue
		var mid: float = (s[0] + s[1]) * 0.5
		var ym: float = _yoff + (s[2] + s[3]) * 0.5
		var size := Vector3(ln, s[3] - s[2], 0.2) if horiz else Vector3(0.2, s[3] - s[2], ln)
		var pos := Vector3(mid, ym, fixed) if horiz else Vector3(fixed, ym, mid)
		_box(size, pos, mat, true)


func _glass_at(horiz: bool, fixed: float, mid: float, e: int, w: float, h: float, yc: float) -> void:
	window_count += 1
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(w, h)
	q.mesh = qm
	var m := ShaderMaterial.new()
	m.shader = _sky_shader
	m.set_shader_parameter("seed", float(window_count) * 7.3)
	q.material_override = m
	q.rotation.y = [0.0, PI, PI * 0.5, -PI * 0.5][e]
	q.position = Vector3(mid, yc, fixed) if horiz else Vector3(fixed, yc, mid)
	add_child(q)


## Escalier en U dans la cage : volée montante (voie basse z), palier, volée suivante (voie haute z).
## Marches visuelles + rampes de collision (pente ~27 deg).
func _stairs(plan: Dictionary, ox: float) -> void:
	var s: Dictionary = plan["stair"]
	var fh: float = float(plan["fh"])
	var n: int = int(s["n"])
	var rise: float = float(s["rise"])
	var tr: float = float(s["tread"])
	var lane: float = float(s["lane"])
	var z0: float = float(s["z0"])
	var zw: float = float(s["w"])
	var sx: float = float(s["start_x"]) - ox
	var ex: float = sx - tr * n
	var mat := _cmat(Color(0.62, 0.6, 0.56))
	var ang := atan2(rise, tr)
	var rl := sqrt(pow(tr * n, 2) + pow(rise * n, 2)) + 0.2
	for f in floor_count - 1:
		var y0: float = f * fh
		for i in n:
			var ya: float = rise * (i + 1)
			_box(Vector3(tr, ya, lane), Vector3(sx - tr * (i + 0.5), y0 + ya * 0.5, z0 + lane * 0.5), mat, false)
			var yb: float = fh * 0.5 + rise * (i + 1)
			_box(Vector3(tr, yb, lane), Vector3(ex + tr * (i + 0.5), y0 + yb * 0.5, z0 + zw - lane * 0.5), mat, false)
		_box(Vector3(-ex, 0.2, zw), Vector3(ex * 0.5, y0 + fh * 0.5 - 0.1, z0 + zw * 0.5), mat, true)
		_ramp(Vector3((sx + ex) * 0.5, y0 + rise * n * 0.5 + rise * 0.5 - 0.05, z0 + lane * 0.5), -ang, rl, lane)
		_ramp(Vector3((sx + ex) * 0.5, y0 + fh * 0.5 + rise * n * 0.5 + rise * 0.5 - 0.05, z0 + zw - lane * 0.5), ang, rl, lane)
		_box(Vector3(sx - ex, fh + 1.0, zw - 2.0 * lane), Vector3((sx + ex) * 0.5, y0 + (fh + 1.0) * 0.5, z0 + zw * 0.5), _cmat(Color(0.75, 0.73, 0.7)), true)


func _ramp(pos: Vector3, ang: float, length: float, width: float) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(length, 0.1, width)
	cs.shape = bs
	cs.position = pos
	cs.rotation.z = ang
	_body.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = bs.size
	mi.mesh = bm
	mi.material_override = _cmat(Color(0.5, 0.48, 0.45))
	mi.position = pos
	mi.rotation.z = ang
	mi.visible = false
	add_child(mi)
