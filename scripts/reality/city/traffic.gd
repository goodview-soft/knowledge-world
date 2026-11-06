class_name Traffic
extends Node3D
## Voitures stylisées sur la grille, conduite à droite, sans physique : déplacement simulé.
## Feux aux carrefours de deux rues prioritaires, stop sur les voies secondaires,
## distance de sécurité avec le véhicule devant. Positions locales à la ville.

const HALF_ST := CityDetails.HALF_ST
const STOP_BACK := CityDetails.STOP_BACK
const LANE := 2.5
const COLORS := ["#c0392b", "#2e86c1", "#f1c40f", "#27ae60", "#ecf0f1", "#34495e", "#e67e22", "#8e44ad", "#7f8c8d", "#16a085"]

var city: CityBuilder
var cars: Array = []            # Dictionary : voir _spawn
var speed := 6.0
var every := 3
var cycle := [6.0, 2.0]
var phase := 0
var _phase_t := 0.0
var rng := RandomNumberGenerator.new()


func setup(c: CityBuilder) -> void:
	city = c
	var cfg: Dictionary = c.config.get("traffic", {})
	speed = float(cfg.get("speed", 6.0))
	every = int(cfg.get("major_every", 3))
	cycle = cfg.get("light_cycle", [6.0, 2.0])
	rng.seed = int(c.config.get("seed", 1)) + 99
	for i in int(cfg.get("count", 0)):
		_spawn(i)


func _n(axis: int) -> int:
	## nombre d'intersections - 1 le long de l'axe de déplacement
	return city.cols_n if axis == 0 else city.rows_n


func _cpos(axis: int, m: int) -> float:
	## coordonnée du carrefour m le long de l'axe de déplacement
	return (m - _n(axis) * 0.5) * city.pitch


func _lpos(axis: int, k: int) -> float:
	## coordonnée fixe de la rue k (axe 0 : z ; axe 1 : x)
	var n: int = city.rows_n if axis == 0 else city.cols_n
	return (k - n * 0.5) * city.pitch


func _spawn(i: int) -> void:
	var car := {"axis": rng.randi() % 2, "sg": 1 if rng.randf() < 0.5 else -1, "turn": false, "wait": 0.0, "v": 0.0, "stuck": 0.0,
		"ok": false, "t": 0.0}
	for tries in 40:
		car["axis"] = rng.randi() % 2
		car["sg"] = 1 if rng.randf() < 0.5 else -1
		var nl: int = (city.rows_n if car["axis"] == 0 else city.cols_n) + 1
		car["k"] = rng.randi() % nl
		car["m"] = rng.randi_range(1, _n(car["axis"]) - 1) if car["sg"] > 0 else rng.randi_range(1, _n(car["axis"]) - 1)
		car["s"] = _cpos(car["axis"], car["m"]) - car["sg"] * rng.randf_range(14.0, 36.0)
		_place(car)
		var clear := true
		for o in cars:
			if (o["pos"] as Vector3).distance_to(car["pos"]) < 9.0:
				clear = false
		if clear:
			break
	var node := Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(COLORS[i % COLORS.size()])
	mat.roughness = 0.5
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.8, 0.6, 4.1)
	body.mesh = bm
	body.material_override = mat
	body.position.y = 0.55
	node.add_child(body)
	var cab := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(1.55, 0.5, 2.0)
	cab.mesh = cm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.15, 0.2, 0.28)
	cab.material_override = gm
	cab.position = Vector3(0, 1.05, 0.2)
	node.add_child(cab)
	add_child(node)
	car["node"] = node
	cars.append(car)
	_apply(car)


func _place(car: Dictionary) -> void:
	var a: int = car["axis"]
	var sg: int = car["sg"]
	var lp := _lpos(a, int(car["k"]))
	var lane: float = LANE * sg if a == 0 else -LANE * sg    # à droite du sens de marche
	car["dir"] = Vector3(sg, 0, 0) if a == 0 else Vector3(0, 0, sg)
	if a == 0:
		car["pos"] = Vector3(car["s"], 0.0, lp + lane)
	else:
		car["pos"] = Vector3(lp + lane, 0.0, car["s"])


