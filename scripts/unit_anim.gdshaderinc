// Animazione dei soldati, condivisa dallo shader dei soldati e da quello del contorno.
//
// Dati per soldato (MultiMesh custom data, INSTANCE_CUSTOM):
//   r = 1 vivo, 0 caduto (il contorno nasconde i caduti)
//   g = stato: 0 fermo, 1 cammino, 2 corsa, 3 attacco, 4 tiro, 5 colpito, 6 morte
//   b = istante d'inizio dello stato (per le animazioni "una volta")
//   a = numero casuale 0..1 del soldato (sfasa i passi, sceglie da che parte cadere)
// Il tempo è la variabile globale unit_anim_time, che si ferma con la pausa.
// Parametri per stato (vedi UnitAnimation.packed):
//   p0 = (cicli/s, saltello, dondolio°, beccheggio°)
//   p1 = (inclinazione°, piegamento°, altezza perno, una volta)
//   p2 = (durata, mantieni inclinazione, primo fotogramma VAT, numero fotogrammi VAT)
//   p3 = (fotogrammi/s VAT, -, -, -)

global uniform float unit_anim_time;

uniform vec4 anim_p0[7];
uniform vec4 anim_p1[7];
uniform vec4 anim_p2[7];
uniform vec4 anim_p3[7];
uniform float model_scale = 1.0;
uniform float model_yaw = 0.0;
uniform vec3 model_offset = vec3(0.0);
uniform bool use_vat = false;
uniform bool vat_has_normals = false;
uniform int vat_rows = 1;
uniform sampler2D vat_positions : filter_nearest, repeat_disable;
uniform sampler2D vat_normals : filter_nearest, repeat_disable;

// rotazione nel piano (a, b) di un angolo t
vec2 rot2(vec2 v, float t) {
	float c = cos(t);
	float s = sin(t);
	return vec2(v.x * c - v.y * s, v.x * s + v.y * c);
}

// inclina in avanti (verso -Z) attorno all'asse X passante per l'altezza h
vec3 pitch_at(vec3 v, float t, float h) {
	vec2 yz = rot2(vec2(v.y - h, -v.z), t);   // (alto, avanti)
	return vec3(v.x, yz.x + h, -yz.y);
}

void unit_animate(inout vec3 v, inout vec3 n, vec4 custom, vec2 uv2) {
	int st = clamp(int(custom.g + 0.5), 0, 6);
	float seed = custom.a;
	vec4 p0 = anim_p0[st];
	vec4 p1 = anim_p1[st];
	vec4 p2 = anim_p2[st];
	vec4 p3 = anim_p3[st];
	bool once = p1.w > 0.5;
	float el = max(unit_anim_time - custom.b, 0.0);
	float u = once ? clamp(el / max(p2.x, 0.01), 0.0, 1.0) : 0.0;
	float ph = unit_anim_time + seed * 13.0;

	// 1. animazione cotta: posizione e normale prese dalla texture
	if (use_vat && p2.w > 0.5) {
		int count = int(p2.w + 0.5);
		int frame = once ? int(u * float(count - 1) + 0.5) : int(mod(floor(ph * p3.x), float(count)));
		ivec2 px = ivec2(int(uv2.x), (int(p2.z + 0.5) + frame) * vat_rows + int(uv2.y));
		v = texelFetch(vat_positions, px, 0).xyz;
		if (vat_has_normals) {
			n = normalize(texelFetch(vat_normals, px, 0).xyz);
		}
	}

	// 2. scala, rotazione e spostamento del modello
	v *= model_scale;
	v.xz = rot2(v.xz, -model_yaw);
	n.xz = rot2(n.xz, -model_yaw);
	v += model_offset;

	// 3. movimento procedurale
	float wave = sin(ph * p0.x * 6.2831853);
	float bump = once ? sin(u * 3.1415927) : 1.0;
	// piegamento della parte alta (colpo d'arma, braccio della catapulta)
	float bend = radians(p1.y) * (once ? sin(u * 3.1415927) : wave);
	if (abs(bend) > 0.0001) {
		float w = smoothstep(p1.z - 0.1, p1.z + 0.5, v.y);
		v = pitch_at(v, bend * w, p1.z);
		n = pitch_at(n, bend * w, 0.0);
	}
	// inclinazione di tutto il corpo; nella morte si cade avanti o indietro a caso
	float lean = radians(p1.x);
	if (once) {
		lean *= p2.y > 0.5 ? smoothstep(0.0, 1.0, u) : bump;
		if (st == 6 && seed > 0.5) {
			lean = -lean;
		}
	}
	lean += radians(p0.w) * wave;
	if (abs(lean) > 0.0001) {
		v = pitch_at(v, lean, 0.0);
		n = pitch_at(n, lean, 0.0);
	}
	// dondolio laterale
	float sway = radians(p0.z) * sin(ph * p0.x * 3.1415927);
	if (abs(sway) > 0.0001) {
		v.xy = rot2(v.xy, sway);
		n.xy = rot2(n.xy, sway);
	}
	// saltello a ogni passo
	if (p0.y > 0.0) {
		v.y += p0.y * (once ? bump : abs(sin(ph * p0.x * 3.1415927)));
	}
}
