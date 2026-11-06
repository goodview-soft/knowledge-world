class_name DoorPortals
extends Node3D
## Portes d'immeubles vers l'appartement visitable : effet portail (caméra virtuelle + SubViewport
## échantillonné en SCREEN_UV, comme portal_system) dans les deux sens, traversée à pied.

const QUAD_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D view_tex : source_color, filter_linear;
void fragment() { ALBEDO = texture(view_tex, SCREEN_UV).rgb; }
"""
const FLIP := Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
const INSIDE_Y := -250.0

var apt: ApartmentInterior
var city: CityBuilder
var active := false
var a_xf := Transform3D()      # porte de la ville (global, +Z vers la rue)
var building := -1
var _cool := 0.0
var _legs: Array = []          # [{quad, vp, cam}] : 0 = vue depuis la ville, 1 = vue depuis l'appartement
var _shader: Shader


func setup(c: CityBuilder, apartment: ApartmentInterior) -> void:
	city = c
	apt = apartment
	_shader = Shader.new()
	_shader.code = QUAD_SHADER
	for k in 2:
		var leg := {}
		var vp := SubViewport.new()
		vp.size = Vector2i(640, 360)
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(vp)
		var cam := Camera3D.new()
		cam.cull_mask = 1
		cam.near = 0.05
		cam.far = 150.0
		vp.add_child(cam)
		cam.current = true
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(ApartmentInterior.DOOR_W, ApartmentInterior.DOOR_H)
		q.mesh = qm
		q.layers = 2
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var m := ShaderMaterial.new()
		m.shader = _shader
		m.set_shader_parameter("view_tex", vp.get_texture())
		q.material_override = m
		q.visible = false
		add_child(q)
		leg = {"quad": q, "vp": vp, "cam": cam}
		_legs.append(leg)


## Transform global de la porte (au sol) d'un bâtiment de la ville.
func door_xf_of(b: Dictionary) -> Transform3D:
	var n := CityDetails.normal_of(str(b["side"]))
	var half: Vector3 = (b["size"] as Vector3) * 0.5
	var ns: bool = n.x == 0.0
	var face: float = half.z if ns else half.x
	var along_half: float = half.x if ns else half.z
	var dp: Vector3 = b["door_pos"]
	var bp: Vector3 = b["pos"]
	var t: float = (dp.x - bp.x) if ns else (dp.z - bp.z)
	t = clampf(t, -along_half + 1.6, along_half - 1.6)
	var p := Vector3(bp.x + (t if ns else 0.0), 0.0, bp.z + (0.0 if ns else t)) + n * (face + 0.05)
	return city.global_transform * Transform3D(Basis(Vector3.UP, atan2(n.x, n.z)), p)


## Ouvre la porte du bâtiment `bi` sur l'appartement de `who`.
func open_for(bi: int, who: String, color: Color, present: bool) -> void:
	building = bi
	a_xf = door_xf_of(city.buildings[bi])
	apt.generate(who, color, present)
	active = true
	_leg_quad(0, a_xf)
	_leg_quad(1, apt.door_xf())


func _leg_quad(k: int, xf: Transform3D) -> void:
	var q: MeshInstance3D = _legs[k]["quad"]
	q.global_transform = xf * Transform3D(Basis(), Vector3(0, ApartmentInterior.DOOR_H * 0.5, 0.03))
	q.visible = true


func close() -> void:
	active = false
	for l in _legs:
		l["quad"].visible = false
		(l["vp"] as SubViewport).render_target_update_mode = SubViewport.UPDATE_DISABLED


func is_inside(p: Node3D) -> bool:
	return p.global_position.y < INSIDE_Y


## Traverse la porte en conservant position/orientation relatives.
func traverse(p: KWPlayer, to_inside: bool) -> void:
	var src := a_xf if to_inside else apt.door_xf()
	var dst := apt.door_xf() if to_inside else a_xf
	var m := dst * FLIP * src.affine_inverse()
	var xf := m * p.global_transform
	var local := dst.affine_inverse() * xf.origin
	if not to_inside:
		local.z = 0.9
	local.y = 0.05
	p.global_position = dst * local
	p.rotation = Vector3(0, xf.basis.get_euler().y, 0)
	p.velocity = m.basis * p.velocity
	_cool = 0.6


func _process(dt: float) -> void:
	if not active:
		return
	var p: KWPlayer = get_parent()._main_player()
	if p == null or p.cam == null:
		return
	var inside := is_inside(p)
	if not inside and p.global_position.distance_to(a_xf.origin) > 14.0:
		close()
		return
	_cool -= dt
	var cx := p.cam.global_transform
	var vsz := p.get_viewport().get_visible_rect().size
	for k in 2:
		var src := a_xf if k == 0 else apt.door_xf()
		var dst := apt.door_xf() if k == 0 else a_xf
		var near := (k == 1) == inside
		var leg: Dictionary = _legs[k]
		var vp: SubViewport = leg["vp"]
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if near else SubViewport.UPDATE_DISABLED
		if near:
			var sz := Vector2i(maxi(int(vsz.x * 0.6), 64), maxi(int(vsz.y * 0.6), 64))
			if vp.size != sz:
				vp.size = sz
			var cam: Camera3D = leg["cam"]
			cam.global_transform = dst * FLIP * src.affine_inverse() * cx
			cam.fov = p.cam.fov
	# traversée à pied
	if _cool > 0.0 or not p.enabled:
		return
	var src2 := apt.door_xf() if inside else a_xf
	var l := src2.affine_inverse() * p.global_position
	var toward := p.velocity.dot(-src2.basis.z) > 0.4
	if absf(l.x) < ApartmentInterior.DOOR_W * 0.5 and l.z > 0.0 and l.z < 0.55 and l.y > -0.5 and l.y < 1.2 and toward:
		traverse(p, not inside)
