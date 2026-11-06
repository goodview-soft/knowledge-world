class_name PosterView
extends RefCounted
## Rendu 3D d'un poster : image importée (user://images/…), cadre optionnel.

static var _cache := {}


static func texture_for(path: String) -> Texture2D:
	if path == "" or not FileAccess.file_exists(path):
		return null
	if _cache.has(path):
		return _cache[path]
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		return null
	if maxi(img.get_width(), img.get_height()) > 2048:
		var k := 2048.0 / maxi(img.get_width(), img.get_height())
		img.resize(int(img.get_width() * k), int(img.get_height() * k), Image.INTERPOLATE_LANCZOS)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_cache[path] = tex
	return tex


static func build(root: Node3D, o: Dictionary, s: Vector3) -> void:
	var c: Dictionary = o.get("content", {})
	var framed: bool = c.get("frame", true)
	var border := 0.035 if framed else 0.0
	if framed:
		ObjectRegistry.box(root, s, Vector3(0, s.y / 2, 0), ObjectRegistry.mat(ObjectRegistry.style_color(o, "primary", Color(0.12, 0.12, 0.13)), 0.0, 0.5))
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(s.x - border * 2.0, s.y - border * 2.0)
	q.mesh = qm
	q.position = Vector3(0, s.y / 2, s.z / 2 + 0.002)
	var m := StandardMaterial3D.new()
	m.roughness = 0.6
	var tex := texture_for(str(c.get("image", "")))
	if tex != null:
		m.albedo_texture = tex
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	else:
		m.albedo_color = Color(0.85, 0.83, 0.8)
		ObjectRegistry.label(root, "Poster\nE : choisir une image", Vector3(0, s.y / 2, s.z / 2 + 0.006), s.x * 0.8, 30)
	q.material_override = m
	root.add_child(q)
