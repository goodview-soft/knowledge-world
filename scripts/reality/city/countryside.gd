class_name Countryside
extends Node3D
## Campagne autour de la ville, pilotée par city.json["countryside"] et une graine :
## routes de campagne prolongeant les rues prioritaires, champs en motifs, fermes,
## arbres et collines d'horizon. MultiMesh partout (peu de nœuds).

var city: CityBuilder
var farm_count := 0
var tree_count := 0
var field_count := 0
var road_count := 0
var _rng := RandomNumberGenerator.new()
var _roads: Array = []   # Rect2 (x,z,w,h) à éviter


func build(c: CityBuilder) -> void:
	city = c
	var cfg: Dictionary = c.config.get("countryside", {})
	_rng.seed = int(cfg.get("seed", 1))
	var radius: float = float(cfg.get("radius", 900.0))
	_ground(radius)
	_country_roads(radius, int(c.config.get("traffic", {}).get("major_every", 3)))
	_fields(cfg, radius)
	_farms(int(cfg.get("farms", 6)))
	_trees(int(cfg.get("trees", 300)), radius)
	_hills(int(cfg.get("hills", 10)), radius)


func _mm(xfs: Array, mesh: Mesh, mat: Material, colors: Array = [], shadows := false) -> void:
	if xfs.is_empty():
		return
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
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _mat(col: Color, vcol := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 1.0
	m.vertex_color_use_as_albedo = vcol
	return m


func _ground(radius: float) -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(radius * 3.0, radius * 3.0)
	mi.mesh = pm
	mi.material_override = _mat(Color(0.45, 0.6, 0.32))
	mi.position.y = -0.09
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## Routes qui partent des rues prioritaires de la ville, dans les 4 directions.
func _country_roads(radius: float, every: int) -> void:
	var xfs: Array = []
	var half := city.extent + 5.0
	var width := 6.0
	for k in city.cols_n + 1:
		if CityDetails.is_major(k, city.cols_n, every):
			var x: float = (k - city.cols_n * 0.5) * city.pitch
			for sg in [-1, 1]:
				var len: float = radius - half
				var cz: float = sg * (half + len * 0.5 - 5.0)
				xfs.append(Transform3D(Basis.from_scale(Vector3(width, 1, len)), Vector3(x, 0.035, cz)))
				_roads.append(Rect2(x - width, cz - len * 0.5, width * 2.0, len))
				road_count += 1
	for k in city.rows_n + 1:
		if CityDetails.is_major(k, city.rows_n, every):
			var z: float = (k - city.rows_n * 0.5) * city.pitch
			for sg in [-1, 1]:
				var len2: float = radius - half
				var cx: float = sg * (half + len2 * 0.5 - 5.0)
				xfs.append(Transform3D(Basis.from_scale(Vector3(len2, 1, width)), Vector3(cx, 0.035, z)))
				_roads.append(Rect2(cx - len2 * 0.5, z - width, len2, width * 2.0))
				road_count += 1
	var pm := PlaneMesh.new()
	pm.size = Vector2(1, 1)
	_mm(xfs, pm, _mat(Color(0.42, 0.38, 0.32)))


func _on_road(x: float, z: float, margin := 0.0) -> bool:
	for r in _roads:
		if (r as Rect2).grow(margin).has_point(Vector2(x, z)):
			return true
	return false


## Champs : rectangles colorés par graine, un tiers avec sillons (bandes sombres).
func _fields(cfg: Dictionary, radius: float) -> void:
	var fs: Array = cfg.get("field", [60.0, 80.0])
	var fw: float = float(fs[0])
	var fh: float = float(fs[1])
	var pal: Array = cfg.get("palette", ["#8fb55a"])
	var xfs: Array = []
	var cols: Array = []
	var furrows: Array = []
	var inner := city.extent + 12.0
	var nx := int(radius * 0.9 / fw)
	var nz := int(radius * 0.9 / fh)
	for i in range(-nx, nx):
		for j in range(-nz, nz):
			var x := (i + 0.5) * fw
			var z := (j + 0.5) * fh
			if absf(x) < inner + fw * 0.5 and absf(z) < inner + fh * 0.5:
				continue
			if _on_road(x, z, fw * 0.5 + 4.0) and (absf(x) < 6.0 + fw * 0.5 or true):
				if _on_road(x, z, 7.0 + fw * 0.4):
					continue
			if _rng.randf() < 0.1:
				continue
			var w := fw * _rng.randf_range(0.7, 0.92)
			var h := fh * _rng.randf_range(0.7, 0.92)
			xfs.append(Transform3D(Basis.from_scale(Vector3(w, 1, h)), Vector3(x, -0.035, z)))
			var col := Color(str(pal[_rng.randi() % pal.size()]))
			cols.append(col.darkened(_rng.randf() * 0.12))
			field_count += 1
			if _rng.randf() < 0.35:
				var vert := _rng.randf() < 0.5
				var n := 7
				for q in n:
					var f := (q + 0.5) / n - 0.5
					var sz := Vector3(w * 0.04, 1, h) if vert else Vector3(w, 1, h * 0.04)
					var off := Vector3(f * w, 0.02, 0) if vert else Vector3(0, 0.02, f * h)
					furrows.append(Transform3D(Basis.from_scale(sz), Vector3(x, 0, z) + off))
	var pm := PlaneMesh.new()
	pm.size = Vector2(1, 1)
	_mm(xfs, pm, _mat(Color.WHITE, true), cols)
	_mm(furrows, pm, _mat(Color(0.34, 0.26, 0.17)))


func _free_spot(min_r: float, max_r: float) -> Vector3:
	for t in 60:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(min_r, max_r)
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
		if absf(p.x) < city.extent + 20.0 and absf(p.z) < city.extent + 20.0:
			continue
		if _on_road(p.x, p.z, 12.0):
			continue
		return p
	return Vector3(max_r, 0, max_r)


func _farms(n: int) -> void:
	var walls: Array = []
	var roofs: Array = []
	var wcol: Array = []
	var rm := PrismMesh.new()
	rm.size = Vector3(1, 1, 1)
	for i in n:
		var p := _free_spot(city.extent + 60.0, 600.0)
		var yaw := float(_rng.randi() % 4) * PI * 0.5
		for part in [[Vector3(10, 5, 8), Vector3.ZERO, Color(0.85, 0.8, 0.7)], [Vector3(14, 7, 10), Vector3(16, 0, 4), Color(0.6, 0.2, 0.15)]]:
			var sz: Vector3 = part[0]
			var off: Vector3 = part[1]
			var c := p + Basis(Vector3.UP, yaw) * off
			walls.append(Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(sz), c + Vector3(0, sz.y * 0.5, 0)))
			wcol.append(part[2])
			roofs.append(Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(sz.x * 1.1, sz.y * 0.45, sz.z * 1.1)), c + Vector3(0, sz.y + sz.y * 0.225, 0)))
		farm_count += 1
	var bm := BoxMesh.new()
	_mm(walls, bm, _mat(Color.WHITE, true), wcol, true)
	_mm(roofs, rm, _mat(Color(0.35, 0.18, 0.12)), [], true)


