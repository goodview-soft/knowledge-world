class_name TransitStage
extends CanvasLayer
## L'ENTRE-DEUX — trou de ver plein écran (un seul shader canvas_item).
## Le portail se contracte, on est aspiré dans un tunnel de lumière qui plie
## l'espace (twist, aberration chromatique, traînées radiales), la salle de
## destination s'ouvre au bout, puis un flash doux nous y dépose.
## ~2,3 s ; clic / Espace / E / Échap / Entrée pour passer.

signal finished

const DURATION := 2.3

const WORMHOLE := """
shader_type canvas_item;
uniform float prog = 0.0;
uniform float aspect = 1.78;
uniform vec3 src : source_color = vec3(0.8, 0.8, 0.8);
uniform vec3 dst : source_color = vec3(0.6, 0.5, 0.9);

float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n2(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y);
}
// Parcours accéléré dans le tunnel.
float travel(float p) { return 2.0 + 26.0 * p * p + 4.0 * p; }

vec3 tunnel(vec2 uv, float p, vec3 tint) {
	float r = length(uv);
	float rw = pow(r, 0.72);                 // distorsion gravitationnelle
	float z = 0.5 / (rw + 0.015);            // profondeur
	float v = z + travel(p);
	float a = atan(uv.y, uv.x) + z * 0.18 + p * 2.5; // torsion
	float s1 = n2(vec2(a * 5.0, v * 0.22));   // traînées étirées
	float s2 = n2(vec2(a * 11.0 + 7.0, v * 0.12));
	float streak = pow(s1 * 0.6 + s2 * 0.5, 3.0) * 2.4;
	float ring = pow(abs(sin(v * 1.2)), 24.0);
	float ribs = smoothstep(0.82, 1.0, sin(a * 6.0 + v * 0.35));
	float depthl = 1.0 / (1.0 + z * 0.045);
	vec3 c = tint * (0.12 + streak + ring * 1.1 + ribs * 0.5) * (0.35 + depthl * 1.4);
	c += mix(tint, vec3(1.0), 0.6) * exp(-r * r * 7.0) * (0.5 + 1.5 * p); // lumière au bout
	return c;
}

void fragment() {
	vec2 uv = (UV - 0.5) * vec2(aspect, 1.0) * 2.0;
	float p = prog;
	vec3 tint = mix(src, dst, smoothstep(0.25, 0.8, p));
	float r = length(uv);
	// Aberration chromatique croissante vers les bords.
	float ab = 0.012 + 0.03 * r;
	vec3 c;
	c.r = tunnel(uv * (1.0 - ab), p, tint).r;
	c.g = tunnel(uv, p, tint).g;
	c.b = tunnel(uv * (1.0 + ab), p, tint).b;
	// Ouverture : le portail (couleur source) se contracte en iris.
	float iris = smoothstep(0.0, 0.3, p);
	vec3 haze = mix(src, vec3(1.0), 0.55) * (1.0 - iris) * (1.2 + 0.4 * n2(uv * 4.0 + p * 6.0));
	c = mix(haze, c, smoothstep(iris * 3.2, iris * 3.2 - 0.5, r));
	// La salle de destination s'ouvre au bout du tunnel.
	float k = smoothstep(0.5, 0.92, p);
	float rc = mix(0.03, 2.0, k * k);
	float d = r / rc;
	if (k > 0.0) {
		vec2 q = uv / max(rc, 0.05);
		vec3 room = mix(dst * 0.35, mix(dst, vec3(1.0), 0.55), smoothstep(-0.9, 0.9, q.y + 0.1));
		room *= 0.7 + 0.5 * (1.0 - smoothstep(0.0, 1.0, abs(q.x)));
		room += dst * 0.6 * smoothstep(0.02, 0.0, abs(q.y + 0.35)); // ligne d'horizon
		float m = smoothstep(1.0, 0.82, d);
		float rim = exp(-pow((d - 0.95) * 9.0, 2.0)) * 2.2;
		c = mix(c, room, m) + mix(dst, vec3(1.0), 0.5) * rim * (1.0 - k * 0.5);
	}
	// Flash doux final + vignette de vitesse.
	float flash = smoothstep(0.84, 1.0, p);
	c *= 1.0 - 0.45 * smoothstep(0.7, 1.7, r) * (1.0 - flash);
	c = mix(c, mix(dst, vec3(1.0), 0.7), flash);
	// Grain léger, tone-map doux.
	c += (h(UV * 900.0 + p) - 0.5) * 0.02;
	c = c / (1.0 + c * 0.35);
	COLOR = vec4(c, 1.0);
}
"""

var _t := 0.0
var _playing := false
var _src := Color.WHITE
var _dst := Color.WHITE
var _rect: ColorRect
var _mat: ShaderMaterial
var _drone: AudioStreamPlayer


static func make(src: Color, dst: Color) -> TransitStage:
	var s := TransitStage.new()
	s._src = src
	s._dst = dst
	return s


func _ready() -> void:
	layer = 6
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = WORMHOLE
	_mat.shader = sh
	_mat.set_shader_parameter("src", Color.from_hsv(_src.h, minf(_src.s + 0.35, 1.0), 1.0))
	_mat.set_shader_parameter("dst", Color.from_hsv(_dst.h, minf(_dst.s + 0.3, 1.0), 1.0))
	_rect.material = _mat
	add_child(_rect)
	_drone = AudioStreamPlayer.new()
	_drone.stream = _make_drone()
	_drone.volume_db = -10.0
	add_child(_drone)
	visible = false


func play() -> void:
	_playing = true
	_t = 0.0
	visible = true
	_drone.play()
	_update()


func _input(event: InputEvent) -> void:
	if not _playing:
		return
	var skip: bool = (event is InputEventMouseButton and event.pressed) or \
		(event is InputEventKey and event.pressed and event.keycode in [KEY_SPACE, KEY_E, KEY_ESCAPE, KEY_ENTER])
	if skip and _t > 0.2:
		_t = maxf(_t, DURATION - 0.3)
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not _playing:
		return
	_t += delta
	_update()
	if _t >= DURATION:
		_playing = false
		finished.emit()


func _update() -> void:
	var sz := _rect.size
	_mat.set_shader_parameter("aspect", sz.x / maxf(sz.y, 1.0))
	_mat.set_shader_parameter("prog", clampf(_t / DURATION, 0.0, 1.0))


## Nappe grave : sinus désaccordés + souffle, enveloppe montante.
func _make_drone() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * DURATION)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	var lp := 0.0
	for i in n:
		var t := float(i) / rate
		var k := float(i) / n
		lp += (rng.randf_range(-1, 1) - lp) * (0.02 + 0.1 * k)
		var f := 55.0 + 90.0 * k * k # glissando montant
		var v := 0.35 * sin(TAU * f * t) + 0.25 * sin(TAU * 82.6 * t + sin(t * 0.7)) + lp * 0.8 * k
		var env := clampf(k * 5.0, 0.0, 1.0) * clampf((1.0 - k) * 6.0, 0.0, 1.0)
		data.encode_s16(i * 2, int(clampf(v * env * 0.6, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	return w
