class_name FurnitureLayout
## Placement des meubles par règles (2D, boîtes orientées). Repère : rot y degrés, avant du meuble = +z local,
## dos = -z local ; direction avant en (x, z) = (sin r, cos r). Murs : épaisseur 0,2 centrée sur le bord de la pièce.

const WT := 0.1          # demi-épaisseur de mur
const BACK_GAP := 0.05   # jeu dos de meuble / mur
const PASS := 0.8        # passage libre entre meubles
const DOOR_DEPTH := 1.1  # zone de débattement devant une porte
const SOLIDLESS := ["rug"]
const TALL := 0.85
const CUSTOM := {
	"bed": Vector3(1.5, 0.9, 2.1), "nightstand": Vector3(0.4, 0.5, 0.4),
	"wardrobe": Vector3(1.2, 2.0, 0.55), "coffee": Vector3(1.0, 0.4, 0.5),
}
const MAJOR := ["sofa", "bed", "wardrobe", "table", "shelf", "armchair"]


static func size_of(type: String) -> Vector3:
	if CUSTOM.has(type):
		return CUSTOM[type]
	return ObjectRegistry.get_def(type)["size"]


static func dir_of(rot_deg: float) -> Vector2:
	return Vector2(sin(deg_to_rad(rot_deg)), cos(deg_to_rad(rot_deg)))


## Coins d'un meuble {pos: Vector2, rot, size, scale} (ordre cyclique).
static func corners(it: Dictionary, grow := 0.0) -> Array:
	var s: Vector3 = it["size"]
	var k: float = float(it.get("scale", 1.0))
	var hx: float = s.x * k * 0.5 + grow
	var hz: float = s.z * k * 0.5 + grow
	var r: float = deg_to_rad(float(it["rot"]))
	var ax := Vector2(cos(r), -sin(r))
	var az := Vector2(sin(r), cos(r))
	var c: Vector2 = it["pos"]
	return [c - ax * hx - az * hz, c + ax * hx - az * hz, c + ax * hx + az * hz, c - ax * hx + az * hz]


static func _proj(pts: Array, axis: Vector2) -> Vector2:
	var lo := INF
	var hi := -INF
	for p in pts:
		var d: float = (p as Vector2).dot(axis)
		lo = minf(lo, d)
		hi = maxf(hi, d)
	return Vector2(lo, hi)


## Intersection stricte de deux polygones convexes (SAT).
static func poly_overlap(a: Array, b: Array) -> bool:
	for poly in [a, b]:
		for i in 4:
			var e: Vector2 = (poly[(i + 1) % 4] as Vector2) - (poly[i] as Vector2)
			var ax := Vector2(-e.y, e.x).normalized()
			var pa := _proj(a, ax)
			var pb := _proj(b, ax)
			if pa.y <= pb.x + 1e-4 or pb.y <= pa.x + 1e-4:
				return false
	return true


static func poly_rect(rc: Rect2) -> Array:
	return [rc.position, Vector2(rc.end.x, rc.position.y), rc.end, Vector2(rc.position.x, rc.end.y)]


static func inner(r: Rect2) -> Rect2:
	return r.grow(-WT)


## Zone rectangulaire d'une ouverture {e, c, w} : depth mesurée depuis la ligne du mur vers l'intérieur.
static func zone(r: Rect2, o: Dictionary, depth: float, pad: float) -> Rect2:
	var c: float = o["c"]
	var hw: float = float(o["w"]) * 0.5 + pad
	match int(o["e"]):
		0: return Rect2(c - hw, r.position.y, hw * 2.0, depth)
		1: return Rect2(c - hw, r.end.y - depth, hw * 2.0, depth)
		2: return Rect2(r.position.x, c - hw, depth, hw * 2.0)
	return Rect2(r.end.x - depth, c - hw, depth, hw * 2.0)


static func target_pt(r: Rect2, o: Dictionary) -> Vector2:
	var c: float = o["c"]
	match int(o["e"]):
		0: return Vector2(c, r.position.y + 0.6)
		1: return Vector2(c, r.end.y - 0.6)
		2: return Vector2(r.position.x + 0.6, c)
	return Vector2(r.end.x - 0.6, c)