func _trees(n: int, radius: float) -> void:
	var trunks: Array = []
	var crowns: Array = []
	var ccol: Array = []
	for i in n:
		var p := _free_spot(city.extent + 20.0, radius * 0.8)
		var s := _rng.randf_range(0.8, 1.6)
		trunks.append(Transform3D(Basis.from_scale(Vector3(0.5 * s, 2.0 * s, 0.5 * s)), p + Vector3(0, s, 0)))
		crowns.append(Transform3D(Basis.from_scale(Vector3(3.2 * s, 4.0 * s, 3.2 * s)), p + Vector3(0, 2.0 * s + 2.0 * s, 0)))
		ccol.append(Color(0.2, 0.42 + _rng.randf() * 0.2, 0.2))
		tree_count += 1
	var tm := CylinderMesh.new()
	tm.top_radius = 0.5
	tm.bottom_radius = 0.5
	tm.height = 1.0
	tm.radial_segments = 6
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = 0.5
	cm.height = 1.0
	cm.radial_segments = 7
	_mm(trunks, tm, _mat(Color(0.35, 0.24, 0.15)))
	_mm(crowns, cm, _mat(Color.WHITE, true), ccol, true)


## Collines basses sur l'horizon.
func _hills(n: int, radius: float) -> void:
	var xfs: Array = []
	var cols: Array = []
	for i in n:
		var a := (i + _rng.randf() * 0.6) / n * TAU
		var r := radius * _rng.randf_range(0.97, 1.15)
		var w := _rng.randf_range(160.0, 320.0)
		var h := _rng.randf_range(40.0, 110.0)
		xfs.append(Transform3D(Basis.from_scale(Vector3(w, h, w * 0.7)).rotated(Vector3.UP, a), Vector3(cos(a) * r, 0, sin(a) * r)))
		cols.append(Color(0.42, 0.55, 0.5).lerp(Color(0.6, 0.7, 0.72), _rng.randf() * 0.5))
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 0.5   # demi-sphère aplatie
	sm.radial_segments = 12
	sm.rings = 6
	_mm(xfs, sm, _mat(Color.WHITE, true), cols)
