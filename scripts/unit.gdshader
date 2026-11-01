// Shader dei soldati: animazione (unit_anim.gdshaderinc) + colore della squadra.
shader_type spatial;
render_mode cull_back;

#include "res://scripts/unit_anim.gdshaderinc"

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap;
uniform sampler2D albedo_texture_pixel : source_color, filter_nearest;
uniform bool use_texture = false;
uniform bool pixel_texture = false;
uniform float team_strength = 1.0;

varying vec3 team_col;

void vertex() {
	unit_animate(VERTEX, NORMAL, INSTANCE_CUSTOM, UV2);
	team_col = COLOR.rgb;
}

void fragment() {
	vec3 base = vec3(1.0);
	if (use_texture) {
		base = pixel_texture ? texture(albedo_texture_pixel, UV).rgb : texture(albedo_texture, UV).rgb;
	}
	ALBEDO = base * mix(vec3(1.0), team_col, team_strength);
	ROUGHNESS = 0.85;
}
