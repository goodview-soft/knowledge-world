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
var _was_third := true
var _legs: Array = []          # [{quad, vp, cam}] : 0 = vue depuis la ville, 1 = vue depuis l'appartement
var _shader: Shader
var street_doors := {}         # idx bâtiment -> HingedDoor (remplace l'instance MultiMesh de la façade)
var _pres := {}
var _poll := 0.0


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
	var plan: Dictionary = b["plan"]
	var rv := Vector3(n.z, 0.0, -n.x)
	var p: Vector3 = (b["pos"] as Vector3) + rv * (float(plan["entrance"]["x"]) - float(plan["w"]) * 0.5) + n * (face + 0.05)
	return city.global_transform * Transform3D(Basis(Vector3.UP, atan2(n.x, n.z)), p)


## Battant animé de la porte d'entrée du bâtiment `bi` (créé à la demande ; masque l'instance MultiMesh).
func street_door(bi: int) -> HingedDoor:
	if street_doors.has(bi) and is_instance_valid(street_doors[bi]):
		return street_doors[bi]
	var d := HingedDoor.new().setup(1.3, 2.2, 0.1, city.details.door_color(bi), Color(0.22, 0.2, 0.18), 0.3)
	city.add_child(d)
	d.global_transform = door_xf_of(city.buildings[bi])
	city.details.set_facade_door_visible(bi, false)
	street_doors[bi] = d
	return d


## Ouvre la porte du bâtiment `bi` sur l'appartement de `who`.
func open_for(bi: int, who: String, color: Color, present: bool, apartment_id := "") -> void:
	building = bi
	a_xf = door_xf_of(city.buildings[bi])
	var plan: Dictionary = city.buildings[bi]["plan"]
	if apartment_id == "" or not plan["apartments"].has(apartment_id):
		apartment_id = str(plan["apartment_ids"][absi(who.hash()) % (plan["apartment_ids"] as Array).size()])
	apt.generate_building(plan, apartment_id, color, present, who)
	active = true
	_pres.clear()
	_leg_quad(0, a_xf)
	_leg_quad(1, apt.door_xf())
	street_door(bi).swing(true)


func _leg_quad(k: int, xf: Transform3D) -> void:
	var q: MeshInstance3D = _legs[k]["quad"]
	q.global_transform = xf * Transform3D(Basis(), Vector3(0, ApartmentInterior.DOOR_H * 0.5, 0.14)) # devant la porte dessinée de la façade (épaisseur 0,12)
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
	if to_inside:
		if not is_inside(p):
			_was_third = p.third_person
		p.set_third_person(false, false) # intérieur : 1re personne forcée
	else:
		p.set_third_person(_was_third, false)
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
	var sd := street_door(building)
	if to_inside:
		sd.close_in(0.8)  # elle se referme derrière nous
	else:
		sd.swing(true, true)
		sd.close_in(1.2)


## Un habitant qui sort (ou rentre) fait jouer sa porte dans le couloir.
func _poll_residents(dt: float, inside: bool) -> void:
	_poll -= dt
	if _poll > 0.0 or not inside:
		return
	_poll = 1.0
	for aid in apt.door_nodes:
		if str(aid) == apt.apartment_id:
			continue
		var pr: bool = bool(get_parent().occupant_of_apt(building, str(aid))["present"])
		if _pres.has(aid) and _pres[aid] != pr:
			var d: HingedDoor = apt.door_nodes[aid]
			d.swing(true)
			d.close_in(2.0)
		_pres[aid] = pr