static func is_solid(it: Dictionary) -> bool:
	return not (str(it["type"]) in SOLIDLESS)


static func is_tall(it: Dictionary) -> bool:
	return (it["size"] as Vector3).y > TALL


## Les points cibles (portes, fenêtres) sont-ils tous reliés, un passage de 0,8 m libre autour des meubles ?
static func connected(r: Rect2, solids: Array, targets: Array) -> bool:
	var inn := r.grow(-WT - 0.3)
	var st := 0.2
	var nx: int = maxi(1, int(ceil(inn.size.x / st)))
	var ny: int = maxi(1, int(ceil(inn.size.y / st)))
	var polys: Array = []
	for it in solids:
		polys.append(corners(it, PASS * 0.5))
	var blocked := PackedByteArray()
	blocked.resize(nx * ny)
	for j in ny:
		for i in nx:
			var p := Vector2(inn.position.x + (i + 0.5) * st, inn.position.y + (j + 0.5) * st)
			var pp := [p + Vector2(-0.001, -0.001), p + Vector2(0.001, -0.001), p + Vector2(0.001, 0.001), p + Vector2(-0.001, 0.001)]
			for poly in polys:
				if poly_overlap(pp, poly):
					blocked[j * nx + i] = 1
					break
	var cells: Array = []
	for t in targets:
		var tp: Vector2 = t
		var ci: int = clampi(int((tp.x - inn.position.x) / st), 0, nx - 1)
		var cj: int = clampi(int((tp.y - inn.position.y) / st), 0, ny - 1)
		cells.append(cj * nx + ci)
	if cells.size() < 2:
		return true
	var seen := PackedByteArray()
	seen.resize(nx * ny)
	var stack: Array = [cells[0]]
	seen[cells[0]] = 1
	while not stack.is_empty():
		var cur: int = stack.pop_back()
		var cx: int = cur % nx
		var cy: int = cur / nx
		for d in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
			var x2: int = cx + d[0]
			var y2: int = cy + d[1]
			if x2 < 0 or y2 < 0 or x2 >= nx or y2 >= ny:
				continue
			var k: int = y2 * nx + x2
			if seen[k] == 0 and blocked[k] == 0:
				seen[k] = 1
				stack.append(k)
	for c in cells:
		if seen[int(c)] == 0:
			return false
	return true


static func _can_reach(r: Rect2, solids: Array, doors: Array, wins: Array) -> bool:
	var pts: Array = []
	for o in doors:
		pts.append(target_pt(r, o))
	for o in wins:
		pts.append(target_pt(r, o))
	return connected(r, solids, pts)


## Vérifie une pièce planifiée ; renvoie la liste des erreurs (vide = propre).
static func check_room(rp: Dictionary) -> Array:
	var errs: Array = []
	var r: Rect2 = rp["rect"]
	var items: Array = rp["items"]
	var inn := inner(r)
	var solids: Array = []
	for i in items.size():
		var a: Dictionary = items[i]
		var pa := corners(a)
		for p in pa:
			if not inn.grow(0.001).has_point(p):
				errs.append("%s hors pièce/mur" % a["type"])
				break
		for o in rp["doors"]:
			if is_solid(a) and poly_overlap(pa, poly_rect(zone(r, o, DOOR_DEPTH, 0.15))):
				errs.append("%s devant une porte" % a["type"])
		if is_tall(a):
			for o in rp["wins"]:
				if poly_overlap(pa, poly_rect(zone(r, o, 0.5, 0.0))):
					errs.append("%s dans une fenêtre" % a["type"])
		if is_solid(a):
			solids.append(a)
		for j in range(i + 1, items.size()):
			var b: Dictionary = items[j]
			if not (is_solid(a) and is_solid(b)):
				continue
			if poly_overlap(pa, corners(b)):
				errs.append("%s/%s s'intersectent" % [a["type"], b["type"]])
			elif bool(a["major"]) and bool(b["major"]) and str(a["grp"]) != str(b["grp"]):
				if poly_overlap(corners(a, PASS * 0.5 - 0.001), corners(b, PASS * 0.5 - 0.001)):
					errs.append("%s/%s passage < 0,8 m" % [a["type"], b["type"]])
	if not _can_reach(r, solids, rp["doors"], rp["wins"]):
		errs.append("passage vers portes/fenêtres bloqué")
	return errs


