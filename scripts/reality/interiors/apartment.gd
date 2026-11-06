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
		var pos := Vector3(r.position.x + fx * r.size.x, 0, r.position.y + float(at[1]) * r.size.y)
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
	b.position = Vector3(r.position.x + r.size.x * 0.5 + 1.2, 0, r.position.y + r.size.y * 0.3)
	add_child(b)
