class_name CityBuilder
extends Node3D
## Ville procédurale simple, pilotée par res://data/city/city.json.
## Rues (asphalte) + trottoirs (MultiMesh), bâtiments = boîtes à motifs + fenêtres (un MultiMesh
## et un shader par modèle), lampadaires/arbres fusionnés (un MultiMesh par type), une collision par bâtiment.

const CONFIG_PATH := "res://data/city/city.json"
const WALL_SHADER := """
shader_type spatial;
uniform sampler2D wall_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec4 win = vec4(1.4, 1.6, 3.2, 3.2); // largeur fenêtre, hauteur, pas horizontal, hauteur d'étage
uniform float rough = 0.9;
varying vec3 lp;
varying vec3 nrm;
varying float hgt;
void vertex() {
	vec3 s = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	lp = VERTEX * s + vec3(0.0, s.y * 0.5, 0.0);
	nrm = NORMAL;
	hgt = s.y;
}
void fragment() {
	bool side = abs(nrm.y) < 0.5;
	float u = abs(nrm.x) > 0.5 ? lp.z : lp.x;
	vec2 uv = side ? vec2(u, lp.y) : lp.xz;
	vec3 col = texture(wall_tex, uv * 0.5).rgb * tint.rgb;
	if (!side) { col *= 0.55; }
	float m = 0.0;
	if (side && win.x > 0.0 && lp.y > win.w * 0.95 && lp.y < hgt - 0.6) {
		vec2 c = vec2(mod(u, win.z), mod(lp.y, win.w));
		float x0 = (win.z - win.x) * 0.5;
		m = step(x0, c.x) * step(c.x, x0 + win.x) * step(0.9, c.y) * step(c.y, 0.9 + win.y);
	}
	ALBEDO = mix(col, vec3(0.16, 0.24, 0.32), m);
	METALLIC = m * 0.3;
	ROUGHNESS = mix(rough, 0.12, m);
}
"""

var config: Dictionary = {}
var building_count := 0
var lamp_count := 0
var tree_count := 0
var extent := 0.0               # demi-largeur de la ville
var plaza := AABB()             # locale à ce noeud
var sidewalk_loops: Array = []  # boucles de points (Vector3 locaux) le long des trottoirs
var graph := CityGraph.new()    # graphe piéton (trottoirs, passages, portes)
var buildings: Array = []       # {idx,pos,size,model,floors,block,role,name,prep,side,door,door_pos,address}
var places: Dictionary = {}     # id -> {id,name,prep,role,door,door_pos,address}
var lamp_mat: StandardMaterial3D
var _blocks := {}               # Vector2i -> {c, sides:{n,s,e,w: [[t,node]]}, corners:{}}
var _ring := 18.75
var _street_n := {}
var _rng := RandomNumberGenerator.new()


static func default_config() -> Dictionary:
	return {"seed": 1, "grid": {"cols": 5, "rows": 5}, "block_size": 40.0, "street_width": 10.0, "sidewalk_width": 2.5,
		"lots_per_block": 2, "density": 0.8, "trees_per_block": 4,
		"models": [{"name": "Boite", "weight": 1, "width": [12, 15], "depth": [12, 15], "floors": [3, 5],
			"floor_height": 3.0, "material": "enduit", "color": "#e0d8c8", "windows": "grid"}]}


static func load_config(path := CONFIG_PATH) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f != null:
		var d = JSON.parse_string(f.get_as_text())
		if typeof(d) == TYPE_DICTIONARY and not (d.get("models", []) as Array).is_empty():
			return d
	return default_config()


func build(cfg: Dictionary) -> void:
	config = cfg
	_rng.seed = int(cfg.get("seed", 1))
	var cols: int = int(cfg.get("grid", {}).get("cols", 5)) | 1   # impair : une place au centre
	var rows: int = int(cfg.get("grid", {}).get("rows", 5)) | 1
	var bs: float = float(cfg.get("block_size", 40.0))
	var sw: float = float(cfg.get("street_width", 10.0))
	var walk: float = float(cfg.get("sidewalk_width", 2.5))
	var pitch := bs + sw
	extent = maxf(cols, rows) * pitch * 0.5
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	# rues : un grand plan sombre
	var road := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(cols * pitch + sw, rows * pitch + sw)
	road.mesh = pm
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(0.11, 0.11, 0.125)
	rm.roughness = 0.95
	road.material_override = rm
	road.position.y = 0.02
	road.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(road)
	var slabs: Array = []   # trottoirs
	var plaza_xf: Transform3D
	var lots: Array = []
	var lamps: Array = []
	var trees: Array = []
	_ring = (bs - walk) * 0.5
	var cx := (cols - 1) * 0.5
	var cz := (rows - 1) * 0.5
	for i in cols:
		for j in rows:
			var c := Vector3((i - cx) * pitch, 0, (j - cz) * pitch)
			var is_plaza := i == cols / 2 and j == rows / 2
			var xf := Transform3D(Basis.from_scale(Vector3(bs, 0.1, bs)), c + Vector3(0, 0.05, 0))
			if is_plaza:
				plaza_xf = xf
				plaza = AABB(c + Vector3(-bs * 0.5 + walk, 0, -bs * 0.5 + walk), Vector3(bs - 2 * walk, 0.1, bs - 2 * walk))
			else:
				slabs.append(xf)
				_lots(c, bs - 2.0 * walk, lots, Vector2i(i, j))
			_props(c, bs, walk, is_plaza, lamps, trees)
			_loop(c, bs - walk)
			_block_nodes(i, j, c)
	_assign_roles(lots, cols, rows)
	_finish_graph(cols, rows)
	_slab_mesh(slabs, StructureKit.make_material("beton", Color(0.82, 0.82, 0.8)))
	_slab_mesh([plaza_xf], StructureKit.make_material("pierre", Color(0.92, 0.9, 0.85)))
	_buildings(lots, body)
	_props_mesh(lamps, true)
	_props_mesh(trees, false)