static func _mk(type: String, pos: Vector2, rot: float, major: bool, grp: String, k := 1.0) -> Dictionary:
	return {"type": type, "pos": pos, "rot": rot, "size": size_of(type), "scale": k, "major": major, "grp": grp}


## Position d'un meuble le dos au mur e (0 n, 1 s, 2 w, 3 e), à `along` le long du mur.
static func _at_wall(type: String, r: Rect2, e: int, along: float, major: bool, grp: String) -> Dictionary:
	var s := size_of(type)
	var inn := inner(r)
	var d: float = s.z * 0.5 + BACK_GAP
	match e:
		0: return _mk(type, Vector2(along, inn.position.y + d), 0.0, major, grp)
		1: return _mk(type, Vector2(along, inn.end.y - d), 180.0, major, grp)
		2: return _mk(type, Vector2(inn.position.x + d, along), 90.0, major, grp)
	return _mk(type, Vector2(inn.end.x - d, along), -90.0, major, grp)


static func _valid(r: Rect2, doors: Array, wins: Array, placed: Array, group: Array) -> bool:
	var inn := inner(r)
	for it in group:
		var pa := corners(it)
		for p in pa:
			if not inn.grow(0.001).has_point(p):
				return false
		if not is_solid(it):
			continue
		for o in doors:
			if poly_overlap(pa, poly_rect(zone(r, o, DOOR_DEPTH, 0.15))):
				return false
		if is_tall(it):
			for o in wins:
				if poly_overlap(pa, poly_rect(zone(r, o, 0.5, 0.0))):
					return false
		var all: Array = placed + group
		for ot in all:
			if ot == it or not is_solid(ot):
				continue
			var same_grp := str(ot["grp"]) == str(it["grp"]) and str(it["grp"]) != ""
			var pb := corners(ot)
			if poly_overlap(pa, pb):
				return false
			if not same_grp:
				var g := 0.1
				if bool(it["major"]) and bool(ot["major"]):
					g = PASS
				if poly_overlap(corners(it, g * 0.5), corners(ot, g * 0.5)):
					return false
	return true


static func _wall_cands(type: String, r: Rect2, rng: RandomNumberGenerator, major: bool, grp: String) -> Array:
	var out: Array = []
	var walls := [0, 1, 2, 3]
	for i in range(3, 0, -1):
		var j: int = rng.randi() % (i + 1)
		var t: int = walls[i]
		walls[i] = walls[j]
		walls[j] = t
	var inn := inner(r)
	for e in walls:
		var lo: float = inn.position.x if e < 2 else inn.position.y
		var hi: float = inn.end.x if e < 2 else inn.end.y
		var mid := (lo + hi) * 0.5
		var offs := [0.0, 0.5, -0.5, 1.0, -1.0, 1.5, -1.5, 2.0, -2.0]
		for o in offs:
			var a: float = mid + float(o)
			out.append(_at_wall(type, r, int(e), a, major, grp))
		# bords (coins) : utile pour les petits meubles
		out.append(_at_wall(type, r, int(e), lo + size_of(type).x * 0.5 + 0.05, major, grp))
		out.append(_at_wall(type, r, int(e), hi - size_of(type).x * 0.5 - 0.05, major, grp))
	return out


static func _corner_cands(type: String, r: Rect2, rng: RandomNumberGenerator) -> Array:
	var s := size_of(type)
	var inn := inner(r)
	var hx: float = s.x * 0.5 + BACK_GAP
	var hz: float = s.z * 0.5 + BACK_GAP
	var out: Array = [
		_mk(type, Vector2(inn.position.x + hx, inn.position.y + hz), 0.0, false, ""),
		_mk(type, Vector2(inn.end.x - hx, inn.position.y + hz), 0.0, false, ""),
		_mk(type, Vector2(inn.position.x + hx, inn.end.y - hz), 0.0, false, ""),
		_mk(type, Vector2(inn.end.x - hx, inn.end.y - hz), 0.0, false, "")]
	for i in range(3, 0, -1):
		var j: int = rng.randi() % (i + 1)
		var t: Dictionary = out[i]
		out[i] = out[j]
		out[j] = t
	return out


