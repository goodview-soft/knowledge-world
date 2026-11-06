class_name RoomBuilder
extends RefCounted
## Génère la géométrie d'une salle à partir de ses données. Champs optionnels de
## personnalisation (rétrocompatibles) : wall_color, floor_color, ceil_color,
## floor_mat, light, light_energy. Aucune salle n'est codée à la main.

const MOOD_COLORS := {"chaude": Color(1.0, 0.86, 0.7), "neutre": Color(1.0, 0.96, 0.9), "froide": Color(0.84, 0.91, 1.0), "tamisee": Color(1.0, 0.76, 0.55)}
const MOOD_ENERGY := {"chaude": 0.8, "neutre": 0.9, "froide": 1.0, "tamisee": 0.4}
## Matériau du sol : [rugosité, motif].
const FLOOR_ROUGH := {"bois": 0.55, "beton": 0.9, "moquette": 1.0, "carrelage": 0.25, "marbre": 0.12, "uni": 0.6}
static var _tex_cache := {}


## Valeurs effectives d'une salle (défauts dérivés de la teinte pour les anciennes salles).
static func style_of(room: Dictionary) -> Dictionary:
	var tint := Color(room.get("color", "#cfc8bc"))
	return {
		"wall_color": Color(room.get("wall_color", Color(0.84, 0.82, 0.78).lerp(tint, 0.15).to_html(false))),
		"floor_color": Color(room.get("floor_color", Color(0.36, 0.33, 0.3).lerp(tint, 0.08).to_html(false))),
		"ceil_color": Color(room.get("ceil_color", "#e6e3dc")),
		"floor_mat": str(room.get("floor_mat", "uni")),
		"light": str(room.get("light", "chaude")),
		"light_energy": float(room.get("light_energy", 1.0)),
	}


static func light_color(st: Dictionary) -> Color:
	return MOOD_COLORS.get(st.light, MOOD_COLORS.chaude)


static func light_energy(st: Dictionary) -> float:
	return float(MOOD_ENERGY.get(st.light, 0.8)) * float(st.light_energy)


static func build(room: Dictionary, is_hub: bool) -> Node3D:
	var root := Node3D.new()
	var s: Array = room["size"]
	var w: float = s[0]
	var h: float = s[1]
	var d: float = s[2]
	var st := style_of(room)
	var lc := light_color(st)
	var le := light_energy(st)
	var wall_m := ObjectRegistry.mat(st.wall_color, 0.0, 0.95)
	var floor_m := floor_material(st.floor_mat, st.floor_color)
	var ceil_m := ObjectRegistry.mat(st.ceil_color, 0.0, 1.0)
	_slab(root, Vector3(w + 0.4, 0.2, d + 0.4), Vector3(0, -0.1, 0), floor_m)
	_slab(root, Vector3(w + 0.4, 0.2, d + 0.4), Vector3(0, h + 0.1, 0), ceil_m)
	_slab(root, Vector3(w, h, 0.2), Vector3(0, h / 2, -d / 2 - 0.1), wall_m)
	_slab(root, Vector3(w, h, 0.2), Vector3(0, h / 2, d / 2 + 0.1), wall_m)
	_slab(root, Vector3(0.2, h, d), Vector3(-w / 2 - 0.1, h / 2, 0), wall_m)
	_slab(root, Vector3(0.2, h, d), Vector3(w / 2 + 0.1, h / 2, 0), wall_m)
	# Gorges lumineuses (éclairage indirect) et plinthes.
	var cove := ObjectRegistry.mat(lc, 1.6 * clampf(le / 0.8, 0.2, 2.0))
	var base := ObjectRegistry.mat(st.wall_color.darkened(0.55))
	for side in [[Vector3(w - 0.6, 0.03, 0.08), Vector3(0, h - 0.2, -d / 2 + 0.06)], [Vector3(w - 0.6, 0.03, 0.08), Vector3(0, h - 0.2, d / 2 - 0.06)],
			[Vector3(0.08, 0.03, d - 0.6), Vector3(-w / 2 + 0.06, h - 0.2, 0)], [Vector3(0.08, 0.03, d - 0.6), Vector3(w / 2 - 0.06, h - 0.2, 0)]]:
		ObjectRegistry.box(root, side[0], side[1], cove)
		var bsz: Vector3 = side[0]
		ObjectRegistry.box(root, Vector3(bsz.x + 0.6 if bsz.x > 1 else 0.02, 0.08, bsz.z + 0.6 if bsz.z > 1 else 0.02), Vector3(side[1].x, 0.04, side[1].z), base)
	var nx := maxi(1, roundi(w / 7.0))
	var nz := maxi(1, roundi(d / 7.0))
	for i in nx:
		for k in nz:
			var l := OmniLight3D.new()
			l.position = Vector3(-w / 2 + w / nx * (i + 0.5), h - 0.7, -d / 2 + d / nz * (k + 0.5))
			l.light_color = lc
			l.light_energy = 0.95 * le
			l.omni_range = maxf(w / nx, d / nz) * 1.25 + h * 0.2
			l.omni_attenuation = 0.8
			root.add_child(l)
	if is_hub:
		var ring := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 2.6
		cyl.bottom_radius = 2.6
		cyl.height = 0.04
		ring.mesh = cyl
		ring.material_override = ObjectRegistry.mat(st.floor_color.lightened(0.35), 0.0, 0.3)
		ring.position = Vector3(0, 0.02, 1.5)
		root.add_child(ring)
		ObjectRegistry.box(root, Vector3(w * 0.5, 0.02, 0.4), Vector3(0, h - 0.01, 0), ObjectRegistry.mat(lc, 1.2))
	return root


