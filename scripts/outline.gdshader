// Outline "a guscio invertito" a spessore costante in pixel: il soldato viene ridisegnato
// spingendo i vertici lungo la normale nello spazio dello schermo, mostrando solo le facce
// posteriori in tinta unita. Usa la stessa animazione dei soldati, così il contorno li segue.
// I soldati caduti (custom data r = 0) vengono scartati.
shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled;

#include "res://scripts/unit_anim.gdshaderinc"

uniform vec4 outline_color : source_color = vec4(1.0, 0.1, 0.05, 1.0);
uniform float width_px = 2.5;

void vertex() {
	if (INSTANCE_CUSTOM.r < 0.5) {
		POSITION = vec4(0.0, 0.0, 2.0, 1.0);
	} else {
		vec3 v = VERTEX;
		vec3 nrm = NORMAL;
		unit_animate(v, nrm, INSTANCE_CUSTOM, UV2);
		vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(v, 1.0));
		vec3 n = mat3(MODELVIEW_MATRIX) * nrm;
		vec2 dir = (PROJECTION_MATRIX * vec4(n, 0.0)).xy;
		if (length(dir) > 0.0001) {
			clip.xy += normalize(dir) * width_px * 2.0 / VIEWPORT_SIZE * clip.w;
		}
		POSITION = clip;
	}
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
