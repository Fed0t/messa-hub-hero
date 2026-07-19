shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never;

// Apă pentru renderer-ul Forward+: estompare pe adâncime (margini line),
// spumă la mal, refracție și reflexie fresnel.

uniform vec3 shallow_color : source_color = vec3(0.30, 0.62, 0.62);
uniform vec3 deep_color : source_color = vec3(0.03, 0.17, 0.30);
uniform vec3 reflect_color : source_color = vec3(0.70, 0.85, 1.0);
uniform float depth_fade : hint_range(0.2, 10.0) = 2.5;
uniform float foam_dist : hint_range(0.0, 2.0) = 0.35;
uniform float wave_speed = 0.35;
uniform float wave_height = 0.05;
uniform float ripple_scale = 0.5;
uniform float refraction : hint_range(0.0, 0.15) = 0.03;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME * wave_speed;
	VERTEX.y += sin(world_pos.x * 0.35 + t) * cos(world_pos.z * 0.3 + t * 0.8) * wave_height;
}

void fragment() {
	float t = TIME * wave_speed;
	float nx = sin(world_pos.x * ripple_scale + t * 2.0) + sin(world_pos.z * ripple_scale * 0.7 - t * 1.3);
	float nz = cos(world_pos.z * ripple_scale + t * 1.6) + cos(world_pos.x * ripple_scale * 0.8 + t * 1.1);
	vec2 ripple = vec2(nx, nz) * 0.5;

	// normală animată (licărire) — apa e orizontală, perturbăm ușor în jurul verticalei
	vec3 world_n = normalize(vec3(nx * 0.12, 1.0, nz * 0.12));
	NORMAL = normalize((VIEW_MATRIX * vec4(world_n, 0.0)).xyz);

	// adâncimea apei = distanța până la fundul scenei minus până la suprafață
	float raw = texture(depth_tex, SCREEN_UV).x;
	vec4 view = INV_PROJECTION_MATRIX * vec4(vec3(SCREEN_UV * 2.0 - 1.0, raw), 1.0);
	view.xyz /= view.w;
	float scene_dist = -view.z;
	float surf_dist = -VERTEX.z;
	float water_depth = clamp(scene_dist - surf_dist, 0.0, 100.0);
	float dfac = clamp(water_depth / depth_fade, 0.0, 1.0);

	vec3 wcol = mix(shallow_color, deep_color, dfac);

	// refracție: sample fundul cu o mică distorsiune
	vec2 ruv = SCREEN_UV + ripple * refraction * 0.05;
	vec3 bg = texture(screen_tex, ruv).rgb;
	float opacity = clamp(dfac * 0.9 + 0.12, 0.0, 1.0);
	vec3 col = mix(bg, wcol, opacity);

	// reflexie fresnel (nuanță de cer la unghi razant)
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 4.0);
	col = mix(col, reflect_color, fres * 0.5);

	// spumă la mal
	float foam = 1.0 - smoothstep(0.0, foam_dist, water_depth);
	col = mix(col, vec3(0.95, 0.98, 1.0), foam * 0.6);

	ALBEDO = col;
	ROUGHNESS = 0.05;
	METALLIC = 0.0;
	SPECULAR = 0.8;
	ALPHA = 1.0;
}