## Matériau de sol : couleur + rugosité + motif procédural (triplanaire, 1 motif / 2 m).
static func floor_material(kind: String, col: Color) -> StandardMaterial3D:
	var m := ObjectRegistry.mat(col, 0.0, float(FLOOR_ROUGH.get(kind, 0.6)))
	var tex := _pattern(kind)
	if tex:
		m.albedo_texture = tex
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3(0.5, 0.5, 0.5)
	if kind == "marbre":
		m.metallic_specular = 0.7
	return m


static func _pattern(kind: String) -> Texture2D:
	if kind == "uni" or not FLOOR_ROUGH.has(kind):
		return null
	if _tex_cache.has(kind):
		return _tex_cache[kind]
	var n := 128
	var im := Image.create(n, n, true, Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.seed = 7
	match kind:
		"bois":
			noise.frequency = 0.02
			for y in n:
				var plank := y / 16
				var off := (plank * 37) % n
				for x in n:
					var g := 0.86 + 0.14 * noise.get_noise_2d((x + off) * 0.25, y * 4.0)
					g += 0.05 * sin(float(plank) * 2.3)
					if y % 16 == 0 or (x + off) % n == 0:
						g *= 0.7
					im.set_pixel(x, y, Color(g, g, g))
		"beton":
			noise.frequency = 0.08
			for y in n:
				for x in n:
					var g := 0.88 + 0.12 * noise.get_noise_2d(x, y) + randf_range(-0.03, 0.03)
					im.set_pixel(x, y, Color(g, g, g))
		"moquette":
			for y in n:
				for x in n:
					var g := 0.9 + randf_range(-0.08, 0.08)
					im.set_pixel(x, y, Color(g, g, g))
		"carrelage":
			for y in n:
				for x in n:
					var joint := x % 32 < 1 or y % 32 < 1
					var g := 0.72 if joint else 0.97 - 0.02 * float((x / 32 + y / 32) % 2)
					im.set_pixel(x, y, Color(g, g, g))
		"marbre":
			noise.frequency = 0.03
			noise.fractal_octaves = 4
			for y in n:
				for x in n:
					var v := absf(sin((x + y) * 0.05 + noise.get_noise_2d(x, y) * 6.0))
					var g := 0.84 + 0.16 * pow(v, 0.3)
					im.set_pixel(x, y, Color(g, g, g))
	im.generate_mipmaps()
	var tex := ImageTexture.create_from_image(im)
	_tex_cache[kind] = tex
	return tex


static func _slab(parent: Node3D, size: Vector3, center: Vector3, m: Material) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.position = center
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(cs)
	ObjectRegistry.box(body, size, Vector3.ZERO, m)
	parent.add_child(body)