## Découpe un îlot en parcelles et y pose des bâtiments selon la densité.
func _lots(center: Vector3, size: float, out: Array, block := Vector2i.ZERO) -> void:
	var n: int = maxi(1, int(config.get("lots_per_block", 2)))
	var cell := size / n
	var dens: float = float(config.get("density", 0.8))
	var models: Array = config.get("models", [])
	var total := 0.0
	for m in models:
		total += float(m.get("weight", 1))
	for a in n:
		for b in n:
			if _rng.randf() > dens:
				continue
			var r := _rng.randf() * total
			var model: Dictionary = models[0]
			for m in models:
				r -= float(m.get("weight", 1))
				if r <= 0.0:
					model = m
					break
			var w := minf(_val(model.get("width", 12)), cell - 1.0)
			var d := minf(_val(model.get("depth", 12)), cell - 1.0)
			var fl := roundi(_val(model.get("floors", 3)))
			var h := maxi(1, fl) * float(model.get("floor_height", 3.0))
			var p := center + Vector3((a - (n - 1) * 0.5) * cell, 0, (b - (n - 1) * 0.5) * cell)
			out.append({"model": model, "pos": p, "size": Vector3(w, h, d), "block": block})


func _val(v) -> float:
	if v is Array and v.size() >= 2:
		return _rng.randf_range(float(v[0]), float(v[1]))
	return float(v)


func _buildings(lots: Array, body: StaticBody3D) -> void:
	var by_model := {}
	for l in lots:
		var key: String = str(l.model.get("name", "?"))
		if not by_model.has(key):
			by_model[key] = {"model": l.model, "xf": []}
		by_model[key].xf.append(Transform3D(Basis.from_scale(l.size), l.pos + Vector3(0, l.size.y * 0.5, 0)))
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = l.size
		cs.shape = bx
		cs.position = l.pos + Vector3(0, l.size.y * 0.5, 0)
		body.add_child(cs)
		building_count += 1
	for key in by_model:
		var model: Dictionary = by_model[key].model
		_multi(by_model[key].xf, BoxMesh.new(), _wall_material(model), true)


func _wall_material(model: Dictionary) -> ShaderMaterial:
	var mid: String = str(model.get("material", "enduit"))
	if not StructureKit.MATERIALS.has(mid):
		mid = "enduit"
	var sh := Shader.new()
	sh.code = WALL_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("wall_tex", StructureKit.texture(mid))
	m.set_shader_parameter("tint", Color(str(model.get("color", "#dddddd"))))
	m.set_shader_parameter("rough", float(StructureKit.MATERIALS[mid].rough))
	var fh: float = float(model.get("floor_height", 3.0))
	var win := Vector4(0, 0, 3.2, fh)
	match str(model.get("windows", "grid")):
		"grid": win = Vector4(1.4, minf(1.6, fh - 1.2), 3.2, fh)
		"tall": win = Vector4(0.9, minf(2.0, fh - 1.0), 2.2, fh)
		"strip": win = Vector4(3.7, minf(1.4, fh - 1.4), 4.0, fh)
	m.set_shader_parameter("win", win)
	return m


func _slab_mesh(xfs: Array, mat: Material) -> void:
	_multi(xfs, BoxMesh.new(), mat, false)


func _multi(xfs: Array, mesh: Mesh, mat: Material, shadows: bool) -> void:
	if xfs.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## Lampadaires aux coins et trottoirs, arbres le long des trottoirs ; la place a son anneau d'arbres.
