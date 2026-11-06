class_name RealityWorld
extends Node3D
## La « réalité » : pour l'instant un grand sol sobre, un ciel doux et un soleil.
## Placée très loin du palais mental (ORIGIN) pour ne jamais interférer avec lui.

const ORIGIN := Vector3(10000, 0, 0)
const ENV_PROPS := ["background_mode", "background_color", "ambient_light_source", "ambient_light_color",
	"ambient_light_energy", "ssao_enabled", "ssil_enabled", "fog_enabled"]

var sun: DirectionalLight3D

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
	bs.size = Vector3(800, 2, 800)
	cs.shape = bs
	cs.position.y = -1.0
	body.add_child(cs)
	add_child(body)
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(800, 800)
	mi.mesh = pm
	var sh := Shader.new()
	sh.code = FLOOR_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mi.material_override = mat
	add_child(mi)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -35, 0)
	sun.light_energy = 0.9
	sun.light_color = Color(1.0, 0.96, 0.9)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)


## Règle l'environnement partagé : ciel doux (réalité) ou valeurs du palais (copie d'origine).
func apply_env(env: Environment, reality: bool, palace_env: Environment) -> void:
	sun.visible = reality
	if not reality:
		for p in ENV_PROPS:
			env.set(p, palace_env.get(p))
		return
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.42, 0.58, 0.82)
	psm.sky_horizon_color = Color(0.78, 0.84, 0.9)
	psm.ground_horizon_color = Color(0.7, 0.72, 0.7)
	psm.ground_bottom_color = Color(0.55, 0.57, 0.55)
	sky.sky_material = psm
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.ssao_enabled = false
	env.ssil_enabled = false
	env.fog_enabled = true
	env.fog_light_color = Color(0.74, 0.79, 0.84)
	env.fog_density = 0.004
