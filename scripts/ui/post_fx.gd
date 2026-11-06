class_name PostFX
extends CanvasLayer
## Filtre « cinéma » plein écran (sous l'interface) : léger effet peinture (Kuwahara
## à petit rayon, adoucit les formes simples), étalonnage chaud, vignettage, grain fin.
## + réglages moteur : tonemapping AgX, FXAA, flou de profondeur lointain.
## Réglage « post_fx » (true par défaut). Coût GPU modéré (un seul passage).

const CODE := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float paint = 1.0;      // force de l'effet peinture (0 = off)
uniform float vignette = 0.32;
uniform float grain = 0.035;
uniform vec3 lift = vec3(0.012, 0.008, 0.0);   // ombres légèrement chaudes
uniform vec3 gain = vec3(1.02, 1.0, 0.97);
uniform float saturation = 1.08;

vec3 kuwahara(vec2 uv, vec2 px) {
	// 4 quadrants 3x3 : on garde la moyenne du quadrant le moins contrasté.
	vec3 m[4]; float s[4];
	for (int k = 0; k < 4; k++) {
		vec2 o = vec2(float(k % 2) * 2.0 - 2.0, float(k / 2) * 2.0 - 2.0);
		vec3 sum = vec3(0.0); vec3 sq = vec3(0.0);
		for (int j = 0; j < 3; j++) for (int i = 0; i < 3; i++) {
			vec3 c = texture(screen_tex, uv + (o + vec2(float(i), float(j))) * px).rgb;
			sum += c; sq += c * c;
		}
		m[k] = sum / 9.0;
		vec3 v = sq / 9.0 - m[k] * m[k];
		s[k] = v.r + v.g + v.b;
	}
	vec3 best = m[0]; float bs = s[0];
	for (int k = 1; k < 4; k++) { if (s[k] < bs) { bs = s[k]; best = m[k]; } }
	return best;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 base = texture(screen_tex, uv).rgb;
	vec3 col = base;
	if (paint > 0.0) {
		col = mix(base, kuwahara(uv, SCREEN_PIXEL_SIZE), paint * 0.75);
	}
	col = col * gain + lift;
	float l = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(l), col, saturation);
	vec2 c = uv - 0.5;
	col *= 1.0 - vignette * smoothstep(0.25, 0.85, dot(c, c) * 2.2);
	float n = fract(sin(dot(uv * vec2(1920.0, 1080.0) + TIME * 37.0, vec2(12.9898, 78.233))) * 43758.5453);
	col += (n - 0.5) * grain;
	COLOR = vec4(col, 1.0);
}
"""

var rect: ColorRect
var mat: ShaderMaterial


func _init() -> void:
	layer = 0 # sous l'interface : seule la 3D est filtrée
	mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = CODE
	mat.shader = sh
	rect = ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.material = mat
	add_child(rect)


func _ready() -> void:
	apply()


static func enabled() -> bool:
	var v = KWSettings.get_value("post_fx")
	return v == null or bool(v)


## Applique filtre + réglages moteur selon le réglage.
func apply() -> void:
	var on := enabled()
	rect.visible = on
	var vp := get_viewport()
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if on else Viewport.SCREEN_SPACE_AA_DISABLED
	var m := get_tree().current_scene
	if m == null or not ("env" in m) or m.env == null:
		return
	var env: Environment = m.env
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.adjustment_enabled = on
	env.adjustment_contrast = 1.12
	env.adjustment_saturation = 1.18
	env.ssao_enabled = true
	env.glow_enabled = true
	# Flou de profondeur lointain : adoucit les bâtiments éloignés.
	if "player" in m and m.player != null:
		var ca := CameraAttributesPractical.new()
		ca.dof_blur_far_enabled = on
		ca.dof_blur_far_distance = 55.0
		ca.dof_blur_far_transition = 70.0
		ca.dof_blur_amount = 0.06
		m.player.cam.attributes = ca
