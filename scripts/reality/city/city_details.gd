class_name CityDetails
extends Node3D
## Détails de ville pilotés par les données : portes numérotées, enseignes, marquages au sol,
## passages piétons, panneaux stop, feux, noms de rues. MultiMesh partout ; les textes
## (Label3D) ne s'affichent que près du joueur (visibility_range).

const TEXT_RANGE := 38.0
const HALF_ST := 5.0
const STOP_BACK := 6.5

var city: CityBuilder
var lights: Array = []        # {pos, axis}
var light_mat := [StandardMaterial3D.new(), StandardMaterial3D.new()]
var stop_signs := 0
var door_count := 0
var sign_count := 0


## Rue prioritaire ? (une rue sur `major_every`, centrée sur la place)
static func is_major(k: int, n: int, every: int) -> bool:
	return posmod(k - n / 2, maxi(every, 1)) == 0


func line_pos(axis: int, k: int) -> float:
	## axis 0 : rue Est-Ouest d'indice k (z fixe) ; axis 1 : rue Nord-Sud (x fixe)
	var n: int = city.rows_n if axis == 0 else city.cols_n
	return (k - n * 0.5) * city.pitch


func build(c: CityBuilder) -> void:
	city = c
	var cfg: Dictionary = c.config.get("traffic", {})
	var every: int = int(cfg.get("major_every", 3))
	_doors_and_signs()
	_markings()
	_crosswalks()
	_intersections(every)


