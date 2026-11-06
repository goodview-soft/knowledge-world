class_name StructureKit
extends RefCounted
## Structures de construction : murs tracés, sols/planchers, escaliers.
## Matériaux à motifs procéduraux plaqués en coordonnées MONDE (triplanaire) :
## les motifs se raccordent sans couture d'une pièce à l'autre.

const LEVEL_H := 3.0
const GRID := 0.5
const MATERIALS := {
	"enduit": {"label": "Enduit", "color": "#e6e1d8", "rough": 0.95},
	"brique": {"label": "Brique", "color": "#b5654a", "rough": 0.9},
	"bois": {"label": "Bois", "color": "#a87a52", "rough": 0.7},
	"carrelage": {"label": "Carrelage", "color": "#dedbd4", "rough": 0.35},
	"pierre": {"label": "Pierre", "color": "#9c968c", "rough": 0.9},
	"beton": {"label": "Béton", "color": "#a9a7a2", "rough": 0.8},
	"marbre": {"label": "Marbre", "color": "#ece9e4", "rough": 0.2},
	"sombre": {"label": "Sombre", "color": "#3a3a40", "rough": 0.6},
}
const MAT_ORDER := ["enduit", "brique", "bois", "carrelage", "pierre", "beton", "marbre", "sombre"]

static var _tex_cache := {}
static var _mat_cache := {}


static func material_of(o: Dictionary) -> String:
	var st: Dictionary = o.get("params", {}).get("style", {})
	var m := str(st.get("material", "bois" if o.type == "struct_floor" or o.type == "stairs" else "enduit"))
	return m if MATERIALS.has(m) else "enduit"


static func color_of(o: Dictionary) -> Color:
	var st: Dictionary = o.get("params", {}).get("style", {})
	if st.has("primary"):
		return Color(st.primary)
	return Color(MATERIALS[material_of(o)].color)


static func make_material(mat_id: String, col: Color) -> StandardMaterial3D:
	var key := mat_id + col.to_html()
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.albedo_texture = texture(mat_id)
	m.roughness = MATERIALS[mat_id].rough
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(0.5, 0.5, 0.5) # une texture = 2 m
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_mat_cache[key] = m
	return m


## Textures en niveaux de gris (teintées par la couleur choisie), 256 px = 2 m.
static func texture(mat_id: String) -> Texture2D:
	if _tex_cache.has(mat_id):
		return _tex_cache[mat_id]
	var n := 256
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(mat_id)
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.05
	match mat_id:
		"brique":
			var bh := 16 # 25 cm → 32 px ; briques 12,5 cm de haut ≈ 16 px
			var bw := 32
			for y in n:
				var row := y / bh
				var off := (bw / 2) * (row % 2)
				for x in n:
					var col_i := ((x + off) / bw)
					rng.seed = row * 977 + col_i * 131
					var base := 0.78 + rng.randf_range(-0.1, 0.08)
					var mortar := (y % bh) < 2 or ((x + off) % bw) < 2
					var v := 1.25 if mortar else base + noise.get_noise_2d(x * 3.0, y * 3.0) * 0.05
					img.set_pixel(x, y, Color(v, v, v))
		"bois":
			var pw := 22
			for y in n:
				for x in n:
					var plank := x / pw
					rng.seed = plank * 733 + (y + plank * 61) / 128
					var tone := 0.85 + rng.randf_range(-0.12, 0.1)
					var grain := sin((y + noise.get_noise_2d(x * 2.0, y * 0.3) * 40.0) * 0.35) * 0.04
					var joint := (x % pw) < 1 or ((y + plank * 61) % 128) < 1
					var v := 0.55 if joint else tone + grain
					img.set_pixel(x, y, Color(v, v, v))
		"carrelage":
			var tw := 64
			for y in n:
				for x in n:
					rng.seed = (y / tw) * 17 + (x / tw) * 3
					var v := 1.0 if (x % tw) < 2 or (y % tw) < 2 else 0.92 + rng.randf_range(-0.03, 0.03) + noise.get_noise_2d(x, y) * 0.02
					if (x % tw) < 2 or (y % tw) < 2:
						v = 0.72
					img.set_pixel(x, y, Color(v, v, v))
		"pierre":
			var cell := FastNoiseLite.new()
			cell.noise_type = FastNoiseLite.TYPE_CELLULAR
			cell.frequency = 0.035
			cell.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
			var id_n := FastNoiseLite.new()
			id_n.noise_type = FastNoiseLite.TYPE_CELLULAR
			id_n.frequency = 0.035
			id_n.cellular_return_type = FastNoiseLite.RETURN_CELL_VALUE
			for y in n:
				for x in n:
					var e := cell.get_noise_2d(x, y)
					var v := 0.8 + id_n.get_noise_2d(x, y) * 0.12 + noise.get_noise_2d(x * 4.0, y * 4.0) * 0.05
					if e > -0.75:
						v *= 0.95
					if e < -0.92:
						v = 0.55
					img.set_pixel(x, y, Color(v, v, v))
		"marbre":
			for y in n:
				for x in n:
					var t := sin((x + y) * 0.04 + noise.get_noise_2d(x * 1.5, y * 1.5) * 6.0)
					var v := 0.93 - pow(absf(t), 8.0) * 0.25
					img.set_pixel(x, y, Color(v, v, v))
		_:
			var amp := 0.06 if mat_id == "beton" else 0.03
			for y in n:
				for x in n:
					var v := 0.9 + noise.get_noise_2d(x * 2.0, y * 2.0) * amp + noise.get_noise_2d(x * 8.0, y * 8.0) * amp * 0.5
					img.set_pixel(x, y, Color(v, v, v))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_tex_cache[mat_id] = tex
	return tex

# ------------------------------------------------------------------ pièces

## Marches d'un escalier droit (un étage) : [taille, centre] dans le repère de l'objet.
static func stair_steps(scl := Vector3.ONE) -> Array:
	var count := 15
	var rise := LEVEL_H / count
	var run := 0.3
	var w := 1.1 * scl.x
	var out := []
	for i in count:
		var h := rise * (i + 1)
		out.append({"size": Vector3(w, h, run), "center": Vector3(0, h / 2.0, -run * (i + 0.5) + count * run / 2.0)})
	return out


## Collision d'un escalier : une rampe invisible (montée fluide) sous les marches.
static func stair_ramp(scl := Vector3.ONE) -> Array:
	var run := 4.5
	var h := LEVEL_H
	var length := sqrt(run * run + h * h)
	var ang := atan2(h, run)
	var n := Vector3(0, cos(ang), sin(ang))
	var center := Vector3(0, h / 2.0, 0.3) - n * 0.05
	return [{"size": Vector3(1.1 * scl.x, 0.1, length), "center": center, "rot": Vector3(ang, 0, 0)}]


static func build(root: Node3D, o: Dictionary, s: Vector3) -> void:
	var m := make_material(material_of(o), color_of(o))
	match o.type:
		"struct_wall", "struct_floor":
			ObjectRegistry.box(root, s, Vector3(0, s.y / 2.0, 0), m)
		"stairs":
			for st in stair_steps():
				ObjectRegistry.box(root, st.size, st.center, m)
			# Limons latéraux.
			var side := ObjectRegistry.mat(Color(0.22, 0.22, 0.24), 0.0, 0.5)
			for x in [-0.58, 0.58]:
				var lm := ObjectRegistry.box(root, Vector3(0.04, 0.2, 4.9), Vector3(x, LEVEL_H / 2.0, 0), side)
				lm.rotation.x = atan2(LEVEL_H, 4.5)
