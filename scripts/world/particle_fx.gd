extends Node3D
## PARTICLE FX (autoload) — particules des portails/portes et aura du joueur.
## Autonome : suit Main (scène courante) sans dépendre de son code.
## - Chaque passage exhale des particules lumineuses (couleur de la salle cible).
## - Le joueur porte une aura (quelques lueurs) et un champ répulsif
##   (GPUParticlesAttractorSphere3D) qui écarte TOUTES les particules GPU du monde.
## - Cosmétiques (autoload Cosmetics) : style de l'aura, traînée de pas, style des émissions
##   de portails ; reconstruits à chaque changement d'équipement (CosmeticFX).

const PORTAL_AMOUNT := 70
const DOOR_AMOUNT := 28

var _emitters := {} # obj_id -> GPUParticles3D
var _signature := ""
var _room := ""
var _aura: GPUParticles3D # null si aucune aura équipée
var _trail: GPUParticles3D # null si aucune traînée
var _portal_style := ""
var _field: GPUParticlesAttractorSphere3D
var _mote_mesh: QuadMesh


func _ready() -> void:
	_mote_mesh = QuadMesh.new()
	_mote_mesh.size = Vector2(0.035, 0.035)
	_mote_mesh.material = _mote_material()
	_field = GPUParticlesAttractorSphere3D.new()
	_field.radius = 1.3
	_field.strength = -7.0
	_field.attenuation = 0.8
	add_child(_field)
	_rebuild_cosmetics()
	var cm = get_node_or_null("/root/Cosmetics")
	if cm:
		cm.changed.connect(_rebuild_cosmetics)


## Aura + traînée selon l'équipement ; les portails sont reconstruits au prochain _process.
func _rebuild_cosmetics() -> void:
	var cm = get_node_or_null("/root/Cosmetics")
	if _aura:
		_aura.queue_free()
		_aura = null
	if _trail:
		_trail.queue_free()
		_trail = null
	if cm == null:
		_aura = _make_aura()
		add_child(_aura)
		return
	var ap: Dictionary = cm.params_of("aura")
	if not ap.is_empty():
		var tint := Color(cm.aura_tint) if cm.aura_tint != "" else Color(0, 0, 0, 0)
		_aura = CosmeticFX.make_aura(ap, tint, cm.aura_density)
		add_child(_aura)
	var tp: Dictionary = cm.params_of("trail")
	if not tp.is_empty():
		_trail = CosmeticFX.make_trail(tp)
		add_child(_trail)
	_portal_style = cm.get_equipped("portal")
	_signature = "" # force la reconstruction des émetteurs de portails


func _main() -> Node:
	var m := get_tree().current_scene
	return m if m != null and "nodes" in m and "player" in m and m.player != null else null


func _process(_delta: float) -> void:
	var m := _main()
	if m == null:
		return
	var p: Node3D = m.player
	_field.global_position = p.global_position + Vector3(0, 1.0, 0)
	if _aura:
		_aura.global_position = p.global_position + Vector3(0, 1.0, 0)
	if _trail:
		_trail.global_position = p.global_position + Vector3(0, 0.04, 0)
		var cb := p as CharacterBody3D
		_trail.emitting = cb != null and cb.is_on_floor() and Vector2(cb.velocity.x, cb.velocity.z).length() > 0.6
	# Reconstruit les émetteurs si la salle, l'ensemble des passages ou le style change.
	var sig: String = m.current_room + "#" + _portal_style
	for id in m.nodes:
		var o: Dictionary = World.data.objects.get(id, {})
		if not o.is_empty() and o.type in ["door", "portal"]:
			sig += "|" + id + str(o.pos) + str(o.rot) + str(o.scale) + str(o.params.get("target_room", ""))
	if sig != _signature:
		_signature = sig
		_rebuild(m)
	for id in _emitters:
		var node = m.nodes.get(id)
		var e: GPUParticles3D = _emitters[id]
		if node != null and is_instance_valid(node):
			e.global_transform = node.global_transform
			e.visible = true
		else:
			e.visible = false