func _mm(xfs: Array, mesh: Mesh, mat: Material, colors: Array = []) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not colors.is_empty()
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
		if mm.use_colors:
			mm.set_instance_color(i, colors[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _unlit(col: Color, emit := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.9
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = emit
	return m


func _label(text: String, p: Vector3, yaw: float, size: float, col: Color, face_cam := false) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.pixel_size = size
	l.font_size = 48
	l.outline_size = 8
	l.modulate = col
	l.position = p
	l.rotation.y = yaw
	if face_cam:
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.visibility_range_end = TEXT_RANGE
	l.visibility_range_end_margin = 4.0
	l.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(l)
	return l


static func normal_of(side: String) -> Vector3:
	match side:
		"n": return Vector3(0, 0, -1)
		"s": return Vector3(0, 0, 1)
		"w": return Vector3(-1, 0, 0)
	return Vector3(1, 0, 0)


## Porte au rez-de-chaussée, côté trottoir, avec numéro ; enseigne pour les lieux nommés.
func _doors_and_signs() -> void:
	var door_xf: Array = []
	var door_col: Array = []
	var aw_xf: Array = []
	var aw_col: Array = []
	var pal := [Color(0.35, 0.2, 0.12), Color(0.15, 0.3, 0.4), Color(0.4, 0.12, 0.12), Color(0.2, 0.35, 0.2), Color(0.25, 0.22, 0.2)]
	var role_col := {"cafe": Color(0.7, 0.25, 0.15), "boulangerie": Color(0.85, 0.65, 0.25), "bibliotheque": Color(0.2, 0.35, 0.6),
		"bureau": Color(0.3, 0.4, 0.5), "atelier": Color(0.5, 0.35, 0.2)}
	for b in city.buildings:
		var n := normal_of(str(b["side"]))
		var half: Vector3 = (b["size"] as Vector3) * 0.5
		var ns: bool = n.x == 0.0
		var face: float = half.z if ns else half.x
		var along_half: float = half.x if ns else half.z
		var dp: Vector3 = b["door_pos"]
		var bp: Vector3 = b["pos"]
		var t: float = (dp.x - bp.x) if ns else (dp.z - bp.z)
		t = clampf(t, -along_half + 1.6, along_half - 1.6)
		var p := Vector3(bp.x + (t if ns else 0.0), 0.0, bp.z + (0.0 if ns else t)) + n * (face + 0.05)
		var yaw := atan2(n.x, n.z)
		var bas := Basis(Vector3.UP, yaw)
		door_xf.append(Transform3D(bas, p + Vector3(0, 1.1, 0)))
		door_col.append(pal[int(b["idx"]) % pal.size()])
		door_count += 1
		var side_v := bas.x
		var num := str(b["address"]).split(" ")[0]
		_label(num, p + Vector3(0, 1.9, 0) + side_v * 1.0 + n * 0.08, yaw, 0.006, Color(1, 1, 1))
		if str(b["name"]) != "":
			var col: Color = role_col.get(str(b["role"]), Color(0.5, 0.4, 0.3))
			aw_xf.append(Transform3D(bas, p + Vector3(0, 2.75, 0.2) ))
			aw_col.append(col)
			_label(str(b["name"]), p + Vector3(0, 2.8, 0.32), yaw, 0.011, Color(1, 0.96, 0.85))
			sign_count += 1
	# lieux sur la place (sans bâtiment) : poteau + panneau
	for id in city.places:
		var pl: Dictionary = city.places[id]
		if pl.has("building"):
			continue
		var dp: Vector3 = pl["door_pos"]
		_label(str(pl["name"]), dp + Vector3(0, 2.6, 0), 0.0, 0.012, Color(1, 0.96, 0.85), true)
		sign_count += 1
	var dm := BoxMesh.new()
	dm.size = Vector3(1.3, 2.2, 0.12)
	var m := _unlit(Color.WHITE)
	m.vertex_color_use_as_albedo = true
	_mm(door_xf, dm, m, door_col)
	var am := BoxMesh.new()
	am.size = Vector3(4.2, 0.7, 0.5)
	_mm(aw_xf, am, m, aw_col)


## Ligne médiane en pointillés sur toutes les rues.
func _markings() -> void:
	var dashes: Array = []
	for axis in 2:
		var n: int = (city.rows_n if axis == 0 else city.cols_n) + 1
		var m_n: int = (city.cols_n if axis == 0 else city.rows_n)
		for k in n:
			var lp := line_pos(axis, k)
			for m in m_n:
				var c0: float = line_pos(1 - axis, m)
				# deux tirets entre les carrefours
				for q in [0.3, 0.5, 0.7]:
					var along: float = c0 + HALF_ST + (city.pitch - 2.0 * HALF_ST) * q
					var xf := Transform3D(Basis(Vector3.UP, 0.0 if axis == 0 else PI * 0.5), Vector3(along if axis == 0 else lp, 0.035, lp if axis == 0 else along))
					dashes.append(xf)
	var bm := BoxMesh.new()
	bm.size = Vector3(3.0, 0.01, 0.18)
	_mm(dashes, bm, _unlit(Color(0.95, 0.85, 0.3)))


## Passages piétons : bandes blanches sur chaque traversée du graphe piéton.
func _crosswalks() -> void:
	var xfs: Array = []
	for cr in city.crossings:
		var a: Vector3 = cr[0]
		var b: Vector3 = cr[1]
		var d := b - a
		var len := d.length()
		var dirv := d / len
		var cnt := int(len / 1.1)
		for i in cnt:
			var p := a + dirv * (1.0 + i * (len - 2.0) / maxf(cnt - 1, 1))
			xfs.append(Transform3D(Basis(Vector3.UP, atan2(dirv.x, dirv.z)), Vector3(p.x, 0.04, p.z)))
	var bm := BoxMesh.new()
	bm.size = Vector3(3.0, 0.01, 0.45)
	_mm(xfs, bm, _unlit(Color(0.95, 0.95, 0.95)))


## Carrefours : lignes d'arrêt, panneaux stop (voie secondaire), feux (deux rues prioritaires), noms de rues.
func _intersections(every: int) -> void:
	var stops: Array = []
	var poles: Array = []
	var lines: Array = []
	var lights_h: Array = []
	var sm := CylinderMesh.new()
	sm.top_radius = 0.38
	sm.bottom_radius = 0.38
	sm.height = 0.04
	sm.radial_segments = 8
	for kz in city.rows_n + 1:
		for kx in city.cols_n + 1:
			var c := Vector3(line_pos(1, kx), 0, line_pos(0, kz))
			var mz := is_major(kz, city.rows_n, every)   # rue E-O prioritaire
			var mx := is_major(kx, city.cols_n, every)   # rue N-S prioritaire
			var both := mz and mx
			_label("%s\n%s" % [city.street_name(1, kx), city.street_name(0, kz)], c + Vector3(HALF_ST - 0.6, 3.1, HALF_ST - 0.6), 0.0, 0.008, Color(0.85, 0.95, 1.0), true)
			# approches : (axe de déplacement, sens)
			for ap in [[0, 1], [0, -1], [1, 1], [1, -1]]:
				var axis: int = ap[0]
				var sg: int = ap[1]
				var prio: bool = mz if axis == 0 else mx
				# la voie d'arrivée n'existe que si le tronçon existe (toujours vrai dans la grille)
				var dirv := Vector3(sg, 0, 0) if axis == 0 else Vector3(0, 0, sg)
				var right := Vector3(0, 0, sg) if axis == 0 else Vector3(-sg, 0, 0)  # à droite du sens de marche
				var stop_pt := c - dirv * STOP_BACK
				var yaw := 0.0 if axis == 1 else PI * 0.5
				lines.append(Transform3D(Basis(Vector3.UP, yaw), stop_pt + right * 2.5 + Vector3(0, 0.04, 0)))
				var sp := stop_pt + right * 4.7
				if both:
					lights_h.append([sp, axis])
					poles.append(Transform3D(Basis(), sp + Vector3(0, 1.4, 0)))
				elif not prio:
					poles.append(Transform3D(Basis(), sp + Vector3(0, 1.1, 0)))
					stop_signs += 1
					var fd := -dirv
					stops.append(Transform3D(Basis(Vector3.UP, atan2(fd.x, fd.z)) * Basis(Vector3.RIGHT, PI * 0.5), sp + Vector3(0, 2.1, 0)))
	var lm := BoxMesh.new()
	lm.size = Vector3(4.5, 0.04, 0.35)
	_mm(lines, lm, _unlit(Color(0.95, 0.95, 0.95)))
	var pm := BoxMesh.new()
	pm.size = Vector3(0.1, 2.2, 0.1)
	for i in poles.size():
		poles[i] = Transform3D(Basis(), (poles[i] as Transform3D).origin)
	_mm(poles, pm, _unlit(Color(0.25, 0.25, 0.28)))
	_mm(stops, sm, _unlit(Color(0.8, 0.1, 0.1)))
	# feux : têtes colorées par axe (matériaux partagés, couleur changée par Traffic)
	for a in 2:
		var xfs: Array = []
		for lh in lights_h:
			if int(lh[1]) == a:
				xfs.append(Transform3D(Basis(), (lh[0] as Vector3) + Vector3(0, 2.5, 0)))
		var hm := BoxMesh.new()
		hm.size = Vector3(0.45, 0.45, 0.45)
		light_mat[a].emission_enabled = true
		light_mat[a].albedo_color = Color(0.1, 0.9, 0.2)
		light_mat[a].emission = Color(0.1, 0.9, 0.2)
		var mi := _mm(xfs, hm, light_mat[a])
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lights = lights_h


## Couleur des feux : phase 0 = axe 0 vert ; 1 = tout rouge ; 2 = axe 1 vert ; 3 = tout rouge.
func set_phase(ph: int) -> void:
	for a in 2:
		var green := (ph == 0 and a == 0) or (ph == 2 and a == 1)
		var col := Color(0.1, 0.9, 0.2) if green else Color(0.95, 0.12, 0.1)
		light_mat[a].albedo_color = col
		light_mat[a].emission = col
