class_name RealityWorld
extends Node3D
## La « réalité » : pour l'instant un grand sol sobre, un ciel doux et un soleil.
## Placée très loin du palais mental (ORIGIN) pour ne jamais interférer avec lui.

const ORIGIN := Vector3(10000, 0, 0)
const ENV_PROPS := ["background_mode", "background_color", "ambient_light_source", "ambient_light_color",
	"ambient_light_energy", "ssao_enabled", "ssil_enabled", "fog_enabled"]

var sun: DirectionalLight3D
var city: CityBuilder
var director: BotDirector
var talk: BotTalk
var apartment: ApartmentInterior
var portals: DoorPortals
var player_home := -1
const APT_POS := Vector3(0, -500, 0) # local : global = (10000, -500, 0)
var _save_in := 10.0
var _hud: CanvasLayer
var _clock_label: Label

const FLOOR_SHADER := """
shader_type spatial;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 q = wp.xz / 2.0;
	vec2 g = abs(fract(q - 0.5) - 0.5) / fwidth(q);
	float line = 1.0 - min(min(g.x, g.y), 1.0);
	vec3 base = vec3(0.62, 0.63, 0.60);
	ALBEDO = mix(base, base * 0.8, line * 0.45);
	ROUGHNESS = 0.95;
}
"""


func _init() -> void:
	name = "RealityWorld"
	position = ORIGIN
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(2800, 2, 2800)
	cs.shape = bs
	cs.position.y = -1.0
	body.add_child(cs)
	add_child(body)
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(620, 620)
	mi.mesh = pm
	mi.position.y = -0.14 # couches de sol bien espacées (anti z-fighting)
	var sh := Shader.new()
	sh.code = FLOOR_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mi.material_override = mat
	add_child(mi)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -35, 0)
	sun.light_energy = 1.25
	sun.light_color = Color(1.0, 0.96, 0.9)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)
	city = CityBuilder.new()
	city.name = "City"
	add_child(city)
	city.build(CityBuilder.load_config())


func _ready() -> void:
	director = BotDirector.new()
	add_child(director)
	director.load_brains()
	director.setup(city)
	if World.data.has("bots"):
		director.from_dict(World.data.bots)
	director.spawn_in(self)
	if "--kw-probe" in OS.get_cmdline_user_args():
		_probe_t = 0.0
	_hud = CanvasLayer.new()
	_hud.layer = 5
	_clock_label = Label.new()
	_clock_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_clock_label.offset_left = -190
	_clock_label.offset_top = 10
	_clock_label.offset_right = -14
	_clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_clock_label.modulate = Color(1, 1, 1, 0.6)
	_clock_label.add_theme_font_size_override("font_size", 14)
	_hud.add_child(_clock_label)
	add_child(_hud)
	talk = BotTalk.new()
	add_child(talk)
	apartment = ApartmentInterior.new()
	apartment.name = "Apartment"
	apartment.position = APT_POS
	add_child(apartment)
	portals = DoorPortals.new()
	portals.name = "DoorPortals"
	add_child(portals)
	portals.setup(city, apartment)
	_pick_player_home()
	talk.closed.connect(func() -> void:
		var m = get_parent()
		if m != null and m.get("player") != null:
			m.player.enabled = true
			m._capture(true))


var _probe_t := -1.0
var _probe0 := {}


func _probe_pos() -> Dictionary:
	var d := {}
	for b in director.bots:
		d[b.name] = [b.global_position - ORIGIN, b.visible]
	return d


func _probe_tick(dt: float) -> void:
	if _probe_t < 0.0:
		return
	if _probe0.is_empty():
		_probe0 = _probe_pos()
	_probe_t += dt
	if _probe_t >= 20.0:
		var now := _probe_pos()
		var moved := 0
		var vis := 0
		for k in now:
			if now[k][1]:
				vis += 1
			if (now[k][0] as Vector3).distance_to(_probe0[k][0]) > 0.5:
				moved += 1
		print("PROBE moved=%d/%d visible=%d tree_paused=%s clock=%s" % [moved, now.size(), vis, str(get_tree().paused), director.clock.text()])
		get_tree().quit()


func _main_player() -> KWPlayer:
	var m = get_parent()
	return m.get("player") if m != null else null


func _active() -> bool:
	var m = get_parent()
	return m != null and m.get("mind") != null and m.mind.state == MindLink.S.REALITY and m.title == null


## Bot le plus proche devant le joueur (< 3 m), ou null.
func aimed_bot(max_dist := 3.0) -> Bot:
	var pl := _main_player()
	if pl == null or director == null:
		return null
	var fwd := -pl.global_transform.basis.z
	fwd.y = 0.0
	var best: Bot = null
	var bd := max_dist
	for b in director.bots:
		if not is_instance_valid(b):
			continue
		var to: Vector3 = b.global_position - pl.global_position
		to.y = 0.0
		var d := to.length()
		if d < bd and (d < 1.0 or fwd.normalized().dot(to / d) > 0.5):
			bd = d
			best = b
	return best


## Résidence la plus proche de la place, sans habitant : « ton » appartement.
func _pick_player_home() -> void:
	var used := {}
	for br in director.brains:
		if not br.home.is_empty():
			used[int(br.home["building"])] = true
	var best := 1e9
	var c: Vector3 = city.plaza.get_center()
	for b in city.buildings:
		if b["role"] != "residence":
			continue
		var d: float = (b["pos"] as Vector3).distance_to(c) + (1000.0 if used.has(int(b["idx"])) else 0.0)
		if d < best:
			best = d
			player_home = int(b["idx"])