func _rebuild(m: Node) -> void:
	for e in _emitters.values():
		e.queue_free()
	_emitters.clear()
	for id in m.nodes:
		var o: Dictionary = World.data.objects.get(id, {})
		if o.is_empty() or not o.type in ["door", "portal"]:
			continue
		var t: String = o.params.get("target_room", "")
		var col := Color(World.data.rooms[t].color) if World.data.rooms.has(t) else Color(0.8, 0.8, 0.85)
		var e := _make_portal_emitter(o, col)
		var cm = get_node_or_null("/root/Cosmetics")
		if cm and cm.get_equipped("portal") != "":
			CosmeticFX.style_portal(e, e.process_material as ParticleProcessMaterial, cm.params_of("portal"), col,
				1.0 if o.type == "portal" else 0.7, 0.035)
		add_child(e)
		_emitters[id] = e

# ------------------------------------------------------------------ émetteurs

func _mote_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _soft_dot()
	mat.disable_receive_shadows = true
	return mat


static func _soft_dot() -> ImageTexture:
	var n := 32
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var d := Vector2(x - n / 2.0 + 0.5, y - n / 2.0 + 0.5).length() / (n / 2.0)
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	return ImageTexture.create_from_image(img)


static func _fade_ramp(col: Color, peak := 1.0) -> GradientTexture1D:
	var g := Gradient.new()
	g.set_color(0, Color(col, 0.0))
	g.set_color(1, Color(col, 0.0))
	g.add_point(0.2, Color(col.lightened(0.3), peak))
	g.add_point(0.7, Color(col, peak * 0.6))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	return gt


func _make_portal_emitter(o: Dictionary, col: Color) -> GPUParticles3D:
	var is_portal: bool = o.type == "portal"
	var scl := World.vec(o.scale)
	var s: Vector3 = ObjectRegistry.get_def(o.type).size * scl
	var e := GPUParticles3D.new()
	e.amount = PORTAL_AMOUNT if is_portal else DOOR_AMOUNT
	e.lifetime = 4.0 if is_portal else 3.0
	e.local_coords = false
	e.draw_pass_1 = _mote_mesh
	e.visibility_aabb = AABB(Vector3(-s.x, -0.5, -1.0), Vector3(s.x * 2.0, s.y + 2.0, 5.0))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(s.x * 0.38, s.y * 0.42, 0.02)
	e.position = Vector3.ZERO
	pm.emission_shape_offset = Vector3(0, s.y * 0.46, 0.05)
	pm.direction = Vector3(0, 0.25, 1)
	pm.spread = 35.0
	pm.initial_velocity_min = 0.08
	pm.initial_velocity_max = 0.35 if is_portal else 0.2
	pm.gravity = Vector3(0, 0.03, 0)
	pm.damping_min = 0.05
	pm.damping_max = 0.15
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 2.5
	pm.turbulence_influence_min = 0.05
	pm.turbulence_influence_max = 0.15
	pm.scale_min = 0.5
	pm.scale_max = 1.6 if is_portal else 1.1
	pm.color_ramp = _fade_ramp(col.lightened(0.2), 1.0 if is_portal else 0.7)
	pm.attractor_interaction_enabled = true
	e.process_material = pm
	return e


func _make_aura() -> GPUParticles3D:
	var e := GPUParticles3D.new()
	e.amount = 36
	e.lifetime = 2.6
	e.local_coords = false
	e.draw_pass_1 = _mote_mesh
	e.visibility_aabb = AABB(Vector3(-3, -2, -3), Vector3(6, 4, 6))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE
	pm.emission_sphere_radius = 0.75
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.02
	pm.initial_velocity_max = 0.08
	pm.gravity = Vector3(0, 0.05, 0)
	pm.orbit_velocity_min = 0.05
	pm.orbit_velocity_max = 0.12
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.4
	pm.scale_min = 0.4
	pm.scale_max = 0.9
	pm.color_ramp = _fade_ramp(Color(0.75, 0.88, 1.0), 0.45)
	pm.attractor_interaction_enabled = false # l'aura n'est pas repoussée par son propre champ
	e.process_material = pm
	return e