func _process(dt: float) -> void:
	if not active:
		return
	var p: KWPlayer = get_parent()._main_player()
	if p == null or p.cam == null:
		return
	var inside := is_inside(p)
	if inside and p.global_position.y < apt.global_position.y - 6.0: # filet : chute hors du bâtiment
		p.teleport(apt.global_position + Vector3(0, 0.05, 1.0), PI)
	if not inside and p.global_position.distance_to(a_xf.origin) > 14.0:
		close()
		return
	_cool -= dt
	var sd := street_door(building)
	_legs[0]["quad"].visible = inside or sd.openness() > 0.45
	_poll_residents(dt, inside)
	var acam: Camera3D = p.get_viewport().get_camera_3d()
	if acam == null:
		acam = p.cam
	var cx := acam.global_transform
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
			cam.fov = acam.fov
			cam.keep_aspect = acam.keep_aspect
	# traversée à pied
	if _cool > 0.0 or not p.enabled:
		return
	var src2 := apt.door_xf() if inside else a_xf
	var l := src2.affine_inverse() * p.global_position
	var toward := p.velocity.dot(-src2.basis.z) > 0.4
	if not inside and not sd.is_open:
		return
	if absf(l.x) < ApartmentInterior.DOOR_W * 0.5 and l.z > 0.0 and l.z < 0.55 and l.y > -0.5 and l.y < 1.2 and toward:
		traverse(p, not inside)


## E à l'intérieur : porte de rue, porte d'un appartement (y entrer) ou porte de l'appartement courant (retour couloir).
func interact_inside(p: KWPlayer, instant := false) -> bool:
	var plan: Dictionary = city.buildings[building]["plan"]
	var ox: float = float(plan["entrance"]["x"])
	var fh: float = float(plan["fh"])
	var lp := p.global_position - apt.global_position
	var f: int = clampi(int(floor((lp.y + 0.3) / fh)), 0, int(plan["floors"]) - 1)
	if f == 0 and absf(lp.x) < 1.4 and lp.z < 2.2:
		traverse(p, false)
		return true
	var px := lp.x + ox
	var best := ""
	var bd := 2.6
	for aid in plan["floors_data"][f]["apartments"]:
		var cd: Array = plan["apartments"][aid]["corridor_door"]
		var d := Vector2(px - float(cd[0]), lp.z - float(cd[1])).length()
		if d < bd:
			bd = d
			best = str(aid)
	if best == "":
		return false
	var a: Dictionary = plan["apartments"][best]
	var cd2: Array = a["corridor_door"]
	var ez: float = float(cd2[1])
	var cz := 0.0
	for r in a["rooms"]:
		cz += float((r["rect"] as Array)[1]) + float((r["rect"] as Array)[3]) * 0.5
	cz /= float((a["rooms"] as Array).size())
	var ia: float = 1.0 if cz > ez else -1.0 # direction vers l'appartement
	var in_apt: bool = (lp.z - ez) * ia > 0.0
	var tz: float
	var face: float
	var dn: HingedDoor = apt.door_nodes.get(best)
	if best == apt.apartment_id and in_apt:
		tz = ez - ia * 1.1 # retour au couloir, dos à la porte
		face = -ia
		p.teleport(apt.global_position + Vector3(float(cd2[0]) - ox, f * fh + 0.05, tz), PI if face > 0.0 else 0.0)
		_cool = 0.6
		if dn != null:
			dn.auto_close = 3.0
			dn.close_in(1.2) # la porte se referme derrière nous
		return true
	var oc: Dictionary = get_parent().occupant_of_apt(building, best)
	var mine: bool = str(oc["who"]) == "toi"
	if best != apt.apartment_id and not mine and not bool(oc["present"]):
		get_parent().toast("Fermé à clé — personne ne répond")
		return true
	var go := func() -> void:
		if best != apt.apartment_id:
			apt.generate_building(plan, best, oc["color"], bool(oc["present"]), str(oc["who"]))
		p.teleport(apt.global_position + Vector3(float(cd2[0]) - ox, f * fh + 0.05, ez + ia * 1.1), PI if ia > 0.0 else 0.0)
		_cool = 0.6
		if not mine:
			get_parent().toast("%s : « Ah, c'est toi ! Entre, entre, fais comme chez toi. »" % str(oc["who"]))
	if instant or best == apt.apartment_id:
		go.call()
		return true
	if not mine:
		get_parent().toast("Toc toc…")
	if dn != null:
		dn.swing(true)
	_cool = 1.0
	get_tree().create_timer(0.8 if not mine else 0.5).timeout.connect(go)
	return true