## Occupant de la porte d'un bâtiment : {who, color, present} (le joueur si c'est « sa » porte).
func occupant_of(bi: int) -> Dictionary:
	for br in director.brains:
		if not br.home.is_empty() and int(br.home["building"]) == bi:
			return {"who": br.bot_name, "apartment_id": str(br.home.get("apartment_id", "")), "color": br.color, "present": br.kind == "home" and br.path.is_empty()}
	if bi == player_home:
		return {"who": "toi", "apartment_id": str(city.buildings[bi]["plan"]["apartment_ids"][0]), "color": Color(0.5, 0.7, 0.9), "present": false}
	return {}


## Porte résidentielle (avec habitant) à moins de 2,6 m du joueur : ouvre le portail.
func occupant_of_apt(bi: int, aid: String) -> Dictionary:
	for br in director.brains:
		if not br.home.is_empty() and int(br.home["building"]) == bi and str(br.home.get("apartment_id", "")) == aid:
			return {"who": br.bot_name, "color": br.color, "present": br.kind == "home" and br.path.is_empty()}
	if bi == player_home and aid == str(city.buildings[bi]["plan"]["apartment_ids"][0]):
		return {"who": "toi", "color": Color(0.5, 0.7, 0.9), "present": false}
	return {"who": "", "color": Color(0.85, 0.82, 0.76), "present": false}


## Entrée d'immeuble : ouverte de 7 h à 22 h, ensuite digicode (résidents seulement ; le joueur réside dans le sien).
func street_open(bi: int) -> bool:
	var h: float = director.clock.hour()
	return (h >= 7.0 and h < 22.0) or bi == player_home


func toast(msg: String) -> void:
	var m := get_tree().current_scene
	if m != null and "hud" in m and m.hud != null:
		m.hud.toast(msg)


func try_door() -> bool:
	var pl := _main_player()
	if pl == null or portals == null:
		return false
	if portals.is_inside(pl):
		if portals.active and portals.interact_inside(pl):
			return true
		var mm := get_tree().current_scene
		if mm != null and "hud" in mm:
			mm.hud.toast("Approchez-vous d'une porte (appartement ou rue) puis E.")
		return false
	for b in city.buildings:
		if b["role"] != "residence":
			continue
		var dx: Transform3D = portals.door_xf_of(b)
		var to: Vector3 = pl.global_position - dx.origin
		to.y = 0.0
		if to.length() < 3.2 and to.dot(dx.basis.z) > -0.5:
			var bi := int(b["idx"])
			if portals.active and portals.building == bi and portals.street_door(bi).is_open:
				portals.street_door(bi).close_in(0.01) # E sur une porte ouverte : on la referme
				return true
			if not street_open(bi):
				toast("Digicode — l'immeuble est fermé la nuit (résidents seulement).")
				return true
			var oc := occupant_of(int(b["idx"]))
			if oc.is_empty(): # immeuble sans habitant connu : on entre quand même
				portals.open_for(int(b["idx"]), "", Color(0.85, 0.82, 0.76), false, "")
			else:
				portals.open_for(int(b["idx"]), str(oc["who"]), oc["color"], bool(oc["present"]), str(oc.get("apartment_id", "")))
			return true
	var m := get_tree().current_scene
	if m != null and "hud" in m:
		m.hud.toast("Approchez-vous de la porte d'un immeuble (numéro affiché) puis E.")
	return false


func try_talk() -> bool:
	if talk == null or talk.is_open():
		return false
	var b := aimed_bot()
	if b == null:
		return try_door()
	var pl := _main_player()
	pl.enabled = false
	talk.open(b)
	return true


var _door_scan := 0.0


func _process(_dt: float) -> void:
	_probe_tick(_dt)
	var pl := _main_player()
	if pl == null or director == null:
		return
	director.set_listener(pl.global_position)
	_door_scan -= _dt
	if _door_scan <= 0.0 and portals != null and city != null:
		_door_scan = 0.5 # vrais battants créés à l'avance pour les portes proches (< 18 m)
		for b in city.buildings:
			if b["role"] == "residence" and b.has("plan"):
				var dxf: Transform3D = portals.door_xf_of(b)
				if dxf.origin.distance_to(pl.global_position) < 18.0:
					portals.street_door(int(b["idx"]))
	if portals != null and not portals.active and portals.is_inside(pl):
		pl.teleport(ORIGIN + Vector3(0, 0.05, 3), 0.0) # sauvegarde reprise dans l'appartement : retour place
	_hud.visible = _active()
	_clock_label.text = director.clock.text()
	talk.show_hint(aimed_bot() if _active() else null)
	_save_in -= _dt
	if _save_in <= 0.0:
		_save_in = 10.0
		save_bots()


func save_bots() -> void:
	if director != null and not director.brains.is_empty():
		World.data["bots"] = director.to_dict()


func _exit_tree() -> void:
	save_bots()


## Règle l'environnement partagé : ciel doux (réalité) ou valeurs du palais (copie d'origine).
func apply_env(env: Environment, reality: bool, palace_env: Environment) -> void:
	sun.visible = reality
	if not reality:
		for p in ENV_PROPS:
			env.set(p, palace_env.get(p))
		return
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.28, 0.5, 0.86)
	psm.sky_horizon_color = Color(0.72, 0.82, 0.92)
	psm.ground_horizon_color = Color(0.7, 0.72, 0.7)
	psm.ground_bottom_color = Color(0.55, 0.57, 0.55)
	sky.sky_material = psm
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.ssao_enabled = false
	env.ssil_enabled = false
	env.fog_enabled = true
	env.fog_light_color = Color(0.74, 0.79, 0.84)
	env.fog_density = 0.0012