func _apply(car: Dictionary) -> void:
	var n: Node3D = car["node"]
	n.position = car["pos"]
	var d: Vector3 = car["dir"]
	n.rotation.y = atan2(-d.x, -d.z)


func is_major_line(axis: int, k: int) -> bool:
	## rue de type `axis` d'indice k (axe 0 : E-O ; axe 1 : N-S)
	return CityDetails.is_major(k, city.rows_n if axis == 0 else city.cols_n, every)


func green_for(axis: int) -> bool:
	return (phase == 0 and axis == 0) or (phase == 2 and axis == 1)


func _controlled_lights(car: Dictionary) -> bool:
	## le prochain carrefour est-il à feux ? (la rue de la voiture et la rue transversale sont prioritaires)
	var a: int = car["axis"]
	return is_major_line(a, int(car["k"])) and is_major_line(1 - a, int(car["m"]))


func _blocked_ahead(car: Dictionary) -> float:
	## distance libre devant (m) jusqu'au véhicule gênant ; 99 si libre
	var best := 99.0
	var p: Vector3 = car["pos"]
	var d: Vector3 = car["dir"]
	for o in cars:
		if o == car:
			continue
		var to: Vector3 = (o["pos"] as Vector3) - p
		var f := to.dot(d)
		if f > 0.0 and f < 9.0:
			var side: float = absf(to.dot(Vector3(-d.z, 0, d.x)))
			if side < 1.7:
				best = minf(best, f - 4.2)
	return best


func _crossing_busy(car: Dictionary, c: Vector3) -> bool:
	for o in cars:
		if o == car:
			continue
		var d: float = (o["pos"] as Vector3).distance_to(c)
		if d < 6.0 and not (o["axis"] == car["axis"] and not o["turn"] and (o["v"] < 0.3) and d > 4.0):
			return true
		if d < 14.0 and o["axis"] != car["axis"] and not o["turn"] and float(o["v"]) > 1.0:
			var to: Vector3 = c - (o["pos"] as Vector3)
			if to.dot(o["dir"]) > 0.0 and is_major_line(int(o["axis"]), int(o["k"])):
				return true
	return false


func sim(dt: float) -> void:
	_phase_t += dt
	var durs := [cycle[0], cycle[1], cycle[0], cycle[1]]
	if _phase_t >= float(durs[phase]):
		_phase_t = 0.0
		phase = (phase + 1) % 4
		if city.details != null:
			city.details.set_phase(phase)
	for car in cars:
		_step(car, dt)
		_apply(car)


func _step(car: Dictionary, dt: float) -> void:
	if car["turn"]:
		_step_turn(car, dt)
		return
	var a: int = car["axis"]
	var sg: int = car["sg"]
	var m: int = car["m"]
	var cp := _cpos(a, m)
	var target := speed
	var dl: float = (cp - sg * STOP_BACK - float(car["s"])) * sg   # distance à la ligne d'arrêt
	var free := _blocked_ahead(car)
	if dl > -0.3:
		var cpt := Vector3(_cpos(a, m), 0, _lpos(a, int(car["k"]))) if a == 0 else Vector3(_lpos(a, int(car["k"])), 0, _cpos(a, m))
		var perm := true
		if _controlled_lights(car):
			perm = green_for(a)
		elif not is_major_line(a, int(car["k"])):
			# stop : marquer l'arrêt, puis passer si le carrefour est libre
			if dl < 0.8 and car["v"] < 0.2:
				car["wait"] = float(car["wait"]) + dt
			perm = float(car["wait"]) > 1.2 and not _crossing_busy(car, cpt)
		if not perm and dl < 14.0:
			target = minf(target, maxf(0.0, dl * 0.9))
		elif perm and dl < 0.0:
			car["wait"] = 0.0
	if free < 6.0:
		target = minf(target, maxf(0.0, free * 0.8))
	if target < 0.2 and car["v"] < 0.2:
		car["stuck"] = float(car["stuck"]) + dt
	else:
		car["stuck"] = 0.0
	if float(car["stuck"]) > 25.0 and dl < 1.0 and free > 1.0:
		car["wait"] = 99.0
		target = 2.0
	car["v"] = move_toward(float(car["v"]), target, (3.0 if target > car["v"] else 7.0) * dt)
	car["s"] = float(car["s"]) + sg * float(car["v"]) * dt
	_place(car)
	# franchissement de la ligne d'arrêt : choix de la manœuvre
	var nd: float = (cp - sg * STOP_BACK - float(car["s"])) * sg
	if nd <= 0.0 and dl > 0.0:
		_decide(car)