func _props(c: Vector3, bs: float, walk: float, is_plaza: bool, lamps: Array, trees: Array) -> void:
	var e := bs * 0.5 - walk * 0.5
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			lamps.append(c + Vector3(sx * e, 0, sz * e))
		lamps.append(c + Vector3(sx * e, 0, 0))
		lamps.append(c + Vector3(0, 0, sx * e))
	var n: int = int(config.get("trees_per_block", 4))
	if is_plaza:
		n = 12
	for k in n:
		var t := (k + 0.5) / n * 4.0
		var side := int(t) % 4
		var f := (t - floorf(t) - 0.5) * (bs - 8.0)
		var q := Vector3.ZERO
		match side:
			0: q = Vector3(f, 0, -e)
			1: q = Vector3(e, 0, f)
			2: q = Vector3(-f, 0, e)
			_: q = Vector3(-e, 0, -f)
		if is_plaza:
			q *= 0.7
		trees.append(c + q + Vector3(_rng.randf_range(-1, 1), 0, 0) * 0.5)


func _loop(c: Vector3, ring: float) -> void:
	var e := ring * 0.5
	var pts: Array = []
	for p in [Vector2(-1, -1), Vector2(0, -1), Vector2(1, -1), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), Vector2(-1, 1), Vector2(-1, 0)]:
		pts.append(c + Vector3(p.x * e, 0.05, p.y * e))
	sidewalk_loops.append(pts)


## Fusionne les parties (mesh, transform, couleur) en un seul ArrayMesh à couleurs de sommets.
func _props_mesh(positions: Array, lamp: bool) -> void:
	if positions.is_empty():
		return
	var parts: Array = []
	if lamp:
		var pole := CylinderMesh.new()
		pole.top_radius = 0.06
		pole.bottom_radius = 0.09
		pole.height = 4.5
		pole.radial_segments = 6
		var head := SphereMesh.new()
		head.radius = 0.28
		head.height = 0.56
		head.radial_segments = 8
		head.rings = 4
		parts = [[pole, Transform3D(Basis.IDENTITY, Vector3(0, 2.25, 0)), Color(0.18, 0.19, 0.2)],
			[head, Transform3D(Basis.IDENTITY, Vector3(0, 4.6, 0)), Color(1.0, 0.9, 0.6)]]
	else:
		var trunk := CylinderMesh.new()
		trunk.top_radius = 0.15
		trunk.bottom_radius = 0.22
		trunk.height = 2.4
		trunk.radial_segments = 6
		var crown := SphereMesh.new()
		crown.radius = 1.6
		crown.height = 3.2
		crown.radial_segments = 8
		crown.rings = 4
		parts = [[trunk, Transform3D(Basis.IDENTITY, Vector3(0, 1.2, 0)), Color(0.38, 0.27, 0.18)],
			[crown, Transform3D(Basis.IDENTITY, Vector3(0, 3.6, 0)), Color(0.28, 0.5, 0.26)]]
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for part in parts:
		var arr: Array = (part[0] as Mesh).surface_get_arrays(0)
		var xf: Transform3D = part[1]
		var base := verts.size()
		for v in arr[Mesh.ARRAY_VERTEX]:
			verts.append(xf * v)
			cols.append(part[2])
		for n in arr[Mesh.ARRAY_NORMAL]:
			norms.append(xf.basis * n)
		for i in arr[Mesh.ARRAY_INDEX]:
			idx.append(base + i)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.85
	if lamp:
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.9, 0.6)
		mat.emission_energy_multiplier = 0.15
		lamp_count = positions.size()
		lamp_mat = mat
	else:
		tree_count = positions.size()
	var xfs: Array = []
	for p in positions:
		xfs.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), p))
	_multi(xfs, am, mat, false)


## Allume/éteint les lampadaires (panne).
func set_lamps(on: bool) -> void:
	if lamp_mat:
		lamp_mat.emission_energy_multiplier = 0.15 if on else 0.0


# --- Graphe piéton et rôles des bâtiments ---

func _block_nodes(i: int, j: int, c: Vector3) -> void:
	var e := _ring
	var corners := {}
	for k in [["nw", -1, -1], ["ne", 1, -1], ["sw", -1, 1], ["se", 1, 1]]:
		corners[k[0]] = graph.add_point(c + Vector3(k[1] * e, 0.05, k[2] * e))
	_blocks[Vector2i(i, j)] = {"c": c, "corners": corners, "sides": {
		"n": [[-e, corners.nw], [e, corners.ne]], "s": [[-e, corners.sw], [e, corners.se]],
		"w": [[-e, corners.nw], [e, corners.sw]], "e": [[-e, corners.ne], [e, corners.se]]}}


