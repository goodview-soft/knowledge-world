class_name RoomBuilder
extends RefCounted
## Génère la géométrie d'une salle à partir de ses données (taille, couleur).
## Aucune salle n'est codée à la main : tout passe par ce modèle réutilisable.

static func build(room: Dictionary, is_hub: bool) -> Node3D:
	var root := Node3D.new()
	var s: Array = room.size
	var w: float = s[0]
	var h: float = s[1]
	var d: float = s[2]
	var tint := Color(room.color)
	var wall_m := ObjectRegistry.mat(Color(0.84, 0.82, 0.78).lerp(tint, 0.15), 0.0, 0.95)
	var floor_m := ObjectRegistry.mat(Color(0.36, 0.33, 0.3).lerp(tint, 0.08), 0.0, 0.55)
	var ceil_m := ObjectRegistry.mat(Color(0.9, 0.89, 0.86), 0.0, 1.0)
	_slab(root, Vector3(w + 0.4, 0.2, d + 0.4), Vector3(0, -0.1, 0), floor_m)
	_slab(root, Vector3(w + 0.4, 0.2, d + 0.4), Vector3(0, h + 0.1, 0), ceil_m)
	_slab(root, Vector3(w, h, 0.2), Vector3(0, h / 2, -d / 2 - 0.1), wall_m)
	_slab(root, Vector3(w, h, 0.2), Vector3(0, h / 2, d / 2 + 0.1), wall_m)
	_slab(root, Vector3(0.2, h, d), Vector3(-w / 2 - 0.1, h / 2, 0), wall_m)
	_slab(root, Vector3(0.2, h, d), Vector3(w / 2 + 0.1, h / 2, 0), wall_m)
	# Gorges lumineuses (éclairage indirect) et plinthes.
	var cove := ObjectRegistry.mat(Color(1.0, 0.9, 0.76), 1.6)
	var base := ObjectRegistry.mat(Color(0.25, 0.24, 0.23))
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
			l.light_color = Color(1.0, 0.92, 0.82)
			l.light_energy = 0.75
			l.omni_range = maxf(w / nx, d / nz) * 1.25
			l.omni_attenuation = 0.8
			root.add_child(l)
	if is_hub:
		var ring := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 2.6
		cyl.bottom_radius = 2.6
		cyl.height = 0.04
		ring.mesh = cyl
		ring.material_override = ObjectRegistry.mat(Color(0.75, 0.72, 0.66), 0.0, 0.3)
		ring.position = Vector3(0, 0.02, 1.5)
		root.add_child(ring)
		ObjectRegistry.box(root, Vector3(w * 0.5, 0.02, 0.4), Vector3(0, h - 0.01, 0), ObjectRegistry.mat(Color(1.0, 0.93, 0.8), 1.2))
	return root


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