## Pose le premier groupe de candidats valide (ou rien).
static func _put(r: Rect2, doors: Array, wins: Array, placed: Array, groups: Array) -> Array:
	for g in groups:
		if not _valid(r, doors, wins, placed, g):
			continue
		var solids: Array = []
		for it in placed + g:
			if is_solid(it):
				solids.append(it)
		if _can_reach(r, solids, doors, wins):
			placed.append_array(g)
			return g
	return []


static func plan_room(kind: String, r: Rect2, doors: Array, wins: Array, rng: RandomNumberGenerator) -> Array:
	var placed: Array = []
	match kind:
		"living":
			var sofa: Array = _put(r, doors, wins, placed, _singles(_wall_cands("sofa", r, rng, true, "L")))
			var table: Array = []
			if not sofa.is_empty():
				var sf: Dictionary = sofa[0]
				var fd := dir_of(float(sf["rot"]))
				var ts := size_of("coffee")
				var cp: Vector2 = (sf["pos"] as Vector2) + fd * ((sf["size"] as Vector3).z * 0.5 + 0.4 + ts.z * 0.5)
				table = _put(r, doors, wins, placed, [[_mk("coffee", cp, float(sf["rot"]) + 180.0, true, "L")]])
				if table.is_empty():
					pass
			if not sofa.is_empty() and not table.is_empty():
				var tb: Dictionary = table[0]
				var fd2 := dir_of(float(sofa[0]["rot"]))
				for k in [1.0, 0.8, 0.65]:
					var rp: Vector2 = (tb["pos"] as Vector2) - fd2 * 0.15
					var rug := _mk("rug", rp, float(sofa[0]["rot"]), false, "", k)
					if _valid(r, doors, wins, placed, [rug]):
						placed.append(rug)
						break
			_put(r, doors, wins, placed, _singles(_wall_cands("armchair", r, rng, true, "")) if rng.randf() < 0.7 else [])
			_put(r, doors, wins, placed, _singles(_wall_cands("shelf", r, rng, true, "")) if rng.randf() < 0.8 else [])
			_put(r, doors, wins, placed, _singles(_corner_cands("lamp", r, rng)))
			if rng.randf() < 0.8:
				_put(r, doors, wins, placed, _singles(_corner_cands("plant", r, rng)))
		"bedroom":
			var bed: Array = _put(r, doors, wins, placed, _singles(_wall_cands("bed", r, rng, true, "B")))
			if not bed.is_empty():
				var b: Dictionary = bed[0]
				var ax := Vector2(cos(deg_to_rad(float(b["rot"]))), -sin(deg_to_rad(float(b["rot"]))))
				var fd := dir_of(float(b["rot"]))
				var ns := size_of("nightstand")
				var sides: Array = [1.0, -1.0]
				if rng.randf() < 0.5:
					sides = [-1.0, 1.0]
				var cs: Array = []
				for sd in sides:
					var cp: Vector2 = (b["pos"] as Vector2) + ax * float(sd) * ((b["size"] as Vector3).x * 0.5 + 0.05 + ns.x * 0.5) - fd * ((b["size"] as Vector3).z * 0.5 - ns.z * 0.5)
					cs.append([_mk("nightstand", cp, float(b["rot"]), false, "B")])
				_put(r, doors, wins, placed, cs)
			_put(r, doors, wins, placed, _singles(_wall_cands("wardrobe", r, rng, true, "")))
		"kitchen":
			var inn := inner(r)
			var long_x: bool = inn.size.x >= inn.size.y
			var ts := size_of("table")
			var cs: Array = []
			var cen := inn.get_center()
			for off in [Vector2.ZERO, Vector2(0.4, 0), Vector2(-0.4, 0), Vector2(0, 0.4), Vector2(0, -0.4), Vector2(0.8, 0), Vector2(-0.8, 0)]:
				for horiz in ([long_x, not long_x]):
					var p: Vector2 = cen + (off as Vector2)
					var rot: float = 90.0 if horiz else 0.0
					# rot 90 : l'axe x local (1,8 m) devient l'axe z -> on aligne la longueur sur x avec rot 0
					rot = 0.0 if horiz else 90.0
					var tbl := _mk("table", p, rot, true, "K")
					var fdt := dir_of(rot)
					var side := Vector2(cos(deg_to_rad(rot)), -sin(deg_to_rad(rot)))
					var csz := size_of("chair")
					var dist: float = ts.z * 0.5 + csz.z * 0.5 + 0.05
					var c1 := _mk("chair", p + fdt * dist, rot + 180.0, false, "K")
					var c2 := _mk("chair", p - fdt * dist, rot, false, "K")
					cs.append([tbl, c1, c2])
					cs.append([tbl, c1])
					cs.append([tbl, c2])
					cs.append([tbl])
			_put(r, doors, wins, placed, cs)
			if rng.randf() < 0.6:
				_put(r, doors, wins, placed, _singles(_wall_cands("shelf", r, rng, true, "")))
			if rng.randf() < 0.6:
				_put(r, doors, wins, placed, _singles(_corner_cands("plant", r, rng)))
		"entry":
			if rng.randf() < 0.5:
				_put(r, doors, wins, placed, _singles(_corner_cands("plant", r, rng)))
			if rng.randf() < 0.5:
				_put(r, doors, wins, placed, _singles(_wall_cands("shelf", r, rng, true, "")))
	return placed