func _decide(car: Dictionary) -> void:
	var a: int = car["axis"]
	var sg: int = car["sg"]
	var m: int = car["m"]
	var k: int = car["k"]
	var opts: Array = []
	if m + sg >= 0 and m + sg <= _n(a):
		opts.append_array(["straight", "straight", "straight"])
	# tourner : nouvelle rue = m (axe 1-a), nouveau sens ±1 ; nouveau prochain carrefour = k + sg2
	var n2 := (city.rows_n if a == 0 else city.cols_n)
	for sg2 in [1, -1]:
		if k + sg2 >= 0 and k + sg2 <= n2:
			opts.append(sg2)
	if opts.is_empty():
		return
	var ch = opts[rng.randi() % opts.size()]
	if str(ch) == "straight":
		car["m"] = m + sg
		return
	var sg2: int = int(ch)
	var a2 := 1 - a
	var c := Vector3(_cpos(a, m), 0, _lpos(a, k)) if a == 0 else Vector3(_lpos(a, k), 0, _cpos(a, m))
	var p0: Vector3 = car["pos"]
	var d2 := Vector3(sg2, 0, 0) if a2 == 0 else Vector3(0, 0, sg2)
	var lane2: float = LANE * sg2 if a2 == 0 else -LANE * sg2
	# point de sortie : STOP_BACK après le centre, sur la voie de la nouvelle rue
	var p2 := c + d2 * STOP_BACK + (Vector3(0, 0, lane2) if a2 == 0 else Vector3(lane2, 0, 0))
	# point de contrôle : intersection des deux axes de voie
	var p1 := Vector3(p2.x, 0, p0.z) if a == 0 else Vector3(p0.x, 0, p2.z)
	car["turn"] = true
	car["t"] = 0.0
	car["bz"] = [p0, p1, p2]
	car["next"] = {"axis": a2, "sg": sg2, "k": m, "m": k + sg2}


func _step_turn(car: Dictionary, dt: float) -> void:
	var bz: Array = car["bz"]
	var len: float = ((bz[0] as Vector3).distance_to(bz[1]) + (bz[1] as Vector3).distance_to(bz[2])) * 0.85
	var free := _blocked_ahead(car)
	var target := 4.0 if free > 5.0 else 0.0
	car["v"] = move_toward(float(car["v"]), target, 5.0 * dt)
	var t: float = minf(1.0, float(car["t"]) + float(car["v"]) * dt / maxf(len, 1.0))
	car["t"] = t
	var q := (bz[0] as Vector3).lerp(bz[1], t)
	var r := (bz[1] as Vector3).lerp(bz[2], t)
	car["pos"] = q.lerp(r, t)
	var tang := ((bz[1] as Vector3) - (bz[0] as Vector3)).lerp((bz[2] as Vector3) - (bz[1] as Vector3), t)
	if tang.length() > 0.01:
		car["dir"] = tang.normalized()
	if t >= 1.0:
		var nx: Dictionary = car["next"]
		car["axis"] = nx["axis"]
		car["sg"] = nx["sg"]
		car["k"] = nx["k"]
		car["m"] = nx["m"]
		car["turn"] = false
		car["s"] = (car["pos"] as Vector3).x if car["axis"] == 0 else (car["pos"] as Vector3).z
		car["wait"] = 0.0
		_place(car)