## Ajoute une porte (point de trottoir) sur le côté `side` du bloc, à la coordonnée t.
func _add_door(block: Vector2i, side: String, t: float) -> Array:
	var b: Dictionary = _blocks[block]
	var used: Array = []
	for it in b.sides[side]:
		used.append(float(it[0]))
	t = clampf(t, -_ring + 4.0, _ring - 4.0)
	var tries := 0
	while tries < 20:
		var clash := false
		for u in used:
			if absf(u - t) < 1.6:
				clash = true
		if not clash:
			break
		t = t + 1.7 if t + 1.7 < _ring - 3.0 else t - 8.0
		tries += 1
	var c: Vector3 = b.c
	var p := Vector3.ZERO
	match side:
		"n": p = c + Vector3(t, 0.05, -_ring)
		"s": p = c + Vector3(t, 0.05, _ring)
		"w": p = c + Vector3(-_ring, 0.05, t)
		_: p = c + Vector3(_ring, 0.05, t)
	var id := graph.add_point(p)
	b.sides[side].append([t, id])
	return [id, p]


func _address(block: Vector2i, side: String) -> String:
	var streets: Dictionary = config.get("streets", {})
	var ns: Array = streets.get("ns", ["rue Nord-Sud"])
	var ew: Array = streets.get("ew", ["rue Est-Ouest"])
	var nm: String
	if side == "n" or side == "s":
		nm = str(ew[(block.y + (1 if side == "s" else 0)) % ew.size()])
	else:
		nm = str(ns[(block.x + (1 if side == "e" else 0)) % ns.size()])
	var n: int = int(_street_n.get(nm, 0))
	_street_n[nm] = n + 1
	return "%d %s" % [n * 2 + (1 if side == "n" or side == "w" else 2), nm]


func _side_of(l: Dictionary) -> Array:
	var c: Vector3 = _blocks[l.block].c
	var d: Vector3 = l.pos - c
	if absf(d.x) > absf(d.z):
		return ["e" if d.x > 0.0 else "w", d.z]
	return ["s" if d.z > 0.0 else "n", d.x]


func _assign_roles(lots: Array, cols: int, rows: int) -> void:
	var cb := Vector2i(cols / 2, rows / 2)
	var pitch: float = float(config.get("block_size", 40.0)) + float(config.get("street_width", 10.0))
	for k in lots.size():
		var l: Dictionary = lots[k]
		var sd := _side_of(l)
		var door := _add_door(l.block, sd[0], sd[1])
		var fh: float = float(l.model.get("floor_height", 3.0))
		buildings.append({"idx": k, "pos": l.pos, "size": l.size, "model": str(l.model.get("name", "")), "floors": maxi(1, roundi(l.size.y / fh)),
			"block": l.block, "role": "residence", "name": "", "prep": "", "side": sd[0], "door": door[0], "door_pos": door[1],
			"address": _address(l.block, sd[0])})
	for spec in config.get("places", []):
		var id: String = str(spec.get("id", spec.get("role", "?")))
		var role: String = str(spec.get("role", id))
		var pl := {"id": id, "name": str(spec.get("name", id)), "prep": str(spec.get("prep", "à")), "role": role}
		if spec.has("plaza"):
			var side: String = str(spec["plaza"])
			var dr := _add_door(cb, side, 0.0)
			pl["door"] = dr[0]
			pl["door_pos"] = dr[1]
			pl["address"] = "sur la place"
		else:
			var near: Array = spec.get("near", [0, 0])
			var target := Vector3((cb.x + int(near[0]) - (cols - 1) * 0.5) * pitch, 0, (cb.y + int(near[1]) - (rows - 1) * 0.5) * pitch)
			var best := -1
			var bd := INF
			for b in buildings:
				if b.role != "residence":
					continue
				var dd: float = (b.pos - target).length()
				if spec.has("prefer") and b.model == str(spec["prefer"]):
					dd -= 120.0
				if dd < bd:
					bd = dd
					best = b.idx
			if best < 0:
				continue
			var bb: Dictionary = buildings[best]
			bb.role = role
			bb.name = pl.name
			bb.prep = pl.prep
			pl["door"] = bb.door
			pl["door_pos"] = bb.door_pos
			pl["address"] = bb.address
			pl["building"] = best
		places[id] = pl


func _finish_graph(cols: int, rows: int) -> void:
	for key in _blocks:
		var b: Dictionary = _blocks[key]
		for side in b.sides:
			var arr: Array = b.sides[side]
			arr.sort_custom(func(x, y) -> bool: return x[0] < y[0])
			for k in range(arr.size() - 1):
				graph.link(arr[k][1], arr[k + 1][1])
		var r: Vector2i = key + Vector2i(1, 0)
		if _blocks.has(r):
			graph.link(b.corners.ne, _blocks[r].corners.nw)
			graph.link(b.corners.se, _blocks[r].corners.sw)
		var d: Vector2i = key + Vector2i(0, 1)
		if _blocks.has(d):
			graph.link(b.corners.sw, _blocks[d].corners.nw)
			graph.link(b.corners.se, _blocks[d].corners.ne)