static func _singles(cands: Array) -> Array:
	var out: Array = []
	for c in cands:
		out.append([c])
	return out


## Meubles sur mesure (le reste vient d'ObjectRegistry).
static func make(type: String, accent: Color) -> Node3D:
	var root := Node3D.new()
	var wood := ObjectRegistry.mat(Color(0.4, 0.3, 0.22))
	match type:
		"bed":
			ObjectRegistry.box(root, Vector3(1.5, 0.35, 2.0), Vector3(0, 0.25, 0.025), wood)
			ObjectRegistry.box(root, Vector3(1.4, 0.2, 1.9), Vector3(0, 0.52, 0.025), ObjectRegistry.mat(accent.lightened(0.5)))
			ObjectRegistry.box(root, Vector3(1.5, 0.9, 0.1), Vector3(0, 0.55, -1.0), wood)
			ObjectRegistry.box(root, Vector3(0.5, 0.12, 0.3), Vector3(-0.35, 0.68, -0.75), ObjectRegistry.mat(Color(0.95, 0.95, 0.92)))
			ObjectRegistry.box(root, Vector3(0.5, 0.12, 0.3), Vector3(0.35, 0.68, -0.75), ObjectRegistry.mat(Color(0.95, 0.95, 0.92)))
		"nightstand":
			ObjectRegistry.box(root, Vector3(0.4, 0.5, 0.4), Vector3(0, 0.25, 0), wood)
			ObjectRegistry.box(root, Vector3(0.34, 0.04, 0.02), Vector3(0, 0.38, 0.2), ObjectRegistry.mat(Color(0.7, 0.6, 0.45)))
			ObjectRegistry.box(root, Vector3(0.1, 0.18, 0.1), Vector3(0, 0.59, 0), ObjectRegistry.mat(Color(0.95, 0.9, 0.7), 0.8))
		"wardrobe":
			ObjectRegistry.box(root, Vector3(1.2, 2.0, 0.55), Vector3(0, 1.0, 0), ObjectRegistry.mat(Color(0.52, 0.4, 0.3)))
			ObjectRegistry.box(root, Vector3(0.02, 1.9, 0.02), Vector3(0, 1.0, 0.28), ObjectRegistry.mat(Color(0.25, 0.2, 0.15)))
		"coffee":
			ObjectRegistry.box(root, Vector3(1.0, 0.05, 0.5), Vector3(0, 0.38, 0), wood)
			for sx in [-0.45, 0.45]:
				for sz in [-0.2, 0.2]:
					ObjectRegistry.box(root, Vector3(0.05, 0.36, 0.05), Vector3(sx, 0.18, sz), wood)
	return root
