shader_type spatial;
render_mode cull_disabled;
uniform float ceiling_height = 10000.0;
uniform vec4 map_color : source_color = vec4(0.22, 0.24, 0.27, 1.0);
varying float world_height;
void vertex() {
	world_height = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}
void fragment() {
	if (world_height > ceiling_height) { discard; }
	ALBEDO = map_color.rgb;
	ROUGHNESS = 1.0;
}
