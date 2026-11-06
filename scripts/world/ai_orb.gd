class_name AIOrb
extends Node3D
## Sphère de conscience : liquide, fluide, lumineuse. C'est l'IA de la pièce.
## Respire au repos, s'agite quand elle réfléchit, ondule quand elle parle.
## Écoute les signaux d'Assistant (busy_changed / reply_chunk) s'ils existent.

const SHADER_CODE := """
shader_type spatial;
render_mode blend_mix, cull_back, specular_schlick_ggx;
uniform vec4 core_color : source_color = vec4(0.35, 0.75, 1.0, 1.0);
uniform vec4 rim_color : source_color = vec4(0.85, 0.55, 1.0, 1.0);
uniform float activity = 0.0;   // 0 repos, 1 réfléchit, 2 parle
uniform float pulse = 0.0;      // impulsions à chaque fragment de réponse
varying vec3 v_pos;
varying float v_disp;

vec3 hash3(vec3 p) {
	p = vec3(dot(p, vec3(127.1, 311.7, 74.7)), dot(p, vec3(269.5, 183.3, 246.1)), dot(p, vec3(113.5, 271.9, 124.6)));
	return -1.0 + 2.0 * fract(sin(p) * 43758.5453123);
}
float noise(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(dot(hash3(i), f), dot(hash3(i + vec3(1,0,0)), f - vec3(1,0,0)), u.x),
				   mix(dot(hash3(i + vec3(0,1,0)), f - vec3(0,1,0)), dot(hash3(i + vec3(1,1,0)), f - vec3(1,1,0)), u.x), u.y),
			   mix(mix(dot(hash3(i + vec3(0,0,1)), f - vec3(0,0,1)), dot(hash3(i + vec3(1,0,1)), f - vec3(1,0,1)), u.x),
				   mix(dot(hash3(i + vec3(0,1,1)), f - vec3(0,1,1)), dot(hash3(i + vec3(1,1,1)), f - vec3(1,1,1)), u.x), u.y), u.z);
}
float fbm(vec3 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 4; i++) { v += a * noise(p); p *= 2.03; a *= 0.5; }
	return v;
}
void vertex() {
	float t = TIME * (0.35 + 0.5 * activity);
	vec3 p = VERTEX * 2.2;
	float d = fbm(p + vec3(t, t * 0.7, -t * 0.5));
	d += 0.35 * sin(VERTEX.y * 9.0 - TIME * 3.0) * clamp(activity - 1.0, 0.0, 1.0);
	float amp = 0.08 + 0.05 * activity + 0.06 * pulse;
	v_disp = d;
	VERTEX += NORMAL * d * amp;
	v_pos = VERTEX;
}
void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	float swirl = fbm(v_pos * 3.0 + vec3(0.0, TIME * 0.4, TIME * 0.25));
	vec3 inner = mix(core_color.rgb, rim_color.rgb, smoothstep(-0.3, 0.4, swirl + v_disp));
	ALBEDO = inner * 0.25;
	METALLIC = 0.2;
	ROUGHNESS = 0.08;
	float glow = 0.9 + 0.5 * activity + 1.2 * pulse;
	EMISSION = inner * (0.55 + 0.45 * swirl) * glow + rim_color.rgb * fres * (1.4 + activity);
	ALPHA = clamp(0.78 + fres * 0.22, 0.0, 1.0);
}
"""

static var _shader: Shader
var radius := 0.55
var mat: ShaderMaterial
var light: OmniLight3D
var sphere: MeshInstance3D
var _activity := 0.0
var _target_activity := 0.0
var _pulse := 0.0
var _t := 0.0
var _float_y := 1.35


static func create(r := 0.55, core := Color(0.35, 0.75, 1.0), rim := Color(0.85, 0.55, 1.0)) -> AIOrb:
	var o := AIOrb.new()
	o.radius = r
	o._build(core, rim)
	return o


func _build(core: Color, rim: Color) -> void:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER_CODE
	mat = ShaderMaterial.new()
	mat.shader = _shader
	mat.set_shader_parameter("core_color", core)
	mat.set_shader_parameter("rim_color", rim)
	sphere = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 96
	sm.rings = 48
	sphere.mesh = sm
	sphere.material_override = mat
	sphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_float_y = 0.75 + radius * 1.1
	sphere.position.y = _float_y
	add_child(sphere)
	# Socle discret : anneau lumineux au sol.
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = radius * 0.9
	tm.outer_radius = radius * 1.0
	ring.mesh = tm
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(0.1, 0.1, 0.12)
	rm.emission_enabled = true
	rm.emission = rim
	rm.emission_energy_multiplier = 1.5
	ring.material_override = rm
	ring.position.y = 0.03
	add_child(ring)
	light = OmniLight3D.new()
	light.light_color = core.lerp(rim, 0.3)
	light.light_energy = 1.2
	light.omni_range = 6.0
	light.position.y = _float_y
	add_child(light)


func _ready() -> void:
	var a := get_node_or_null("/root/Assistant")
	if a == null:
		return
	if a.has_signal("busy_changed"):
		a.busy_changed.connect(func(x = null, y = null): _target_activity = 1.0 if (y if y is bool else x) == true else 0.0)
	if a.has_signal("reply_chunk"):
		a.reply_chunk.connect(func(_a = null, _b = null, _c = null): _target_activity = 2.0; _pulse = 1.0)
	if a.has_signal("reply_ready"):
		a.reply_ready.connect(func(_d, _r): _target_activity = 0.0; _pulse = 1.0)


func set_activity(v: float) -> void:
	_target_activity = v


func _process(delta: float) -> void:
	_t += delta
	_activity = lerpf(_activity, _target_activity, 1.0 - exp(-3.0 * delta))
	_pulse = maxf(0.0, _pulse - delta * 2.5)
	mat.set_shader_parameter("activity", _activity)
	mat.set_shader_parameter("pulse", _pulse)
	sphere.position.y = _float_y + sin(_t * 0.9) * 0.05
	light.light_energy = 1.0 + 0.4 * sin(_t * 1.3) + 0.6 * _activity + 1.5 * _pulse
